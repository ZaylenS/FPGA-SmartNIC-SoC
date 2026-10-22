# Brainstorm — Video Production Workflow (Solo, 1 Week)

Practical workflow for producing both the grandma video (~60-90 sec) and the investor video (~90-120 sec) as a solo engineer in ~11 days.

## 1. Tool Stack Options

### 1.1 AI video generation

| Tool | Strengths | Cost | 2026 status |
|------|-----------|------|-------------|
| Sora (OpenAI) | High quality, good physics | Subscription-based | Mature as of 2026 |
| Runway Gen-3/4 | Fast iteration, good UI | $35/mo mid-tier | Industry standard for AI cuts |
| Kling (Kuaishou) | Strong motion, cheap | ~$20/mo | Popular with indie creators |
| Luma Dream Machine | Good for quick clips | Freemium | Solid free tier |
| Pika Labs | Consistent characters across clips | $35/mo pro | Best for a recurring "dog" or "guard" character |
| Veo (Google) | High fidelity | Subscription | Available via Gemini Advanced |

**[DIG DEEPER]:** Pick one primary tool (consistency matters; mixing tools gives jarring style shifts). Probably Runway or Pika. Test run a 5-sec clip on each before committing.

**[DIG DEEPER]:** Free tiers are usually enough for ~5-10 short clips. A single video needs ~8-12 clips. Two videos ~= 20 clips, so one paid month of one tool should suffice. Budget $35-50.

### 1.2 Voice-over

| Tool | Strengths |
|------|-----------|
| ElevenLabs | Best-in-class voice cloning; emotional range |
| OpenAI TTS (via API) | Good quality, cheap |
| PlayHT | Solid alternative |
| User's own voice | Free, authentic — recommended for investor segment if user's delivery is good |

**[DIG DEEPER]:** For grandma segment, consider a warm / grandparent-adjacent voice via ElevenLabs. For investor segment, user's own voice feels more credible. Interview clips will use interviewees' actual voices.

### 1.3 Music / soundtrack

| Source | Notes |
|--------|-------|
| YouTube Audio Library | Free, royalty-free |
| Suno AI | Generate custom music from a prompt |
| Mubert | AI music, mood-based |
| Epidemic Sound | Professional, subscription |

**[DIG DEEPER]:** For grandma, warm / piano-based; for investor, upbeat / corporate-tech. Keep music at -12 dB under voice-over.

### 1.4 Editing

| Tool | Cost |
|------|------|
| DaVinci Resolve | Free (Studio version paid; free is more than enough) |
| CapCut | Free, easy |
| Premiere Pro | Subscription |
| iMovie | Free on Mac |

**[DIG DEEPER]:** DaVinci Resolve free tier handles 4K, color grading, audio — overkill for this project but no downside. CapCut if user prefers faster turnaround.

### 1.5 Storyboard + script

- ChatGPT / Claude for first-pass script
- Pen + paper or Miro / Figma for storyboard

## 2. Workflow (per video)

1. **Script** (2-3 hrs)
   - Write the voice-over narration first, *not* visuals. Visuals follow narration.
   - Target word count: ~150 words for 60 sec, ~250 for 90 sec (at ~2.5 wps).
   - Get feedback from 1-2 trusted people before proceeding.
2. **Storyboard** (1-2 hrs)
   - Sketch each 5-10 second beat. ~10 beats for a 60-sec video.
   - Note the visual style: realistic, cartoon, mixed? (Consistency > variety.)
3. **Generate clips** (4-6 hrs)
   - Prompt engineering per clip: use the same descriptive phrases across clips (same character, same lighting, same environment) for consistency.
   - Expect ~2-3 generations per final clip (pick the best).
4. **Voice-over** (1-2 hrs)
   - Record in a quiet room with a decent mic (even a phone's mic is usable if close).
   - For AI voice: generate, listen, regenerate if emotional tone is off.
5. **Edit** (4-6 hrs)
   - Cut clips to beats.
   - Layer voice-over.
   - Add music (at -12 dB under voice).
   - Add title cards, subtitles.
   - Export at 1080p, H.264.

**Total per video: ~14-20 hours.**

Two videos = ~30-40 hours. Across 11 days, that's ~3-4 hours/day. Feasible but tight.

**[DIG DEEPER]:** Reserve 2026-04-26 and 2026-04-27 as a buffer. If a clip fails to generate well, iteration costs real time.

## 3. Consistency Tricks

- **Character lock**: use the same descriptive phrase for your "character" across every clip. E.g., "*a golden retriever wearing a blue security guard cap, cartoon style, warm lighting.*"
- **Color palette**: pick 3-5 colors and specify them in prompts.
- **Aspect ratio**: choose 16:9 for lecture presentation (default for most AI tools).
- **Length per clip**: 3-8 seconds per AI-generated clip works best. Longer clips accumulate more artifacts.

**[DIG DEEPER]:** Generate 3 "character reference" clips first to lock the style. Then generate story clips.

## 4. Pitfalls (common AI-video mistakes)

- **Uncanny humans**: AI video tools mishandle hands and faces. For grandma segment, consider animated characters instead of photorealistic people.
- **Inconsistent character across clips**: unless you use character-consistency features (Pika has this) or very careful prompting.
- **Text / captions inside AI clips**: AI video tools garble text badly. Add text as a *post* layer in the editor, not inside generated clips.
- **Abrupt cuts**: AI clips often feel "floaty" — add crossfades or short transitions.
- **Audio-visual mismatch**: voice-over timing often doesn't match clip length exactly. Record after clips are cut, not before.

## 5. Deliverable Format

| Property | Value |
|----------|-------|
| Resolution | 1920x1080 (16:9) |
| Codec | H.264 |
| Container | MP4 |
| Audio | AAC, -14 LUFS (standard for web) |
| File size target | <200 MB per video (email / upload safe) |
| Captions | SRT file alongside, or burned in |

**[DIG DEEPER]:** Check lecture presentation setup. Is the room showing via projector (MP4 fine) or streaming (file upload required)?

## 6. Time Budget Sheet

| Task | Grandma | Investor | Shared |
|------|---------|----------|--------|
| Script | 3 hr | 3 hr | — |
| Storyboard | 2 hr | 2 hr | — |
| Clip generation | 5 hr | 4 hr | — |
| Voice-over | 1 hr | 1 hr | — |
| Edit | 5 hr | 5 hr | — |
| Interview recording | — | 2 hr | — |
| Music selection | — | — | 1 hr |
| Final review pass | — | — | 2 hr |
| **Total** | 16 hr | 17 hr | 3 hr |
| **Grand total** | | | **36 hr** |

Over 11 days = ~3.3 hr / day. Realistic for solo work alongside other responsibilities.

**[DIG DEEPER]:** Front-load the investor interview recording (contact by Apr 18, record by Apr 22) — it's the least-controllable item.

## 7. Critical Path

The items most likely to cause a schedule slip, in order:

1. **Investor interview** — external dependency. Backup interviewee needed.
2. **Clip generation consistency** — if characters drift across clips, you lose hours re-generating. Solve early (Apr 19).
3. **Voice-over timing** — record late, after clips are cut.
4. **Final review pass** — leave at least 4 hours for this; it always reveals something.

**[DIG DEEPER]:** Dry run the whole workflow on a 20-second test video *before* scaling to the 60-90 second targets. Catches tool-gotchas early.
