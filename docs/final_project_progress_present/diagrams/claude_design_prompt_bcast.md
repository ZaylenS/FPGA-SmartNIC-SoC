# Claude Design Prompt — BCAST Walkthrough (Clip C-BCAST)

**Created 2026-04-21**: Variant A chosen — Ben-Eater-style before/after SIMD + datapath zoom + cycle-count bar chart. Matches user-spec §E requirement: *"a presentation slides/video for your final project that highlights the difference in technical detail to convince the domain expert that your solution is novel and that your team is the only one who can do it."*

**Q&A scope guardrail (user preference 2026-04-21)**: avoid on-screen implementation detail that would widen the Q&A surface. No literal Verilog snippets, no file/module name citations, no stack-layers inventory sidebar, no pipeline-stage timing diagrams. The clip stays at the block-diagram + assembly-mnemonic level — concrete enough to feel technical, abstract enough to keep the Q&A manageable. The "only our team can do it" message is carried implicitly by narration ("this speedup required adding an instruction to our own GPU") — never stated as a sentence, never as a visual inventory.

Paste everything below the `---` line into a fresh Claude Design conversation. Target output: 5-stage animated HTML prototype with autoplay (~50-sec screen-recordable clip for Google Slides embedding).

**Google Slides integration path**:
- Recommended: click "Play" → screen-record the full autoplay (~50 sec) with OBS / Win+G / Loom → export MP4 → Google Slides `Insert > Video > Google Drive`.
- Alternative: screenshot each of the 5 stages at 1920×1080 → insert as 5 sequential slides with Fade transition.

---

Create an animated "technical walkthrough" diagram for a graduate electrical-engineering class progress presentation. The clip walks through the **BCAST instruction** — a cross-lane broadcast operation we added to our custom GPU's ISA to unlock full 4-lane SIMD parallelism for neural network inference. The payoff: one small hardware change (a 4:1 mux) yielded a 3.28× speedup on our intrusion-detection classifier, measured cycle-exact on real silicon.

**Aspect ratio**: 16:9, target export resolution 1920×1080.

**Style**: technical-YouTuber zoomed-in hardware walkthrough — Ben Eater reference. Calm authoritative, deliberate pace, strong visuals of registers and datapath blocks, no marketing gloss. White background, strong color coding by block type, clean sans-serif + monospace typography, arrow weights consistent. Must match the visual style of the companion C-ARCH and C-DIFF diagrams (same color palette, same minimal chrome).

**Layout**:
- Central content area fills ~70% of the canvas, changes per stage.
- Stage counter top-right ("Stage N of 5"), subtitle band bottom.
- Stage title at top (sans-serif bold, 24pt), subtitle at bottom (italic, 16pt).

**Color system** (match C-ARCH and C-DIFF exactly):
- SIMD lane boxes (active): fill `#fed7aa` (GPU orange from C-ARCH), stroke `#c05621`
- SIMD lane boxes (wasted / greyed): fill `#edf2f7` with diagonal grey hatching, stroke `#a0aec0`, label "wasted"
- "Register file" / "ALU block" diagram boxes: fill `#f7fafc`, stroke `#4a5568`
- BCAST mux (the fix, highlighted): fill `#c6f6d5` (green, same as FIFO color in C-ARCH — signals "our addition"), stroke `#2f855a`, 3px
- NO-INSTRUCTION barrier (Stage 2): fill `#fed7d7`, stroke `#c53030`, thick 4px vertical wall with red "NO INSTRUCTION" text in bold
- Distinct-neuron lane colors (Stage 2, Layer N output `{h3, h2, h1, h0}`): use four distinct pastels — lane 0 blue `#bee3f8`, lane 1 green `#c6f6d5`, lane 2 yellow `#faf089`, lane 3 pink `#fed7e2`, each with matching darker stroke
- Bar chart "before" bar: fill `#fc8181`, stroke `#c53030` (red — scalar, wasteful)
- Bar chart "after" bar: fill `#68d391`, stroke `#2f855a` (green — BCAST, efficient)
- Assembly mnemonic text: monospace, `#2d3748` on `#f7fafc` background rounded rect
- Callout badges: fill `#edf2f7`, stroke `#2b6cb0`, text `#1a365d`
- Background: pure white `#ffffff`

**5 animation stages** with Previous/Next buttons, keyboard arrow shortcuts, stage counter top-right, and a **"Play" button** that auto-advances through all stages with ~10-sec pauses on each.

**Stage 1 — The waste (scalar mode)**
Visual: four horizontal rectangles representing the four SIMD lanes of one register, labeled Lane 0 / Lane 1 / Lane 2 / Lane 3 beneath. All four boxes show the same monospace value `0.7` (pick any concrete number). Lane 0 rendered in active GPU-orange; Lanes 1, 2, 3 rendered in grey with diagonal hatching and the word "wasted" stamped across them. Small badge bottom-right: "25% SIMD utilization."
Subtitle: *"Without cross-lane operations, our 4-lane SIMD ran in scalar mode — all lanes computing the same value, three of four wasted."*

**Stage 2 — The inter-layer barrier**
Visual: two horizontal register strips stacked vertically, with a thick red vertical barrier between them:
- Top strip ("Layer N output, R1"): four lanes in four distinct pastels, each showing a different labeled value `h3`, `h2`, `h1`, `h0` (one per lane)
- A thick red vertical wall labeled "NO INSTRUCTION" in bold red caps, with smaller grey italic subtext "cross-lane replicate unavailable"
- Bottom strip ("Layer N+1 input, R3 needed"): four lanes all in the same blue color (the `h0` pastel), each showing `h0` — i.e., `{h0, h0, h0, h0}`
- A ghosted grey arrow tries to go from top strip's lane 0 down through the barrier to all four bottom lanes, but stops at the wall with a small "✕" symbol
Subtitle: *"Multi-layer neural nets need one neuron's output replicated across all lanes as input to the next layer. Our base ISA had no instruction for this — so the kernel fell back to scalar mode."*

**Stage 3 — The fix: one 4:1 mux**
Visual: a simple block-level datapath diagram, three blocks left-to-right:
- Box A (left, grey `#f7fafc`): labeled "Register File", shows a small register icon with `{h3, h2, h1, h0}` inside
- Wide arrow →
- Box B (center, **green highlight** `#c6f6d5` with 3px `#2f855a` stroke and a subtle glow): labeled "4:1 lane mux", with a small "lane select" control input pin coming in from above (labeled with a literal 0, 1, 2, or 3 cycling gently)
- Wide arrow →
- Box C (right, grey `#f7fafc`): labeled "4 SIMD ALUs", shows four small ALU icons in a row, output showing `{h0, h0, h0, h0}`
Resource callout badge below the mux block: `+65 LUTs · ~0.1% of the chip`
Subtitle: *"The fix: a 4:1 mux placed between the register file and the SIMD ALUs, activated only by a new opcode. Sixty-five LUTs — about a tenth of a percent of the chip."*

**Stage 4 — BCAST in action**
Visual: a three-frame animated sequence, played left-to-right (each frame a small register strip with annotations):
- Frame 1: register `R1 = {h3, h2, h1, h0}` — four lanes in four distinct pastels (same colors as Stage 2). Annotation above: "from previous FMA"
- Curved arrow labeled with an assembly mnemonic in monospace box: `BCAST R3, R1, 0`
- Frame 2: register `R3 = {h0, h0, h0, h0}` — four lanes now all in the `h0` pastel blue. Annotation: "lane 0 replicated to all lanes"
- Curved arrow labeled with: `FMA R1, R2, R3, R1`
- Frame 3: register `R1 = {n3', n2', n1', n0'}` — four lanes again in four distinct pastels, annotation "4 neurons updated in parallel"

Small persistent syntax key in the corner: `BCAST Rd, Rs, lane   (lane = 0..3)`
Subtitle: *"One new instruction. Any lane can become the broadcast input to the next layer's computation — 4-neuron parallel mode unlocked."*

**Stage 5 — The result**
Visual: centered two-bar chart:
- Left bar (red `#fc8181`): height proportional to 2402, label "2402 cycles" atop bar, x-axis label "before · scalar mode"
- Right bar (green `#68d391`): height proportional to 732, label "732 cycles" atop bar, x-axis label "after · BCAST 4-neuron parallel"
- Large "3.28×" label floating between the bar tops with a curved arrow indicating the speedup
- Below the chart, a single verified-badge strip: `hardware-verified 2026-04-17 · measured via PCI cycle counter wired into the SoC's register map`
- Final soft glow across the whole canvas to signal completion
Subtitle: *"3.28× speedup on the IDS inference, measured cycle-exact on silicon. This required adding an instruction to our own GPU — the kind of change only possible when you own the whole stack."*

**DO NOT include** (Q&A-scope guardrail):
- Literal Verilog or assembly code snippets beyond the `BCAST Rd, Rs, lane` mnemonic syntax key in Stage 4 and the two assembly-mnemonic arrow labels
- File names, module names, or line-number citations of any kind
- Pipeline-stage timing diagrams (IF/ID/EX1/EX2/EX3/WB)
- Stack-layers inventory sidebar in Stage 5 (deliberately omitted — user preference to keep Q&A scope narrow; the implicit "only we can do it" signal comes from the subtitle wording in Stage 5, not from visual inventory)
- Critical-path timing numbers or timing-violation counts
- LUT / FF / BRAM detailed resource breakdowns beyond the single "+65 LUTs · ~0.1%" callout in Stage 3
- Cross-lane operations other than BCAST (no hint at HSUM, DOT-product, shuffle — keep the story focused)
- The scalar kernel's actual loop text or instruction counts per layer
- NSL-KDD dataset specifics, feature names, accuracy numbers (those belong to C-ARCH and the live intro, not here)
- The phrase "only our team can do it" spoken literally — humble framing rule

**Interactivity requirements**:
- **Play button**: auto-advances all 5 stages with 10-sec pauses, smooth transitions. When autoplay finishes, remains on Stage 5.
- **Previous/Next buttons**: manual stepping, each transition ~0.4 sec fade.
- Keyboard arrow keys as shortcuts (Left = Previous, Right = Next, Space = Play).
- Stage counter top-right: "Stage N of 5".
- No tooltips, no hover-only effects, no sounds.

**Typography**:
- Stage titles: sans-serif bold, 24pt
- Lane value labels inside SIMD register strips: monospace, 20pt
- Register names (R1, R3): monospace bold, 18pt
- Block labels ("Register File", "4:1 lane mux", "4 SIMD ALUs"): sans-serif bold, 18pt
- Assembly mnemonic arrow labels: monospace, 16pt, `#2d3748` on rounded `#f7fafc` background
- Callout badges ("+65 LUTs · ~0.1%", "25% SIMD utilization"): sans-serif, 14pt, `#1a365d`
- Bar chart axis labels: sans-serif, 14pt, `#4a5568`
- Bar chart value labels (2402, 732, 3.28×): sans-serif bold, 22pt
- "hardware-verified" badge strip: sans-serif, 14pt italic, `#4a5568`
- Subtitles (bottom captions): sans-serif italic, 16pt, gray `#4a5568`
- Stage counter: sans-serif, 14pt, gray `#718096`

**Output**: single self-contained HTML artifact that I can open, click Play for the autoplay demo, screenshot each stage at 1920×1080 for Google Slides, or screen-record the full autoplay sequence for MP4 embedding.
