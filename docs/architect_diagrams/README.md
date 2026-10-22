# Network Processor Architecture Diagrams

This set is derived from a read-only cross-check of all 38 RTL/header files under `src/` and all 25 Markdown files under `docs/lab6_arm`, `docs/lab7_gpu`, and `docs/lab8_integration`. Where historical walkthroughs disagree with the current implementation, the diagrams follow the RTL. No existing source or walkthrough file was changed; this directory is the only output location.

| View | Presentation | Editable source |
|---|---|---|
| Brief SoC architecture | [SVG](01-soc-overview.svg) · [PNG](01-soc-overview.png) | [Mermaid](01-soc-overview.mmd) |
| ARM CPU microarchitecture | [SVG](02-arm-cpu-microarchitecture.svg) · [PNG](02-arm-cpu-microarchitecture.png) | [Mermaid](02-arm-cpu-microarchitecture.mmd) |
| GPU microarchitecture | [SVG](03-gpu-microarchitecture.svg) · [PNG](03-gpu-microarchitecture.png) | [Mermaid](03-gpu-microarchitecture.mmd) |
| Detailed full-SoC architecture | [SVG](04-soc-detailed.svg) · [PNG](04-soc-detailed.png) | [Mermaid](04-soc-detailed.mmd) |
| Packet-to-inference operating sequence | [SVG](05-inference-sequence.svg) · [PNG](05-inference-sequence.png) | [Mermaid](05-inference-sequence.mmd) |

PNG exports accompany the SVGs for software that cannot import vector graphics. SVG is the preferred presentation format; Mermaid is the preferred editable/semantic format.

## Diagram conventions

- Solid arrows are packet, instruction, or data movement.
- Dashed arrows are control, status, stall, reset, or feedback.
- FIFO words are 72 bits (`ctrl[7:0] + data[63:0]`); CPU/GPU/DMA data words are 64 bits.
- All reviewed custom RTL uses one `clk`; there is no custom-logic clock-domain crossing in `src/`.
- Mode 0 owns FIFO Port B for drain; mode 1 exposes the processor port to CPU-or-PCI; mode 2 exposes it to DMA-or-PCI.

## Current-RTL interpretation notes

- ARM MEM uses three windows: `0x00-0x7F` internal DMEM, `0x80-0xEF` FIFO BRAM (FIFO indices `0x00-0x6F`), and `0xF0-0xFF` wrapper-register aliases.
- The GPU is four-lane for BF16 SIMD and BF16 FMA. Its current integer path has one lane-0 `int16_alu`, then replicates that 16-bit result into all four output lanes.
- `include/gpu_params.vh` is the active build header and includes BCAST; the duplicate `src/gpu/gpu_params.vh` does not contain the current BCAST definitions.
- FIFO drain is shown with its implemented continuous-`out_rdy` requirement. A mid-packet stall can overwrite the single prefetched word and skip data.
- The diagrams distinguish intended ownership from software sequencing requirements: keep mode 2 throughout DMA, return to mode 0 before drain, and hold the GPU in reset while loading/setup is performed.
