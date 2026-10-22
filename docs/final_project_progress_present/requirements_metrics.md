# Requirements & Metrics — Final Progress Presentation

Master checklist for the **Apr 28/30 progress presentation**. "Should-be" = required to hit; "could-be" = nice to have or discretionary.

## A. Timeline & Scope

| Item | Value |
|------|-------|
| Lecture dates | 2026-04-28 and 2026-04-30 |
| Progress-presentation deadline | 2026-04-28 (first lecture slot, assumed) |
| Final demo video deadline | 2026-05-13 |
| Engineer | Zilin Shao (solo) |
| Days from 2026-04-17 to 2026-04-28 | 11 days |
| This is a | **progress** presentation — we are NOT expected to show a completed system |

### What's scoped for Apr 28/30

**User's order of work (decided 2026-04-21)**: Expert (Part 3) first, then Grandma + Investor. Expert content is already heavily materialized (diagrams, BCAST benchmarks, hardware-verified) whereas Part 2 has an external-dependency (interview recording) that's easy to fail. Building Part 3 first de-risks the Apr 28 deliverable.

| Part | Required for Apr 28/30? | Notes |
|------|-------------------------|-------|
| 3. Expert | **Should-be** — diagrams + narrative (expanded Option B, no live demo) | **Now the first-built deliverable.** Three artifacts: simplified solution diagram, differentiation diagram, "novel + only we can do it" slides/video. See `part3_expert.md` §3. Live DDoS demo still deferred to 2026-05-13. |
| 1. Grandma/grandpa | **Should-be** — video with analogy | Second-built. "Competitive / well-made" expected per user's own bar. |
| 2. Investor | **Should-be** — slides/video with interview(s) | Third-built. External dependency (interview) is the schedule risk; send outreach early even while expert work is in flight. |

## B. Format Requirements

| Requirement | Status |
|-------------|--------|
| Part 1 (grandma): video format | **Should-be** — professor: "nowadays all presentations should be videos, not just slides." Emotional pull needs motion. |
| Part 2 (investor): slides / interviews / video — any or mixed | **Should-be** — user-spec wording explicitly permits "slides/interviews/video." A video incorporating slide-style market charts + an interview clip is the target. |
| Part 3 (expert): slides / video — mixed OK | **Should-be** — user-spec wording is "presentation slides/video." Diagrams + narration is expected; can be pure slide deck with voiceover or video with diagram overlays. |
| AI-generated visuals | **Could-be** — encouraged; professor said "use all tools you can use" |
| Real interview(s) | **Should-be** for Part 2 |
| On-camera host appearance | **Could-be** — narration over visuals is acceptable |
| Subtitles / captions | **Could-be** — adds polish, especially for grandma part |
| Music / soundtrack | **Could-be** — emotional pull for grandma; upbeat for investor |
| Voice-over | **Should-be** — user's own voice OR AI voice (ElevenLabs) |

## C. Grandma/Grandpa — Specific Metrics

User-spec wording: *"Attention grabbing introductory video … that will allow your Grandma and Grandpa to understand and convince them this project is very important."* Two explicit purposes: (1) **they understand what it is**, (2) **they are convinced it matters**.

| Requirement | Status |
|-------------|--------|
| Attention-grabbing in first 15 seconds | **Should-be** — grandparent-relatable scenario |
| Grandparent can restate what the project does in their own words | **Should-be** — understanding test |
| Grandparent says "that's important" or equivalent after watching | **Should-be** — importance test; this is the payoff metric |
| Avoid technical jargon | **Should-be** — professor's Facebook story warns against wrong analogies |
| Use analogy (not technical description) | **Should-be** |
| Connect to a grandparent-familiar concern (scam calls, smart home, privacy) | **Should-be** |
| Scale-up hook to industry (LLM security) | **Could-be** — smooth transition to Part 2 |
| Length | **Should-be** — ~60-90 seconds (keeps attention) |
| Video quality | **Should-be** — "competitive / well-made" |
| Test with a real grandparent before recording | **Could-be** — high signal-to-effort ratio; directly validates the two tests above |

## D. Investor — Specific Metrics

User-spec wording: *"Market/business research slides/interviews/video … allow the investor to understand and be convinced that the solution will make him/her money."* Format is explicitly flexible (slides OR interviews OR video, or a mix). The payoff metric is **investor believes this will make them money**.

| Requirement | Status |
|-------------|--------|
| Investor payoff test: viewer answers "yes, this could make money" unprompted | **Should-be** — payoff metric |
| Market size claim with a source | **Should-be** — even a ballpark number is OK |
| Growth rate of market | **Should-be** — investors care about "growing, not shrinking" |
| Differentiation vs existing solutions | **Should-be** — what makes us different |
| Real interview (at least one) | **Should-be** — professor explicitly encouraged |
| Market/business research slide(s) | **Should-be** — user-spec wording names "slides" explicitly for this part |
| Multiple interviews | **Could-be** — one is required; 2-3 strengthens the pitch |
| Interviewees | **Could-be** — parents' friends are OK, use connections |
| Sample pitch deck screen | **Could-be** — shows seriousness |
| Call to action / ask | **Could-be** — "here's the problem, here's our solution, here's what's next" |
| Length | **Should-be** — ~90-120 seconds |

## E. Expert — Specific Metrics (optional for Apr 28/30; required for May 13)

User-spec wording: *"A simplified diagram of the current solution. A diagram of your solution that differentiates your solution from existing solutions. A presentation slides/video … that highlights the difference in technical detail to convince the domain expert that your solution is novel and that **your team is the only one who can do it**."*

Three concrete deliverables are named: (1) simplified current-solution diagram, (2) differentiation diagram vs existing solutions, (3) technical presentation (slides or video) with novelty + "only team that can do it" framing. The payoff metrics are **"novel"** and **"only we can do it."**

| Requirement | Status at Apr 28/30 | Status at May 13 |
|-------------|---------------------|------------------|
| **(1) Simplified diagram of our solution** (CPU + GPU + FIFO + DMA, one box, flow arrows) | **Should-be** (user 2026-04-21) | **Should-be** — user-spec named deliverable |
| **(2) Differentiation diagram** (us vs NVIDIA BlueField / AMD Pensando / Intel IPU — axes like specialized↔general, edge↔cloud, ML-first↔general-purpose) | **Should-be** (user 2026-04-21) | **Should-be** — user-spec named deliverable |
| **(3) Technical presentation (slides or video)** tying diagrams + benchmarks + novelty story | **Should-be** (user 2026-04-21) | **Should-be** — user-spec named deliverable |
| "Novel" claim substantiated (custom BCAST ISA extension is the strongest single novelty point) | **Should-be** — anchored by hardware-verified 3.28x | **Should-be** — payoff metric |
| "Only our team can do it" framing (full-stack ownership: custom GPU + custom ISA + toolchain + ANN + integration) | **Should-be** — delivered as scope-of-ownership beat | **Should-be** — payoff metric; lean on scope + depth, not on hubris (see Hard Don'ts) |
| Technical correctness | **Should-be** for the diagrams + benchmarks presented | **Should-be** full demo |
| Live DDoS demo | **Could-be** — NOT chosen for Apr 28 (user 2026-04-21); wrap-line "coming May 13" | **Should-be** — see `../final_project_demo_video/final_project_expert_demo_plan.md` |
| BCAST / cycle-counter benchmarks (732 cycles vs 2402 scalar = 3.28x) | **Should-be** — anchors "novel" claim | **Should-be** |
| Accuracy benchmark (75% on NSL-KDD, hardware-verified) | **Should-be** | **Should-be** |
| Honest framing of limitations (NSL-KDD dataset age, 3.28x is vs our own baseline, no in-FPGA filter path yet) | **Should-be** — expert-audience credibility | **Should-be** |

## F. Tools Allowed / Encouraged

| Tool category | Examples | Status |
|---------------|----------|--------|
| AI video generation | Runway, Sora, Kling, Veo, Pika, Luma | **Could-be** — encouraged |
| AI voice-over | ElevenLabs, OpenAI TTS | **Could-be** — saves time vs recording |
| AI script assistance | ChatGPT, Claude | **Could-be** |
| Editing | DaVinci Resolve (free), CapCut (free), Premiere | **Should-be** — some editor required |
| Music | Suno, Mubert, Epidemic Sound, YouTube Audio Library | **Could-be** |
| Screen recording (for expert part) | OBS Studio | **Should-be** for expert demo |

## G. Hard Don'ts (from professor's feedback and user's prior experience)

| Don't | Why |
|-------|-----|
| Assume grandparents like "Facebook-like" things | Professor's story — prior group bombed on this. Grandparents actively dislike Facebook. |
| Claim to be an "evolution of Prof Cho's DAC 2005 paper" | User's existing style-feedback memory — keep humble framing. |
| State "only our team can do it" as hubris | User-spec §E names this phrasing, but the audience will reject arrogance. Frame as *scope + ownership*: "We built every layer — the GPU, the ISA, the toolchain, the ANN — which is why the cross-layer optimizations exist." Let the work speak. |
| Go over length | Attention spans; keep each part tight. |
| Show code / Verilog to grandma | Not grandma-audience. |
| Show scam-call UX to investor | Wrong audience — investors want market + differentiation. |
| Over-claim performance vs commercial silicon | Our 3.28x speedup is vs our own scalar baseline, not vs NVIDIA BlueField. Be honest. |

## H. Open Risks / Questions (TODO before filming)

- **[DIG DEEPER]:** Confirm lecture time slot on 2026-04-28 vs 2026-04-30 — does the user present on Tuesday or Thursday? Which day is actually "the" progress-presentation day?
- **[DIG DEEPER]:** Is there a mandatory total length per part? Ask TA Namo or Sreehari if unclear.
- **[DIG DEEPER]:** Is there a required slide/video-deck submission separate from the lecture?
- **[DIG DEEPER]:** Does the lecture format allow showing a video OR must it be live-presented? Confirm with professor.
- **[DIG DEEPER]:** Does the grading rubric for the progress presentation explicitly require Part 3, or is it acceptable to show only Parts 1 + 2? Confirm with TA.
