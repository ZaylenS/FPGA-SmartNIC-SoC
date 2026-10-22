# Claude Design Prompt — Solution Diagram (Clip C-ARCH)

**Revised 2026-04-21**: scope expanded from "network processor hardware" to "full ML-IDS solution" (training + compilation + runtime). Matches user-spec §E requirement: *"simplified diagram of the current solution."*

Paste everything below the `---` line into a fresh Claude Design conversation. Target output: 5-stage animated HTML prototype with autoplay support (so you can screen-record a clean MP4 for Google Slides embedding, or screenshot each stage for slide-per-stage insertion).

**Google Slides integration path**:
- Recommended: click "Play" → screen-record the full 5-stage autoplay (~40 sec) with OBS / Win+G / Loom → export MP4 → Google Slides `Insert > Video > Google Drive`.
- Alternative: screenshot each of the 5 stages at 1920×1080 → insert as 5 sequential slides with Fade transition.

---

Create an animated "solution diagram" for a graduate electrical-engineering class progress presentation. The diagram walks through 5 progressive reveal stages showing the **end-to-end ML-based intrusion detection solution** we built: training, compilation, and runtime on our custom FPGA-based network processor. Critically: this is the *full solution*, NOT just the hardware — it must show our training pipeline and our compilation toolchain alongside the runtime silicon.

**Aspect ratio**: 16:9, target export resolution 1920×1080 (for Google Slides insertion or screen recording).

**Style**: technical educator / YouTube-channel clean — Ben Eater, Branch Education. Calm authoritative, not corporate-slick, not playful-cartoon. White background, strong color coding per block type, clear sans-serif typography, arrow weights consistent.

**Layout**: three horizontal rows stacked vertically, each labeled clearly on the left:
1. Row 1: "1. Train" (small gray subtitle: "offline, once")
2. Row 2: "2. Compile" (small gray subtitle: "offline, once")
3. Row 3: "3. Run" (small gray subtitle: "every packet") — this row has a "Network Processor SoC — one FPGA" container box around its middle content

Within each row, data flows left to right. In the final animation stage, dashed cross-row arrows appear from Train and Compile down to the GPU in Run.

**Color system** (use exactly these):
- Data/artifact boxes (datasets, files, hex): fill `#f7fafc`, stroke `#4a5568`, text `#2d3748`, monospace font for filenames
- Script/tool boxes (Python scripts, compilers): fill `#edf2f7`, stroke `#2b6cb0`, text `#1a365d`, italic for "our custom tools"
- SoC container box (Run row): fill `#e8f2ff`, stroke `#2c5282`, heavy stroke width
- Convertible FIFO: fill `#c6f6d5`, stroke `#2f855a`
- ARM CPU: fill `#e9d8fd`, stroke `#6b46c1`
- GPU: fill `#fed7aa`, stroke `#c05621`
- Cross-row dashed arrows (weights/program loading into GPU): stroke `#6b46c1`, dashed
- Phase labels / row headers: text `#2d3748`, bold, 24pt+
- Background: pure white `#ffffff`

**Row 1 — Train** (3 boxes, left to right):
- `NSL-KDD` (data box — label: "NSL-KDD dataset")
- `train_ann.py` (tool box, italic — label: "train_ann.py" with small subtitle "Python gradient descent")
- `weights` (data box — label: "weights (BF16)")
Arrows: box 1 → box 2 → box 3.

**Row 2 — Compile** (4 boxes, left to right):
- `kernel.cu` (data box — label: "kernel.cu" with small subtitle "CUDA source")
- `PTX` (data box — label: "PTX")
- `ptx_translator.py + assembler.py` (tool box, italic — label: "our toolchain" with small subtitle "ptx_translator.py + assembler.py")
- `program.hex` (data box — label: "program.hex")
Arrows: box 1 → box 2 → box 3 → box 4.

**Row 3 — Run** (5 elements inside SoC container):
- Left of SoC box: "Packet In" arrow entering the SoC from the left
- Inside SoC: "Convertible FIFO" block (central)
- Inside SoC, above FIFO: "ARM CPU" block, connected to FIFO with bidirectional arrow labeled "header"
- Inside SoC, right of FIFO: "GPU" block with small italic secondary label "BCAST ISA" underneath. Connected to FIFO with bidirectional arrow labeled "features via DMA"
- Right of SoC box: "Packet Out" arrow exiting to the right

**Cross-row dashed arrows** (appear only in Stage 5):
- From `weights` (Row 1) dashed-arrow down to GPU (Row 3), label: "loaded to GPU DMEM"
- From `program.hex` (Row 2) dashed-arrow down to GPU (Row 3), label: "loaded to GPU IMEM"

**DO NOT include**: BRAM sizes, thread counts, SIMD lane counts, pipeline stage names, register addresses, DMA as a separate box (fold into arrow label), Verilog module names, specific NSL-KDD feature column names, or mentions of "Xilinx" / "Virtex" / "NetFPGA" silicon specifics.

**5 animation stages** with Previous/Next buttons, keyboard arrow shortcuts, stage counter top-right ("Stage N of 5"), and a **"Play" button** that auto-advances through all stages with ~8-sec pauses on each (for clean screen recording).

**Stage 1 — Skeleton**
Show: three row labels ("1. Train", "2. Compile", "3. Run") and the empty SoC container in Row 3. All data/tool boxes hidden.
Subtitle at bottom: *"Our solution has three parts — training, compilation, and runtime."*

**Stage 2 — Training populates**
Add Row 1 boxes sequentially (NSL-KDD → train_ann.py → weights) with arrows. Fade-in ~0.3 sec per box.
Subtitle: *"We train an 11-16-8-2 neural network on the NSL-KDD intrusion detection dataset."*

**Stage 3 — Compilation populates**
Add Row 2 boxes sequentially (kernel.cu → PTX → our toolchain → program.hex). Highlight the "our toolchain" box with a subtle pulse to emphasize it's custom-built.
Subtitle: *"We translate CUDA to our custom ISA through our own Python toolchain."*

**Stage 4 — Runtime populates**
Add Row 3 contents inside the SoC: FIFO, ARM CPU, GPU with BCAST ISA, Packet In/Out arrows. A small packet graphic moves from Packet In arrow into the FIFO. Both internal arrows (FIFO↔ARM, FIFO↔GPU) pulse once.
Subtitle: *"At inference, packets flow through our custom silicon — on-chip, no host round-trip."*

**Stage 5 — Integration**
Two dashed purple arrows fade in:
1. From `weights` (Row 1) down to GPU (Row 3), label "loaded to GPU DMEM"
2. From `program.hex` (Row 2) down to GPU (Row 3), label "loaded to GPU IMEM"
The entire diagram softly glows once to signal completion.
Subtitle: *"Three phases, one pipeline. Every layer — training, compilation, and silicon — is ours."*

**Interactivity requirements**:
- **Play button**: auto-advances all 5 stages with 8-sec pauses, smooth transitions. When autoplay finishes, remains on Stage 5.
- **Previous/Next buttons**: manual stepping, each transition ~0.3 sec fade.
- Keyboard arrow keys as shortcuts (Left = Previous, Right = Next, Space = Play).
- Stage counter top-right: "Stage N of 5".
- No tooltips, no hover-only effects, no sounds.

**Typography**:
- Row headers: sans-serif bold, 28pt
- Box labels: sans-serif, 18-20pt
- Filename labels: monospace, 14-16pt
- Subtitles (bottom captions): sans-serif italic, 16pt, gray `#4a5568`
- Stage counter: sans-serif, 14pt, gray `#718096`

**Output**: single self-contained HTML artifact that I can open, click Play for autoplay demo, screenshot each stage at 1920×1080 for Google Slides, or screen-record the full autoplay sequence for MP4 embedding.
