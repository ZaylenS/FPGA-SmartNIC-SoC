# Claude Design Prompt — Deck 3: Beat 4 BCAST Story (Final Demo Video)

**Drafted 2026-05-11.** For the final project demo video. Beat 4 in the outline; budget ~2:20 of voiceover. This deck tells the story of the **BCAST instruction** — a custom cross-lane broadcast opcode we added to our GPU's ISA to unlock 4-lane SIMD parallelism for multi-layer neural-network inference.

**Goes deeper than the Apr 28 live-presentation BCAST clip on purpose.** The Apr 28 version was deliberately Q&A-narrow (no pipeline-stage placement, no encoding format, no kernel-loop snippets, no LUT cost). For an asynchronous demo video to TAs, on-screen depth is welcome — TAs should finish Beat 4 thinking "OK, they actually built an ISA modification and understood the trade-offs."

**Where it fits in the final cut**:

```
Beat 3 architecture deck  →  (Beat 4 BCAST deck, this one)  →  Beat 5 live inference  →  ...
        ~2:50                          ~2:20                        ~1:30
```

**Capture path (user-facing notes)**: Paste below the marker into Claude Design, iterate to taste, save the returned HTML locally, open in a browser with `?clean=1` appended to the URL to hide controls, click Play, screen-record at 1920×1080, save the MP4 to your local demo-video folder as `beat4_bcast.mp4`.

**Sibling visual identity (user-facing note)**: This deck shares its color palette and panel conventions with the Beat 3 architecture deck and the Deck 1 intro deck — same orange/green/blue/red codes, same pale-blue transient panels, same Ben-Eater-style technical-educator look. The three decks should feel like one continuous visual identity in the final cut.

---

> 🟢 **PASTE EVERYTHING BELOW THIS LINE INTO CLAUDE DESIGN.** Do not include anything above this line. The prompt is fully self-contained — no external files, links, or codebase references are needed.

---

Create an animated **6-stage HTML deck** for the technical walkthrough of a custom GPU instruction called **BCAST** — a cross-lane broadcast operation. The deck tells the story across six beats: (1) the problem — wasted SIMD lanes in scalar mode; (2) the architectural gap — no instruction to replicate one lane across all lanes; (3) the hardware fix — a 4:1 mux placed in the EX1 pipeline stage; (4) the ISA fix — a new opcode in the 32-bit encoding; (5) the kernel transformation — inner-loop rewrite that goes from 2-neuron to 4-neuron parallel; (6) the result — silicon-measured 3.28× speedup.

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

**Total runtime**: ~140–150 s autoplay (6 stages × ~22–26 s each). The voiceover budget for Beat 4 is ~2:20.

**Talking-head overlay constraint**: this deck will be screen-captured and composited with a small circular webcam overlay at the **bottom-right corner** of the frame — approximately 400 px wide × 220 px tall, occupying `x = 1480..1880, y = 860..1080`. **Reserve this region** — do not place any critical content (stage title, datapath block, encoding diagram, bar chart, callout) inside the bottom-right rectangle. Specifically:
- Keep all stage content inside `x = 0..1460, y = 80..820`.
- Subtitle stays at `y = 850..905`, left-anchored at `x = 80`, max width 1380 px (right edge ≤ 1460).
- Autoplay controls and stage counter stay clear of the bottom-right corner.

**Style**: Ben Eater / Branch Education clean technical educator — calm authoritative, not corporate-slick, not playful-cartoon. White background, strong color coding per block type, clear sans-serif typography, consistent arrow weights, monospace for code/registers/encoding fields.

## Color system (use exactly these)

- **SIMD lane (active)**: fill `#fed7aa`, stroke `#c05621` (orange — the GPU's signature color in the rest of the video)
- **SIMD lane (wasted, scalar mode)**: fill `#edf2f7` with diagonal gray hatching, stroke `#a0aec0`. Label "wasted" stamped diagonally inside.
- **BCAST itself / the project's own addition**: fill `#c6f6d5`, stroke `#2f855a`, heavy 3 px stroke (green — signals "this is what we added")
- **Inter-layer barrier (Stage 2 only)**: fill `#fed7d7`, stroke `#c53030`, heavy 4 px stroke, with bold red "NO INSTRUCTION" text
- **Distinct-neuron lane pastels** (Stage 2's Layer N output `{h3, h2, h1, h0}`): lane 0 blue `#bee3f8`, lane 1 green `#c6f6d5`, lane 2 yellow `#faf089`, lane 3 pink `#fed7e2`, each with a matching darker stroke
- **Register file / ALU block boxes** (Stage 3 datapath): fill `#f7fafc`, stroke `#4a5568`
- **Pipeline-stage tag** (e.g. "EX1 stage"): fill `#edf2f7`, stroke `#2c5282`, mono text inside
- **Encoding bit-field cells** (Stage 4): alternating fill `#f7fafc` and `#edf2f7`, stroke `#4a5568` (1 px). Bit-position labels in 11 pt mono gray above the cells.
- **Assembly mnemonic blocks**: fill `#f7fafc`, stroke `#cbd5e0` (1 px, subtle), corner radius 6 px. Mono text inside, color `#2d3748`.
- **Bar chart**: "before" bar fill `#fc8181` / stroke `#c53030`; "after" bar fill `#68d391` / stroke `#2f855a`
- **Highlight callouts / numerical reveals**: fill `#e8f2ff`, stroke `#2c5282`, heavy stroke
- **Subtitle text**: italic gray `#4a5568`
- **Stage counter**: small, gray `#718096`

## Typography

- Stage title at top of canvas: sans-serif bold, 36 pt, color `#1a365d`
- Block labels (Register File / 4:1 lane mux / SIMD ALUs): sans-serif bold, 22 pt
- Lane values inside SIMD register strips: monospace, 20 pt
- Register notation (R1, R3, `{h0, h0, h0, h0}`): monospace, 18 pt
- Bit-field position labels (31..27, 26..23, etc.): mono, 11 pt, gray
- Bit-field cell values (`11010`, `dest`, `source`, etc.): mono bold, 14 pt
- Assembly mnemonics (e.g., `BCAST R3, R1, 0`): mono, 16–18 pt
- Subtitles (bottom captions): sans-serif italic, 22–26 pt, gray `#4a5568`
- Stage counter top-right: sans-serif, 14 pt, gray `#718096`
- Resource callouts (`+65 LUTs · ~0.1 %`, `25 % SIMD utilization`): sans-serif, 14 pt, color `#1a365d` on light-blue background
- Big numeric reveals (2402, 732, 3.28×): sans-serif bold, 56 pt, tabular-nums
- Bar-chart axis labels: sans-serif, 14 pt, gray `#4a5568`

---

## Layout principles (apply across all stages)

- **Safe content zone**: `x = 0..1460, y = 80..820` (1460 × 740 px). Everything important lives here.
- **Stage title slot**: top of canvas, `x = 80..1380, y = 36..96`, sans-serif bold 36 pt, color `#1a365d`, left-aligned.
- **Subtitle slot**: `y = 850..905, x = 80..1460`, italic 22–26 pt, gray `#4a5568`, left-anchored.
- **Stage counter**: top-right inside the canvas at `x = 1380..1460, y = 36..66`, gray 14 pt: "Stage N of 6".
- **Controls** (Previous / Play / Next): `y = 930..980, x = 80..1460`, hidden when `?clean=1` query param is set.
- Centered content stages: center horizontally on `x = 730` (= 1460 / 2), not on `x = 960`, because the right side is bounded by 1460.
- Generous whitespace between major elements. Don't fill the whole safe zone.

---

## 6 animation stages

Each stage uses 350–500 ms ease-out fade-in on appearing elements, with sophisticated motion (slide-up, scale-in from 0.95, letter-by-letter or value-by-value where appropriate). Use `cubic-bezier(0.2, 0.7, 0.3, 1)` for entrance, `cubic-bezier(0.4, 0, 0.2, 1)` for exits. No `linear` easing.

### Stage 1 — The waste (scalar mode), ~22 s

**Layout**: stage title at top, four large lane rectangles centered, callouts below.

**Reveals**:
1. **Stage title** at `y = 36`: "The waste — scalar mode". Fade-in.
2. **A register strip labeled `R3` at center** appears. The strip is one horizontal block 1100 px wide × 130 px tall, centered at `x = 730, y = 240..370`. It is divided into 4 equal-width lane cells, each ~270 px wide, separated by 4 px white gaps. Each lane cell carries a centered monospace label `x[i]` — representing one input feature value, pre-replicated across all four SIMD lanes in scalar-mode data layout. Reveal cells left-to-right ~150 ms apart. Above the strip, italic 14 pt gray annotation: "scalar-mode layout — R3 = {x[i], x[i], x[i], x[i]}".
3. **Lane 0** (leftmost cell) is colored as **active**: fill `#fed7aa`, stroke `#c05621`. Lanes 1, 2, 3 are colored as **wasted**: fill `#edf2f7` with diagonal gray hatching (CSS `repeating-linear-gradient` at 45° with 6 px stripes), stroke `#a0aec0`. Each wasted lane has the word **"wasted"** stamped diagonally across it in 22 pt italic gray.
4. **Lane labels** below the strip at `y = 380`: "Lane 0", "Lane 1", "Lane 2", "Lane 3", each centered under its cell, sans-serif 16 pt. Lane 0's label is bold and orange `#c05621`.
5. **Utilization badge** at `y = 440..490, x = 540..920` (centered): pale-blue rounded rectangle (fill `#e8f2ff`, stroke `#2c5282`, 2 px). Inside, two stacked lines:
   - Top line, sans-serif bold 20 pt color `#1a365d`: "25 % SIMD utilization"
   - Bottom line, mono italic 14 pt color `#4a5568`: "data layout: R = {v, v, v, v} — BF16 replicated"
6. **Scalar inner-loop snippet** at `y = 560..760, x = 80..1380`: a monospace 16 pt code block (fill `#f7fafc`, stroke `#cbd5e0`, 1 px, corner radius 6 px, padding 16 px). Lines fade in top-to-bottom, ~200 ms each. Show 5 lines:
   ```
   LD   R3, 0(R9)        ; load input, all 4 lanes get {v,v,v,v}
   LD   R2, 0(R8)        ; load weight, all 4 lanes get {w,w,w,w}
   FMA  R1, R2, R3, R1   ; all 4 lanes compute the SAME thing
   ; ...
   ; 14 cycles → 2 neurons → 7 cy/neuron
   ```
   The first three lines are color-coded in standard mono (`#2d3748`). The trailing comments are italic gray. The last metrics line is bold.

**Subtitle**: *"Our GPU has a four-lane SIMD datapath. Every arithmetic instruction operates element-wise across all four lanes. But the base ISA has no cross-lane operations — no broadcast-from-register, no horizontal sum, no shuffle. So for a multi-layer neural network, the kernel falls back to scalar mode: every value is pre-replicated across all four lanes, and three of four lanes compute redundantly."*

### Stage 2 — The inter-layer barrier, ~24 s

**Layout**: two register strips stacked vertically with a thick red barrier between them; ghosted broken arrow showing the impossible move.

**Reveals**:
1. **Stage title** at `y = 36`: "The inter-layer barrier". Fade-in.
2. **Top register strip — "Layer N output (R1)"**: same dimensions as Stage 1's strip, centered at `x = 730, y = 200..330`. 4 lane cells. Each cell shows a different labeled value in monospace 22 pt: from left to right, `h3`, `h2`, `h1`, `h0`. Each cell is colored a distinct pastel: lane 0 (leftmost) blue `#bee3f8` / stroke `#3182ce`; lane 1 green `#c6f6d5` / stroke `#2f855a`; lane 2 yellow `#faf089` / stroke `#b7791f`; lane 3 pink `#fed7e2` / stroke `#b83280`. Above the strip, italic 16 pt gray label: "Layer N output, R1 = {h3, h2, h1, h0}". Reveal cells left-to-right.
3. **Inter-layer barrier**: a thick red horizontal bar at `y = 380..440, x = 180..1280`, fill `#fed7d7`, stroke `#c53030`, 4 px. Inside the bar, centered: bold 26 pt red "NO INSTRUCTION". Below the bar (overlapping its bottom edge slightly), italic 16 pt gray subtext at `y = 450`: "cross-lane replicate unavailable in the base ISA". Reveal with a brief 250 ms scale-up bounce.
4. **Bottom register strip — "Layer N+1 input (R3) needed"**: same dimensions, centered at `x = 730, y = 510..640`. 4 lane cells, all colored the same blue (`#bee3f8`, stroke `#3182ce` — matching the lane-0 pastel from the top strip). Each cell shows `h0` in mono 22 pt. Below the strip, italic 16 pt gray label: "Layer N+1 needs R3 = {h0, h0, h0, h0}". Reveal cells left-to-right.
5. **Ghosted impossible arrow**: a curved dashed arrow (stroke `#a0aec0`, 2 px, dashed) tries to go from the top strip's lane 0 (`h0` cell, at x ≈ 460, y = 330) down through the barrier to the bottom strip's four lanes. At the barrier line, the arrow ends with a red "✕" symbol (24 pt bold, color `#c53030`). The arrow is at 50 % opacity to signal "this can't happen."
6. **Right-side enumeration callout** at `x = 1320..1430, y = 200..640`: a narrow pale-blue panel (fill `#e8f2ff`, stroke `#2c5282`). Title bold 14 pt: "Base ISA can:". Body lines mono 13 pt:
   ```
   MOVI Rd, #imm
   → all 4 lanes = imm
   (broadcasts a CONSTANT,
    not a register value)
   ```
   Then a divider line, then title "Base ISA cannot:". Body:
   ```
   broadcast from register
   horizontal sum
   lane shuffle
   ```

**Subtitle**: *"Multi-layer neural networks need each scalar output of layer N broadcast across all four lanes as input to layer N+1. Our base ISA had no instruction to extract one lane of a register and replicate it. The only existing broadcast — MOVI — replicates a compile-time constant, not a register value. So the kernel was stuck in scalar mode."*

### Stage 3 — The hardware fix: a 4:1 mux in EX1, ~26 s

**Layout**: datapath block diagram horizontally laid out, with pipeline-stage tag at top and resource callout below.

**Reveals**:
1. **Stage title** at `y = 36`: "The hardware fix — a 4:1 lane mux in EX1". Fade-in.
2. **Pipeline-stage tag** at `y = 120..170, x = 80..400`: small rectangle (fill `#edf2f7`, stroke `#2c5282`, 1 px, corner radius 4 px). Inside, two-line label:
   - Line 1, mono bold 14 pt: "GPU pipeline stage"
   - Line 2, mono 13 pt: "IF → ID → **EX1** → EX2 → EX3 → WB"
   The `EX1` is colored orange `#c05621` and bold to indicate "this is where the fix lives." Reveal fade-in.
3. **Datapath block A — Register File** at `x = 120..360, y = 280..480`. Rounded rectangle, fill `#f7fafc`, stroke `#4a5568`, 2 px. Inside, label bold 20 pt at top: "Register file". Below the label, a mono mini-register at the center: `R1 = {h3, h2, h1, h0}` — with four micro-lane cells, each colored its distinct Stage-2 pastel (blue/green/yellow/pink). Reveal scale-in.
4. **Heavy structural arrow** from Block A's right edge to the next block, `x = 360..560, y = 380`. Stroke `#2d3748`, 3 px, with arrowhead.
5. **Datapath block B — BCAST 4:1 lane mux** at `x = 580..880, y = 220..540`. This is **the addition**, highlighted: rounded rectangle, fill `#c6f6d5`, stroke `#2f855a`, **3 px**, with a subtle glow (`box-shadow: 0 0 16px rgba(47, 133, 90, 0.3)`). Inside:
   - Top label bold 22 pt color `#1a365d`: "4:1 lane mux"
   - Below the label, a small mux pictogram: trapezoid (wider on left where 4 input lines enter, narrower on right where 1 output exits). Inside the trapezoid, four short horizontal input lines labeled top-to-bottom `lane 0`, `lane 1`, `lane 2`, `lane 3` (mono 12 pt). One output line on the right.
   - Above the trapezoid, a **lane-select control input** comes in from above: a thin vertical wire at the trapezoid's top labeled "lane select" in italic 13 pt gray. The wire's input value cycles gently: 0 → 1 → 2 → 3 → 0 (mono bold 14 pt color `#1a365d`, changes every ~1.2 s).
   - Below the pictogram, italic 13 pt gray annotation: "ALU_BCAST = 4'd6"
6. **Heavy structural arrow** from Block B's right edge to the next block, `x = 880..1080, y = 380`. Stroke `#2d3748`, 3 px, with arrowhead. Above the arrow, mono 14 pt label: "effective_a = {Rs[lane], Rs[lane], Rs[lane], Rs[lane]}"
7. **Datapath block C — 4 SIMD ALUs** at `x = 1100..1380, y = 280..480`. Rounded rectangle, fill `#f7fafc`, stroke `#4a5568`, 2 px. Inside, label bold 20 pt at top: "4 SIMD ALUs". Below the label, four small ALU icons in a horizontal row (each ~50 × 50 px, rounded squares with small `Σ` symbol inside, mono 18 pt). Below the row, mono 16 pt: `result = {h0, h0, h0, h0}` (assuming lane select = 0). Reveal scale-in.
8. **Resource callout** at `y = 580..680, x = 540..920` (centered below the mux): pale-blue rounded rectangle (fill `#e8f2ff`, stroke `#2c5282`, 2 px). Three-line monospace 14 pt body:
   ```
   placement: EX1 stage (before per-lane ALU dispatch)
   cost: +65 LUTs · ~0.1 % of XC2VP50
   flip-flops added: 0   (purely combinational)
   ```
9. **Bottom italic note** at `y = 720..760, centered`: small gray italic 14 pt: "the only correct location — per-lane ALUs cannot see other lanes' data".

**Subtitle**: *"The fix is a 4:1 lane mux placed in EX1, before the per-lane ALU dispatch. When the opcode is BCAST, the mux selects one lane from the source register and replicates it to all four output lanes; the per-lane ALUs then pass the value through. Sixty-five lookup tables added — about a tenth of a percent of the chip — and no new flip-flops."*

### Stage 4 — The ISA fix: a new opcode, ~24 s

**Layout**: 32-bit encoding diagram at top, assembly syntax in the middle, two example encodings below.

**Reveals**:
1. **Stage title** at `y = 36`: "The ISA fix — opcode 5'b11010". Fade-in.
2. **32-bit encoding diagram** centered at `x = 180..1280, y = 160..320`: a horizontal row of 7 cells representing the bit-field layout. Each cell has alternating fill (`#f7fafc` and `#edf2f7`), stroke `#4a5568` (1 px). Above each cell, the bit positions in mono 11 pt gray. Inside each cell, the field name in mono bold 14 pt + the value in mono 18 pt. Cell widths proportional to bit widths.
   ```
   [31:27]  [26:23]  [22:19]  [18:15]  [14:12]  [11:2]    [1:0]
   opcode   rd       rs1      0000     dtype    unused    lane
   11010    dest     source   (zero)   (unused) (zero)    0..3
   ```
   Reveal cells left-to-right ~120 ms apart.
3. **Field-callout arrows** at `y = 340..420`. Three small arrows pointing from below the encoding row to specific fields:
   - One pointing to `[31:27]` with label below: "new opcode allocated in unused 5'b11010 slot"
   - One pointing to `[18:15]` with label below: "rs2 = 0 — hardwired to R0, avoids false hazard stalls"
   - One pointing to `[1:0]` with label below: "lane select carried in func bits — 2-bit immediate"
   Labels are italic 13 pt gray, centered under each arrow.
4. **Assembly syntax box** centered at `x = 480..980, y = 460..560`: rounded rectangle (fill `#c6f6d5`, stroke `#2f855a`, 2 px). Inside, mono bold 22 pt centered: `BCAST Rd, Rs1, lane    (lane = 0..3)`. Above the box, italic 14 pt gray: "assembly syntax". Reveal fade + slight scale-up.
5. **Two example encodings** at `x = 240..1220, y = 620..760`: a 2-row table. Header row mono 14 pt bold: "assembly" | "hex encoding" | "lane = ?". Two data rows:
   - `BCAST R3, R1, 0` | `0xD1880000` | lane 0
   - `BCAST R3, R1, 2` | `0xD1880002` | lane 2
   Mono 16 pt. Cell borders subtle (stroke `#cbd5e0`, 1 px). Reveal rows top-to-bottom.
6. **Bottom-right callout** at `x = 1080..1380, y = 460..560` (small panel): "pipeline latency: 2 cycles (EX1 → EX2)" in mono 14 pt. Italic subtext: "same as MOV". Pale-blue background.

**Subtitle**: *"The new opcode lives in slot binary 11010 — the twelfth opcode in the GPU's instruction set. The lane select is encoded in the bottom two bits of the func field — reusing existing instruction bits, so no new control signal width was needed. Two-cycle latency through EX1 and EX2 — the same as a MOV. Two example encodings, hand-assembled, are right there at the bottom."*

### Stage 5 — The kernel transformation: scalar → BCAST, ~26 s

**Layout**: side-by-side inner-loop comparison, before on left, after on right; metrics row at the bottom.

**Reveals**:
1. **Stage title** at `y = 36`: "The kernel — 2-neuron → 4-neuron parallel". Fade-in.
2. **Left panel — "before (scalar mode)"** at `x = 80..720, y = 140..680`. Rounded rectangle (fill `#fef5f5` very light red tint, stroke `#fc8181`, 2 px). Top label bold 18 pt color `#c53030`: "before — scalar mode, 2-neuron interleave". Body — monospace 14 pt code block, lines fade in top-to-bottom (~150 ms each):
   ```
   loop:
     LD   R2, 0(R8)        ; weight neuron A
     LD   R3, 0(R9)        ; input  {x, x, x, x}
     ADD  R9, R9, R7
     LD   R4, S(R8)        ; weight neuron B (stride S)
     FMA  R1, R2, R3, R1   ; neuron A
     FMA  R5, R4, R3, R5   ; neuron B
     ADD  R8, R8, R7
     BLT  R9, R12, loop
   ```
   Below the code, mono italic 14 pt gray bullets:
   - "14 cycles per iteration · 2 neurons · 7.0 cy / neuron"
   - "SIMD utilization: 25 %"
   - "DMEM layout: every word = {v, v, v, v} — 4× memory waste"
3. **Right panel — "after (BCAST mode)"** at `x = 760..1400, y = 140..680`. Rounded rectangle (fill `#f0fff4` very light green tint, stroke `#68d391`, 2 px). Top label bold 18 pt color `#2f855a`: "after — BCAST, 4-neuron parallel". Body — monospace 14 pt code block, lines fade in top-to-bottom (~150 ms each), staggered to start ~600 ms after the left panel:
   ```
   loop:
     LD    R3, 0(R9)        ; scalar input (lane 0 only)
     LD    R2, 0(R8)        ; packed weights {w3, w2, w1, w0}
     ADD   R9, R9, R7
     ADD   R8, R8, R7
     BCAST R3, R3, 0        ; broadcast lane 0 → all 4 lanes
     FMA   R1, R2, R3, R1   ; 4 neurons in parallel
     BLT   R9, R12, loop
   ```
   The `BCAST` line is highlighted: light-green background (`#c6f6d5`) with a brief 800 ms pulse on first reveal. Below the code, mono italic 14 pt gray bullets:
   - "14 cycles per iteration · 4 neurons · 3.5 cy / neuron"
   - "SIMD utilization: 100 %"
   - "DMEM layout: weights packed 4-per-word — 3.5× memory reduction"
4. **Center separator** at `x = 720..760, y = 140..680`: a vertical "→" arrow with curved shape (CSS-styled), color `#2c5282`, 3 px stroke. Above the arrow, small italic 14 pt gray: "kernel rewrite". Reveal fade-in after both panels are visible.
5. **Bottom metrics row** at `y = 720..790, x = 80..1380`: a horizontal pale-blue panel (fill `#e8f2ff`, stroke `#2c5282`, 2 px) containing three large numeric stats side-by-side. Each stat is two-line: number on top (sans-serif bold 32 pt color `#2c5282`), label below (sans-serif 14 pt gray). Stats fade in left-to-right with 200 ms staggers:
   - "2 → 4" / "neurons per loop iteration"
   - "7.0 → 3.5" / "cycles per neuron (2× improvement)"
   - "25 % → 100 %" / "SIMD utilization"

**Subtitle**: *"One new instruction reshapes the inner loop. The scalar version interleaved two neurons across the 4-lane SIMD to hide load-to-FMA stalls; the BCAST version packs four neurons' weights into one register, broadcasts the shared input across lanes, and computes all four neurons in parallel from a single FMA. Same fourteen cycles per iteration, twice the work — a 2× per-neuron improvement, and SIMD utilization jumps from 25 % to 100 %."*

### Stage 6 — The result, ~22 s

**Layout**: centered two-bar chart with the speedup label floating between; per-layer breakdown table below; closing badge.

**Reveals**:
1. **Stage title** at `y = 36`: "The result — 2402 → 732 cycles on silicon". Fade-in.
2. **Two-bar chart centered** at `x = 360..1100, y = 140..540`. White panel with subtle border (stroke `#e2e8f0`). Y-axis runs 0..2500 cycles (no tick labels, just a clean line). Two bars:
   - Left bar at `x = 480..600`, height proportional to 2402 / 2500 = 96 % of the chart's vertical range. Fill `#fc8181`, stroke `#c53030`, 2 px. Bar value label atop the bar at `y = 160..200`: bold 38 pt color `#c53030` tabular-nums: "2402". X-axis label below the bar: bold 16 pt: "before — scalar mode".
   - Right bar at `x = 860..980`, height proportional to 732 / 2500 = 29 % of the chart's range. Fill `#68d391`, stroke `#2f855a`, 2 px. Bar value label atop the bar at `y = 380..420`: bold 38 pt color `#2f855a` tabular-nums: "732". X-axis label below the bar: bold 16 pt: "after — with BCAST".
   - Animate both bars growing upward from 0 over ~1.2 s (ease-out). Value labels count up: left bar 0 → 2402, right bar 0 → 732.
3. **Speedup callout** floating between the bar tops: at `x = 660..820, y = 260..330`, a curved arrow drawn from the left bar's top to the right bar's top, with a centered floating label at the apex: bold 56 pt sans-serif color `#2c5282` tabular-nums: "3.28×". Reveal: arrow draws first (left to right, ~600 ms), then label scale-in with brief glow.
4. **Per-layer breakdown table** at `y = 580..720, x = 200..1260`. Compact table (fill `#f7fafc`, stroke `#cbd5e0`, 1 px). Header row sans-serif bold 14 pt: " " | "Layer 1 (11→16)" | "Layer 2 (16→8)" | "Layer 3 (8→2)" | "Total". Two data rows, mono 16 pt:
   ```
   scalar mode   1328 cy   944 cy   124 cy   2402 cy
   with BCAST     664 cy   646 cy   124 cy    732 cy
   ```
   The Layer 3 column is highlighted (background tint `#fefce8` yellow) and the matching `124 cy` cells in both rows are bold; a small italic 12 pt gray annotation underneath the table reads: "Layer 3 doesn't speed up — only 2 output neurons, can't fill 4 lanes."
5. **Bottom verification badge** at `y = 760..810, x = 240..1220`: a horizontal slim pale-blue strip (fill `#e8f2ff`, stroke `#2c5282`, 1 px). Two-line centered content. Top line mono 14 pt: `hardware-verified · measured via the GPU cycle-counter register exposed at offset 0x30`. Bottom line italic 13 pt gray: "five consecutive silicon runs · stable at 732 cycles · no jitter".

**Subtitle**: *"Three-point-two-eight times faster on the eleven-sixteen-eight-two intrusion-detection classifier — measured cycle-exact on the FPGA. Layer one and layer two both roughly halve. Layer three doesn't change — only two output neurons, four lanes, the math doesn't help there. A single new opcode, sixty-five lookup tables, and a kernel rewrite — that's what owning the GPU end-to-end lets you do."*

---

## Animation polish

- All reveals use easing curves like `cubic-bezier(0.2, 0.7, 0.3, 1)` for entrance, `cubic-bezier(0.4, 0, 0.2, 1)` for exits. Avoid `linear`.
- Bar growth in Stage 6 uses `cubic-bezier(0.3, 0.0, 0.4, 1)` over ~1.2 s. Value labels count up via `requestAnimationFrame` with ease-out.
- Code-block line reveals (Stages 1 and 5) use a brief 250 ms fade + 4 px upward slide per line.
- Number count-ups use `requestAnimationFrame` with ease-out; show no fractional digits unless they exist (e.g., 3.28, 7.0).
- Stage transitions: 300 ms fade-cross between consecutive stages.
- Subtitle changes: 200 ms fade-out, 200 ms fade-in of the new text.
- The mux pictogram's lane-select control in Stage 3 cycles its displayed value 0 → 1 → 2 → 3 → 0 every ~1.2 s. After the value changes, the corresponding input line of the mux briefly highlights (250 ms).

## Interactivity

- **Play button**: auto-advances all 6 stages with stage-specific pauses (Stage 1: 22 s · Stage 2: 24 s · Stage 3: 26 s · Stage 4: 24 s · Stage 5: 26 s · Stage 6: 22 s · total ≈ 144 s). All durations configurable via `?s1=22000&s2=24000&s3=26000&s4=24000&s5=26000&s6=22000` query params (defaults match). When autoplay finishes, remains on Stage 6. Pressing Play again rewinds to Stage 1 and replays.
- **Previous / Next buttons**: manual stepping, each transition ~300 ms fade-cross.
- **Capture mode**: support `?clean=1` query param that hides Prev/Play/Next controls and reduces the stage counter to a small subtle marker (or hides it entirely). Used during screen-recording so the captured MP4 has no UI chrome.
- Keyboard shortcuts: Left = Previous, Right = Next, Space = Play/Pause.
- No tooltips, no hover-only effects, no sounds.
- When stepping back manually, hide all elements newer than the chosen stage but keep prior reveals visible.

## Output

A single self-contained HTML artifact (one file) that I can open in any modern browser, click Play to autoplay through the full ~2:20 sequence, screen-record at 1920×1080, or step through manually for screenshots. No external assets — all SVG inline, CSS inline, JavaScript inline.

---

## Design intent

This deck is the BCAST chapter of the demo video. It anchors three claims, each carried by visuals + voiceover:
1. **There was a real architectural problem** (Stages 1–2): a 4-lane SIMD running in scalar mode because the base ISA had no cross-lane operation.
2. **The fix was vertical, not surface-level** (Stages 3–4): a new lookup-table mux in the EX1 pipeline stage, plus a new opcode in the 32-bit instruction encoding. Both the silicon and the ISA changed.
3. **The result is measurable on real hardware** (Stages 5–6): 3.28× speedup, 65 LUTs of added logic, and a kernel rewrite that lifted SIMD utilization from 25 % to 100 %.

The closing subtitle — *"a single new opcode, sixty-five lookup tables, and a kernel rewrite — that's what owning the GPU end-to-end lets you do"* — is the headline takeaway. Owning the whole stack is the differentiator; the speedup is the proof.

Things deliberately excluded — do not add: critical-path timing numbers, post-route slack values, flip-flop counts beyond the "0 new" callout, fanout statistics, the underlying weight-and-bias values for the IDS network, ARM CPU details (those belong to other beats), file paths or module names of any kind, or any text outside what's specified in the stage definitions above.
