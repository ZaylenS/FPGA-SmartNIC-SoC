# SmartNIC Project — Resume Wording Refinement

*Source: `C:\Dev\Resume\Resume_first_version_2026_1.pdf`*
*v1: 2026-05-04 — initial refinement*
*v2: 2026-05-06 — drop recall, sharpen ARM-ISA + CUDA-programmable framing*

## Original (current resume)

**FPGA SoC with ARM CPU, Custom SIMD GPU, and On-Chip IDS Inference** — Spring 2026
*Verilog, Python, C, Xilinx ISE, Icarus Verilog, ARM GCC, NetFPGA Virtex-II Pro*

- Architected and implemented a heterogeneous SoC on Xilinx Virtex-II Pro integrating a quad-thread pipelined ARM CPU, custom 4-lane SIMD GPU, DMA engine, and mode-switchable packet FIFO; delivered 7,800+ lines of synthesizable Verilog, hardware-verified on physical NetFPGA boards.
- Designed a custom 15-opcode GPU ISA with a 3-stage pipelined BFloat16 FMA unit and built a CUDA/PTX-to-hardware compilation toolchain; improved critical-path timing from 21.4 ns to 14.1 ns through pipeline restructuring, reaching 96% slice utilization.
- Deployed an MLP-based network intrusion detection system on-chip (Ethernet → FIFO → DMA → GPU inference), executing a 211-instruction BFloat16 kernel in ~19.2 µs at 125 MHz; validated attack/normal classification on live packet tests.

---

## Refined v2 — 3-bullet version (recommended)

**FPGA SoC with ARM-ISA CPU, CUDA-Programmable SIMD GPU, and On-Chip Intrusion Detection** — Spring 2026
*Verilog, Python, CUDA, C, Xilinx ISE, Icarus Verilog, ARM GCC, NetFPGA Virtex-II Pro*

- Architected and implemented a heterogeneous SoC on Xilinx Virtex-II Pro (NetFPGA) integrating a quad-thread pipelined **ARM-ISA-compatible CPU**, **CUDA-programmable 6-stage 4-lane SIMD GPU coprocessor**, packet DMA engine, and mode-switchable convertible FIFO; delivered 7,800+ lines of synthesizable Verilog with end-to-end **packet → inference → packet round-trip** hardware-verified on physical boards.
- Designed a custom 15-opcode SIMD ISA (**INT16 / BFloat16**) with a 3-stage pipelined BF16 FMA unit and a custom **cross-lane BCAST instruction that delivered 3.3× speedup** on dense fully-connected layers; built a **CUDA → NVIDIA PTX → custom-ISA compilation toolchain** and tightened critical-path timing from 21.4 ns to 14.1 ns at 96% slice utilization.
- Deployed a 4-layer MLP intrusion detection model (**NSL-KDD, 11-16-8-2 topology**) on-chip over the Ethernet → FIFO → DMA → GPU pipeline, achieving **82.4% accuracy on the KDDTest+ benchmark** and **~5.9 µs per-packet inference at 125 MHz**; XPower-measured 2.67 W full-chip FPGA power and projected **~100 mW per inference engine at 28 nm** (Kuon & Rose scaling).

---

## Refined v2 — 4-bullet version (more detail; only if you have space)

Same first two bullets as the 3-bullet version, then split the IDS bullet into application + power:

- Deployed a 4-layer MLP intrusion detection model (NSL-KDD, 11-16-8-2 topology) on-chip over the Ethernet → FIFO → DMA → GPU pipeline, achieving **82.4% accuracy on the KDDTest+ benchmark** and **~5.9 µs per-packet inference at 125 MHz**; validated end-to-end on a 500-sample live packet stream with zero drops on physical NetFPGA boards.
- Performed XPower analysis (2.67 W full-chip FPGA) and projected **~90–110 mW per inference engine when scaled to a 28 nm ASIC** via Kuon & Rose technology scaling, supporting an on-NIC inference vs. host-CPU offload comparison.

---

## What changed in v2 (vs. v1)

1. **Dropped attack recall from bullet 3.** Recall alone is one-sided (a trivial all-attack classifier scores 100%). 88% on its own reads as mediocre in security contexts; 100% (full KDDTest+ sim) invites overfit/methodology questions. Cleaner to lead with `82.4% accuracy on KDDTest+` and let interviewers ask for precision/F1.
2. **"ARM CPU" → "ARM-ISA-compatible CPU."** Cleanroom phrasing that signals "I implemented the ARM ISA" rather than "ARM-flavored." Same convention RISC-V projects use to distinguish a real ISA implementation from a lookalike.
3. **"Custom 4-lane SIMD GPU" → "CUDA-programmable 6-stage 4-lane SIMD GPU coprocessor."** Surfaces in bullet 1 the fact that the GPU accepts CUDA kernels (via the PTX toolchain detailed in bullet 2). "CUDA-programmable" rather than "CUDA-compatible" is the more defensible claim — *CUDA source compiles onto this hardware via a translation toolchain* — and sidesteps the contested "CUDA-compatible" framing.
4. **Bullet 2 toolchain label sharpened.** "CUDA/PTX-to-hardware" → "CUDA → NVIDIA PTX → custom-ISA compilation toolchain." Names the exact pipeline so a reviewer sees three real stages, not a vague handwave.
5. **Title updated.** Now spotlights the two architectural provenance claims (ARM-ISA, CUDA-programmable) rather than burying them in body bullets.

## Earlier changes carried over from v1

- "On-Chip IDS Inference" → "On-Chip Intrusion Detection" — readable to non-security recruiters.
- Added "**6-stage**" GPU pipeline depth.
- Added "**convertible FIFO**" — the actual codebase term.
- Added "**packet → inference → packet round-trip**" — names the verified outcome.
- Added "**(INT16 / BFloat16)**" datatype flag.
- Added "**custom cross-lane BCAST instruction that delivered 3.3× speedup**" — headline ISA-level win.
- Replaced "211-instruction BFloat16 kernel" with topology + benchmark name (`11-16-8-2`, `NSL-KDD`).
- Replaced "~19.2 µs" baseline with "~5.9 µs" post-BCAST. *(Alternative phrasing if you'd rather show the optimization arc: "improved per-packet inference from 19.2 µs to 5.9 µs (3.3×) via a custom cross-lane SIMD instruction" — and drop BCAST from bullet 2.)*
- Added power benchmark (2.67 W FPGA / ~100 mW projected at 28 nm).

---

## Resolved questions

1. **Attack recall** — dropped (see v2 change #1).
2. **Email** — confirmed `zilinshaodev@gmail.com` is the user's professional account.

## Still open

1. **20-sample demo accuracy (90%, 18/20).** Left off — sample size too small to publish.
2. **"Reaching 96% slice utilization."** Real but double-edged: shows density, also signals no headroom. Kept because the timing-improvement story (21.4 → 14.1 ns) makes it read as "tight, well-optimized." If asked, you can pivot to the structural-conversion analysis in `docs/todo_lab9_prep.md`.
3. **Lines of Verilog (7,800+).** Trusted from the prior resume; not re-counted. If you want a confirmed number, I can `cloc src/`.
