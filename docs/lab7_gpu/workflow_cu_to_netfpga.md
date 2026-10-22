# Workflow Guide: CUDA Kernel → NetFPGA Hardware Test

Complete pipeline from writing a CUDA kernel to running it on the GPU implemented on the NetFPGA V2 (Virtex-II Pro XC2VP50).

> **Refreshed 2026-05-17.** The 10-step workflow below is unchanged since the original Lab 7 deployment — the assembler / translator / synthesis flow is independent of the RTL refinements. Two notes for new users:
>
> 1. The ISA now includes **BCAST** (opcode `11010` / `0x1A`), added 2026-04-13. The assembler accepts it; see `toolchains/gpu/isa_defs.py`.
> 2. After running a kernel on hardware, the cycle count for that run can be read directly from the wrapper register `LAB8_GPU_CYCLE_COUNT = 0x30` (added 2026-04-13). No need to instrument the kernel itself or use the logic analyzer for cycle counting any more.

```
 kernel.cu ──nvcc──→ kernel.ptx ──parser──→ structured PTX
                                                │
                               translator ◄─────┘
                                    │
                                    ▼
                              kernel.asm ──assembler──→ kernel.hex
                                                            │
    ┌───────────────────────────────────────────────────────┘
    │
    ▼
 NetFPGA FPGA ◄──gpureg load──◄── IMEM/DMEM hex
    │
    └──→ kernel_done → read DMEM results
```

---

## Prerequisites

| Tool | Purpose | Location |
|------|---------|----------|
| CUDA Toolkit (nvcc) | Compile `.cu` → `.ptx` | System PATH |
| Python 3.x | Toolchain scripts | System PATH |
| Fedora 14 VM | NetFPGA synthesis (ISE 10.1) | VMware/VirtualBox |
| USC VPN + SSH | Access FPGA node | Cisco AnyConnect |

---

## Step 1 — Write CUDA Kernel

Create or edit `kernels/kernel.cu`. Each kernel processes 4 elements per thread using SIMD-friendly patterns.

```cuda
// kernels/kernel.cu
#include <cuda_bf16.h>

extern "C" __global__
void vec_add_i16(const int16_t* a, const int16_t* b,
                 int16_t* out, int n_elements) {
    int tid = (int)threadIdx.x;
    int base = tid * 4;
    if (base + 3 >= n_elements) return;
    out[base + 0] = a[base + 0] + b[base + 0];
    out[base + 1] = a[base + 1] + b[base + 1];
    out[base + 2] = a[base + 2] + b[base + 2];
    out[base + 3] = a[base + 3] + b[base + 3];
}
```

**Kernel writing rules:**
- `extern "C"` required (prevents name mangling)
- Process exactly 4 elements per thread (maps to 4-lane SIMD)
- Use `int16_t` for integer ops, `__nv_bfloat16` for BFloat16 ops
- FMA: use `__hfma(a, b, c)` intrinsic
- ReLU: use `max(x, 0)` pattern (translator detects it)

---

## Step 2 — Compile CUDA to PTX

```bash
cd toolchain/

# Option A: Full pipeline (requires nvcc + MSVC)
python compile.py ../kernels/kernel.cu -o ../programs/compiled/

# Option B: CUDA → PTX only
nvcc --machine 64 -ptx -arch=sm_80 ../kernels/kernel.cu -o ../kernels/kernel.ptx

# Option C: From existing PTX (skip nvcc)
python compile.py ../kernels/kernel.ptx -o ../programs/compiled/
```

**What nvcc produces:** Scalar PTX assembly where each kernel unrolls 4 element operations. Our translator collapses these back into single SIMD instructions.

**Verify PTX was generated:**
```bash
cat ../kernels/kernel.ptx | head -20
# Should see: .visible .entry vec_add_i16(...)
```

---

## Step 3 — Parse PTX

```bash
python ptx_parser.py ../kernels/kernel.ptx
```

**What it does:** Extracts kernel names, parameters, register declarations, and PTX instructions into structured `KernelInfo` objects.

**Output:** Prints parsed kernel summary — name, parameter types, instruction count.

---

## Step 4 — Translate PTX to Custom Assembly

```bash
python ptx_translator.py ../kernels/kernel.ptx ../programs/translated/
```

**What it does:**
1. Detects the core compute operation (e.g., `add.s16`, `fma.rn.bf16`)
2. Counts input/output arrays from parameter types
3. Collapses 4 scalar PTX operations → 1 SIMD instruction
4. Emits custom `.asm` with `LD → compute → ST → HALT`

**Key translations:**

| PTX Operation | Custom ASM | Data Type |
|---------------|-----------|-----------|
| `add.s16` | `ADD Rd, Rs1, Rs2` | S16 |
| `sub.s16` | `SUB Rd, Rs1, Rs2` | S16 |
| `max.s16` (ReLU pattern) | `RELU Rd, Rs1` | S16 |
| `mul.rn.bf16` | `MUL Rd, Rs1, Rs2` | BF16 |
| `fma.rn.bf16(a, b, -0.0)` | `MUL Rd, Rs1, Rs2` | BF16 |
| `fma.rn.bf16(a, b, c)` | `FMA Rd, Rs1, Rs2, Rs3` | BF16 |

**Verify translation:**
```bash
cat ../programs/translated/vec_add_i16.asm
# Should see:
#   LD   R1, 0(R0)
#   LD   R2, 1(R0)
#   ADD  R3, R1, R2
#   ST   R3, 2(R0)
#   HALT
```

---

## Step 5 — Assemble to Hex Machine Code

```bash
python assembler.py ../programs/translated/vec_add_i16.asm -o ../programs/compiled/vec_add_i16.hex
```

Or use `compile.py` which does steps 3-5 automatically:
```bash
python compile.py ../kernels/kernel.ptx -o ../programs/compiled/
```

**What it does:** 2-pass assembler:
- Pass 1: Collect labels, count PC addresses
- Pass 2: Encode each instruction to 32-bit hex using ISA field positions

**Instruction encoding format (32 bits):**
```
[31:27] opcode    — 5-bit operation code
[26:23] rd        — 4-bit destination register
[22:19] rs1       — 4-bit source register 1
[18:15] rs2       — 4-bit source register 2
[14:12] dtype     — 3-bit data type (S16=000, BF16=100)
[11:8]  rs3       — 4-bit source register 3 (FMA only)
[11:0]  offset    — 12-bit memory offset (LD/ST)
```

**Verify hex output:**
```bash
cat ../programs/compiled/vec_add_i16.hex
# 80800000    ← LD  R1, 0(R0)
# 81000001    ← LD  R2, 1(R0)
# 09890000    ← ADD R3, R1, R2
# 89800002    ← ST  R3, 2(R0)
# F8000000    ← HALT
```

---

## Step 6 — Generate Test Data

```bash
python data_generator.py ../programs/
```

**Produces `data_*.hex` files** — one per kernel, `$readmemh`-compatible:

| File | Contents |
|------|----------|
| `data_vec_add_i16.hex` | A={1,2,3,4}, B={5,6,7,8}, result=0 |
| `data_vec_sub_i16.hex` | A={10,20,30,40}, B={3,5,10,15}, result=0 |
| `data_bf16_mul.hex` | A={1.0,2.0,0.5,3.0}, B={2.0,3.0,0.5,0.25}, result=0 |
| `data_bf16_fma.hex` | A, B, C arrays, result=0 |
| `data_relu_i16.hex` | input={-3,5,-1,7}, result=0 |

**64-bit word layout (4 × 16-bit SIMD lanes):**
```
[63:48] lane 3  [47:32] lane 2  [31:16] lane 1  [15:0] lane 0
```

---

## Step 7 — Simulate with iverilog (Local Verification)

```bash
cd ..   # back to Lab7_gpu/

# Compile
/c/iverilog/bin/iverilog.exe -g2001 -I rtl/ -o sim_work/gpu_5kernel_tb \
  rtl/program_counter.v rtl/fetch_stage.v rtl/instruction_memory.v \
  rtl/data_memory.v rtl/instruction_decoder.v rtl/register_file.v \
  rtl/decode_stage.v rtl/pipeline_reg_idex.v rtl/int16_alu.v \
  rtl/bf16_alu.v rtl/simd_alu.v rtl/bf16_fma_unit.v \
  rtl/execute_stage.v rtl/pipeline_reg_exwb.v rtl/writeback_stage.v \
  rtl/hazard_unit.v rtl/core_top.v tb/gpu_5kernel_tb.v

# Run
/c/iverilog/bin/vvp.exe sim_work/gpu_5kernel_tb

# Expected output:
#   *** ALL 5 KERNEL TESTS PASSED ***

# View waveform (optional)
gtkwave gpu_5kernel_tb.vcd
```

**Key waveform signals:** `w_pc`, `w_stall`, `w_flush`, `w_ex_result`, `w_wb_data`, `dmem_wr_en`

---

## Step 8 — Synthesize Bitfile (Fedora 14 VM)

```bash
# On Fedora 14 VM
su                              # password: fighton
cd /root/netfpga/projects/lab7

# Copy RTL files from Windows → VM (via shared folder or scp)
# All 18 GPU RTL files go to lab7/src/
# gpu_params.vh goes to lab7/include/

# Synthesize
cd synth
export XIL_TIMING_ALLOW_IMPOSSIBLE=1    # Required (timing violations expected)
make 2>&1 | tee build_log.txt

# Output: synth/nf2_top_par.bit
```

**Synthesis resources (typical):**
| Resource | Used | Available | % |
|----------|------|-----------|---|
| Slices | ~15,500 | 23,616 | 65% |
| MULT18X18 | 12 | 232 | 5% |
| BRAM | 95 | 232 | 40% |

---

## Step 9 — Deploy to NetFPGA Hardware

```bash
# From your local machine (requires USC VPN)
# SSH to FPGA node with legacy crypto settings
ssh -oKexAlgorithms=+diffie-hellman-group1-sha1 \
    -oHostKeyAlgorithms=+ssh-rsa \
    -oPubkeyAcceptedAlgorithms=+ssh-rsa \
    -oCiphers=+aes256-cbc \
    user@nfX.usc.edu

# On FPGA node — download bitfile
nf_download /path/to/nf2_top_par.bit
```

---

## Step 10 — Run Kernels on Hardware

Use the `gpureg` Perl script on the FPGA node:

### Quick test (built-in programs):
```bash
cd /path/to/lab7/sw
./gpureg test_all
```

### Manual kernel execution:
```bash
# 1. Hold GPU in reset
./gpureg reset

# 2. Load instruction hex into IMEM
./gpureg load vec_add

# 3. Load test data into DMEM
#    Write 64-bit words: lower 32 bits first, then upper 32 bits
./gpureg dmem_wr 0 0001 00030004       # DMEM[0] = 0x0001000200030004
./gpureg dmem_wr 1 0005 00070008       # DMEM[1] = 0x0005000600070008

# 4. Release reset — GPU starts executing
./gpureg run

# 5. Poll until done
./gpureg status
# Should show: kernel_done = 1

# 6. Read results from DMEM
./gpureg dmem 0 4
# DMEM[2] should show: 0006 0008 000a 000c  (= {6, 8, 10, 12})
```

### Register addresses (for raw regread/regwrite):
```
GPU_CTRL    = 0x2004000   # bit[0]: 1=reset, 0=run
GPU_STATUS  = 0x2004004   # bit[0]: kernel_done
IMEM[N]     = 0x2005000 + N*4
DMEM[N] lo  = 0x2006000 + N*8      # write lower 32 bits first
DMEM[N] hi  = 0x2006000 + N*8 + 4  # write upper 32 bits (triggers 64-bit commit)
```

---

## All-In-One: New Kernel from Scratch

```bash
# 1. Write kernel
vim kernels/kernel.cu        # add new __global__ void my_kernel(...)

# 2. Compile entire pipeline
cd toolchain/
python compile.py ../kernels/kernel.cu -o ../programs/compiled/

# 3. Generate test data
python data_generator.py ../programs/

# 4. Simulate locally
cd ..
/c/iverilog/bin/iverilog.exe -g2001 -I rtl/ -o sim_work/gpu_5kernel_tb \
  rtl/*.v tb/gpu_5kernel_tb.v
/c/iverilog/bin/vvp.exe sim_work/gpu_5kernel_tb

# 5. If simulation passes → synthesize on Fedora VM
scp rtl/*.v fedora-vm:/root/netfpga/projects/lab7/src/
ssh fedora-vm 'cd /root/netfpga/projects/lab7/synth && make'

# 6. Deploy and test on FPGA
scp fedora-vm:/root/netfpga/projects/lab7/synth/nf2_top_par.bit .
# Upload to FPGA node, nf_download, gpureg test_all
```

---

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `nvcc not found` | CUDA toolkit not on PATH | Install CUDA or use `--skip-nvcc` with existing `.ptx` |
| `cl.exe not found` | MSVC not installed | Install VS Build Tools or use WSL for nvcc |
| PTX translation `unknown op` | Unsupported PTX instruction | Check `PTX_TO_ISA` mapping in `ptx_translator.py` |
| Simulation timeout | Hazard stall loop or bad encoding | Check instruction hex against ISA reference |
| `kernel_done` never asserts | Missing HALT instruction | Ensure `.hex` ends with `F8000000` |
| Synthesis timing violation | BF16 ALU critical path | Use `XIL_TIMING_ALLOW_IMPOSSIBLE=1` if still present after 5-stage pipeline fix |
| DMEM reads show 0 | Forgot lower-before-upper write order | Always write DMEM lo word first, then hi word |

---

## File Reference

```
Lab7_gpu/
├── kernels/
│   ├── kernel.cu              # CUDA source (5 kernels)
│   └── kernel.ptx             # nvcc PTX output
├── toolchain/
│   ├── compile.py             # Main pipeline: .cu/.ptx → .hex
│   ├── ptx_parser.py          # PTX → KernelInfo structs
│   ├── ptx_translator.py      # KernelInfo → custom .asm
│   ├── assembler.py           # .asm → .hex (2-pass)
│   ├── isa_defs.py            # Opcode/field definitions
│   ├── bf16_utils.py          # BFloat16 pack/unpack
│   └── data_generator.py      # Test data hex generator
├── programs/
│   ├── compiled/              # Final .asm + .hex per kernel
│   ├── translated/            # Intermediate PTX-translated .asm
│   └── data_*.hex             # DMEM test data files
├── rtl/                       # 19 synthesizable Verilog modules
├── tb/
│   └── gpu_5kernel_tb.v       # All 5 kernel verification testbench
└── docs/
    └── workflow_cu_to_netfpga.md   # This file
```
