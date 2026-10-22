# Part 3 Expert v3 — Insert (3 slides)

**Inserts into:** `part3_expert_v3.md` — the Apr 28/30 expert-segment slide spec.
**Created:** 2026-04-28 after the first presentation lecture (driven by prof feedback to other teams).
**Status:** DRAFT for review — content/order not yet locked. Once locked, derive `part3_expert_v3_insert_prompts.md` (Claude Design slide prompt + per-diagram prompts) following the `part3_expert_v3_prompts.md` format.

NICE is **not** introduced in this insert — branding is handled at the very start of the full presentation (upstream of the expert segment), so these three slides assume the audience already knows the project name. They focus on technical substance only.

---

## 1. Slot-in context

The v3 expert deck (locked 2026-04-27) flows: Beat 0 hook → Slide 1.1 industry landscape → Slide 1.2 4-up walkthrough → Slide 1.3 Fortinet deep-dive → Slide 2.1 "ML inference at the silicon packet path" → Slide 2.2 headline result → Slide 3.1 power tables → Slide 3.2 power positioning. The two slides that bracket the new insert are summarized below so a reader doesn't need to re-open v3 to evaluate the fold-in fit.

### 1.1 Slide BEFORE the insert — v3 Slide 1.3 (Fortinet deep-dive)

- **Title**: *"Fortinet — built the silicon, stopped one step short."*
- **Visual**: 3-plane horizontal architecture (FortiGate · FortiNDR · FortiGuard), with NP7 ASIC inside FortiGate marked "sigs only, NO ML."
- **Banner**: *"Their flagship: 800 Gbps firewall → 200 Gbps with IPS engaged. Fortinet built the silicon and stopped one step short. We put inspection in silicon."*
- **Final spoken sentence**: *"They built the silicon and stopped one step short. **We put inspection in silicon.**"*

### 1.2 Slide AFTER the insert — v3 Slide 2.1 ("Our position")

- **Title**: *"ML inference at the silicon packet path."*
- **Visual**: THEM-vs-US two-row contrast flow (Fortinet's 3-plane stack vs our single chip → verdict for an edge IoT/phone).
- **Banner**: *"All on a single chip — no host trip, no appliance, no cloud. Sized for the edge."*
- **Opening spoken sentence**: *"Fortinet built custom silicon for security and stopped one step short — kept ML off the chip. We took the next step."*

### 1.3 Bridges this insert must satisfy

- **Bridge IN (from 1.3)**: Slide 1.3 ends with *"We put inspection in silicon."* → the **first** insert slide should pick up by **showing** that silicon (the architecture diagram).
- **Bridge OUT (to 2.1)**: Slide 2.1 opens by re-framing "we took the next step" → the **last** insert slide should hand the audience a complete picture of *what that step was* (custom ML running on the silicon), so 2.1's positioning lands as a summary rather than a fresh claim.

## 2. Coupled changes to v3 (separate from this insert, but required)

These are flagged here so the slide builder applies them when integrating:

| Change | Where | Why |
|--------|-------|-----|
| **DELETE** Slide 1.2 (4-up walkthrough — Pigasus/Palo Alto/Snort 3/Morpheus) | v3 §Beat 1 | Per user 2026-04-28: Slide 1.1's banner "None do on-die ML inference for IDS" already establishes the gap; the 4-up walkthrough is redundant and steals time. Pigasus/Palo Alto/Snort 3/Morpheus content survives in the v3 Slide 1.2 Reference block as Q&A backup. |
| **REVISE** Slide 1.1 speaker note | v3 §Slide 1.1 | Currently promises *"we'll dig into the four most-public — Fortinet, Palo Alto, Snort 3, and Pigasus."* After 1.2 deletion this is dishonest. **User-locked replacement (2026-04-28)**: *"So there are two camps. On the left, specialized security hardware. On the right, general-purpose DPUs. Neither of them does on-die ML inference for intrusion detection on a customize hardware."* |
| **CONSIDER** updating Slide 2.2 GIF + benchmark numbers | v3 §Slide 2.2 | User plans (a) a 500-sample NetFPGA test to replace the 20-sample silicon-agrees-with-dev GIF, and (b) training a larger dev-only model targeting >90 % KDDTest+ to replace the 82.4 % full-benchmark headline. Both are downstream workstreams — see §6 below. Insert plan does **not** depend on either being complete. |

## 3. The three insert slides (proposed)

**Order: Architecture → BCAST → Custom ML methodology.** Rationale: 1.3 ends on *"we put inspection in silicon"* → N1 shows the silicon → N2 shows the silicon's unique trick → N3 shows what runs on it → 2.1 lands as the "where ML lives in our pipeline" summary. ML in N3 chains directly into "ML inference at the silicon packet path" in 2.1.

Speaking budget across the three slides: **~70-75 s** (~12 s + ~25 s + ~35 s). v3's total budget had ~75 s of slack from the original 4-beat plan; deleting Slide 1.2 reclaims another ~17 s. Net delta after this insert: roughly even, talk lands at ~3 min total — within envelope.

---

### Slide N1 — Our chip (general architecture)

**Title:** *Our chip*

**On-slide content:** one designer-quality SoC block diagram (described under DIAGRAM below). No body text. No banner. The diagram and one spoken sentence carry the whole slide.

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

- **Style:** neutral background, accent color reserved exclusively for the GPU block fill and the chip outline; **solid arrows for the data plane**, **dashed (or noticeably muted-color / thinner) arrows for the control plane** so the eye immediately separates "what carries packet bytes" from "what carries control signals." Same font family as the rest of v3.

The diagram should make obvious that the ARM never sees packet payload — data flows FIFO → DMA → GPU → DMA → FIFO; the ARM only drives status registers and DMA configuration. Do not draw a host CPU or PCIe link; this slide is about the on-die orchestrator story. **]**

**Speaker note (~12 s, one sentence — per user 2026-04-28 "general architecture, one or none sentence speaking"):**
> *"Packet enters the FIFO, our ARM orchestrator dispatches the DMA, flow features stream into our SIMD GPU, the GPU classifies, and the verdict exits — all on a single die."*

**Reference (off-slide; for slide-builder + Q&A backup):**
- Asset reuse candidates (read first before commissioning a new diagram): `diagrams/architecture_simplified.mmd`, `diagrams/solution-diagram.html`. Both predate the 4/26 cut of animated diagrams and may be close to what's needed already.
- The 4-thread ARM is from Lab 6; the 4-lane SIMD GPU is from Lab 7; the convertible FIFO and DMA were the Lab 8 integration glue. Every layer is ours — relevant for Q&A on "how much did you build vs reuse."
- If asked about FPGA resource footprint: 67 % LUT, 44 % FF, 46 % BRAM, 4 % multiplier on a 90 nm Virtex-II Pro. (Same Q&A backup as v3 Slide 2.1 Reference.)

---

### Slide N2 — BCAST: cross-lane SIMD instruction we added

**Title:** *BCAST — the cross-lane SIMD instruction we added*

**On-slide content:** two-part visual described under DIAGRAM below. Banner at the bottom.

**[DIAGRAM:** Two-panel composition. Top panel = SIMD-lane behavior contrast (before vs after BCAST). Bottom panel = cycle-count result.

- **TOP PANEL — split horizontally into LEFT ("scalar fallback") and RIGHT ("with BCAST"):**

  - **LEFT subpanel — header *"Without BCAST: scalar fallback"*.** Four vertical columns labeled `lane 0` … `lane 3`, each showing 4 stacked register-cell boxes representing a SIMD register. Below the lanes: a small "scratch register" rectangle in the middle, with **N curving arrows** looping from each lane down to scratch and back, drawn one after another to convey *sequential scalar passes*. Caption underneath: *"Cross-lane reduction → N serial scalar passes through the register file."*
  - **RIGHT subpanel — header *"With BCAST: one cycle"*.** Same four-lane layout. A single thick **horizontal arrow** spans across all four lanes (left to right), labeled *"BCAST"*. The arrow's source cell (lane 0) is highlighted in the accent color; the destination cells in lanes 1-3 inherit the same value (shown as the same accent color filling those cells). Caption underneath: *"One instruction broadcasts a value across all four lanes."*

  Use the accent color reserved for "us / our chip" only on the BCAST arrow and the cells it touches, so the eye is drawn to the "with BCAST" panel.

- **BOTTOM PANEL — cycle-count comparison.** Two horizontal bars stacked vertically:
  - Top bar (long, neutral color) — labeled *"Scalar baseline"* — value *"2,402 cycles per inference"* annotated at the right end.
  - Bottom bar (short, accent color) — labeled *"With BCAST"* — value *"732 cycles per inference"* annotated at the right end. Below the bottom bar, a small annotation: *"3.28× speedup · hardware-counted via on-chip PCI cycle counter, 2026-04-17."*

  Bars on a shared linear x-axis so the visual ratio reads as ~3.3×.

Style: same visual language as v3's other diagrams. Header strip of v3 (*"Expert segment — Zilin Shao | EE533 Final Project Progress — 2026-04-28"*) at top right. **]**

**Banner:** *None — the diagram and speaker note carry the slide.*

**Speaker note (~25 s):**
> *"The most novel piece of engineering on the chip — we added a single instruction to our GPU's ISA: BCAST, a cross-lane broadcast for SIMD. Without it, accumulating across lanes needed N scalar passes through the register file. With it, one cycle. The whole inference dropped from 2,402 cycles to 732 — 3.28×, hardware-counted by an on-chip cycle counter. This change required modifying the RTL, the ISA, the assembler, and the kernel — only possible because we own every layer."*

**Reference (off-slide; for slide-builder + Q&A backup):**
- The BCAST instruction is documented in `docs/bcast_instruction_design.md`. Source RTL: `src/gpu/simd_alu.v` and `src/gpu/execute_stage.v` (effective_a register fix, hardware-verified 2026-04-17).
- The 2,402-cycle baseline is the unoptimized scalar kernel (`programs/gpu/kernels/`, pre-BCAST). 732 cycles is the optimized BCAST kernel running the same 11-16-8-2 ANN inference.
- "Cross-layer ownership" framing maps directly to today's prof feedback themes (#4, #5): highlight that we did ARM **and** custom GPU; emphasize custom hardware. BCAST is the single best "we built every layer" anchor — pattern available across v3 Q&A as well.
- If asked "why a custom instruction instead of using existing reduction primitives": the GPU was originally a Lab 7 SIMD with no cross-lane operations; multi-layer ANN inference forced scalar fallback; BCAST is the minimum-invasive ISA addition that unlocks the inference speedup. Don't over-claim it as a general-purpose primitive — it's targeted at this kernel.
- 7.32 μs at 100 MHz today (732 cycles); ~0.7 μs projected at 1 GHz / 28 nm — *projection assumes 10× clock-scaling holds; not pipeline-verified.* Same Q&A backup as v3 Slide 3.2 Reference.

---

### Slide N3 — What ML actually runs

**Title:** *What ML actually runs*

**On-slide content:** pull-quote at top + two-part visual described under DIAGRAM below + caption strip at the bottom.

**[DIAGRAM:** Two-zone composition (no top pull-quote — encryption framing dropped per user 2026-04-28; another team covered it and we don't re-emphasize).

- **MAIN ZONE — two side-by-side panels (LEFT and RIGHT) filling the upper ~80 % of the slide.**

  - **LEFT panel — *"4-layer ReLU MLP"*.** Stylized neural-network diagram showing four columns of neurons connected by full lines (no individual weight values needed):
    - Column 1 (input) — 11 neurons, label *"11 inputs"* below.
    - Column 2 (hidden) — 16 neurons, label *"16 ReLU"* below.
    - Column 3 (hidden) — 8 neurons, label *"8 ReLU"* below.
    - Column 4 (output) — 2 neurons, label *"2 outputs · attack / normal"* below.
    - Small annotation under the network: *"Trained with label-smoothing 0.1 on KDDTrain+ (125,973 samples)."*

  - **RIGHT panel — *"Random Forest feature importance · top 11 of 41"*.** Horizontal bar chart with 41 horizontal bars sorted by importance (top to bottom). The top 11 are highlighted in the accent color and labeled with feature names; the remaining 30 are rendered in neutral gray to show the long tail. **Verified top-11 (RF importance order, `rf_seed = 42`, from `docs/ids_accuracy_journey.md` lines 64-76):**

    | Rank | Feature | Type / preprocessing |
    |-----:|---------|----------------------|
    | 1 | `dst_bytes` | numeric, log1p |
    | 2 | `src_bytes` | numeric, log1p |
    | 3 | `flag` | **categorical**, label-encoded |
    | 4 | `same_srv_rate` | numeric |
    | 5 | `diff_srv_rate` | numeric |
    | 6 | `dst_host_srv_count` | numeric, log1p |
    | 7 | `dst_host_same_srv_rate` | numeric |
    | 8 | `logged_in` | boolean |
    | 9 | `protocol_type` | **categorical**, label-encoded |
    | 10 | `count` | numeric, log1p |
    | 11 | `service` | **categorical**, label-encoded |

    The chart's x-axis is feature importance (0 → 1, normalized). No absolute axis labels needed if the bars convey the rank visually. Visual notes: italicize the three categorical labels in the chart so they stand out from numerics; consider a small marker glyph on the four `log1p`-preprocessed numerics.

- **CAPTION ZONE — single line at the bottom of the slide, smaller type than the panel content.** Center-aligned:
  > *"11 RF-importance-ranked features (mostly flow) · 4-layer ReLU · label smoothing 0.1 was the unlock. NSL-KDD also includes payload-derived attributes; we chose flow."*

Style: both panels use the same neutral color palette except for the accent color on the highlighted top-11 bars and the network's input column (visually links "11 inputs" with "11 selected features"). The caption-zone payload mention is deliberately small and neutral — it shows we know NSL-KDD has payload-derived (content) attributes without re-emphasizing the encryption rationale. Header strip of v3 at top right. **]**

**Banner:** *None — the panels and caption carry the slide.*

**Speaker note (~25 s):**
> *"Two methodology decisions. We use flow features — eleven of NSL-KDD's forty-one, ranked by Random Forest importance. NSL-KDD also includes payload-derived attributes; we chose flow. The classifier is a four-layer ReLU network — eleven inputs, sixteen hidden, eight hidden, two outputs. Label smoothing at point one is the unlock; without it the model collapses to the majority class."*

**Reference (off-slide; for slide-builder + Q&A backup):**
- The full 11-feature list, the RF importance values, and the LS=0.1 ablation log live in `docs/ids_accuracy_journey.md` (canonical per v3). Pull the actual top-11 list from there before producing the bar chart asset.
- Memory anchor: `project_accuracy_improvement_0426.md` — IDS v3 (2026-04-26): 82.4% on KDDTest+, LS=0.1 was the unlock.
- Flow-vs-payload framing aligns with prof Cho's earlier hint ("payload vs traffic") — see `project_professor_meeting_0326.md`. Reference if asked about prior art on flow-feature IDS.
- **Q&A inoculation against another team's undisclosed-methodology ~99% claim** *(observed by user 2026-04-28; do not cite the team aloud)*: this slide names the **benchmark** (NSL-KDD KDDTest+, 22,544 held-out samples — on Slide 2.2), the **feature count** (11), and the **methodology** (RF-selected flow features, 4-layer ANN, LS=0.1). Anyone presenting an accuracy number without those three disclosures will look unaudited by comparison. If pressed in Q&A *("yours is lower than X's")*, reply: *"Different methodology — ours is hardware-measured on the public NSL-KDD held-out set, with the eleven features and four-layer architecture you just saw. Without those three disclosures you can't compare results."* Calm, factual, no name-checking.
- 11-16-8-2 architecture is sized to fit on-chip in BF16 inside the GPU's 1024-word DMEM. Bigger architectures are training experiments only — see §6.

---

## 4. What this insert does NOT cover (because v3 already does)

To prevent re-recording overlap, here's the guard rail:

| Topic | Lives in v3 at | Insert must NOT repeat |
|-------|----------------|------------------------|
| KDDTest+ accuracy headline (82.4 %, F1, recall, precision) | Slide 2.2 LEFT card | ✗ |
| FPGA live demo numbers (90 %, 100 % attack recall, ~6 ms/pkt) + GIF | Slide 2.2 RIGHT card | ✗ |
| Silicon-vs-dev correspondence (±0.01 logit) | Slide 2.2 RIGHT card | ✗ |
| Power numbers (2.67 W FPGA, 90-110 mW projected at 28 nm) | Slides 3.1 + 3.2 | ✗ |
| THEM-vs-US flow contrast | Slide 2.1 | ✗ |
| "All on a single chip" positioning banner | Slide 2.1 | ✗ |
| Process-node scaling math + Kuon & Rose citation | Slide 3.1 Reference | ✗ |
| Latency comparison vs Fortinet | (intentionally suppressed in v3 §Beat 3 — apples-to-oranges) | ✗ — keep suppressed |

The insert adds: **(a) what the chip looks like (N1)**, **(b) the unique HW trick that makes inference fast (N2)**, and **(c) what model runs on it and how its features were chosen (N3)**. Nothing else.

## 5. Mapping to today's prof-feedback themes (2026-04-28)

| Theme | Where it lands |
|-------|----------------|
| 1. Brand identity (NICE) | Upstream of the expert segment — not in this insert |
| 2. Concrete proof + precise numbers | v3 Slide 2.2 (accuracy + GIF) and v3 Slide 3.1/3.2 (power) — unchanged |
| 3. Show hardware, latency, power | v3 §Beat 3 (power) — unchanged |
| 4. Highlight ARM and custom GPU work | **Slide N1** (architecture shows both); **Slide N2** banner *"cross-layer change, cross-layer ownership"* |
| 5. Custom hardware focus | **Slide N2** (BCAST is the single best anchor) |
| 6. Show intermediate CLI / live results | v3 Slide 2.2 GIF — unchanged (will be upgraded per §6) |
| 7. Numbers must be precise | already enforced across v3 |
| 8. Go in detail | **Slides N2 + N3** are the depth additions |
| 9. Custom ML solutions for experts | **Slide N3** (RF + flow vs payload + LS=0.1) |
| 10. Show implementation details | **Slide N2** is the implementation-detail slide |
| Point A — drop competitor walkthrough | §2 (delete v3 Slide 1.2) |
| Point B — flow vs payload note | **Slide N3 pull-quote** |

ASIC scaling deeper math: explicitly *not* expanded — user-confirmed low priority since current numbers are already precise.

## 6. Downstream workstreams (after this insert plan locks)

These are **not blocking** the insert plan, but are flagged so they're tracked and can be folded in once done.

1. **500-sample NetFPGA test → replace 20-sample GIF on v3 Slide 2.2.** Same setup as the 20-sample run (`lab10reg.py ids_batch_packets`), but `--n 500`. Record terminal, convert to GIF. Inherits today's 11-16-8-2 silicon model; numbers will likely land near the dev-replay accuracy (BF16-faithful).
2. **Larger-model workstream RESOLVED-NEGATIVE 2026-04-29.** Originally-committed 5-layer **11→64→32→16→2** dropped 2026-04-28 (didn't fit 1,024-word DMEM). Picked **11→32→32→16→2** (2,002 params, fits with ~370-word headroom) as the fits-without-hardware-changes target.

   30-seed empirical sweep ran 2026-04-29 with the v3 recipe (Adam + cosine LR + LS = 0.1 + AW = 1.5 + 200 epochs, rf-seed = 42) on two larger architectures:

   | Architecture | Params | Best KDDTest+ | KDDTrain+ | vs silicon (82.39 %) |
   |---|---:|---:|---:|---:|
   | 11→16→8→2 (silicon) | 218 | **82.39 %** (seed 53) | 97.2 % | baseline |
   | 11→32→16→8→2 | 1,066 | 79.81 % (seed 46) | 98.4 % | −2.58 pp |
   | 11→32→32→16→2 | 2,002 | 79.65 % (seed 45) | 98.5 % | −2.74 pp |

   **Two independent capacity points both regress ~2.6 pp on KDDTest+.** KDDTrain+ rises with capacity (98.4-98.5 % vs 97.2 %) — capacity is **not** the bottleneck; depth opens a generalization gap on KDDTest+ (which contains novel attack categories not in train) that the v3 recipe can't close.

   **Decision 2026-04-29: stop the workstream.** Silicon 11→16→8→2 stays deployed. No kernel rewrite. No N3 / Slide 2.2 architecture update. The negative result becomes a methodological-disclosure asset — see "Things tried that did NOT help" in `docs/ids_accuracy_journey.md` (engineering-side append pending). Q&A line if asked *"could you make it more accurate?"*: *"We tested 5-layer variants on dev — both regressed about 2.6 pp on KDDTest+. The silicon's 4-layer is the right size for this benchmark's generalization profile."*
3. **~~Verify the RF-selected top-11 feature list~~ — DONE 2026-04-28.** Source: `docs/ids_accuracy_journey.md` lines 64-76 (`rf_seed = 42`). Verified list now embedded in Slide N3 DIAGRAM block above. Note: my original placeholder list was significantly off — the actual top-11 includes 3 categoricals (`flag`, `protocol_type`, `service`) and 1 boolean (`logged_in`); `dst_bytes` is #1 (not `src_bytes`); `count` ranks lower than I'd guessed; `srv_count` / `dst_host_count` / `dst_host_serror_rate` aren't in the top 11 at all.

After (1) and (2) land, v3 Slide 2.2 gets a small revision and the insert Slide N3 caption may also gain a note about the dev-only larger model. None of that affects the *structure* of this insert.

## 7. Production cost estimate (this insert only)

| Slide | New visual asset to build | Estimated effort |
|-------|---------------------------|------------------|
| N1 | SoC block diagram | 1.5-2 h (or 30 min if `architecture_simplified.mmd` is reusable) |
| N2 | Two-panel SIMD-lane + cycle-count diagram | 2-3 h (most novel artwork) |
| N3 | 4-layer net diagram + RF importance bar chart + pull-quote layout | 1.5-2 h (RF chart needs a one-time data export from training pipeline) |
| Narration recording | ~75 s of script across the three slides | 30-45 min |

**Total: ~6-8 h** of build + record. Achievable in the Apr 28 → Apr 30 window.

## 8. Decisions locked (2026-04-28 user review)

- ✓ **Order**: Architecture → BCAST → ML methodology.
- ✓ **N2 banner**: removed (diagram + speaker note carry the slide).
- ✓ **N3 encryption mention**: dropped from speaker note and from any prominent slide position. Kept only as a small caption-zone acknowledgement at the bottom of N3 — *"NSL-KDD also includes payload-derived attributes; we chose flow."* Per user 2026-04-28: another team covered the encryption framing today, so we don't re-emphasize; the caption shows we're aware.
- ✓ **N1 accent color**: GPU block only (the GPU is the differentiator).
- ✓ **Slide 1.1 speaker note**: user-locked wording in §2.
- ✓ **N3 RF top-11 features**: verified from `docs/ids_accuracy_journey.md` lines 64-76; full list embedded in §3 N3 DIAGRAM block.

**Remaining work after this lock**: derive `part3_expert_v3_insert_prompts.md` (Claude Design slide-builder prompt + per-diagram prompts) mirroring the format of `part3_expert_v3_prompts.md`. User to request when ready.
