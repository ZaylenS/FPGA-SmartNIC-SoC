# Part 3 Expert — Slide-Generation Prompt (v3 cliff-anchored variant, 2026-04-27)

**Source spec:** `part3_expert_v3.md` (cliff-anchored banner variant). This file is the slide-tool-friendly extract of v3 — strip out the bookkeeping, status block, and Q&A reference content; keep only what a slide builder (or an AI slide tool) needs.

**Audience:** experts (network-security engineers, hardware designers, faculty). Total spoken length ~2.5 min. 7 slides.

---

## How to use this file (Claude Design)

This file is written for **Claude Design** as the slide builder. Claude Design can render diagrams, lay out content with design judgment, and consume rich structured input. Each slide below has up to three input layers:

1. **Title + Banner + Speaker note** — text. Use verbatim. Title is the slide heading; banner is the prominent on-slide tagline; speaker note goes into the notes panel only (never on-slide).
2. **`[DIAGRAM: ...]` blocks** — natural-language descriptions of architectural / flow / comparison diagrams. **Render these as designer-quality diagrams** (architecture flows, block diagrams, log-scale bar charts, contrast diagrams). Do NOT paste the ASCII reference onto the slide — the ASCII is included only as a structural hint for what the diagram should convey.
3. **`[IMAGE: ...]` blocks** — image placeholders. Some are **pre-fetched** (paths under `docs/final_project_progress_present/expert/img/`, see file table at the bottom); others note suggested search sources or DALL-E-style prompts the user can run.

**Slide-design principle (per prof Cho's "nobody reads slide text" feedback):** the visual + banner is the whole slide. Speaker notes carry substance. **Never paste paragraphs of body text on a slide.**

## Style hints
- One font family throughout. Suggest Inter, Helvetica, or system sans-serif.
- Size hierarchy: **title 36–48 pt, banner 22–26 pt, body 14–18 pt**.
- Color scheme: neutral / professional with one accent color reserved for "us" / "our chip". **No animations, no gradients** (per "too crazy" prof feedback).
- **Header strip on every slide** (top-right or top-left, small): *"Expert segment — Zilin Shao | EE533 Final Project Progress — 2026-04-28"*.

## Top-level prompt (copy-paste into Claude Design)

> You are Claude Design generating a 7-slide expert-segment presentation for an EE533 final project, *"ML-based Intrusion Detection on Custom SoC"*. For each slide below, render the **Title** as the slide heading and the **Banner** as a prominent on-slide tagline; copy the **Speaker note** verbatim into the slide's speaker-notes panel (never put it on the slide). Where you see a **`[DIAGRAM: ...]`** block, render it as a designer-quality diagram (architecture flow, comparison flow, log-scale bar chart, etc.) — use your full diagram-rendering capability; the ASCII reference is a structural hint only and must not appear on the slide. Where you see a **`[IMAGE: ...]`** block, insert the referenced image (pre-fetched paths or suggested sources noted). Apply minimal on-slide text per the slide-design principle: the visual + banner is the slide; never paste paragraphs of body text. Use a neutral professional theme — one font family, neutral colors with one accent color reserved for *"us / our chip"*, no animations or gradients. Header strip on every slide: *"Expert segment — Zilin Shao | EE533 Final Project Progress — 2026-04-28"*. Slides follow:

---

## Beat 0 — Hook (no slide; ~5 s spoken only)

Speaker opens directly with no title slide:

> "So how do our competitors' solutions actually work?"

Cut immediately to Slide 1.1. The header strip on Slide 1.1 carries the speaker's name and segment.

---

## Slide 1.1: Industry network-security silicon — the landscape

**Title:** Industry network-security silicon

**[DIAGRAM:** Two-column landscape layout, vendor logos on each row. Left column header *"Specialized security HW"*; right column header *"Programmable DPUs"*. Same vertical alignment across columns so adjacent rows visually pair up.

Left column rows (top→bottom): **Fortinet**, **Palo Alto Networks**, **Cisco / Snort 3**, **Carnegie Mellon** *(label "Pigasus — academic")*.
Right column rows (top→bottom): **NVIDIA BlueField-3**, **AMD Pensando**, **Intel IPU E2000**, **Marvell Octeon 10**.

Each row: logo on the left of the cell, vendor / product label to the right of the logo. Center the column headers. No additional decoration. Reserve a thin row at the bottom for the banner.

**Use the pre-fetched logos** at `docs/final_project_progress_present/expert/img/`:
- `logo_fortinet.svg` · `logo_cisco.svg` · `logo_cmu.svg` (Carnegie Mellon wordmark, for Pigasus)
- `logo_nvidia.svg` · `logo_amd.svg` · `logo_intel.svg` · `logo_marvell.svg`
- **Palo Alto Networks logo not pre-fetched** — fetch from `https://en.wikipedia.org/wiki/Palo_Alto_Networks` (right-click their infobox logo → save) or a stock fair-use SVG. **]**

**Banner:** *"None do on-die ML inference for IDS."*

**Speaker note (~34 words / ~11 s):**
> "Two camps. Specialized security hardware. General-purpose DPUs. Neither does on-die ML inference for IDS. We'll dig into the four most-public — Fortinet, Palo Alto, Snort 3, and Pigasus — at the architecture, algorithm, and tricks level."

**ASCII reference** *(structural hint only — do not paste on the slide):*

| Specialized security HW | Programmable DPUs |
|---|---|
| Fortinet | NVIDIA BlueField-3 |
| Palo Alto | AMD Pensando |
| Cisco / Snort 3 | Intel IPU E2000 |
| Pigasus *(academic)* | Marvell Octeon 10 |

---

## Slide 1.2: Walkthrough — none put ML at the silicon packet path

**Title:** Walkthrough — none put ML at the silicon path

**[DIAGRAM:** 4-quadrant comparison grid (2 × 2). Each cell contains a centered vendor logo at the top and a single short caption underneath. Equal cell sizes, thin neutral borders, generous padding. Cells in reading order:

- **Top-left — Pigasus (CMU OSDI 2020):** logo = `logo_cmu.svg` (Carnegie Mellon wordmark). Surface "Pigasus" + "CMU OSDI 2020" as small label text under the logo. Caption: ***"Custom FPGA — but Aho-Corasick, no ML."***
- **Top-right — Palo Alto Networks:** logo = Palo Alto Networks wordmark *(manual fetch needed; fall back to the typographic wordmark "Palo Alto Networks" if no logo file)*. Caption: ***"'ASIC' = commodity Cavium + 'inline ML' = cloud trip."***
- **Bottom-left — Snort 3 / Cisco Talos:** logo = `logo_cisco.svg`. Caption: ***"Aho-Corasick (1975) + SIMD lipstick. No ML."***
- **Bottom-right — Nvidia Morpheus + BlueField:** logo = `logo_nvidia.svg`. Caption: ***"Real ML — but commodity GPU / DPU."***

Logos pulled from `docs/final_project_progress_present/expert/img/`. **]**

**ASCII reference** *(structural hint only — do not paste on the slide):*

```
+---------------------+---------------------+
| PIGASUS (CMU 2020)  | PALO ALTO (SP3)     |
|                     |                     |
| Custom FPGA --      | "ASIC" = commodity  |
| but Aho-Corasick,   | Cavium + "inline    |
| no ML.              | ML" = cloud trip.   |
+---------------------+---------------------+
| SNORT 3 / CISCO     | NVIDIA MORPHEUS     |
|                     |                     |
| Aho-Corasick (1975) | Real ML --          |
| + SIMD lipstick.    | but commodity       |
| No ML.              | GPU / DPU.          |
+---------------------+---------------------+
```

**Banner:** *"Four ways to skip the inline-ML-on-silicon quadrant."*

**Speaker note (~50 words / ~17 s):**
> "Quick walkthrough — four representative competitors. Pigasus, our academic FPGA peer: custom silicon for IDS, but pure pattern matching. Palo Alto's SP3 isn't custom silicon, just commodity Cavium cores; their inline ML is a cloud roundtrip. Snort 3 — Aho-Corasick from 1975 with SIMD lipstick. Nvidia Morpheus: real ML for IDS, but commodity GPU / DPU."

---

## Slide 1.3: Fortinet — they built the silicon. They just stopped one step short.

**Title:** Fortinet — built the silicon, stopped one step short

**[DIAGRAM:** Three-plane horizontal architecture diagram. Three labeled containers, left-to-right, connected by labeled arrows. Visual emphasis on Plane 1 (the silicon path).

- **Plane 1 — "FortiGate appliance"** (rectangular container; subtle accent border to mark this as the inline data path). Inside, two stacked sub-blocks:
  - Top sub-block: *"NP7 ASIC — sigs only, NO ML"* (small monospace label "NP7" + cross-out style on "ML" to underline that ML is *not* on this silicon).
  - Bottom sub-block: *"host CPU — AI/ML IPS classifier (re-scorer)"*.
  - Below the container: caption ***"inline data path (line rate)"***.
- **Plane 2 — "FortiNDR appliance (separate box)"** (rectangular container, neutral border). One sub-block: *"GPU + Deep Neural Network — patent-pending, weekly model updates"*. Below: caption ***"mirrored / off path (post-hoc)"***.
- **Plane 3 — "FortiGuard cloud"** (cloud-shape container, off to the right). One sub-block: *"sandbox + threat intel"*. Below: caption ***"cloud roundtrip (slow)"***.
- **Arrows:** thick arrow into Plane 1 from the left labeled *"live traffic"*; arrow Plane 1 → Plane 2 labeled *"mirror to NDR"*; arrow Plane 2 → Plane 3 labeled *"file extract"*.

**Use the Fortinet logo** at `docs/final_project_progress_present/expert/img/logo_fortinet.svg` as a small mark on the FortiGate plane (top-left of Plane 1).

Optional supplemental — if you want product photos as small insets next to each plane:
- FortiGate 3800G chassis: `https://www.fortinet.com/products/next-generation-firewall/fortigate-3800g` (or datasheet PDF). Skip if unavailable.
- FortiNDR appliance: `https://www.fortinet.com/products/network-detection-and-response`. Skip if unavailable.

Style: clean engineering schematic, neutral background, three planes same height, minor accent-color highlight on Plane 1 to emphasize "this is the silicon path." **]**

**ASCII reference** *(structural hint only — do not paste on the slide):*

```
+----------------+    +----------------+    +----------------+
| FortiGate      |    | FortiNDR       |    |  FortiGuard    |
|                |    | (separate box) |    |   (cloud)      |
| +----+ +-----+ |    | +-----------+  |    | +-----------+  |
| | NP7| |host | |    | |   GPU     |  |    | | sandbox + |  |
| |sigs| | CPU | |    | |  + DNN    |  |    | | threat    |  |
| | NO | |+ML  | |    | +-----------+  |    | | intel     |  |
| | ML | |     | |    |                |    | +-----------+  |
| +----+ +-----+ |    |                |    |                |
+--------+-------+    +--------+-------+    +--------+-------+
         |                     |                     |
   inline data path       off path             cloud roundtrip
        (line rate)         (post-hoc)
```

**Banner:** *"Their flagship: 800 Gbps firewall → 200 Gbps with IPS engaged. Fortinet built the silicon and stopped one step short. We put inspection in silicon."*

**Speaker note (~95 words / ~32 s):**
> "Fortinet — biggest name in network security. They invested in custom silicon for security: NP7 ASIC at 200 gigabits, signature offload only. Then they kept ML off that chip. ML runs on the FortiGate host CPU as a re-scorer, on a separate FortiNDR appliance off the data path, and in FortiGuard cloud. Three planes, three latency tiers, three silicons. And here's the cliff — their flagship hits 800 gigabits firewall, but with IPS engaged drops to 200. They built the silicon and stopped one step short. We put inspection in silicon."

---

## Slide 2.1: ML inference at the silicon packet path

**Title:** ML inference at the silicon packet path

**[DIAGRAM:** Two-row contrasting flow diagram (THEM vs US). The visual asymmetry is the message: top row long and crowded, bottom row short and compact.

- **TOP ROW — labelled "Their stack (e.g. Fortinet's 3 planes)":** Four icons left-to-right with three labelled arrows between them.
  - **Icon 1:** edge device (laptop / IoT sensor / generic endpoint).
  - **Icon 2:** FortiGate appliance (rack-mount server icon). Small label below: *"sigs ASIC"*.
  - **Icon 3:** FortiNDR appliance (rack-mount server icon, optionally with a small "GPU" mark). Small label: *"ML, off-path"*.
  - **Icon 4:** cloud (cloud-shape icon). Small label: *"more ML, cloud"*.
  - Arrows between icons (no labels needed; the captions under the icons carry the point).
  - **Sub-caption below the entire row:** *"3 chips, 3 boxes, 3 latency tiers."*

- **BOTTOM ROW — labelled "Our stack":** Three icons, much shorter.
  - **Icon 1:** edge device (smartphone / IoT sensor — pick the same family icon used in the top row to make the contrast cleaner).
  - **Icon 2:** single chip (highlighted in accent color, visually emphasized — slightly larger or with a subtle glow / accent border). Small label: *"on-die ML, line rate"*.
  - **Icon 3:** verdict (checkmark / "PASS·BLOCK" indicator).
  - Two arrows between icons.
  - **Sub-caption below the row:** *"1 chip, on-die ML, line rate."*

Style: same icon family / line weight across both rows so the contrast is purely *count of boxes*, not *style of icons*. Top row visually fills more horizontal space (long, segmented). Bottom row compact (short, single hop). Use the accent color reserved for "us" only on Icon 2 of the bottom row.

Source for icons: Claude Design's icon library, or stock libraries (Material Icons, Heroicons). Skip explicit photos. **]**

**ASCII reference** *(structural hint only — do not paste on the slide):*

```
THEM (e.g. Fortinet's 3 planes):

   device --> FortiGate --> FortiNDR --> FortiGuard
              (sigs ASIC)  (ML, off-    (more ML,
                            path)        cloud)


US:

   edge IoT / phone --> [ our chip ] --> verdict
                        on-die ML, line-rate
```

**Banner:** *"All on a single chip — no host trip, no appliance, no cloud. Sized for the edge."*

**Speaker note (~55 words / ~18 s):**
> "Fortinet built custom silicon for security and stopped one step short — kept ML off the chip. We took the next step. Custom silicon plus on-die ML — that empty position isn't shipping anywhere. And we're sized for the edge: IoT, embedded, phones, low-power. Where the big players don't economically reach."

---

## Slide 2.2: Headline result — silicon agrees with dev

**Title:** Headline result — silicon agrees with dev

**[DIAGRAM:** Two metric "result cards" side-by-side, plus the live demo GIF anchoring the right-hand card. **The two-card role-split is the point — do not merge them; visually distinct framing per card.**

- **LEFT CARD — "Benchmark accuracy"** *(headline accuracy claim with explicit train/test gap; revised 2026-04-29).* Two stacked sub-blocks separated by a thin divider, both inside the same card:

  - **Training-set sub-block** — Header: *"KDDTrain+ training set (n = 125,973)"*. One stat row:
    - **Accuracy:** 97.2 %

  - **Held-out benchmark sub-block** — Header: *"KDDTest+ held-out — unseen attack-feature combinations (n = 22,544)"*. Four stat rows:
    - **Accuracy:** 82.4 %
    - **F1 (attack):** 0.848
    - **Attack recall:** 0.864
    - **Attack precision:** 0.833

  Visual emphasis: render the two sub-blocks with a clear divider but on the same card so the **14.8 pp generalization gap** between 97.2 % (train fit) and 82.4 % (held-out) is visible at a glance. This gap is the methodological-disclosure asset — it distinguishes our audited result from unaudited "99 %" numbers other teams may show without disclosing whether they're reporting train or held-out accuracy.

- **RIGHT CARD — "FPGA live demo"** *(silicon-agrees-with-dev evidence).* Header: *"FPGA live demo — n = 20, recorded 2026-04-27"*. Body: five stat rows + the GIF embedded directly underneath:
  - **Accuracy:** 18 / 20 = 90 %
  - **Attack recall:** 10 / 10 = 100 %
  - **F1 (attack):** 0.909
  - **Latency:** ~6 ms / packet
  - **Silicon vs dev:** ±0.01 logit (BF16 noise)
  - **GIF embedded:** path `docs/final_project_progress_present/diagrams/ids_live_demo.gif`. *(GIF is TODO — must be produced from a screen recording of `lab10reg.py ids_batch_packets 20 test_features.csv` taken 2026-04-27 at delay = 1.5 s; crop start = "Ready for 20 packets" line, crop end = end of `BATCH RESULTS SUMMARY`; strip model-loading preamble.)*

Style: each card has a thin neutral border, padding, a header strip in a slightly different shade so the two cards visually separate. Stat values bold and large; labels smaller. Banner / killer takeaway is *not* on this slide — let the metrics + GIF carry the message. **]**

**ASCII reference** *(structural hint only — do not paste on the slide):*

```
+----------------------------------------------------------+
| RESULT                                                   |
|                                                          |
|  Training set -- KDDTrain+         (n = 125,973)         |
|     Accuracy           97.2 %                            |
|                                                          |
|  Held-out benchmark -- KDDTest+    (n = 22,544;          |
|                          unseen attack combinations)     |
|     Accuracy           82.4 %                            |
|     F1 (attack)        0.848                             |
|     Attack recall      0.864                             |
|     Attack precision   0.833                             |
|                                                          |
|  FPGA live demo -- n = 20, recorded 2026-04-27           |
|     Accuracy           18/20 = 90 %                      |
|     Attack recall      10/10 = 100 %                     |
|     F1 (attack)        0.909                             |
|     Latency            ~6 ms / packet                    |
|     Silicon vs dev     +/- 0.01 logit (BF16 noise)       |
|                                                          |
|  [GIF: 20-packet live inference on team-6 FPGA]          |
+----------------------------------------------------------+
```

**Speaker note (~65 words / ~22 s — revised 2026-04-29, train/test gap made explicit):**
> "97 percent on KDDTrain+ — the training set. 82.4 percent on KDDTest+ — the held-out benchmark with unseen attack-feature combinations not in training, about 22 and a half thousand packets. The FPGA agrees with our dev replay. The live demo right here shows 18 of 20 classified correctly, and every attack got caught. Six milliseconds per packet with PCI overhead, end-to-end."

---

## Slide 3.1: Measured FPGA + projected ASIC

**Title:** Measured FPGA + projected ASIC power

**[DIAGRAM:** Side-by-side composition: two stacked tables on the left (measured + projected — content below), with a small **process-node scaling visual** on the right.

The scaling visual is a horizontal sequence: **90 nm FPGA → 90 nm ASIC → 28 nm ASIC → 7 nm ASIC**. Render each node as a chip-shape icon with the power number below it (2.67 W → ~430 mW → ~100 mW → ~30–50 mW). Shrink the chip-icon size at each step (or shrink an associated power-bar height) so the projection direction is obvious. Highlight **28 nm ASIC** as the headline target (accent color or a subtle marker like "← target node").

If the slide gets too busy, drop the scaling visual and keep just the tables — the tables alone already make the point. **]**

**Table 1 — measured (Xilinx XPower, 2026-04-26):**

| Domain | Power |
|---|---|
| Total full chip | 2,674 mW |
| Quiescent (static) | 159 mW |
| Dynamic clocks | 817 mW |
| Dynamic logic | 729 mW |
| Dynamic signals | 678 mW |
| Dynamic IOs | 292 mW |

**Table 2 — projected (Kuon & Rose TCAD 2007 + standard process scaling):**

| Node | Total power | Reasoning |
|---|---|---|
| 90 nm FPGA (measured) | **2,674 mW** | XPower v2 |
| 90 nm ASIC (projected) | ~**430 mW** | ÷6 dynamic gap (BRAM/mult-blended) |
| **28 nm ASIC (projected)** | ~**90–110 mW** | **3 process generations, ~5× V²+C reduction** |
| 7 nm ASIC (projected) | ~**30–50 mW** | Further ~2–3× scaling |

**Speaker note (~70 words / ~23 s):**
> "We measured the full chip at 2.67 watts on the FPGA — 90 nanometer, includes all NetFPGA platform infrastructure. Applying Kuon & Rose's published FPGA-to-ASIC scaling and standard process scaling, our SoC projects to about 90–110 milliwatts at 28 nanometer; 30–50 at 7 nanometer. Conservative even against Fortinet's only disclosed silicon node — FortiSP5 at 7 nanometer."

---

## Slide 3.2: Power positioning — IoT-edge with on-die NN

**Title:** Power positioning — IoT-edge with on-die NN

**[DIAGRAM:** Horizontal bar chart on a **log10 power scale**, titled *"Power per IDS workload"*. Five horizontal bars, sorted ascending so the contrast lands visually. X-axis labelled in watts at decade ticks: **0.1, 1, 10, 100, 1000, 10000 W**. Background gridlines at each decade.

Bars top-to-bottom (use the accent color reserved for "us" on rows marked ★, and a neutral color for competitors):

| Row | Power | Detection task | Color |
|---|---|---|---|
| ★ Our SoC (projected 28 nm ASIC) | **~0.1 W (100 mW)** | ML classification | accent |
| ★ Our SoC (FPGA today, 90 nm) | 2.67 W | ML classification | accent (lighter) |
| FortiGate 200G (mid) | 145 W | Signature matching | neutral |
| NVIDIA BlueField-3 (DPU, 7 nm) | up to 150 W | general programmable | neutral |
| FortiGate 3800G (flagship) | 1,496 W | Signature matching | neutral |

Each bar:
- Power number annotated at the right end of the bar (right of the bar tip if bar is short, inside the bar if bar is long).
- Detection task in italics, right-aligned in the row gutter (or below the row label).

Visual emphasis: the two ★ accent bars sit at the left end of the chart (small / short); the three neutral bars dominate the right side of the chart. This directly visualizes the **1000×+ power gap** between our projected design point and FortiGate's flagship.

Optional supplemental: render the table below the chart as a small reference table — Claude Design can lay out chart + table together, but the chart is the headline. **]**

**Reference table** *(supplemental — Claude Design can render alongside the chart, or as the chart's caption block):*

| | Power | Detection task |
|---|---|---|
| Our SoC (FPGA today, 90 nm) | 2.67 W full chip | ML classification |
| **Our SoC (projected 28 nm ASIC)** | **~100 mW** | ML classification |
| FortiGate 200G (current mid) | 145 W appliance | Signature matching |
| FortiGate 3800G (current flagship) | 1,496 W appliance | Signature matching |
| NVIDIA BlueField-3 (DPU, 7 nm) | up to 150 W | general programmable |

**Banner:** *"IoT-edge power (<200 mW projected) with on-die NN inference."*

**Speaker note (~45 words / ~15 s):**
> "Context. Fortinet's current mid runs at 145 watts; their flagship, 1.5 kilowatts. BlueField up to 150 watts. Our projected design point at 28 nanometer is sub-200 milliwatts — three-plus orders of magnitude lower. This is the gating constraint at the edge: nothing else fits."

---

## End: stop here. No outro. (Per user direction 2026-04-26.)

---

## Asset checklist

Two categories: **logos / images** that Claude Design embeds, and **diagrams** that Claude Design *renders* from the `[DIAGRAM: ...]` blocks. The diagrams don't need pre-fetched assets — Claude Design generates them. Only logos, product photos, and the live-demo GIF need fetching.

### Logos — Slides 1.1 + 1.2 (fair-use educational)

✓ = pre-fetched 2026-04-27 from Wikipedia Commons. **TBD** = needs manual fetch.

| Asset | Status | Path (relative to `docs/final_project_progress_present/`) |
|---|---|---|
| Fortinet logo | ✓ saved | `expert/img/logo_fortinet.svg` (2,968 B) |
| Palo Alto Networks logo | **TBD** — Wikipedia URL didn't resolve through the standard pattern. Fetch manually from `https://en.wikipedia.org/wiki/Palo_Alto_Networks` (right-click their infobox logo → save as SVG). | `expert/img/logo_paloalto.svg` *(target path)* |
| Cisco logo | ✓ saved | `expert/img/logo_cisco.svg` (2,396 B) |
| NVIDIA logo | ✓ saved | `expert/img/logo_nvidia.svg` (665 B) |
| AMD logo | ✓ saved | `expert/img/logo_amd.svg` (694 B) |
| Intel logo | ✓ saved | `expert/img/logo_intel.svg` (2,811 B) |
| Marvell logo | ✓ saved | `expert/img/logo_marvell.svg` (2,727 B) |
| Carnegie Mellon wordmark (for Pigasus) | ✓ saved | `expert/img/logo_cmu.svg` (9,435 B) |

### Optional product photos — Slide 1.3 (small insets only)

The Slide 1.3 `[DIAGRAM: ...]` block renders the 3-plane architecture from a description; product photos are *optional* small insets (skip cleanly if unavailable).

| Asset | Suggested source |
|---|---|
| FortiGate 3800G chassis photo | `https://www.fortinet.com/products/next-generation-firewall/fortigate-3800g` (or the 3800G datasheet PDF) |
| FortiNDR appliance photo | `https://www.fortinet.com/products/network-detection-and-response` |

### Diagrams — Claude Design renders from prompts (no fetch needed)

| Slide | Diagram |
|---|---|
| Slide 1.1 | 2-column landscape layout with vendor logos |
| Slide 1.2 | 4-quadrant comparison grid with logos + killer phrases |
| Slide 1.3 | 3-plane horizontal architecture (FortiGate · FortiNDR · FortiGuard) |
| Slide 2.1 | THEM-vs-US two-row contrast flow |
| Slide 2.2 | Two side-by-side metric cards + embedded GIF |
| Slide 3.1 | Power tables + small process-node scaling visual |
| Slide 3.2 | Horizontal log-scale power bar chart |

### Critical custom asset (must produce yourself, no substitute)

| Asset | How to produce | Path |
|---|---|---|
| **Live demo GIF** for Slide 2.2 | Run `lab10reg.py ids_batch_packets 20 test_features.csv` on team-6 FPGA at delay = 1.5 s; capture screen recording; convert to GIF (cropped — start at "Ready for 20 packets", end at end of `BATCH RESULTS SUMMARY`; strip model-loading preamble). | `docs/final_project_progress_present/diagrams/ids_live_demo.gif` |

---

## Files saved 2026-04-27

Saved to `docs/final_project_progress_present/expert/img/`:
- `logo_fortinet.svg`
- `logo_cisco.svg`
- `logo_nvidia.svg`
- `logo_amd.svg`
- `logo_intel.svg`
- `logo_marvell.svg`
- `logo_cmu.svg` *(Carnegie Mellon wordmark, for Pigasus)*

Still pending:
- `logo_paloalto.svg` — Wikipedia commons URL didn't resolve via the standard pattern; fetch manually.
- All product photos (FortiGate 3800G, FortiNDR) and stock icons (cloud, edge devices, process-node scaling) — manual fetch / generation per the checklist above.
- The `ids_live_demo.gif` — must be produced from a screen recording on the FPGA.
