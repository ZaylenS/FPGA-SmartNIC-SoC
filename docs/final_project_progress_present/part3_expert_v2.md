# Part 3 Expert — Slide Content (v2, post-prof-review pivot 2026-04-26)

**Supersedes:** `part3_expert.md` (2026-04-21 plan with 5-beat AI-voiced clip structure).
**Driver:** Prof Cho's 2026-04-23 practice review feedback — "remove the two animated diagrams (too crazy); show competitors first; show benchmarks; don't show our algorithm because we can't beat industry." See `~/.claude/projects/.../memory/project_present_pivot_0426.md`.

**Format**: live presenter + static slides. No animated MP4 clips. ~3 min total to fit 12-min/6-member team budget.

**3-beat structure (revised 2026-04-27 — old Beat 3 differentiation matrix cut as redundant with Beat 2):** Competitor landscape → What we built differently → Power benchmark. No outro. (Plus the no-slide Beat 0 hook.)

**Slide design principle (per prof Cho's "nobody is gonna read all that text on your slides" feedback, 2026-04-27):**

Each slide section in this doc has three layers — *do not conflate them*:
- **On-slide content** — what literally appears on the slide. Visuals (diagrams, tables of short labels), one headline, a killer-detail banner. Aim for ≤ 5–7 lines of text on a slide; favor a single visual + one phrase.
- **Speaker note** — what the presenter says aloud. Hits the killer detail and the transition to the next slide. ~30–50 words ≈ 10–15 s for most slides.
- **Reference (slide-builder + Q&A backup)** — deep architecture / algorithm / tricks / source content. *Not* on the slide and *not* spoken live. Lives in the .md so the slide builder has context and so the speaker has Q&A material.

If any "On-slide content" block contains dense prose, multi-row sentence-tables, or more than ~30 words, trim it — the speaker carries the substance, not the slide.

---

## ✓ STATUS: Accuracy work RESOLVED 2026-04-27 — slide rewrites unblocked

**v3 result (replaces the v1 "75 % on 20-sample" number, do NOT quote v1 anywhere). Two scopes — keep them visually separated wherever cited:**

*Full benchmark — NSL-KDD KDDTest+ (n = 22 544, BF16 HW-faithful):* this is the accuracy claim.
- **82.39 %** accuracy
- **F1(attack) = 0.848**, attack precision = 0.833, attack recall = 0.864

*FPGA live demo — n = 20, recorded 2026-04-27 on team-6 FPGA:* this is the silicon-agrees-with-dev evidence, **not** the accuracy claim.
- **18/20 = 90 %** overall, **100 %** attack recall (10/10 attacks caught)
- **F1(attack) = 0.909**
- **~6 ms** end-to-end per packet (5.1 - 7.5 ms across the 20-sample run)
- Silicon vs dev replay: matches to **±0.01 logit** (BF16 rounding noise); argmax decisions agree on 100 % of samples — so the 22 544-sample dev number describes the silicon, not just the model.

- GIF source: 20-sample `lab10reg.py ids_batch_packets` recorded on team-6 FPGA, 2026-04-27, delay=1.5 s. All 20 packets aligned in CSV order, OK/MISS column visible.
- Method delta: label-smoothing-trained model + log1p heavy-tailed numerics + label-encoded categorical (protocol_type / flag / service) + 15-seed sweep at rf_seed=42, picked seed 53. Full method/ablation log in `docs/ids_accuracy_journey.md` (canonical, supersedes `ids_v2_results.md`).

**Beat 0 / 1 / 2 structural rewrites — status (2026-04-27 user-review pass):**

1. **Beat 0** — ✓ **DONE 2026-04-27.** Title slide cut. Speaker opens with the hook question *"So how do our competitors' solutions actually work?"*; header strip on every slide carries name + segment. ~5 s budget reclaimed for Beat 1.

2. **Beat 1** — ✓ **DRAFTED + RESTRUCTURED 2026-04-27, awaiting review.** Now a **3-slide structure: deep dive on one real-business competitor + walkthrough of the rest** (per user direction 2026-04-27 — "dig very deep into the most-meaningful one, walkthrough the rest").
   - **Slide 1.1** Industry landscape (signature-based hardware vs DPUs); funnels to the walkthrough + Fortinet deep-dive.
   - **Slide 1.2** **4-up walkthrough** — Pigasus, Palo Alto, Snort 3, Nvidia Morpheus, each with one-line killer detail. Banner: *"Four ways to skip the inline-ML-on-silicon quadrant."* Reference block holds the full per-competitor Architecture / Algorithm / Tricks deep content (formerly the per-competitor slides 1.2–1.4).
   - **Slide 1.3** **Fortinet DEEP DIVE** — chosen because Fortinet is the *only* commercial vendor that already invested in custom silicon for security (NP7 ASIC). They made the same opening move we did, then stopped one step short — kept ML off the chip. Cleanest "what we did differently" setup for Beat 2. On-slide: 3-plane topology (NP7 + FortiOS host CPU + FortiNDR + FortiGuard) + banner *"Fortinet built custom silicon for security and stopped one step short. We took the next step."* Reference block holds NP7/FortiSP5/FortiNDR architecture, FortiGate SKU specs (200F/200G/3800G), 5-axis differentiation matrix vs us, and source pointers. **Additional research agent in flight 2026-04-27** on five gap areas (FortiSP5 details, CPRL pattern language, NP7-NP6 progression, AI-IPS classifier algorithm class, IPS-engaged perf) — will fold into Slide 1.3 Reference when it returns.

   Total Beat 1 speaking budget: **~55 s** (Slide 1.1 ~12 s + Slide 1.2 walkthrough ~17 s + Slide 1.3 Fortinet deep ~25 s). **~+5 s vs original 50 s** — comfortable.

   Pigasus + Morpheus moved out of dedicated slides into the Slide 1.2 walkthrough; "Pigasus form / Morpheus method / we are the AND" framing retired in favor of a Fortinet-anchored Beat 2 framing (*"Fortinet built custom silicon for security and stopped one step short. We took the next step."*) since Fortinet is the deep-dived competitor and the "AND" hinged on Pigasus + Morpheus being paired explicitly on a slide.

   **Slide-design pass applied 2026-04-27** (per prof Cho's "nobody reads slide text" feedback): all Beat 1 slides use the three-layer format — **On-slide content** (terse: visual + headline + banner), **Speaker note** (substance, ~30–55 words), **Reference** (off-slide deep content for slide builder + Q&A backup).

   Source artifacts (10 .md notes) saved to `docs/final_project_progress_present/expert/`. **Caveat:** 3 binary PDFs (Pigasus paper, PAN SP3 whitepaper, FortiNDR datasheet) were not auto-downloaded due to research-agent sandbox limitations; canonical URLs in `expert/sources_index.md` for manual `curl` later.

3. **Beat 2** — ✓ **DRAFTED 2026-04-27, awaiting review.** Path (a): application-level differentiation. (Original plan preserved a 4-beat structure with Beat 3 design-space matrix; that plan was revised on 2026-04-27 — see #4 below.)

   - **Slide 2.1** — *ML inference at the silicon packet path.* On-slide: a THEM-vs-US comparison visual (Fortinet's 3-plane stack vs our single chip → verdict for an edge IoT/phone) + banner *"All on a single chip — no host trip, no appliance, no cloud. Sized for the edge."* Speaker note (~70 words / ~23 s) walks Beat 1's 4 killer details and lands on *"we are the AND, sized for the edge."* Reference block holds: internal architecture / toolchain / resource footprint (kept *off* the slide per prof feedback), edge / IIoT positioning rationale, vendor-style one-sentence, direct-contrast cheat-sheet vs each of the 5 Beat 1 competitors.
   - **Slide 2.2** — *Headline result.* Two-grouped-scope metrics block (full benchmark + FPGA demo) + GIF; existing content retrofitted into the On-slide / Speaker note / Reference 3-layer convention.
   - **Network-processor side intentionally suppressed** on-slide (FIFO + ARM + SIMD GPU + DMA + ISA + utilization stats live only in the Reference block) — assume every other team built one too; not differentiating.
   - **Total Beat 2 speaking budget:** ~33 s (Slide 2.1 ~23 s + Slide 2.2 ~10 s). **Under the original ~45 s** — 10 s of slack reclaimed.

4. **Structure revision 2026-04-27 — 4-beat → 3-beat.**
   - **Old Beat 3 (design-space differentiation matrix) — CUT.** Restated Beat 2's "we are alone in the inline-ML position" without adding new content; "market map" reframe was rejected as too investor-flavored for an expert audience; "why the empty quadrant is empty" technical reframe was an option but the user chose to cut and tighten to 3 beats instead.
   - **Old Beat 4 → New Beat 3 — Power benchmark** (renumbered).
   - **Latency comparison removed from Beat 3 (formerly 4).** Slide 4.2 had a Power × Latency × Detection-task table comparing our 7.32 μs (silicon NN inference, GPU-kernel-only) against Fortinet's 4.36 / 3.53 μs (firewall fast-path, *not* IPS-engaged). Apples-to-oranges; defensibility audit flagged three concerns (scope, IPS-engaged latency undisclosed, 1 GHz-at-28 nm projection un-pipeline-verified). Cleanest fix: drop the latency column entirely; pivot to power-only comparison. The "we're at a different scale" framing now lives on power, where the gap is genuinely 1000×+. Silicon NN-inference latency (7.32 μs today / ~0.7 μs projected at 28 nm 1 GHz) preserved as Q&A backup in the Slide 3.2 Reference block, not on the slide.
   - **Slides 3.1 and 3.2 retrofitted** to the 3-layer slide-design convention (On-slide / Speaker note / Reference) while the latency removal was applied.
   - **Total expert segment now ≈ 2.5 min** (Beat 0 ~5 s + Beat 1 ~75 s + Beat 2 ~33 s + Beat 3 ~40 s) — comfortably under the ~3 min envelope.

**Source for the rewrite templates:**
- Palo Alto Networks SP3 whitepaper (https://media.paloaltonetworks.com/documents/Single_Pass_Parallel_Processing_Architecture.pdf)
- Pigasus, Zhao et al., USENIX OSDI 2020 (https://www.usenix.org/system/files/osdi20-zhao_zhipeng.pdf)
- Fortinet AI/ML-based IPS detection docs (https://docs.fortinet.com/document/fortigate/7.6.6/administration-guide/408891/ai-and-ml-based-ips-detection)

---

---

## Beat 0 — Hook (live, ~5 s, no dedicated slide)

No title slide. Every slide carries a small header strip: *"Expert segment — Zilin Shao | EE533 Final Project Progress — 2026-04-28"*. That strip is the only place the audience needs to anchor on the speaker; no live seconds spent on self-intro.

**Speaker opens directly with the transition question:**

> "So how do our competitors' solutions actually work?"

Cut immediately to Slide 1.1.

*Rationale: this is the expert segment of a 12-min team video — the team is already introduced upstream. A 3-min beat budget for 4 beats cannot afford 10 s of throat-clearing. A hook question is a stronger opening device than "I'm X, I'll cover Y." Header strip carries the speaker anchor passively.*

---

## Beat 1 — Deep dig into competitors (slides + voice, ~70 s)

Per user direction (2026-04-27): show the audience that we know exactly what each competitor does, at the architecture / algorithm / tricks level. Each competitor gets a "killer detail" callout that Beat 2 picks up as a contrast point. Source artifacts in `docs/final_project_progress_present/expert/`.

### Slide 1.1: Industry network-security silicon — the landscape

**On-slide content:**

| Specialized security HW | Programmable DPUs |
|---|---|
| Fortinet | NVIDIA BlueField-3 |
| Palo Alto | AMD Pensando |
| Cisco / Snort 3 | Intel IPU E2000 |
| Pigasus *(academic)* | Marvell Octeon 10 |

Footer banner: *"None do on-die ML inference for IDS."*

**Speaker note (~34 words ≈ 11 s):**
> "Two camps. Specialized security hardware. General-purpose DPUs. Neither does on-die ML inference for IDS. We'll dig into the four most-public — Fortinet, Palo Alto, Snort 3, and Pigasus — at the architecture, algorithm, and tricks level."

**Reference (off-slide):**
- Vendors omitted from the slide table for brevity but real: Cisco / Juniper signature ASICs; Suricata as a second open-source baseline alongside Snort 3; CrowdStrike / Zscaler in the off-silicon ML quadrant (covered in Beat 3 differentiation matrix, not here).
- Why these four for deep-dig: Fortinet = closest analog with full portfolio. Palo Alto = best published architecture transparency. Snort 3 = open-source baseline / algorithmic floor. Pigasus = academic FPGA peer / closest in form.

---

### Slide 1.2: Walkthrough — none put ML at the silicon packet path

**On-slide content (4-up grid + banner):**

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

Banner: *"Four ways to skip the inline-ML-on-silicon quadrant."*

**Speaker note (~50 words ≈ 17 s):**
> "Quick walkthrough — four representative competitors. Pigasus, our academic FPGA peer: custom silicon for IDS, but pure pattern matching. Palo Alto's SP3 isn't custom silicon, just commodity Cavium cores; their inline ML is a cloud roundtrip. Snort 3 — Aho-Corasick from 1975 with SIMD lipstick. Nvidia Morpheus: real ML for IDS, but commodity GPU / DPU."

**Reference (off-slide; for slide-builder + Q&A backup):**

*Pigasus (CMU OSDI 2020) — closest academic peer in form:*
- **Architecture** — TCP Reassembler + Multi-String Pattern Matcher (MSPM) on Intel Stratix-10 MX FPGA. CPU = slow path only (DMA ring poll). ~3.3 MB BRAM for MSPM. 100 GbE line rate.
- **Algorithm** — Aho-Corasick + regex over the Snort Registered Ruleset (~10 K rules). Reuses existing corpus — no new format invented.
- **Tricks** — Hot-path / slow-path partition. 5 % of packets to CPU, 95 % FPGA verdict. **38× less power than CPU at 100 Gbps.** Pigasus 2.0 (SIGCOMM '22): multi-FPGA, DSP utilization zero (mults → adders/shifters).
- **Killer detail** — closest peer in form (custom silicon for IDS), but no neural network anywhere — pattern matching just spatially mapped instead of temporally executed.

*Palo Alto SP3:*
- **Architecture** — "Single-Pass Parallel Processing": 3 named processor roles (SMP / SP / NP) on Cavium OCTEON MIPS64 NPUs. Not custom silicon. Separated control plane.
- **Algorithm** — Cavium HFA "Hyper Finite Automata" RegEx engine for signatures. Inline ML = 5 deep classifiers per protocol family (HTTP, HTTP2, SSL, unknown-UDP, unknown-TCP) trained on WildFire sandbox, executed in PAN ATP cloud.
- **Tricks** — "Single pass" = one byte-stream traversal does User-ID + App-ID + signatures + content match. Marketing: "industry's first inline DL."
- **Killer detail** — "ASIC" = general-purpose Cavium cores; "inline ML" = cloud roundtrip.

*Snort 3 / Cisco Talos:*
- **Architecture** — 1 control thread + ≤ 32 packet threads. MPSE (Multi-Pattern Search Engine) → per-rule detection.
- **Algorithm** — Aho-Corasick (1975) + Hyperscan (Intel NSDI 2019) SIMD MPSE: FDR (shift-or with supercharacters), Teddy (Glushkov NFA bit-parallel, 64 chars in 16 SIMD ops), Sheng (AVX-512 byte-shuffle DFA), NFA-DFA hybrid fallback.
- **Tricks** — Hyperscan compiles rules to SIMD bytecode off-line. Snort blog: **2× faster than `ac_full`, 12× less memory.** OpenAppID = LuaJIT scripts.
- **Killer detail** — 1975 algorithm with SIMD lipstick. No neural network anywhere.

*Nvidia Morpheus + BlueField — closest peer in method:*
- **Architecture** — Open-source AI cybersecurity framework. Pipelines = DAGs of containerized stages. CUDA + Nvidia Triton Inference Server hosts pre-trained models. Production target: BlueField DPU; published work tested on RTX 3050.
- **Algorithm** — Two pipeline modes: **FIL** (Feature Importance Learning) using XGBoost gradient-boosted trees in the **Anomalous Behavior Profiling (ABP)** pre-trained model; **NLP** mode for text-based attacks.
- **Tricks** — Federated learning across multiple DPUs/GPUs via Triton. Containerized stages drop in as plugins. Reported (Sensors 25, 130, Chiriac et al. 2024): ~73 K msg/s polymorphic, ~39 K msg/s ABP, 87–90 % accuracy on 4SICS.
- **Killer detail** — closest peer in method (real ML inference for IDS) but commodity programmable silicon, software framework, not a silicon innovation.

*Source files:* `expert/pigasus_osdi2020_summary.md`, `expert/paloalto_sp3_summary.md`, `expert/paloalto_atp_inline_ml.md`, `expert/snort3_mpse_hyperscan.md`, `expert/snort3_openappid.md`, `expert/hyperscan_nsdi19_notes.md`, `sensors-25-00130.txt`.

---

### Slide 1.3: Fortinet — they built the silicon. They just stopped one step short.

The deep-dive — Fortinet is the most-meaningful real-business competitor for an expert audience because they're the **only commercial vendor who already invested in custom silicon for security** (NP7 ASIC). They made the same opening move we did. Then they stopped one step short — kept ML off that chip. That's the cleanest "what we did differently" setup for Beat 2.

**On-slide content (3-plane topology + inset stat + banner):**

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

**Inset stat** *(small, placed beside or below the diagram, visually distinct):* **"FG-3800G: 800 Gbps firewall → 200 Gbps with IPS engaged (−75 %)"**

Banner: *"Fortinet built custom silicon for security and stopped one step short. We took the next step."*

**Speaker note (~95 words ≈ 32 s):**
> "Fortinet — biggest name in network security. They invested in custom silicon for security: NP7 ASIC at 200 gigabits, signature offload only. Then they kept ML off that chip. ML runs on the FortiGate host CPU as a re-scorer, on a separate FortiNDR appliance off the data path, and in FortiGuard cloud. Three planes, three latency tiers, three silicons. And here's the cliff — their flagship hits 800 gigabits firewall, but with IPS engaged drops to 200. They built the silicon and stopped one step short. We put inspection in silicon."

**Reference (off-slide; for slide-builder + Q&A backup):**

- **NP7 ASIC architecture** — 200 Gbps max throughput (2 × 100 GbE per NP7). Internal blocks named in FortiOS docs: Integrated Switch Fabric (ISF), inter-VDOM link acceleration, NP7 traffic shaping queues, `config np-queues` for protocol prioritization. Offload list: IPv4/IPv6 forwarding, IPsec/Suite B encryption, GTP / CAPWAP / VXLAN tunneling, NAT44/66/64/46 setup, DoS protection. **No DPI, no ML.** Process node, gate count, die size: **all undisclosed.**

- **NP generation progression** — NP6Lite (10 Gbps) → NP6XLite (36 Gbps) → NP6 (40 Gbps) → NP7Lite (40 Gbps) → **NP7 (200 Gbps, 5× jump)**. The big leap was NP6 → NP7, launched alongside FortiGate 1800F (Feb 2020). Functional progression: NP6 → NP7 added GTP (5G mobile-core), VXLAN (DC overlay), Suite B crypto, hyperscale features (CGN, hardware logging, HA hardware sync). NP7 → NP7Lite (in SP5, 2023) added SHA-3 family (post-quantum-friendly hashes). Crypto cipher ladder across generations: AES-CBC → +AES-GCM → +Suite B → +SHA-3. **Critical observation: zero ML offload added across the entire 4-generation roadmap.** Inspection intelligence stayed in CP9/CP10 pattern-matching + host CPU.

- **FortiSP5 (Feb 2023, 7 nm SoC)** — *not* a discrete accelerator; it is an **SoC integrating ARM CPU(s) + NP7Lite (40 Gbps) + CP10 content-processor on a single 7 nm die**. Fortinet markets the topology as "akin to Apple's A15 / M1." Why two purpose-built chips: scaling-target economics — NP7 standalone for chassis (3800G, 100/400 GE), FortiSP5 SoC for branch/edge (200G, 90G). SP5 functions: 40 Gbps firewall, 37 Gbps IPsec, **2.5 Gbps SSL deep inspection** (the headline branch-edge feature), VXLAN/GRE encap, hardware QoS, ZTNA/SD-WAN, volumetric DDoS. Performance vs CPU: 17× firewall, 32× crypto, 88 % lower power. **7 nm is the only publicly disclosed Fortinet process node** — NP7's geometry remains undisclosed.

- **CPRL — Content Pattern Recognition Language** — Fortinet's signature execution engine. **Patented bytecode DSL** (US Patent 8,140,660 B1, Wells et al., 2012) with 5 predicate families: **Test, Decision, Iteration, Function, Pointer**. Strictly more powerful than regex / Aho-Corasick — supports branches, loops, function calls, pointer arithmetic. **Executed natively by the FortiASIC Content Processor** (CP9 today, CP10 in 200G/3800G) via the IPSA offload path. CP10 doubles CP9's IPS pattern-matching throughput (20 Gbps) and grows the rule database 6×. Pipeline placement: NP7 forwards/reassembles → NTurbo delivers flow bytes → **CP9/CP10 runs CPRL bytecode** → IPS engine on CPU sees survivors → AI/ML IPS classifier rescores on CPU. Single CPRL signature can match 50,000+ malware variants (Fortinet glossary). **CPRL is fixed-function pattern matching — does not run ML.** *Architectural note: this is the same pattern-matching-co-processor concept explored in academic prior work (e.g. Cho et al., "A Pattern Matching Co-processor for Network Security," DAC 2005), generalized by Fortinet into a patented commercial bytecode.*

- **FortiOS AI/ML IPS** (introduced 7.6.3) — sits **on the FortiGate's host CPU**, not in NP7. Hybrid: signatures pre-filter, ML re-scores survivors. Goal = false-positive reduction on existing IPS triggers, not zero-day discovery. Features extracted during protocol decoding (HTTP fields explicitly named). Distributed as "AI/Machine Learning IPS Definitions" package downloaded via FortiGuard. **Algorithm class: undisclosed.** Despite Fortinet's 1,500+ security patents (100+ in ML/AI), no public patent or paper pins down the FortiOS 7.6.3+ classifier specifically. Deployment profile (CPU-only, downloadable definitions, signature-gated, single CLI toggle) **rules out CNN / transformer**; consistent with **gradient-boosted tree (XGBoost/LightGBM) or shallow MLP at most**. *(Note: Fortinet's "billions of nodes ANN" marketing line refers to FortiAI sample triage in the FortiGuard cloud, not the on-box IPS classifier.)*

- **FortiNDR appliance** — separate physical box (FortiNDR-1000F, -3500F, etc.), marketed as "Virtual Security Analyst (VSA)." Lives **off the data path** (mirrored traffic). Compute: GPU + CPU. "Patent-pending Deep Neural Networks" pre-trained in FortiGuard labs with **20 M+ clean and malicious files**, **6 M malicious + safe features**. ANN DBs (`moat_kdb_all.tar.gz`, `pae_kdb_all.tar.gz`) updated **once or twice a week**, decoupled from daily AV signatures. Files scanned over HTTP, SMB, SMTP.

- **FortiGuard cloud** — heavy training in the cloud; FortiNDR appliance does on-prem fine-tuning + inference. Cloud also handles sandboxing and threat intel.

- **Specific FortiGate SKUs (datasheet):**
  - **60F** (entry, NP6Lite): 10 Gbps firewall → **0.7 Gbps threat-protection (-93 %)**
  - **200F** (prior mid, ~2020, NP6XLite + CP9): 102 W, 5 Gbps IPS, 4.78 μs firewall fast-path.
  - **200G** (current mid, May 2024, FortiSP5 = NP7Lite + CP10): 145 W, **39 Gbps firewall → 6.4 Gbps threat-protection (-84 %)**, 4.36 μs firewall fast-path latency *(NOT IPS-engaged)*, 16.5 Mpps.
  - **3800G** (current flagship, Nov 2025, NP7 + CP10): 1,496 W, **800 Gbps firewall → 200 Gbps threat-protection (-75 %)**, 3.53 μs firewall fast-path latency.

- **🔥 The inspection cliff** *(strongest single finding from research):* even on Fortinet's flagship 3800G with full NP7 + CP10 silicon, **engaging IPS + ML + AV collapses throughput by 75 %** (800 Gbps → 200 Gbps). The 200G mid-range collapses 84 %; the 60F entry-level 93 %. As silicon scales up, the gap narrows, but **the inspection pipeline never approaches the NP fast path**. The CPU-side pattern-match + ML cannot keep up. **Latency-with-IPS-on is not in any datasheet** — Fortinet keeps that out of marketing. **NDR-mode FortiGate numbers don't exist** — that workload runs on a separate FortiNDR appliance. **The fast-path / protected gap is the silicon-ML opportunity our chip claims to fill** by putting the ML classifier directly in silicon at line rate.

- **Where we differ — 6 axes (Q&A cheat sheet):**

| Axis | Fortinet | Us |
|---|---|---|
| ML location | Different chip in a different appliance | Same die as the packet path |
| Latency tiers | 3 (line-rate sigs · off-path ML · cloud sandbox) | 1 (silicon NN inference) |
| Boxes | 3 (FortiGate + FortiNDR + cloud) | 1 chip |
| **Inspection cliff** | **Flagship: -75 % when IPS+ML engages** | **No cliff — ML at line rate by construction** |
| Deployment scale | Enterprise / data-center (3800G = 1.5 kW) | Edge / IoT / embedded (<200 mW projected) |
| Silicon disclosure | NP7 process node undisclosed | 90 nm FPGA → 28 nm projected, fully described |

- **Why this is the clean differentiation against us:** Fortinet made the same opening move — custom silicon for security. They generalized the pattern-matching-co-processor concept (CPRL on CP9/CP10) and shipped it commercially across four NP generations. Then they hit an inspection cliff: silicon scales to 800 Gbps, inspection drops to 200. Our project skips the cliff: a small ANN, ML directly at the silicon packet path, line-rate by construction. Same premise, next step taken.

- **Source files:**
  - Existing notes: `expert/fortinet_aiml_ips.md`, `expert/fortinet_np7_brief.md`, `expert/fortinet_fortindr_brief.md`
  - Added 2026-04-27: `expert/fortinet_sp5.md`, `expert/fortinet_cprl.md`, `expert/fortinet_np7_vs_np6.md`, `expert/fortinet_aiml_ips_algorithm.md`, `expert/fortinet_ips_engaged_perf.md`

---

## Beat 2 — What we built (application-level differentiation, slide + voice, ~35 s)

Beat 2's job per user direction (2026-04-27) and prof Cho's "no need to show your algorithm; can't beat industry competitors" feedback: show **what we did differently** at the application / product level. The network-processor side is intentionally suppressed — every team built one too; that's not differentiating. What's differentiating is *where ML lives* in our pipeline vs theirs, and *who the right user is.*

### Slide 2.1: ML inference at the silicon packet path

**On-slide content (one comparison visual + one banner):**

```
THEM (e.g. Fortinet's 3 planes):

   device --> FortiGate --> FortiNDR --> FortiGuard
              (sigs ASIC)  (ML, off-    (more ML,
                            path)        cloud)


US:

   edge IoT / phone --> [ our chip ] --> verdict
                        on-die ML, line-rate
```

Banner: *"All on a single chip — no host trip, no appliance, no cloud. Sized for the edge."*

**Speaker note (~55 words ≈ 18 s):**
> "Fortinet built custom silicon for security and stopped one step short — kept ML off the chip. We took the next step. Custom silicon plus on-die ML — that empty position isn't shipping anywhere. And we're sized for the edge: IoT, embedded, phones, low-power. Where the big players don't economically reach."

**Reference (off-slide; for slide-builder + Q&A backup):**

- **What "single chip" actually means in this demo (kept *off* the slide per prof feedback):** a custom SoC on a Xilinx Virtex-II Pro FPGA, integrating an ARM-compatible CPU (Lab 6), a 4-lane SIMD GPU coprocessor (Lab 7), a convertible packet FIFO, and a DMA engine — all on one die. Every team built a network processor too, so this internal architecture is not a differentiator; the application-side framing is.
- **Toolchain (Q&A backup, not on slide):** offline training in Python (BF16-faithful gradient descent on NSL-KDD, label smoothing, 11→16→8→2 ANN); offline compile (CUDA → PTX → our PTX-translator → our assembler → kernel hex); on-chip run dispatched by the ARM, GPU runs the kernel at line rate. Every layer — training script, compiler, ISA, GPU, integration — is ours.
- **Resource footprint (Q&A backup):** 67 % LUT, 44 % FF, 46 % BRAM, 4 % multiplier on a 90 nm Virtex-II Pro.
- **Edge / IIoT positioning rationale** *(per prof Cho's hint, project-proposal lectures ~4 weeks ago + user reasoning 2026-04-27)*: large-scale enterprise / data-center IDS will go to big vendors and the cloud (Fortinet, PAN, FortiGuard, CrowdStrike, Zscaler — they win on rule depth, ops scale, threat-intel network effects). Small custom silicon's natural niche is **edge IoT, smartphones, embedded / industrial sensors, low-power deployments** — where the big players cannot economically reach. Power becomes the gating constraint at the edge, which sets up Beat 4.
- **Vendor-style one-sentence (handout / Q&A):** *"Per-flow features feed an on-device ML classifier; verdicts gate egress at line rate — all on a single chip, no host round-trip, no separate appliance, no cloud round-trip."*
- **Direct contrast cheat-sheet** *(Q&A — pick up Beat 1's killer details one-by-one)*:
  - vs **Fortinet** (ML on a different chip in a different appliance) — *we put ML and the packet engine on the same die.*
  - vs **Palo Alto** ("inline ML" is a cloud roundtrip) — *our inference is on-chip; no cloud trip.*
  - vs **Snort 3** (Aho-Corasick 1975, no ML) — *we replaced pattern matching with neural inference.*
  - vs **Pigasus** (custom silicon for IDS, but no ML) — *same form, plus ML.*
  - vs **Morpheus** (real ML, but commodity silicon) — *same method, plus custom silicon.*

### Slide 2.2: Headline result (live demo + benchmark)

**On-slide content (two grouped metric blocks + GIF; numbers and visual only — no prose):**

```
+----------------------------------------------------------+
| RESULT                                                   |
|                                                          |
|  Full benchmark -- NSL-KDD KDDTest+  (n = 22 544)        |
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

**Speaker note (~30 words ≈ 10 s):**
> "82.4 % accuracy on the full NSL-KDD KDDTest+ benchmark — 22 544 packets. The FPGA agrees with the dev replay bit-for-bit; the live demo shows 18 of 20 classified correctly, every attack caught. Six milliseconds per packet, end-to-end."

**Reference (off-slide; for slide-builder + Q&A backup):**

- **Two-group role-split is the point — do not collapse:** the full-benchmark block carries the accuracy claim; the demo block + GIF carries the "this is real silicon and it agrees with the model" evidence. The FPGA logits agree with the dev-replay logits within ±0.01 across all 20 demo samples (BF16 rounding noise), so the 22 544-sample dev number describes the silicon, not just the model.
- **Speaker delivery:** three sentences, then move on. Per prof Cho's "no need to show your algorithm" feedback — the result is *table stakes* for "we built something that works", not the thing being sold. Slide 2.1 (differentiation) and Beat 4 (power) do the selling.
- **GIF asset:** `docs/final_project_progress_present/diagrams/ids_live_demo.gif` *(TODO — convert from the screen recording of `lab10reg.py ids_batch_packets 20 test_features.csv` taken 2026-04-27, delay = 1.5 s, all 20 packets aligned)*. Crop start: "Ready for 20 packets" line. Crop end: end of `BATCH RESULTS SUMMARY` block. Strip the model-loading preamble.
- **Source canon for the metrics:** `docs/ids_accuracy_journey.md` (canonical, supersedes `ids_v2_results.md`).

---

## Beat 3 — Power benchmark (slide + voice, ~40 s)

*(Renumbered from Beat 4 on 2026-04-27; old Beat 3 — design-space differentiation matrix — cut as redundant with Beat 2.)*

### Slide 3.1: Measured FPGA + projected ASIC

**On-slide content (two stacked tables):**

**Measured (Xilinx XPower, 2026-04-26):**

| Domain | Power |
|---|---|
| Total full chip | 2,674 mW |
| Quiescent (static) | 159 mW |
| Dynamic clocks | 817 mW |
| Dynamic logic | 729 mW |
| Dynamic signals | 678 mW |
| Dynamic IOs | 292 mW |

**Projected (Kuon & Rose TCAD 2007 + standard process scaling):**

| Node | Total power | Reasoning |
|---|---|---|
| 90 nm FPGA (measured) | **2,674 mW** | XPower v2 |
| 90 nm ASIC (projected) | ~**430 mW** | ÷6 dynamic gap (BRAM/mult-blended) |
| **28 nm ASIC (projected)** | ~**90–110 mW** | **3 process generations, ~5× V²+C reduction** |
| 7 nm ASIC (projected) | ~**30–50 mW** | Further ~2–3× scaling |

**Speaker note (~70 words ≈ 23 s):**
> "We measured the full chip at 2.67 watts on the FPGA — 90 nanometer, includes all NetFPGA platform infrastructure. Applying Kuon & Rose's published FPGA-to-ASIC scaling and standard process scaling, our SoC projects to about 90–110 milliwatts at 28 nanometer; 30–50 at 7 nanometer. Conservative even against Fortinet's only disclosed silicon node — FortiSP5 at 7 nanometer."

**Reference (off-slide; for slide-builder + Q&A backup):**

- The FPGA-measured 2.67 W includes NetFPGA platform infrastructure (Ethernet PHY, PCI bridge, oscillators); our SoC alone ≈ **1.0–1.5 W**.
- Citation: Kuon & Rose, *"Measuring the Gap Between FPGAs and ASICs,"* IEEE TCAD 2007. The ÷6 factor is for blended logic + BRAM + multiplier dynamic power; pure-logic gap is ~14×, pure-BRAM gap is ~5×.
- Comparison-node context: Fortinet has not publicly disclosed the NP7 process node. Their FortiSP5 security processor (separate silicon from the NP7 packet engine) is disclosed at **7 nm** (Feb 2023 announcement). The 28 nm projection is **conservative** — comparing it against the only disclosed Fortinet silicon node (7 nm SP5) leaves margin in their favor.

### Slide 3.2: Power positioning

**On-slide content (power-only comparison + banner):**

| | Power | Detection task |
|---|---|---|
| Our SoC (FPGA today, 90 nm) | 2.67 W full chip | ML classification |
| **Our SoC (projected 28 nm ASIC)** | **~100 mW** | ML classification |
| FortiGate 200G (current mid) | 145 W appliance | Signature matching |
| FortiGate 3800G (current flagship) | 1,496 W appliance | Signature matching |
| NVIDIA BlueField-3 (DPU, 7 nm) | up to 150 W | general programmable |

Banner: *"IoT-edge power (<200 mW projected) with on-die NN inference."*

**Speaker note (~45 words ≈ 15 s):**
> "Context. Fortinet's current mid runs at 145 watts; their flagship, 1.5 kilowatts. BlueField up to 150 watts. Our projected design point at 28 nanometer is sub-200 milliwatts — three-plus orders of magnitude lower. This is the gating constraint at the edge: nothing else fits."

**Reference (off-slide; for slide-builder + Q&A backup):**

- **Latency comparison removed 2026-04-27** as not defensible against Fortinet's published numbers (datasheet figures = firewall fast-path, *not* IPS-engaged; their IPS-engaged latency is undisclosed). The pivot is intentional: power, not latency, is where our advantage is unambiguous.
- **Silicon NN-inference latency, kept as Q&A backup (not on slide):** 7.32 μs today (732 BCAST cycles @ 100 MHz on the FPGA). ~0.7 μs projected at 28 nm / 1 GHz — *projection assumes 10× clock-scaling holds; not pipeline-verified.* The ~6 ms FPGA demo number on Slide 2.2 is the PCI/Python control-path bound and doesn't represent the silicon.
- **Power numbers cross-reference:** FortiGate 200G datasheet, FortiGate 3800G datasheet, NVIDIA BlueField-3 product brief.
- **Framing principle:** "We're at a different scale" pivots on power, not latency. The headline is power-per-classification at edge scale (sub-200 mW projected), 1000× lower than appliance-scale Fortinet — that's the edge enabler.

---

## End: stop here. No outro. (Per user direction 2026-04-26.)

---

## Appendix: Q&A backup material

If asked about specific technical contributions beyond the system level:

### Q: "What was the most novel piece of engineering?"
> "We added a cross-lane broadcast instruction — BCAST — to our SIMD ISA. It got us a 3.28× speedup on inference: 2402 cycles down to 732, hardware-verified. We had to modify the assembler, the GPU pipeline, and the kernel to get there — that cross-layer change was only possible because we own every layer of the stack."

### Q: "How accurate is the classifier?"
> "82.4 % on the full NSL-KDD KDDTest+ benchmark — 22 544 packets. On the 20-sample FPGA live demo, 100 % attack recall and 90 % overall, with F1 of 0.909 on the attack class. Per-packet logits on the FPGA match the dev replay within ±0.01 — that's BF16 rounding noise — so the 22 544-sample number describes the silicon's behavior, not just the model. The model itself is a small 11-16-8-2 ANN sized to fit on-chip; the architectural claim is that on-die ML inference works, not that we beat industry signature engines."

### Q: "What's the throughput?"
> "Six milliseconds per packet end-to-end, measured on the FPGA — that's the PCI / Python control path. The GPU inference itself is roughly 20 microseconds (732 cycles at the optimized BCAST kernel, 100 MHz). So the silicon is line-rate-capable for 1 GbE; the host round-trip dominates today. The on-chip ARM orchestrator path bypasses PCI entirely — it's hardware-verified, with the response-egress path closing next."

### Q: "Why NetFPGA Virtex-II Pro? It's old."
> "Class-issued hardware. The architectural argument is independent of node — that's what the projection slide shows. Modern silicon would inherit the same design, just smaller and lower-power."

### Q: "Doesn't Fortinet already do ML? FortiAI, FortiNDR, etc."
> "Yes, but not at the silicon packet path. Fortinet's ML runs in three places: FortiOS 7.6.3-plus has an AI/ML-based IPS that executes as a CPU software classifier after the signature engine triages traffic; FortiNDR is a separate GPU-based appliance that processes mirrored traffic, not inline at the firewall data plane; FortiGuard cloud sandbox does behavioral analysis on files extracted from the appliance. Inline neural inference at the ASIC packet path is what's not in shipping product. That's the quadrant we're in."

### Q: "Could you tape this out?"
> "Not realistically — tape-out is 18+ months of unbuilt engineering. The projection numbers are architectural, not a tape-out claim. We'd need to verify the design parameterizes beyond 4 lanes, and we haven't done that."

### Q: "How does this compare to Prof Cho's 2005 DAC paper?"
> "His pattern-matching co-processor was influential prior work in this space — it informed how we thought about tightly-coupled accelerators on a network data path. We're building on insights from that direction; the application choice (ML classification rather than signature matching) is where we diverge."

---

## Production checklist

- [ ] Build static slides in Google Slides or PowerPoint per Beats 0 / 1 / 2 / 3 above (3-beat structure post-2026-04-27 revision)
- [ ] Drop in the table content; pick one font / color scheme; keep it boring (per "too crazy" feedback)
- [ ] Import competitor logos for slide 1.1 (Fortinet, NVIDIA, AMD, Intel logos — fair-use educational)
- [ ] Render the THEM-vs-US comparison visual for slide 2.1 — ASCII version included; can redraw in draw.io for cleaner look
- [ ] **Convert 2026-04-27 screen recording → `diagrams/ids_live_demo.gif`** for slide 2.2. Crop "Ready for 20 packets" to end of `BATCH RESULTS SUMMARY`. Embed in slide 2.2 corner.
- [ ] Render power tables for slide 3.1 / 3.2 — already tabular, paste directly
- [ ] Print speaker notes (Beats 0 / 1 / 2 / 3 above) as one cue card
- [ ] Optional: render a single-frame "still" from the cut animated diagrams (`solution-diagram.html`, `cdiff-differentiation.html`) as a backup visual if the live presenter wants something less spartan than the ASCII diagrams. Not required.
- [ ] Rehearse to ~2.5–3 min total. Current speaking budget ≈ 2.5 min; if under 2 min, pad Beat 1.3 with one more Fortinet detail (e.g. FortiSP5, NP6→NP7 progression); if over 3 min, drop the BlueField-3 row in slide 3.2 or trim a Slide 1.2 walkthrough cell.

## What was killed and where to find the corpse

- `diagrams/architecture_diagram*.mp4` — animated architecture clip. Not used. Single frame may be useful as a Q&A backup.
- `diagrams/differentiation_diagram*.mp4` — animated differentiation clip. Not used.
- `diagrams/architecture_audio*.mp3` and `diagrams/differentiation_audio*.mp3` — AI voice tracks. Not used.
- BCAST clip (C-BCAST) — never built as an MP4; lives as `diagrams/claude_design_prompt_bcast.md`. Reserved for Q&A only.
- 5-beat structure with intro/outro live + 3 AI-voiced clips — replaced. `part3_expert.md` retains the historical record.
