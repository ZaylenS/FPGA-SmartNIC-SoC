# Final Project Demo Video — Plan

**Status:** active plan (drafted 2026-05-07). Supersedes `final_project_expert_demo_plan_apr17_HISTORICAL.md` (Apr 17, retained for reference).

**Target deadline:** ~2026-05-13.

**Engineer:** Zilin Shao, solo.

---

## 1. Goal & format

A single-track ~8–10 min demo video of the whole network-processor design and the solutions we built on it (inline ML-based IDS with custom GPU coprocessor, BCAST instruction, and on-chip ARM orchestration). No grandma/investor segments — those were for the live presentation only.

Audience: TAs grading the class (most weren't in the live final presentation), plus a general expert reviewer.

Production tooling: Clipchamp (consistent with M4 video). Voiceover recorded separately and aligned to clip cuts.

---

## 2. Beat outline (locked 2026-05-07; Beat 6 reframed 2026-05-08; Beats 6 + 7 re-split 2026-05-10; Beat 3 HTML refreshed 2026-05-10; Beat 0/1 trimmed + Beat 3 extended + Deck 1 added + headshot overlay decided 2026-05-10)

| # | Beat | Time | Source material | Notes |
|---|---|---|---|---|
| 0 | Cold open / hook | **~15 s** | Deck 1 stage 1 | "Network Processor with Inline ML-IDS" (two-line stack). Course code, speaker name, date. Letter-by-letter title reveal. |
| 1 | Classifier architecture | **~36 s** *(extended 2026-05-11)* | Deck 1 stage 2 | 11→16→8→2 fully-connected ANN sketch + per-layer weight-shape annotations (W1 11×16+16, W2 16×8+8, W3 8×2+2) + parameter-count callout (346 params · 692 bytes BF16) + spec cards (fully connected · ReLU · BF16 quantized via QAT · binary classification). |
| 2 | Dataset + training | **~89 s** | Deck 1 stages 3–4 + **two-part insert** (`train ids demo.mp4` ~12 s + `ids_inference_testing_dev_machine.mp4` ~15 s) + Deck 1 stage 5 | **Stage 3 (22 s):** NSL-KDD big stats (126K / 22.5K / 11) + 41→11 feature-selection visualization + real top-11 feature list (dst_bytes/src_bytes/flag/same_srv_rate/diff_srv_rate/dst_host_srv_count/dst_host_same_srv_rate/logged_in/protocol_type/count/service). **Stage 4 (22 s):** v3 recipe config card (Adam · lr 1e-3 cosine · 200 epochs · batch 256 · LS 0.1 · 15-seed sweep → seed 53 · QAT → BF16) + loss curve with "best val · early stop" marker. **Two-part insert (30 s)** *(restructured 2026-05-11)*: (1) `train ids demo.mp4` speed-ramped, **cut before final test-results screen** — shows the training pipeline running fresh for the demo (different seed than deployed, so its end numbers are intentionally hidden); (2) `ids_inference_testing_dev_machine.mp4` shows the deployed `data_ids_trained_weights.json` (seed 53) evaluating on KDDTest+ to produce the actual 82.4 % / 86.4 % attack recall / 77.1 % normal recall. **Stage 5 (15 s):** 82.4 % big number + KDDTest+ 22,544 samples · BF16-faithful caption + per-class recall + handoff arrow to "next: on silicon · Beat 3 · Beat 4 · Beat 5". |
| 3 | Architecture walkthrough | **~2:30–3:00** | Deck 2 — `claude_design_prompt_beat3_architecture.md` → `beat3_architecture.mp4` capture | 5-stage packet journey inside the SoC: FIFO + ARM (4 hardware threads visible) + DMA + GPU (4 SIMD lanes + 6-stage pipe + DMEM/IMEM mini-blocks + animated 0→732 cycle counter). Offline weights/program inset upper-right at 60 % opacity. *(2026-05-10 factual revision)* Stage 1 also reveals an upstream-feature-extraction inset on the left at 60 % opacity, marked "(not in this demo)" — features arrive pre-extracted. Stage 2 reframes ARM as orchestrator (polls FIFO_STATUS / sets FIFO_MODE / prepares DMA), not header-parser. Stage 5 closes at "response packet leaves over the wire as a packet" — interpretation and action policy deferred to Beats 6 and 7 honestly. *Stages stretched from 24 s → 30–36 s each on 05-10 to fill the larger budget.* |
| 4 | GPU + custom ISA + BCAST | **~2:20** *(extended 2026-05-11)* | Deck 3 — `claude_design_prompt_beat4_bcast.md` → `beat4_bcast.mp4` capture + `5 runs that show BCAST perf improve consistency.mp4` as the silicon-evidence supplement | 6-stage walkthrough: scalar-mode waste → inter-layer barrier (no cross-lane op) → 4:1 mux in EX1 → new opcode 5'b11010 with 32-bit encoding diagram → scalar vs BCAST inner-loop side-by-side → 2402 → 732 cycles bar chart with per-layer breakdown. Replaces the Apr 28 live-presentation BCAST clip (which was Q&A-narrow). |
| 5 | Live ML inference on silicon | **~65 s** *(shrunk 2026-05-11 — dev-machine eval moved to Beat 2c)* | `ids_inference_improved_testing_20samples.mp4` + `500 samples test on netfpga.mp4` | Silicon-only evidence: 20-sample FPGA live (18/20, 100% attack recall) + 500-sample batch (82.2%, 88% attack recall, 7 ms/pkt, 0/500 dropped). Voiceover bridges back to the dev baseline shown in Beat 2c: "silicon agrees with dev to ±0.01 logit / 0.2 pp accuracy." |
| 6 | **End-to-end inline IDS on the wire** | ~2 min | `Round-trip 5 takes.mp4` (3 ATTACK + 2 NORMAL on node1 via PCI round-trip path) | Node1 sends traffic; FPGA classifies in silicon; verdict returns over the wire as a UDP response. 5 takes shown (3 ATTACK / 2 NORMAL) — directly observable inline-IDS behavior. Closes with the "no PCI involvement in the inference path" framing — silicon does the classification; the host's `_form_and_drain_response` only assembles the response envelope to satisfy Linux RPF. |
| 7 | **Engineering candor — toward full on-chip autonomy** | ~50–60 s | `arm orchestrator BRAM dump.mp4` + `arm orchestrator throughput run.mp4` + `nf2 reference design tree.mp4` | The next mile of the work: ARM CPU on-die orchestrates the same pipeline autonomously — dispatches DMA, runs GPU, writes response headers — with no host involvement at all. BRAM dump shows the silicon writes correct response headers; throughput loop runs continuously. Wire-side delivery from the ARM path is bounded by the NF2 reference `output_queues`' drain FSM (stuck-after-one-packet behavior internal to the reference module, outside our module boundary — `nf2 reference design tree.mp4` shows that file lives in the ref lib, not our `src/`). Honest framing: "we got the silicon path to the BRAM; the ceiling is in code we don't own." |
|   | Closing | ~30 s | new title card | Headline takeaways. End. |

**Total budget (post-2026-05-11 EOD timing):** 15 + **36** + **89** + (165–195) + **140** + **65** + 120 + 55 + 30 = **715–745 s ≈ 12:00–12:25**. Beat 1 grew ~6 s (param-count callout + per-layer shape annotations + QAT card), Beat 2 stayed ~89 s but reallocated (now uses a two-part clip insert — training-for-demo + deployed-model eval). Beat 3 grew ~10–15 s (FIFO Port-A/B + ISA card + DMA poll-done). Beat 4 grew ~50 s (Deck 3 BCAST walkthrough). Beat 5 **shrank ~25 s** (dev-machine eval moved into Beat 2c, so Beat 5 goes straight to silicon evidence: 20-sample → 500-sample).

**Clip allocation by beat (as of 2026-05-10):**

| Clip | Beat(s) | Notes |
|---|---|---|
| New `deck1_intro_training.mp4` (pending capture) | 0, 1, 2 | Output of `claude_design_prompt_deck1_intro_training.md`; 5 stages. In Clipchamp, split between stages 4 and 5 to insert `train ids demo.mp4`. |
| `train ids demo.mp4` | 2 (middle) | Live training screen capture (05-08). Cuts into Deck 1 between stages 4 and 5. |
| New `beat3_architecture.mp4` (pending capture) | 3 | Output of `claude_design_prompt_beat3_architecture.md`; 5 stages, ~30–36 s each. |
| `5 runs that show BCAST perf improve consistency.mp4` | 4 | BCAST 3.28× cycle counter A/B |
| `ids_inference_testing_dev_machine.mp4` | 5 | KDDTest+ dev-machine eval |
| `ids_inference_improved_testing_20samples.mp4` | 5 | 20-sample FPGA live (18/20) |
| `500 samples test on netfpga.mp4` | 5 | 500-sample batch (82.2 %, 88 % attack recall) |
| `Round-trip 5 takes.mp4` | **6 (headline)** | Promoted from Beat 7 to Beat 6 on 05-10 |
| `arm orchestrator BRAM dump.mp4` | 7 | Silicon-level evidence of autonomous orchestration |
| `arm orchestrator throughput run.mp4` | 7 | Continuous-loop evidence |
| `nf2 reference design tree.mp4` | 7 | output_queues lives in NF2 ref lib boundary |

**Headshot webcam overlay (locked 2026-05-10)**: always-on, bottom-right corner, ~18 % of frame width (~360–400 px), circular crop, subtle drop shadow. Position `x = 1480..1880, y = 860..1080`. Both decks reserve this region; the demo clips were not captured with this constraint but the headshot will partially overlap their bottom-right corner — acceptable for terminal/screen-recording content since critical text is usually not in that corner.

**Power positioning** (Apr 28 v3 Slides 3.1 + 3.2) — **dropped from this video** per user direction 2026-05-07. If the closing card has room, a one-liner ("ASIC projection ~100 mW @ 28 nm — see presentation deck") is the longest mention allowed.

### Beat 6 / Beat 7 — B-Split (2026-05-10)

Supersedes the 2026-05-08 inline-IDS reframe. The split-axis is **what's wire-verified** vs. **what's silicon-verified**:

- **Beat 6 = wire-verified path (PCI round-trip).** `Round-trip 5 takes.mp4` shows 3 ATTACK + 2 NORMAL verdicts arriving on node1, end-to-end. The PCI host (`lab10reg.py:_form_and_drain_response`) assembles the response envelope, but the inference itself happens in silicon. This is the most visceral demo evidence we have.
- **Beat 7 = silicon-verified path (ARM orchestrator).** `arm orchestrator BRAM dump.mp4` proves the ARM CPU on-die autonomously writes correct response headers; `throughput run.mp4` proves it loops continuously without host. Wire-side delivery from this path is bounded by NF2 reference `output_queues`' drain FSM — confirmed via the BUFG re-synth investigation (see `project_oq_bufg_resynth_0508.md`) and `nf2 reference design tree.mp4` showing the file's location in the ref lib, outside our `src/`.

Why this split over the 05-08 inline-IDS reframe:
- The inline-IDS reframe dropped the strongest demo footage we had (verdicts on node1). B-Split keeps it as the headline.
- B-Split is honest about where each piece of evidence applies: Beat 6 = "this works on the wire (with host help)"; Beat 7 = "this works in silicon (no host) but the wire ceiling is in code we don't own."
- Beat 7 candor remains substantive (~50–60 s of engineering work + ceiling explanation), not a footnote.
- Beat 3's "no host round-trip" closing line still works — it primes Beat 7's "full autonomy is the next mile" frame, with Beat 6's host-assisted round-trip as the warm-up.

Things explicitly **not** claimed in this version:
- Beat 6 voiceover does **not** claim "ARM CPU dispatches end-to-end" — that's Beat 7's content.
- Beat 7 voiceover does **not** claim the ARM-path wire-side round-trip was completed — only that the silicon-side orchestration works and the ceiling lives outside our module boundary.

The 2026-05-08 inline-IDS framing notes (Fortinet/Snort/Pigasus inline-silent-inspection alignment) are not lost — they migrate into Beat 7's voiceover as "this is the same shape as how production inline IDSes work — they inspect silently in the data path; our ARM orchestrator is that path at silicon depth, modulo the throughput ceiling."

---

## 3. Schedule (May 7 → May 13)

| Date | Work |
|---|---|
| **May 7 (Thu)** | Outline locked. Docs scaffold up. Voiceover script outline started. Begin RPF unblock on node1. |
| May 8 (Fri) | RPF unblock complete (sysctl path). Tcpdump-verify response delivery. Re-run `ids_pci_throughput` and `ids_arm_start` with `--listen` end-to-end. Record `train_ids.py` Beat 2 footage. |
| May 9 (Sat) | Record ARM round-trip footage for Beat 6 (split-screen nf6 + node1). Multiple takes. Voiceover script first full pass. |
| May 10 (Sun) | Record voiceover. Begin Clipchamp assembly: title card + reuse clips + new ARM clip + animated arch diagram + new train_ids.py clip. |
| May 11 (Mon) | First full cut. Internal review pass. Re-record beats that need work. |
| May 12 (Tue) | Final polish. Captions if time permits. |
| **May 13 (Wed)** | Submit. |

If RPF unblock or ARM-round-trip recording slips, fall back to **Beat 6 = PCI-side-only verification** (use `ids_arm_debug_once 116` BRAM dump screenshots to prove the ARM orchestrator wrote correct headers; narrate the round-trip blocker honestly as "live response delivery is gated by a Linux kernel filter we'd resolve in production"). The fallback is defensible — it's the same evidence that satisfied 2026-04-21 silicon verification.

---

## 4. Blockers (must clear before recording)

### 4.1 Linux RPF / martian-source drop on node1 (gates Beat 6)

Documented in `project_throughput_tooling_2026-04-21.md` and `project_fixb_bitfile_2026-04-20.md`. Responses egressing the FPGA carry broadcast SrcIP (`10.0.7.255`) and broadcast SrcMAC (`ff:ff:ff:ff:ff:ff`) because the orchestrator and the Python `_form_and_drain_response` flow both swap MAC/IP fields verbatim — the original packet from node1 was sent to the broadcast address. Linux silently drops these as martians.

**Quick demo fix** (sufficient for video recording):
1. `sudo sysctl -w net.ipv4.conf.all.rp_filter=0`
2. `sudo sysctl -w net.ipv4.conf.all.accept_local=1` (sometimes needed)
3. Verify with `tcpdump -i <iface> -nne udp port 9998` while running `ids_pci_throughput 3` from nf6.
4. If tcpdump sees frames → kernel filter was the culprit; sysctl fixes it.
5. If tcpdump sees nothing → MAC0 TX path issue; investigate cabling / classifier routing (separate problem).

**Permanent fix** (production-quality, optional for the video):
- Edit `_form_and_drain_response` in `scripts/lab10reg.py` (~line 884) to hardcode a valid SrcMAC (e.g., `02:00:00:00:00:01` locally-administered) and SrcIP (e.g., `10.0.7.2`) on egress.
- Extend `programs/arm/ids_orchestrator.hex` (~20 instructions) to do the same in the ARM path.
- Zero the IP checksum (most stacks accept that) or recompute.

For the demo video, the quick fix is sufficient and avoids re-synth. The permanent fix is a future-work footnote in the voiceover.

### 4.2 New ARM round-trip footage doesn't exist yet

All existing FPGA video clips (`IDS inference on netfpga small demo.mp4`, `500 samples test on netfpga.mp4`) were recorded in **PCI mode** (`lab10reg.py ids_batch_packets`). For Beat 6 we need to record `ids_arm_start` running on nf6 with `send_ids.py --listen` showing responses arriving on node1. Plan: record May 9 once 4.1 is cleared.

### 4.3 New training/dataset footage for Beat 2 doesn't exist yet

Beat 2 needs a screen recording showing `train_ids.py` running end-to-end (feature selection → 50 epochs → BF16 quantization → JSON output). The Apr 28 dev-machine eval clip (`expert/ids_small_live_demo_dev_machine.mp4`) shows the *eval* pipeline, not training. Plan: record May 8 alongside the RPF unblock work. Speed-ramp the training portion (or pre-record overnight and trim) so the on-screen run takes ~30–45 s of clip time.

---

## 5. Production materials

### 5.1 To produce (updated 2026-05-10)

- [x] `train_ids.py` screen recording (Beat 2) — captured 05-08
- [x] ARM orchestrator footage (Beat 7) — captured 05-08
- [x] PCI round-trip footage (Beat 6) — captured 05-08
- [x] NF2 reference design tree footage (Beat 7) — captured 05-08
- [x] Beat 3 Claude Design prompt — drafted 05-10 (`claude_design_prompt_beat3_architecture.md`)
- [x] Deck 1 Claude Design prompt — drafted 05-10 (`claude_design_prompt_deck1_intro_training.md`)
- [ ] Deck 1 HTML output + screen capture → `deck1_intro_training.mp4` (user paste into Claude Design + capture)
- [ ] Deck 2 / Beat 3 HTML output + screen capture → `beat3_architecture.mp4` (user paste into Claude Design + capture)
- [ ] Voiceover script (all 8 beats, voiceover-only format with stage-level timing cues)
- [ ] Webcam + voiceover recording session (OBS, separate webcam mp4 + audio)
- [ ] Final cut .mp4 in Clipchamp (webcam overlay composited at bottom-right ~18 % circular crop)

### 5.4 Recording workflow (locked 2026-05-10)

**Approach**: separate webcam + screen captures, composite in Clipchamp. Most flexible for redoing individual segments.

1. **Pre-record all silent screen content** as mp4s: Deck 1 autoplay, Deck 2 autoplay, the demo clips already exist. Make simple title cards as PNGs or short mp4s.
2. **Assemble silent timeline in Clipchamp** — stitch all screen content end-to-end in beat order with the demo clips cut in at the right transitions. No audio yet. Get the *timing* right first.
3. **Record webcam + voiceover** in OBS while watching the silent Clipchamp preview play back. Single full pass OR beat-by-beat takes (beat-by-beat is more recoverable).
4. **Composite in Clipchamp** — webcam recording on track 2 (above screen content). Resize to ~18 % frame width, position bottom-right, circular crop + subtle shadow. Use audio from the webcam recording as the voiceover track.

**Camera + audio**:
- Solid color background behind speaker; no busy patterns.
- Light source in front, not behind. Eye-level camera.
- External mic if available; laptop mic is acceptable but worse.
- Wardrobe: solid color top.

### 5.2 To reuse (verbatim or trimmed)

See `README.md` "Source materials we'll be reusing" table.

### 5.3 Doc trail

Each new doc produced lands in `docs/final_project_demo_video/` and is linked from `README.md`. Anticipated:
- `voiceover_script.md` — all-beats transcript
- `production_runbook.md` — pre-recording setup, OBS config, take order, edit checklist
- `recording_log.md` — date-stamped notes on each take

---

## 6. Decisions locked 2026-05-07

- **Beat outline**: 7 beats, no power, training/dataset added as Beat 2.
- **RPF approach**: quick sysctl fix on node1.
- **Beat 6 fallback**: PCI-side-only verification (BRAM dump screenshots + honest narration) if round-trip can't be recorded.
- **Speaker**: voiceover only (no on-camera presence).
- **Title + closing cards**: plain text (project name, course code, name, date). Matches M4 video's no-frills approach.

---

## 7. Reference

- `final_project_expert_demo_plan_apr17_HISTORICAL.md` — Apr 17 plan (historical; live-DDoS narrative dead)
- `docs/throughput_measurement_runbook.md` — RPF blocker + ARM/PCI throughput methodology
- `docs/arm_orchestrator.md` — ARM orchestrator design and bring-up record
- `docs/bcast_instruction_design.md` — BCAST design rationale (Beat 3 backup)
- `docs/final_project_progress_present/part3_expert_v3.md` — Apr 28 expert deck slide notes
- `docs/final_project_progress_present/part3_expert_v3_transcript.md` — Apr 28 expert spoken transcript
- `docs/ids_accuracy_journey.md` — full IDS training/eval methodology, accuracy story
- `memory/project_status_0507.md` — status snapshot (M4 done, final demo pending)
- `memory/project_throughput_tooling_2026-04-21.md` — RPF blocker details
