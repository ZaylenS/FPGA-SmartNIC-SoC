# Throughput Measurement Runbook — PCI vs ARM Orchestration

**What this measures.** End-to-end packet throughput of the IDS inference
pipeline under two orchestration strategies:

- **PCI orchestration** — host Python loop drives the pipeline per packet
  (poll FIFO, DMA features, release GPU, poll kernel, form response, drain).
  Matches `lab10reg.py ids_batch_packets`.
- **ARM orchestration (Fix B)** — ARM CPU on-chip polls the FIFO, runs the
  same sequence in ~microseconds per packet, rewrites Eth/IP/UDP headers,
  and drains the response autonomously. Host only loads programs.

Both use the same BCAST IDS kernel, same weights, same input packets.
Only the orchestrator differs.

---

## Prerequisites

**Bitfile:** The Fix B bitfile (`synth/nf2_top_par.bit`, md5 `aa680d9f...`,
post-synth 2026-04-20 21:13) must be flashed on the target FPGA. All plan
gates met (core slack −4.394 ns, MAC clocks 0 failing endpoints). See
`docs/milestone3_refinements.md` §10 for timing closure details.

**Files on nf5:**
- `scripts/lab10reg.py` (with new `ids_pci_throughput` and `ids_arm_start`
  commands)
- `scripts/lab9reg.py`
- `programs/gpu/ann_ids_11_16_8_2_bcast.hex`
- `programs/gpu/data_ids_11_16_8_2_bcast.hex`
- `programs/arm/ids_orchestrator.hex`
- `scripts/test_features.csv` (or any labeled feature CSV)

**Files on node1:**
- `scripts/send_ids.py` (with new `--count`, `--listen` flags)
- `scripts/test_features.csv`

---

## Measurement 1 — PCI orchestration throughput (baseline)

### Important: pacing requirement

The `convertible_fifo` is a **1-packet buffer**. While PCI is servicing a
packet (~1–2 s per packet because every register access is a
subprocess call to the NF2 `regread`/`regwrite` binaries), a subsequent
packet arriving at NF2 ingress is dropped — `in_rdy` is low. So node1 must
**pace its sends slower than the PCI service rate**. A safe default is
`--delay 2.0` (one packet every 2 s) which gives PCI plenty of time per
iteration while still being representative. If you try `--delay 0` (blast),
only the first packet will be serviced and the nf6 script will stall
waiting for packets that were already dropped at ingress.

The nf6 script has a 30 s stall watchdog: if no new packet arrives for
30 s after the last service completes, it bails out and reports what it
got (rather than hanging).

### Commands

**On nf6:**

```bash
python lab10reg.py ids_pci_throughput 50
```

Waits for the first packet (30 s timeout), then runs the service loop for
50 packets with a dot-per-packet progress indicator.

**On node1 (after nf6 prints "Waiting for first packet..."):**

```bash
python send_ids.py --csv test_features.csv --count 50 --delay 2.0 --replicated
```

Sends 50 packets from the CSV, one every 2 s (cycles the rows if the CSV
is shorter than `count`). With 50 packets at 2 s pacing, total send time
is ~100 s; nf6's service time will track the same window.

> Why 2.0 s and not 1.0? With delay = service time exactly, there's no
> margin and any one slow iteration on nf6 (e.g., GPU poll timeout)
> cascades into packet drops. 2.0 s gives ~2× headroom without making
> the test take too long.

### What nf5 prints at the end

```
=== PCI Orchestration Result ===
  Serviced:        50 packets
  Skipped (ARP):   <N>
  GPU timeouts:    0
  Wall time:       <T> s
  Throughput:      <X> pps
  Avg per-pkt:     <Y> ms
```

### Expected numbers (from prior measurements)

| Metric | Expected |
|---|---|
| Throughput | **limited by send pacing** at 0.5 pps when --delay=2.0 |
| True PCI service rate | ~0.3 – 1 pps (visible in "Avg per-packet" ms) |
| Avg per-packet | ~1000 – 3000 ms |

The reported throughput here is essentially `1 / send_delay` — node1 paces
the test. But **Avg per-packet** is the real PCI service time; that's what
would set the ceiling if node1 were a perfect queue. To see the bare PCI
service rate, reduce `--delay` toward the Avg per-packet time (e.g., if
Avg per-packet is 1.2 s, try `--delay 1.4`).

The per-packet cost is dominated by **Python-over-PCI register access
latency** — every `regread`/`regwrite` is a subprocess call to the NF2
`regread`/`regwrite` binaries. The orchestrator makes ~30 such calls per
packet.

---

## Measurement 2 — ARM orchestration throughput

### Commands

**On nf5:**

```bash
python lab10reg.py ids_arm_start
```

This loads the BCAST kernel + weights into GPU, loads
`programs/arm/ids_orchestrator.hex` into ARM IMEM, starts the ARM, applies
the `mode 0 + fifo_reset` workaround after `cpu_start` (see
`feedback_orchestrator_bringup_checklist`), then enters a 2-second-interval
idle monitor showing the GPU cycle counter.

The host does **nothing** per-packet after this point. Every inference is
handled end-to-end on-chip.

**On node1 (after nf5 says "ARM orchestrator running"):**

```bash
python send_ids.py --csv test_features.csv --count 50 --delay 0 --replicated --listen
```

This:
1. Binds local UDP port 9998 (stable source port so responses return to us).
2. Sends 50 packets back-to-back (no inter-packet delay).
3. Drains any pending responses between sends (non-blocking).
4. After the last send, waits 3 s for stragglers.
5. Reports send rate, receive rate, delivery %, and first-response logits.

### What node1 prints at the end

```
=== send_ids throughput report ===
  Sent:            50 packets
  Send window:     <T_send> s
  Send rate:       <X_send> pps  (Python sendto pace)
  Received:        <M> responses  (<pct>% of sent)
  First response:  +<t1> s after first send
  Last response:   +<tN> s after first send
  End-to-end pps:  <X_e2e> pps  (responses received / total window)
  First logits:    BF16 0xXXXX / 0xYYYY  (~f1, ~f2)  -> NORMAL|ATTACK
```

### Expected numbers (Fix B on silicon)

| Metric | Expected |
|---|---|
| Send rate | hundreds of pps (Python socket limit) |
| End-to-end pps | hundreds of pps (bounded by MAC / FIFO / kernel cycle, ARM orchestrator is ~microseconds per packet) |
| Delivery % | should be ~100 % on small batches; may drop under heavy overload |

### Stop the ARM on nf5

`Ctrl-C` on the `ids_arm_start` terminal — the script issues
`cpu_assert_reset()` on exit, holding the ARM in reset cleanly.

---

## Comparison math (what to put on the slide)

Let `T_pci` = PCI throughput (pps), `T_arm` = ARM end-to-end throughput (pps).

- **Speedup** = `T_arm / T_pci`
- **Per-packet latency reduction** = `(1/T_pci - 1/T_arm) * 1000` ms

Narrative framing: the PCI path is limited by Python-over-PCI orchestration,
not by the FPGA itself; the ARM path uses the same GPU kernel but runs the
orchestration in hardware cycles (~microseconds per iteration), so the
ceiling moves from ~1 pps to whatever the NF2 MAC/FIFO/GPU pipeline can
sustain. This is the SmartNIC / DPU narrative from `docs/arm_orchestrator.md`.

---

## Sanity checks if numbers look wrong

**ARM path — 0 responses received.**
1. On nf5: `python lab10reg.py cpu_status` — confirm `halted=0` and
   `running=1`. If halted, the ARM tripped HALT (check for IMEM corruption).
2. On nf5: `python lab10reg.py status` — confirm FIFO is in mode 0 and
   `pkt_ready` is toggling as packets arrive. If FIFO_MODE=1, re-run the
   `fifo_set_mode(0)` step (cpu_start sets it to 1).
3. Confirm the bitfile has Fix B loaded (check `synth/nf2_top_par.bit` md5,
   should be `aa680d9f...`; the Apr 18 Fix A bitfile won't have the
   reg_fifo_drain alias at slot 0xFA and will silently NOT drain).
4. Check node1 firewall / `iptables` allowing UDP port 9998.

**ARM path — some responses received, low rate.**
- Increase `--count` (e.g., 500 or 1000) to amortize any one-time setup jitter.
- Try `--delay 0.001` vs `--delay 0` — very tight blast can saturate the
  NF2 FIFO (one-packet buffer) causing packet drop at ingest. ARM then
  only sees a subset.

**PCI path — way below 1 pps.**
- Expected on PCI-orchestrated path; not a failure.
- If it's even slower (< 0.1 pps), check for GPU timeouts in the summary.

**First logits column shows wrong class.**
- Check that the BCAST kernel + weights match (`ids_load`).
- The sample used is `test_features.csv` row 0. If the CSV has labels,
  row 0's true label should match the predicted one most of the time
  (75% accuracy was measured on the 20-sample batch).

---

## Files changed / added for this runbook

- `scripts/lab10reg.py` — added `cmd_ids_pci_throughput()`,
  `cmd_ids_arm_start()`, and `cmd_ids_arm_debug_once()` with configurable
  `halt_at`, plus CLI dispatch entries.
- `scripts/send_ids.py` — added `load_samples()`, `_drain_responses()`,
  `_parse_response_bf16_pair()`, `send_throughput()`, plus `--count`,
  `--delay`, `--listen` flag handling in `main()`.
- `scripts/ids_arm_watch.sh` — parallel diagnostic loop (runs in 2nd
  terminal during `ids_arm_start`). Uses only PCI status reads — does
  NOT read FIFO BRAM since that flips FIFO_MODE to 1 and blocks ingress.
- `docs/throughput_measurement_runbook.md` — this file.

---

## Status as of 2026-04-21

**Measured:**
- PCI orchestration: 0.65 pps, 1527 ms/packet. Dominated by Python-over-PCI
  subprocess overhead (30 regread/regwrite calls per packet × ~50 ms each).
- Fix B orchestrator: silicon-verified to rewrite BRAM[0..8] correctly per
  the design. See `docs/arm_orchestrator.md §13.3.4` for the BRAM dump.

**Blocker: response delivery to node1.**
- Neither PCI nor ARM-orchestration responses reach node1. `send_ids.py
  --listen` reports 0 received in both paths.
- Root cause hypothesis: MAC/IP swap produces broadcast SrcMAC/SrcIP
  (since node1 sends to `10.0.7.255` broadcast → ingress DstMAC/DstIP
  are both broadcast → after swap they become the response's SrcMAC/SrcIP,
  which is an invalid source address config). Linux kernel RPF
  (`rp_filter=1` default) silently drops unicast frames with broadcast
  SrcIP.
- Affects both paths identically because `_form_and_drain_response`
  (lab10reg.py) and `ids_orchestrator.hex` use the same swap math.
- Milestone 1's "75% accuracy" didn't expose this — it counted packets
  processed on nf6, not responses received on node1.

**Next session plan:**
1. `tcpdump -i <iface> -nne udp port 9998` on node1. Re-run PCI test. If
   tcpdump sees frames → kernel filter. If not → MAC0 TX / routing issue.
2. If kernel filter: either `sudo sysctl -w net.ipv4.conf.all.rp_filter=0`
   on node1 (quick hack), or hardcode valid SrcMAC/SrcIP in both
   `_form_and_drain_response` and `ids_orchestrator.hex` (proper fix).
3. Once delivery works: run throughput comparison per the commands above
   and report PCI pps vs ARM pps.
