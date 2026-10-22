# Claude Design Prompt — Deck 1: Intro + Problem + Training (Beats 0–2)

**Drafted 2026-05-10. Revised 2026-05-11** to match Deck 2 / Deck 3 conventions (stage titles at top of canvas, stage counter top-right, real values from the trained-weights JSON, denser per-stage content matching the TA-depth bar set by Decks 2 and 3).

Deck 1 covers the visuals for **Beat 0 (Cold open, ~15 s)**, **Beat 1 (Classifier architecture, ~36 s)**, and **Beat 2 (Dataset + training, ~60 s + 30 s clip)** of the demo video.

**Where it fits in the final cut** (user-facing context):

```
Deck 1 stages 1 - 4   (about 88 s)
       v
Training-demo screen recording cuts in here   (about 30 s)
       v
Deck 1 stage 5        (about 15 s)
       v
Deck 2 architecture walkthrough plays next
```

Deck 1 is captured as one continuous 5-stage HTML autoplay. In Clipchamp, the captured MP4 is split between stages 4 and 5 to make room for the training-demo screen recording. Total slide time about 110 s; total runtime for this section about 140 s.

**Sibling artifact (user-facing note)**: Decks 2 (Beat 3 architecture) and 3 (Beat 4 BCAST) use the same color palette, the same Ben Eater / Branch Education clean-educator style, the same headshot-zone reservation, the same stage-counter convention, and the same transient-panel patterns. The three decks should feel like one continuous visual identity in the final cut.

**Capture target (user-facing notes)**: Save the returned HTML locally, open in a browser with `?clean=1` appended to the URL to hide controls, click Play, screen-record at 1920×1080, save the MP4 to your local demo-video folder as `deck1_intro_training.mp4`.

---

> 🟢 **PASTE EVERYTHING BELOW THIS LINE INTO CLAUDE DESIGN.** Do not include anything above this line. The prompt is fully self-contained — no external files, links, or codebase references are needed.

---

Create a single-file, animated **5-stage HTML deck** for the opening of an engineering demo video. The five stages cover (1) the project title, (2) the classifier architecture, (3) the training dataset, (4) the training methodology, and (5) the training-results handoff toward silicon. The deck plays continuously on autoplay; each stage is one beat in the voiceover.

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

**Total runtime**: ~110 s autoplay across five stages with per-stage durations specified below. The voiceover budget for Beats 0–2 is ~140 s including the training-demo MP4 cut between stages 4 and 5.

## Talking-head overlay constraint (critical)

This deck will be screen-captured and composited with a small circular webcam overlay at the **bottom-right corner** of the frame — approximately 400 px wide × 220 px tall, occupying `x = 1480..1880, y = 860..1080`. **Reserve this region**:
- Do not place any critical text, diagram, big numeric reveal, or call-out inside the bottom-right rectangle.
- **Subtitle** stays at `y = 850..905`, left-anchored at `x = 80`, max width 1380 px (right edge ≤ 1460).
- Main content for each stage sits within `x = 0..1460, y = 80..820` so the bottom-right corner is always empty.
- **Controls** (Prev / Play / Next) at `y = 930..980, x = 80..1460`, hidden when `?clean=1` query param is set.
- **Stage counter** top-right at `x = 1380..1460, y = 36..66`, sans-serif 14 pt gray (`#718096`): "Stage N of 5". Same convention as the sibling decks.

## Style

Ben Eater / Branch Education clean technical educator — calm authoritative, not corporate-slick, not playful-cartoon. White background, strong color coding per element type, clear sans-serif + monospace typography. **Use sophisticated, intentional animations**: letter-by-letter reveals on the title, smooth easing curves (cubic-bezier, not linear), micro-interactions on key numbers, type-out animation on code/config blocks, gentle motion that feels designed. Match the quality bar of well-produced YouTube technical explainers.

**Density bar**: this is not a sparse-presentation deck. Each non-title stage carries multiple supporting elements (annotations, callout panels, side-panels, per-layer labels, real concrete numbers) so the viewer can read along with the voiceover and absorb depth without needing a follow-up demo. The Deck 2 and Deck 3 standards apply: real values where possible, generous monospace for code/numerics, dense-but-readable rather than minimal.

## Color system (use exactly these — they match the sibling decks)

- Data/artifact boxes (filenames, structural placeholders): fill `#f7fafc`, stroke `#4a5568`, text `#2d3748`, monospace for filenames
- Tool / methodology boxes (config card, NSL-KDD panel): fill `#edf2f7`, stroke `#2b6cb0`, text `#1a365d`
- Highlight / key-claim panels: fill `#e8f2ff`, stroke `#2c5282`, heavy 2 px stroke
- ARM / hidden-layer node color: `#e9d8fd` fill / `#6b46c1` stroke
- GPU / output-layer node color: `#fed7aa` fill / `#c05621` stroke
- Input-layer node color: `#f7fafc` fill / `#4a5568` stroke
- Connection lines between layers: stroke `#cbd5e0`, 1 px, opacity 0.4
- Loss curve / progress lines: `#2b6cb0`
- Big numeric reveals (e.g., "82.4 %"): `#2c5282`, sans-serif bold, tabular-nums
- Subtitle text: italic, gray `#4a5568`
- Subtle background gradient OK on Stage 1 (very gentle, near-white); solid white on Stages 2–5
- Stage counter: gray `#718096`, 14 pt

## Typography

- Stage 1 project title: sans-serif bold, 88–96 pt (two-line stack — see Stage 1 layout)
- Course code / subtitle on Stage 1: sans-serif, 28–32 pt
- Speaker name + date on Stage 1: sans-serif, 22–24 pt
- Stage titles at top of canvas (Stages 2–5): sans-serif bold, 36 pt, color `#1a365d`, left-anchored at `x = 80, y = 36..96`
- Body labels and bullets: sans-serif, 20–24 pt
- Per-layer annotations (under each ANN column): sans-serif, 14–16 pt; monospace for shapes like "11 × 16 + 16"
- Filename / monospace tags / config bullets: ui-monospace / Consolas / Menlo, 16–20 pt
- Big numeric reveal (Stage 5): sans-serif bold, 180–200 pt, tabular-nums
- Big stat numbers (Stage 3): sans-serif bold, 88–96 pt, tabular-nums
- Subtitle (bottom caption): sans-serif italic, 22–26 pt, gray `#4a5568`

---

## Layout principles (apply across all stages)

- **Safe content zone**: `x = 0..1460, y = 80..820` (1460 × 740 px). Everything important goes here.
- **Stage title slot** (Stages 2–5): top of canvas at `y = 36..96`, left-anchored at `x = 80`. Stage 1 (the title card) does not use this slot — the project title IS the focal element, centered.
- **Subtitle slot**: `y = 850..905`, left-anchored at `x = 80`, max width 1380 px.
- **Stage counter**: `x = 1380..1460, y = 36..66`, gray 14 pt — "Stage N of 5".
- Centered-content stages: center horizontally on `x = 730` (= 1460 / 2), not on `x = 960`, because the right side is bounded by 1460.
- Generous whitespace between elements — don't fill the safe zone.

---

## 5 animation stages

Each stage uses 300–500 ms ease-out fade-in on appearing elements, with sophisticated motion (slide-up, scale-in from 0.95, letter-by-letter where appropriate). Avoid linear easing — use `cubic-bezier(0.2, 0.7, 0.3, 1)` for entrance, `cubic-bezier(0.4, 0, 0.2, 1)` for exits.

### Stage 1 — Title (~15 s)

**Layout**: single centered column on the safe zone.

**Reveals** (in this order, ~600 ms apart):
1. **Project title — two-line stack**, centered horizontally at `x = 730`:
   - Top line: "Network Processor"
   - Bottom line: "with Inline ML-IDS"
   - Sans-serif weight 800, **96 pt** per line, line-height 1.1, vertical center of the stack around `y = 380..460`.
   - Animation: letter-by-letter slide-up + fade-in, ~50 ms per letter, ease-out. The two lines reveal sequentially — top line completes, then bottom line begins. Slight timing jitter (±15 ms per letter) makes it feel human.
2. **Thin horizontal accent line** at `y = 510`, color `#2c5282`, width 280 px, centered. Draws in left-to-right over ~400 ms.
3. **Course code line** — "EE533 — Computer System Architectures". Sans-serif 30 pt, centered at `y = 560`, color `#4a5568`. Fade-in.
4. **Speaker name** — "Zilin Shao". Sans-serif 24 pt, centered at `y = 615`, color `#2d3748`. Fade-in.
5. **Date** — "May 2026". Sans-serif 22 pt, centered at `y = 655`, color `#718096`. Fade-in.
6. **Hold** for ~5 s after all elements visible.

**Subtitle slot** (small italic gray 20 pt at `y = 720`, centered, above the headshot zone): *"A custom inline machine-learning intrusion-detection system, end-to-end on FPGA silicon."*

### Stage 2 — Classifier architecture (~36 s)

**Layout**: stage title at top; ANN sketch centered with per-layer annotations above and below each column; parameter-count callout panel on the right; spec-card row at the bottom.

**Reveals**:
1. **Stage title** at `y = 36..96, x = 80`: "Classifier — fully-connected ANN". Sans-serif bold 36 pt color `#1a365d`. Fade-in.
2. **ANN sketch** at `y = 180..560`, centered horizontally on safe zone (`x = 730`):
   - Four columns of small filled circles (16 px diameter), representing the 11 → 16 → 8 → 2 fully-connected network.
   - **Column 1 (input)** at x ≈ 240, **11 circles** vertically arranged, fill `#f7fafc`, stroke `#4a5568` (2 px). Above the column at `y = 180`, monospace 18 pt: `input · 11`. Below the column at `y = 580`, sans-serif italic 14 pt gray: `packet features (pre-extracted)`.
   - **Column 2 (hidden 1)** at x ≈ 540, **16 circles**, fill `#e9d8fd`, stroke `#6b46c1`. Above at `y = 180`, mono 18 pt: `hidden · 16`. Below at `y = 580`, italic 14 pt gray: `ReLU`.
   - **Column 3 (hidden 2)** at x ≈ 840, **8 circles**, fill `#e9d8fd`, stroke `#6b46c1`. Above: `hidden · 8`. Below: `ReLU`.
   - **Column 4 (output)** at x ≈ 1140, **2 circles**, fill `#fed7aa`, stroke `#c05621`. Above: `output · 2`. Below: `normal · attack (logits)`.
   - **Per-layer weight-shape annotations** between columns. Three small monospace labels at `y = 620..660` centered between adjacent columns, sans-serif 14 pt color `#4a5568`:
     - Between cols 1 and 2: `W1: 11 × 16  +  16 b`
     - Between cols 2 and 3: `W2: 16 × 8  +  8 b`
     - Between cols 3 and 4: `W3: 8 × 2  +  2 b`
   - Between each pair of columns, faint connection lines at 30 % opacity (stroke `#cbd5e0`, 1 px) — draw ~10 representative diagonals per pair, not the full bipartite graph.
   - Animation: input column appears first, then columns 2/3/4 reveal left-to-right with a brief scale-up bounce ~200 ms apart. Connection lines fade in between each adjacent pair as the second column lands. After all four columns are visible, a soft "pulse" wave travels left-to-right through the network (each column briefly highlights then settles, ~180 ms each).
3. **Parameter-count callout panel** at `x = 1240..1430, y = 200..380` (right side of the ANN, inside safe zone). Rounded rectangle, fill `#e8f2ff`, stroke `#2c5282`, 2 px, corner radius 6 px. Inside, three centered lines:
   - Top, sans-serif bold 18 pt color `#1a365d`: "Total parameters"
   - Middle, sans-serif bold 48 pt color `#2c5282` tabular-nums: "346"
   - Bottom, mono italic 14 pt color `#4a5568`: "= 692 bytes at BF16"
   Reveal: panel fades in after column 4 settles; the big "346" counts up from 0 over ~700 ms.
4. **Technical spec cards** at `y = 700..770, x = 80..1380`. A single horizontal row of four small rounded-rectangle cards (each ~310 px wide × 60 px tall), evenly spaced with ~22 px gaps. Each card: fill `#edf2f7`, stroke `#cbd5e0` (1 px), corner radius 6 px, centered text sans-serif 18 pt color `#1a365d`. Reveal sequentially ~250 ms apart:
   - Card 1: `fully connected`
   - Card 2: `ReLU activations`
   - Card 3: `BF16 quantized (QAT)`
   - Card 4: `binary classification`

**Subtitle**: *"Eleven inputs · two hidden layers of sixteen and eight ReLU units · two output logits · 346 parameters total. Trained in float, quantized to BF16 for silicon inference."*

### Stage 3 — Dataset (~22 s)

**Layout**: stage title at top; three big stats in a horizontal row; 41 → 11 feature-selection visualization in the middle; top-11 feature list at the bottom.

**Reveals**:
1. **Stage title** at `y = 36..96, x = 80`: "Dataset — NSL-KDD". Sans-serif bold 36 pt color `#1a365d`. Fade-in.
2. **Three big stats** in a horizontal row at `y = 140..300`, evenly spaced across `x = 100..1400`. Each stat is a column: big number on top (sans-serif bold 88 pt color `#2c5282`, tabular-nums) and label underneath (sans-serif 18 pt gray):
   - "126 K" / "training samples"
   - "22.5 K" / "test samples (KDDTest+)"
   - "11" / "features (top-RF, of 41 raw)"
   Numbers animate counting up from 0 over ~700 ms each; staggered ~200 ms apart.
3. **Subtle horizontal separator** under the big stats at `y = 320`, stroke `#cbd5e0`, 1 px, width 1300 px centered. Fade-in.
4. **Feature-selection mini-visualization** at `y = 360..480, x = 200..1260` (centered). A horizontal flow: a small data-source pill `[NSL-KDD: 41 raw features]` on the left → a small arrow with the label "Random-Forest importance" → a target pill `[11 selected]` on the right. Pills: rounded rectangles (~280 px × 56 px), fill `#edf2f7`, stroke `#2b6cb0`, 1 px, monospace 16 pt color `#1a365d`, centered text. The arrow is sans-serif italic 14 pt gray above a thin horizontal arrow drawn left-to-right. Reveal: source pill first, then arrow draws, then target pill scale-ins.
5. **Top-11 feature list** at `y = 520..700, x = 100..1400`. Three lines, monospace 18 pt color `#4a5568`, wrapping the 11 feature names with " · " separators:
   ```
   dst_bytes · src_bytes · flag · same_srv_rate · diff_srv_rate ·
   dst_host_srv_count · dst_host_same_srv_rate · logged_in ·
   protocol_type · count · service
   ```
   Each name fades in left-to-right, ~120 ms apart. After all names are revealed, **`src_bytes` and `dst_bytes`** each briefly highlight in `#2c5282` bold (250 ms pulse) to suggest "byte-counts dominate the signal."

**Subtitle**: *"NSL-KDD — the de-duplicated cleanup of the KDD'99 intrusion-detection benchmark. We start from 41 raw features per connection, then rank by random-forest importance and keep the top eleven. Source and destination byte counts dominate."*

### Stage 4 — Training methodology (~22 s)

**Layout**: stage title at top; config card on the left; loss curve on the right; small Pareto/handoff callout below.

**Reveals**:
1. **Stage title** at `y = 36..96, x = 80`: "Training methodology". Sans-serif bold 36 pt color `#1a365d`. Fade-in.
2. **Config card** at `x = 100..680, y = 160..640`. Rounded rectangle, fill `#edf2f7`, stroke `#2b6cb0`, 2 px, corner radius 8 px. Title line at top inside the card, sans-serif bold 20 pt color `#1a365d`: "v3 recipe (deployed)". Below the title, eight monospace lines (mono 18 pt color `#1a365d`, padding-left 24 px) reveal one at a time ~250 ms apart:
   ```
   optimizer        :  Adam
   learning rate    :  1e-3 (cosine decay)
   epochs           :  200
   batch size       :  256
   loss             :  cross-entropy
   label smoothing  :  0.1
   seed sweep       :  15 → seed 53
   quantization     :  QAT → BF16
   ```
3. **Loss curve panel** at `x = 760..1400, y = 160..640`. White panel with subtle border (stroke `#e2e8f0`, 1 px, corner radius 8 px). Inside:
   - X axis: 0 .. 200 epochs (tick labels at 0, 50, 100, 150, 200, sans-serif 14 pt gray).
   - Y axis: 0 .. 1 loss (no tick labels, just a clean axis line).
   - Curve: smooth decaying line from (0, 0.85) → (~30, 0.30) → (200, 0.15), using `cubic-bezier(0.3, 0.0, 0.4, 1)` to draw progressively over ~3 s. Color `#2b6cb0`, stroke 2.5 px.
   - At epoch ~25, mark a small filled circle with italic 14 pt gray label "best val · early stop" — points at the Pareto-optimal epoch where the deployed checkpoint comes from. The circle and label fade in *after* the curve draws past that x-position.
   - Y-axis title at upper-left of panel: italic 14 pt gray, "validation loss".
4. **Output artifact callout** at `y = 700..750, x = 540..920` (centered, below the two panels). A thin pale-blue rounded rectangle, fill `#e8f2ff`, stroke `#2c5282`, 1 px. Inside, two-line content:
   - Top, sans-serif bold 16 pt color `#1a365d`: "→ deployed weights"
   - Bottom, mono 14 pt color `#4a5568`: "346 params · 692 bytes · BF16"
   Fades in last.

**Subtitle**: *"Adam optimizer, two hundred epochs with cosine learning-rate decay, batch size 256, cross-entropy with label smoothing of zero-point-one, fifteen-seed sweep — seed fifty-three won. The best-validation checkpoint comes from early in training; label smoothing tames overfitting fast at this network size. Final step is quantization-aware training, which produces weights that are faithful to BF16 at inference time."*

### Stage 5 — Training results & handoff (~15 s)

**Layout**: a single dominant centerpiece — the headline accuracy number — with caption above and transition cue below.

**Reveals**:
1. **Stage title** at `y = 36..96, x = 80`: "Result — dev baseline". Sans-serif bold 36 pt color `#1a365d`. Fade-in.
2. **Big number** centered at `y = 220..480`: "82.4 %", sans-serif bold **200 pt**, color `#2c5282`, tabular-nums. Animate the digits counting up: 0 → 82.4 over ~1.5 s using ease-out. After landing, a subtle drop-shadow appears once and fades.
3. **Caption row** at `y = 520..560, x = 80..1380`, centered, sans-serif 22 pt color `#4a5568`: "KDDTest+ test set · 22,544 samples · BF16-faithful evaluation". The three phrases separated by middle dots; each phrase appears 200 ms apart.
4. **Per-class recall mini-row** at `y = 600..640, x = 320..1140`, centered, mono 16 pt color `#4a5568`. Two stats side-by-side with " · " separator:
   - "attack recall: 86.4 %"
   - "normal recall: 77.1 %"
   Sourced from the confusion matrix on the dev split. Fade-in after the caption row.
5. **Transition arrow** at `y = 700..750, x = 480..980`, centered. A horizontal right-pointing arrow (stroke `#c05621`, 3 px) with the words "next: on silicon" in italic 22 pt color `#c05621` to the left of the arrow's tail and the words "Beat 3 architecture · Beat 4 BCAST · Beat 5 live inference" in italic 14 pt gray to the right of the arrowhead. Animate the arrow drawing left-to-right over ~600 ms.
6. **Hold** for ~4 s after all elements visible.

**Subtitle**: *"Eighty-two-point-four percent on the KDDTest+ test set, evaluated faithfully in BF16. Attack recall sits at eighty-six percent on this dev split. The weights are ready for silicon — next we'll see the architecture that runs them."*

---

## Animation polish

- All reveals use easing curves like `cubic-bezier(0.2, 0.7, 0.3, 1)` for entrance, `cubic-bezier(0.4, 0, 0.2, 1)` for exits. Avoid `linear`.
- Letter-by-letter title reveal on Stage 1 should feel intentional — slight timing jitter (±15 ms) makes it feel human, not mechanical.
- Number count-ups use `requestAnimationFrame` with ease-out; show fractional digits when they exist (e.g., 82.4 not 82, 22.5 K not 22 K). Tabular-nums font so digits don't jitter.
- Code/config block lines (Stage 4 config card, Stage 3 feature list) use type-out animation — one line every ~250 ms with a brief 200 ms fade + 4 px upward slide per line.
- Loss curve in Stage 4 draws progressively over ~3 s; the "best val · early stop" marker fades in only after the curve has drawn past that x-position.
- Stage transitions: 300 ms fade-cross between consecutive stages.
- Subtitle changes: 200 ms fade-out, 200 ms fade-in of the new text.

## Interactivity

- **Play button**: auto-advances all 5 stages with stage-specific pauses (Stage 1: 15 s · Stage 2: 36 s · Stage 3: 22 s · Stage 4: 22 s · Stage 5: 15 s · total ≈ 110 s). When autoplay finishes, remains on Stage 5. Pressing Play again rewinds to Stage 1 and replays. Configurable via per-stage `?s1=15000&s2=36000&s3=22000&s4=22000&s5=15000` query params (defaults match the values above).
- **Previous / Next buttons**: manual stepping, each transition ~300 ms fade-cross.
- **Capture mode**: support `?clean=1` query param that hides Prev/Play/Next controls and reduces the stage counter to a small subtle marker (or hides it). Used during screen-recording so the captured MP4 has no UI chrome.
- Keyboard shortcuts: Left = Previous, Right = Next, Space = Play/Pause.
- No tooltips, no hover-only effects, no sounds.
- When stepping back manually, hide all elements newer than the chosen stage but keep prior reveals visible.

## Output

A single self-contained HTML artifact (one file) that I can open in any modern browser, click Play to autoplay through the full ~110 s sequence, screen-record at 1920×1080, or step through manually for screenshots. No external assets — all SVG inline (for the ANN sketch and loss curve), CSS inline, JavaScript inline.

---

## Design intent

This deck is the opening chapter of an engineering demo video, sized to convince a TA — who may never run the CLI demo — that the speaker knows the model and the training methodology cold. The viewer should be able to read the slides alone and come away knowing: the network shape (11 → 16 → 8 → 2 with 346 BF16 parameters); the dataset (NSL-KDD, 41 → 11 by random-forest importance, 22,544 test samples); the training recipe (Adam, 200 epochs, cosine LR decay, label smoothing 0.1, QAT, seed 53 from a 15-seed sweep); and the achieved dev accuracy (82.4 % on KDDTest+, 86.4 % attack recall, 77.1 % normal recall on the dev split).

The deck closes with a deliberate handoff to Beats 3, 4, and 5 — architecture, BCAST, and live silicon inference. Stage 5 names those three follow-on beats so the viewer knows what's coming.

Things deliberately excluded — do not add: per-class confusion matrices beyond the two recall numbers in Stage 5, hardware-specific terminology (no FPGA / Verilog / Virtex / mention of synthesis — Beat 3 handles all of that), product-name deep-dives, the 100 %-attack-recall figure (that's a silicon-side result from a small batch; it belongs to Beat 5), or any text outside what's specified in the stage definitions above.
