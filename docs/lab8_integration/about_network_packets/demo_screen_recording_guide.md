# Lab 9 Demo — Screen Recording Guide

Updated for Lab 9 (subgroup integration phase). Uses `lab9reg.py` on the FPGA.
Each section has PAUSE markers and mouse/scroll hints for audio sync.

---

## Terminal Setup (before recording starts)

- Terminal 1 (FPGA): `ssh netfpga@nf5.usc.edu`, already in `~/lab9_integration/`
- Terminal 2 (node0): `ssh node0@nf6.usc.edu`
- Make terminal font large enough to read on recording
- Both terminals visible (side-by-side or tabbed)

Pre-check before hitting record:

```bash
# On FPGA terminal
nf_download ~/lab9_integration/nf2_top_par.bit
cd ~/lab9_integration
ls    # show files: lab9reg.py, test_4t_v2.hex, kernels, ANN hex files, etc.
```

---

## START RECORDING

---

### [0:00] Opening — Show Environment (~15 sec)

```bash
ls
```

> MOUSE: Point slowly across the files shown (lab9reg.py, test_4t_v2.hex, kernel .hex files, ANN .hex files)
> PAUSE 3 sec on the file listing

Switch to node0 terminal briefly:

```bash
# On node0
/sbin/ifconfig port0
```

> MOUSE: Point at the IP address 10.0.0.3
> PAUSE 2 sec, then switch back to FPGA terminal

---

### [0:15] Test A — Packet Capture (~30 sec)

```bash
python lab9reg.py reset
```

> PAUSE 3 sec (wait for ARP to arrive)

```bash
python lab9reg.py status
```

> MOUSE: Point at `pkt_ready=1`, then `pkt_word_cnt=8`
> PAUSE 3 sec on status output

```bash
python lab9reg.py fifo_read 0 8
```

> MOUSE: Slowly point at each line:
>   1. BRAM[0] -- point at `ctrl=0xff` (header marker)
>   2. BRAM[1] -- point at `ffffffff_ffff` (broadcast MAC)
>   3. BRAM[2] -- point at `0806` (ARP EtherType)
> PAUSE 4 sec total, let the viewer read the packet dump

---

### [0:45] Test B — Packet Echo / Header Rewrite + Drain (~20 sec)

```bash
python lab9reg.py packet_echo 01
```

> MOUSE: Point at the output lines:
>   1. Point at `dst_port=0x0002` and `CPU0` -- original routing
>   2. Point at `dst_port 0x0002 -> 0x0001` -- the rewrite
>   3. Point at `ctrl=0xff preserved` -- critical detail
>   4. Point at `Drain triggered`
> PAUSE 3 sec on packet_echo output

Now verify the FIFO is empty after drain:

```bash
python lab9reg.py status
```

> MOUSE: Point at `fifo_empty=1`, then point at `pkt_ready=0`
> PAUSE 3 sec -- confirm to the viewer the packet was fully drained

---

### [1:05] Test C — ARM CPU Modifies Packet (~60 sec)

#### C1: Capture new packet

```bash
python lab9reg.py reset
```

> PAUSE 3 sec

```bash
python lab9reg.py status
```

> MOUSE: Point at `pkt_ready=1`
> PAUSE 1 sec

#### C2: Read BRAM[1] BEFORE CPU

```bash
python lab9reg.py fifo_read 1 1
```

> MOUSE: Point at the lower 32 bits of the data value
> PAUSE 3 sec -- this is the "before" value the viewer needs to remember

#### C3: Load CPU program (slow, ~30 sec)

```bash
python lab9reg.py cpu_load_imem test_4t_v2.hex
```

> This takes ~30 sec. While waiting:
> MOUSE: Can point at the "Loading..." progress
> No need to do anything, just let it run

#### C4: Switch to CPU mode, check current value

```bash
python lab9reg.py mode 1
python lab9reg.py fifo_read 1 1
```

> MOUSE: Point at the current lower 32 bits
> PAUSE 2 sec -- note this value (CPU will add 42 to THIS value)

#### C5: Run CPU

```bash
python lab9reg.py cpu_start
```

> PAUSE 1 sec

```bash
python lab9reg.py cpu_status
```

> MOUSE: Point at `all_halted` or `running` status
> PAUSE 2 sec

```bash
python lab9reg.py cpu_stop
```

#### C6: Read BRAM[1] AFTER CPU

```bash
python lab9reg.py fifo_read 1 1
```

> MOUSE: Point at the lower 32 bits -- should differ by 0x2A (42) from C4 value
> PAUSE 4 sec -- this is the key result, give viewer time to compare

#### C7: Drain modified packet

```bash
python lab9reg.py packet_echo 01
```

> PAUSE 2 sec on output

---

### [2:05] Test D — GPU Kernels on Packet Data (5 kernels, manual steps)

Each kernel follows the same manual sequence. The first kernel (D1) is shown
in full detail. Kernels D2-D5 repeat the same steps with a different hex file.

#### D1: vec_add_i16 — INT16 vector addition (full detail, ~90 sec)

##### D1a: Capture packet

```bash
python lab9reg.py reset
```

> PAUSE 3 sec (wait for ARP)

```bash
python lab9reg.py status
```

> MOUSE: Point at `pkt_ready=1`
> PAUSE 1 sec

##### D1b: Switch to GPU mode

```bash
python lab9reg.py mode 2
```

> PAUSE 1 sec

##### D1c: Load GPU kernel

```bash
python lab9reg.py gpu_load_imem vec_add_i16.hex
```

> MOUSE: Point at "Loaded N instructions"
> PAUSE 2 sec

##### D1d: DMA packet data from FIFO to GPU (skip header BRAM[0])

```bash
python lab9reg.py dma_fifo_to_gpu 1 0 7
```

> MOUSE: Point at "DMA FIFO->GPU: FIFO[1..7] -> GPU DMEM[0..6]"
> PAUSE 2 sec

##### D1e: Verify GPU received the data

```bash
python lab9reg.py gpu_read_dmem 0 3
```

> MOUSE: Point at DMEM[0] and DMEM[1] -- these are the two input words
> (DMEM[0] = BRAM[1], DMEM[1] = BRAM[2])
> PAUSE 3 sec

##### D1f: Run the kernel

```bash
python lab9reg.py gpu_start
```

> PAUSE 1 sec

```bash
python lab9reg.py gpu_status
```

> MOUSE: Point at `kernel_done`
> PAUSE 2 sec

```bash
python lab9reg.py gpu_stop
```

##### D1g: Read GPU result

```bash
python lab9reg.py gpu_read_dmem 0 3
```

> MOUSE: Point at DMEM[2] -- THIS IS THE RESULT
>   DMEM[2] = DMEM[0] + DMEM[1], lane-by-lane 16-bit wrapping add
>   Example: FFFF+9F0A=9F09, FFFF+106B=106A, FFFF+0806=0805, A036+0001=A037
> PAUSE 5 sec -- key result, let viewer read and compare

##### D1h: DMA results back to FIFO

```bash
python lab9reg.py dma_gpu_to_fifo 0 1 7
```

> MOUSE: Point at "DMA GPU->FIFO" confirmation
> PAUSE 2 sec

##### D1i: Verify FIFO BRAM has the GPU results

```bash
python lab9reg.py fifo_read 0 8
```

> MOUSE: Point at BRAM[3] -- should match DMEM[2] (the GPU result)
>   BRAM[0] still has the original header (ctrl=0xff)
>   BRAM[1], BRAM[2] unchanged (passthrough from GPU)
> PAUSE 4 sec

##### D1j: Drain modified packet

```bash
python lab9reg.py packet_echo 01
```

> PAUSE 2 sec

---

#### D2: vec_sub_i16 — INT16 vector subtraction (~60 sec)

Same steps, different kernel. v2 = v0 - v1.

```bash
python lab9reg.py reset
```

> PAUSE 3 sec

```bash
python lab9reg.py status
python lab9reg.py mode 2
python lab9reg.py gpu_load_imem vec_sub_i16.hex
python lab9reg.py dma_fifo_to_gpu 1 0 7
```

> PAUSE 1 sec

```bash
python lab9reg.py gpu_start
python lab9reg.py gpu_status
python lab9reg.py gpu_stop
```

> MOUSE: Point at `kernel_done`
> PAUSE 1 sec

```bash
python lab9reg.py gpu_read_dmem 0 3
```

> MOUSE: Point at DMEM[2] -- subtraction result (DMEM[0] - DMEM[1])
> PAUSE 4 sec

```bash
python lab9reg.py dma_gpu_to_fifo 0 1 7
python lab9reg.py fifo_read 0 8
```

> MOUSE: Point at BRAM[3] -- should match DMEM[2]
> PAUSE 3 sec

```bash
python lab9reg.py packet_echo 01
```

> PAUSE 1 sec

---

#### D3: bf16_mul — BFloat16 multiplication (~60 sec)

Same steps. v2 = v0 * v1 (BFloat16, 4 lanes).

```bash
python lab9reg.py reset
```

> PAUSE 3 sec

```bash
python lab9reg.py status
python lab9reg.py mode 2
python lab9reg.py gpu_load_imem bf16_mul.hex
python lab9reg.py dma_fifo_to_gpu 1 0 7
```

> PAUSE 1 sec

```bash
python lab9reg.py gpu_start
python lab9reg.py gpu_status
python lab9reg.py gpu_stop
```

> MOUSE: Point at `kernel_done`
> PAUSE 1 sec

```bash
python lab9reg.py gpu_read_dmem 0 3
```

> MOUSE: Point at DMEM[2] -- BFloat16 multiplication result
> PAUSE 4 sec

```bash
python lab9reg.py dma_gpu_to_fifo 0 1 7
python lab9reg.py fifo_read 0 8
```

> MOUSE: Point at BRAM[3]
> PAUSE 3 sec

```bash
python lab9reg.py packet_echo 01
```

> PAUSE 1 sec

---

#### D4: bf16_fma — BFloat16 fused multiply-add (~60 sec)

Same steps. v3 = v0 * v1 + v2 (6 instructions, stores to DMEM[3]).

```bash
python lab9reg.py reset
```

> PAUSE 3 sec

```bash
python lab9reg.py status
python lab9reg.py mode 2
python lab9reg.py gpu_load_imem bf16_fma.hex
python lab9reg.py dma_fifo_to_gpu 1 0 7
```

> PAUSE 1 sec

```bash
python lab9reg.py gpu_start
python lab9reg.py gpu_status
python lab9reg.py gpu_stop
```

> MOUSE: Point at `kernel_done`
> PAUSE 1 sec

```bash
python lab9reg.py gpu_read_dmem 0 4
```

> MOUSE: Point at DMEM[3] (not DMEM[2]) -- FMA result
>   This kernel uses 3 inputs (v0, v1, v2) and stores to v3 -> DMEM[3]
> PAUSE 4 sec

```bash
python lab9reg.py dma_gpu_to_fifo 0 1 7
python lab9reg.py fifo_read 0 8
```

> MOUSE: Point at BRAM[4] -- should match DMEM[3]
> PAUSE 3 sec

```bash
python lab9reg.py packet_echo 01
```

> PAUSE 1 sec

---

#### D5: relu_i16 — INT16 ReLU activation (~60 sec)

Same steps. v1 = max(v0, 0) (clamp negative lanes to zero).

```bash
python lab9reg.py reset
```

> PAUSE 3 sec

```bash
python lab9reg.py status
python lab9reg.py mode 2
python lab9reg.py gpu_load_imem relu_i16.hex
python lab9reg.py dma_fifo_to_gpu 1 0 7
```

> PAUSE 1 sec

```bash
python lab9reg.py gpu_start
python lab9reg.py gpu_status
python lab9reg.py gpu_stop
```

> MOUSE: Point at `kernel_done`
> PAUSE 1 sec

```bash
python lab9reg.py gpu_read_dmem 0 2
```

> MOUSE: Point at DMEM[1] -- ReLU output
>   Compare with DMEM[0]: lanes with bit[15]=1 (negative int16) become 0x0000
>   Lanes with bit[15]=0 (positive int16) pass through unchanged
> PAUSE 4 sec

```bash
python lab9reg.py dma_gpu_to_fifo 0 1 7
python lab9reg.py fifo_read 0 8
```

> MOUSE: Point at BRAM[2] -- should match DMEM[1]
> PAUSE 3 sec

```bash
python lab9reg.py packet_echo 01
```

> PAUSE 1 sec

---

### [~7:30] Test E — Stress Test: CPU + GPU Back-to-Back (~90 sec)

This shows the full pipeline: packet -> CPU processing -> GPU processing.

> MOUSE: Before starting, briefly hover on the terminal to signal "new section"
> PAUSE 2 sec

##### E1: Capture packet

```bash
python lab9reg.py reset
```

> PAUSE 3 sec

```bash
python lab9reg.py status
```

> MOUSE: Point at `pkt_ready=1`

##### E2: CPU modifies BRAM[1] (+42)

```bash
python lab9reg.py cpu_load_imem test_4t_v2.hex
python lab9reg.py mode 1
python lab9reg.py fifo_read 1 1
```

> MOUSE: Point at BRAM[1] value -- "before CPU"
> PAUSE 2 sec

```bash
python lab9reg.py cpu_start
```

> PAUSE 1 sec

```bash
python lab9reg.py cpu_status
python lab9reg.py cpu_stop
python lab9reg.py fifo_read 1 1
```

> MOUSE: Point at BRAM[1] -- lower 32 bits changed by +0x2A
> PAUSE 3 sec

##### E3: GPU processes the CPU-modified data (vec_add_i16)

```bash
python lab9reg.py mode 2
python lab9reg.py gpu_load_imem vec_add_i16.hex
python lab9reg.py dma_fifo_to_gpu 1 0 7
python lab9reg.py gpu_start
```

> PAUSE 1 sec

```bash
python lab9reg.py gpu_status
python lab9reg.py gpu_stop
python lab9reg.py gpu_read_dmem 0 3
```

> MOUSE: Point at DMEM[0] -- this is the CPU-modified BRAM[1] data
>   Point at DMEM[2] -- GPU result computed from CPU-modified data
>   This proves: packet -> CPU modify -> GPU compute -> all chained
> PAUSE 5 sec -- highlight of the stress test

##### E4: DMA back and drain

```bash
python lab9reg.py dma_gpu_to_fifo 0 1 7
python lab9reg.py fifo_read 0 8
```

> MOUSE: Point at the final BRAM contents -- both CPU and GPU modifications visible
> PAUSE 3 sec

```bash
python lab9reg.py packet_echo 01
```

> PAUSE 2 sec

---

### [~9:00] Test F — ANN Inference on Real Packet Data (~60 sec)

This is new for Lab 9: run the trained neural networks on actual captured
packet data, proving end-to-end ML inference on real network traffic.

> MOUSE: Brief pause to signal "new section"
> PAUSE 2 sec

##### F1: Capture fresh packet

```bash
python lab9reg.py reset
```

> PAUSE 3 sec

```bash
python lab9reg.py status
```

> MOUSE: Point at `pkt_ready=1`

##### F2: Run both ANN tests (automated)

```bash
python lab9reg.py test_all_real_pkt
```

> This runs both ANN networks automatically. Each test:
>   1. Reads BRAM[1] as 4x BF16 input (from real ARP packet)
>   2. PCI-direct reference run (expected output)
>   3. DMA path (weights via PCI, input via DMA from packet)
>   4. Verifies DMA result matches PCI-direct reference
>   5. Verifies BRAM round-trip
>
> MOUSE: As output scrolls, point at key lines:
>   1. "Input as 4x BF16" -- show the raw packet data interpreted as BF16
>   2. "Reference DMEM[7]" -- the expected ANN output
>   3. "DMA vs PCI-direct: MATCH" -- proves DMA path works
>   4. "BRAM round-trip: MATCH" -- proves full round-trip
>   5. "*** PASS ***" for each test
>   6. "Real Packet ANN Tests: 2/2 passed" -- final score
> PAUSE 5 sec on each PASS, 3 sec on final score

---

### [~10:00] Closing (~10 sec)

> PAUSE 3 sec on clean terminal
> End of demo

---

## STOP RECORDING

---

## Timing Summary (for audio sync reference)

| Timestamp | Section | Key visual |
|-----------|---------|-----------|
| 0:00 | Opening | `ls` file listing, node0 ifconfig |
| 0:15 | Test A: Capture | `fifo_read` packet dump, ctrl=0xff |
| 0:45 | Test B: Echo | `packet_echo` output, dst_port rewrite |
| 1:05 | Test C: CPU | BRAM[1] before/after, +42 difference |
| 2:05 | Test D1: vec_add | Manual GPU steps, DMEM[2] = add result |
| 3:35 | Test D2: vec_sub | DMEM[2] = sub result |
| 4:35 | Test D3: bf16_mul | DMEM[2] = BF16 product |
| 5:35 | Test D4: bf16_fma | DMEM[3] = FMA result |
| 6:35 | Test D5: relu_i16 | DMEM[1] = ReLU result |
| 7:30 | Test E: Stress | CPU+GPU back-to-back on same packet |
| 9:00 | Test F: ANN | Real packet ANN inference, 2/2 pass |
| 10:00 | Closing | Clean terminal |

**Total estimated: ~10 minutes**

Note: cpu_load_imem takes ~30 sec each time. Timestamps above are estimates
and will drift. Use the visual markers (status output, DMEM dumps) to sync
audio, not exact timestamps.

---

## If Things Go Wrong During Recording

| Problem | Quick fix (stay on camera) |
|---------|--------------------------|
| `pkt_ready=0` after reset | Wait a few more seconds, or run `ping -c 1 10.0.0.2` on node0 tab |
| `kernel_done` not set | `python lab9reg.py gpu_stop`, then `python lab9reg.py gpu_start` and re-check |
| DMA hangs | `python lab9reg.py gpu_stop`, `python lab9reg.py mode 0`, `python lab9reg.py reset`, restart this kernel |
| Wrong BRAM/DMEM values | Doesn't matter for demo -- the point is showing the pipeline works |
| cpu_load_imem takes long | Normal (~30 sec). Just wait. |
| Terminal disconnects | Re-SSH, `cd ~/lab9_integration`, continue from last test |
| ANN test says "No packet" | Run `python lab9reg.py reset`, wait for ARP, then re-run `test_all_real_pkt` |
