# Presentation Diagrams — Part 3 Expert Segment

Working diagrams for the 2026-04-28 progress presentation. Primary tool = **Claude Design** (animated HTML prototypes); source files here are prompts Claude Design consumes, not hand-built diagrams.

## Scope note (revised 2026-04-21)

User-spec §E calls for a *"simplified diagram of the current solution"* — where **solution = the full ML-IDS stack**, not just the hardware. So the C-ARCH diagram spans three phases: **Train**, **Compile**, **Run**, with runtime happening inside a Network Processor SoC container. The hardware-only Mermaid draft below is superseded by the Claude Design prompt but retained as a quick-reference for Q&A preparation.

## Files

| File | Purpose | Status |
|------|---------|--------|
| `claude_design_prompt_architecture.md` | **Primary** — Claude Design prompt for clip C-ARCH solution diagram (5-stage animated HTML, train/compile/run phases) | Ready to paste into Claude Design |
| `claude_design_prompt_differentiation.md` | **Primary** — Claude Design prompt for clip C-DIFF differentiation 2x2 (5-stage animated HTML, axes = detection paradigm × data-path locality) | Ready to paste into Claude Design |
| `claude_design_prompt_bcast.md` | **Primary** — Claude Design prompt for clip C-BCAST BCAST walkthrough (5-stage animated HTML, waste → barrier → mux fix → BCAST in action → 3.28× result). Variant A (Ben-Eater-style block-diagram + before/after SIMD + cycle-count bar chart). Q&A-scope guardrail: no literal code, no filename citations, no stack-layers sidebar | Ready to paste into Claude Design |
| `architecture_simplified.mmd` | Reference — hardware-only Mermaid (superseded; useful as Q&A back-pocket) | Kept for reference |

**Axes note for C-DIFF (2026-04-21)**: the 2x2 axes in the differentiation prompt are **Signature ↔ ML classification** × **Off-NIC ↔ Inline at NIC**. This supersedes the earlier cloud/edge × general/app-specific 2x2 drafted in `../part3_expert.md` §3.5. Reason: the new axes better answer Prof Cho's "SoC advantage" framing (from his 2026-03-26 feedback), and the "inline ML at NIC is nearly empty" claim is more defensible to an expert audience than the edge-viability claim (which is architectural-only on NetFPGA V2).

## Google Slides integration — how to get the animated HTML in

Google Slides does not embed live HTML. Use one of:

**Path 1 — MP4 embed (recommended)**:
1. Open Claude Design's HTML output, click "Play" for autoplay mode
2. Screen-record the full ~40 sec autoplay with OBS Studio / Win+G (Xbox Game Bar) / Loom
3. Export as MP4
4. Google Slides: `Insert > Video > Google Drive` (upload MP4 first) or embed via YouTube unlisted link

**Path 2 — Multi-slide screenshot sequence**:
1. Open Claude Design HTML, use Previous/Next buttons to step through 5 stages
2. Screenshot each stage at 1920×1080
3. Insert each screenshot as a separate slide in Google Slides
4. Apply Fade transition between slides

**Path 3 — Present HTML live**:
1. Open the Claude Design HTML in a browser tab before presenting
2. Alt-tab to browser during the C-ARCH segment, click Play
3. Alt-tab back to slides for remaining content

## How to render `architecture_simplified.mmd` (reference only)

**Fastest path (browser, no install):**
1. Open https://mermaid.live
2. Paste file contents into the left panel
3. Right-click rendered diagram → "Download SVG" or "Download PNG"

**VSCode preview**: install extension `bierner.markdown-mermaid`, open `.mmd`, Ctrl+Shift+V.

## Animation shot list for clip C-ARCH (~45 sec, user voices over)

Matches stages in the Claude Design prompt.

| Stage | Time | Visual | Narration cue (for user transcript) |
|-------|------|--------|--------------------------------------|
| 1 | 0-8 sec | Three row labels + empty SoC container | "Our solution has three parts — training, compilation, and runtime on our custom silicon." |
| 2 | 8-16 sec | Row 1 populates: NSL-KDD → train_ann.py → weights | "We train an 11-16-8-2 neural network on the NSL-KDD intrusion detection dataset. Our Python gradient-descent script produces BF16 weights." |
| 3 | 16-24 sec | Row 2 populates: kernel.cu → PTX → our toolchain → program.hex | "We translate CUDA kernel source through our own PTX-to-ISA translator and assembler, producing the executable our GPU runs." |
| 4 | 24-33 sec | Row 3 populates: SoC container with FIFO, ARM, GPU, packet flow | "At inference time, every packet flows through this convertible FIFO. The ARM reads the header; the GPU runs the classifier. All on-chip." |
| 5 | 33-45 sec | Cross-row dashed arrows light up (weights → GPU DMEM, program → GPU IMEM); diagram glows once | "Three phases, one pipeline. Every layer — training script, compiler toolchain, silicon — is ours." |

## Notes on scope — what's in, what's out, why

**Included** (because user-spec asks for "solution"):
- Full training pipeline (NSL-KDD, train_ann.py, weights)
- Full compilation pipeline (CUDA, PTX, our translator + assembler, program.hex)
- Runtime SoC (FIFO, ARM, GPU with BCAST ISA, packet flow)
- Cross-phase loading arrows in final stage — shows how train + compile feed runtime

**Deliberately excluded**:
- BRAM sizes (256×72) — Q&A detail only
- Thread count / SIMD lane count — covered in C-BCAST clip
- Pipeline stage names (IF/ID/EX1/etc.) — too granular
- DMA as its own block — folded into "features via DMA" arrow label
- `user_data_path.v` wrapper — implementation detail
- FIFO mode enumeration (Mode 0/1/2) — narration-only if needed
- Xilinx / Virtex / NetFPGA silicon specifics — "one FPGA" suffices for this level

## Iteration plan

1. User pastes `claude_design_prompt_architecture.md` into Claude Design
2. First render — review, feedback via Claude Design chat for refinements
3. Once content is locked, screen-record autoplay or screenshot stages
4. Insert into Google Slides per integration path above
5. Draft user voice-over transcripts per stage (can happen in parallel with recording)
