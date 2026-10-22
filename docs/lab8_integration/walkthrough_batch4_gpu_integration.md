# Batch 4 -- GPU Integration Walkthrough

> **Updated 2026-07-14:** Stale walkthrough content was reconciled with the current RTL implementation by Codex (GPT-5).

**Files covered:** `gpu_top.v` (instantiation) -> `lab8_wrapper.v` (GPU registers, DMA engine, port muxes) -> `lab8_reg_defines.vh` (GPU/DMA offsets)

This batch adds the Lab 7 GPU coprocessor into the Lab 8 wrapper and builds a DMA engine so packet data can flow between the FIFO BRAM and GPU DMEM. The original integration required no GPU-interface change: all bridge and DMA logic lives in `lab8_wrapper.v`. The current core later gained BCAST and other internal refinements while retaining the same `gpu_top.v` ports.

> **Document history.** Captured 2026-03-25 against the Lab 8 baseline. **Reconciled 2026-07-14** against the current checkpoint RTL in `src/lab8_wrapper.v` and `src/gpu/`.
>
> - **2026-04-13 (commit `b4648bd`):** new GPU cycle counter register (`LAB8_GPU_CYCLE_COUNT = 0x30`). Reads back the cycle count of the most recent kernel run, measured by hardware -- one PCI read replaces 100s of µs of host-side polling jitter. See §2 (register map) and `walkthrough_batch2_wrapper.md §2.13` for the counter state machine.
> - **2026-04-13 (commit `e14d012`):** the BCAST cross-lane SIMD instruction was added to the GPU core. The current checkpoint also contains the later `simd_alu.v` input register and scalar lane-0 INT16 refactor. **None of this changes the integration interface** -- `gpu_top.v` ports remain bit-identical and `lab8_wrapper.v`'s GPU instantiation (§4) is unchanged.
> - **2026-07-14 reconciliation:** current wrapper RTL includes ARM register aliases, CPU BRAM[0] ctrl preservation, and soft-reset auto-clear. DMA FIFO writes still prepend `8'h00`.

---

## 1. GPU Architecture Recap (from Lab 7)

The GPU is a 6-stage SIMD pipeline:

```
FETCH -> DECODE -> EX1 -> EX2 -> EX3 -> WRITEBACK
```

Key parameters (authoritative `include/gpu_params.vh`):
- 64-bit data width, 32-bit instructions
- 64-bit vector registers arranged as four 16-bit lane positions
- Four active BF16 ALU/FMA lanes; the current INT16 ALU computes lane 0 only and replicates that result to all four positions
- 16 registers (R0 hardwired to zero)
- IMEM: 1024 x 32-bit (10-bit address)
- DMEM: 1024 x 64-bit (10-bit address)
- Hazard resolution by stalling (no forwarding)
- Branch resolved in EX1 (2-cycle penalty: flush IF/ID + ID/EX)
- HALT gating: PC, IMEM read, DMEM write gated by registered `halted` signal

Both IMEM and DMEM are true dual-port BRAMs:
- **Port A**: core pipeline (fetch/LD/ST)
- **Port B**: external host interface (PCI program loading, DMA data transfer)

### 1.1 gpu_top.v Interface

```verilog
module gpu_top (
    input         clk,
    input         rst,
    input  [31:0] thread_id,     // Hardwired to 0 in Lab 8
    input  [31:0] block_id,      // Hardwired to 0
    input  [31:0] block_dim,     // Hardwired to 1
    output        kernel_done,   // Registered completion after HALT reaches EX3/WB
    // External IMEM (Port B): 10-bit addr, 32-bit data
    input  [9:0]  ext_imem_addr,
    input         ext_imem_wr_en,
    input  [31:0] ext_imem_wr_data,
    output [31:0] ext_imem_rd_data,
    // External DMEM (Port B): 10-bit addr, 64-bit data
    input  [9:0]  ext_dmem_addr,
    input         ext_dmem_wr_en,
    input  [63:0] ext_dmem_wr_data,
    output [63:0] ext_dmem_rd_data
);
```

**Single-invocation hardwiring:** The wrapper hardwires `thread_id=0`, `block_id=0`, and `block_dim=1`. The current repository contains no dispatcher in this path; these special-register inputs therefore describe one kernel invocation. Four BF16/FMA lanes execute in parallel, while the resource-reduced INT16 path uses lane 0 and replicates its result.

**Current SIMD timing/resource refinement:** `simd_alu.v` registers `alu_op`, `dtype`, `effective_a` (after the BCAST lane-select mux), and `operand_b` before the lane ALUs. Four two-cycle `bf16_alu` instances follow that input register. A single combinational `int16_alu` operates on lane 0, is delayed one cycle for alignment, and is replicated four times at the output. `execute_stage.v` therefore consumes the ALU's EX3-aligned result directly; it no longer adds a separate `simd_result_r` register.

**kernel_done:** The GPU's `core_top` sets a `halted_r` register when a HALT instruction reaches the WB stage. `kernel_done = halted_r` (registered only -- no combinational bypass). It goes HIGH one cycle after HALT completes writeback and stays HIGH until the next reset. The registered-only design avoids a combinational timing path that caused Bug #5 (see Batch 5 walkthrough).

### 1.2 Why Two Separate External Ports?

The GPU IMEM and DMEM are different widths (32-bit vs 64-bit) and serve different purposes:
- **IMEM Port B**: only PCI writes programs here (no DMA needed -- programs are small)
- **DMEM Port B**: muxed between PCI (debug read/write) and DMA (bulk data transfer)

This split means we need two sets of registers and two separate mux paths.

---

## 2. GPU Register Map (0x20--0x2B)

Added to `lab8_reg_defines.vh`:

```verilog
`define LAB8_GPU_CTRL           6'h20   // RW  bit[0]=gpu_reset (1=hold in reset)
`define LAB8_GPU_STATUS         6'h21   // RO  bit[0]=kernel_done, bit[1]=dma_busy
`define LAB8_GPU_IMEM_ADDR      6'h22   // RW  IMEM address [9:0]
`define LAB8_GPU_IMEM_WDATA     6'h23   // RW  IMEM write data [31:0]
`define LAB8_GPU_IMEM_CMD       6'h24   // RW  bit[0]=write strobe (auto-clear)
`define LAB8_GPU_IMEM_RDATA     6'h25   // RO  IMEM readback [31:0]
`define LAB8_GPU_DMEM_ADDR      6'h26   // RW  DMEM address [9:0]
`define LAB8_GPU_DMEM_WDATA_LO  6'h27   // RW  DMEM write data [31:0]
`define LAB8_GPU_DMEM_WDATA_HI  6'h28   // RW  DMEM write data [63:32]
`define LAB8_GPU_DMEM_CMD       6'h29   // RW  bit[0]=write strobe (auto-clear)
`define LAB8_GPU_DMEM_RDATA_LO  6'h2A   // RO  DMEM readback [31:0]
`define LAB8_GPU_DMEM_RDATA_HI  6'h2B   // RO  DMEM readback [63:32]
```

**Offset gap:** GPU registers start at 0x20, not 0x1B (the next slot after CPU registers at 0x1A). Offsets 0x1B--0x1F are padding (5 reserved registers in `lab8.xml`) so the GPU block aligns at a clean boundary. The NF2 register generator assigns offsets from XML declaration order, so these padding entries consume real register slots.

**GPU IMEM is 32-bit, not 64-bit:** Unlike FIFO BRAM and GPU DMEM, the GPU instruction word is only 32 bits. A single PCI register holds one full instruction -- no lo/hi split needed. This is why IMEM has one WDATA/RDATA register while DMEM has two (LO/HI).

**GPU DMEM uses the same indirect-access pattern as FIFO BRAM:**
1. Write address to `GPU_DMEM_ADDR`
2. For writes: write lo/hi data, then strobe `GPU_DMEM_CMD`
3. For reads: write address, then read `GPU_DMEM_RDATA_LO` and `GPU_DMEM_RDATA_HI`

---

## 3. DMA Register Map (0x2C--0x2F)

```verilog
`define LAB8_DMA_CTRL           6'h2C   // RW  bit[0]=start (auto-clear), bit[1]=dir
`define LAB8_DMA_FIFO_ADDR      6'h2D   // RW  FIFO BRAM start address [7:0]
`define LAB8_DMA_GPU_ADDR       6'h2E   // RW  GPU DMEM start address [9:0]
`define LAB8_DMA_LENGTH          6'h2F   // RW  word count [7:0]

// GPU performance counter (added 2026-04-13)
`define LAB8_GPU_CYCLE_COUNT    6'h30   // RO  cycles from gpu_reset-deassert to kernel_done
```

**DMA_CTRL fields:**
- bit[0] = start strobe (auto-clears after 1 cycle)
- bit[1] = direction: 0 = FIFO->GPU, 1 = GPU->FIFO

**GPU_CYCLE_COUNT (added 2026-04-13):** Hardware-measured cycle count from the moment `gpu_reset` deasserts until `gpu_kernel_done` first asserts. Reading this register one PCI access at the end of a kernel replaces ~100s of µs of host-side polling/timestamp jitter -- crucial for measuring the BCAST vs scalar IDS speedup (2402 → 732 cycles, 3.28×) directly from Python without instrumenting the kernel. State machine lives in the wrapper -- see `walkthrough_batch2_wrapper.md §2.13`.

**Usage pattern (FIFO->GPU copy of 7 words starting at BRAM[1] to GPU DMEM[0]):**
```
regwrite(DMA_FIFO_ADDR, 1)     -> source start = FIFO BRAM[1]
regwrite(DMA_GPU_ADDR,  0)     -> dest start   = GPU DMEM[0]
regwrite(DMA_LENGTH,    7)     -> copy 7 words
regwrite(DMA_CTRL,      0x1)   -> start, direction=0 (FIFO->GPU)
```

---

## 4. GPU Instantiation in lab8_wrapper.v

```verilog
   gpu_top u_gpu (
      .clk             (clk),
      .rst             (gpu_reset),           // reset | reg_gpu_ctrl[0]
      .thread_id       (32'd0),               // Single thread
      .block_id        (32'd0),
      .block_dim       (32'd1),
      .kernel_done     (gpu_kernel_done),
      .ext_imem_addr   (gpu_imem_addr),        // Always PCI-driven
      .ext_imem_wr_en  (gpu_imem_wr_en),
      .ext_imem_wr_data(gpu_imem_wr_data),
      .ext_imem_rd_data(gpu_imem_rd_data),
      .ext_dmem_addr   (gpu_dmem_addr),        // Muxed: PCI or DMA
      .ext_dmem_wr_en  (gpu_dmem_wr_en),
      .ext_dmem_wr_data(gpu_dmem_wr_data),
      .ext_dmem_rd_data(gpu_dmem_rd_data)
   );
```

### 4.1 GPU Reset

```verilog
   assign gpu_reset = reset | reg_gpu_ctrl[0];
```

**Default state at power-on:** `reg_gpu_ctrl` resets to `32'h1` (not `32'd0` like the other registers):

```verilog
         // GPU registers -- GPU starts in reset
         reg_gpu_ctrl        <= 32'h1;
```

This means the GPU is held in reset from power-on until software explicitly clears it with `regwrite(GPU_CTRL, 0)`. This prevents the GPU from executing random IMEM contents before a program is loaded. The CPU registers, by contrast, reset to 0 -- the CPU relies on the `start_stop` bit and the software "atomic start" protocol (Bug #1 workaround).

### 4.2 GPU IMEM PCI Path (Always PCI-Driven)

```verilog
   assign gpu_imem_addr    = reg_gpu_imem_addr[9:0];
   assign gpu_imem_wr_en   = reg_gpu_imem_cmd[0];
   assign gpu_imem_wr_data = reg_gpu_imem_wdata;
```

GPU IMEM Port B is **always** driven by PCI registers. There is no DMA path to IMEM because:
1. Current GPU programs range from tens to a few hundred instructions -- PCI loading remains an out-of-band setup operation
2. Programs are loaded once before execution, not during real-time packet processing
3. Adding an IMEM DMA path would require a second mux and more control logic

---

## 5. DMA Engine

The DMA engine copies 64-bit words between FIFO BRAM and GPU DMEM. It uses a 3-state FSM with a pipelined read that achieves 1 word per cycle after a 1-cycle setup.

### 5.1 DMA State Machine

```verilog
   localparam DMA_IDLE = 2'd0;
   localparam DMA_READ = 2'd1;
   localparam DMA_COPY = 2'd2;
```

```
DMA_IDLE:  waiting for start strobe
  |
  | dma_start (mode==2, length!=0, ctrl[0]=1)
  v
DMA_READ:  first read address presented, wait 1 cycle for BRAM latency
  |
  | (unconditional, 1 cycle)
  v
DMA_COPY:  read source, write dest, 1 word/cycle until done
  |
  | wr_ptr+1 == length
  v
DMA_IDLE
```

### 5.2 DMA Start Gating

```verilog
   assign dma_start = reg_dma_ctrl[0]
                    && (reg_fifo_mode_r[1:0] == 2'd2)
                    && (reg_dma_length[7:0] != 8'd0);
```

Three conditions must ALL be true:
1. **`reg_dma_ctrl[0]`** -- start strobe is active (auto-clears next cycle)
2. **`mode == 2`** -- GPU mode. DMA is not allowed in FIFO mode (0) or CPU mode (1) because it would conflict with whoever owns the FIFO BRAM proc port
3. **`length != 0`** -- zero-length DMA does nothing (prevents spurious FSM transitions)

### 5.3 DMA Registers (Latched on Start)

```verilog
            DMA_IDLE: begin
               if (dma_start) begin
                  dma_dir       <= reg_dma_ctrl[1];          // 0=FIFO->GPU, 1=GPU->FIFO
                  dma_fifo_base <= reg_dma_fifo_addr[7:0];   // FIFO BRAM start
                  dma_gpu_base  <= reg_dma_gpu_addr[9:0];    // GPU DMEM start
                  dma_len       <= reg_dma_length[7:0];      // word count
                  dma_rd_ptr    <= 8'd0;
                  dma_wr_ptr    <= 8'd0;
                  dma_state     <= DMA_READ;
               end
            end
```

The DMA latches all parameters (direction, addresses, length) on the start edge. This means software can safely modify the DMA registers while a transfer is in progress without corrupting it (not that you should -- just a nice safety property).

### 5.4 DMA Read Pipeline

```verilog
            DMA_READ: begin
               // First read address presented combinationally; wait 1 cycle
               dma_rd_ptr <= 8'd1;
               dma_state  <= DMA_COPY;
            end
```

**Why DMA_READ exists:** Both FIFO BRAM and GPU DMEM have 1-cycle read latency. On the cycle DMA_READ starts, the source address (base + 0) is presented combinationally to the BRAM. The data appears one cycle later. DMA_READ waits that one cycle, then DMA_COPY begins writing the data that just arrived.

After DMA_READ, `dma_rd_ptr=1` while `dma_wr_ptr=0`. The read pointer always leads the write pointer by 1 -- this is the read pipeline offset.

### 5.5 DMA Copy Loop

```verilog
            DMA_COPY: begin
               dma_wr_ptr <= dma_wr_ptr + 8'd1;
               dma_rd_ptr <= dma_rd_ptr + 8'd1;
               if (dma_wr_ptr + 8'd1 == dma_len)
                  dma_state <= DMA_IDLE;
            end
```

Every cycle in DMA_COPY:
1. Write the word read LAST cycle (rd_ptr was 1 ahead of wr_ptr)
2. Advance both pointers
3. When `wr_ptr + 1 == len`, all words are written -> done

**Nominal internal throughput:** after setup, the loop transfers 1 word/cycle = 64 bits/cycle at 125 MHz = 8 Gbit/s = 1 GB/s. Because the 8-bit length register rejects zero, the largest programmable transfer is 255 words, not 256. It occupies one `DMA_READ` cycle plus 255 `DMA_COPY` cycles (256 cycles, about 2.048 µs at 125 MHz) after the start transition.

### 5.6 DMA Timing Diagram

```
Cycle   State       rd_ptr  wr_ptr  Source reads     Dest writes
  0     DMA_READ      0->1    0     addr=base+0      (none)
  1     DMA_COPY      1->2    0->1  addr=base+1      data[0] written
  2     DMA_COPY      2->3    1->2  addr=base+2      data[1] written
  ...
  L     DMA_COPY      ...     L-1->L ...              data[L-1] written (last);
                                                      state becomes IDLE after this edge
  L+1   DMA_IDLE      --      --    --               (none)
```

The `rd_ptr` always leads by 1: while `data[k]` is being written to the destination, `data[k+1]` is being read from the source.

---

## 6. Port Muxes -- The Complete Picture

Batch 4 extends the wrapper's proc-bus source mux from 2-way (CPU/PCI) to 3-way (CPU/DMA/PCI) and adds a new mux for the GPU DMEM external port. Physical FIFO BRAM Port B has another mux inside `convertible_fifo.v`: mode 0 selects the drain pointer, while modes 1/2 select this proc bus.

### 6.1 FIFO BRAM Proc Port Mux (3-way)

```verilog
   wire cpu_drives_proc = (reg_fifo_mode_r[1:0] == 2'd1) && cpu_running;
   wire dma_drives_proc = (reg_fifo_mode_r[1:0] == 2'd2) && dma_active;
```

```verilog
   reg [7:0] arm_bram_wctrl;
   always @(*) begin
      if (cpu_ext_mem_addr[6:0] == 7'h00)
         arm_bram_wctrl = 8'hFF;
      else
         arm_bram_wctrl = 8'h00;
   end

   always @(*) begin
      fifo_mode        = reg_fifo_mode_r[1:0];
      fifo_drain_start = reg_fifo_drain[0];

      if (cpu_drives_proc) begin
         // CPU MEM stage drives FIFO BRAM
         fifo_proc_addr = cpu_ext_mem_addr;
         fifo_proc_din  = {arm_bram_wctrl, cpu_ext_mem_din};
         fifo_proc_we   = cpu_ext_mem_we;
      end else if (dma_drives_proc) begin
         if (!dma_dir) begin
            // FIFO->GPU: read from FIFO BRAM (source)
            fifo_proc_addr = dma_fifo_base + dma_rd_ptr;
            fifo_proc_din  = 72'd0;
            fifo_proc_we   = 1'b0;                    // Read only
         end else begin
            // GPU->FIFO: write to FIFO BRAM (destination)
            fifo_proc_addr = dma_fifo_base + dma_wr_ptr;
            fifo_proc_din  = {8'h00, gpu_dmem_rd_data};   // ctrl=0x00 (data words)
            fifo_proc_we   = (dma_state == DMA_COPY);
         end
      end else begin
         // PCI registers drive FIFO BRAM (default)
         fifo_proc_addr = reg_bram_addr[7:0];
         fifo_proc_din  = {reg_bram_wctrl[7:0], reg_bram_wd_hi, reg_bram_wd_lo};
         fifo_proc_we   = bram_pci_wr_strobe;
      end
   end
```

**Wrapper proc-bus priority:** CPU > DMA > PCI. In practice these never overlap because:
- CPU drives only when `mode==1` and running
- DMA drives only when `mode==2` and active
- PCI drives `proc_*` in all other cases (including `mode==2` when DMA is idle). In mode 0, however, the FIFO ignores `proc_*` and physical Port B remains owned by its drain logic.

**DMA direction determines who reads and who writes:**
- FIFO->GPU (`dma_dir=0`): FIFO BRAM is the source (read), GPU DMEM is the destination (write)
- GPU->FIFO (`dma_dir=1`): GPU DMEM is the source (read), FIFO BRAM is the destination (write)

**ctrl byte during CPU/DMA writes:** the CPU path writes `0xFF` at FIFO index 0 and `0x00` elsewhere, allowing firmware to rewrite the NF2.1 header. The DMA path always prepends `8'h00` because GPU DMEM stores only the 64-bit data half. For the host-driven packet-processing flow shown later, the original packet header remains in BRAM[0] while DMA updates payload words in BRAM[1..N].

### 6.2 GPU DMEM Ext Port Mux (2-way)

```verilog
   always @(*) begin
      if (dma_active) begin
         if (!dma_dir) begin
            // FIFO->GPU: write to GPU DMEM (destination)
            gpu_dmem_addr    = dma_gpu_base + {2'b0, dma_wr_ptr};
            gpu_dmem_wr_en   = (dma_state == DMA_COPY);
            gpu_dmem_wr_data = fifo_proc_dout[63:0];     // From FIFO BRAM read
         end else begin
            // GPU->FIFO: read from GPU DMEM (source)
            gpu_dmem_addr    = dma_gpu_base + {2'b0, dma_rd_ptr};
            gpu_dmem_wr_en   = 1'b0;                     // Read only
            gpu_dmem_wr_data = 64'd0;
         end
      end else begin
         // PCI registers drive GPU DMEM (default)
         gpu_dmem_addr    = reg_gpu_dmem_addr[9:0];
         gpu_dmem_wr_en   = gpu_dmem_pci_wr_strobe;
         gpu_dmem_wr_data = {reg_gpu_dmem_wd_hi, reg_gpu_dmem_wd_lo};
      end
   end
```

**Address width adaptation:** FIFO BRAM addresses are 8-bit (256 entries), GPU DMEM addresses are 10-bit (1024 entries), and the DMA offset pointers are 8-bit. The nonzero 8-bit length limits one transfer to 255 words. The GPU base is 10 bits and the zero-extended offset is added to it, so DMA can target a window starting anywhere in the 1024-word DMEM, not only its first 256 entries. There is no range check: FIFO and GPU sums wrap at their native 8- and 10-bit widths.

**Data path for FIFO->GPU:** `fifo_proc_dout[63:0]` feeds `gpu_dmem_wr_data`. Note that `fifo_proc_dout` is the FIFO BRAM's Port B output -- the same wire the CPU reads from. Since DMA exclusively owns the proc port when active, there is no conflict.

**Data path for GPU->FIFO:** `gpu_dmem_rd_data` feeds `fifo_proc_din[63:0]` (via the proc port mux). The GPU DMEM Port B outputs the read data, which flows through the DMA engine into the FIFO BRAM Port B write data.

### 6.3 Cross-Port Data Flow Diagram

```
FIFO->GPU transfer:
  FIFO BRAM Port B (read)                GPU DMEM Port B (write)
  addr = dma_fifo_base + rd_ptr          addr = dma_gpu_base + wr_ptr
  dout = fifo_proc_dout[63:0]  --------> wr_data = fifo_proc_dout[63:0]
                                          wr_en  = (state == DMA_COPY)

GPU->FIFO transfer:
  GPU DMEM Port B (read)                 FIFO BRAM Port B (write)
  addr = dma_gpu_base + rd_ptr           addr = dma_fifo_base + wr_ptr
  dout = gpu_dmem_rd_data  ----------->  din = {8'h00, gpu_dmem_rd_data}
                                          we  = (state == DMA_COPY)
```

---

## 7. GPU Status Register

```verilog
   wire [31:0] reg_gpu_status = {30'd0, dma_active, gpu_kernel_done};
```

- bit[0] = `kernel_done` -- registered GPU completion after HALT reaches EX3/WB
- bit[1] = `dma_active` -- DMA engine is in DMA_READ or DMA_COPY state

Software polls `GPU_STATUS` to check:
1. Is a DMA transfer done? (`bit[1] == 0`)
2. Has the GPU kernel finished? (`bit[0] == 1`)

---

## 8. Auto-Clear Strobes (Batch 4 Additions, current RTL reconciled 2026-07-14)

```verilog
          if (reg_gpu_imem_cmd[0])  reg_gpu_imem_cmd[0]  <= 1'b0;
          if (reg_gpu_dmem_cmd[0])  reg_gpu_dmem_cmd[0]  <= 1'b0;
          if (reg_dma_ctrl[0])      reg_dma_ctrl[0]      <= 1'b0;
          if (reg_ctrl[0])          reg_ctrl[0]          <= 1'b0;
```

Three strobes were added by Batch 4 (alongside `fifo_drain`, `bram_cmd`, `cpu_imem_cmd`, and `cpu_dmem_cmd`). The current wrapper also auto-clears `reg_ctrl[0]`, for **8** auto-cleared command bits total.

The ARM alias window can write `DMA_CTRL`, `GPU_CTRL`, FIFO mode/soft reset/drain, and DMA parameters, and can read GPU/FIFO status plus the GPU cycle counter. Thus the host-driven sequence below remains valid, but it is no longer the only control path.

---

## 9. End-to-End Data Flow: GPU Processes a Packet

The intended sequence for a GPU kernel operating on packet data:

```
1. Network packet arrives -> FIFO captures it (Port A writes to BRAM)
   BRAM[0] = {0xFF, header}   BRAM[1..N] = {0x00, data}

2. Host sets mode=2 (GPU mode) via PCI
   FIFO in_rdy drops (mode != 0)
   Port B now available for DMA/PCI

3. Host loads GPU program via PCI (IMEM Port B)
   regwrite(GPU_CTRL, 0x1)              -> hold GPU in reset
   For each instruction:
     regwrite(GPU_IMEM_ADDR, addr)
     regwrite(GPU_IMEM_WDATA, instr)
     regwrite(GPU_IMEM_CMD, 0x1)        -> strobe (auto-clear)

4. Host triggers DMA: FIFO BRAM[1..7] -> GPU DMEM[0..6]
   regwrite(DMA_FIFO_ADDR, 1)           -> skip header (BRAM[0])
   regwrite(DMA_GPU_ADDR,  0)           -> GPU DMEM starts at 0
   regwrite(DMA_LENGTH,    7)           -> 7 payload words
   regwrite(DMA_CTRL,      0x1)         -> start, dir=0 (FIFO->GPU)
   Poll GPU_STATUS until bit[1]=0       -> DMA complete

5. Host starts GPU
   regwrite(GPU_CTRL, 0x0)              -> release reset
   Poll GPU_STATUS until bit[0]=1       -> kernel_done

6. Host stops GPU
   regwrite(GPU_CTRL, 0x1)              -> re-assert reset

7. Host triggers DMA: GPU DMEM[0..6] -> FIFO BRAM[1..7]
   regwrite(DMA_FIFO_ADDR, 1)
   regwrite(DMA_GPU_ADDR,  0)
   regwrite(DMA_LENGTH,    7)
   regwrite(DMA_CTRL,      0x3)         -> start, dir=1 (GPU->FIFO)
   Poll GPU_STATUS until bit[1]=0       -> DMA complete

8. Host sets mode=0, triggers drain (intended egress sequence)
   regwrite(FIFO_MODE, 0x0)             -> back to FIFO mode
   regwrite(FIFO_DRAIN, 0x1)            -> drain modified packet
   With continuous downstream readiness, modified BRAM[1..7] are intended to
   flow downstream with the original header
```

The repository's Lab 8 hardware record verifies the internal FIFO→DMA→GPU→DMA→FIFO round trip by reading BRAM back over PCI. It also records `out_rdy` staying low during drain, so successful downstream/wire-side response delivery was not established. In addition, Batch 1 documents a current prefetch defect if `out_rdy` stalls after a drain has begun.

---

## 10. Design Decisions

### 10.1 Why DMA Instead of Direct GPU Fetch?

The GPU could theoretically read FIFO BRAM directly through its DMEM port. But:
1. **Stable GPU interface:** The integration uses the existing IMEM/DMEM Port B interfaces. Adding direct FIFO access would require a new memory path even though later internal GPU refinements did not change these ports.
2. **Width mismatch:** FIFO BRAM is 72-bit (ctrl+data), GPU DMEM is 64-bit. The DMA engine handles the 72->64 bit stripping.
3. **Separate address spaces:** GPU programs use GPU DMEM addresses (0--1023). If the GPU fetched from FIFO BRAM directly, the program would need to know the FIFO BRAM address range.

### 10.2 Why Keep GPU DMEM Separate?

Same reasoning as CPU DMEM (Batch 3): the GPU needs scratch space for intermediate results, register spills, and loop counters. Packet data is copied in, processed with local scratch space, then copied out.

### 10.3 Why 8-bit DMA Pointers?

FIFO BRAM has an 8-bit address, so an 8-bit offset is sufficient. Because length zero is rejected, one command transfers at most 255 words. The 10-bit GPU base plus the zero-extended offset can address a 255-word window anywhere in the 1024-word DMEM; both address sums wrap if software crosses the end of a memory.

---

## Summary -- What Batch 4 Establishes

1. **GPU instantiation** -- gpu_top with hardwired single-thread identity, reset gated by `reg_gpu_ctrl[0]`, default reset state = held in reset (`32'h1`)
2. **GPU registers (0x20--0x2B)** -- IMEM (PCI-only, 32-bit), DMEM (muxed PCI/DMA, 64-bit split lo/hi), GPU_STATUS packs kernel_done + dma_active
3. **DMA engine** -- 3-state FSM (IDLE->READ->COPY), 1 word/cycle throughput, bidirectional (FIFO<->GPU), gated by mode==2 and nonzero length
4. **DMA registers (0x2C--0x2F)** -- start strobe, direction bit, base addresses, length
5. **FIFO proc-bus source mux extended to 3-way** -- CPU / DMA / PCI with priority chain; the FIFO's separate physical Port B mux still selects drain logic in mode 0
6. **GPU DMEM ext port mux** -- 2-way: DMA (when active) / PCI (default)
7. **8 total auto-cleared command bits in current RTL** -- the four pre-GPU commands, three Batch 4 commands (`gpu_imem_cmd`, `gpu_dmem_cmd`, `dma_ctrl`), and FIFO soft reset (`reg_ctrl[0]`)

**Next batch:** Synthesis and hardware testing (Batch 5)
