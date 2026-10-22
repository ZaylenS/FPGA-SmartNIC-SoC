# Lab 10 Refinements: IDS MLP on Network Processor

## Context

Lab 10 refines the Lab 8/9 network processor (ARM CPU + GPU coprocessor + convertible FIFO on NetFPGA VP50) toward the final project: **ML-based Network Intrusion Detection (IDS)**. The core hardware is complete and verified (9/9 tests pass, March 20-21 2026). Lab 10 adds the IDS inference pipeline: packetize parameters, run MLP inference on the GPU, return results as packets, and measure performance.

The final project uses an **11-16-8-2 MLP** (346 parameters, 97 DMEM words for packed weights) trained on NSL-KDD for traffic-level classification. Professor Cho approved the IDS direction (meeting 2026-03-26), framing it as traffic-level ML (not DPI), targeting IoT/edge deployment.

---

## Lab 10 Requirements Status

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 1 | Packetize ANN params + test data, send to NetFPGA | **~90%** | **`send_ids.py` sends 11 BF16 features via UDP; batch CSV with 0.5s delay**; `lab10reg.py ids_batch_packets` orchestrates |
| 2 | Firmware + hardware processes packets, computes inference | **~90%** | **IDS kernel sim-verified, trained on NSL-KDD, batch packet pipeline with mode-correct FIFO handling** |
| 3 | Collect outputs into network packets, send out | **~85%** | **Response packet formed by swapping headers + writing result, drain to node0**; needs hardware verification |
| 4 | Scripts to process output packets for analysis | **~60%** | **`ids_batch_packets` outputs confusion matrix, accuracy, precision/recall, results CSV**; no output-packet parsing yet |
| 5 | Performance evaluation mechanisms | **~25%** | **Per-sample inference timing in batch results**; no hardware cycle counters |

---

## Completed: IDS GPU Kernel (11-16-8-2 MLP)

### Architecture Decision: Firmware-Only, Scalar SIMD Mode

**Key finding**: The GPU's 4-lane SIMD operates element-wise (each lane independent), with no cross-lane operations (no broadcast, no horizontal sum). This creates an inter-layer data problem:

- **4-neuron parallel mode** packs 4 different neuron values into one register `{n3, n2, n1, n0}`. After Layer 1 stores this, Layer 2 cannot extract individual values to broadcast as inputs -- there is no BCAST instruction.
- **Scalar mode** replicates the same value across all 4 lanes `{v, v, v, v}`. All lanes compute identically. Inter-layer data stays replicated automatically.

A second issue: **ADDI only increments lane 0** (the 64-bit immediate `1` splits as `{0,0,0,1}` across 16-bit lanes). Must use `ADD Rd, Rs, R7` where R7 = `{1,1,1,1}` (set via MOVI) for uniform pointer arithmetic.

| Approach | Cycles | RTL Change | Feasible? |
|----------|--------|------------|-----------|
| 4-neuron parallel all layers | ~300 | BCAST (~20 lines) | Requires re-synthesis |
| Scalar + 2-neuron interleaving | **~2400** | **None** | **Implemented** |
| Scalar naive (no interleaving) | ~5000+ | None | Too slow |
| HSUM/DOT hardware | ~1300+ | 250-450 LUTs | Actually worse (serializes neurons) |
| Result forwarding | ~150 | ~1200 LUTs | Won't fit at 96% utilization |

**Decision**: Firmware-only scalar mode with 2-neuron interleaving. No RTL changes, no re-synthesis risk. The 8x gap vs BCAST is a strong performance comparison story for Requirement 5.

### Kernel Design

**File**: `programs/gpu/ann_ids_11_16_8_2.asm` (211 instructions)

**Register allocation** (inner loop):
```
R0  = zero (hardwired)          R7  = {1,1,1,1} increment constant
R1  = accumulator neuron A      R8  = weight pointer
R2  = weight temp A             R9  = input pointer / loop counter
R3  = input temp (shared)       R10 = (free for setup/teardown)
R4  = weight temp B             R11 = (free for setup/teardown)
R5  = accumulator neuron B      R12 = loop limit
R6  = (free for setup/teardown)
```

**Inner loop** (8 instructions, ~14 cycles/iteration for 2 FMAs):
```asm
loop:
    LD   R2, 0(R8)           # weight neuron A
    LD   R3, 0(R9)           # input (shared)
    ADD  R9, R9, R7          # input ptr++ EARLY (hides BLT stall)
    LD   R4, S(R8)           # weight neuron B (stride S)
    FMA  R1, R2, R3, R1      # acc_A += w_A * x
    FMA  R5, R4, R3, R5      # acc_B += w_B * x (independent, no stall)
    ADD  R8, R8, R7          # weight ptr++
    BLT  R9, R12, loop       # R9 already updated, no stall
```

**Stall analysis** (no result forwarding, stall-only hazard resolution):
- LD R2 -> FMA R1: 4-cycle stall (LD result at WB, must exit before FMA reads)
- FMA R1 -> FMA R5: **0 stall** (independent accumulators, LD R4 exits WB just in time)
- ADDI R9 placed early: BLT reads R9 ~6 cycles after ADD, no stall
- Net: ~14 cycles per iteration = 7 cycles/FMA

**Layer breakdown**:
| Layer | Neurons | Groups of 2 | Inputs | Iterations | Cycles |
|-------|---------|-------------|--------|------------|--------|
| 1: 11->16 | 16 | 8 | 11 | 88 | ~1350 |
| 2: 16->8 | 8 | 4 | 16 | 64 | ~980 |
| 3: 8->2 | 2 | 1 | 8 | 8 | ~140 |
| **Total** | | **13** | | **160** | **~2400** |

### DMEM Layout (383 words, all replicated across 4 BF16 lanes)

```
Address     Content                                    Words
[0..10]     Input features x[0..10]                    11
[11..186]   L1 weights w1[n][i] @ 11 + n*11 + i       176
[187..202]  L1 biases b1[0..15]                        16
[203..218]  L1 output h1[0..15] (= L2 input)           16
[219..346]  L2 weights w2[n][i] @ 219 + n*16 + i       128
[347..354]  L2 biases b2[0..7]                         8
[355..362]  L2 output h2[0..7] (= L3 input)            8
[363..378]  L3 weights w3[n][i] @ 363 + n*8 + i        16
[379..380]  L3 biases b3[0..1]                         2
[381..382]  L3 output out[0..1]                        2
Total: 383 / 1024 (37.4%)
```

### Simulation Results

**Testbenches**: `tb/tb_ids_inference.v` (hardcoded expected), `tb/tb_ids_generic.v` (file-based expected)

| Test Case | Cycles | L1 (16) | L2 (8) | L3 (2) | Result |
|-----------|--------|---------|--------|--------|--------|
| Simple (w=0.25, b=0, x=1.0) | 2402 | 16/16 | 8/8 | 2/2 | **26/26 PASS** |
| Random (seed=42, x=1.0) | 2402 | 16/16 | 8/8 | 2/2 | **26/26 PASS** |

**Build/run**:
```bash
# Assemble
python toolchains/gpu/assembler.py programs/gpu/ann_ids_11_16_8_2.asm

# Generate data (--test for simple, omit for random)
python toolchains/gpu/ids_data_generator.py --test -o programs/gpu/data_ids_11_16_8_2.hex
python toolchains/gpu/ids_gen_expected_hex.py programs/gpu/data_ids_11_16_8_2_expected.txt \
       -o programs/gpu/expected_ids.hex

# Simulate
iverilog -g2001 -I include -I src/gpu -o tb_ids src/gpu/*.v tb/tb_ids_inference.v
vvp tb_ids
```

### Files Created

| File | Purpose |
|------|---------|
| `programs/gpu/ann_ids_11_16_8_2.asm` | IDS kernel assembly (211 instructions) |
| `programs/gpu/ann_ids_11_16_8_2.hex` | Assembled kernel hex |
| `programs/gpu/data_ids_11_16_8_2.hex` | Test DMEM data (simple weights) |
| `programs/gpu/data_ids_random.hex` | Test DMEM data (random weights, seed=42) |
| `programs/gpu/expected_ids.hex` | Expected outputs for generic testbench |
| `toolchains/gpu/ids_data_generator.py` | Data generator (weights -> DMEM hex + reference) |
| `toolchains/gpu/ids_gen_expected_hex.py` | Helper: expected.txt -> expected.hex |
| `tb/tb_ids_inference.v` | Standalone GPU testbench (hardcoded expected) |
| `tb/tb_ids_generic.v` | Generic testbench (file-based expected) |

---

## Completed: NSL-KDD Training and Deployment Script

### Training Pipeline (`scripts/train_ids.py`)

1. **Dataset**: NSL-KDD (125,973 train / 22,544 test samples), downloaded automatically
2. **Feature selection**: Random Forest importance, top 11 numeric features:
   - `src_bytes` (0.2017), `dst_bytes` (0.1236), `same_srv_rate` (0.0826)
   - `diff_srv_rate` (0.0672), `dst_host_same_srv_rate` (0.0598), `logged_in` (0.0592)
   - `dst_host_srv_count` (0.0523), `dst_host_diff_srv_rate` (0.0423)
   - `dst_host_srv_serror_rate` (0.0400), `dst_host_same_src_port_rate` (0.0381), `count` (0.0336)
3. **Normalization**: min-max to [0, 1] on training set, clipped for test set
4. **Training**: SGD + momentum (lr=0.01, 50 epochs, batch=256), Xavier init
5. **Accuracy**: 96.1% train, 73.7% test (float32); **75.8% test (BF16-quantized)**
6. **BF16 reference**: FMA-style single truncation matches hardware exactly (26/26 sim pass)

### Deployment Script (`scripts/lab10reg.py`)

| Command | Description |
|---------|-------------|
| `ids_load` | Load IDS kernel + trained weights into GPU IMEM/DMEM |
| `ids_infer [hex]` | Single inference on 11 BF16 features (underscore-separated) |
| `ids_test` | Run test with default trained data (attack sample, should classify as attack) |
| `ids_batch <csv>` | Batch inference on CSV of normalized features, saves results |
| `ids_status` | Show GPU status + last inference result |

Also forwards all `lab9reg.py` commands (status, gpu_*, dma_*, etc.).

### Training Files

| File | Purpose |
|------|---------|
| `scripts/train_ids.py` | Training pipeline (download, select, train, export) |
| `scripts/lab10reg.py` | Deployment script for NetFPGA hardware |
| `datasets/KDDTrain+.txt` | NSL-KDD training data (125,973 samples) |
| `datasets/KDDTest+.txt` | NSL-KDD test data (22,544 samples) |
| `programs/gpu/data_ids_trained.hex` | Trained DMEM hex (default attack sample) |
| `programs/gpu/data_ids_trained_weights.json` | Trained weights + feature selection + normalization params |
| `programs/gpu/expected_ids_trained.hex` | Expected outputs for simulation verification |

---

## Completed: Packet-Based Feature Sending (Task #3)

### End-to-End Packet Flow

```
node0 (nf6.usc.edu)                    NetFPGA (nf5.usc.edu)
====================                    ======================

python send_ids.py                      python lab10reg.py ids_load
  |                                       |
  | 11 normalized floats                  | Loads kernel (211 instr) +
  | -> BF16 conversion                   | trained weights (383 DMEM words)
  | -> 6-byte padding + 24 bytes         |
  | -> UDP to 10.0.0.2:9999              |
  |                                       |
  +------------ UDP packet ------------->  FIFO BRAM
                                           |
                                         python lab10reg.py ids_from_packet
                                           |
                                           | Read BRAM[7..9]: 11 BF16 features
                                           | Replicate each to {v,v,v,v}
                                           | Write to GPU DMEM[0..10]
                                           | Run kernel (2402 cycles)
                                           | Read DMEM[381..382]: logits
                                           | argmax -> normal/attack
                                           |
                                           v
                                         Classification result
```

### FIFO BRAM Packet Layout

```
BRAM[0]:     NF2.1 header (ctrl=0xFF, dst/src ports, lengths)
BRAM[1-6]:   Ethernet (14) + IP (20) + UDP (8) + padding (6) = 48 bytes
BRAM[7]:     Features x[0..3]  (4 x BF16 = 8 bytes)
BRAM[8]:     Features x[4..7]  (4 x BF16 = 8 bytes)
BRAM[9]:     Features x[8..10] + pad (3 x BF16 + 1 zero = 8 bytes)
```

The 6-byte padding in the UDP payload aligns BF16 data to the BRAM[7] word boundary (42 bytes of Eth+IP+UDP headers + 6 padding = 48 = 6 x 8-byte words).

### Sender Script (`scripts/send_ids.py`)

| Mode | Command | Description |
|------|---------|-------------|
| Default | `python send_ids.py` | Send default attack sample |
| Manual | `python send_ids.py 0.1 0.2 ... (11 floats)` | Send specific features |
| Batch | `python send_ids.py --csv features.csv` | Send from CSV file |
| Batch+Norm | `python send_ids.py --csv raw.csv --norm` | Auto-normalize raw features |

### Receiver Commands (`scripts/lab10reg.py`)

| Command | Description |
|---------|-------------|
| `ids_from_packet` | Process single packet: read BRAM -> GPU -> classify |
| `ids_packet_loop [N]` | Auto-process loop: polls FIFO, classifies each packet |

### Test CSV Generator (`scripts/gen_test_csv.py`)

Extracts normalized feature vectors from NSL-KDD test set:
```bash
python scripts/gen_test_csv.py -n 20 -o scripts/test_features.csv
```
Output: CSV with 11 features + true_label column (10 normal, 10 attack).

### New Files

| File | Purpose |
|------|---------|
| `scripts/send_ids.py` | UDP sender: 11 BF16 features -> NetFPGA |
| `scripts/gen_test_csv.py` | Generate test CSV from NSL-KDD |
| `scripts/test_features.csv` | 20-sample test set (10 normal, 10 attack) |

---

## GPU Architecture Notes (for kernel design)

### SIMD Semantics
- **4-lane element-wise**: `MUL R3, R1, R2` computes `R3[i] = R1[i] * R2[i]` for each lane independently
- **FMA is element-wise** (not dot product): `FMA Rd, Rs1, Rs2, Rs3` computes `Rd[i] = Rs1[i]*Rs2[i] + Rs3[i]`
- **Only MOVI broadcasts**: `MOVI Rd, imm16` replicates the 16-bit immediate to all 4 lanes
- **No cross-lane operations**: no broadcast-from-register, no horizontal sum, no lane select

### Pipeline Hazards (No Forwarding)
- Every RAW dependency stalls until the producer exits WB
- LD -> use: 4 stall cycles
- FMA -> use: 4 stall cycles
- ALU -> use: 3 stall cycles
- Mitigation: interleave independent instructions to fill stall slots

### ADDI Lane Non-Uniformity
- `ADDI Rd, Rs, imm19` sign-extends the 19-bit immediate to 64 bits, then adds to each 16-bit lane
- For imm=1: 64-bit value = `0x0000_0000_0000_0001`, splits as `{0, 0, 0, 1}` across lanes
- Only lane 0 increments; other lanes get +0
- **Fix**: use `ADD Rd, Rs, R_one` where R_one = `{1,1,1,1}` (set via `MOVI R_one, 1`)

### BCAST Opportunity (Optional RTL Enhancement)
A `BCAST Rd, Rs, lane_sel` instruction (~20 lines Verilog, ~50 LUTs) would:
- Copy one lane of Rs to all lanes of Rd
- Enable 4-neuron parallel mode for all layers (not just the first)
- Reduce inference from ~2400 to ~300 cycles (8x speedup)
- Eliminate DMEM replication (383 -> ~109 words)
- Great "before/after" story for performance evaluation (Requirement 5)

---

## Implementation Plan: Remaining Lab 10 Work

### Phase A: IDS Core (P0 -- Blocking)

| # | Task | Status | Details |
|---|------|--------|---------|
| 1 | Adapt GPU kernel for IDS MLP (11->16->8->2) | **DONE** | `ann_ids_11_16_8_2.asm`, 211 instructions, sim-verified |
| 2 | Train IDS model on NSL-KDD, export BF16 weights | **DONE** | `train_ids.py`: 11 features by RF importance, 75.8% BF16 accuracy, 26/26 sim pass |
| 3 | Script to packetize weights + test data, send to NetFPGA | **DONE** | `send_ids.py` (sender), `lab10reg.py ids_from_packet` (receiver), batch CSV via `--csv` |

### Phase B: End-to-End Pipeline (P1 -- Critical for Demo)

| # | Task | Status | Details |
|---|------|--------|---------|
| 4 | Batch inference orchestration script | **DONE** | `ids_batch_packets` command: mode-correct packet loop, ARP filtering, per-sample timing, confusion matrix, results CSV |
| 5 | Output packet formation | **DONE** | `_form_and_drain_response()`: swap src/dst MAC+IP+UDP, write result at BRAM[7], drain via MAC0 |
| 6 | Receive/capture script on node0 | TODO | Script on nf6 to capture output packets, parse NF2.1 headers, extract BF16 results |
| 7 | Output analysis script | TODO | Compare predicted vs actual, confusion matrix, CSV export |
| 8 | Software timing instrumentation | TODO | `time.time()` around DMA in, kernel, DMA out, total; batch throughput |

### Phase C: Performance & Optimization (P2 -- For Complete Submission)

| # | Task | Status | Details |
|---|------|--------|---------|
| 9 | Hardware cycle counter register | TODO | 32-bit counter in `gpu_top.v`, expose via register map BASE+0x30 |
| 10 | Application-specific simplification (P5) | TODO | IDS uses BF16 only; can INT16 ALU be removed to reduce slices from 96%? |
| 11 | NSL-KDD feature extraction script | TODO | Extract 11 features, normalize, convert to BF16, format as packets |
| 12 | "Why SoC beats Fortinet" pitch | TODO | Prof Cho asked; prepare: lower cost, IoT edge, gap Fortinet doesn't serve |

### Phase D: Cleanup (P3 -- Polish)

| # | Task | Status | Details |
|---|------|--------|---------|
| 13 | Mode-switch safety guard (P9) | TODO | ~5 lines: gate mode changes by `cpu_running \|\| gpu_running \|\| dma_active` |
| 14 | DMA address bounds check (H5) | TODO | ~5-10 lines: detect overflow, set error status bit |
| 15 | Dead code deletion (L1) | TODO | Delete `src/arm/adder8_comb.v`, `full_adder.v` |
| 16 | Comment typo fixes (L2) | TODO | `[31:0]` -> `[63:32]` in `lab8_reg_defines.vh` |
| 17 | Docs cleanup (L3) | TODO | Mark P4, P7 as DONE in `improvements_and_optimizations.md` |

### Phase E: Deferred (P4 -- Only If Needed)

| # | Item | Reason to Defer |
|---|------|-----------------|
| 18 | Missing ARM opcodes (M1: ADC, SBC, RSB, RSC, CMN) | No program uses them |
| 19 | ROR #0 -> RRX (M3) | No program uses RRX |
| 20 | C_flag for logic ops (M4) | No program depends on carry |
| 21 | Registered PCI strobes (H4) | Only if future muxing added |
| 22 | Logic analyzer wrap indicator (L4) | Debug aid only |
| 23 | Dual-port GPU bandwidth (P1) | High risk, only if throughput bottleneck |
| 24 | BRAM register file + 2x DCM (P2) | Major change, only if timing demands |
| 25 | Behavioral->structural conversion (P3) | Not worth it at 96% utilization |
| 26 | Shared FIFO BRAM as scratchpad (P6) | High complexity |
| 27 | GPU decode pipeline split (P8) | High risk; P5 more effective |

### Suggested Execution Order

```
Phase A: IDS Core
  #1 [DONE] GPU kernel for 11-16-8-2 MLP
  #2 Train model, export BF16 weights
  #3 Packetize + send script

Phase B: End-to-End Pipeline
  #4 Batch inference orchestration
  #5 Output packet formation
  #6 Receive/capture script
  #7 Analysis script
  #8 Software timing

Phase C: Performance & Optimization
  #9  Hardware cycle counter
  #10 Application-specific simplification
  #11 NSL-KDD feature extraction

Phase D: Cleanup
  #13-17 Safety guards, dead code, docs

Phase E: Presentation Prep
  #12 "Why SoC" pitch for professor
```

---

## Known Constraints

- **96% slice utilization** -- any RTL addition risks not fitting
- **4816 timing violations** at 125 MHz (worst in GPU DECODE, 11ns vs 8ns budget)
- **No result forwarding** in GPU pipeline -- stall-only hazard resolution
- **Single-packet FIFO buffer** -- hardware blocks during GPU processing
- **Python 2.4+ on NetFPGA** -- no ternary, no `with`, no f-strings in deployment scripts
