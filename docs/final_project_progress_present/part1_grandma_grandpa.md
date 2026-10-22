# Part 1 — Grandma / Grandpa Presentation Plan

A grandma-audience video explaining why our project (FPGA-based network intrusion detection) matters — using analogy, not jargon. Target: ~60-90 seconds. Video, not slides.

## 1. Professor's Guidance

### 1.1 Story: The "Facebook" mistake (professor told on lecture)

A prior student group did a project for old people that let them communicate remotely with their grandchildren. When presenting, the group said "*it's something like Facebook.*" The result: **nobody in the old-people audience listened to the rest of the presentation** — because old people hate Facebook. The group hadn't done enough research to know that.

**Takeaway**: analogies cut both ways. A bad analogy actively loses your audience in 10 seconds. A good analogy wins them in 10 seconds. Pick the analogy from the *audience's* world, not ours.

### 1.2 Directive: "Nowadays all presentations should be videos, not just slides" (professor on lecture)

Slide decks are legacy. Expect presentations to be produced as videos. Especially true for the grandma segment, where emotional pull matters more than information density.

### 1.3 Directive: "Use all tools you can use" (professor on lecture)

AI-generated visuals are encouraged. No purity test — if Runway or Sora gets us a better grandma video in less time, use them.

## 2. User's Angle (2026-04-17 session)

The user's thinking, captured verbatim from the session:

1. **Fit topic to edge AI safety**: "IoT and phone calls, since they are close to grandma/grandpa."
2. **Old people care about privacy**: real and well-documented. Seniors are heavily targeted by phone scams and increasingly wary of smart devices (smart TVs, Alexa, etc).
3. **Scale-up hook to industry**: use this as a bridge into Part 2 (investor). "We can say this applies as well to industry/big companies... imagine AI companies spend billions to train a LLM, and some cyber-hackers just spend hundred thousands to steal it and change some weights to reach same performance and without being detected since the weights are changed."
4. **Video can be AI-generated**: "actually the most ideal way, the goal for this part is simply to attract grandma/grandpa, AI-generated videos are easy to make and can easily look fancy."

## 3. Proposed Narrative Arc (draft, ~80 seconds)

**Structure**: hook → problem → our solution (by analogy) → why it matters → scale-up.

1. **Hook (0-15 sec)**: A warm scene — grandma receives a suspicious phone call, or her smart speaker lights up with an unfamiliar voice. "*Who's calling, grandma?*"
2. **Problem (15-30 sec)**: "*Bad people are trying to reach your phone, your TV, your home. They want your money, your pictures, your privacy.*"
3. **Solution by analogy (30-50 sec)**: "*What if your phone had a tiny guard inside, always watching, who could tell the good calls from the bad ones before they ever reach you?*" — visual of a friendly cartoon guard stopping a suspicious envelope.
4. **Why it matters (50-65 sec)**: "*That's what we built. A tiny chip that keeps a watchful eye — so your grandkids' phone calls get through, but the scammers don't.*"
5. **Scale-up (65-80 sec)**: "*And the same guard scales up — it protects hospitals, banks, even the companies that train the AI you use every day. From your living room to the world's biggest computers, one idea: spot the bad stuff before it gets in.*"
6. **Close (80-90 sec)**: Card with a single line: "Security that fits in your pocket. Built by [Group 12 / Zilin Shao]."

**[DIG DEEPER]:** Pick the specific analogy. Candidates are in `brainstorm_analogies.md`. Current lean (see that file's recommendation): grandchild's-instincts as the opening hook, tiny-security-guard as the mechanism, friendly-dog as the consistent visual. Test with a real grandparent if possible.

**[DIG DEEPER]:** Decide whether the scale-up hook lives in this video or is split off into a separate investor-video intro. Risk of mixing: grandma tunes out at "AI companies." Mitigation: scale-up framed as "same idea, bigger houses."

**[DIG DEEPER]:** Write the full narration script in one place (probably as a `part1_grandma_script.md` sibling file once the analogy is locked in). Word count target: ~180 words for 80 sec at 2.25 wps.

## 4. What Makes This *Different* From a Generic Security Ad

The differentiator that separates this from "buy Norton AntiVirus":
- **On-device** (no cloud watching your data) — privacy-preserving for grandma.
- **Custom hardware** — we built the chip, not bought one.
- **Edge AI inference** — the "guard" is a trained AI, not a rulebook.

**[DIG DEEPER]:** How much of this do we actually convey to grandma? Probably only the "doesn't send your stuff to the cloud" point. The hardware story is Part 2/3 material.

## 5. Hard Don'ts

- **Don't say "it's like Facebook for security"** (see §1.1).
- **Don't show Verilog or terminal windows** — grandma-hostile.
- **Don't use the word "packets" or "inference"** — jargon.
- **Don't start the video with a technical diagram** — lose the audience in 5 seconds.
- **Don't use an AI-generated photorealistic grandparent** — uncanny-valley faces are a specific AI-video failure mode (see `brainstorm_video_production.md` §4). Animate cartoon characters instead.

## 6. Production Notes

See `brainstorm_video_production.md` for tool options and time budget. First-pass budget:
- Script + storyboard: 4 hours (Apr 18 evening)
- AI clip generation: 4-6 hours (Apr 19 day)
- Voice-over recording: 1-2 hours (Apr 20 morning)
- Edit + polish: 4-6 hours (Apr 20 evening + Apr 21 day)
- Total: ~15-20 hours spread over 4 days.

**[DIG DEEPER]:** Confirm the video-generation credits/quota on the chosen tool. Free tiers of Runway/Sora/Kling are limited to ~5-10 clips. Plan for a paid month if scaling up.

## 7. Open Questions

- **[DIG DEEPER]:** Who's the on-screen narrator? User's own voice, AI-generated (ElevenLabs), or no narrator (music + subtitles only)? The grandmotherly narrator option (warm voice via ElevenLabs) is worth piloting.
- **[DIG DEEPER]:** Do we include a real grandparent on camera (user's own family)? Big emotional payoff if yes; logistically hard if no. Even a 3-second smiling cutaway at the end would land.
- **[DIG DEEPER]:** Test screening — can we show a rough cut to 1-2 real grandparents before Apr 28 and get feedback? Guards against the "Facebook mistake." Low cost (one phone call), high information value.
- **[DIG DEEPER]:** What specific scam/threat do we lead with? Phone scam (most universal, grandparents *know* this one personally), smart-home intrusion (more futuristic), or data breach (more abstract)? Phone scam is probably the winner.
- **[DIG DEEPER]:** What's the "click" moment — the single frame someone remembers after the video ends? Design it deliberately.
