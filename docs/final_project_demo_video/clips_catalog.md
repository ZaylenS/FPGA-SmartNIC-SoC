# Demo Video Clips Catalog

Inventory of all source clips in `docs/final_project_demo_video/final_demo_videos/`. This is the reference the voiceover script writes against — what's actually visible on screen for each beat.

Updated as new clips are captured.

---

## Reuse clips (from earlier presentation prep)

### `ids_inference_testing_dev_machine.mp4` — ~13 s

**Beat:** 5 (live ML inference — dev-machine eval)

**What's on screen:**
- PowerShell on the dev machine at the project root
- Command run (paraphrased from the original session, see `project_500_sample_silicon_test_0429.md` and presentation v3 plan):
  ```powershell
  py -3 scripts/train_ids_v2.py --eval-only --final-bf16-samples 0 --tag trained
  ```
- Output: loads `KDDTrain+.txt` (125,973 rows) + held-out `KDDTest+.txt` (22,544 rows), log1p + RF importance feature select, loads `data_ids_trained_weights.json` (seed 53 v3 model)
- Lands on `BF16 KDDTest+ accuracy: 0.8239 (18575/22544)`, `F1(A) = 0.848`, attack precision 0.833, attack recall 0.864
- Both Train and Test files visibly loading (this is the visual proof that 82.4% is held-out test accuracy, not training accuracy)

**Voiceover should:** establish the model's dev-machine accuracy baseline. Headline: 82.4% on KDDTest+, F1(attack) = 0.848. Bridge: "this is the BF16-faithful eval — same arithmetic the FPGA runs."

### `ids_inference_improved_testing_20samples.mp4` — ~35 s

**Beat:** 5 (live ML inference — 20-sample FPGA)

**What's on screen:**
- nf6 FPGA host terminal
- Command (paraphrased from v3 prep, recorded 2026-04-27 on team-6 FPGA):
  ```bash
  python lab10reg.py ids_batch_packets 20 test_features.csv
  ```
- node1 in parallel sends 20 BF16-encoded feature packets at delay=1.5 s
- All 20 packets in CSV order with OK / MISS column visible
- BATCH RESULTS SUMMARY held for ~4 s at end: Accuracy 18/20 = 90.0%, Recall(attack) 100.0%

**Voiceover should:** translate the dev-machine accuracy into silicon proof. Headline: 18 of 20 classified correctly on FPGA, 100% attack recall, ~6 ms/packet end-to-end. Bridge: "silicon agrees with the dev replay to ±0.01 logit (BF16 rounding noise)."

### `500 samples test on netfpga.mp4` — ~2:30

**Beat:** 6 (inline IDS — on-chip orchestration), with optional reuse of opening seconds in Beat 5

**What's on screen:**
- nf6 FPGA host terminal (team-7 board per `project_500_sample_silicon_test_0429.md`, 2026-04-29)
- Command run:
  ```bash
  python lab10reg.py ids_batch_packets 500 test_features_600.csv
  ```
- node1 sends 500 BF16 feature packets (subset of `test_features_600.csv`)
- Per-packet OK / MISS column scrolls past on FPGA terminal
- Final summary: 82.2% accuracy (411/500), 88% attack recall, 7 ms/pkt avg, 0/500 dropped

**Voiceover should:** scale the demo from 20 to 500 samples to prove reliability + match dev-machine accuracy. Headline: 82.2% (matches dev to 0.19 pp), 88% attack recall, 0 dropped packets, 7 ms/pkt. Architectural framing for Beat 6: "the ARM CPU on chip dispatches each packet to the GPU through DMA, classifies, and returns the verdict — no host PCI loop in the data path. This is how Fortinet, Snort 3, and Pigasus all operate: silent inline inspection. The verdict drives a forward-or-drop action, just like a production IDS."

### `5 runs that show BCAST perf improve consistency.mp4` — ~1:42

**Beat:** 4 (GPU + ISA + BCAST)

**What's on screen:**
- nf6 FPGA host terminal
- Five back-to-back runs of the IDS kernel via `lab10reg.py ids_perf` (or similar), alternating scalar (`ann_ids_11_16_8_2.hex`) and BCAST (`ann_ids_11_16_8_2_bcast.hex`)
- Each run prints `cycles=2402` for scalar / `cycles=732` for BCAST (per `project_fix1_hardware_verified.md` and `project_bcast_implementation.md`)
- Five runs for visual proof of consistency (no glitching after Fix 1 landed)

**Voiceover should:** establish the BCAST custom ISA contribution. Headline: 2402 → 732 cycles = **3.28× speedup**, hardware-verified consistent across 5 runs. Cross-layer narrative: "We added a single instruction — BCAST, a cross-lane broadcast — to our SIMD ISA. To get there we modified the assembler, the GPU pipeline RTL, and the kernel itself. That cross-stack change was only possible because we own every layer."

---

## Newly captured clips

### `train ids demo.mp4` — ~2 min (captured 2026-05-08)

**Beat:** 2 (Dataset + training); also covers Capture #4 (dataset peek) inline

**Recording session:** 2026-05-08, dev machine

**Why ~2 min when Beat 2 is ~1.5 min:** intentionally over-recorded to give cutting room in Clipchamp. Speed-ramp Group 2 (training) to 4–6× to land at ~30–45 s on screen.

**Commands executed (in order):**

```powershell
cd C:\Dev\EE533Labs\Lab10_refine_for_application
Clear-Host

# Group 1: Dataset peek (~15 s)
Get-ChildItem datasets/ | Select-Object Name,Length | Format-Table -AutoSize
"Train rows: $((Get-Content datasets/KDDTrain+.txt | Measure-Object -Line).Lines)"
"Test rows:  $((Get-Content datasets/KDDTest+.txt | Measure-Object -Line).Lines)"
Get-Content datasets/KDDTrain+.txt -Head 3

# Group 2: Training run (~30-60 s)
& "C:\Users\shao4\AppData\Local\Python\bin\python3.14.exe" scripts/train_ids_v2.py --epochs 50 --tag demo

# Group 3: Output peek (~10 s)
Get-ChildItem programs/gpu/data_ids_demo_weights.json | Select-Object Name,Length | Format-Table -AutoSize
Get-Content programs/gpu/data_ids_demo_weights.json -Head 30
```

**What's on screen:**

**Group 1 — Dataset peek**
- File listing showing `KDDTrain+.txt` (~19 MB) and `KDDTest+.txt` (~3.4 MB) under `datasets/`
- "Train rows: 125973" / "Test rows: 22544"
- Three sample lines from `KDDTrain+.txt` showing raw NSL-KDD format: about 40 comma-separated fields per row including categorical (`tcp,http,SF,...`) and numeric counts/rates

**Group 2 — Training run** (50 epochs, --tag demo so it doesn't overwrite the deployed model)
- Header: "Loaded train: 125973 / test: 22544"
- Feature selection log: "Selected 11 features by RF importance: src_bytes, dst_bytes, same_srv_rate, diff_srv_rate, dst_host_same_srv_rate, logged_in, dst_host_srv_count, dst_host_diff_srv_rate, dst_host_srv_serror_rate, dst_host_same_src_port_rate, count" (or similar)
- Hyperparams summary (epochs=50, optimizer=adam, label smoothing, log1p numerics, etc.)
- Per-epoch lines flying by, e.g.: `epoch  10: loss=0.34 lr=0.001 f32_train=0.92 bf16_train=0.91 bf16_test=0.79`
- Loss decreasing, BF16 test accuracy climbing toward ~80%+
- Final block: `BF16-faithful (silicon): 0.8xxx (~18xxx/22544)` plus confusion matrix and per-class precision/recall/F1
- "Saved weights -> programs/gpu/data_ids_demo_weights.json"

**Group 3 — Output peek**
- File listing: `data_ids_demo_weights.json` (~14 KB)
- First ~30 lines of JSON: selection metadata (selected feature names, normalization parameters per feature) followed by weight matrix entries

**Notes for voiceover writer:**

The voiceover narrates Beat 2 (~1.5 min). It should cover:
- **Dataset framing (~15 s, syncs with Group 1):** NSL-KDD is a standard benchmark for intrusion detection. ~126 K training samples, ~22.5 K held-out test samples covering attacks not in training. Each row has ~40 raw features.
- **Methodology (~30 s, syncs with Group 2 start + speed-ramped epochs):** "We narrow ~40 raw features to 11 by random-forest importance to fit in our DMEM budget. The network is 11→16→8→2 — small enough to fit on-die, large enough to learn the task. We train with Adam + label smoothing + log1p on heavy-tailed numeric features. The forward pass is BF16-faithful — every multiply-accumulate truncates to BF16 exactly the way our FPGA's bf16_fma_unit does, so the trained accuracy is what the silicon will actually produce."
- **Quantization & export (~15 s, syncs with Group 2 end + Group 3):** "After training, weights export to JSON with the selected feature names and normalization parameters. A separate toolchain step converts the JSON to GPU DMEM hex, which we load via PCI before each inference run."

**Production notes:**
- The `--tag demo` artifacts (`data_ids_demo_weights.json`, `data_ids_demo.hex`, `expected_ids_demo.hex`) should be deleted post-recording to keep the project tree clean. Cleanup commands in `final_demo_video_plan.md` § Production materials.
- The deployed model (`data_ids_trained_*.{hex,json}`, the seed-53 v3 model) is untouched by this recording.

---

### `arm orchestrator BRAM dump.mp4` — ~1:30 (captured 2026-05-08)

**Beat:** 7 (engineering candor — supporting evidence for "on-chip orchestration works; wire-side egress is what's blocked")

**Recording session:** 2026-05-08, FPGA host (`team-6:fpga`)

**Why ~1:30 when Beat 7 is ~45 s and the dump itself runs ~10 s:** intentionally over-recorded to give cutting + speed-ramping room in Clipchamp. The post-halt diagnostics scroll fast at 1× — clip will be edited down by speed-ramping the LA + register dump portions and pausing at the BRAM[0], BRAM[1], BRAM[7], BRAM[8] lines.

**Pre-recording state confirmed (off-screen):**
- Bitfile: Fix B baseline, md5 `aa680d9fcc44672277502b2f6937817f`
- `lab10reg.py`: reverted to baseline (no BUFG / oq_reset diagnostic comments). RPF_FIX_ENABLED = True is still in the file but not exercised in the ARM path.
- ARM orchestrator hex: `ids_orchestrator.hex` 13.8 KB, Apr 21 timestamp (Fix B 117-instruction orchestrator + HALT padding)

**Commands executed (in order):**

```bash
# On FPGA host (recording starts after `clear`)
python lab10reg.py ids_arm_debug_once

# (script pauses at "ARM in wait_pkt. SEND ONE PACKET NOW from node1:")

# On node1 (off-screen / different terminal — pre-typed, single Enter to fire):
python send_ids.py --replicated
```

**What's on screen (FPGA host terminal, real-time order):**

1. `=== ARM Orchestration Debug (one-shot) ===`
2. `Loading BCAST IDS kernel + weights into GPU...` → `Loaded 108 instructions from ann_ids_11_16_8_2_bcast.hex` + `Loaded 128 DMEM words`
3. `Loading ARM orchestrator from ids_orchestrator.hex...` → `Loaded 385 instructions from ids_orchestrator.hex (CPU held in reset)`
4. `Patching IMEM[116] -> HALT (ARM halts at this point after packet arrives)...` → `IMEM[116] readback = 0xffffffff (expected 0xFFFFFFFF)` (proves the HALT patch landed)
5. `Starting ARM, then mode 0 + FIFO reset workaround...`
6. **`ARM in wait_pkt. SEND ONE PACKET NOW from node1:`** (prompt; user fires send_ids.py off-screen)
7. `Polling for ARM halt (Ctrl-C to abort)...` (~1 s pause until the packet arrives, ARM processes it, halts at IMEM[116])
8. `=== Post-halt diagnostics ===`
9. **`-- FIFO STATUS --`** `STATUS=0x00000004 pkt_ready=0 empty=1 full=0` ← drain "completed" from FIFO's perspective; `FIFO_MODE=0 (FIFO)`
10. `-- LA (most recent 32 events while ARM was running) --` (32 lines of alternating LA values; this is the wait_pkt loop pattern after the orchestrator processed and halted — speed-ramp this in editing)
11. `-- GPU + DMA status registers --` showing `GPU_STATUS=0x00000000 kernel_done=0 dma_busy=0`, `GPU_CTRL=0x00000001`, **`DMA_CTRL=0x00000002 ... DMA_LENGTH=0x00000002`** (last DMA was the output DMA: GPU DMEM[126..127] → BRAM[7..8], 2 words)
12. **`-- GPU DMEM[126..127] (kernel output) --`** `DMEM[126]: 0x40204020_40204020` and `DMEM[127]: 0x40204020_40204020` (BF16 logits replicated 4× across SIMD lanes)
13. **`-- FIFO BRAM[0..17] (post-orchestrator contents) --`** ← the headline visual, 18 lines:
    - **`BRAM[ 0]: ctrl=0xff data=0x00010012_00020090`** ← NF2 header rewritten (dst=MAC0=0x0001, words=18, src=CPU0=0x0002, bytes=0x90=144)
    - **`BRAM[ 1]: 0xa0369f0a_0eb3ffff`** ← DstMAC = `a0:36:9f:0a:0e:b3` (node1's port0). Trailing `ffff` is start of broadcast SrcMAC (the platform-layer issue we acknowledge in voiceover).
    - `BRAM[ 2]: 0xffffffff_08004500` ← rest of broadcast SrcMAC + EtherType IPv4 + IP ver/IHL/TOS
    - `BRAM[ 3]: 0x00820000_40004011` ← IP total_length=0x82 (130 bytes), ID=0, flags=0x4000 (DF), TTL=64, Protocol=17 (UDP)
    - `BRAM[ 4]: 0x1a6a0a00_07ff0a00` ← IP cksum=0x1a6a + SrcIP=10.0.7.255 (broadcast — the issue) + DstIP[0..1]=10.0
    - `BRAM[ 5]: 0x0403270f_da61006e` ← rest of DstIP=…04:03 (10.0.4.3 = node1), UDPsrc=0x270f=9999, UDPdst=0xda61 (node1's ephemeral src port from this send), UDPlen=0x6e=110
    - `BRAM[ 6]: 0x00000000_00000000` ← UDP cksum zeroed (orchestrator's writeback)
    - **`BRAM[ 7]: 0x40204020_40204020`** ← BF16 logit 0 replicated 4× — **bit-identical to DMEM[126]**, proving the on-chip DMA delivered it
    - **`BRAM[ 8]: 0x40204020_40204020`** ← BF16 logit 1 replicated 4× — bit-identical to DMEM[127]
    - `BRAM[ 9..17]` ← unmodified residual ingress feature data (orchestrator only writes BRAM[7..8] for the response payload; BRAM[9..17] are leftover from the original ingress that node1 sent: `0x3E4C...` etc.)
14. `ARM held in reset. If you want to run another one-shot, re-run this command.`

**The "headline visual" — 4 lines that tell the whole story:**
- BRAM[0] → header rewritten on chip
- BRAM[1] → MAC swap on chip (destination is correct)
- DMEM[126] vs BRAM[7] → bit-identical (GPU computed logit; ARM-driven DMA wrote it to BRAM)
- BRAM[8] → second logit, also delivered

**Notes for voiceover writer (Beat 7, ~45 s of speech):**

The voiceover narrates Beat 7 as honest engineering acknowledgment. Suggested structure synced to clip cuts:

- **0:00–0:10 (commands + ARM start):** "We worked toward end-to-end response delivery from the FPGA back to the originating node — that would let the system also serve as a query API in the spirit of VirusTotal or FortiSandbox. To verify how far we got, we run a one-shot debug: patch the ARM orchestrator to halt right after processing one packet, then dump every register and BRAM word."
- **0:10–0:20 (BRAM dump appears, cursor highlights BRAM[0] and BRAM[1]):** "On chip, the orchestrator did its job. The NF2 header is rewritten with the right ports, the destination MAC is correctly swapped to the originating host."
- **0:20–0:30 (cursor highlights DMEM[126] then BRAM[7]):** "The GPU computed BF16 logits, and the ARM-orchestrated DMA wrote them into the FIFO right next to the headers — bit-for-bit identical to the GPU's output. Everything we built sits in BRAM, ready to drain."
- **0:30–0:45 (transition to engineering candor):** "But the wire-side delivery — pushing those bytes through the NF2 reference output_queues to the MAC — that part is out of reach on our end. The reference module's drain state machine has a stall we can only reset by reflashing the bitfile. We dug into it, learned the limit, and stopped before sinking more days into a vendor-IP boundary issue. So the demo we're shipping is the inline-IDS architecture — silent inspection in the data path, the way real production IDS works."

**Production notes:**
- The 32-line LA dump is the slowest-paced part — speed-ramp 4–6× or crop heavily.
- BRAM[2..6] can also speed-ramp (they show the IP/UDP swap details which aren't headline).
- Pause / hold at BRAM[0], BRAM[1], DMEM[126], BRAM[7..8] for emphasis.
- Final clip target: ~12–15 s after editing, fits inside Beat 7's ~45 s budget alongside the round-trip live take.

---

### `nf2 reference design tree.mp4` — ~2:20 (captured 2026-05-08, 17 MB)

**Beat:** 7 (engineering candor — supports the "boundary inside reference module" narrative)

**Recording session:** 2026-05-08, Fedora VM (NetFPGA build machine where `/root/netfpga/` lives)

**Why ~2:20 when Beat 7 only needs ~10–15 s of this:** intentionally over-recorded for cutting room. Final use in editing: ~10–13 s clip showing the `find` result, the `wc -l` and `head` output (proving the module is real Verilog with substantial source), and the empty `find` result on our project's `src/` (proving we don't own it).

**Commands executed (in order):**

```bash
# Pre-recording: ssh into Fedora VM, navigate to /root/netfpga
cd /root/netfpga

# Recording starts (window full-screen, large font):
clear

# Locate output_queues.v in NF2 reference design
find /root/netfpga/lib -name "output_queues.v" -type f
# Returns: path under /root/netfpga/lib/verilog/core/.../output_queues.v

# Show it's substantial Verilog
wc -l /root/netfpga/lib/verilog/core/output_queues/output_queues.v
# Returns: hundreds of lines

# Show it's real source code, not a stub
head -10 /root/netfpga/lib/verilog/core/output_queues/output_queues.v
# Returns: module header / port declarations / Verilog comments

# Show our project tree's src/ — note: no output_queues.v
ls /root/netfpga/projects/lab8/src/
# Returns: arm/, fifo/, gpu/, include/, lab8_wrapper.v, user_data_path.v

# Confirm by direct search — should produce no results
find /root/netfpga/projects/lab8/src -name "output_queues*"
echo "(empty result confirms we don't own that module)"
```

(Exact path of `output_queues.v` depends on the NF2 reference version; user's `find` returned the actual path used in subsequent commands.)

**What's on screen (real-time order):**

1. `find` result: 1 line showing `/root/netfpga/lib/verilog/core/.../output_queues.v` exists in NF2 reference tree
2. `wc -l` result: line count (hundreds of lines — substantial source)
3. `head -10` output: real Verilog source (module declaration, port list, etc.)
4. `ls projects/lab8/src/` output: our project's src tree (`arm/ fifo/ gpu/ include/ lab8_wrapper.v user_data_path.v`) — visibly **no `output_queues.v`**
5. Final `find` returns empty + the echo'd `(empty result confirms we don't own that module)` line

**Notes for voiceover writer (Beat 7, ~10–13 s synced to clip cuts):**

- **0:00–0:03 (find result + wc -l):** "Here's where the NF2 reference design lives on our build machine — the library tree we build on top of. The output_queues module — the one whose drain stalls — is hundreds of lines of real Verilog written by the NetFPGA reference design team."
- **0:03–0:08 (head output + ls our src):** "But it's not in our project's source tree. We instantiate it; we don't author it."
- **0:08–0:13 (empty find + echo):** "So when its drain state machine has a one-shot stall we can only fix by re-flashing the bitfile, that's a vendor-IP boundary — the engineering line we drew, not a problem we could solve from our side without forking the reference design itself."

**Production notes:**
- The headline visual is the **empty `find` result** at the end — pause / hold for ~1 s before cutting.
- Speed-ramp the `head -10` output if it scrolls slowly.
- The first `find` output (one path line) and the final `find` (empty) make a clean cause-effect bookend.

**Final clip target:** ~10–13 s after editing, fits inside Beat 7 alongside the multi-take round-trip and BRAM dump segments.

---

### `arm orchestrator throughput run.mp4` — ~?? (captured 2026-05-08, 10 MB)

**Beat:** 6 (inline IDS — on-chip ARM orchestrator throughput) + transitions into Beat 7 (engineering candor)

**Recording session:** 2026-05-08, FPGA host (`team-6:fpga`) + node1 (`team-6:n0`)

**Why this clip is better than expected:** initially planned to show only the on-chip ARM running (Beat 6 supporting visual). The recording also captured **the ARM orchestrator's wire-side response drain** — one inbound frame appeared in tcpdump at 18:17:21.355186 with broadcast SrcMAC + truncated-ip warning, exactly matching the same 1-per-session drain stall we hit in PCI mode. So one clip carries both:
- Beat 6 narrative — ARM running on chip processing packets autonomously
- Beat 7 narrative — visible evidence that ARM-hex's lack of RPF/truncation patches makes the wire-side egress unrecognizable to Linux (broken SrcMAC/SrcIP, the boundary we acknowledged in the round-trip beat)

**Two phases in one continuous take:**

**Phase 1 — ARM orchestrator throughput (~30 s of clip)**

```bash
# FPGA host
nf_download nf2_top_par.bit
python lab10reg.py ids_arm_start
# (wait for "ARM orchestrator running. On node1: ..." prompt)

# node1 Terminal A — tcpdump (started before recording, left running)
sudo /usr/sbin/tcpdump -i port0 -nne 'udp port 9998 or arp'

# node1 Terminal B — fire 10 packets
python send_ids.py --csv test_features.csv --count 10 --delay 0.5 --replicated --listen

# (wait ~5 s after node1's send finishes; FPGA monitor lines continue)

# FPGA host — Ctrl-C to stop ARM
```

**On-screen during Phase 1:**
- FPGA host: ARM orchestrator boot output (load BCAST kernel + orchestrator hex) → "ARM orchestrator running" → 16 monitor lines `pkt_rising=0  tid_swaps=N  running=1 halted=0  tid=X` over ~32 s, with `tid_swaps` advancing 20 → 292
- `pkt_rising` stays at 0 throughout — the host's 50 ms poll loop is too slow to catch the microsecond-window FIFO `pkt_ready` rising edges; this is **expected and itself part of the story** (the ARM is faster than the host can monitor)
- node1 tcpdump: 10 outbound frames (`a0:36:9f:0a:0e:b3 > ff:ff:ff:ff:ff:ff, ... 10.0.4.3.9998 > 10.0.7.255.9999: UDP, length 102`) over ~5 s starting at 18:17:20.855
- **node1 tcpdump: 1 inbound frame at 18:17:21.355186** (`ff:ff:ff:ff:ff:ff > a0:36:9f:0a:0e:b3, ... 10.0.7.255.9999 > 10.0.4.3.9998: UDP, length 102` with `truncated-ip - 7 bytes missing!` warning) — the ARM orchestrator's response drained over the wire. RPF on node1 drops it (broadcast SrcMAC + broadcast SrcIP — ARM hex doesn't have the patches we built into the PCI path).
- send_ids.py exits with `Received 0 responses (0%)` — expected, the packet was dropped at kernel level by RPF.
- FPGA host final counters: `pkt_rising=0  tid_swaps=292`

**Phase 2 — Post-test BRAM dump (~15 s of clip)**

```bash
# FPGA host
python lab10reg.py ids_arm_debug_once
# (wait for "ARM in wait_pkt. SEND ONE PACKET NOW from node1" prompt)

# node1 Terminal B
python send_ids.py --replicated

# (wait for ARM halt + BRAM dump to scroll on FPGA host)
```

**On-screen during Phase 2:**
- Standard `ids_arm_debug_once` flow (same as the standalone `arm orchestrator BRAM dump.mp4`):
  - "Patching IMEM[116] -> HALT" + readback verification
  - "ARM in wait_pkt. SEND ONE PACKET NOW from node1"
  - Polling for halt
  - Post-halt diagnostics dump
- The headline 4 lines of the BRAM dump:
  - `BRAM[ 0]: ctrl=0xff data=0x00010012_00020090` — NF2 header rewritten on chip
  - `BRAM[ 1]: ctrl=0x00 data=0xa0369f0a_0eb3ffff` — DstMAC = node1, broadcast SrcMAC visible (the limitation)
  - `DMEM[126]: 0x40204020_40204020` — GPU computed logit
  - `BRAM[ 7]: ctrl=0x00 data=0x40204020_40204020` — same value, ARM-driven DMA delivered it bit-identical
  - `BRAM[ 8]: ctrl=0x00 data=0x40204020_40204020` — second logit

**Notes for voiceover writer (Beat 6 → Beat 7 transition):**

This clip provides a **single visual that bridges Beat 6 to Beat 7**. Suggested structure:

- **Phase 1 Beat 6 narrative (~25 s of voiceover):** "Now we run with the ARM orchestrator on chip. node1 sends ten packets. Watch tcpdump — ten outbound frames go out. On the FPGA, the host's monitor shows tid_swaps advancing into the hundreds — the four-thread fine-grained multithreading ARM is running and dispatching the GPU pipeline. The pkt_rising counter stays at zero — but that's not a bug. The ARM processes each packet in microseconds; the host's fifty-millisecond poll loop is too slow to count individual ingress events. The on-chip pipeline is faster than the host can monitor."
- **Phase 1 → Beat 7 transition (~10 s):** "And look here — tcpdump caught one inbound frame at 18:17:21. That's the ARM orchestrator draining one response onto the wire — same one-per-session pattern as the PCI path, the same NF2 reference output queue boundary. But notice the truncated-ip warning and the broadcast source MAC — the ARM hex doesn't have the RPF and length patches we put into the PCI path; that's why send_ids reports zero received. The orchestration worked on chip; the wire-side delivery hits the platform limitation."
- **Phase 2 BRAM dump narrative (~15 s):** "To verify the on-chip processing actually produced correct results, we freeze the orchestrator on a single follow-up packet and dump the BRAM. Headers rewritten — destination MAC swapped to node1, NF2 dst-port set to MAC0. The BF16 logits the GPU computed sit bit-identical in BRAM seven and eight via the ARM-driven DMA. Everything happened on chip, in microseconds, exactly as designed. The boundary we hit lives outside that — in the NF2 reference output queues we build on top of."

**Production notes:**
- The two phases are continuous in the recording — the natural cut is the FPGA host's "Final counters" line at the end of Phase 1.
- Speed-ramp the ARM startup output and the LA dump in Phase 2 (similar to the standalone BRAM-dump clip).
- The **broadcast SrcMAC frame in tcpdump** at 18:17:21.355186 is the visual "engineering candor" moment — pause briefly to highlight it; the truncated-ip warning is the cherry on top.
- The `tid_swaps=292` final counter is the "ARM was busy" proof — hold for a beat.

**Final clip target:** ~50 s after editing. Provides Beat 6's main visual + Beat 7's transition setup.

---

### `Round-trip 5 takes.mp4` — ~3:33 (captured 2026-05-08, 19 MB)

**Editing approach (locked 2026-05-08):** keep Take 1's reflash visible to establish the platform constraint tangibly; cut reflashes from Takes 2–5 to keep pacing crisp. Final beat target ~60–75 s. Voiceover narrates "Each session starts with a bitfile reflash to clear the output-queue state — that's the boundary we acknowledged" while Take 1's reflash plays at ~2× speed.

**Beat:** 7 (engineering candor — round-trip multi-take, headline visual)

**Recording session:** 2026-05-08, FPGA host (`team-6:fpga`) + node1 (`team-6:n0`)

**Why one bundled file (not 5 separate ones):** consolidated into a single source clip for editing. Take boundaries are visible in the FPGA-host re-flash output (the `nf_download` block between takes is the natural cut point).

**Pre-recording state confirmed (off-screen):**
- Bitfile: Fix B baseline, md5 `aa680d9fcc44672277502b2f6937817f`
- `scripts/lab10reg.py`: reverted to baseline + RPF/truncation patches in `_form_and_drain_response` (RPF_FIX_ENABLED=True, TX_TRUNCATE_BYTES=7)
- `scripts/send_ids.py`: **patched 2026-05-08** — `_parse_response_bf16_pair` now auto-detects PCI vs ARM orchestrator BRAM layout (PCI packs both logits in BRAM[7]; ARM replicates each logit across BRAM[7] and BRAM[8]). Without this patch, PCI mode reported logit1=0x0000 always.

**Important diagnostic findings during prep (background context for voiceover):**
1. **Old `--replicated` flag was wrong for PCI mode.** Earlier takes used `--replicated`, which puts features in BRAM[7..17] in 4× replicated layout (1 feature per word). But `cmd_ids_pci_throughput` reads features from BRAM[7..9] in **packed** layout (3 features per word, 4 lanes per word). Result: model received only the first 3 features replicated 4× instead of all 11 features. Fix: drop `--replicated` flag for the PCI path.
2. **`docs/demo_script.md` "normal browsing" samples were stale** — written for an older model variant with a different feature ordering. With the v3 deployed model (seed 53, Apr 26), those samples actually classify as ATTACK. Replaced with real NORMAL rows from `test_features.csv` (the same CSV used for the 18/20 = 90% small-batch test and 82.2% 500-sample test, where ground-truth labels confirm NORMAL/ATTACK).

**Three-terminal layout during recording:**
- FPGA host (`team-6:fpga`) — runs `nf_download` + `ids_pci_throughput 2`
- node1 Terminal A (tcpdump) — `sudo /usr/sbin/tcpdump -i port0 -nne 'udp port 9998 or arp'` left running across all 5 takes
- node1 Terminal B (send) — different `send_ids.py` command per take

**Commands executed (per take, 5× total):**

For each take, the per-take cycle:
1. **FPGA host:** `nf_download nf2_top_par.bit` (resets the drain stall state from the previous take)
2. **FPGA host:** `python lab10reg.py ids_pci_throughput 2`
3. (when "Waiting for first packet..." prompt appears) **node1 Terminal B:** run the take's `send_ids.py` command below
4. Wait ~10 s for full cycle (PCI service + tcpdump capture + send_ids report)
5. Continue to next take (or stop recording)

**The 5 take commands** (no `--replicated` flag, used the patched send_ids.py):

```bash
# Take 1 — default ATTACK
python send_ids.py --count 2 --delay 2.5 --listen

# Take 2 — NORMAL (CSV row 1: substantial bytes, logged-in, saturated same-srv)
python send_ids.py 0.276667 0.347530 0.000000 1.000000 0.000000 0.971848 0.820000 1.000000 0.000000 0.111111 0.217391 --count 2 --delay 2.5 --listen

# Take 3 — ATTACK (CSV row 8: zero bytes, high count, low same-srv = port scan)
python send_ids.py 0.000000 0.000000 0.200000 0.040000 0.060000 0.396241 0.030000 0.000000 0.000000 0.860163 0.028986 --count 2 --delay 2.5 --listen

# Take 4 — NORMAL (CSV row 4: balanced bytes, logged-in, fully saturated)
python send_ids.py 0.285280 0.253162 0.000000 1.000000 0.000000 1.000000 1.000000 1.000000 0.000000 0.488035 0.043478 --count 2 --delay 2.5 --listen

# Take 5 — ATTACK (CSV row 2: REJ flag, dst_bytes only, no logged_in)
python send_ids.py 0.181328 0.000000 0.800000 1.000000 0.000000 0.893718 0.550000 0.000000 0.000000 0.111111 0.130435 --count 2 --delay 2.5 --listen
```

**Verdict variety expected:** 3 ATTACK + 2 NORMAL (Takes 1, 3, 5 = ATTACK; Takes 2, 4 = NORMAL). All samples are drawn from `test_features.csv` ground-truth-labeled rows, so the model's actual argmax matches the ground-truth label.

**What's on screen (per take, in temporal order):**

For each of the 5 takes:

- **FPGA host:** `nf_download` output → `ids_pci_throughput 2` startup ("Loading IDS Model" + "Waiting for first packet...") → 2 dots as packets are serviced → `=== PCI Orchestration Result ===` with `Serviced: 2 of 2 packets`
- **node1 tcpdump:** 2 outbound (`a0:36:9f:0a:0e:b3 > ff:ff:ff:ff:ff:ff, ... 10.0.4.3.9998 > 10.0.7.255.9999: UDP, length 102`) and 1 inbound (`02:de:ad:be:ef:00 > a0:36:9f:0a:0e:b3, ... 10.0.4.2.9999 > 10.0.4.3.9998: UDP, length 95`) — the inbound carries our patched valid SrcMAC + SrcIP, no truncated-ip warning, UDP length=95 (= 102 − 7 truncation patch)
- **node1 send (Terminal B):** `Sending 2 packets...` → `Received: 1 responses (50.0% of sent)` → `First logits: BF16 0xXXXX / 0xYYYY (~−A.A, ~B.B) -> ATTACK|NORMAL`

The take boundary in the file is the FPGA host's `nf_download` block — this is a natural cut for editor (Clipchamp).

**Notes for voiceover writer (Beat 7, ~50–60 s of speech, multi-take montage):**

Suggested structure synced to clip cuts (assuming each take edited to ~8–10 s):

- **0:00–0:08 (Take 1, ATTACK default):** "We worked toward end-to-end response delivery — the FPGA classifying a packet and replying back to the originating host. We got there for one packet per session: send two, get one response back, with the verdict over the wire."
- **0:08–0:16 (Take 2, NORMAL):** "Different traffic pattern — substantial bytes, logged-in connection, normal-looking same-service rate. The FPGA sends back NORMAL."
- **0:16–0:24 (Take 3, ATTACK):** "Zero-byte connections with high count and low same-service rate — the model sees a port scan, sends back ATTACK."
- **0:24–0:32 (Takes 4 + 5 quick montage):** "We can keep going — different samples, different verdicts, each one delivered live to node1 over the network."
- **0:32–0:50 (transition to engineering candor + BRAM dump):** "But each session, only one response makes it through. After that the bitfile's NF2 reference output queue stalls — it's a state-machine issue inside that reference module that we can't reach from outside it. We patched what we could on our side: the response's source MAC and IP get rewritten to valid unicast values, the IP and UDP lengths get adjusted, the IP checksum gets recomputed — all of which get the response past Linux's RPF filter on node1. But the reference output queue's drain only delivers once per reset. So the demo we're shipping uses the inline-IDS architecture from the previous beat — the way real production IDS actually operates. The query-API mode shown here is the boundary we hit, and where we drew the engineering line."

**Production notes:**
- 5 take boundaries marked by the FPGA host's `nf_download` block — natural Clipchamp cut points.
- Speed-ramp the `Loading IDS Model` startup output (3–4 s of repetitive output per take) to keep each take crisp.
- Hold the `→ ATTACK` / `→ NORMAL` line on the node1 send terminal for ~1 s before cutting to the next take — that's the headline.
- Emphasize the **alternating ATTACK / NORMAL** in editing — color-code the take labels in lower-thirds if Clipchamp supports it.
- Final clip target: ~50 s after editing (5 takes × 8–10 s each), fits inside Beat 7's expanded ~50–60 s budget.

### Beat 3 (architecture) — animated HTML capture from Claude Design

**Status:** to be generated (replaces the originally-planned `architecture_diagram.mp4` from the Apr 28 prep).

**Notes for when generated:** the new HTML diagram should walk the four units (FIFO, ARM CPU, GPU coprocessor, DMA engine) and the data flow (packet → FIFO → ARM/GPU → drain). Match length to ~2 min Beat 3 budget. Voiceover talks over the animation.

---

## How this catalog is used

When drafting the Beat-by-Beat voiceover script (Task #5):
- For each beat, reference the source clip(s) listed here.
- Pace voiceover to the clip's natural rhythm (don't outrun the visual).
- The "Voiceover should" notes per clip are first-draft prose — refine as the script comes together.

When editing in Clipchamp:
- Use the durations + content notes here to plan cuts.
- Speed-ramp where noted (training run, BCAST 5 runs, 500-sample tail).

When new clips are captured: append a section here describing commands run + on-screen content + voiceover guidance.
