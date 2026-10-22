# Lab 8 Implementation Plan — Network Processor Integration

> **Document status (refreshed 2026-05-17).** This is the *original* Lab 8 implementation plan, written before the build started (early 2026-02 / 2026-03). It describes what was *planned* — five batches of integration work — and remains accurate as a historical record of the intended scope.
>
> **What this plan does not cover:** the Lab 10 refinements that landed *after* Lab 8 was hardware-verified on 2026-03-20. Those are:
>
> - 2026-04-13 — BCAST cross-lane SIMD instruction + simd_alu pipeline restructure (commit `e14d012`)
> - 2026-04-13 — GPU cycle counter PCI register + readback mux refactor (commit `b4648bd`)
> - 2026-05-10 — ARM register-alias window for the Milestone 4 orchestrator (commit `942decf`)
>
> For the *current* state of the design, read the per-batch walkthroughs in this directory (`walkthrough_batch1..5_*.md`) and the GPU walkthroughs in `../lab7_gpu/`. `gpu_update_notes.md` and `walkthrough_batch5_synthesis_hw.md §7-§8` are the changelog-style index of post-Lab-8 changes.

## Architecture Overview

```
                        user_data_path.v
  8B data  ┌─────────────────────────────────────────────────────┐  8B data
  1B ctrl  │                                                     │  1B ctrl
 ─────────►│  ┌─────────────────────────────────────────────┐    │
           │  │          lab8_wrapper.v                      │   ├────────►
           │  │                                              │    │
           │  │  NF2.1 in ──► CONVERTIBLE FIFO ──► NF2.1 out│    │
           │  │               (256x72 BRAM)                  │    │
           │  │                ▲ Port A   Port B ▲           │    │
           │  │                │   (MUXed)       │  (MUXed)  │    │
           │  │           FIFO ctrl         ARM CPU MEM stage│    │
           │  │           (head/tail)       or GPU DMEM port │    │
           │  │                                              │    │
           │  │  ┌──────────┐          ┌───────────────┐     │    │
           │  │  │ ARM CPU  │          │ GPU (SIMD)    │     │    │
           │  │  │ IMEM+DMEM│          │ IMEM+DMEM     │     │    │
           │  │  └──────────┘          └───────────────┘     │    │
           │  │                                              │    │
           │  │  Register ring interface (PCI control only)  │    │
           │  └─────────────────────────────────────────────-┘    │
           └─────────────────────────────────────────────────────┘
```

**Data flow**: Packets flow through NETWORK (not PCI). PCI registers used only for control/status and initial program loading.

**Three FIFO BRAM users** (time-multiplexed via mode MUX):
1. FIFO logic — writes incoming packets (Port A), reads outgoing packets (Port B)
2. ARM CPU — reads/modifies packet data via MEM stage (Port B)
3. GPU — reads packet data for tensor operations (Port B, or both ports for 2x bandwidth)

---

## NF2.1 Packet Protocol (from Lab 6/7 analysis)

```
Word 0 (header):  ctrl = 0xFF, data = {src_port[15:0], word_length[15:0], byte_length[15:0], ...}
Word 1..N-1:      ctrl = 0x00, data = Ethernet frame bytes
Word N (last):    ctrl = 0x00 (or non-zero if partial last word indicating valid bytes)
```

- `word_length` in the module header = total words including header
- Packet boundary detection: read `word_length` from header word, count down
- `in_rdy` = 0 stalls upstream when FIFO is full (one packet buffered)

**Register ring chain**: `udp_reg_master → input_arbiter → output_port_lookup → lab8_wrapper → output_queues → udp_reg_master`

---

## Potential Future Optimizations (from lecture)

Deferred — get it working first (lecture point #6: incremental approach).

1. **Shared FIFO BRAM as unified memory** — Replace both CPU DMEM and GPU DMEM with the FIFO BRAM. CPU and GPU operate directly on packet data in-place. Saves BRAMs but requires width adaptation (72-bit FIFO vs 64-bit CPU/GPU) and address space partitioning.

2. **BRAM-based register file with double-clock** — Replace the CPU's distributed-RAM register file (64x64b, ~2200 LUTs) with a dual-port BRAM running at 2x CPU clock. At 2x frequency, each BRAM port gets 2 operations per CPU cycle: Port A does read1+write, Port B does read2+idle → 2 reads + 1 write per cycle. Requires a DCM to generate the 2x clock (2 DCMs still available on VP50). Saves ~2000 LUTs.

3. **Dual-port 2x64-bit GPU bandwidth** — In GPU mode, use BOTH BRAM ports to feed data to GPU simultaneously (addr N on Port A, addr N+1 on Port B → 128 bits/cycle). Critical for SIMD performance with 4-lane x 16-bit operations.

4. **Behavioral → structural conversion** — Convert key datapaths (FIFO BRAM, port MUXes) from behavioral to structural Verilog for more predictable ISE 10.1 synthesis on VP50.

5. **Application-specific simplification** — If targeting int16-only image processing (no BFloat16), remove BF16 ALU/FMA from GPU to save slices.

---

## Batched Implementation Plan

### Batch 0: Project Setup

**Goal**: Lab8 directory with all source files ready.

- [ ] Create `src/`, `tb/`, `include/`, `sw/`, `programs/` directories
- [ ] Copy ARM CPU sources from Lab6_synth/src/ (processor.v, IF_stage.v, inst_mem.v, ID.v, idex_reg.v, ifid_reg.v, EX.v, alu64.v, addsub64.v, logic64.v, adder8_comb.v, full_adder.v, exmem_reg.v, data_mem.v, memwb_reg.v, logic_analyzer.v)
- [ ] Copy GPU sources from Lab7_synth/src/ (gpu_top.v, core_top.v, program_counter.v, instruction_memory.v, fetch_stage.v, decode_stage.v, instruction_decoder.v, register_file.v, pipeline_reg_idex.v, execute_stage.v, simd_alu.v, int16_alu.v, bf16_alu.v, bf16_fma_unit.v, pipeline_reg_exwb.v, writeback_stage.v, hazard_unit.v, data_memory.v)
- [ ] Copy GPU params: Lab7_synth/include/gpu_params.vh
- [ ] Copy Lab6 testbench stubs: tb/xilinx_stubs.v
- [ ] Copy Lab6 toolchain: programs/ (sort.hex, expand_arm.py, dump2hex.py, etc.)
- [ ] Copy Lab6 Perl script: sw/processorreg (adapt later for Lab8)

---

### Batch 1: Convertible FIFO (standalone, no CPU/GPU)

**Goal**: A FIFO that captures one NF2.1 packet into BRAM, stalls input, then drains on command.

#### 1a. fifo_bram.v — 256 x 72-bit dual-port BRAM

```
module fifo_bram(
    input         clk,
    // Port A
    input  [7:0]  addr_a,
    input  [71:0] din_a,     // {ctrl[7:0], data[63:0]}
    input         we_a,
    output [71:0] dout_a,
    // Port B
    input  [7:0]  addr_b,
    input  [71:0] din_b,
    input         we_b,
    output [71:0] dout_b
);
```

- 72 bits = 8-bit ctrl + 64-bit data (matches NF2.1 word width)
- 256 entries × 72 bits = 2.25 KB (fits in ~2 BRAMs on VP50)
- True dual-port: both ports can read/write independently

#### 1b. convertible_fifo.v — FIFO controller + port MUX + BRAM

**Interface** (NF2.1 data path):
```
module convertible_fifo(
    input         clk,
    input         reset,
    // NF2.1 input (from output_port_lookup)
    input  [63:0] in_data,
    input  [7:0]  in_ctrl,
    input         in_wr,
    output        in_rdy,
    // NF2.1 output (to output_queues)
    output [63:0] out_data,
    output [7:0]  out_ctrl,
    output        out_wr,
    input         out_rdy,
    // Processor access port (directly from CPU MEM stage or GPU)
    input  [7:0]  proc_addr,
    input  [71:0] proc_din,
    input         proc_we,
    output [71:0] proc_dout,
    // Control/status
    input  [1:0]  mode,        // 0=FIFO, 1=CPU, 2=GPU
    input         drain_start, // CPU signals: done processing, drain packet
    output        pkt_ready,   // one packet buffered, ready for processing
    output        fifo_full,
    output        fifo_empty,
    output [7:0]  pkt_len,     // number of words in buffered packet
    // Head/tail access (CPU can read/write)
    input  [7:0]  head_wr_val,
    input         head_wr_en,
    input  [7:0]  tail_wr_val,
    input         tail_wr_en,
    output [7:0]  head_rd,
    output [7:0]  tail_rd
);
```

**State Machine**:
```
IDLE:
  - in_rdy = 1 (can accept data)
  - Wait for in_wr && in_ctrl != 0 (module header)
  - Capture word_length from in_data[31:16]
  - Write {in_ctrl, in_data} to BRAM[wr_ptr] via Port A
  - Increment wr_ptr, decrement word_counter
  → RECEIVING

RECEIVING:
  - in_rdy = 1
  - On in_wr: write to BRAM[wr_ptr], increment wr_ptr, decrement word_counter
  - When word_counter == 0: packet complete
  → PKT_BUFFERED

PKT_BUFFERED:
  - in_rdy = 0 (stall input — FIFO FULL)
  - Assert pkt_ready
  - Wait for drain_start (from CPU/mode controller)
  → DRAINING

DRAINING:
  - in_rdy = 0
  - Read BRAM[rd_ptr] via Port B, present on out_data/out_ctrl
  - On out_rdy: assert out_wr, increment rd_ptr
  - 1-cycle BRAM read latency: need registered output or prefetch
  - When rd_ptr == wr_ptr (all words drained)
  → IDLE (reset wr_ptr and rd_ptr to 0)
```

**Port A MUX** (FIFO write OR idle):
- FIFO mode: addr=wr_ptr, din={in_ctrl, in_data}, we=in_wr
- CPU/GPU mode: we=0 (idle) — or could allow proc access on Port A too

**Port B MUX** (FIFO read OR processor access):
- FIFO mode (draining): addr=rd_ptr, read only
- CPU mode: addr=proc_addr, din=proc_din, we=proc_we, dout=proc_dout
- GPU mode: addr=proc_addr, din=proc_din, we=proc_we, dout=proc_dout

**Output handshake** (DRAINING state):
- Need to handle 1-cycle BRAM read latency
- Approach: prefetch first word, then pipeline reads
  - Cycle 0: present addr=rd_ptr to Port B
  - Cycle 1: BRAM output valid, present on out_data/out_ctrl
  - Cycle 2: if out_rdy was asserted, advance rd_ptr; else hold

#### 1c. tb_convertible_fifo.v — Standalone testbench

Test cases:
1. Inject a 10-word packet (1 header + 9 data), verify BRAM contents
2. Verify pkt_ready asserts after last word
3. Verify in_rdy = 0 (FIFO FULL) after packet stored
4. Trigger drain, verify all 10 words output in order with correct ctrl/data
5. Verify FIFO returns to IDLE, in_rdy = 1
6. Test mode switching: switch to CPU mode, read/write BRAM, switch back to FIFO mode, drain

---

### Batch 2: NF2 Wrapper (FIFO + register interface, no CPU/GPU yet)

**Goal**: lab8_wrapper sits in the NF2.1 chain, captures packets via FIFO, provides PCI register access for testing. No CPU or GPU yet — just PCI-controlled FIFO.

#### 2a. lab8_wrapper.v

Follows the gpu_nf2_wrapper.v pattern:
- Register ring chain (block address decode, req/ack, pass-through)
- Instantiates convertible_fifo
- PCI registers to control FIFO mode, read/write BRAM, trigger drain

**Register map (initial — FIFO only)**:

| Offset | Name | Type | Description |
|--------|------|------|-------------|
| 0x00 | SYS_CTRL | SW | bit[0]=system_reset |
| 0x01 | SYS_STATUS | HW | status bits |
| 0x02 | FIFO_MODE | SW | 0=FIFO, 1=CPU_ACCESS, 2=GPU_ACCESS |
| 0x03 | FIFO_STATUS | HW | {pkt_ready, full, empty, pkt_len[7:0]} |
| 0x04 | FIFO_DRAIN | SW | bit[0]=drain_start strobe (auto-clear) |
| 0x05 | FIFO_HEAD | RW | read pointer |
| 0x06 | FIFO_TAIL | RW | write pointer |
| 0x07 | FIFO_BRAM_ADDR | SW | BRAM address for PCI access |
| 0x08 | FIFO_BRAM_WDATA_LO | SW | write data [31:0] |
| 0x09 | FIFO_BRAM_WDATA_HI | SW | write data [63:32] |
| 0x0A | FIFO_BRAM_WCTRL | SW | write ctrl [7:0] |
| 0x0B | FIFO_BRAM_CMD | SW | bit[0]=write, bit[1]=read (auto-clear) |
| 0x0C | FIFO_BRAM_RDATA_LO | HW | read data [31:0] |
| 0x0D | FIFO_BRAM_RDATA_HI | HW | read data [63:32] |
| 0x0E | FIFO_BRAM_RCTRL | HW | read ctrl [7:0] |

**Register interface pattern** (from Lab6 user_data_path.v):
- Latch incoming reg request signals
- Decode block address match
- WRITE: case statement on offset → update register
- READ: case statement on offset → load reg_rd_data
- Auto-clear strobes (FIFO_DRAIN[0], FIFO_BRAM_CMD[0:1])
- Pass through to next module in ring

#### 2b. user_data_path.v (Lab8 version)

Adapted from Lab6. Chain:
```
input_arbiter → output_port_lookup → lab8_wrapper → output_queues
```

The lab8_wrapper replaces the processor slot. Instantiation follows the same pattern as Lab6's processor wrapper.

#### 2c. include/lab8.xml + project.xml

Register block definition for the NF2 register generator.

#### 2d. tb_lab8_wrapper.v

Simulate NF2.1 environment:
- Generate mock in_data/in_ctrl/in_wr signals (packet injection)
- Verify packet captured in FIFO BRAM
- Use PCI register reads to inspect BRAM contents
- Trigger drain, verify packet output
- Test PCI-based BRAM read/write in CPU_ACCESS mode

#### 2e. sw/lab8reg (Perl script)

Adapt from Lab6's processorreg:
- Commands: fifo_status, fifo_read <addr>, fifo_write <addr> <data>, fifo_drain
- Can read/write FIFO BRAM contents for debugging

---

### Batch 3: ARM CPU Integration

**Goal**: CPU reads/modifies packet data via its MEM stage, then signals FIFO to drain.

#### 3a. CPU MEM stage → FIFO BRAM connection

The CPU accesses FIFO BRAM through its **MEM stage** (LDR/STR instructions), NOT through slow PCI registers. This is the "Use Network, NO PCI" principle.

**Address decoding in MEM stage**:
- CPU address space: 8-bit (256 words) for DMEM
- Split: addr[7] == 0 → CPU DMEM (128 words), addr[7] == 1 → FIFO BRAM (128 words)
- OR: use a control register to switch the entire DMEM port between local DMEM and FIFO BRAM
- **Simpler approach**: Mode-based switching. When mode=CPU_ACCESS, Port B of FIFO BRAM is driven by CPU MEM stage signals instead of FIFO drain logic.

**Wiring**:
```
CPU data_mem.v Port A (CPU datapath) → addr, dina, WMemEn, douta
                                        ↓ (directly, unchanged)
                                   CPU's own 256x64 DMEM

CPU MEM stage alu_result/write_data → Port B MUX of convertible_fifo
                                        ↓ (when mode=CPU_ACCESS)
                                   FIFO BRAM 256x72
```

Wait — the CPU's MEM stage already uses both BRAM ports (Port A for datapath, Port B for PCI debug). For FIFO access, we need to MUX the CPU's address/data signals to the FIFO BRAM's Port B.

**Revised approach**: In CPU_ACCESS mode, the lab8_wrapper routes the CPU's MEM stage outputs (address, write_data, WMemEn) to the FIFO BRAM Port B, and routes the FIFO BRAM Port B read output back to the CPU's load data input.

This requires modifying processor.v to expose MEM stage signals:
- Output: `mem_alu_result[7:0]` (address), `mem_write_data[63:0]`, `mem_WMemEn`
- Input: `fifo_rd_data[63:0]` (data loaded from FIFO BRAM)
- A mux in the WB stage: if the load came from FIFO range, use fifo_rd_data instead of DMEM output

**Alternative simpler approach**: Give the CPU a second "external memory port" that bypasses DMEM entirely. The CPU's ARM program uses a specific address range (e.g., LDR/STR with base register pointing to FIFO range) and an address decoder routes it to either DMEM or the external FIFO port.

#### 3b. Add CPU registers to lab8_wrapper

Extend register map:

| Offset | Name | Type | Description |
|--------|------|------|-------------|
| 0x10 | CPU_CTRL | SW | bit[0]=run, bit[1]=cpu_reset |
| 0x11 | CPU_STATUS | HW | {all_halted, cpsr, thread_id, run, ~rst} |
| 0x12 | CPU_IMEM_ADDR | SW | IMEM address |
| 0x13 | CPU_IMEM_WDATA | SW | IMEM write data |
| 0x14 | CPU_IMEM_CMD | SW | IMEM strobe (auto-clear) |
| 0x15 | CPU_DMEM_ADDR | SW | DMEM address |
| 0x16 | CPU_DMEM_WDATA_LO | SW | DMEM write data lo |
| 0x17 | CPU_DMEM_WDATA_HI | SW | DMEM write data hi |
| 0x18 | CPU_DMEM_CMD | SW | DMEM strobe (auto-clear) |
| 0x19 | CPU_IMEM_RDATA | HW | IMEM readback |
| 0x1A | CPU_DMEM_RDATA_LO | HW | DMEM readback lo |
| 0x1B | CPU_DMEM_RDATA_HI | HW | DMEM readback hi |
| 0x1C-0x1D | CPU_LA_ADDR/RDATA | SW/HW | Logic analyzer |

#### 3c. ARM test program

Simple packet modifier:
```arm
; Assume FIFO BRAM mapped at address range 0x80-0xFF (addr[7]=1)
; Packet header at FIFO BRAM[0] = addr 0x80
; First data word at FIFO BRAM[1] = addr 0x81
;
; Program: read word at offset 2 (first payload word after header),
;          add 42 to it, write it back

loop:
    ; Poll pkt_ready (need a memory-mapped status register or use a fixed address)
    LDR  r0, [r15, #status_addr]  ; load FIFO status
    TST  r0, #1                    ; pkt_ready bit
    BEQ  loop                      ; not ready, keep polling

    ; Read payload word from FIFO BRAM
    MOV  r1, #0x80                 ; FIFO BRAM base address (in CPU address space)
    LDR  r2, [r1, #8]             ; load FIFO word at offset 1 (first data word)
    ADD  r2, r2, #42              ; modify
    STR  r2, [r1, #8]             ; write back

    ; Signal done (write to control register to trigger drain)
    MOV  r3, #1
    STR  r3, [r15, #drain_addr]   ; trigger drain

    B    loop                      ; wait for next packet
```

#### 3d. tb_cpu_fifo.v

1. Load ARM program into CPU IMEM
2. Inject a packet into FIFO
3. Start CPU
4. Verify CPU reads packet data, modifies it, triggers drain
5. Verify modified packet appears on output

---

### Batch 4: GPU Integration

**Goal**: GPU performs tensor operations on packet payload data.

#### 4a. GPU register interface

Add to lab8_wrapper register map:

| Offset | Name | Type | Description |
|--------|------|------|-------------|
| 0x20 | GPU_CTRL | SW | bit[0]=gpu_reset |
| 0x21 | GPU_STATUS | HW | bit[0]=kernel_done |
| 0x22 | GPU_IMEM_ADDR | SW | GPU IMEM address |
| 0x23 | GPU_IMEM_WDATA | SW | GPU IMEM data |
| 0x24 | GPU_IMEM_CMD | SW | GPU IMEM strobe |
| 0x25 | GPU_DMEM_ADDR | SW | GPU DMEM address |
| 0x26 | GPU_DMEM_WDATA_LO | SW | GPU DMEM data lo |
| 0x27 | GPU_DMEM_WDATA_HI | SW | GPU DMEM data hi |
| 0x28 | GPU_DMEM_CMD | SW | GPU DMEM strobe |
| 0x29 | GPU_IMEM_RDATA | HW | GPU IMEM readback |
| 0x2A | GPU_DMEM_RDATA_LO | HW | GPU DMEM readback lo |
| 0x2B | GPU_DMEM_RDATA_HI | HW | GPU DMEM readback hi |

#### 4b. Data transfer: FIFO BRAM ↔ GPU DMEM

**Initial approach** (DMA-style via PCI or small FSM):
- CPU or Perl script copies packet data from FIFO BRAM → GPU DMEM via register writes
- GPU runs kernel
- Results copied back GPU DMEM → FIFO BRAM
- Slow but requires no GPU RTL changes

**Better approach** (hardware FSM):
- Small copy controller in lab8_wrapper
- Triggered by a register write (e.g., COPY_FIFO_TO_GPU with src_addr, dst_addr, count)
- Reads FIFO BRAM Port B, writes GPU DMEM Port B, one word per cycle
- ~256 cycles to copy full packet

#### 4c. GPU test program

vec_add on packet payload:
```
; GPU kernel: add constant vector to first 4 payload words
LD  R1, 0(R0)      ; load payload[0] from DMEM
LD  R2, 4(R0)      ; load constant vector
ADD R3, R1, R2     ; SIMD add (4 x int16)
ST  R3, 0(R0)      ; store result back
HALT
```

#### 4d. tb_gpu_fifo.v

1. Inject packet with known payload
2. Copy payload → GPU DMEM
3. Run GPU kernel (vec_add)
4. Copy result → FIFO BRAM
5. Drain modified packet
6. Verify output

---

### Batch 5: NetFPGA Synthesis & Hardware Test

**Goal**: Deploy on NetFPGA V2, demonstrate packet processing.

- [ ] Create Lab8 project on Fedora VM (copy reference_nic)
- [ ] Set up include/lab8.xml and project.xml
- [ ] Run `make` to generate registers.v and lib/
- [ ] Copy all RTL to VM project src/
- [ ] `export XIL_TIMING_ALLOW_IMPOSSIBLE=1 && cd synth && make`
- [ ] Flash bitstream: `nf_download synth/nf2_top_par.bit`
- [ ] Perl script: load CPU program, send test packet, verify output
- [ ] Demo: packet with integers → CPU adds constant → forwarded packet has modified values
- [ ] (If GPU integrated) Demo: packet → GPU tensor op → modified packet

---

## Module Hierarchy (Final)

```
user_data_path.v
├── input_arbiter (NF2 standard)
├── output_port_lookup (NF2 standard)
├── lab8_wrapper.v
│   ├── Register interface (block address decode, ring chain)
│   ├── convertible_fifo.v
│   │   └── fifo_bram.v (256x72 dual-port BRAM)
│   ├── processor.v (ARM CPU from Lab6_synth)
│   │   ├── IF_stage.v + inst_mem.v (IMEM 32bx512)
│   │   ├── ID.v (decode + 64-entry regfile)
│   │   ├── ifid_reg.v, idex_reg.v, exmem_reg.v
│   │   ├── EX.v + alu64.v + addsub64.v + logic64.v
│   │   ├── data_mem.v (CPU DMEM 64bx256, kept separate)
│   │   ├── memwb_reg.v (WB stage)
│   │   └── logic_analyzer.v (2048x64 trace buffer)
│   └── gpu_top.v (GPU from Lab7_synth)
│       ├── core_top.v (4-stage pipeline)
│       ├── instruction_memory.v (GPU IMEM 32bx1024)
│       ├── data_memory.v (GPU DMEM 64bx1024)
│       └── (all other GPU pipeline stages)
├── output_queues (NF2 standard)
└── udp_reg_master (NF2 standard)
```

---

## Resource Budget Estimate

| Component | Slices (est) | BRAMs | MULT18 |
|-----------|-------------|-------|--------|
| NF2 infrastructure | ~8,000 | ~60 | 0 |
| ARM CPU | ~5,000 | 2 (IMEM+DMEM) | 0 |
| GPU | ~7,000 | 4 (IMEM+DMEM) | 12 |
| Convertible FIFO | ~500 | 2 (256x72) | 0 |
| Logic Analyzer | ~200 | 8 | 0 |
| Lab8 wrapper + muxes | ~500 | 0 | 0 |
| **Total** | **~21,200 / 23,616 (90%)** | **~76 / 232** | **12 / 232** |

Tight on slices. Mitigation options (if needed):
- Reduce LA depth: 2048→1024 (saves ~100 slices + 4 BRAMs)
- BRAM-based regfile (saves ~2000 LUTs/slices)
- Remove BF16 from GPU if not needed (saves ~1000 slices)
- Use only Thread 0 in CPU, reduce regfile to 16 entries (saves ~1000 LUTs)

---

## Base Project

**reference_nic** on Fedora VM (confirmed by user).

---

## Key Design Decisions Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| CPU DMEM | Keep separate from FIFO BRAM | Avoid width mismatch, keep scratch space independent |
| GPU DMEM | Keep separate, DMA copy | No GPU RTL changes needed |
| CPU ↔ FIFO | MEM stage muxed (not PCI) | "Use Network, NO PCI" — bandwidth requirement |
| Packet end detection | word_length from module header | Reliable, doesn't depend on ctrl transitions |
| FIFO capacity | 1 packet (256x72) | Lab spec requirement |
| Register file | Distributed RAM (current) | Defer BRAM+double-clock to optimization phase |
