# Part 2 — Investor Presentation Plan

A video pitching the investor thesis: there's a real, growing market for our technology, and we're doing something different. Includes at least one real interview. Target: ~90-120 seconds.

## 1. Professor's Guidance

### 1.1 Story: Investors care about money (professor on lecture)

**"All investors care about is money."** Not the technology. Not the clever engineering. Money. You have to convince them that (a) there's a market, and (b) the market is growing. Everything else is secondary.

**Takeaway**: open with market, not architecture. Close with ROI/trajectory, not clock cycles.

### 1.2 Directive: Use your connections (professor on lecture)

Professor explicitly said: it's fine to have your parents' friends play the role of "investor" in interviews. "If you have an uncle in finance, use him." The interview itself is signal — it shows you can pitch to a non-technical audience and not flub.

## 2. User's Angle

### 2.1 The LLM-weight-tampering story (user's thought, 2026-04-17)

Verbatim from the session: *"Professor said on lecture that cybersecurity for AI would be very important, imagine AI companies spend billions to train a LLM, and some cyber-hackers just spend hundred thousands to steal it and change some weights to reach same performance and without being detected since the weights are changed."*

This is the **AI-supply-chain-attack** angle. Active concern in 2026 — major AI companies publicly acknowledge weight-theft as a threat; NIST AI RMF (2023) calls out supply-chain attacks as a top category. Our tech sits in the *network layer* that would detect the exfiltration or intrusion traffic during such an attack.

**[DIG DEEPER]:** Find 2-3 real incidents or NIST/MITRE documents naming this threat model. Anchor the claim with a link or a pull-quote on screen. Without a citation this sounds speculative.

**[DIG DEEPER]:** Be honest about scope. Our IDS detects *network-level* signals of a supply-chain attack (unusual exfiltration, unauthorized API access). It does not inspect model weights directly. The pitch should not over-claim. The investor-friendly framing: "we catch the network traffic that attacks leave behind."

### 2.2 The edge/IoT market angle (bridges from Part 1)

Reusing the grandma video's framing:
- Edge AI market is exploding (SmartNICs, on-device inference).
- Privacy regulations (EU AI Act, US state laws) push compute to the edge.
- IoT device counts: ~30 billion by 2030, each a potential attack surface.

Transition from Part 1 → Part 2: "The same chip that protects grandma's phone also protects the data centers she'd never see."

**[DIG DEEPER]:** Pull one punchy number per market layer. See `brainstorm_market_sizing.md` for sources and candidate numbers.

## 3. Proposed Narrative Arc (draft, ~105 seconds)

**Structure**: problem (money-shaped) → market size → our solution → differentiation → interview → close.

1. **Hook (0-15 sec)**: "*In 2024, cybercrime cost companies $10 trillion. Most of that went through networks.*" [Scary stat, graph ticking up.]
2. **Market framing (15-35 sec)**: "*The SmartNIC market is $8B and growing 30% a year. Enterprise network security is $200B. And a new market — AI infrastructure security — is forming right now.*"
3. **Our thesis (35-55 sec)**: "*We built an ML-accelerated network intrusion detector on custom hardware. It spots attack patterns in real-time, on-device, without sending your data to the cloud.*"
4. **Differentiation (55-75 sec)**: "*Existing SmartNICs from Intel and AMD are general-purpose. We baked the ML classifier directly into silicon — 3x faster, tiny footprint, tuned for security workloads from day one.*"
5. **Interview cutaway (75-100 sec)**: Real interview clip. "*Sounds like something every data-center should have.*" [Parent's-friend-as-investor interviewee.]
6. **Close (100-120 sec)**: "*One chip. Detects attacks on phones, hospitals, and the AI data centers the world is about to build. Invest in the layer between AI and the internet.*"

**[DIG DEEPER]:** Decide which single market layer to lead with. Edge/IoT is most grandma-relatable (transitions well from Part 1). Enterprise/SmartNIC has the biggest TAM. AI-supply-chain is the sexiest story. Probably lead with edge, name-drop AI-supply-chain as the "where this is going" closer.

**[DIG DEEPER]:** The 3.28x speedup claim is real (BCAST measured 3.28x on 2026-04-17, hardware-verified). Consider showing the before/after cycle-count graph briefly — investors like a number.

## 4. Interview Plan

### 4.1 Who to interview

From user's existing contacts memory:
- **Wenkai (Apple)** — edge silicon, privacy-on-device thesis; strong fit.
- **David Z (Noise)** — consumer hardware, scale. Could speak to product-market fit at the device level.
- **Parker's father** — cancer expert; less directly relevant but could speak to HIPAA/privacy in healthcare.
- **Parents' friends** — whoever has finance, insurance, healthcare, or tech roles.

Target mix: at least one tech/business person; bonus if someone in cybersecurity or healthcare (both big IDS buyers).

**[DIG DEEPER]:** Write out the shortlist with a 3-line "why them" per candidate: (a) what they bring, (b) what question you most want answered by them, (c) scheduling risk. See `brainstorm_interview_questions.md` §4.

**[DIG DEEPER]:** Reach out to 3-5 candidates by Apr 18-19 to account for schedule misses. Even if only one lands, you have content.

### 4.2 Format

- 10-15 minute interview; keep only ~20 seconds in the final video.
- Recorded on Zoom (use "record to cloud" for easy clips), Google Meet, or in-person.
- Permission to use likeness — capture in writing even if informal. Simple email suffices.
- Transcript via Otter.ai or Zoom's built-in for subtitling.

**[DIG DEEPER]:** Contact interviewees at least 5 days before filming to allow scheduling.

### 4.3 The "money question" to land on camera

One sentence from the interviewee that works as a pull-quote. Examples of shape:
- "*Every data center is going to need something like this.*"
- "*If you told me this runs on a single FPGA, I'd be very interested.*"
- "*Our customers ask about this kind of detection every week.*"

**[DIG DEEPER]:** Pre-brief the interviewee so the money-question isn't a surprise. Prof Cho explicitly encouraged using connections — this is the moment to use them. See `brainstorm_interview_questions.md` §2.5 for the script.

## 5. Differentiation Story (the second investor question)

Why aren't we just a thin wrapper on an existing SmartNIC?

| Axis | Incumbent (AMD Pensando, NVIDIA BlueField) | Us |
|------|--------------------------------------------|-----|
| Silicon | General-purpose ARM + NIC | ARM + custom SIMD GPU coprocessor |
| Workload fit | Broad | Security-ML-first |
| ML throughput | CPU-bound | 3.28x speedup via BCAST ISA extension (hardware-verified 2026-04-17) |
| Footprint | Enterprise-scale | Designed for edge / small deploy |
| Openness | Closed silicon | Our toolchain is open, customizable |

**[DIG DEEPER]:** Validate the "3.28x" framing on camera. It's vs our own scalar baseline, not vs a commercial competitor. Be careful with the claim.

**[DIG DEEPER]:** Market-positioning diagram — 2x2 with axes like "specialized vs general" and "cloud vs edge." Our quadrant is specialized + edge. Visually simple, investor-friendly.

## 6. Hard Don'ts

- **Don't over-claim performance** vs commercial silicon without a direct apples-to-apples benchmark (we don't have one).
- **Don't show architecture diagrams** unless designed for a business audience (arrows, not opcodes).
- **Don't use "DDoS" without defining it** — some investors are non-technical.
- **Don't promise a product on a specific date** — this is a class project, not a fundable startup.
- **Don't quote Prof Cho's 2005 DAC paper as if we're its evolution** — humble framing per user's memory.

## 7. Production Notes

- Investor video can reuse some assets from Part 1 (the "tiny security guard" concept extended into a larger setting).
- Budget ~10-15 hours production, on top of interview recording time.
- Record interview(s) by Apr 23 to allow editing time.

**[DIG DEEPER]:** Sequence: Apr 18 = confirm interviewees; Apr 19-22 = record; Apr 23-26 = edit.

## 8. Open Questions

- **[DIG DEEPER]:** Include a "pitch deck" visual (mocked-up slide, fake term sheet) for investor-signaling, or keep it fully narrative?
- **[DIG DEEPER]:** Show real numbers from the milestone-1 75% accuracy + 3.28x speedup, or keep it high-level?
- **[DIG DEEPER]:** Multiple interviewees in one supercut, or one well-chosen interview? Both work; supercut feels more like real-world validation.
- **[DIG DEEPER]:** Does the investor video reference the grandma video ("*as you saw in Part 1...*") or does each stand alone? Depends on whether they're played back-to-back.
- **[DIG DEEPER]:** Decide how openly to name specific incumbents (NVIDIA, AMD, Intel, Fortinet). Naming sharpens differentiation; over-naming triggers lawyer-adjacent caution in some investor audiences. Fortinet is a safe name to use given professor's own reference to them.
