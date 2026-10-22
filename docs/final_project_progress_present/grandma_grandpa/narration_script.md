# Grandma & Grandpa Video — Narration Script (v2)

Total runtime after 1 s crossfades: **76.6 s** (matches `transitions/transitions_A_classic_1s.mp4`).

## Why this version is more relatable than v1

Prof's note: *"Too generic, need stories that are relatable."* This rewrite anchors the abstract "bad envelopes" in the **specific scams seniors actually hear about on the news and from friends**:

- **The "grandson scam"** — a faked, scared voice asking for bail money. THE most-reported senior scam in the US.
- **AI voice cloning of family members** — a 2024–2026 news staple, and the perfect bridge from "your phone" to "the data center" later in the script.
- **Fake bank / Medicare / doctor calls** — every senior has either gotten one or knows someone who has.
- **Sunday calls with the grandkids** — a specific, universal senior moment that the dog/phone/cottage visuals already point at.

The v1 narration said things like *"the bad people have AI"* and *"the biggest place in the world."* Poetic, but a senior can't picture it. v2 swaps those for *"a voice that sounds like family"* and *"Sunday with the grandkids"* — same idea, but it lands in their kitchen.

The narrator persona is unchanged: warm storyteller, slow, gentle, never alarming. Pace targets ~2.5 words/sec so each line fits its 8 s clip with ~1 s breath at the end.

---

## Per-clip narration

### Clip 1 (8 s) — Cozy kitchen, the call comes in
**Visual:** Golden-hour kitchen, weathered hands cradle a mug, landline rings, dog perks up.
> A quiet afternoon. The phone rings. Unknown number. Maybe your doctor. Maybe the bank.

*13 words.*

### Clip 2 (8 s) — "Unknown Number"
**Visual:** Smartphone close-up, "UNKNOWN NUMBER", dog tilts head with a tiny worried whimper.
> Or — one of those calls you've heard about. A grandson in trouble. A voice that sounds like family.

*18 words. Names the **grandparent scam** and **AI voice cloning** without saying those words.*

### Clip 3 (8 s) — Envelopes drift toward the cottage
**Visual:** Twilight cottage, shadowy envelopes float toward the warm windows.
> These days, the bad ones don't knock on the door. They slip in — through your phone, your email, your TV.

*20 words. "Don't knock on the door" is the relatable analogy: a senior knows what a doorbell threat feels like; this reframes it.*

### Clip 4 (8 s) — Envelopes at the window, dog growls
**Visual:** Inside the cottage, envelopes peer through glass, dog stands guard between them and the devices.
> They want your password. Your photos. Your savings. Even the voice of someone you love — to use against you.

*19 words. Concrete list of what's at stake. "The voice of someone you love" hooks back to clip 2 and forward to clip 9.*

### Clip 5 (8 s) — Magical zoom into the phone, tiny guard
**Visual:** Camera dives through the phone screen into a tiny world; chibi security guard with paw-print badge, dog at his side.
> But what if a tiny guard lived right inside your phone? One who never sleeps — and who knows who's family.

*20 words. Introduces the metaphor. "Knows who's family" makes the abstract idea of authentication feel like recognition.*

### Clip 6 (8 s) — Guard sorts good vs. bad envelopes
**Visual:** Good envelopes (heart, child's drawing, stethoscope) walk through; sneaky envelope poofs away after the dog's bark.
> The real call from your grandson — straight through. The fake one — gently turned away. No fuss. No worry.

*19 words. Mirrors clip 2's setup ("a grandson in trouble") with a payoff: now you know which is real.*

### Clip 7 (8 s) — Pull back, chip pulses, the call is answered
**Visual:** Pastel-blue chip pulses inside the phone; the same hands answer; grandchild on screen waves "Hi Grandma!"; dog's tail thumps.
> So the calls that matter most — Sunday with the grandkids — those always come through. Clear, safe, and yours.

*18 words. "Sunday with the grandkids" is the specific senior moment that anchors the entire video.*

### Clip 8 (8 s) — Same chip on hospital, bank, data center
**Visual:** Wide map view; chip stamp lands on a hospital, a bank, a data center; dog trots between them.
> And it's not just your phone. Your hospital has one. Your bank has one. Even the big computers behind today's AI.

*21 words. "The big computers behind today's AI" is more concrete than v1's "the biggest place in the world" — seniors have heard "AI" everywhere lately and know it lives in big computers.*

### Clip 9 (8 s) — Inside the data center, guards turn threats away
**Visual:** Friendly server racks shaped like bookshelves with pulsing AI orbs; sneaky envelopes with wrenches turned away.
> Because the same tricksters who copy your grandson's voice — they whisper to those big computers, too.

*17 words. **This is the key payoff sentence**. It connects the personal threat (clip 2) to the data-center scale (clip 8) with one shared villain. That linkage is what makes the project's actual thesis — protecting AI infrastructure — feel personal.*

### Clip 10 (8 s) — Sunset kitchen, dog by phone, the chip glows once
**Visual:** Same kitchen as clip 1, now sunset; dog curled by phone, ears alert; soft glow pulses once from the phone.
> So tonight — the phone is quiet. The dog is asleep. And the little guard is still watching.

*16 words. Mirrors clip 1 ("a quiet afternoon") for narrative bookend. "The dog is asleep" is the calm payoff after his clip-4 growl.*

### Clip 11 (6 s) — Endcard
**Visual:** "Security that fits in your pocket. Group 12 — Zilin Shao." Dog tilts head, gives a small wag.
> Security that fits in your pocket. Looking out for what — and who — you love.

*14 words. v1 ended at "in your pocket"; the added phrase makes it about people, not devices.*

---

## Word count totals

| Clip | Words | At 2.5 wps |
|------|-------|------------|
| 1 | 13 | 5.2 s |
| 2 | 18 | 7.2 s |
| 3 | 20 | 8.0 s |
| 4 | 19 | 7.6 s |
| 5 | 20 | 8.0 s |
| 6 | 19 | 7.6 s |
| 7 | 18 | 7.2 s |
| 8 | 21 | 8.4 s |
| 9 | 17 | 6.8 s |
| 10 | 16 | 6.4 s |
| 11 | 14 | 5.6 s |
| **Total** | **195** | **78.0 s** |

Slightly over the 76.6 s video. ElevenLabs at the existing voice settings (stability 0.60, style 0.35) reads a touch faster than 2.5 wps for warm-but-clear delivery, so this should land at ~75 s and leave a small breath at every clip end. If any clip's audio overruns the visual, slow the line down by trimming 1-2 filler words rather than cutting meaning.

---

## How to generate

1. `cd docs/final_project_progress_present/grandma_grandpa/`
2. `export XI_API_KEY=<your_eleven_labs_key>` (or `set` on cmd / `$env:XI_API_KEY=` on PowerShell)
3. `python generate_audio.py`
4. 11 MP3s land in `audios/` (clip01… through clip11…).
5. In Clipchamp / your editor, drop each MP3 onto the timeline starting at the corresponding clip's start. Each MP3 is shorter than its clip's window so a small bed-music gap will fall at the end of each clip — that's intentional, lets the music breathe between lines.

The voice ID and tuning in `generate_audio.py` are unchanged from the previous run, so the new MP3s will match the voice you already chose.
