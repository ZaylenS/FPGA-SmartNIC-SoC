# Final Project — Part 3 (Expert Demo) Plan: Live DDoS Detection

**Target**: Record the "for experts" segment of the 3-part final project video (per Prof Cho's exemplar from 2026-04-09 lecture). Show an end-to-end live demonstration where attack traffic is generated from nf7, features are extracted in real time, classified on the NetFPGA, and visualized.

**Deadline context (updated 2026-04-17)**:
- **2026-04-28 / 2026-04-30** — *progress* presentation lecture. Part 3 is NOT required as a completed demo; an optional teaser is acceptable (see `../final_project_progress_present/part3_expert.md` for the progress-lecture handling).
- **2026-05-13** — **final project demo video** due. This is the hard deadline for Part 3 / the live-DDoS demo described in this plan.

**Engineer**: Zilin Shao, solo.

**Companion folders**:
- `../final_project_progress_present/` — Apr 28/30 progress-lecture materials (Parts 1 grandma + 2 investor; Part 3 treated as teaser at best).
- This folder (`docs/final_project_demo_video/`) — everything for the May 13 deliverable.

---

## 1. Demo Narrative

### What the viewer sees (~90 seconds on-screen, plus ~2 minutes voiceover)

1. **Split screen**: left = nf7 (attacker) terminal running an attack generator; right = nf6 (defender) terminal running the FPGA classifier with a live visualizer.
2. **Baseline**: ~30 seconds of normal traffic (e.g., `curl` or `ping` from nf7 to nf6). The live visualizer shows green bars / all-NORMAL classifications. Confusion matrix widget shows high normal accuracy.
3. **Attack begins**: attacker launches a SYN flood via `hping3` or `scapy`. Within one 2-second feature window, the visualizer flips to red ATTACK bars. Classification confidence is shown numerically (attack logit climbs from negative to large positive).
4. **Attack variant**: attacker switches to UDP flood. Visualizer still flags ATTACK. Optional: ICMP flood, mixed attack.
5. **Recovery**: attacker stops. Within one to two windows the visualizer returns to NORMAL.
6. **Voiceover wrap**: explain the detection pipeline — live packet capture → sliding-window feature extraction → UDP to FPGA → BCAST-optimized GPU kernel → classification → visualizer. Explicit honest framing: "In production, the classification result would drive an in-FPGA packet-drop action. This demo focuses on the detection stage, which is the hard ML part; the filter action is the kind of MAC-layer packet mux we already demonstrated working in Lab 8."

### What this demonstrates for experts

- **ML inference on custom hardware**: the 11-16-8-2 MLP runs on our own 4-lane SIMD GPU coprocessor with a custom ISA extended by the BCAST instruction we added in milestone 2.
- **Real traffic, not simulated**: features come from actual packets, not pre-canned CSVs.
- **Honest architecture framing**: detection vs filtering separation is professional, not hand-waved.
- **Full stack ownership**: packet generation, feature extraction, classification kernel, hardware instrumentation, all written by us.
- **(If Track A from §2.5 succeeds) On-chip orchestration**: ARM CPU dispatches packets to the GPU and drains results entirely in FPGA silicon — no host intervention during the live demo. Converts the story from "host orchestrates CPU + GPU" to "complete SoC handles the whole pipeline." This is the headline upgrade targeted for the May 13 cut.
- **(If Track A is dropped)** The voiceover reverts to a Lab-8-accurate framing: "ARM CPU sits in the convertible FIFO path for control-plane work; GPU is the data-plane classifier; Python orchestrates them from the host." Defensible but weaker.

---

## 2. Technical Feasibility (from research)

Research agent verified this plan against three authoritative sources: the UCI KDD Cup 1999 task description, the Tavallaee et al. 2009 NSL-KDD paper (IEEE CISDA), and the AI-IDS/kdd99_feature_extractor open-source reference implementation. Findings:

### 2.1 The 11 trained features — extractability

The trained model (from `programs/gpu/data_ids_trained_weights.json`) uses exactly these 11 NSL-KDD features, selected by random forest importance:

| # | Feature | KDD category | Window | Live extractability |
|---|---------|-------------|--------|---------------------|
| 1 | `src_bytes` | basic | per-connection | **EASY** — sum TCP/UDP payload per 5-tuple flow |
| 2 | `dst_bytes` | basic | per-connection | **EASY** — same, reverse direction |
| 3 | `same_srv_rate` | time-traffic | 2-sec | **MEDIUM** — ratio over 2-sec deque of connections with same service |
| 4 | `diff_srv_rate` | time-traffic | 2-sec | **MEDIUM** — 1 − same_srv_rate approximately |
| 5 | `dst_host_same_srv_rate` | host-traffic | 100-conn | **HARD** — per-dst-host ring buffer of last 100 connections, count matching service |
| 6 | `logged_in` | content | per-connection | **VERY HARD** — needs app-layer auth inspection. **Decision: hardcode to 0** for the live pipeline (matches both DDoS and synthetic-normal traffic correctly). |
| 7 | `dst_host_srv_count` | host-traffic | 100-conn | **HARD** — count of last-100 matching service per dst host |
| 8 | `dst_host_diff_srv_rate` | host-traffic | 100-conn | **HARD** — same ring buffer, different service |
| 9 | `dst_host_srv_serror_rate` | host-traffic | 100-conn | **HARD** — requires TCP state tracking for S0/S1/REJ flags |
| 10 | `dst_host_same_src_port_rate` | host-traffic | 100-conn | **HARD** — same ring buffer, src port equality |
| 11 | `count` | time-traffic | 2-sec | **MEDIUM** — 2-sec deque keyed on dst IP |

**Net**: 2 easy, 1 hardcoded, 3 medium, 5 hard. Estimated Python/scapy port of the AI-IDS extractor logic: ~300-500 lines (confirmed by agent reviewing the C++ source at `AI-IDS/kdd99_feature_extractor/src/ConversationFeatures.cpp`).

### 2.2 DDoS signatures in these 11 features

The NSL-KDD DoS subclasses (neptune=SYN flood, smurf=ICMP amplification, udpstorm=UDP flood, pod=ping-of-death, teardrop, land) were the dataset's dominant attack category (~40% of KDDTrain+ attack samples are neptune alone). The trained model has seen many examples of each and should discriminate them from normal.

Expected feature signatures for live attacks (community consensus across multiple papers; not a single primary source):

| Feature | SYN flood | ICMP flood | UDP flood | Normal |
|---------|-----------|------------|-----------|--------|
| `count` (2-sec conns to dst) | **very high** | **very high** | **very high** | low |
| `same_srv_rate` | **~1.0** | 1.0 | ~1.0 | varies |
| `dst_host_srv_count` | **~100** (saturated) | **~100** | **~100** | low |
| `dst_host_same_srv_rate` | **~1.0** | 1.0 | ~1.0 | varies |
| `dst_host_srv_serror_rate` | **~1.0** (strongest SYN-flood signal) | 0 (non-TCP) | 0 (non-TCP) | ~0 |
| `src_bytes` | ~0 (SYN only) | 0 (ICMP echo small) | variable | normal |
| `dst_bytes` | 0 (no reply) | large (echo-reply) | 0 | normal |

**Critical caveat** flagged by research: `dst_host_srv_serror_rate` is the single strongest neptune discriminator but is **zero for non-TCP attacks by KDD convention**. Our model must lean on `count`, `same_srv_rate`, and `dst_host_srv_count` to catch UDP/ICMP floods. The model training set balance determines whether this works. **Mitigation**: validate offline with hping3-generated pcaps *before* wiring the live pipeline (see §5.1).

### 2.3 Architectural constraints (why we can't do "real line-rate filtering")

- **PCI-orchestrated pipeline is ~1 pps, not ~200 pps.** Milestone 1 measured ~5 ms of *inference*, which is not the binding constraint. Measured end-to-end on 2026-04-17 on nf5: `lab10reg.py ids_batch_packets --delay 0.5` captures 8/20, while `--delay 2.5` captures 20/20. The `cmd_ids_batch_packets` listener alternates between Mode 0 (FIFO captures from NF interface) and Mode 2 (GPU/DMA — FIFO does *not* capture). Mode-2 orchestration (fifo_set_mode, 11× DMEM PCI writes + kernel release + poll_done + response-packet formation + fifo_reset) dominates the loop at ~500 ms wall time per packet under Python-2.4 PCI. Any node1 packets arriving during Mode 2 are dropped at the NF interface. **Real end-to-end capture ceiling is ~1 packet/sec.** The demo must either (a) cap the feature-vector emission rate from nf7 at ≤1 Hz (attack generator can still run at any pps internally — only the *emitted* feature vectors are rate-limited), or (b) rearchitect the loop to pre-buffer multiple feature packets in a single Mode-0 window and batch-process them in Mode 2 (several-hour effort; not currently planned). Path (a) is the assumed baseline for this plan. The story becomes "detect attack *patterns* via ~1 classification/sec, not block at line rate." Honest narration handles this.
- **No in-FPGA filter**: current bitfile classifies and sends a response packet; it does not drop/forward. Adding a drop path would need new RTL, re-synth, and timing closure — infeasible solo in 1 week. The honest framing ("detection stage shown; filtering is existing packet-mux work from Lab 8") is both defensible and expert-respected.
- **NSL-KDD features are connection aggregates**. Feature extraction must maintain state (flow table, 2-sec deque, 100-conn ring buffers). All state lives in Python on nf7 in the planned pipeline.

### 2.4 Known gotchas (from research)

1. **NSL-KDD is critiqued as obsolete** (COMIDDS). Fine for a class demo; don't claim production-grade accuracy.
2. **Service port mapping** — we already dropped `service` from our 11 features, avoiding the fixed 1998 port table problem.
3. **Flow termination ambiguity** — TCP uses FIN/RST, UDP/ICMP use idle timeout (~60s in AI-IDS extractor). Match that convention for consistency.
4. **`srv_serror_rate` flag semantics** — S0 (SYN with no reply) and REJ (RST immediately) must be tracked per TCP flow. For UDP/ICMP flows set to 0 by KDD convention.
5. **Window "current connection" bias** — KDD's `count` looks backward from current conn start time including itself. Implementations differ by ~5-10%.
6. **AI-IDS extractor disclaimer**: "Some features might not be calculated exactly same way as in KDD." The canonical 1998 extractor source is lost; any live extractor is a reasonable approximation.

### 2.5 ARM CPU utilization — analysis (2026-04-17)

**Motivation**: in the pipeline described so far, the ARM CPU does nothing during IDS inference. Feature extraction runs on nf7 in Python; the host PC on nf5 orchestrates DMA and the GPU via PCI; the ARM sits idle. For a network-processor demo, this understates what the system actually is (CPU + GPU + DMA + convertible FIFO on one chip). This section analyzes whether/how to put the ARM to work before May 13.

#### 2.5.1 What the ARM can do today (no RTL change)

Verified from `src/arm/data_mem.v:46-57`, `src/arm/EX.v`, `src/arm/alu64.v`, `src/arm/processor.v:42-56`, `src/lab8_wrapper.v:316-342`:

| Capability | Status | Detail |
|------------|--------|--------|
| Read/write FIFO BRAM | ✅ Yes | ARM DMEM addresses ≥0x80 mux to `cpu_ext_mem_*` (FIFO BRAM Port B). 1-cycle latency. |
| 4-thread FGMT | ✅ Yes | Round-robin (T0 → T1 → T2 → T3). Each thread sees 31.25 MHz effective. No hazards. |
| Shared DMEM | ✅ Yes | 256 × 64-bit words shared across threads (addresses 0x00–0x7F). |
| ARM ISA | ✅ Yes | ADD/SUB/CMP/CMN, AND/OR/XOR/BIC, LDR/STR, shifts, conditional B/BX. **No MUL. No DIV.** |
| Read/write DMA_CTRL, GPU_STATUS, GPU_CTRL | ❌ **No** | These are PCI-register-space (`reg_req_*` path). Not memory-mapped to ARM. Hard architectural blocker for any ARM code that wants to poll GPU done or trigger DMA from the FPGA side. |
| Write GPU IMEM / DMEM | ❌ **No** | GPU memories reachable only via PCI register interface or DMA engine. |

#### 2.5.2 Option A — ARM orchestrates the full pipeline (requires small RTL addition)

Architecturally blocked today, but unblockable with a ~50-line RTL change: memory-map GPU_STATUS, DMA_CTRL, DMA_FIFO_ADDR, DMA_GPU_ADDR, DMA_LENGTH, GPU_CTRL into a reserved ARM DMEM address window (e.g., 0xE0–0xEF). Extend the mux in `src/arm/data_mem.v` or add a sideband decoder in `src/lab8_wrapper.v` that routes those addresses to the existing register flops.

With that change, an ARM program (4-thread FGMT) can:
1. T0: poll FIFO_STATUS (mode 0), wait for packet
2. T0: switch to mode 2, read packet header from FIFO BRAM
3. T0: write DMA_FIFO_ADDR/DMA_GPU_ADDR/DMA_LENGTH + set DMA_CTRL[0]
4. T1: poll GPU_STATUS[1] (dma_active) → clear, then write GPU_CTRL[0] (gpu_start)
5. T2: poll GPU_STATUS[0] (kernel_done)
6. T3: on done, trigger DMA the other way (GPU → FIFO), format response, switch back to mode 0

**Throughput win**: the current Python-PCI orchestrator runs at ~500 ms/packet (§2.3). ARM at 125 MHz doing the same orchestration would run at **microseconds per packet** — a ~1000x throughput increase. This converts the demo from "1 classification/sec" to "hundreds-thousands/sec," which unlocks the line-rate-filter narrative the plan currently disavows in §2.3.

**Narrative win**: the demo story becomes "our SoC orchestrates itself — CPU dispatches, GPU classifies, DMA moves data, all on-chip — no host intervention required." This is the strongest expert-framing available with our system.

**Effort estimate**: 2.5–3 weeks solo.
- RTL + sim: 3–4 days. Small mux, low risk but requires re-synth.
- ARM assembly orchestrator: 5–7 days. FGMT debugging is tricky. Start with single-thread version.
- Hardware verification: 3–4 days. Nf5 testing, fallback to PCI orchestration if issues.
- Integration with feature-extractor pipeline: 2–3 days.

**Risks**:
- **Timing regression.** Fix 1 just closed timing with −4.22 ns worst slack. Adding the ARM-accessible register mux path adds a few LUT levels and could regress. Mitigation: build and synth the RTL change in week 1 and gate further work on timing closure. Revert RTL if endpoints blow past ~1500.
- **ARM debugging is harder than Python debugging.** 4-thread FGMT with shared DMEM means race conditions are possible. Mitigation: start with single-thread orchestrator (run only T0); bring up the other threads only if single-thread works.
- **ARM has no multiply/divide.** Orchestration doesn't need them (it's just address math and polling). But any future feature-extraction work on ARM is handicapped.

#### 2.5.3 Option B — ARM does partial feature extraction (no RTL change)

ARM reads incoming packet from FIFO BRAM, maintains a flow table (~128 entries across 4 threads in shared DMEM), extracts lightweight features (byte counts, TCP flag sums, simple aggregates), writes the 11-BF16 feature vector somewhere the host can pick it up (e.g., dedicated FIFO BRAM slot).

**Feasibility**: yes, without RTL changes. But:
- Flow table fits 256 × 64-bit DMEM tightly (~64 words / 4 threads = 64 flow entries each).
- No MUL/DIV means rate features (`same_srv_rate`, `srv_count/100`) need shift-subtract approximations or fixed-point tables.
- nf7 still has to do *something* (hash bucketing, sending packets to the FPGA in a digestible form), so you don't fully eliminate the nf7 component.
- Doesn't solve the PCI throughput ceiling — host still orchestrates the GPU.

**Effort estimate**: 2 weeks solo.
**Narrative**: weaker than Option A ("ARM helps with feature counting" vs "ARM runs the pipeline"). Good fallback if Option A's RTL changes regress timing.

#### 2.5.4 Option C — keep host orchestration; narrate ARM's role from Lab 8

Keep the demo as currently planned. In the voiceover, reference the ARM's *existing* verified role: in Mode 1 (Lab 8), the ARM reads packets from FIFO BRAM and can modify them before forwarding. In the IDS pipeline that ARM-path is idle — this is an honest architectural separation, not a deficiency.

**Effort**: zero. Narrative: defensible but not maximally impressive. Professor's SoC-advantage hint from 2026-03-26 meeting makes Option A stronger if we can land it.

#### 2.5.5 Recommendation

**Pursue Option A with Option B as the fallback.** Schedule (see §5 below) front-loads the RTL change and synth gate in Week 1 (Apr 18–24). If the synth clears timing, continue to the ARM orchestrator. If it regresses badly, revert and pivot to Option B. Option C is the last-resort fallback.

---

## 3. System Architecture

```
┌─────────────────────────────┐                    ┌──────────────────────────────┐
│ nf7 (attacker + extractor)  │                    │ nf6 (NetFPGA defender)       │
│                             │                    │                              │
│  ┌──────────────────────┐   │                    │   ┌────────────────────┐     │
│  │ hping3 / scapy       │   │ 1. ATTACK TRAFFIC  │   │ NF2 reference      │     │
│  │ attack generator     │   ├───────────────────▶│   │ data path          │     │
│  └──────────────────────┘   │ (10.0.7.255 → .4.2)│   │ (drops at MAC0)    │     │
│           ║                 │                    │   └────────────────────┘     │
│           ║ sniff(lo or     │                    │                              │
│           ║  port0 tap)     │                    │   ┌────────────────────┐     │
│           ▼                 │                    │   │ ids_live_loop.py   │     │
│  ┌──────────────────────┐   │                    │   │                    │     │
│  │ feature_extractor.py │   │ 2. FEATURE VECTORS │   │ listens for BF16   │     │
│  │                      │   │ (one per 2-sec     │   │ feature packets in │     │
│  │ ─ 5-tuple flow table │   │  or per N packets) │   │ FIFO BRAM          │     │
│  │ ─ 2-sec time deque   │   ├───────────────────▶│   │                    │     │
│  │ ─ 100-conn ring/host │   │ via send_ids.py    │   │ for each:          │     │
│  │ ─ TCP flag tracker   │   │ (existing script)  │   │   DMA → GPU        │     │
│  │ ─ logged_in = 0      │   │                    │   │   run BCAST kernel │     │
│  │                      │   │                    │   │   read logits      │     │
│  │ emits 11-feature vec │   │                    │   │   emit to viz      │     │
│  └──────────────────────┘   │                    │   └────────────────────┘     │
│           │                 │                    │            │                 │
│           │                 │                    │            ▼                 │
│           │                 │                    │   ┌────────────────────┐     │
│           │                 │                    │   │ live_viz.py        │     │
│           │                 │                    │   │ matplotlib or      │     │
│           │                 │                    │   │ colored terminal   │     │
│           │                 │                    │   │ rolling window of  │     │
│           │                 │                    │   │ ATTACK/NORMAL      │     │
│           │                 │                    │   │ classifications    │     │
│           │                 │                    │   └────────────────────┘     │
└─────────────────────────────┘                    └──────────────────────────────┘
```

**Clarifications**:
- The attack traffic (arrow 1) goes over the real port0 link from nf7 to nf6. It *doesn't* interact with the classification loop directly; it's there so the feature extractor (which sniffs the same link from nf7 side) sees real headers and state.
- The feature vectors (arrow 2) go over the *same* port0 link but as UDP packets to a known port. The NF2 reference pipeline captures them into the convertible FIFO BRAM, just like milestone 1.
- We sniff on nf7, not nf6, because nf6 is a FPGA host with no easy live packet capture on its custom data path. Sniffing on nf7 means we see the attack we just sent; this is fine — the real-world analog is "you have a mirror port feeding a server that does classification."

---

## 4. Component Spec

### 4.1 Traffic generator (`attack_gen.py` on nf7)

Python wrapper around `hping3` (or pure scapy as fallback if hping3 unavailable). Controls attack type, rate, duration, and an optional normal-traffic interleaver.

**Modes**:
- `normal` — `curl http://10.0.4.2/` in a loop, or `ping 10.0.4.2`, 2-5 pps
- `syn_flood` — `hping3 --flood -S -p 80 10.0.4.2` throttled via `--interval u20000` for ~50 pps
- `udp_flood` — `hping3 --flood --udp -p 53 10.0.4.2` throttled similarly
- `icmp_flood` — `hping3 --flood --icmp 10.0.4.2` throttled
- `mixed` — scripted sequence: 30s normal, 30s syn, 30s udp, 30s icmp, 30s normal

**Rate cap**: the attack generator can run at any pps — hping3 at 50–500 pps is fine because only the *nf7-side feature extractor* sees these packets. What matters for the NetFPGA is the **feature-vector emission rate** from the extractor, which must be ≤1 Hz to match the Mode-0/Mode-2 capture ceiling measured on 2026-04-17 (see §2.3). Keep `attack_gen.py` unthrottled (makes attack traffic visually recognizable on nf7-side tcpdump); do the throttling in `feature_extractor.py` (§4.2). "DDoS" here is *pattern*, not volume.

**Pre-flight**: check that `hping3` is installed; if not, implement a pure-scapy fallback using `scapy.send(IP/TCP/UDP/ICMP, ...)` in a loop.

**~100 lines of Python.**

### 4.2 Feature extractor (`feature_extractor.py` on nf7)

Port of the AI-IDS `kdd99_feature_extractor` `ConversationFeatures.cpp` logic to Python/scapy. Maintains:

1. **Flow table** keyed by `(src_ip, src_port, dst_ip, dst_port, proto)` 5-tuple:
   - Accumulates `src_bytes`, `dst_bytes` (payload lengths by direction)
   - TCP state: first SYN seen → SYN-ACK seen? → FIN/RST seen? → final flag (S0, S1, S2, S3, SF, REJ, RSTO, ...)
   - Opens on first packet, closes on FIN+FIN or RST for TCP, idle timeout (~60s) for UDP/ICMP
   - At close, emits a "connection record" to the windowing layer

2. **Time window** (deque of connection records, trimmed to last 2 seconds):
   - Computes `count` = |{conn in deque : conn.dst_ip == current.dst_ip}|
   - Computes `same_srv_rate` = |{conn in same-dst-group : conn.dst_port == current.dst_port}| / count

3. **Host window** (per-dst-host ring buffers of last 100 connection records):
   - Computes `dst_host_srv_count`, `dst_host_same_srv_rate`, `dst_host_diff_srv_rate`, `dst_host_srv_serror_rate`, `dst_host_same_src_port_rate` by iterating the 100-conn ring for the current connection's `dst_ip`

4. **Output**:
   - Hardcode `logged_in = 0`
   - Pack 11 features into a normalized (min-max using the stored `norm_params` from `data_ids_trained_weights.json`) BF16 UDP payload
   - Emit via `send_ids.py`-style sender to nf6 port0

**Emission cadence**: **exactly one feature vector per 1-second tick** (hard cap — matches the ≤1 pps nf6 capture ceiling from §2.3). Internally the extractor updates its flow table, 2-sec deque, and 100-conn ring buffers at full packet rate. On each 1-sec tick, it picks a representative connection from the last second (e.g., most recently completed, or highest `count`) and emits its 11-feature vector via `send_ids.py`-style sender. During a SYN flood the representative will show high `count` + high `dst_host_srv_serror_rate`; during normal traffic it will show low-rate features. If no connection completed in a 1-sec window (possible during the "recovery" phase of the demo), emit a zero-vector or skip the tick — decide in Day 2 testing.

**Windows update rule**: update the host window whenever a connection completes, using the just-completed connection as the "current" one. This matches the KDD convention.

**Validation**: before running live, feed the extractor a pre-recorded pcap of hping3 SYN flood and compare the emitted features against what `pandas.read_csv('NSL-KDD.txt').groupby('attack_type')` produces for neptune. Tolerance ±20% on rate features is acceptable; `count` and `srv_count` should be exactly reproducible.

**~400 lines of Python.**

### 4.3 Live loop on nf6 (`ids_live_loop.py`)

Extends `lab10reg.py ids_batch_packets` pattern. Listens for UDP packets in FIFO BRAM, for each:
- Read 11 BF16 features from BRAM[7..9]
- DMA to GPU DMEM[0..10]
- Release BCAST kernel
- Poll kernel_done, read logits from DMEM[126..127]
- Classify (argmax)
- Emit `(timestamp, features, logits, classification)` tuple to the visualizer

Runs as long as packets arrive. Should reuse the existing machinery in `lab10reg.py` cmd_ids_from_packet but strip the response-drain step for throughput (we don't need a response packet — the visualization runs on nf6).

**~150 lines building on existing code in lab10reg.py.**

### 4.4 Live visualizer (`live_viz.py` on nf6)

Two options:

**Option A — terminal scroll** (fastest, ~30 lines):
```
[time] [features...] [pred_normal_logit] [pred_attack_logit] [CLASS]
  0.1s  ...                  4.3            -5.1            NORMAL
  0.6s  ...                 -3.8             8.7            ATTACK  ←
```
Colorized with ANSI codes. Last line per-second highlighted.

**Option B — matplotlib rolling window** (~100 lines):
- Top panel: scrolling 30-second timeline of per-second attack probability
- Bottom panel: live confusion matrix updated over the last 30 seconds
- Title strip: current attack mode (if known) + current classification

**Recommendation**: build A first (day 4), upgrade to B if time permits (day 5). A alone is enough for a credible video.

---

## 5. Schedule (revised 2026-04-17 — rebased to 2026-05-13 deadline)

*Previous schedule targeted 2026-04-22 completion on the wrong assumption that Part 3 needed to ship with the Apr 28/30 progress lecture. New truth: Apr 28/30 is a **progress** presentation and Part 3 is optional at that milestone; the hard deadline is **May 13** for the final project demo video. The schedule now has 26 days (Apr 18 → May 13), which lets us pursue the high-risk / high-reward ARM orchestration path (§2.5 Option A) with Option B as a mid-point fallback.*

*Two parallel tracks:*
- **Track A (ARM orchestration)** — the headline upgrade. RTL change + ARM program + integration.
- **Track F (Features/classifier)** — the live-DDoS pipeline from the old schedule (attack_gen, feature_extractor, live_loop, viz).

*Track F is the demo's critical path. Track A is the SoC-narrative upgrade — it runs in parallel but can be cut if timing fails. The record-record-record phase happens in Week 4.*

### Week 1 — Apr 18 (Fri) → Apr 24 (Thu): Track F Days 1–3 + Track A RTL gate

#### Track F (Days 1–3)
- [ ] **F1. Apr 18** — Clone AI-IDS extractor; read `ConversationFeatures.cpp`; take notes on the state machine.
- [ ] **F1.** Confirm the 11 features + norm_params in `data_ids_trained_weights.json` match what the BCAST kernel expects at DMEM[0..10].
- [ ] **F1.** Write `scripts/feature_extractor.py` skeleton: flow table + time window + host window classes with unit tests on 3 synthetic pcaps.
- [ ] **F1.** Generate 3 pcap files on nf7 using hping3 for: SYN flood, UDP flood, ICMP flood (~10 seconds each).
- [ ] **F1.** Run extractor offline on those pcaps; verify feature values look sane vs expected signatures in §2.2.
- [ ] **F1.** Feed the extracted features through the trained model in NumPy (reuse `train_ids.py` eval path).
- [ ] **F1 Gate.** SYN flood → ATTACK, UDP flood → ATTACK, ICMP flood → ATTACK, normal curl pcap → NORMAL. If any fails, diagnose (possibly retrain with class rebalancing) before proceeding.
- [ ] **F2. Apr 19–20** — Write `scripts/attack_gen.py` with modes normal / syn_flood / udp_flood / icmp_flood / mixed; verify via tcpdump on nf7.
- [ ] **F3. Apr 21–22** — `feature_extractor.py`: add live mode (`scapy.sniff(iface='port0', prn=callback)`); test attack_gen+extractor in parallel; confirm vectors emitted per §4.2 cadence.

#### Track A (RTL change + synth gate)
- [ ] **A1. Apr 18–19** — Design the ARM-accessible register mux: pick address range (e.g., 0xE0–0xEF), specify which of {GPU_CTRL, GPU_STATUS, DMA_CTRL, DMA_FIFO_ADDR, DMA_GPU_ADDR, DMA_LENGTH} are exposed, write the Verilog change in either `src/arm/data_mem.v` or a new sideband module.
- [ ] **A2. Apr 20** — Add a testbench in `tb/tb_arm_reg_access.v` that writes a simple ARM program to (a) set DMA_LENGTH via the new path, (b) read it back via PCI, (c) prove coherence.
- [ ] **A3. Apr 21–22** — Synthesize on Fedora VM (`cd /root/netfpga/projects/lab8/synth && make`). Review post-PAR timing.
- [ ] **A3 Gate.** If `core_clk_int` worst slack stays ≥ −6 ns and failing endpoints stay ≤ 1500, proceed to Track A programming. Otherwise: revert RTL; fall back to Option B (partial feature extraction) or Option C (keep ARM idle, narrate honestly).
- [ ] **A4. Apr 23–24** — Given gate passes, hardware-download the new bitfile; run `tb_arm_reg_access` equivalent from Python; confirm the address window behaves as designed.

### Week 2 — Apr 25 (Fri) → May 1 (Thu): Track F end-to-end + Track A orchestrator program

#### Track F (end-to-end pipeline)
- [ ] **F4.** Extend extractor to push feature vectors as UDP to nf6 (reuse `send_ids.py` packing code).
- [ ] **F5.** On nf6, run existing `ids_batch_packets` loop and verify packets arrive and get classified.
- [ ] **F6.** Write `scripts/ids_live_loop.py`: continuous loop reading FIFO BRAM → DMA → GPU → logit → classification → print/emit. Strip the response-drain step.
- [ ] **F7.** Terminal color visualizer (`live_viz.py` Option A).
- [ ] **F8 Gate.** End-to-end dry run: attack_gen sequence "normal → syn → normal" on nf7, watch classifier flip on nf6 within 2 sec of each transition. If flip doesn't happen, diagnose before proceeding.

#### Track A (ARM orchestrator program)
- [ ] **A5.** Write single-thread ARM assembler: `programs/arm/ids_orchestrator.asm` that polls FIFO status, triggers DMA, polls GPU done, formats response. Start single-thread; add FGMT only after single-thread works.
- [ ] **A6.** Simulate via `tb/tb_arm_ids_orchestrator.v` using sim_primitives for FIFO + GPU.
- [ ] **A7. Gate.** Simulation reaches kernel_done and produces a response packet in FIFO BRAM. Compare result vs reference Python orchestration (should be bit-identical since it's the same kernel).

### Week 3 — May 2 (Fri) → May 8 (Thu): Integration + polish + fallbacks

- [ ] **I1.** If Track A gate A7 passed: integrate — use ARM orchestrator instead of Python in `ids_live_loop.py`. Python reduces to "send packet, watch response."
- [ ] **I2.** If Track A gate A7 failed but Option B viable: implement the partial feature-extractor ARM program (§2.5.3) and narrate accordingly.
- [ ] **I3.** If both failed: fall back to Option C (keep ARM idle, narrate the Lab 8 role honestly).
- [ ] **I4.** Matplotlib visualizer (`live_viz.py` Option B) — nicer graphics for the final recording.
- [ ] **I5.** Full end-to-end rehearsal of the 90-second demo script, 2–3 times.
- [ ] **I6.** Write `docs/final_project_demo_video/final_project_expert_demo_script.md` — on-camera cheatsheet + voiceover transcript.

### Week 4 — May 9 (Fri) → May 13 (Tue): Record, edit, ship

- [ ] **R1. May 9–10.** Record Part 3 video with OBS (side-by-side nf6/nf7 windows). Multiple takes.
- [ ] **R2. May 11.** Edit to ~90 seconds. Voice-over.
- [ ] **R3. May 12.** Final review pass. Share with 1–2 beta viewers for feedback.
- [ ] **R4. May 13.** Submit.

### Apr 28 / Apr 30 progress-lecture handling (parallel to above)

At the Apr 28/30 lecture, Part 3 is **optional** (see `../final_project_progress_present/part3_expert.md`):
- If Week 1 cleared both gates (F1 + A3), option B/C from the progress-present doc: include a 30-sec teaser showing architecture + BCAST 3.28× + 75% accuracy, title card "Live demo May 13."
- Otherwise: skip Part 3 at the lecture; focus on Parts 1 + 2 (grandma + investor).

---

## 6. Verification Plan

### 6.1 Unit (offline, no FPGA)
- feature_extractor on pre-recorded pcaps from hping3
- Compare extracted feature distributions to NSL-KDD neptune/smurf/udpstorm samples via pandas
- Feed extracted features through NumPy model (same forward pass as train_ids.py eval)
- Gate: SYN/UDP/ICMP flood pcaps → ATTACK, normal curl pcap → NORMAL

### 6.2 Integration (live, with FPGA)
- Live attack_gen + extractor + FPGA classifier + terminal viz
- Gate: three-attack sequence flips visualizer within 1 window (2-3 sec) of each transition

### 6.3 Demo rehearsal (full dress)
- 90-second script with attack transitions
- Gate: clean take with < 10% classification flips during steady-state phases

### 6.4 Bitfile reliability (BCAST glitching) — **RESOLVED 2026-04-17**

Apr 12 bitfile showed 14-cycle / 1.0-BF16 glitches in ~40% of BCAST runs. Fix 1 bitfile (built 2026-04-17 11:00 GMT, at `synth/nf2_top_par.bit`) is hardware-verified deterministic — see §7.2 for the full record. The live-demo classifier runs on Fix 1 and does **not** need glitch tolerance. No per-second smoothing or majority vote needed in `ids_live_loop.py`.

If a future re-synth regresses this, fall back to the Fix 1 bitfile already deployed on nf5 (`~/zil_testing_folder/nf2_top_par.bit`).

---

## 7. Risks and Mitigations

### 7.1 Risk: feature extraction doesn't match NSL-KDD distribution
**Likelihood**: medium. AI-IDS extractor itself disclaims exact fidelity; Python port will diverge slightly.
**Impact**: model accuracy drops, possibly below "obviously right" on live traffic.
**Mitigation**: Day 2 gate tests against offline pcaps catch this before going live. If model accuracy is too low on live features, options:
- Retrain `train_ids.py` directly on features extracted by our extractor from a pcap-to-feature pipeline (so model and extractor agree even if neither matches canonical NSL-KDD)
- Accept it and narrate honestly: "Our live extractor diverges from canonical NSL-KDD by ~X%, we could close this with more engineering"

### 7.2 Risk: BCAST glitching makes live demo unreliable — **RESOLVED 2026-04-17**
**Status**: closed. The Apr 12 bitfile showed 14-cycle / 1.0-BF16 quanta glitches in ~40% of BCAST runs. On 2026-04-17, **Fix 1** (register `effective_a` inside `src/gpu/simd_alu.v` to split the `op_b mux → bcast_value → effective_a → bf16_alu` combinational path) was hardware-verified on nf5:
- BCAST × 5 loop: **5/5 PASS**, cycles=732 every run, DMEM[126]=`0x41b041b0_41b041b0` every run (bit-identical).
- Scalar IDS regression: 2402 cycles, correct output.
- `ids_batch_packets 20 test_features.csv` with varied samples: 75.0% accuracy, matching milestone 1 exactly — confirming Fix 1 doesn't regress classification behavior.
- Synth: failing `core_clk_int` endpoints dropped 4146 → 650; worst slack −7.15 → −4.22 ns. Remaining violations live in the ARM CPU datapath (idle during IDS inference).

**No mitigation needed.** The previously escalating mitigations (majority-vote smoothing, INT16-ALU removal re-synth, 100 MHz clock drop) are **not required** and should not be implemented — they would add code paths that obscure the clean detection narrative. See `docs/milestone3_refinements.md` §3.6–§3.7 and `memory/project_fix1_hardware_verified.md` for the full verification record.

### 7.3 Risk: UDP/ICMP floods don't trigger ATTACK because `dst_host_srv_serror_rate` is 0 for them
**Likelihood**: medium. Research flagged this explicitly.
**Impact**: UDP/ICMP portions of the demo fail, SYN flood still works.
**Mitigation**: validate in Day 2 offline tests. If UDP/ICMP don't fire, options:
- Demo SYN flood only and call it "our model's strongest signal"
- Augment training data with more udpstorm/smurf examples and retrain (~1 hour)
- Lean on `count` and `dst_host_srv_count` which *should* fire for all flood types if the model weights learned them

### 7.4 Risk: hping3 not installed on nf7
**Likelihood**: low (commonly available on Linux test hosts) but not verified.
**Impact**: need scapy fallback.
**Mitigation**: Day 1 check. If missing, pure-scapy attack generator is straightforward (~50 extra lines, uses `send(IP(dst)/TCP(flags='S', dport=80), loop=1)` etc.).

### 7.5 Risk: nf7 sniffing requires root or raw socket privilege
**Likelihood**: high.
**Impact**: extractor needs sudo.
**Mitigation**: just run with sudo in the recording. Set CAP_NET_RAW on the Python binary if sudo is awkward for recording.

### 7.6 Risk: slow-rate attack doesn't look like "DDoS" to layperson
**Likelihood**: high if viewer is non-technical.
**Impact**: Part 3 narrative weakened.
**Mitigation**: Part 3 is the *expert* segment — experts understand that pattern >> volume for an ML-based classifier demo. Narrate explicitly: "The attack generator is running at ~50–100 packets per second, but our classifier produces one aggregated classification per second — experts will recognize this as pattern-level DDoS detection over a sliding window, not line-rate packet filtering. A production deployment would pair this classifier with an in-FPGA drop action; we already demonstrated the MAC-layer packet mux that enables that in Lab 8." For Part 1 (grandma segment) the narration can be more dramatic since accuracy is less important there.

### 7.7 Risk: solo time estimate is optimistic
**Likelihood**: medium. Every solo project overruns.
**Impact**: Part 3 slips toward the May 13 deadline; Track A (ARM orchestration) gets cut.
**Mitigation**: Track F is the critical path; Track A is the upgrade. If Track F Week-2 gate (F8) doesn't pass by May 1, freeze Track A regardless of its state and converge on Option C (narrate ARM's Lab 8 role). The May 9–13 recording window is non-negotiable.

### 7.8 Risk: ARM-register RTL change regresses timing (Track A only)
**Likelihood**: medium. Fix 1 just closed `core_clk_int` with −4.22 ns worst slack and 650 failing endpoints. Adding an ARM-side mux path into the register-read network is a few LUT levels near addresses that already have tight slack (register flops → PCI readback).
**Impact**: if timing blows up (e.g., worst slack < −8 ns, endpoints > 1500), the ARM orchestration path is not trustworthy on hardware. Symptoms on-chip would look like sporadic wrong register reads or DMA kicks at the wrong moment — very hard to debug, would consume Week-2/3 budget.
**Mitigation**: treat gate A3 (Apr 21–22) as a **hard** go/no-go. Budget: 2 days of synth + analysis in Week 1. Fallback branches are clean:
- Revert `src/arm/data_mem.v` + any wrapper changes to the Fix 1 baseline. Bitfile reverts to the known-working Apr 17 deployment on nf5.
- Pivot to Option B (partial feature extraction, no RTL change) or Option C (keep ARM idle).
- Track F continues regardless — it does not depend on Track A.

**Early-abort criterion**: if after 4 hours of PAR you're above −10 ns worst slack with no obvious placement fix, don't fight it. Revert and pivot.

---

## 8. Fallback Plans

### Fallback A — Partial DDoS demo (if live extraction is flaky)
Ship SYN-flood-only demo with live extraction working. Drop UDP/ICMP modes. Still shows the full pipeline for one attack type; narrate honestly.

### Fallback B — Offline pcap playback (if live sniffing has timing issues)
Pre-record pcaps of each attack type. Replay via `tcpreplay` or a scripted scapy sender. Feature extractor runs on the replay. Loses some "it's live!" punch but is rock-solid reliable.

### Fallback C — Revert to milestone-1-style demo with live feature flavor (worst case)
If the whole live-extraction pipeline collapses, run milestone 1's `ids_batch_packets` batch demo with a CSV of features extracted offline from real attack pcaps. Narrate: "these features were extracted from real hping3 DDoS pcaps; the live extractor is future work." Accuracy numbers carry the demo.

---

## 9. Deliverables Checklist

### Track F (required for May 13) — Python pipeline
- [ ] `scripts/feature_extractor.py` — ~400 lines, scapy-based NSL-KDD feature extractor
- [ ] `scripts/attack_gen.py` — ~100 lines, hping3/scapy attack traffic generator
- [ ] `scripts/ids_live_loop.py` — ~150 lines, nf6-side classification loop with viz hook
- [ ] `scripts/live_viz.py` — ~30-100 lines, terminal or matplotlib visualizer

### Track A (optional upgrade, pursued if §2.5 Option A passes gate A3) — ARM orchestration
- [ ] RTL: memory-mapped ARM access to {GPU_CTRL, GPU_STATUS, DMA_CTRL, DMA_FIFO_ADDR, DMA_GPU_ADDR, DMA_LENGTH} at reserved DMEM window (e.g., 0xE0–0xEF). ~50 lines Verilog in `src/arm/data_mem.v` or `src/lab8_wrapper.v`.
- [ ] `tb/tb_arm_reg_access.v` — simulation coherence test for the new ARM path.
- [ ] `programs/arm/ids_orchestrator.asm` + `.hex` — ARM assembly orchestrator (FIFO poll + DMA + GPU start + done poll + response format).
- [ ] `tb/tb_arm_ids_orchestrator.v` — full-stack simulation (ARM program driving FIFO → GPU → response).
- [ ] Re-synthesized bitfile if gate passes.

### Docs
- [ ] This plan doc — keep updated as things slip.
- [ ] `docs/final_project_demo_video/final_project_expert_demo_script.md` — analogous to `docs/milestone2_demo_script.md`, with on-camera cheatsheet + voiceover transcript. Write in Week 3 when the technical flow is confirmed.
- [ ] (if Track A) `docs/final_project_demo_video/arm_orchestration_design.md` — RTL change rationale, ARM program architecture, verification record.

### Artifacts
- [ ] 3 hping3-generated pcaps for offline validation
- [ ] Recorded Part 3 video (~90 sec, due 2026-05-13)
- [ ] (Apr 28/30) optional teaser clip for progress lecture — see `../final_project_progress_present/part3_expert.md`

---

## 10. Sources

Research references (used in §2):
- [KDD Cup 1999 Task Description (UCI)](https://kdd.ics.uci.edu/databases/kddcup99/task.html) — authoritative feature definitions
- [Tavallaee et al. 2009, "A Detailed Analysis of the KDD CUP 99 Data Set" (NSL-KDD paper, IEEE CISDA)](https://www.ee.torontomu.ca/~bagheri/papers/cisda.pdf)
- [AI-IDS/kdd99_feature_extractor on GitHub](https://github.com/AI-IDS/kdd99_feature_extractor) — C++ reference implementation we port
- [AI-IDS ConversationFeatures.cpp](https://github.com/AI-IDS/kdd99_feature_extractor/blob/master/src/ConversationFeatures.cpp) — confirms 2-sec + 100-conn parallel windows
- [NSL-KDD dataset (UNB CIC)](https://www.unb.ca/cic/datasets/nsl.html)
- [COMIDDS critique of NSL-KDD](https://fkie-cad.github.io/COMIDDS/content/datasets/nsl_kdd_dataset/) — obsolescence warning
- [KDD99 alternatives survey, arXiv 1811.05372](https://arxiv.org/pdf/1811.05372)
- [MrGM26/Live-Threats-Detection (Python live NSL-KDD demo)](https://github.com/MrGM26/Live-Threats-Detection) — prior art reference

Project context:
- `docs/lab10_refinements.md` — full lab 10 plan
- `docs/milestone1_demo_script.md` — milestone 1 pipeline that we extend
- `docs/milestone2_demo_script.md` — BCAST + cycle counter story to name-drop in Part 3 narration
- `docs/bcast_instruction_design.md` — BCAST design rationale, for the "custom ISA" talking point
- `scripts/train_ids.py` — defines the 11 trained features and normalization
- `programs/gpu/data_ids_trained_weights.json` — source of truth for selected features and norm params
