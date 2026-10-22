# Codex Handoff From Claude Work

This note distills the Claude handoff files and memory notes into repo-local context for future Codex sessions. It is not a substitute for the source docs; it points to the docs that should be read before changing a subsystem.

## Sources Reviewed

- `CLAUDE.md` and `AGENTS.md` in this checkpoint repo.
- Matching `CLAUDE.md`, `AGENTS.md`, and `.claude/settings.local.json` in `C:\Dev\EE533Labs\Lab10_refine_for_application`; hashes match this checkpoint copy.
- Claude project memory Markdown files in `C:\Users\shao4\.claude\projects\C--Dev-EE533Labs-Lab10-refine-for-application\memory`.
- Key repo docs: `docs/lab10_refinements.md`, `docs/ids_accuracy_journey.md`, `docs/bcast_instruction_design.md`, `docs/arm_orchestrator.md`, `docs/throughput_measurement_runbook.md`, and `docs/final_project_demo_video/README.md`.

## Current Project Status

- EE533 SP26 final project was completed and delivered on 2026-05-12.
- Delivered system: NetFPGA network processor with ARM CPU, convertible FIFO, DMA, and custom 4-lane SIMD GPU running an ML-based IDS classifier.
- Main delivered metrics: 11->16->8->2 ANN, 346 parameters / 692 bytes BF16, 82.4% KDDTest+ BF16-faithful dev accuracy, 82.2% on a 500-sample hardware batch, 88% attack recall on that batch, 0/500 dropped, about 7 ms/packet for the batch test.
- BCAST custom GPU instruction is hardware-verified: scalar 2402 cycles -> BCAST 732 cycles, 3.28x speedup, +65 LUTs, no new flip-flops, measured with the GPU cycle counter.

## Critical Engineering Context

- `docs/ids_accuracy_journey.md` is the source for training/accuracy claims. The final v3 recipe uses label smoothing 0.1, seed 53, RF seed 42, 200 epochs, Adam/cosine, QAT/BF16-faithful evaluation.
- `docs/bcast_instruction_design.md` is the source for BCAST motivation, encoding, RTL placement, cycle analysis, and resource cost.
- `docs/milestone3_refinements.md` records timing-closure lessons. Fix 1 registers `effective_a` in `src/gpu/simd_alu.v` and is hardware-verified. Fix B timing closure depended on neutral RTL perturbations in `src/lab8_wrapper.v`; do not casually undo them.
- `docs/arm_orchestrator.md` is the source for ARM-orchestrated IDS. The ARM is an orchestrator, not a classifier or header parser. It polls status, sets FIFO mode, programs DMA, releases GPU, and frames/drains response packets.
- ARM-orchestrated inference is silicon-verified at BRAM/DMEM level. Fully autonomous wire-side response delivery is limited by the NetFPGA reference `output_queues` drain behavior, outside this repo's authored RTL.
- PCI round-trip path includes host-side response-envelope fixes in `scripts/lab10reg.py`: valid SrcMAC/SrcIP for Linux RPF and 7-byte TX truncation compensation. This path was used for on-wire demo evidence.

## Hardware And Deployment Gotchas

- FIFO BRAM Port B is not PCI-readable in mode 0 because the address is hardwired to `rd_ptr`; switch to mode 2 for PCI BRAM reads.
- After `cpu_start`, explicitly restore `mode 0` and reset the FIFO before expecting ingress packets; `cpu_start` side effect otherwise disconnects NF2 ingress.
- For ARM orchestrator bring-up, load the BCAST kernel/data explicitly, not the scalar default.
- `send_ids.py --replicated` is required for the ARM orchestrator/BCAST flow because the DMA copies one replicated BF16 feature word per GPU DMEM slot.
- The FIFO/classifier word-length convention drops the last data word. Scripts add a sacrificial trailer/padding word; audit this before touching `src/fifo/convertible_fifo.v`.
- On final-project hardware, board/testbench context differs from older Lab 8/9 notes: final project used nf6 as FPGA host and node1@nf7 as sender/listener on `10.0.4.x`.

## GPU Kernel Gotchas

- GPU destination registers R13, R14, and R15 are read-only aliases for THREADID, BLOCKID, and BLOCKDIM; writes silently drop. Use R1-R12 for destinations. R0 is hardwired zero.
- `ADDI Rd, Rs, 1` breaks SIMD lane uniformity because the immediate is a 64-bit scalar value, not four 16-bit lane constants. For lane-uniform pointer increments, use `ADD` with a MOVI-initialized `{1,1,1,1}` register.
- Without BCAST or another cross-lane primitive, multi-layer networks fall back to scalar SIMD mode. BCAST enables output-parallel layer execution by broadcasting packed previous-layer outputs.

## Workflow Rules

- Local read-only git commands are allowed for repo hygiene. Do not run `git commit`, `git push`, or remote/publishing git operations unless the user explicitly asks.
- Do not copy secrets or API keys out of Claude local settings or transcript logs. `.claude/settings.local.json` is permissions history, not a project specification.
- The original class-facing flow used ISE 10.1 and Python 2.4 on NetFPGA hosts, but the class is complete. Future development may use modern flows such as Vivado 2024.1 on Ubuntu 22.04 LTS. Keep Python 2.4 compatibility only for scripts still intended to run on the old NetFPGA machines.
- Use CLI simulation for normal iteration when available. `iverilog` remains useful for Verilog-2001 testbenches; evaluate Verilator or Vivado XSim when speed, lint, SystemVerilog, or Xilinx-specific behavior matters.
- If showing shell commands with heredocs, warn that delimiter lines such as `EOF` must begin at column 1.

## Source-Of-Truth Pointers

- Project overview, register map, Verilog rules: `AGENTS.md` and `CLAUDE.md`.
- Lab 10 implementation plan and early status: `docs/lab10_refinements.md`.
- IDS model/training story: `docs/ids_accuracy_journey.md`, `docs/ids_v2_results.md`.
- Hardware IDS verification: `docs/ids_hardware_test_doc.md`.
- BCAST design and timing closure: `docs/bcast_instruction_design.md`, `docs/milestone3_refinements.md`.
- ARM orchestrator and Fix B: `docs/arm_orchestrator.md`.
- Throughput and response-delivery debugging: `docs/throughput_measurement_runbook.md`.
- Final demo-video artifacts: `docs/final_project_demo_video/README.md`, `docs/final_project_demo_video/voiceover_script.md`, `docs/final_project_demo_video/clips_catalog.md`.
- Modern simulation/tooling notes: `docs/simulation_tools.md`.
