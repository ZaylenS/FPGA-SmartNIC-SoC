# Claude Design Prompt — Beat 3 Architecture Walkthrough (Final Demo Video)

**Drafted 2026-05-10.** For the final project demo video (target submit 2026-05-13). Beat 3 in the 8-beat outline; budget ~2 min on-screen runtime (longer than the Apr 28 live-presentation diagram, which was ~40 s).

**Differences from the earlier Apr 21 solution diagram** (user-facing notes — not part of what Claude Design sees):

- Train + Compile rows are removed. Beat 2 of the demo video already covers training; offline plumbing collapses into a small *inset* (weights + program pre-loaded into GPU memory at boot), not a full row.
- Spine is **packet journey** — follow one packet from ingress to verdict — instead of "three phases of the solution."
- One level deeper inside the **ARM CPU** (4 hardware threads visible) and inside the **GPU** (4 SIMD lanes + 6-stage pipeline tag + DMEM/IMEM sub-blocks + cycle counter).
- **DMA engine** is its own block (was folded into an arrow label before).
- Mode register gets one name-drop in the subtitle for Stage 1, no dedicated visual.

**Factual revisions (2026-05-10 (later in day), verified against `docs/arm_orchestrator.md` and `scripts/lab10reg.py`):**

- **ARM is purely an orchestrator** — it polls FIFO_STATUS, sets FIFO_MODE, triggers DMA in/out, polls GPU_STATUS, and frames the response. It does **not** parse headers or interpret logits. Stage 2 wording updated accordingly ("polls + orchestrates", not "reads header and decides").
- **Stage 2 adds a small dashed-gray "upstream feature extraction (not in this demo)" inset** outside the SoC's left edge. The 11 features arrive pre-extracted in the packet payload — a real inline IDS would add hardware feature extraction (flow tables / windowed counters) between the wire and the FIFO. We show this as a structural placeholder, not a working block.
- **Stage 5 no longer claims "ARM reads verdict and decides forward/drop"** — that policy doesn't exist on-chip; argmax happens in Python on the receiver. Stage 5 closes at "response packet leaves over the wire as a packet." The "next-mile" framing (interpretation, on-chip action policy, full ARM-side autonomous egress) is reserved for Beat 7's engineering candor.
- **Stage 5 drops "no host round-trip"** — the wire-verified round-trip is the PCI-host-assisted path; the ARM-only path is silicon-verified at BRAM level but wire-side egress hits the NF2 reference `output_queues` drain-FSM ceiling. Both are covered honestly in Beats 6 and 7.

**Capture path (user-facing notes)**: Once Claude Design returns the HTML, save it locally, open in a browser, click "Play" → screen-record the autoplay at 1920×1080 → export MP4 → drop into your video editor.

---

> 🟢 **PASTE EVERYTHING BELOW THIS LINE INTO CLAUDE DESIGN.** Do not include anything above this line. The prompt is fully self-contained — no external files, links, or codebase references are needed.

---

Create an animated 5-stage HTML diagram for an engineering demo video. The diagram is a **packet-journey walkthrough** of a custom network-processor SoC that runs inline ML-based intrusion detection. We follow one packet from ingress to verdict, revealing the chip's interior layer by layer.

## REQUIRED DIMENSIONS — 16:9 / 1920×1080 (non-negotiable)

The HTML must render with a **fixed 1920×1080 stage, 16:9 aspect ratio**. Do NOT use 4:3, 1:1, or any other aspect ratio. The stage uniformly scales to fit the browser window while preserving 16:9. All `(x, y)` positions in this prompt refer to coordinates inside the 1920×1080 stage.

Implement this with the following scaffolding pattern:

```html
<div id="stageWrap"><div id="stage"><!-- all stage content lives in here --></div></div>
```

```css
html, body { margin: 0; padding: 0; height: 100vh; overflow: hidden; background: #1a1a1a; }
#stageWrap { position: fixed; inset: 0; display: grid; place-items: center; }
#stage { width: 1920px; height: 1080px; background: #ffffff; position: relative; overflow: hidden; transform-origin: center center; }
```

```js
function fit() {
  const s = Math.min(window.innerWidth / 1920, window.innerHeight / 1080);
  document.getElementById('stage').style.transform = 'scale(' + s + ')';
}
window.addEventListener('resize', fit);
fit();
```

White stage background, dark surround. The captured screen recording will frame the white 1920×1080 stage only.

**Total runtime**: ~165–195 s autoplay. Stage 1 runs longer (~40–48 s) since it sets up the full chip + the convertible-FIFO mechanism + the GPU ISA contextualization; Stages 2-5 each run ~30–36 s. The voiceover budget for Beat 3 is 2:45–3:15.

**Talking-head overlay constraint** *(added 2026-05-10)*: This diagram will be screen-captured and composited in Clipchamp with a small circular webcam overlay at the **bottom-right corner** of the frame — approximately 400 px wide × 220 px tall, occupying the region `x = 1480..1880, y = 860..1080`. **Reserve this region**: do not place any critical diagram element (SoC content, subtitle, controls, stage counter) inside the bottom-right rectangle. Specifically:
- Keep the SoC container's bottom edge at **y ≤ 840**.
- Keep the subtitle at **y < 860** OR limit its horizontal extent to **x < 1480**.
- Keep autoplay controls and stage counter clear of the bottom-right corner (top-left or top-center is fine).
- The offline inset upper-right (`y = 60..220`) is unaffected — headshot is bottom corner only.

**Style**: Ben Eater / Branch Education clean technical educator — calm authoritative, not corporate-slick, not playful-cartoon. White background, strong color coding per block type, clear sans-serif typography, consistent arrow weights.

**Color system** (use exactly these):
- Data/artifact boxes (offline inset): fill `#f7fafc`, stroke `#4a5568`, text `#2d3748`, monospace font for filenames
- SoC container box: fill `#e8f2ff`, stroke `#2c5282`, heavy stroke width (4-6 px)
- Convertible FIFO: fill `#c6f6d5`, stroke `#2f855a`
- ARM CPU: fill `#e9d8fd`, stroke `#6b46c1`
- DMA engine: fill `#fefcbf`, stroke `#b7791f` (distinct from FIFO/ARM/GPU)
- GPU: fill `#fed7aa`, stroke `#c05621`
- Packet glyph: fill `#2b6cb0`
- Active data-flow arrows during a stage: heavy `#2d3748`, 3 px stroke, with arrowhead
- Inactive/structural arrows: light gray `#a0aec0`, 2 px stroke, with arrowhead
- Dashed cross-context arrows (offline → GPU): stroke `#6b46c1`, dashed
- Drop strike-through: `#c53030` with 3 px stroke

**Typography**:
- Stage subtitle (bottom caption): sans-serif italic, 22-26 pt, gray `#4a5568`
- Block labels (FIFO / ARM CPU / DMA / GPU): sans-serif bold, 22-24 pt
- Sub-labels inside blocks ("4 hardware threads", "4 SIMD lanes / BF16", "Mode reg: PCI · ARM · DMA"): sans-serif, 14-16 pt, slightly lighter color
- Filename labels (inset): monospace, 14-16 pt
- Stage counter top-right: sans-serif, 14 pt, gray `#718096`

---

## Layout (canvas 1920×1080)

**SoC container** — main element, occupies most of the canvas:
- Position: x ≈ 240 .. 1680, y ≈ 160 .. 820 *(bottom edge raised from 920 → 820 to clear the headshot zone)*
- Header label inside top edge: "Network Processor SoC — one FPGA" (bold, dark blue)
- Inside, three blocks arranged for packet flow:
  - **ARM CPU** at top center: x ≈ 540 .. 940, y ≈ 230 .. 380. Show 4 thread strips inside as small horizontal bars labeled "T0 T1 T2 T3". Sub-label below the block: "4 threads · fine-grained round-robin".
  - **Convertible FIFO** at center: x ≈ 540 .. 1100, y ≈ 460 .. 600. Sub-label inside: "dual-port 256 × 72 bit BRAM".
    - **Port A label**: small italic 11 pt mono tag "Port A" inside the FIFO's top-left interior corner at x ≈ 560, y ≈ 475. A short gray structural arrow (2 px, no animation) exits the FIFO left edge at y ≈ 530 and ends with a tiny italic gray label below the FIFO at x ≈ 380, y ≈ 625: "Port A → NetFPGA data path (always-on)".
    - **Port B label**: small italic 11 pt mono tag "Port B" inside the FIFO's top-right interior corner at x ≈ 1075, y ≈ 475. Port B is the muxed side — see Port B mux below.
  - **Port B mux** (new, persistent): a small 3:1 mux pictogram sitting in the gap between FIFO and DMA. Position: x ≈ 1110 .. 1165, y ≈ 465 .. 595 (55 wide × 130 tall). Drawn as a horizontal trapezoid: right edge taller (130 px), left edge shorter (60 px). Fill `#edf2f7`, stroke `#2c5282`, 1 px. Inside, three input labels stacked vertically on the right, monospace 12 pt, color `#1a365d`:
    - top: "PCI"
    - middle: "ARM"
    - bottom: "DMA"
    Output: short heavy arrow (2 px, dark gray) from the mux's left edge (x ≈ 1110, y ≈ 530) into the FIFO's right edge at y ≈ 530, landing on the Port B label. Above the mux, italic 11 pt gray tag at x ≈ 1100, y ≈ 450: "selected by Mode reg".
  - **Mode register footnote** (new, persistent): a small pale-blue rounded panel below the FIFO. Position: x ≈ 540 .. 920, y ≈ 615 .. 695 (380 wide × 80 tall). Fill `#f7fafc`, stroke `#cbd5e0` (1 px), corner radius 6 px. Title line bold 14 pt sans-serif: "FIFO_MODE register". Body (monospace 12 pt, color `#1a365d`, lines fade in left-to-right during Stage 1 reveal 3):
    ```
    0 = packet forwarding (Port B → PCI)
    1 = ARM CPU drives Port B
    2 = DMA engine drives Port B
    ```
  - **DMA engine** at center-right: x ≈ 1180 .. 1340, y ≈ 480 .. 580. A compact box, smaller than FIFO/GPU. Sub-label below: italic "1 word / cycle, pipelined".
  - **GPU** at right: x ≈ 1380 .. 1640, y ≈ 360 .. 760. Largest block (Beat 4 will zoom into it). Inside the GPU box:
    - Top: sub-label "GPU" (bold), with a small italic tag "4 SIMD · BF16/INT16"
    - Just under the top sub-label, a tiny monospace tag at 13 pt: "1024-word IMEM · 1024-word DMEM"
    - DMEM mini-block: x ≈ 1400 .. 1500, y ≈ 410 .. 460. Label "DMEM".
    - IMEM mini-block: x ≈ 1520 .. 1620, y ≈ 410 .. 460. Label "IMEM".
    - Four SIMD lane rectangles, drawn vertically inside the GPU box: x ≈ 1400 .. 1620, y ≈ 490 .. 650, divided into 4 vertical columns (each ~50 px wide). Each column labeled "L0", "L1", "L2", "L3" at the top.
    - **Layer-flow pill row** inside the GPU just below the SIMD lanes: x ≈ 1400 .. 1640, y ≈ 660 .. 685. Horizontal sequence of 4 pills connected by tiny right-arrows, monospace 12 pt, fill `#edf2f7`, stroke `#2c5282`: `[11 in]` → ReLU → `[16]` → ReLU → `[8]` → ReLU → `[2 out]`. (Connectors are short labels between pills; pills themselves carry the numbers.) These pills are static structural reveals in Stage 1; they pulse during Stage 4.
    - Pipeline tag along the bottom inside GPU: "IF → ID → EX1 → EX2 → EX3 → WB" — small horizontal sequence, 6 short pill shapes joined by tiny arrows. Position: x ≈ 1400 .. 1640, y ≈ 700 .. 745.
    - Cycle counter top-right inside GPU: small numeric readout "0 / 732 cycles" (initially "0", animates to "732" in Stage 4).
- Inside the SoC, near the bottom edge, a small italic gray label (14 pt, color `#718096`) running across center: "Two control planes — PCI bus + ARM alias window 0xF0–0xFF". Position: centered at x ≈ 760, y ≈ 795.

**Packet In** label and arrow at canvas left, entering the SoC near the FIFO row (y ≈ 530).
**Packet Out** label and arrow at canvas right, exiting the SoC near the FIFO row (y ≈ 530).

**Offline inset** — small, upper-right corner *outside* the SoC, kept at 50–60 % opacity to indicate "background context, not part of runtime data flow":
- Position: x ≈ 1700 .. 1900, y ≈ 60 .. 220
- Two small data boxes stacked vertically. Both use monospace text:
  - Top box label: "weights (BF16)"
  - Bottom box label: "program (hex)"
- Two dashed purple arrows fanning down-left from the inset into GPU DMEM and GPU IMEM respectively, with a small italic label between the inset and the SoC: "pre-loaded once at boot"

**Upstream feature-extraction inset** — small, left side *outside* the SoC, kept at 50–60 % opacity to indicate "this is the production stage that's mocked in this demo":
- Position: x ≈ 30 .. 200, y ≈ 455 .. 605 (170 wide × 150 tall, centered vertically on the FIFO row at y ≈ 530)
- One dashed-stroke rectangle, fill `#f7fafc`, stroke `#a0aec0` (gray, **dashed**, 2 px), corner radius 6 px.
- Inside the box, two text blocks stacked vertically (both horizontally centered inside the box):
  - Top block, sans-serif 14 pt, color `#4a5568`, may wrap onto two lines: "upstream feature extraction"
  - Bottom line, sans-serif italic 12 pt, color `#718096`: "(not in this demo)"
- A short dashed-gray arrow (stroke `#a0aec0`, 2 px, dashed) leaves the right edge of this inset (x ≈ 200, y ≈ 530) and points to where Packet In enters the SoC (x ≈ 240, y ≈ 530). No inline label on this arrow — the Stage 1 subtitle carries the explanation that packets arrive with 11 pre-extracted features.
- The Packet In wire from the canvas-left edge (x = 0) to the FE inset's left edge (x ≈ 30) stays the regular gray structural style — represents real packets arriving at the FPGA. The visual reading order is: real packets → (mocked stage, dashed) → SoC.

**Transient annotation regions** — per-stage callouts that fade in during a stage's reveals and fade out at the stage transition. Each region is reused across stages; only one stage owns it at a time.
- **TopLeft Panel slot** — x = 260 .. 540, y = 200 .. 420, inside the SoC top-left above the ARM block. Used in Stage 2 for the input-packet BRAM layout and in Stage 5 for the response BRAM layout. Light pale-blue fill `#f7fafc`, stroke `#cbd5e0` (1 px), corner radius 6 px. Title line in 16 pt sans-serif bold; body in 14 pt monospace.
- **ARM Right slot** — x = 950 .. 1170, y = 240 .. 380, between the ARM block and the DMA block. Used in Stage 2 for the register-readout snippet and in Stage 5 for the header-swap + drain snippet. Same panel style as TopLeft.
- **Below-DMA slot** — x = 1180 .. 1340, y = 600 .. 760, directly under the DMA block. Used in Stage 3 for the DMA-in register programming and in Stage 5 for the DMA-out register programming. Same panel style.
- All transient panels animate fade-in (250 ms after the stage's primary reveal), and inner mono lines type-out one at a time (one line every ~250 ms). At stage transition, fade out 200 ms.

**Stage counter** top-right inside the canvas: "Stage N of 5". Top-left could carry a small grayed-out title: "EE533 Final Project — Network Processor — Beat 3: Architecture" if it doesn't crowd the offline inset.

**Subtitle**: italic gray text. Position at `y = 850 .. 905` (between the SoC bottom and the headshot zone). **Left-anchored at x = 80, max width 1380 px (right edge ≤ 1460)** so it never crosses into the bottom-right headshot region. Fade transitions between stages.

**Controls**: Previous · Play · Next buttons, rounded, light border, plain text labels with simple unicode arrows. Position at `y = 930 .. 980, x = 80 .. 1460` (bottom-center-left, also clear of the headshot corner). Hidden when the `?clean=1` query param is set. Keyboard shortcuts: Left/Right arrows = Prev/Next, Space = Play/Pause.

---

## 5 animation stages

Each stage runs **~30–36 s in autoplay**. Use smooth fade-ins (300–400 ms) for newly revealed elements, brief pulses (~900 ms) to call attention, and one packet glyph that travels across the diagram beginning Stage 2.

**Stage 1 — The chip (~30–36 s)**

Stage 1 runs ~40–48 s (longer than Stages 2-5; this is the densest setup stage). Reveals in this order, ~400 ms apart:

1. SoC container with its header label.
2. ARM CPU block — including the 4 thread strips and "4 threads · fine-grained round-robin" sub-label.
3. Convertible FIFO block — including "dual-port 256 × 72 bit BRAM" sub-label, then the Port A label + structural arrow exiting the FIFO left edge with the "always-on to NetFPGA data path" tag, then the Port B label inside the FIFO right corner.
4. **Port B mux pictogram** appears in the gap between FIFO and DMA, with its three input labels (PCI / ARM / DMA) typing out one by one. The short heavy arrow from the mux's left edge into FIFO Port B fades in last, and the italic "selected by Mode reg" tag above the mux appears.
5. **FIFO_MODE register footnote panel** fades in below the FIFO. Title bar appears first, then the three semantic lines (`0 = packet forwarding`, `1 = ARM CPU drives Port B`, `2 = DMA engine drives Port B`) fade in left-to-right, ~250 ms apart. A faint structural line connects the panel title to the "selected by Mode reg" tag above the mux to make the visual relationship explicit.
6. DMA engine block with its "1 word / cycle, pipelined" sub-label.
7. GPU block — full interior (DMEM, IMEM, 4 lanes, layer-flow pill row, pipeline tag, cycle counter at 0, and the "1024-word IMEM · 1024-word DMEM" mono tag).
8. Packet In and Packet Out arrows + labels (gray, structural, no flow yet).
9. Offline inset (the two small boxes "weights (BF16)" and "program (hex)") fades in to 60 % opacity. Dashed purple arrows fade in from inset into GPU DMEM and IMEM, with "pre-loaded once at boot" label.
10. Upstream feature-extraction inset (left of SoC, dashed-gray box "upstream feature extraction" with italic "(not in this demo)") fades in to 60 % opacity, along with the short dashed-gray arrow from the inset into the SoC's Packet In point. No inline label needed — the subtitle carries the explanation.
11. The italic "Two control planes — PCI bus + ARM alias window 0xF0–0xFF" tag fades in along the bottom interior of the SoC.

No motion in the data path. Goal: viewer sees the whole chip laid out, plus the structural placeholders for what's pre-loaded and what's mocked, plus the convertible-FIFO mechanism (Port A always-on; Port B muxed by the FIFO_MODE register to PCI, ARM, or DMA), plus a glimpse of the layer flow inside the GPU.

**Subtitle**: *"One die — a convertible dual-port FIFO, a four-thread ARM CPU, a pipelined DMA engine, and a custom four-lane SIMD GPU. The FIFO is dual-port: Port A is always on, wired into the NetFPGA data path so every packet lands and exits through it; Port B is muxed by the FIFO_MODE register between the PCI bus, the ARM CPU, and the DMA engine. That mode-mux is what makes the FIFO 'convertible' — one BRAM, three accessors, no extra memory. The chip is reachable on two control planes — the PCI bus and an ARM address-alias window. Weights and the GPU program load once at boot. Upstream feature extraction is mocked — packets arrive with 11 pre-extracted features. Inside the GPU, the network shape is already visible: eleven inputs, two hidden layers, two output logits."*

**Stage 2 — Packet arrives, ARM orchestrates (~30–36 s)**

Reveals + motion:
1. A blue packet glyph (28 × 20 px rounded rect) slides in from off-canvas-left through the upstream-FE inset's path and along the Packet In arrow, into the FIFO, taking ~1.5 s. Packet remains visible inside the FIFO.
2. **TopLeft Panel slot opens** with an input-packet BRAM layout (monospace 14 pt, lines type out one at a time). Title line bold 16 pt: "FIFO BRAM — incoming". Body:
   ```
   [0]      NF2.1 header
   [1..6]   Eth + IP + UDP + pad
   [7..17]  11 features (BF16, replicated)
   [18]     trailer
   ```
   The `[7..17]` line is highlighted (italic, color `#2c5282`) to mark where the feature payload lives.
3. A short one-way control arrow appears from ARM CPU (bottom edge) down to the FIFO (top edge), labeled italic "poll + setup" in 16 pt gray. The arrow pulses briefly once. (This represents the ARM polling FIFO_STATUS and writing the FIFO_MODE register — not header parsing.)
4. ARM CPU block softly glows; one of the four thread strips (T0) lights up to indicate the orchestrator thread.
5. **ARM Right slot opens** with a register-readout snippet (monospace 14 pt). Title line bold 16 pt: "T0 (orchestrator)". Body lines type out:
   ```
   read  FIFO_STATUS
   write FIFO_MODE := 2
   ```
6. Subtitle updates.

**Subtitle**: *"Every packet lands in the FIFO. Inside the BRAM, the network headers sit at words zero through six; the eleven pre-extracted features sit at words seven through seventeen. The ARM CPU, on its orchestrator thread, polls the FIFO status register and then writes the FIFO mode register — handing port B of the dual-port BRAM over to the DMA. A production inline IDS would add upstream feature-extraction hardware between the wire and the FIFO; we're skipping that for this demo and feeding pre-extracted features directly."*

**Stage 3 — DMA streams features to GPU (~30–36 s)**

Reveals + motion:
1. ARM block pulses once (signaling DMA programming).
2. **Below-DMA slot opens** with a DMA-in register-programming callout (monospace 14 pt, lines type out one at a time). Title line bold 16 pt: "DMA program (T0 writes)". Body lines:
   ```
   DMA_FIFO_ADDR := 0x07
   DMA_GPU_ADDR  := 0x00
   DMA_LENGTH    := 11
   DMA_CTRL      := 0x01   (start · FIFO→GPU)
   poll DMA_CTRL[0] until clear
   ```
   The `DMA_CTRL := 0x01` line pulses briefly when the DMA fires; the `poll DMA_CTRL[0] until clear` line is rendered in slightly lighter gray (color `#4a5568`) and italicized to indicate it's a spin-loop rather than a single write.
3. A heavy arrow grows from FIFO → DMA, then from DMA → GPU DMEM. Label above the arrow at midpoint, italic 14 pt: "11 BF16 words · each replicated `{x,x,x,x}` across 4 SIMD lanes". Use a moving-dash style (CSS dash animation) on this arrow during the stage so the viewer can see direction of flow.
4. The GPU DMEM mini-block fills with 11 small word-slot tick marks left to right (~80 ms per slot), then settles. This makes "11 features land at DMEM[0..10]" visible.
5. The GPU IMEM mini-block briefly glows to remind viewers the program is *already* there (don't re-animate the offline inset).

**Subtitle**: *"The ARM programs the DMA engine with four register writes: source address, destination address, length, direction. The DMA pulls the eleven feature words from FIFO BRAM and pushes them into the GPU's data memory — one word per cycle, pipelined. Each feature word is a BF16 value replicated across all four SIMD lanes, since the deployed kernel works in lane-replicated mode."*

**Stage 4 — GPU classifies (~32–38 s)**

Reveals + motion:
1. **TopLeft Panel slot opens** with a GPU ISA reference card (monospace 13 pt, lines type out one at a time, ~150 ms per line). Title line bold 16 pt: "GPU ISA — 12 opcodes". Body lines:
   ```
   LD    ST    ADD   SUB
   MUL   FMA   RELU  MOV
   ADDI  MOVI  BLT   BGE
   HALT  BCAST (custom)

   16 × 64-bit regs · 6-stage pipe
   IMEM 1024 w · DMEM 1024 w
   ```
   The `BCAST (custom)` line is highlighted (italic, color `#c05621`) to flag it as the project's contribution.
2. The 4 SIMD lane rectangles inside the GPU light up in a staggered wave (L0 → L1 → L2 → L3, ~200 ms apart) and then continue to pulse softly throughout the stage to signal active computation.
3. The 6-stage pipeline tag at the bottom of the GPU has each pill highlight in a rolling pattern (IF → ID → EX1 → EX2 → EX3 → WB), suggesting the pipeline is flowing.
4. The **layer-flow pill row** (already structurally visible from Stage 1) pulses in sequence — L1 pill `[16]` lights, then L2 pill `[8]`, then L3 pill `[2 out]`. The wave repeats slowly throughout the stage to suggest "the network is being computed layer by layer."
5. The cycle counter inside the GPU animates from `0` to `732` over ~5 s, with a tabular-nums font so digits don't jitter. After it lands on `732`, a small italic 13 pt gray tag appears just below the counter readout: "732 cy · with BCAST · Beat 4 covers the design".
6. At the end of the stage, a "verdict" badge appears just below the IMEM mini-block at x ≈ 1520 .. 1640, y ≈ 470 .. 545. Two-line monospace block (16 pt), drawn inside a light pale-blue rounded rectangle (fill `#f7fafc`, stroke `#cbd5e0`):
   ```
   normal:  -5.50
   attack:  +8.81  ← argmax
   ```
   The `← argmax` arrow is italic red `#c53030` to draw the eye. Below the badge, a small italic 13 pt gray caption: "real values from a NetFPGA attack run".

**Subtitle**: *"Four SIMD lanes, BF16. The GPU is a real programmable processor — twelve opcodes, sixteen 64-bit registers, six-stage pipeline. It runs the eleven-sixteen-eight-two fully-connected network with ReLU between layers, working layer by layer through the SIMD pipeline. A hardware cycle counter on the FPGA reads exactly seven hundred and thirty-two cycles for the full classification — that's with our custom BCAST instruction, which Beat 4 covers in detail. The output is two BF16 logits in DMEM: a normal score and an attack score. For this packet, the attack score wins clearly."*

**Stage 5 — Response packet out (~30–36 s)**

Reveals + motion:
1. ARM block pulses once (signaling DMA-out programming).
2. **Below-DMA slot reopens** (Stage 3's panel content is replaced) with the DMA-out register-programming callout (monospace 14 pt, lines type out one at a time). Title line bold 16 pt: "DMA program (T0 writes)". Body:
   ```
   DMA_FIFO_ADDR := 0x0A
   DMA_GPU_ADDR  := 0x7E
   DMA_LENGTH    := 2
   DMA_CTRL      := 0x03   (start · GPU→FIFO)
   poll DMA_CTRL[0] until clear
   ```
   The `poll DMA_CTRL[0] until clear` line is rendered in slightly lighter gray (color `#4a5568`) and italicized — same convention as Stage 3 — to indicate it's a spin-loop.
3. A heavy arrow appears from GPU DMEM back through the DMA block into the FIFO, label italic "2 BF16 logits" in 16 pt. Use the same moving-dash style as Stage 3 (`stroke-dasharray: 8 6` + dashMove animation) so direction of flow is unmistakable — dashes move from right (GPU) to left (FIFO). Path: GPU DMEM left edge (≈ x = 1400) → DMA right edge (≈ x = 1340), then DMA left edge (≈ x = 1180) → FIFO right edge (≈ x = 1100). Both segments point leftward.
4. **TopLeft Panel slot reopens** (Stage 2's panel content is replaced) with the response BRAM layout (monospace 14 pt). Title line bold 16 pt: "FIFO BRAM — response". Body:
   ```
   [0]       NF2.1 hdr (rewritten)
   [1..6]    Eth + IP + UDP (src ↔ dst swap)
   [10..11]  2 BF16 logits
   ```
   The `[10..11]` line is highlighted (italic, color `#2c5282`) to mark where the verdict lives.
5. **ARM Right slot reopens** with the response-framing register snippet (monospace 14 pt). Title line bold 16 pt: "T0 (orchestrator)". Body lines:
   ```
   rewrite BRAM[1..6] hdrs
   FIFO_MODE  := 1
   FIFO_DRAIN := 1
   ```
6. ARM block pulses again with a small italic 14 pt gray callout near it: "swap MAC + IP src ↔ dst, write UDP ports".
7. The packet glyph (still in FIFO from Stage 2) glides right along the Packet Out arrow toward the right edge and exits the canvas cleanly. **No strike-through, no ATTACK/NORMAL badge** — the on-chip pipeline only produces the two-logit verdict packet; interpretation lives downstream.
8. Final soft full-diagram glow (300–400 ms) to signal closing of the walkthrough.

**Subtitle**: *"The GPU has written two BF16 logits into its data memory; the ARM programs the DMA in the reverse direction to copy them back into the FIFO. Then the ARM rewrites the response packet's headers in BRAM — swapping source and destination on Ethernet, IP, and UDP — flips the FIFO mode register back to ARM mode, and drains the FIFO. The verdict packet leaves over the wire. What happens to that verdict downstream — who interprets it, who acts on it — is covered in the next two beats."*

---

## Animation polish

- All reveals use a 300 ms ease-out fade + 8 px upward slide.
- Pulses use a 900 ms `pulse-ring`-style animation (stroke pulses out then fades).
- The DMA stream arrow in Stage 3 uses a moving CSS dash (`stroke-dasharray: 8 6` + `animation: dashMove 1.2s linear infinite`) — direction of dashes implies flow from FIFO toward GPU DMEM.
- Cycle counter animation in Stage 4: `requestAnimationFrame` loop incrementing the displayed integer from 0 to 732 over ~5 s, then holds at 732 for the remainder of the stage.
- Offline inset stays at 60 % opacity throughout (never lights up); the dashed purple arrows also stay subdued.

## Interactivity

- **Play button**: auto-advances all 5 stages with stage-specific pauses (Stage 1: 42 s · Stages 2-5: 32 s each — total ≈ 170 s) by default. All five per-stage durations are configurable via `?s1=42000&s2=32000&s3=32000&s4=32000&s5=32000` query params (defaults match the values above). When autoplay finishes, remains on Stage 5. Pressing Play again rewinds and replays.
- **Capture mode**: support a `?clean=1` query parameter that hides the Prev/Play/Next controls and reduces the stage counter to a small subtle marker (or hides it entirely). This is used when screen-recording the autoplay to avoid UI chrome in the captured MP4.
- **Previous / Next buttons**: manual stepping, each transition ~300 ms fade.
- Keyboard: Left = Previous, Right = Next, Space = Play/Pause.
- Stage counter top-right: "Stage N of 5".
- No tooltips, no hover-only effects, no sounds.
- When stepping back manually, hide all elements newer than the chosen stage but keep prior reveals visible (i.e. Stage 3 should look like the end-state of Stage 3, with all Stage 1+2+3 reveals present).

## Output

A single self-contained HTML artifact (one file) that I can open in any modern browser, click Play to autoplay the full 2-minute sequence, screen-record at 1920×1080, or step through manually for screenshots. No external assets — all SVG inline, CSS inline, JavaScript inline.

---

## Design intent

This diagram is meant to be a self-contained architecture walkthrough that anchors the claim "the inspection pipeline runs on one die" and shows how a packet actually moves through the silicon. The headline takeaway is the closing flow: GPU writes the two-logit verdict → DMA + ARM frame the response → verdict leaves over the wire as a packet. Two structural placeholders (offline inset upper-right at 60 % opacity; upstream feature-extraction inset on the left at 60 % opacity) honestly mark what's pre-loaded and what's mocked.

Things deliberately excluded — do not add: individual register addresses, PCI bus details, MAC0/MAC1 ingress port numbers, instruction-level GPU implementation details, dual-port BRAM port-A/port-B mux details, power or process-node projections, on-chip forward/drop action policy (does not exist in this build), on-chip verdict interpretation (argmax happens in the receiver, not on-die), or any text outside what's specified in the stage definitions above.

