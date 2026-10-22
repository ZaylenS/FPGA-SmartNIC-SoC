# Part 3 Expert v3 — Insert Slide-Generation Prompts (2026-04-28)

**Source spec:** `part3_expert_v3_insert.md`. This file is the slide-tool-friendly extract of the insert spec — bookkeeping, decisions-locked block, and Q&A reference content stripped out; only what a slide builder needs.

**Audience:** experts (network-security engineers, hardware designers, faculty). 3 insert slides drop into the v3 deck between v3 Slide 1.3 (Fortinet deep-dive) and v3 Slide 2.1 (ML inference at the silicon packet path). Total spoken length ~75 s across the three.

**Companion file** for the existing 7-slide v3 deck: `part3_expert_v3_prompts.md`. The slide builder runs **both** files: v3 prompts produces the existing slides; this file produces the 3 inserts and applies the 2 coupled v3 changes below.

---

## How to use this file (Claude Design)

Same conventions as `part3_expert_v3_prompts.md`. Each slide has up to three input layers:

1. **Title + Banner + Speaker note** — text. Use verbatim. Title is the slide heading; banner (when present) is the prominent on-slide tagline; speaker note goes into the notes panel only (never on-slide). **Most insert slides have no banner** — the diagram and speaker note carry the slide deliberately.
2. **`[DIAGRAM: ...]` blocks** — natural-language descriptions of architectural / flow / contrast diagrams. **Render these as designer-quality diagrams.** Do NOT paste any ASCII or table content from the description verbatim onto the slide — the prose is a structural hint for what the diagram should *convey*.
3. **No `[IMAGE: ...]` blocks** for the insert (no logos / product photos to embed; everything is a rendered diagram).

**Slide-design principle (per prof Cho's "nobody reads slide text" feedback):** the visual + (optional) banner is the whole slide. Speaker notes carry substance. **Never paste paragraphs of body text on a slide.**

**Animated alternatives:** §A1 and §A2 below are separate Claude Design prompts that produce *animated* versions of the N1 and N2 diagrams (the architecture flow and the BCAST lane comparison). Output them as MP4 (or whatever Claude Design's animation export is) and convert to GIF for slide embedding via:

```bash
ffmpeg -i input.mp4 -vf "fps=10,scale=1280:-1:flags=lanczos" -loop 0 output.gif
```

The static-diagram versions (in the slide blocks below) remain the default; the animated GIFs are optional polish for N1 and N2 if production time allows. N3 stays static.

## Style hints (same as v3_prompts.md)

- One font family throughout. Suggest Inter, Helvetica, or system sans-serif.
- Size hierarchy: **title 36–48 pt, banner (when present) 22–26 pt, body 14–18 pt**.
- **Color palette (navy-on-light, matches existing v3 slides per user 2026-04-28)**: background = navy blue, slightly lighter than full navy — match the tint already used in the existing v3 slides for visual continuity. Text and elements use lighter, high-contrast colors against this background: titles white or near-white, body text light gray (around `#D0D8E0` or similar), captions a softer gray. Accent color reserved for "us / our chip" should be the *one* saturated color on the slide and pop cleanly against navy — vivid teal/cyan, warm amber/gold, or pastel mint all work; pick one and use it consistently. The accent appears only on the **GPU block fill + chip outline (Slide N1)**, the **BCAST arrow + destination cells + cycle bar (Slide N2)**, and the **highlighted top-11 bars + input neuron column (Slide N3)** — everything else is neutral. **No gradients on slide pages themselves** (animated GIFs are inline media, not slide motion). Per "too crazy" prof feedback.
- **Header strip on every slide** (top-right or top-left, small): *"Expert segment — Zilin Shao | EE533 Final Project Progress — 2026-04-28"*. Same as v3.

## Top-level prompt (copy-paste into Claude Design)

> You are Claude Design generating 3 expert-segment slides that insert into an existing 7-slide v3 deck for an EE533 final project, *"ML-based Intrusion Detection on Custom SoC"*. The 3 inserts drop between v3's Slide 1.3 (Fortinet deep-dive) and v3's Slide 2.1 (Our position). For each slide below, render the **Title** as the slide heading and copy the **Speaker note** verbatim into the slide's speaker-notes panel (never put it on the slide). Where you see a **`[DIAGRAM: ...]`** block, render it as a designer-quality diagram — use your full diagram-rendering capability; the structural hints in the prose (and any tables) must not appear on the slide. Most insert slides have **no banner** — the diagram and speaker note carry the slide deliberately. Apply minimal on-slide text per the slide-design principle: the visual is the slide; never paste paragraphs of body text. Use a neutral professional theme — one font family, neutral colors with one accent color reserved for *"us / our chip"*, no animations or gradients. Header strip on every slide: *"Expert segment — Zilin Shao | EE533 Final Project Progress — 2026-04-28"*. Slides follow:

---

## Coupled v3 changes — apply BEFORE integrating the inserts

These two changes to the existing v3 deck must land alongside the inserts.

### Coupled change A — DELETE v3 Slide 1.2

The 4-up Pigasus / Palo Alto / Snort 3 / Morpheus walkthrough slide is removed entirely. Reasoning: v3 Slide 1.1's banner *"None do on-die ML inference for IDS"* already establishes the gap, so the walkthrough is redundant and steals time. The competitor-detail content stays in the source v3.md as Q&A reference.

### Coupled change B — REVISE v3 Slide 1.1 speaker note

Slide 1.1's title / diagram / banner are unchanged. **Replace only the speaker note** with the user-locked wording (2026-04-28):

> *"So there are two camps. On the left, specialized security hardware. On the right, general-purpose DPUs. Neither of them does on-die ML inference for intrusion detection on a customize hardware."*

(Replaces the prior wording which promised digging into four competitors — only Fortinet remains after coupled change A.)

---

## Slide N1: Our chip

**Title:** Our chip

**[DIAGRAM:** Single-die SoC block diagram, drawn as a clean engineering schematic with **two visually distinct planes** inside one chip-shape boundary: a **data plane** (top half) carrying packet bytes, and a **control plane** (bottom half) carrying ARM status/control signals. The ARM is *not* on the data path — this distinction is the whole point of the diagram.

- **Outer container** — chip-shape rounded rectangle, accent border, label *"Single die (Xilinx Virtex-II Pro FPGA today, 28 nm ASIC projected)"* at the top edge inside the chip outline.

- **DATA PLANE — upper half of the chip, three blocks arranged left-to-right:**
  1. **Convertible FIFO** (BRAM-shape rectangle) — label *"Convertible FIFO · 256 × 72 BRAM · one-packet buffer"*.
  2. **DMA engine** (small rectangle) — label *"DMA · 1 word/cycle"*.
  3. **GPU coprocessor** (larger rectangle, accent fill — the differentiator, give it visual weight) — label *"SIMD GPU · 4 lanes · BF16 + INT16 · custom ISA"*.

  **Data-plane arrows (solid, neutral color):**
  - thick arrow into FIFO from outside the chip, labeled *"packet ingress"*
  - FIFO → DMA → GPU forward path, labeled *"flow features (DMA in: FIFO[7..17] → GPU DMEM[0..10])"*
  - GPU → DMA → FIFO return path slightly below the forward, labeled *"verdict (DMA out: GPU DMEM[126..127] → FIFO[10..11])"*
  - thick arrow out of FIFO to outside the chip, labeled *"packet egress"*

- **CONTROL PLANE — lower half of the chip, single block:**
  - **ARM CPU** (CPU-shape rectangle, neutral fill, *not* on the data path) — label *"ARM CPU · 4-thread · orchestrator (polls status, dispatches DMA, releases GPU)"*.

  **Control-plane arrows (dashed or muted-color — visually distinct from data-plane arrows):**
  - ARM ↔ FIFO — labeled *"poll FIFO_STATUS · set FIFO_MODE"*
  - ARM ↔ DMA — labeled *"configure addr + length; start"*
  - ARM ↔ GPU — labeled *"release; poll kernel_done"*

- **Style:** neutral background, accent color reserved exclusively for the GPU block fill and the chip outline; **solid arrows for the data plane**, **dashed (or noticeably muted-color / thinner) arrows for the control plane** so the eye immediately separates "what carries packet bytes" from "what carries control signals." Same font family as the rest of v3. The diagram should make obvious that the ARM never sees packet payload — data flows FIFO → DMA → GPU → DMA → FIFO; the ARM only drives status registers and DMA configuration. Do not draw a host CPU or PCIe link; this slide is about the on-die orchestrator story. **]**

**ASCII reference** *(structural hint only — do not paste on the slide; Claude Design renders the actual diagram from the `[DIAGRAM: ...]` block above):*

```
                   +-------- Single die (Virtex-II Pro FPGA today / 28 nm ASIC projected) --------+
                   |                                                                               |
                   |  DATA PLANE   (solid = packet bytes)                                          |
                   |                                                                               |
                   |                       flow features                                           |
                   |                       (FIFO[7..17] -> GPU DMEM[0..10] via DMA)                |
                   |                          ===========>===========>===========>                 |
                   |                                                                               |
   pkt in          |   +--------------+      +-------------+      +======================+        |
   ============>=======| Convertible  |      |             |      |     SIMD GPU         |        |
                   |   | FIFO         |      | DMA engine  |      |  4 lanes · BF16+INT16|        |
                   |   | 256x72 BRAM  |      | 1 word/cyc  |      |  custom ISA          |        |
   pkt out         |   | one-pkt buf  |      |             |      |  (accent color)      |        |
   <===========<=======|              |      |             |      |                      |        |
                   |   +--------------+      +-------------+      +======================+        |
                   |                                                                               |
                   |                          <===========<===========<===========                 |
                   |                       verdict                                                 |
                   |                       (GPU DMEM[126..127] -> FIFO[10..11] via DMA)            |
                   |                                                                               |
                   |  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -    |
                   |                                                                               |
                   |  CONTROL PLANE   (dashed = ARM status reads / config writes)                  |
                   |                                                                               |
                   |          ^                      ^                            ^                |
                   |          :                      :                            :                |
                   |          : poll FIFO_STATUS     : configure DMA addr+len     : release;       |
                   |          : · set FIFO_MODE      : · start                    : poll done      |
                   |          :                      :                            :                |
                   |   +-----------------------------------------------------------------+         |
                   |   |  ARM CPU · 4-thread · orchestrator                              |         |
                   |   |  (polls status, dispatches DMA, releases GPU)                   |         |
                   |   +-----------------------------------------------------------------+         |
                   |                                                                               |
                   +-------------------------------------------------------------------------------+
```

**Banner:** *None.*

**Speaker note (~12 s, one sentence):**
> *"Packet enters the FIFO, our ARM orchestrator dispatches the DMA, flow features stream into our SIMD GPU, the GPU classifies, and the verdict exits — all on a single die."*

---

## Slide N2: BCAST — the cross-lane SIMD instruction we added

**Title:** BCAST — the cross-lane SIMD instruction we added

**[DIAGRAM:** Two-panel composition. **Top panel** = SIMD-lane behavior contrast (before vs after BCAST). **Bottom panel** = cycle-count result.

- **TOP PANEL — split horizontally into LEFT ("scalar fallback") and RIGHT ("with BCAST"):**

  - **LEFT subpanel — header *"Without BCAST: scalar fallback"*.** Four vertical columns labeled `lane 0` … `lane 3`, each shown as a stack of 4 register-cell boxes representing a SIMD register. Below the lanes: a small "scratch register" rectangle in the middle, with **N curving arrows** looping from each lane down to scratch and back, drawn one after another to convey *sequential scalar passes*. Caption underneath: *"Cross-lane reduction → N serial scalar passes through the register file."*
  - **RIGHT subpanel — header *"With BCAST: one cycle"*.** Same four-lane layout. A single thick **horizontal arrow** spans across all four lanes (left to right), labeled *"BCAST"*. The arrow's source cell (lane 0) is highlighted in the accent color; the destination cells in lanes 1-3 inherit the same value (shown as the same accent color filling those cells). Caption underneath: *"One instruction broadcasts a value across all four lanes."*

  Use the accent color reserved for "us / our chip" only on the BCAST arrow and the cells it touches, so the eye is drawn to the right subpanel.

- **BOTTOM PANEL — cycle-count comparison.** Two horizontal bars stacked vertically:
  - Top bar (long, neutral color) — labeled *"Scalar baseline"* — value *"2,402 cycles per inference"* annotated at the right end.
  - Bottom bar (short, accent color) — labeled *"With BCAST"* — value *"732 cycles per inference"* annotated at the right end. Below the bottom bar, a small annotation: *"3.28× speedup · hardware-counted via on-chip PCI cycle counter, 2026-04-17."*

  Bars on a shared linear x-axis so the visual ratio reads as ~3.3×.

Style: same visual language as v3's other diagrams. Header strip at top right. **]**

**Banner:** *None.*

**Speaker note (~25 s):**
> *"The most novel piece of engineering on the chip — we added a single instruction to our GPU's ISA: BCAST, a cross-lane broadcast for SIMD. Without it, accumulating across lanes needed N scalar passes through the register file. With it, one cycle. The whole inference dropped from 2,402 cycles to 732 — 3.28×, hardware-counted by an on-chip cycle counter. This change required modifying the RTL, the ISA, the assembler, and the kernel — only possible because we own every layer."*

---

## Slide N3: What ML actually runs

**Title:** What ML actually runs

**[DIAGRAM:** Two-zone composition.

- **MAIN ZONE — two side-by-side panels (LEFT and RIGHT) filling the upper ~80 % of the slide.**

  - **LEFT panel — *"4-layer ReLU MLP"*.** Stylized neural-network diagram showing four columns of neurons connected by full lines (no individual weight values needed):
    - Column 1 (input) — 11 neurons, label *"11 inputs"* below.
    - Column 2 (hidden) — 16 neurons, label *"16 ReLU"* below.
    - Column 3 (hidden) — 8 neurons, label *"8 ReLU"* below.
    - Column 4 (output) — 2 neurons, label *"2 outputs · attack / normal"* below.
    - Small annotation under the network: *"Trained with label-smoothing 0.1 on KDDTrain+ (125,973 samples)."*

  - **RIGHT panel — *"Random Forest feature importance · top 11 of 41"*.** Horizontal bar chart with 41 horizontal bars sorted by importance (top to bottom). The top 11 are highlighted in the accent color and labeled with feature names; the remaining 30 are rendered in neutral gray to show the long tail. **Top-11 feature names (RF importance order, `rf_seed = 42`, verified from `docs/ids_accuracy_journey.md`):**

    1. `dst_bytes` — numeric, log1p
    2. `src_bytes` — numeric, log1p
    3. `flag` — *categorical*, label-encoded
    4. `same_srv_rate` — numeric
    5. `diff_srv_rate` — numeric
    6. `dst_host_srv_count` — numeric, log1p
    7. `dst_host_same_srv_rate` — numeric
    8. `logged_in` — boolean
    9. `protocol_type` — *categorical*, label-encoded
    10. `count` — numeric, log1p
    11. `service` — *categorical*, label-encoded

    Visual notes: italicize the three categorical labels in the chart so they stand out from numerics; consider a small marker glyph next to the four `log1p`-preprocessed numerics. The chart's x-axis is feature importance (0 → 1, normalized) — no absolute axis values needed if the bars convey the rank visually. The 30 non-top-11 bars need not be labeled (just gray bars, descending, to convey the long tail).

- **CAPTION ZONE — single line at the bottom of the slide, smaller type than the panel content.** Center-aligned:

  > *"11 RF-importance-ranked features (mostly flow) · 4-layer ReLU · label smoothing 0.1 was the unlock. NSL-KDD also includes payload-derived attributes; we chose flow."*

Style: both panels share the same neutral color palette except for the accent color on the highlighted top-11 bars and the network's input column (visually links "11 inputs" with "11 selected features"). The caption-zone payload mention is deliberately small and neutral — it acknowledges that NSL-KDD has payload-derived (content) attributes without re-emphasizing the encryption rationale. Header strip at top right. **]**

**Banner:** *None.*

**Speaker note (~25 s):**
> *"Two methodology decisions. We use flow features — eleven of NSL-KDD's forty-one, ranked by Random Forest importance. NSL-KDD also includes payload-derived attributes; we chose flow. The classifier is a four-layer ReLU network — eleven inputs, sixteen hidden, eight hidden, two outputs. Label smoothing at point one is the unlock; without it the model collapses to the majority class."*

---

## §A. Animated diagram prompts (optional GIF embeds)

These produce animated MP4s in Claude Design that are then converted to GIFs for embedding in slides N1 and N2 in place of the static diagrams. N3 stays static — its content is informational density, not motion.

### §A1. Architecture animation (optional, replaces N1 static diagram)

**Output target:** ~10-second seamless loop, 1280 × 720, exported as MP4 → converted to GIF (10 fps).

**Prompt for Claude Design:**

> Generate a clean 10-second looping animation of a single-die SoC processing one network packet. The static frame is a 2-plane layout inside one chip-shape rounded rectangle (label at top: *"Single die — Virtex-II Pro FPGA today, 28 nm ASIC projected"*).
>
> **Data plane (upper half of the chip)** — three blocks arranged left-to-right: **Convertible FIFO** (256 × 72 BRAM, one-packet buffer), **DMA engine** (1 word/cycle), **SIMD GPU** (4 lanes · BF16 + INT16 · custom ISA — render this block in the accent color, slightly larger than the others, since it's the differentiator). Solid arrows: a packet-ingress arrow into FIFO from outside the chip, FIFO → DMA → GPU forward path, GPU → DMA → FIFO return path, and a packet-egress arrow exiting the right side of the chip.
>
> **Control plane (lower half of the chip)** — one block: **ARM CPU** (4-thread, *orchestrator* — polls status, dispatches DMA, releases GPU). Dashed (or muted-color) control arrows: ARM ↔ FIFO, ARM ↔ DMA, ARM ↔ GPU. The ARM never carries packet bytes; it only drives control signals.
>
> **Animation timeline (looping, 10 s total):**
>
> - **t=0.0–0.5 s:** static initial frame; no packet in the chip; ARM idle.
> - **t=0.5–1.5 s:** a small "packet" glyph slides in from outside the chip and lands inside the FIFO block (FIFO briefly highlighted neutral).
> - **t=1.5–2.0 s:** ARM block pulses briefly (it polled FIFO_STATUS and saw `pkt_ready`); the dashed ARM ↔ FIFO control arrow lights up momentarily, with a small overlay label *"FIFO_MODE = GPU"*.
> - **t=2.0–2.5 s:** the dashed ARM ↔ DMA control arrow lights up, with overlay label *"DMA in: FIFO[7..17] → GPU DMEM[0..10]"*.
> - **t=2.5–4.0 s:** flow-feature glyphs stream along the solid data-plane arrow FIFO → DMA → GPU (multiple small glyphs pumping through); DMA block has a subtle "pumping" animation.
> - **t=4.0–4.5 s:** ARM pulses; dashed ARM ↔ GPU control arrow lights up, with overlay label *"GPU_CTRL = run"*.
> - **t=4.5–6.0 s:** GPU block pulses in the accent color (classification happening); brief overlay text near the GPU: *"732 cycles · BF16 inference"* fades in then out.
> - **t=6.0–6.5 s:** ARM pulses (saw `kernel_done`); dashed ARM ↔ DMA arrow lights up again, with overlay label *"DMA out: GPU DMEM[126..127] → FIFO[10..11]"*.
> - **t=6.5–7.5 s:** verdict glyph flows along the solid data-plane return path GPU → DMA → FIFO.
> - **t=7.5–8.5 s:** ARM pulses; dashed ARM ↔ FIFO arrow lights up briefly (*"FIFO_MODE = 0"*); packet-egress arrow lights up; verdict packet exits the right side of the chip.
> - **t=8.5–10.0 s:** chip empties, brief pause, then loop seamlessly back to t=0.
>
> **Style:** **navy-blue background matching the existing v3 slides** (slightly lighter than full navy — same tint as the slide deck for visual continuity). All elements in lighter, high-contrast colors: text white or near-white, neutral data-plane arrows in light gray, control-plane (dashed) arrows in a slightly muted-color version of light gray. Accent color reserved exclusively for the GPU block + the moving feature/verdict glyphs at decision points (vivid teal/cyan, warm amber, or pastel mint — match whichever accent the slide deck uses). **Solid neutral arrows for the data plane**, **dashed (or muted-color) arrows for the control plane**; no flashy effects; tempo matches a calm, deliberate engineering walkthrough. The animation should make obvious that the ARM is the orchestrator — it polls and dispatches but never carries packet bytes; data flows entirely on the upper plane (FIFO → DMA → GPU → DMA → FIFO). Header strip at top right: *"Expert segment — Zilin Shao | EE533 Final Project Progress — 2026-04-28"* (static throughout the loop).
>
> Output 1280 × 720, MP4. After export, convert to GIF via `ffmpeg -i input.mp4 -vf "fps=10,scale=1280:-1:flags=lanczos" -loop 0 output.gif`.

**Target filename:** `docs/final_project_progress_present/diagrams/insert_n1_arch_anim.gif`

### §A2. BCAST animation (recommended, replaces N2 static diagram)

**Output target:** ~9-second seamless loop, 1280 × 720, exported as MP4 → converted to GIF (10 fps). This is the most important animation — BCAST is the technical centerpiece, and motion makes the contrast (sequential scalar passes vs single broadcast) far more legible than a static diagram.

**Prompt for Claude Design:**

> Generate a clean 9-second looping animation comparing two SIMD execution modes for the same cross-lane reduction. The frame is split horizontally into two equal-width panels with headers: **LEFT — *"Without BCAST: scalar fallback"*.** **RIGHT — *"With BCAST: one cycle"*.** Each panel shows four vertical columns labeled `lane 0`, `lane 1`, `lane 2`, `lane 3`, each column rendered as a stack of 4 register-cell boxes. Beneath both panels' lanes, place a small "scratch register" rectangle. Below the entire two-panel area, render a horizontal cycle-count comparison bar chart with two stacked bars (top = "Scalar baseline · 2,402 cycles", bottom = "With BCAST · 732 cycles · 3.28× speedup"); both bars start hidden and animate in at the end (see timeline).
>
> **Animation timeline (looping, 9 s total):**
>
> - **t=0.0–0.5 s:** static setup frame; both panels visible, no motion yet, bottom bar chart hidden.
> - **t=0.5–4.5 s:** **LEFT panel animates** — four sequential curving arrows draw themselves one at a time, each lane → scratch register → back. Cadence ~1 arrow / second. As each arrow draws, briefly pulse the originating lane in a neutral highlight to indicate "this lane is the active scalar pass." After all four arrows are drawn, a small label *"4 sequential cycles, scalar fallback"* fades in below the LEFT panel.
> - **t=4.5–5.0 s:** brief pause to let the audience register *"that took four passes."*
> - **t=5.0–6.0 s:** **RIGHT panel animates** — a single thick horizontal arrow sweeps from `lane 0` rightward across `lane 1`, `lane 2`, `lane 3`, all in one continuous motion (sweep duration ~0.6 s). The source cell in `lane 0` is in the accent color; as the arrow crosses each destination cell, that cell fills with the same accent color (visually broadcasting the value). Label *"BCAST: 1 instruction, 1 cycle"* fades in below the RIGHT panel.
> - **t=6.0–7.5 s:** the bottom cycle-count comparison bar chart animates in: the long top bar (scalar baseline) draws first with its label *"2,402 cycles"*; then the short bottom bar (BCAST) draws in the accent color with its label *"732 cycles · 3.28× speedup"*. Bars are on a shared linear x-axis so the ~3.3× ratio reads visually.
> - **t=7.5–9.0 s:** hold final frame, then loop seamlessly back to t=0.
>
> **Style:** **navy-blue background matching the existing v3 slides** (slightly lighter than full navy — same tint as the slide deck for visual continuity). All elements in lighter, high-contrast colors: register cell outlines in light gray, lane labels and headers in white/near-white, neutral arrows light gray. Accent color reserved exclusively for the BCAST arrow + the destination cells it touches in the RIGHT panel + the BCAST bar in the bottom chart (match the slide deck's accent — vivid teal, warm amber, or pastel mint). Everything else neutral. Tempo deliberate — the LEFT panel's four-pass sequence should *feel* slow relative to the RIGHT panel's single sweep, because that's the entire visual argument. No flashy effects, no gradients. Header strip at top right: *"Expert segment — Zilin Shao | EE533 Final Project Progress — 2026-04-28"* (static throughout the loop).
>
> Output 1280 × 720, MP4. After export, convert to GIF via `ffmpeg -i input.mp4 -vf "fps=10,scale=1280:-1:flags=lanczos" -loop 0 output.gif`.

**Target filename:** `docs/final_project_progress_present/diagrams/insert_n2_bcast_anim.gif`

---

## End: stop here.

---

## Asset checklist

Two categories: **diagrams** Claude Design renders directly into the slides, and **optional animated GIFs** that replace specific static diagrams.

### Diagrams — Claude Design renders from the `[DIAGRAM: ...]` blocks

| Slide | Diagram | Source description |
|---|---|---|
| N1 | Single-die SoC block diagram | Slide N1 block above |
| N2 | Two-panel SIMD-lane contrast + cycle-count bars | Slide N2 block above |
| N3 | Two-panel: 4-layer net + RF feature-importance bar chart + caption | Slide N3 block above |

### Optional animated GIFs (replace static diagrams in N1 and N2)

| GIF | Source prompt | Target path |
|---|---|---|
| Architecture animation | §A1 | `docs/final_project_progress_present/diagrams/insert_n1_arch_anim.gif` |
| BCAST animation | §A2 | `docs/final_project_progress_present/diagrams/insert_n2_bcast_anim.gif` |

**Production order:** static diagrams first (lock the layout and the data), then animations only if production time allows. The static N2 diagram alone makes the BCAST point; the animation amplifies but doesn't change the message.

### Coupled v3 changes (apply at integration time)

| Change | Location | Action |
|---|---|---|
| Coupled change A | v3 Slide 1.2 | DELETE entirely |
| Coupled change B | v3 Slide 1.1 speaker note | REPLACE with the user-locked wording above |

No new asset fetching required — both changes are text/structural edits to existing v3 deliverables.
