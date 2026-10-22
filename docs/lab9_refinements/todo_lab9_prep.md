# TODO: Lab 9 Preparation

Two items to work on before Lab 9 integration with another subgroup.

---

## TODO 1: Real Network Packet ANN Inference Test -- DONE

**Status:** Hardware verified on nf5.usc.edu, March 21 2026. 2/2 PASS.

**Approach:** Hybrid -- weights loaded via PCI to GPU DMEM[1-6], packet data
(BRAM[1]) DMA'd to GPU DMEM[0] as ANN input. A PCI-direct reference run
computes the expected output first, then the DMA path is verified to match.

### New Commands

```
test_ann_real_pkt               ANN handcrafted on real packet data
test_ann_trained_real_pkt       ANN trained on real packet data
test_all_real_pkt               Run both real-packet ANN tests
```

### Verification Strategy

Each test runs two passes on the same packet data:
1. **PCI-direct reference**: write BRAM[1] data to DMEM[0] via PCI, run kernel,
   read DMEM[7] -> this is the expected result
2. **DMA path**: DMA BRAM[1] -> DMEM[0], run kernel, read DMEM[7], DMA back to
   BRAM[1-8] -> verify DMEM[7] matches reference AND BRAM[8] matches DMEM[7]

PASS = DMA result matches PCI-direct reference AND BRAM round-trip matches.

### Hardware Test Instructions

**Prerequisites:**
- FPGA programmed with latest bitfile (nf2_top_par.bit, March 20 2026)
- Files deployed to nf5.usc.edu:
  ```
  scp scripts/lab8reg.py root@nf5.usc.edu:~/
  scp programs/ann_3layer_relu.hex root@nf5.usc.edu:~/
  scp programs/data_ann_handcrafted.hex root@nf5.usc.edu:~/
  scp programs/data_ann_trained.hex root@nf5.usc.edu:~/
  ```

**Step-by-step on nf5.usc.edu:**
```bash
# 1. Program FPGA (if not already done)
nf2_download nf2_top_par.bit

# 2. Reset FIFO and wait for ARP packet from node0 (nf6.usc.edu)
python lab8reg.py reset
python lab8reg.py status          # wait until pkt_ready=1

# 3. Inspect captured packet
python lab8reg.py fifo_read 0 8

# 4. Run real-packet ANN tests (both networks)
python lab8reg.py test_all_real_pkt

# 5. Or run individually:
python lab8reg.py test_ann_real_pkt
python lab8reg.py test_ann_trained_real_pkt
```

**If no packet arrives within ~30 seconds:**
```bash
# On node0 (nf6.usc.edu), generate ARP traffic:
ping -c 1 10.0.0.2
# Then on nf5: python lab8reg.py status
```

### What the Output Looks Like

The test prints the captured packet data interpreted as 4x BF16 values, runs
both PCI-direct and DMA paths, and compares:
```
=== ANN handcrafted (real packet input) (real packet) ===
  1. Checking for captured packet...
     Packet ready: 8 words
  2. Reading packet input (BRAM[1])...
     BRAM[1]: ctrl=0x00  data=0xXXXXXXXX_XXXXXXXX  (ANN input)
     Input as 4x BF16: [0xXXXX, 0xXXXX, 0xXXXX, 0xXXXX]
  3. PCI-direct reference run...
     Reference DMEM[7] = 0xXXXXXXXX_XXXXXXXX
  ...
  10. Verification:
      DMA vs PCI-direct: MATCH
      BRAM round-trip:   MATCH
  *** PASS ***
```

---

## TODO 2: Behavioral-to-Structural Conversion Analysis

**Goal:** Determine which parts of the design are worth converting to structural
Verilog (explicit primitive instantiation or schematic-drawn in ISE 10.1).

### Current Design Stats (from synthesis)
- Slices: 20,963 / 21,760 (96% -- very tight)
- RAMB16: 108 / 232 (47% -- plenty of headroom)
- MULT18X18: 12 / 232 (5% -- almost entirely unused)
- DCM: 6 / 8 (75%)
- Critical path: -3.958ns slack on core_clk_int (125 MHz), 72% routing-bound

### Candidate Assessment

| Module | File(s) | Worth It? | Why |
|--------|---------|-----------|-----|
| **FIFO BRAM (256x72)** | `fifo_bram.v` | **No** | Inference works perfectly. Not on critical path. RAMB16_S36_S36 instantiation adds maintenance burden for zero timing gain. |
| **Int16 ALU Multiplier (16x16)** | `int16_alu.v` | **Maybe** | Combinational multiply feeds into EX stage shift+ALU. Explicit MULT18X18 with LOC constraints could save ~0.5ns by co-locating with consuming logic. But 96% slice utilization limits placement flexibility. |
| **BF16 ALU Multiplier (8x8)** | `bf16_alu.v` | **No** | Already 2-cycle pipelined. Structural won't improve. |
| **BF16 FMA Multiplier (8x8)** | `bf16_fma_unit.v` | **No** | Already pipelined in EX stages. Not timing-critical. |
| **Proc Port MUX (3-way)** | `lab8_wrapper.v` | **No** | Behavioral mux maps cleanly to LUT/F6MUX. Not a timing bottleneck. Structural primitives would hurt readability. |
| **ARM Register File** | (distributed RAM) | **Maybe** | Convert to BRAM-based with DCM 2x clock (P2 in improvements doc). Frees ~2,200 LUTs. But requires DCM and careful timing. |
| **GPU Register File** | `register_file.v` | **Maybe** | Same as ARM -- BRAM-based saves LUTs. GPU has simpler port requirements (1R1W per cycle). |

### Key Insight: Routing Congestion is the Real Problem

The critical path is **72% routing delay** (only 28% logic). This means the
design is too packed -- ISE cannot find short routing paths. Structural conversion
of individual modules won't fix this. What helps:

1. **Reduce slice count** (P5: remove BF16 if app doesn't need it -> ~1000+ LUTs freed)
2. **Move FFs to BRAM** (P2: register files -> BRAM -> ~2200 LUTs freed)
3. **Then** structural MULT18X18 placement makes sense (LOC constraints work when
   there's routing slack)

### Recommendation

**For Lab 9, structural conversion is NOT the highest-value work.** The design
works and is hardware-verified. The 4816 timing violations are real but do not
cause functional failures at current test conditions.

If you want to demonstrate structural knowledge for the course:
- **Best candidate: FIFO BRAM** -- simple, self-contained, easy to draw as schematic
  (256x72 dual-port = 4x RAMB16_S36_S36 stitched). Good for showing you understand
  VP50 BRAM primitives, even though it won't improve timing.
- **Most impactful: Register file -> BRAM** (P2) -- actually reduces slice pressure
  and demonstrates DCM usage. More complex but higher reward.

### Schematic vs. Hand-Written Structural

Two paths to structural Verilog on ISE 10.1 (WinXP VM):
- **Schematic (ECS):** Draw in ISE schematic editor -> File > Export > Verilog Netlist.
  Good for: BRAM configurations, simple datapaths. Produces `.vf` files (like
  the deleted `adder8_comb.v` and `full_adder.v` from Lab 2).
- **Hand-written:** Instantiate primitives directly in `.v` files (e.g.,
  `RAMB16_S36_S36 #(.INIT_A(...)) u_bram (...)`). More flexible, version-controllable.

Either approach works. Schematic is visual and good for demos; hand-written is
more maintainable.
