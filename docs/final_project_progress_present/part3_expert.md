# Part 3 — Expert Presentation Plan

**Deadline split** — the live-DDoS demo is NOT required for the Apr 28/30 progress presentation; hard deadline for the live demo is **2026-05-13** (final project demo video). However, per user decision 2026-04-21, an *expanded Option B* will be delivered at Apr 28/30: three named artifacts (simplified solution diagram, differentiation diagram, "only our team can do it" technical narrative). No live demo at Apr 28. This file covers:
1. What to include at Apr 28/30 (locked: expanded Option B).
2. How Part 3 relates to the existing `../final_project_demo_video/final_project_expert_demo_plan.md`.

## 1. Deadline Clarification

- **2026-04-28 / 2026-04-30 (progress lecture)**: Part 3 contributes three artifacts (see §3). No live DDoS demo.
- **2026-05-13 (final demo video)**: Part 3 full live-DDoS demo required.

**Scope pivot (user, 2026-04-21)**: user is tackling Part 3 *first* for Apr 28, then Parts 1 (grandma) + 2 (investor) afterward. This inverts the default reading of §A in `requirements_metrics.md` where Parts 1+2 were flagged "main deliverable" at Apr 28. With expert content already heavily materialized (diagrams, BCAST benchmarks, hardware-verified 3.28x), building Part 3 first is lower-risk than starting with the external-dependency (interview) of Part 2.

**Implication**: the old advice "don't waste Apr 28 prep time polishing Part 3" is now inverted — polish Part 3 *first*, then turn to Parts 1+2.

## 2. Pointer to Existing Technical Plan

All engineering and rehearsal for the May 13 deliverable is tracked in `../final_project_demo_video/final_project_expert_demo_plan.md`:
- System architecture (now includes §2.5 ARM CPU utilization analysis — Track A vs Track F)
- Feature-extractor spec (~400 LoC Python port of AI-IDS) — Track F
- Attack generator (hping3 / scapy) — Track F
- Live loop on nf6 — Track F
- Visualizer — Track F
- Optional ARM-orchestration upgrade — Track A (requires ~50 LoC RTL addition, gated on synth timing in Apr 21–22)
- Schedule rebased to 2026-05-13 deadline with 4 weeks: Week 1 (Apr 18–24) = Track F Days 1–3 + Track A RTL gate; Week 2 = end-to-end + ARM orchestrator; Week 3 = integration; Week 4 = record/edit
- Risks and fallbacks

**[DIG DEEPER]:** Periodically sync this progress-presentation file with that plan — status can drift if one is updated without the other.

## 3. What to Include at Apr 28/30 — LOCKED: Expanded Option B

**User decision (2026-04-21)**: Option B, expanded to cover the three user-spec named deliverables from `requirements_metrics.md` §E. Not a 30-sec teaser — a substantive expert segment, minus the live DDoS demo.

### 3.1 The three Apr 28 artifacts

| # | Artifact | Primary content | Lift | Source material ready? |
|---|----------|-----------------|------|------------------------|
| 1 | **Simplified diagram of our solution** | CPU + GPU + FIFO + DMA in one box, labeled flow arrows (packet → FIFO → DMA → GPU DMEM → classify → response). Axes labeled (data plane vs control plane). | ~2-3 hrs drawing | ✅ ASCII diagram in `CLAUDE.md`; redraw in draw.io or Figma. Reuse `docs/lab7_gpu/datapath_diagram.md` if present. |
| 2 | **Differentiation diagram** (us vs existing) | 2x2 matrix OR side-by-side feature table. Axes: specialized↔general, edge↔cloud. Competitors: NVIDIA BlueField, AMD Pensando, Intel IPU, Fortinet. Us: specialized + edge + ML-first ISA. | ~2-3 hrs | ✅ Comparison table in `part2_investor.md` §5 is reusable. Market numbers in `brainstorm_market_sizing.md`. |
| 3 | **Technical narrative** — "novel + only our team can do it" | Slide deck with voice-over OR video. Pulls diagrams + BCAST benchmark (732 vs 2402 = 3.28x) + accuracy (75% NSL-KDD) + scope-of-ownership story. | ~8-10 hrs | ✅ Benchmarks hardware-verified 2026-04-17; milestone-1 recorded 2026-04-06; BCAST re-synth 2026-04-11 all in memory. |

### 3.2 Narrative — 5-beat structure (revised 2026-04-21, AI-voice pivot)

**Framing**: per prof's live feedback to user (2026-04-21), emphasize *"unique features of our architecture,"* not ownership scope or scalability. The "only we can do it" argument is implicit across the features — never stated as a sentence (humble framing per `requirements_metrics.md` §G).

**Format pivot (2026-04-21)**: user prefers AI-voiced animated clips for the diagram segments so live-talking burden is limited to a brief intro and outro. Live time budget = ~35 sec total. All three middle segments are AI-voiced pre-recorded clips.

**Flow order (user 2026-04-21)**: live intro → architecture diagram → differentiations diagram → "why only we can do" (BCAST) → live outro. Architecture *before* differentiation (establish what we built, then contrast it).

**Application**: ML-based IDS. Every group has a network processor; our differentiator is what we built it for.

**Scaling direction**: *down* (edge deployment), not up. Do not claim data-center or ASIC scale-up.

| # | Format | Beat | Length | Voice |
|---|--------|------|--------|-------|
| 1 | **Live** | Intro — "I'm Zilin. Expert segment of our ML-based IDS project. Next three videos walk through our architecture, how we differ from existing solutions, and our key technical contribution." | ~15 sec | You |
| 2 | **Clip C-ARCH** (animated + AI voice) | Architecture diagram (artifact 1): packet enters convertible FIFO → CPU reads header → DMA moves features to GPU DMEM → GPU classifies → response exits. All on-chip, no host round-trip. | ~45 sec | AI (ElevenLabs — "documentary explainer" voice) |
| 3 | **Clip C-DIFF** (animated + AI voice) | Differentiation diagram (artifact 2): 2x2 on cloud/edge × general/ML-IDS-specific. Competitors plotted (BlueField, Pensando, CrowdStrike, Zscaler). Our slot = empty quadrant (edge + ML-IDS). | ~40 sec | AI (ElevenLabs — "market-briefing host" voice) |
| 4 | **Clip C-BCAST** (animated + AI voice) | BCAST ISA extension walkthrough: 4-lane SIMD + cross-lane broadcast; 2402 → 732 cycles = 3.28x, hardware-verified 2026-04-17. Show the instruction in the assembler. Implicit "why only we can do" — this cross-layer change needs owning GPU RTL + ISA + assembler + kernel. | ~50 sec | AI (ElevenLabs — "Ben-Eater-style technical walkthrough" voice) |
| 5 | **Live** | Outro — "That's our progress. 75% on NSL-KDD today. Live DDoS demo on 2026-05-13. Payload inspection next. Questions?" | ~20 sec | You |

**Total**: ~2.5 min clips + ~35 sec live = ~3 min expert segment.

**Optional 6th beat — C-SCOPE clip (~25 sec)**: visual inventory of all layers (CPU + GPU + ISA + assembler + CUDA toolchain + trained ANN). Narration: *"Every layer of this stack is ours. That's why the BCAST change was possible in 5 days, not 5 months."* **Default: skip.** The BCAST clip carries the message implicitly; explicit inventory risks sounding like boasting. Only add if user wants "videos" (plural) for the "why only we can do" section beyond a single BCAST clip.

**AI-voice consistency rule**: use the *same* ElevenLabs voice (or paired voices with consistent style) across all three clips. Switching voices mid-segment is jarring.

**AI-voice workflow inversion**: for the three AI-voiced clips, script must come *before* voice generation — ElevenLabs needs text input. Narrow exception to the §3.3.2 visuals-first rule: storyboard → visuals → script → AI voice → sync. Still visuals-first overall.

**Credibility hedge**: ~80% of spoken audio will be AI-generated. Your 35 sec of live speech + Q&A handling is the human-presence hedge. Be ready for "explain BCAST in your own words" in Q&A.

**What NOT to say (per user discussion 2026-04-21)**:
- Don't claim 4-lane SIMD / BF16 / small DMEM were "chosen to fit NSL-KDD" — that's backward rationalization (GPU was built in Lab 7 before IDS was picked).
- Don't claim "totally scalable" or "will tape out to ASIC" — parameterization is not verified beyond 4-lane; tape-out is 18+ months of unbuilt engineering.
- Don't claim lower power as silicon-level (NetFPGA V2 is 2006 CMOS, not low-power) — only architecturally, as in "fits on minimal silicon, translates to low-power edge devices."
- Don't bring up the 4816 timing violations unless directly asked. If asked: "current silicon is congestion-limited; modern edge FPGAs have more routing headroom." Truthful and concise.

**[DIG DEEPER]:** Script the 5 beats as a ~2-3 minute voice-over *after* slides and clips are built (per §3.3.2 visuals-first workflow). Word-count target: ~450-600 words for 3 minutes at 2.5 wps.

### 3.3 Format — LOCKED: mixed pre-recorded video clips + live presentation

**User decision (2026-04-21)**: hybrid delivery — pre-recorded video clips (technical-YouTuber reference style) interleaved with live presenter segments. The pre-recorded clips lock in the precision of the technical explanations (architecture walkthrough, BCAST mechanics, cycle-count result); the live segments carry the transitions, framing, and Q&A.

**Reference style**: technical-YouTuber production (user's stated reference). Closest-fit creators as a mood board:
- **Branch Education** — 3D-animated chip / architecture explanations; matches artifact (1) "here's our SoC."
- **Ben Eater** — low-level hardware walkthroughs with zoomed-in diagrams; matches "here's how the BCAST datapath works."
- **3Blue1Brown / Asianometry** — visual explanations with strong narration; fits the differentiation and scope-of-ownership beats.

### 3.3.1 Clip inventory — revised 2026-04-21 (3 core clips, AI-voiced)

Mapped to §3.2 beats. All three middle clips are AI-voiced animated; beats 1 and 5 (brief live intro/outro) are the only live-presenter content.

| Clip ID | Beat | Topic | Length | Style anchor | Voice |
|---------|------|-------|--------|--------------|-------|
| *(live)* | 1 | Live intro (see §3.2 beat 1 script) | ~15 sec | You on camera / voice only | You |
| **C-ARCH** | 2 | Architecture diagram animated — convertible FIFO + CPU header read + DMA transfer + GPU classify + response egress. Packet visibly flows through the SoC box. | ~45 sec | Branch Education — animated architecture | AI (ElevenLabs, "documentary explainer") |
| **C-DIFF** | 3 | Differentiation 2x2 animated — axes drawn, competitors plotted in their quadrants, our slot highlighted last. | ~40 sec | 3Blue1Brown — clean axes, minimal motion | AI (ElevenLabs, "market-briefing host") |
| **C-BCAST** | 4 | BCAST ISA extension walkthrough — 4-lane SIMD before/after; cross-lane broadcast visualized; the instruction shown in the assembler; cycle-counter graph 2402 → 732. | ~50 sec | Ben Eater — zoomed-in hardware | AI (ElevenLabs, "technical walkthrough") |
| *(live)* | 5 | Live outro (see §3.2 beat 5 script) + Q&A invitation | ~20 sec | You on camera / voice only | You |
| C-SCOPE *(optional)* | 4b | Scope-of-ownership inventory (skipped by default; see §3.2) | ~25 sec | Asianometry — inventory + commentary | AI (same voice as C-BCAST) |

**Totals**: pre-recorded ~2:15, live ~35 sec, total ~2:50. Tight for a class progress slot and leaves Q&A headroom.

**Clip-specific animation complexity (highest to lowest)**:
1. **C-BCAST** — most complex. Needs SIMD lane visualization, before/after comparison, instruction-in-assembler overlay, cycle counter graph. Budget ~4-5 hrs.
2. **C-ARCH** — medium. Packet motion through FIFO + mode transitions + DMA path. Budget ~3-4 hrs.
3. **C-DIFF** — simplest. Static 2x2 with staged logo reveals. Budget ~2-3 hrs.

**[DIG DEEPER]:** If animation budget compresses, downgrade C-ARCH first (static diagram with arrow overlays is still defensible). C-BCAST is the technical centerpiece — protect its budget.

**[DIG DEEPER]:** Voice consistency — C-ARCH and C-DIFF can share one voice profile if the same ElevenLabs voice reads both well. C-BCAST might use a slightly more technical-sounding voice. Test 10-second samples of 2-3 voices before committing.

### 3.3.2 Production workflow (visuals-first, with AI-voice insertion)

Per user (2026-04-21): **scripts are written *after* visuals are built**, then fed to ElevenLabs for the three AI-voiced clips. Inverts the default "script-first" guidance in `brainstorm_video_production.md` §2.

1. **Storyboard each clip** (1-2 hrs) — rough frame-by-frame sketch; no words yet.
2. **Build the static slides** (2-3 hrs) — diagrams for artifacts (1) + (2), timing-graph for BCAST.
3. **Build the video clips** — animate diagrams; keep clips silent at first.
   - C-ARCH: 3-4 hrs
   - C-DIFF: 2-3 hrs
   - C-BCAST: 4-5 hrs (most complex — SIMD visualization)
4. **Write the narration scripts** (2-3 hrs total) — now that visuals exist, time narration to on-screen motion. Target word counts:
   - C-ARCH: ~110 words (45 sec @ 2.5 wps)
   - C-DIFF: ~100 words (40 sec @ 2.5 wps)
   - C-BCAST: ~130 words (50 sec @ 2.5 wps)
5. **Generate AI voice via ElevenLabs** (1-2 hrs including iteration) — paste each script, pick a voice preset, listen, regenerate if emotional tone is off.
6. **Sync AI audio to video** (1-2 hrs) — DaVinci Resolve or CapCut; audio on track 1, visuals on track 2, align to frame-accurate cues.
7. **Live-presenter notes for intro/outro** (1 hr) — two short cue-cards totaling ~35 sec of speaking.
8. **Final review + export** (1-2 hrs) — watch the whole thing end-to-end; export MP4 at 1080p / H.264.

Total Part 3 production: **~19-26 hrs**. Higher than the earlier estimate because AI-voiced production inserts steps 4-5-6 that slide-only would skip.

### 3.3.3 Animation tooling options

| Tool | Strength | When to pick it |
|------|----------|-----------------|
| Keynote / PowerPoint with motion paths + recorded screen capture | Zero learning curve; usable diagrams | Fastest path; Ben-Eater-level quality |
| Figma + After Effects (or Figma alone with Smart Animate) | Clean minimal look | Polished 3Blue1Brown-adjacent look |
| Manim (3Blue1Brown's library) | Technical-math quality | Overkill unless user already knows it |
| Davinci Resolve / Premiere for edit + compositing | Free (Resolve) or paid (Premiere) | Final assembly regardless of source |
| OBS Studio | Screen capture of FPGA tools, waveforms | If including any real-hardware screens |

**[DIG DEEPER]:** Pick one animation tool and commit — mixing tool outputs across clips will cause jarring style shifts. Recommended: Keynote/PowerPoint for the lowest-effort path if new to animation, or Figma + Smart Animate if some design muscle exists.

### 3.4 Options that are NOT chosen (for reference)

- ~~Option A (full skip at Apr 28/30)~~ — not chosen. User wants meaningful Part 3 content at Apr 28.
- ~~Option C (full live-DDoS video at Apr 28/30)~~ — not viable. Live demo deferred to May 13 per `../final_project_demo_video/final_project_expert_demo_plan.md`.

### 3.5 Differentiation diagram — content spec (artifact 2)

**Form**: 2x2 matrix. Axes selected (2026-04-21) to place us in a defensible empty quadrant — no direct competitor overlap.

| | **Cloud / Data-Center deployment** | **Edge deployment** |
|---|---|---|
| **General-purpose compute** | NVIDIA BlueField<br>AMD Pensando<br>Intel IPU | *(small commercial FPGA appliances, unnamed)* |
| **Application-specific (ML-IDS)** | CrowdStrike<br>Zscaler<br>(cloud SaaS ML-IDS) | **Us** |

**Narrative this diagram supports**:
- The other three quadrants all have big-name competitors. Ours is the empty slot.
- Cloud-SaaS ML-IDS (CrowdStrike) does ML for IDS but in cloud — power-expensive, latency-expensive, privacy-intrusive at the endpoint.
- General-purpose SmartNIC (BlueField) does edge-ish hardware but general-purpose, not ML-IDS-specific.
- Our slot = application-specific ML-IDS on an edge device. Sparse.

**Honest caveats (not shown on slide, but know them for Q&A)**:
- We haven't deployed to edge silicon (we're on NetFPGA V2, which is research hardware). The claim is *architectural edge-viability*, not *shipped edge product*.
- Commercial small-FPGA IDS products may exist that we haven't named; the quadrant isn't literally empty in the market.
- CrowdStrike also does endpoint detection (EDR), but the ML heavy lifting happens in cloud. Our categorization simplifies this.

**[DIG DEEPER]:** Pick 3-4 named competitors per filled quadrant, no more. A diagram with 12 logos reads as research; a diagram with 6-8 reads as a pitch. Filter by name recognition and domain authority.

**[DIG DEEPER]:** If time permits, plot Prof Cho's 2005 DAC work on the diagram as the *"inspiration / prior art"* point — near us but historical. **Humble framing**: label as "influential prior work," not "our parent design." See `feedback_communication_style.md`.

## 4. Expert Narrative Framing

Two things experts care about (per user's stated goals for this part):

### 4.1 "We know what we're doing"

Show craftsmanship, not just results:
- Custom 4-lane SIMD GPU built from scratch
- Custom ISA including a BCAST cross-lane instruction we added and verified
- PCI-mapped cycle counter for hardware measurement
- Fix 1 timing closure (5/5 deterministic, verified 2026-04-17)
- Full toolchain (Python assembler, CUDA→PTX→our-ISA path)

**[DIG DEEPER]:** Pick 2-3 craftsmanship points to showcase — don't dump the whole list. Focus on what's *unusual* (the BCAST ISA extension is the most unusual; most classes don't get to add ISA instructions).

### 4.2 "We're doing something different"

Positioning:
- Most class projects: hello-world on FPGA.
- Us: end-to-end ML-accelerated intrusion detection, real network traffic, measurable speedup.
- Most industry: general-purpose SmartNICs.
- Us: security-ML-first ISA design.

**[DIG DEEPER]:** Be careful with the "most class projects" framing — don't imply we're better than classmates. Frame around what we *chose* to do differently, not who we're better than.

**[DIG DEEPER]:** Per user's existing feedback memory: **humble framing** when referencing Prof Cho's prior work. Don't claim "evolution of his 2005 DAC paper." Credit the inspiration; don't imply replacement.

## 5. Production Notes (for May 13)

See `../final_project_demo_video/final_project_expert_demo_plan.md` §4.3–§4.4 for visualizer specs, §5 for the 4-week schedule, and §9 for deliverables.

**[DIG DEEPER]:** Track A (ARM orchestration) is the headline upgrade for May 13 vs milestone 2. If gate A3 (Apr 21–22 synth timing) passes, the final video can claim "our SoC orchestrates itself — CPU dispatches, GPU classifies, DMA moves data, all on-chip." That's a much stronger expert narrative than the current Python-on-host orchestration.

**[DIG DEEPER]:** Record the demo in at least two takes. First take is typically flawed; second is 2–3× better after you've seen your own mistakes.

## 6. Open Questions

- ~~Option A/B/C decision~~ — **RESOLVED 2026-04-21**: Expanded Option B chosen. See §3.
- ~~Live-present vs pre-recorded at Apr 28~~ — **RESOLVED 2026-04-21**: mixed — pre-recorded clips (technical-YouTuber style) + live presenter segments. See §3.3.
- ~~Script timing relative to slides/videos~~ — **RESOLVED 2026-04-21**: scripts *after* slides and video clips are complete (visuals-first workflow). See §3.3.2.
- **[DIG DEEPER]:** Does the progress-presentation lecture grade include a Part 3 component, or is it purely Parts 1+2? Given user's decision to lead with Part 3, resolving this is higher priority now — worth pinging TA Namo or Sreehari.
- **[DIG DEEPER]:** If the Apr 28/30 lecture gives feedback on this Part 3 segment, should the May 13 live-DDoS video visibly incorporate that feedback? (Probably yes — shows learning. Worth a note in the May 13 video.)
- **[DIG DEEPER]:** Create a companion `part3_expert_script.md` *after* the slides and clips are built (per §3.3.2 workflow). Scripted content: per-clip narration + live-presenter cue cards.
- **[DIG DEEPER]:** Pick one animation tool before starting clip production (§3.3.3) — tool-hopping mid-clip causes style drift.
