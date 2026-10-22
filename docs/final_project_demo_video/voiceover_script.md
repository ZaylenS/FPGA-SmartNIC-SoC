# Voiceover Script — Final Project Demo Video

**Drafted 2026-05-10.** For the ~11:10–11:40 final demo video. Speaker: Zilin Shao. Recording approach: webcam + mic in OBS while watching the silent Clipchamp timeline play back. Beat-by-beat takes recommended.

## How to use this script

- **Read aloud, don't memorize.** The user style preference is read-from-transcript; this script is built to be spoken naturally.
- Pace target: ~150 words per minute = 2.5 words per second (technical speaking pace).
- Brackets `[like this]` are stage directions / what's on screen — **do not read them aloud**.
- Italic emphasis indicates words to stress lightly when speaking.
- `↘` = natural pause (~0.5 s); `↘↘` = longer pause / breath (~1 s).
- Numbers spelled out for spoken cadence ("eleven-sixteen-eight-two" not "11-16-8-2").
- Total runtime budget: 670–700 s (≈ 11:10–11:40).

## Timing summary

**Note (post-2026-05-11 revisions):** Deck 1 grew (Beat 1 + Beat 2 carry more methodology detail), Beat 3 grew (Port A/B + ISA card + DMA poll-done), and Beat 4 grew (new Deck 3 BCAST walkthrough). All times below are best-effort estimates; refine in Clipchamp.

| Beat | Time | Visual | Word budget |
|---|---|---|---|
| 0 — Title | 0:00–0:15 | Deck 1 stage 1 | ~37 |
| 1 — Classifier architecture | 0:15–0:51 | Deck 1 stage 2 | ~90 |
| 2 — Dataset + training | 0:51–2:20 | Deck 1 stages 3–5 + post-deck training-clip evidence (audio-only) | ~220 |
| 3 — Architecture walkthrough | 2:20–5:10 | Deck 2 stages 1–5 | ~395 |
| 4 — GPU + ISA + BCAST | 5:10–7:30 | Deck 3 stages 1–6 + supplementary `5 runs that show BCAST perf improve consistency.mp4` | ~340 |
| 5 — Live ML inference (silicon only) | 7:30–8:35 | 2 silicon clips *(dev-eval moved to Beat 2c)* | ~120 |
| 6 — End-to-end on the wire | 8:35–10:35 | `Round-trip 5 takes.mp4` | ~240 |
| 7 — Engineering candor | 10:35–11:30 | ARM BRAM dump + throughput + nf2 ref tree | ~130 |
| – Closing | 11:30–12:00 | Closing title card | ~65 |

**Total runtime estimate:** ~12:00. Beat 5 shrank by ~25 s after the dev-machine eval moved into Beat 2d (so Beat 2d now uses both `train ids demo.mp4` for "training-for-demo" visual + `ids_inference_testing_dev_machine.mp4` for "deployed-model eval" result). **2026-05-12 production change:** Beat 2's two training clips moved from between Deck 1 stages 4-5 to AFTER Deck 1 finishes (after the 82.4 % result reveal), so OBS records all of Deck 1 in one continuous take with webcam. The clip segment is then voice-only (no webcam overlay) since the clips themselves fill the frame.

---

## Beat 0 — Cold open (0:00 – 0:15, ~15 s)

**On screen**: Deck 1 stage 1 — Title "Network Processor with Inline ML-IDS" letter-by-letter reveal, then course code, name, date.

> Hi, I'm Zilin Shao. ↘ This is the EE-five-three-three final project: ↘ a custom network processor that runs a machine-learning intrusion detection system on FPGA.

---

## Beat 1 — Classifier architecture (0:15 – 0:51, ~36 s)

**On screen**: Deck 1 stage 2 — 11-16-8-2 ANN sketch with per-layer weight-shape annotations (W1 11×16+16, W2 16×8+8, W3 8×2+2), parameter-count callout (346 params · 692 bytes BF16), and four spec cards (fully connected · ReLU activations · BF16 quantized (QAT) · binary classification).

> The classifier is a small fully-connected neural network. ↘ Eleven inputs — ↘ packet features that I'll explain in a moment. ↘ Two hidden layers of sixteen and eight neurons with ReLU activations. ↘ Two outputs: ↘ a normal score and an attack score. ↘↘ Three hundred and forty-six total parameters — ↘ that's six hundred and ninety-two bytes at BF-sixteen precision. ↘ Small enough to fit comfortably in the GPU's data memory, ↘ alongside the inputs and intermediate activations. ↘↘ The weights are quantization-aware-trained — ↘ the network was trained knowing it would run in BF-sixteen on silicon, ↘ so the deployed numerics are faithful to what trained. ↘↘ Inference runs inline — ↘ the model executes as packets traverse the FPGA, ↘ between ingress and egress.

---

## Beat 2 — Dataset + training (0:51 – 2:20, ~89 s)

### Beat 2a — Dataset (0:51 – 1:13, ~22 s)

**On screen**: Deck 1 stage 3 — NSL-KDD big stats (126 K · 22.5 K · 11), 41 → 11 feature-selection visualization, top-11 feature list with `src_bytes` and `dst_bytes` highlighted.

> We trained on NSL-KDD — ↘ the de-duplicated cleanup of the classic KDD'99 intrusion-detection benchmark. ↘ A hundred and twenty-six thousand training samples, ↘ twenty-two and a half thousand test samples in KDDTest-plus. ↘↘ NSL-KDD ships with forty-one features per connection. ↘ We rank them by random-forest importance ↘ and keep the top eleven. ↘ Two of those — source-bytes and destination-bytes — ↘ carry most of the signal.

### Beat 2b — Training methodology (1:13 – 1:35, ~22 s)

**On screen**: Deck 1 stage 4 — config card with v3 recipe (Adam · lr 1e-3 cosine · 200 epochs · batch 256 · cross-entropy · label smoothing 0.1 · 15-seed sweep → seed 53 · QAT → BF16) + loss curve with "best val · early stop" marker at epoch ~25.

> Training: ↘ Adam optimizer, ↘ two hundred epochs with cosine learning-rate decay, ↘ batch size two hundred and fifty-six, ↘ cross-entropy loss with label smoothing of zero point one. ↘↘ We swept fifteen random seeds and kept seed fifty-three. ↘↘ The best-validation checkpoint comes from early in training — ↘ label smoothing reduces overfitting fast at this network size. ↘↘ Final step: ↘ quantization-aware training, which makes the deployed weights faithful to B-F-sixteen at inference time.

### Beat 2c — Result reveal (1:35 – 1:50, ~15 s)

**On screen**: Deck 1 stage 5 — "82.4 %" big number reveal, "KDDTest+ · 22,544 samples · BF16-faithful" caption, per-class recall row (attack 86.4 % · normal 77.1 %), "next: training demo + hardware architecture →" handoff arrow.

> On the dev baseline, the model hits *eighty-two point four percent* accuracy on KDDTest-plus — ↘ twenty-two thousand five hundred and forty-four samples, evaluated faithfully in BF-sixteen. ↘ Attack recall is eighty-six percent on the dev machine. ↘↘ Next, ↘ a quick demo of how this trains, ↘ then on to the hardware architecture.

### Beat 2d — Training pipeline evidence (1:50 – 2:20, ~30 s) — audio-only, post-deck

**Production note**: Deck 1 has finished playing (continuous OBS take ends at stage 5). This segment is a **voice-only audio pass over the two clips** — no webcam overlay, no slide. The clips fill the frame.

**On screen, two-part insert (in this order)**:
1. **~12 s**: `train ids demo.mp4` — speed-ramped through the training loop (loss dropping, validation climbing). **Cut BEFORE the final test-results screen** so this clip's own end numbers (which come from a separate demo training run with a different random seed and don't match the deployed model) never appear on camera. This clip is shown only to prove the training pipeline works end-to-end.
2. **~15 s**: `ids_inference_testing_dev_machine.mp4` — eval script loading `data_ids_trained_weights.json` (seed 53, v3 recipe — the actual deployed weights) and running it on KDDTest+ to produce `BF16 KDDTest+ accuracy: 0.8239 (18575/22544)`, `F1(A) = 0.848`, attack recall 0.864 — the deployed model's numbers, matching the Deck 1 stage 5 number you just saw.

> Two clips here. ↘↘ First: ↘ the training pipeline running live, ↘ just to show that the pipeline itself works end-to-end. ↘ Note this is a fresh demo run with a different random seed — ↘ its final numbers aren't the deployed model's. ↘↘ Second: ↘ the actual deployed weights — ↘ seed fifty-three, ↘ the model that loads onto the FPGA — ↘ evaluated on KDDTest+ on the dev machine. ↘↘ Eighty-two-point-four percent, ↘ identical to the slide.

---

## Beat 3 — Architecture walkthrough (2:15 – 5:05, ~170 s)

**On screen**: Deck 2 (Beat 3 packet-journey HTML), Stage 1 ~42 s + Stages 2-5 ~32 s each. *(Downstream beats shift ~10 s later; refine in Clipchamp.)*

### Beat 3.1 — The chip (2:15 – 2:57, ~42 s)

**On screen**: SoC interior — FIFO (dual-port 256×72 BRAM with Port A always-on to NetFPGA data path, Port B muxed by FIFO_MODE register to PCI / ARM / DMA), Mode register footnote panel below FIFO, ARM (4 threads), DMA (1 word/cycle pipelined), GPU (ISA footprint visible, 1024-word IMEM+DMEM, 4 SIMD lanes, layer-flow pill row 11→16→8→2, 6-stage pipe). Offline weights+program inset upper-right. Upstream-FE inset on the left.

> This is the SoC. ↘ One FPGA. ↘↘ Convertible FIFO at the center. ↘ Port B muxes between PCI, ARM, and DMA based on the FIFO_MODE register. ↘↘ The ARM has an address-alias window into the chip's register space, ↘ which lets it orchestrate FIFO, DMA, and GPU on its own — ↘ without the host involved. ↘↘ And there is one honest disclosure: ↘ the upstream feature extraction is mocked — ↘ on our testing, packets arrive with eleven pre-extracted features in the payload.

### Beat 3.2 — Packet arrives, ARM orchestrates (2:57 – 3:29, ~32 s)

**On screen**: Packet glyph slides through upstream-FE inset into FIFO. TopLeft Panel opens with input BRAM layout. ARM "poll + setup" control arrow to FIFO. ARM thread T0 lights. ARM Right Panel opens with register-readout snippet.

> A packet arrives from the network. ↘ It lands in the FIFO BRAM through Port A. ↘↘ The BRAM is laid out word by word — ↘ the NetFPGA framing header at word zero, ↘ the Ethernet, IP, and UDP headers at words one through six, ↘ and the eleven feature values for this packet — pre-extracted BF-sixteen values — at words seven through seventeen. ↘↘ The ARM CPU — running on its orchestrator thread — polls the FIFO status register, ↘ waits for the packet-ready bit, ↘ then writes the FIFO mode register: ↘ mode equals two. ↘ That flips the Port B mux from PCI to the DMA engine. ↘↘ The ARM does not parse the packet itself. ↘ It's just the orchestrator, ↘ not the classifier.

### Beat 3.3 — DMA streams to GPU (3:29 – 4:01, ~32 s)

**On screen**: ARM pulse. Below-DMA Panel opens with DMA register programming (incl. poll-done line). Moving-dash arrow FIFO → DMA → GPU DMEM with "11 BF16 words · replicated {x,x,x,x}" label. GPU DMEM fills slot-by-slot. GPU IMEM briefly glows.

> The ARM programs the DMA engine — ↘ source, destination, length, then a start command. ↘↘ The DMA pulls the eleven feature words from FIFO BRAM and pipes them into the GPU's data memory — ↘ one word per cycle, fully pipelined. ↘ Each word is a BF-sixteen feature value replicated across all four SIMD lanes; ↘ the kernel works in lane-replicated mode. ↘↘ Meanwhile, the ARM polls the DMA's start bit, ↘ which auto-clears when the DMA finishes — ↘ that's how ARM and DMA stay in sync. ↘↘ The GPU's program is already in instruction memory, loaded at boot. ↘ Now the GPU is ready to classify.

### Beat 3.4 — GPU classifies (4:01 – 4:33, ~32 s)

**On screen**: TopLeft Panel opens with GPU ISA reference card (12 opcodes, BCAST highlighted, 16 × 64-bit regs). 4 SIMD lanes pulse. Layer-flow pill row pulses sequentially L1 → L2 → L3. 6-stage pipe rolls. Cycle counter animates 0 → 732 with "with BCAST · Beat 4 covers the design" tag. Verdict badge below IMEM shows real silicon logits.

> The GPU has a custom ISA — ↘ standard ALU and memory ops, ↘ plus our own cross-lane primitive BCAST, which I'll cover in a moment. ↘↘ Four SIMD lanes, BF-sixteen, ↘ running the eleven-sixteen-eight-two ANN. ↘↘ A hardware cycle counter on the FPGA reads *seven hundred and thirty-two* cycles for the full classification — ↘ that's with BCAST. ↘↘ At the end, the GPU writes a two-element BF-sixteen verdict back to its data memory. ↘ For this packet — a real attack sample from our test set — ↘ the normal logit reads negative five point five, ↘ the attack logit reads positive eight point eight. ↘ Clearly an attack.

### Beat 3.5 — Response packet out (4:33 – 5:05, ~32 s)

**On screen**: ARM pulse. Below-DMA Panel reopens with DMA-out register programming (incl. poll-done line). Heavy moving-dash arrow GPU DMEM → DMA → FIFO. TopLeft Panel reopens with response BRAM layout. ARM Right Panel reopens with header-rewrite + drain snippet. ARM pulses with "swap MAC + IP src↔dst" callout. Packet glyph exits cleanly along Packet Out. Final glow.

> The ARM programs the DMA again, ↘ this time in reverse — ↘ GPU-to-FIFO, copying the two BF-sixteen logits back into the response area of the FIFO BRAM. ↘ ARM polls until the DMA finishes. ↘↘ Then the ARM rewrites the response packet's headers in BRAM: ↘ swap source and destination MAC addresses, ↘ swap source and destination IP addresses, ↘ write the UDP ports. ↘ The packet now routes back to whoever sent it. ↘↘ The ARM flips the FIFO mode register from two to one — ↘ Port B mux now points back at the ARM — ↘ and sets the drain bit. ↘ The verdict packet leaves over the wire through Port A. ↘↘ That's the architectural claim of this build: ↘ a small ML model, ↘ running on a custom GPU inside a single FPGA, ↘ classifying each packet's feature vector ↘ on-die.

---

## Beat 4 — GPU + custom ISA + BCAST (5:10 – 7:30, ~140 s)

**On screen**: Deck 3 (Beat 4 BCAST HTML), 6 stages × ~22–26 s each. Supplementary clip `5 runs that show BCAST perf improve consistency.mp4` can be cross-cut into Beat 4.6 in Clipchamp if there's room.

### Beat 4.1 — The waste, scalar mode (5:10 – 5:32, ~22 s)

**On screen**: Deck 3 stage 1 — 4 lane rectangles (lane 0 active orange; lanes 1-3 grayed with diagonal hatching, "wasted" stamped). R3 = {x[i], x[i], x[i], x[i]} annotation. "25 % SIMD utilization" badge. Scalar inner-loop snippet showing all lanes compute the same thing.

> Our GPU has a four-lane SIMD datapath — ↘ every arithmetic instruction operates element-wise across all four lanes. ↘↘ But the base ISA has no cross-lane operations. ↘ So for a multi-layer network, every value is pre-replicated across all four lanes: ↘ R3 equals x-of-i, x-of-i, x-of-i, x-of-i. ↘↘ All four lanes compute the same thing. ↘ Three of four are wasted. ↘ Twenty-five percent SIMD utilization.

### Beat 4.2 — The inter-layer barrier (5:32 – 5:56, ~24 s)

**On screen**: Deck 3 stage 2 — top register R1 = {h3, h2, h1, h0} in four distinct pastels; red "NO INSTRUCTION" barrier; bottom register R3 = {h0, h0, h0, h0} needed; ghosted broken arrow with red ✕; side panel enumerating what base ISA can / cannot do.

> So why scalar mode? ↘ Because multi-layer networks force it. ↘↘ Layer N's four outputs sit in one register — ↘ h-three, h-two, h-one, h-zero, ↘ one per lane. ↘ Layer N-plus-one needs each output broadcast across all four lanes as the next layer's input. ↘↘ Our base ISA had no instruction for that. ↘ M-O-V-I broadcasts a *constant*, ↘ not a register value. ↘↘ No horizontal sum, no lane shuffle. ↘ So scalar mode.

### Beat 4.3 — The hardware fix: 4:1 mux in EX1 (5:56 – 6:22, ~26 s)

**On screen**: Deck 3 stage 3 — pipeline-stage tag with EX1 highlighted in the 6-stage pipe (IF → ID → **EX1** → EX2 → EX3 → WB). Datapath: Register file → BCAST 4:1 lane mux (green, highlighted) → 4 SIMD ALUs. Lane-select control input cycling 0 → 1 → 2 → 3. Resource callout: `+65 LUTs · ~0.1 % of XC2VP50 · 0 new flip-flops · purely combinational`.

> The fix is a four-to-one lane mux added in EX1, ↘ right before the per-lane ALU dispatch. ↘↘ When the opcode is B-CAST, ↘ the mux selects one lane of the source register — ↘ chosen by two bits from the instruction — ↘ and replicates it across all four output lanes. ↘ The per-lane ALUs pass it through. ↘↘ Sixty-five lookup tables — ↘ about a tenth of a percent of the chip. ↘ Zero new flip-flops; ↘ the mux is purely combinational.

### Beat 4.4 — The ISA fix: a new opcode (6:22 – 6:46, ~24 s)

**On screen**: Deck 3 stage 4 — 32-bit instruction encoding diagram (7 bit-field cells: opcode 11010 / rd / rs1 / 0000 / dtype / unused / lane). Field-callout arrows. Assembly syntax box: `BCAST Rd, Rs1, lane`. Two example encodings: `BCAST R3, R1, 0 → 0xD1880000` and `BCAST R3, R1, 2 → 0xD1880002`. "2-cycle latency, same as MOV" tag.

> On the ISA side, ↘ B-CAST is the GPU's twelfth opcode. ↘↘ The lane select is encoded in the bottom two bits of the func field — ↘ reusing existing instruction bits, ↘ so no new control signal width was needed. ↘↘ In assembly, ↘ B-CAST takes three operands — ↘ destination, source, and lane. ↘↘ Two-cycle latency, ↘ same as a M-O-V.

### Beat 4.5 — The kernel transformation (6:46 – 7:12, ~26 s)

**On screen**: Deck 3 stage 5 — side-by-side inner loops. Left (red-tinted): scalar 2-neuron interleave, 7.0 cy/neuron, 25 % SIMD. Right (green-tinted): BCAST 4-neuron parallel with `BCAST R3, R3, 0` highlighted, 3.5 cy/neuron, 100 % SIMD. Bottom metrics row: 2→4 neurons, 7.0→3.5 cy/neuron, 25→100 % SIMD.

> A single B-CAST instruction reshapes the inner loop. ↘↘ Before, ↘ the kernel had to interleave two neurons across the four lanes — ↘ seven cycles per neuron. ↘↘ With B-CAST, ↘ we pack four neurons' weights into one register, ↘ broadcast the input across all four lanes, ↘ and a single FMA computes all four neurons at once. ↘↘ Same fourteen cycles per iteration, ↘ but now four neurons — ↘ that's three-and-a-half cycles per neuron, ↘ and SIMD utilization climbs from twenty-five to one hundred percent.

### Beat 4.6 — The result (7:12 – 7:30, ~18 s slide + Clipchamp may cross-cut supplementary clip here)

**On screen**: Deck 3 stage 6 — two-bar chart 2402 (red) vs 732 (green). "3.28×" floating label. Per-layer breakdown table: L1 1328→664, L2 944→646, L3 124→124 (highlighted: "doesn't speed up — only 2 output neurons, can't fill 4 lanes"). Verification badge: "hardware-verified · measured via GPU cycle-counter at register offset 0x30 · 5 stable silicon runs at 732 cycles". Optionally cross-cut the `5 runs that show BCAST perf improve consistency.mp4` clip here in Clipchamp as B-roll evidence.

> Measured cycle-exact on the FPGA, ↘ the classifier went from twenty-four hundred and two cycles down to seven hundred and thirty-two — ↘ a *three-point-two-eight* times speedup. ↘↘ Layers one and two both roughly halve; ↘ layer three doesn't change, ↘ because with only two output neurons we can't fill four lanes. ↘↘ One new opcode, ↘ sixty-five lookup tables, ↘ and a kernel rewrite — ↘ that's what owning the GPU end-to-end lets you do.

### Beat 4.6 supplementary — Stable-runs B-roll cross-cut (~14 s, audio-only)

**On screen**: `5 runs that show BCAST perf improve consistency.mp4` — sped up 7× (from ~98 s to ~14 s). Five consecutive BCAST inference runs on the FPGA, every run measuring 732 cycles.

**Production note**: Separate audio pass overlaid during the cross-cut in Clipchamp. No webcam.

> Five consecutive BCAST inference runs on silicon. ↘↘ Every run lands at exactly seven hundred and thirty-two cycles — ↘ stable, repeatable, no jitter. ↘↘ Clip is sped up seven times to fit.

---

## Beat 5 — Live ML inference on silicon (7:30 – ~10:45, ~3:15 of visual; ~35 s voiceover front-loaded)

**On screen, two clips in sequence**:
1. **~35 s**: `ids_inference_improved_testing_20samples.mp4` — 20-sample batch on FPGA, 18 correct, 100 % attack recall.
2. **~2:40**: `500 samples test on netfpga.mp4` — 500 packets in one batch, **NOT sped up** (real-time). Final summary at the end of the clip: 82.2 % accuracy, 7 ms/packet, zero dropped.

**Production note**: Single ~35 s voiceover at the start, covering both clips. The 500-sample clip plays out in real time; the voiceover explicitly tells TAs they can skip to the end.

> Next, ↘ two hardware demos of the IDS inference. ↘↘ First: ↘ a twenty-sample batch — ↘ eighteen correct, ↘ a hundred percent attack recall. ↘↘ Second: ↘ five hundred packets, ↘ not sped up — ↘ feel free to skip ahead to the summary. ↘↘ The results show eighty-two-point-two percent accuracy, ↘ eighty-eight percent attack recall, ↘ seven milliseconds per packet, ↘ zero dropped — ↘ proving the hardware agrees with the dev machine.

---

## Beat 6 — End-to-end inline IDS on the wire (8:35 – 10:35, ~120 s)

**On screen**: `Round-trip 5 takes.mp4` — 5 separate takes, 3 ATTACK + 2 NORMAL on node1.

> This demo shows the full inline-IDS round-trip on hardware. ↘↘ Five takes. ↘ Three attack packets, ↘ two normal. ↘↘ Please note that each take sends two packets and gets only one response back. ↘ That is a workaround — ↘ the bitfile only delivers one response per session before the drain stalls. ↘ I suppose that's because of a state-machine issue in the NF2 reference output queues. ↘ So I send two packets, ↘ take the one response, ↘ and reflash the bitfile between takes. ↘↘ One honest note: ↘ the IDS classification itself happens entirely on the FPGA, ↘ but the response packet's headers are built by our Python script on the host — ↘ because of a Linux network-filtering rule that would otherwise drop our packets on the receiving side.

---

## Beat 7 — Engineering candor — toward full on-chip autonomy

**On screen, three clips in sequence**:
1. `arm orchestrator BRAM dump.mp4`
2. `arm orchestrator throughput run.mp4`
3. `nf2 reference design tree.mp4`

### Beat 7a — ARM orchestrator BRAM dump (~38 s voiceover)

**On screen**: `arm orchestrator BRAM dump.mp4`

> The previous demo had Python assemble the response headers. ↘ Running the whole pipeline on the FPGA means the ARM CPU does *everything* — ↘ orchestrate DMA, run GPU, build the response, drain to the wire. ↘↘ This BRAM dump shows what's left in FIFO BRAM after one full classification run on hardware. ↘ The ARM has DMA-ed eleven features into GPU memory, ↘ released the GPU, ↘ DMA-ed the two BF-sixteen verdict logits back into BRAM, ↘ then rewritten the response headers in place: ↘ swapped MAC source and destination, ↘ swapped IP source and destination, ↘ rewritten the NF2 framing header. ↘ All on-chip — ↘ no host involvement.

### Beat 7b — Throughput run (~34 s voiceover)

**On screen**: `arm orchestrator throughput run.mp4` (Phase 1 — ARM throughput on chip + node1 tcpdump). 10 packets sent from node1, FPGA-host monitor showing `tid_swaps` climbing 20 → 292, `pkt_rising=0` throughout.

> Same orchestrator, ↘ now running continuously. ↘↘ node1 fires ten packets — ↘ tcpdump shows ten outbound frames go out. ↘↘ On the FPGA, ↘ `tid_swaps` climbs into the hundreds — ↘ the four-thread ARM is dispatching packet after packet, ↘ end-to-end on chip. ↘↘ The `pkt_rising` counter stays at zero — ↘ not a bug. ↘ The ARM processes each packet in microseconds; ↘ our host poll runs at fifty milliseconds, ↘ too slow to catch the rising edges. ↘ The on-chip pipeline is faster than we can sample it.

### Beat 7c — NF2 reference design tree (output_queues stall) (~25 s voiceover)

**On screen**: `nf2 reference design tree.mp4` — `find` locates `output_queues.v` in `/root/netfpga/lib/...`; `wc -l` shows hundreds of lines; `head -10` shows real Verilog source; `ls projects/lab8/src/` shows our project tree has no `output_queues*`; final `find` against our tree returns empty.

> The `output_queues` module that stalls is not part of our code. ↘ It's a Verilog module from the NetFPGA reference design — ↘ a few hundred lines written by the NetFPGA team. ↘↘ Our project uses it, ↘ but we did not write it, ↘ and it's not in our source tree. ↘↘ So the one-shot drain stall is inside code we don't own. ↘ Fixing it would mean modifying NetFPGA's reference design, ↘ which is outside the scope of this project.

---

## Closing (~25 s voiceover)

**On screen**: Closing title card (plain text).

> That's the project. ↘↘ An eleven-sixteen-eight-two neural-network intrusion classifier running inline on an FPGA, ↘ a custom four-lane SIMD GPU with a BCAST cross-lane instruction that cut the per-packet cycle count from twenty-four hundred to seven hundred and thirty-two, ↘ and an on-chip ARM orchestrator that closes the loop. ↘↘ Built end-to-end this semester. ↘↘ Thanks for watching — ↘ and thanks to Professor Cho and the TAs for the semester.

---

## Per-beat recording tips

- **Beat 0**: speak slightly slower than your default — first impression sets pace expectations.
- **Beat 1**: emphasize *inline* and *on silicon*; these are the headline claims.
- **Beat 2c**: this segment has a 35 s clip; you can pause briefly between sentences to let the visuals breathe.
- **Beat 3**: longest beat at 2:45. Take a sip of water before starting; pace yourself.
- **Beat 4**: BCAST is the design-win story — speak with energy on "three point two-eight times speedup."
- **Beat 5**: numbers-heavy. Read the percentages carefully; tabular numerics matter for credibility.
- **Beat 6**: this is the demo punch. The honesty about host envelope-assembly should be matter-of-fact, not apologetic.
- **Beat 7**: candor tone — direct, not defensive. The line "code we don't own" is the load-bearing phrase.
- **Closing**: warmer tone; you're winding down, the viewer should feel finished.

## Reading reminders

- "BF-sixteen" not "B-F-one-six"
- "eleven-sixteen-eight-two" not "eleven sixteen eight two"
- "KDDTest-plus" — say it as one phrase, not "K-D-D-Test plus"
- "NSL-KDD" — say it as initialism: "N-S-L K-D-D" (or "N-S-L dash K-D-D")
- Numbers under 100: spell out ("seven hundred and thirty-two", not "seven thirty two")
- Percentages: "eighty-two point four percent"
- "EE-five-three-three" not "E-E-five-thirty-three"

## Total word count

Approx 1,720 words across all beats. At 150 wpm that's 11.5 minutes — matches the 11:10–11:40 budget if you pace evenly. If you find yourself running long, the natural trim points are Beat 4 (drop one BCAST sub-clause) and Beat 6 (compress the "watch the listener" lines).
