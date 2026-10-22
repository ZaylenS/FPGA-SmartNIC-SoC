# AGENTS.md -- Lab 10: Network Processor Refinements for Application

This file provides guidance to Codex when working with code in this repository.

## Codex Working Rules

- This workspace is the checkpoint copy at `C:\Dev\EE533Labs\EE533_Project`, duplicated from `C:\Dev\EE533Labs\Lab10_refine_for_application`. Treat the original Lab10 folder and Claude project memories as read-only reference unless the user explicitly asks otherwise.
- The user owns publishing history. Local read-only git commands such as `git status`, `git diff`, `git log`, and `git show` are allowed and should be used when helpful for repo hygiene. Never run `git commit`, `git push`, or other remote/publishing operations unless the user explicitly asks.
- Treat existing dirty or untracked files as user-owned state. Do not revert, delete, move, or overwrite unrelated files.
- When showing copyable terminal commands, warn if accidental leading spaces would break or change behavior. In particular, heredoc delimiter lines such as `EOF` must start at column 1.
- Treat `.claude/settings.local.json` as Claude permission/config history, not engineering source. Do not copy secrets, API keys, or private transcript details from Claude local state into docs, code, or chat.
- The original EE533 deployment used NetFPGA V2 and Xilinx ISE 10.1, so legacy scripts/docs may mention Python 2.4 and ISE-only deliverable constraints. The class is complete; future development may target modern tools such as Vivado 2024.1 on Ubuntu 22.04 LTS. Preserve old compatibility only when editing scripts meant to run on the original NetFPGA hosts.
- CLI simulators are encouraged for iteration. Prefer the fastest local simulator that is compatible with the touched RTL/testbench, then document any target-specific Vivado/XSim checks when modern Xilinx behavior matters.

## Baton Handoff

- Current durable handoff summary for Codex is `docs/codex_handoff.md`.
- Simulator/tooling notes are in `docs/simulation_tools.md`.
- Historical Claude memory source for this project is `C:\Users\shao4\.claude\projects\C--Dev-EE533Labs-Lab10-refine-for-application\memory`. Use it as background only; prefer repo docs for source-of-truth technical details.

## Project

Network Processor integrating an ARM-compatible CPU (Lab 6) and custom GPU coprocessor (Lab 7) via a convertible FIFO on the **NetFPGA V2 (Virtex-II Pro XC2VP50)**. Uses Xilinx ISE 10.1 for synthesis. This is an EE533 lab project.

**This is Lab 10** -- refining the Lab 8/9 design toward final project use. The core design (FIFO + ARM + GPU + DMA) is complete and hardware-verified. Lab 10 focuses on:
1. Packetizing ANN parameters (weights/biases) and test data, sending from node0 to NetFPGA
2. Running ANN inference on the GPU using data from network packets
3. Collecting inference outputs and sending them back as network packets
4. Performance evaluation and measurement

## Design Status (carried from Lab 8)

**All hardware verified on NetFPGA (March 20, 2026):**
- Convertible FIFO (256x72 dual-port BRAM, one-packet buffer)
- ARM CPU integration (4-thread, reads/writes FIFO BRAM via MEM stage mux)
- GPU integration (4-lane SIMD, BF16+INT16, 6-stage pipeline)
- DMA engine (FIFO BRAM <-> GPU DMEM, pipelined 1 word/cycle)
- 9/9 tests pass: 5 CUDA kernels + 2 ANN inference + 2 integrated round-trip
- Real network packet tests pass (ARP capture, CPU modify, GPU kernels, ANN)
- Phase 1 refinements applied (bug fixes, GPU branch-to-EX1, HALT gating)

## Architecture

```
                      user_data_path.v
  8-byte  +--------------------------------------------+  8-byte
  data in |  Convertible FIFO                          |  data out
 -------->|  (Dual-Port BRAM: 256x72)                  |-------->
  ctrl in |     Port A <--> NetFPGA pipeline            |  ctrl out
 -------->|     Port B <--> ARM CPU / GPU (MUXed)       |-------->
          |                                            |
          |  +---------+         +---------------+     |
          |  | ARM CPU |<------->| GPU (SIMD     |     |
          |  | (Lab 6) |  shared |  coprocessor) |     |
          |  |         |  BRAM   |  (Lab 7)      |     |
          |  +---------+         +---------------+     |
          +--------------------------------------------+
```

## Mode Register

- **Mode 0 (FIFO)**: Normal packet forwarding. Port B = PCI access.
- **Mode 1 (CPU)**: ARM CPU drives Port B. PCI still accesses GPU/CPU registers.
- **Mode 2 (GPU)**: DMA engine drives Port B when active. GPU IMEM/DMEM via PCI.

## Register Map (word-indexed, 6-bit offsets from base 0x2001100)

- 0x00-0x0B: FIFO registers (CTRL, STATUS, MODE, DRAIN, BRAM_ADDR/WD/CMD/RD)
- 0x0C-0x1A: CPU registers (CTRL, STATUS, IMEM, DMEM, LA)
- 0x1B-0x1F: Reserved padding
- 0x20-0x2B: GPU registers (CTRL, STATUS, IMEM, DMEM)
- 0x2C-0x2F: DMA registers (CTRL, FIFO_ADDR, GPU_ADDR, LENGTH)

See `include/lab8_reg_defines.vh` for exact definitions.

## NF2.1 Packet Protocol

- Header word: ctrl=0xFF, data={dst_port[15:0], word_length[15:0], src_port[15:0], byte_length[15:0]}
- Data words: ctrl=0x00
- One-hot port encoding: MAC0=0x01, CPU0=0x02, MAC1=0x04, CPU1=0x08
- reference_nic routes incoming packets to CPU0 queue (dst_port=0x0002)

## GPU Architecture

- **ISA**: Custom 32-bit instructions (LD, ST, ADD, SUB, MUL, FMA, RELU, MOV, ADDI, MOVI, BLT, BGE, HALT)
- **Data types**: INT16 (4-lane SIMD), BF16 (4-lane SIMD) selected by dtype field
- **Pipeline**: 6-stage (IF -> ID -> EX1 -> EX2 -> EX3 -> WB), branch resolved in EX1
- **Resources**: 16 registers x 64-bit, 1024-word IMEM, 1024-word DMEM
- **Parameters**: See `include/gpu_params.vh` for all defines

## ANN Inference Setup

Two handcrafted neural networks (3-layer ReLU, same kernel `ann_3layer_relu.hex`):
- **Network A**: f(x) = 3*ReLU(0.5*ReLU(2x-1)+0.25) - 0.5 (weights in `data_ann_handcrafted.hex`)
- **Network B**: f(x) = 2x + 1 (weights in `data_net_2x_plus_1.hex`)

DMEM layout: [0]=input(4xBF16), [1-6]=weights/biases, [7]=output

Crafted UDP input from node0 via `send_bf16.py` lands at BRAM[7] (6-byte padding aligns to 8-byte boundary). DMA from BRAM[7] to GPU DMEM[0].

## Verilog Coding Rules (CRITICAL -- ISE 10.1)

1. **Verilog-2001 only** -- no SystemVerilog
2. **Every `case` must have `default`** -- prevents latch inference
3. **Every flip-flop needs explicit reset** -- VP50 has no global reset
4. **Multiplier inference:** operands <=18 bits infers `mult18x18`
5. **BRAM inference:** synchronous read pattern with `initial $readmemh`
6. **No `$display` or `$readmemh` in synthesizable RTL** -- debug in `tb/` only

## Build & Simulation Commands

**iverilog compilation:**
```bash
GPU_SRC="src/gpu/gpu_top.v src/gpu/core_top.v src/gpu/program_counter.v \
  src/gpu/instruction_memory.v src/gpu/data_memory.v src/gpu/fetch_stage.v \
  src/gpu/decode_stage.v src/gpu/instruction_decoder.v src/gpu/register_file.v \
  src/gpu/pipeline_reg_idex.v src/gpu/pipeline_reg_ex.v src/gpu/pipeline_reg_exwb.v \
  src/gpu/execute_stage.v src/gpu/simd_alu.v src/gpu/int16_alu.v \
  src/gpu/bf16_alu.v src/gpu/bf16_fma_unit.v src/gpu/hazard_unit.v \
  src/gpu/writeback_stage.v"

# Full integration test
iverilog -g2001 -I include -o tb_gpu_int \
  tb/sim_primitives.v src/fifo/fifo_bram.v src/fifo/convertible_fifo.v \
  src/arm/*.v $GPU_SRC src/lab8_wrapper.v tb/tb_gpu_integration.v && vvp tb_gpu_int
```

**NetFPGA synthesis (on Fedora VM):**
```bash
export XIL_TIMING_ALLOW_IMPOSSIBLE=1
cd /root/netfpga/projects/lab8/synth && make
```

## Directory Layout

```
Lab10_refine_for_application/
  src/                    -- All synthesizable Verilog
    arm/                  -- ARM CPU pipeline modules (14 files)
    fifo/                 -- Convertible FIFO (fifo_bram.v, convertible_fifo.v)
    gpu/                  -- GPU coprocessor (20 files incl. gpu_params.vh for TerosHDL)
    lab8_wrapper.v        -- Top-level integration wrapper (registers, DMA, proc mux)
    user_data_path.v      -- NF2 user data path (thin wrapper around lab8_wrapper)
  include/                -- Verilog headers
    gpu_params.vh         -- GPU ISA defines, opcodes, field positions
    lab8_reg_defines.vh   -- PCI register address defines
    registers.v           -- NF2 register infrastructure
    lab8.xml, project.xml -- NF2 register generator input
  tb/                     -- Testbenches and sim_primitives.v
  toolchains/             -- Build tools (assemblers, compilers, translators)
    arm/                  -- ARM toolchain: dump2hex.py, expand_arm.py, gen_write_imem.py
                             + sort.c, sort.s, sort_expanded.s (reference C/ASM)
    gpu/                  -- GPU toolchain: assembler.py, compile.py, ptx_translator.py,
                             bf16_utils.py, data_generator.py, isa_defs.py, ptx_parser.py
                             + tests/ (test assembly files)
  programs/               -- Pre-built hex files and assembly source
    arm/                  -- ARM CPU programs: test_4t_v2.hex, sort.hex, branch_test.hex
    gpu/                  -- GPU kernel hex+asm: 5 CUDA kernels + ANN kernels + data files
      kernels/            -- CUDA source: kernel.cu, kernel.ptx
  scripts/                -- Python scripts for NetFPGA register access and testing
    lab9reg.py            -- Main register interface (FIFO, CPU, GPU, DMA, all test suites)
    send_bf16.py          -- Send crafted BF16 data via UDP from node0
    train_ann.py          -- Train ANN weights via gradient descent
  docs/                   -- All documentation, organized by lab origin
    spec/                 -- Lab specs (lab7-s26.md, lab8-s26.md + page PNGs)
    lab6_arm/             -- ARM CPU walkthrough (14 pipeline modules)
    lab7_gpu/             -- GPU architecture, walkthroughs (5 batches), FMA fix,
                             timing fix, CUDA-to-NetFPGA workflow, datapath diagram
    lab8_integration/     -- Integration walkthroughs (5 batches), design/implementation
                             log, implementation plan, about_network_packets/
    lab9_refinements/     -- Refinement plans, improvements doc, GPU integration guide,
                             shared architecture spec, todo_lab9_prep
  sw/                     -- Legacy NF2 Perl register script (lab8reg)
```

## NetFPGA Deployment

- **FPGA host**: nf5.usc.edu (Team 5)
- **node0**: nf6.usc.edu (port0: 10.0.0.3 <-> nf2c0: 10.0.0.2)
- **Base address**: 0x2001100
- **Python**: 2.4+ on NetFPGA (no ternary, no `with`, no f-strings)
- **Deploy**: scp scripts + programs + bitfile to ~/lab9_integration/ on nf5

## Known Issues

- 4816 timing violations on core_clk_int (125 MHz), worst in GPU DECODE (11ns vs 8ns budget)
- 96% slice utilization -- routing congestion is the bottleneck (72% of critical path)
- Drain FSM stalls (out_rdy from output_queues stays low) -- not blocking for PCI-based verification
- Structural conversion analysis: not worth it until slice pressure reduced (see docs/todo_lab9_prep.md)

## Prior Lab Locations

- **Lab 6 ARM (my version)**: C:\Dev\EE533Labs\Lab6_synth\
- **Lab 7 GPU (final)**: C:\Dev\EE533Labs\Lab7_synth\
- **Lab 8 (main development)**: C:\Dev\EE533Labs\Lab8_fifo\
- **ANN scripts/programs**: C:\Dev\EE533Labs\on_fpga_ann\

## Lab 10 Objectives

From the lab spec:
1. Scripts to packetize ANN parameters + test data, send to NetFPGA
2. Firmware/hardware that processes packets and computes ANN inference
3. Collect inference outputs into network packets with correct headers, send out
4. Scripts to process output packets for analysis/presentation
5. Performance evaluation mechanisms for timing/throughput measurement
