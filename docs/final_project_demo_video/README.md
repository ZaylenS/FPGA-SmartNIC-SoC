# Final Project Demo Video — Doc Index

This folder holds everything produced while making the final project demo video (the only deliverable left for the class as of 2026-05-07). All new docs about the demo video go here.

## Scope (locked 2026-05-07)

- **Format**: single-track expert demo, **~8–10 min**
- **Out of scope**: grandma/grandpa and investor segments (those were live-presentation only — final presentation delivered 2026-04-30)
- **Headline new content**: ARM orchestrator demonstrated with a **real inline round-trip** (node1 → FPGA → node1), no host in the loop
- **Audience**: TAs grading; experts who weren't in the live presentation

## Docs in this folder

| File | Status | Purpose |
|---|---|---|
| [`README.md`](README.md) | live | This index |
| [`final_demo_video_plan.md`](final_demo_video_plan.md) | **active plan** | Beats, schedule, blockers for the May 13 deliverable |
| [`clips_catalog.md`](clips_catalog.md) | live | Inventory of source clips (existing + planned) with on-screen content + voiceover guidance. Reference for the voiceover script writing. |
| [`voiceover_script.md`](voiceover_script.md) | **ready to read** | Full voiceover script across all 8 beats + closing. Timing cues, stage directions, pronunciation reminders, per-beat recording tips. ~1,720 words at ~150 wpm = ~11:30 spoken. Read aloud against the silent Clipchamp timeline. |
| [`claude_design_prompt_deck1_intro_training.md`](claude_design_prompt_deck1_intro_training.md) | **ready to paste** | **Deck 1** (revised 2026-05-11). Claude Design prompt for Beats 0-2 (Title 15 s → Classifier 36 s → Dataset 22 s → Training methodology 22 s → Result 15 s; total ~110 s slide). Revised to match Deck 2/3 conventions: stage titles top of canvas, stage counter top-right, real values from the trained-weights JSON (346 params / 692 bytes BF16, real top-11 features, Adam 200 epochs cosine + QAT, dev recall 86.4 % attack / 77.1 % normal). In Clipchamp, the captured MP4 is split between stages 4 and 5 to insert `train ids demo.mp4`. Reserves bottom-right 400×220 px for the webcam overlay. Output → `final_demo_videos/deck1_intro_training.mp4`. |
| [`claude_design_prompt_beat3_architecture.md`](claude_design_prompt_beat3_architecture.md) | **ready to paste** | **Deck 2**. Claude Design prompt for Beat 3 architecture HTML — 5-stage packet-journey walkthrough, ~2:45–3:15 runtime (extended 05-11 with Port A/B + FIFO_MODE semantics + GPU ISA card + DMA poll-done), Stage 1 ~40–48 s, Stages 2-5 ~30–36 s each. Real BRAM offsets, real register sequence, real silicon logits, GPU ISA reference card. Reserves bottom-right 400×220 px for the webcam overlay. Output → `final_demo_videos/beat3_architecture.mp4`. |
| [`claude_design_prompt_beat4_bcast.md`](claude_design_prompt_beat4_bcast.md) | **ready to paste** | **Deck 3**. Claude Design prompt for Beat 4 BCAST HTML — 6-stage walkthrough, ~2:20 runtime, 22–26 s per stage. Story: scalar-mode waste → inter-layer barrier → 4:1 mux in EX1 → new opcode (encoding diagram) → kernel rewrite (scalar vs BCAST inner-loop side-by-side) → silicon-measured 2402→732 cycles. Replaces the Apr 28 live-presentation BCAST clip (which was Q&A-narrow); this version is TA-depth. Reserves bottom-right 400×220 px for the webcam overlay. Output → `final_demo_videos/beat4_bcast.mp4`. |
| [`final_project_expert_demo_plan_apr17_HISTORICAL.md`](final_project_expert_demo_plan_apr17_HISTORICAL.md) | *historical reference* | Apr 17 plan for live-DDoS Part-3 of a 3-part video. **Superseded** by `final_demo_video_plan.md` (2026-05-07). Live-DDoS narrative is dead; §2.5 (ARM orchestrator analysis) and §6/§7 (verification + risk patterns) still useful as reference material. |

Future docs (script, runbook, recording log, production checklist) will be added here and indexed in this table.

## Source materials we'll be reusing

Lifted from the Apr 28 expert presentation backbone (`docs/final_project_progress_present/`):

| Artifact | Path | Reuse target |
|---|---|---|
| Animated architecture diagram | `diagrams/architecture_diagram.mp4` | Beat 3 (architecture walkthrough) |
| BCAST design rationale | `diagrams/claude_design_prompt_bcast.md` | *(NOT reused — superseded by Deck 3 `claude_design_prompt_beat4_bcast.md` which goes deeper for TA depth)* |
| Dev-machine eval clip | `expert/ids_small_live_demo_dev_machine.mp4` | Beat 5 (KDDTest+ baseline) |
| 20-sample FPGA live | `expert/IDS inference on netfpga small demo.mp4` | Beat 5 |
| 500-sample FPGA batch | `expert/500 samples test on netfpga.mp4` | Beat 5 |
| BCAST cycle counter A/B | `expert/BCAST perf improve consistency.mp4` | Beat 4 |
| Expert speaker transcript | `part3_expert_v3_transcript.md` | Beat 1 (Fortinet cliff) — near-verbatim |
| Expert slide notes | `part3_expert_v3.md` | Q&A backup, Beat 1 talking points |

**New footage captured 2026-05-08:**
- `train ids demo.mp4` — Beat 2 (dataset + training, cuts into Deck 1)
- `arm orchestrator BRAM dump.mp4` — Beat 7 (silicon-level orchestrator evidence)
- `Round-trip 5 takes.mp4` — **Beat 6 headline** (5 takes, 3 ATTACK + 2 NORMAL via PCI round-trip; promoted from Beat 7 → Beat 6 in 05-10 B-Split)
- `arm orchestrator throughput run.mp4` — Beat 7 (continuous-loop evidence)
- `nf2 reference design tree.mp4` — Beat 7 (output_queues.v lives in NF2 ref lib, not our src/)

**Pending capture:**
- `deck1_intro_training.mp4` — Beats 0–2 slide deck (animated HTML, generated via Deck 1 Claude Design prompt)
- `beat3_architecture.mp4` — Beat 3 packet-journey slide deck (animated HTML, generated via Deck 2 Claude Design prompt — extended 05-11)
- `beat4_bcast.mp4` — Beat 4 BCAST walkthrough slide deck (animated HTML, generated via Deck 3 Claude Design prompt — drafted 05-11)

**Final production format**: webcam headshot overlay at bottom-right corner (~18 % frame width, circular crop), always-on, audio from webcam track. Both decks reserve the bottom-right zone so the overlay doesn't cover critical content.

## Open blockers

| Blocker | Owner | Impact |
|---|---|---|
| **Linux RPF / martian-source drop on node1** dropping FPGA responses with broadcast SrcIP/SrcMAC | open since 2026-04-21 | Gates Beat 5 (ARM round-trip) recording. Quick fix: `sysctl rp_filter=0 + accept_local=1` on node1 + `tcpdump` to confirm. Permanent fix: hardcode valid SrcMAC/SrcIP in `_form_and_drain_response` (lab10reg.py ~line 884) + `ids_orchestrator.hex`. See `project_throughput_tooling_2026-04-21.md` and `docs/throughput_measurement_runbook.md`. |

## Key context for picking up this work

- **Final presentation**: delivered 2026-04-30 ✅
- **M4 demo video**: delivered 2026-05-07 ✅
- **Final project demo video**: target ~2026-05-13 — **only remaining deliverable**
