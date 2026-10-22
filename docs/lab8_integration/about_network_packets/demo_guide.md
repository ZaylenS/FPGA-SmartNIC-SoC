# Lab 8 Demo Recording Guide

**Group 12** — Zilin Shao, YungChing Chang, Parker Chang
**FPGA node:** Team 5, `netfpga@nf5.usc.edu`

---

## Pre-Demo Setup

### 1. SSH into FPGA node

```bash
ssh netfpga@nf5.usc.edu
```

### 2. Load bitfile and navigate to working directory

```bash
nf_download ~/integration_lab8/nf2_top_par.bit
cd ~/integration_lab8
```

### 3. Verify link to node0

On a second terminal, SSH to node0:

```bash
ssh node0@nf6.usc.edu
# node0's port0 is at 10.0.0.3, FPGA nf2c0 is at 10.0.0.2
```

### 4. Kernel files on FPGA

These should already be in `~/integration_lab8/`:

| File | Kernel | What it does |
|------|--------|-------------|
| `vec_add_i16.hex` | INT16 vector add | v2 = v0 + v1 (4 lanes, 16-bit wrapping) |
| `vec_sub_i16.hex` | INT16 vector sub | v2 = v0 - v1 (4 lanes, 16-bit wrapping) |
| `bf16_mul.hex` | BFloat16 multiply | v2 = v0 * v1 (4 lanes, BF16) |
| `bf16_fma.hex` | BFloat16 fused multiply-add | v3 = v0 * v1 + v2 (4 lanes, BF16) |
| `relu_i16.hex` | INT16 ReLU activation | v1 = max(v0, 0) (4 lanes) |

Also need `test_4t_v2.hex` for the CPU test.

---

## Test Sequence: A, B, C, D

### Test A — Packet Capture and Inspection

**What to say:** "First we reset the FIFO and wait for a real network packet to arrive from node0. The FIFO automatically detects the packet boundary by reading the ctrl bits — ctrl=0xFF marks the module header, and the word_length field tells it how many words to expect. Once all words are received, the FIFO asserts pkt_ready and backpressures the input."

```bash
./lab8reg reset
# Wait a few seconds for ARP traffic to arrive
./lab8reg status
```

Expected: `pkt_ready=1`, `pkt_word_cnt=8`, `mode=0 (FIFO)`

```bash
./lab8reg fifo_read 0 8
```

Expected output — an ARP packet (8 words):
- BRAM[0]: ctrl=0xff, module header (dst_port=0x0002, word_len=8, byte_len=60)
- BRAM[1]: ctrl=0x00, Ethernet dst FF:FF:FF:FF:FF:FF (broadcast)
- BRAM[2]: ctrl=0x00, Ethernet src + EtherType 0x0806 (ARP)
- BRAM[3..7]: ARP payload + padding

**What to say:** "The captured packet is an ARP request — node0 is trying to resolve our FPGA's MAC address. We can see the NF2.1 module header at BRAM[0] with ctrl=0xFF, and 7 data words with ctrl=0x00. The FIFO correctly detected the packet boundaries."

### Test B — Packet Echo (Header Rewrite + Drain)

**What to say:** "Now we rewrite the module header to change the destination port from CPU queue (0x0002) to MAC0 (0x0001), so the packet gets sent back out the physical Ethernet port to node0. The PCI write path preserves the ctrl=0xFF byte, which is required for the output queues to recognize this as a valid header. Then we drain the packet."

```bash
./lab8reg packet_echo 01
```

Expected: header rewrite confirmation (dst_port 0x0002 -> 0x0001, ctrl=0xff preserved), drain triggered.

**What to say:** "The packet has been drained back through the NF2.1 output queues to MAC0. The FIFO returns to empty state."

```bash
./lab8reg status
```

Expected: `pkt_ready=0`, `fifo_empty=1`

### Test C — ARM CPU Modifies Packet Data

**What to say:** "Next we demonstrate the ARM CPU processing a network packet. We capture a new packet, then switch to CPU mode. The CPU reads a data word from the FIFO BRAM, adds 42 to it, and writes the result back. This shows the CPU can perform computation on real packet data."

```bash
# Capture a new packet
./lab8reg reset
# Wait a few seconds
./lab8reg status
# Should show pkt_ready=1
```

```bash
# Read BRAM[1] before CPU — note the lower 32 bits
./lab8reg fifo_read 1 1
```

```bash
# Load CPU program, run it, verify
./lab8reg cpu_load_imem test_4t_v2.hex
./lab8reg mode 1
./lab8reg fifo_read 1 1
# Note: value may differ from initial read if Bug #2 (in_rdy not gated) overwrote it during IMEM load
```

```bash
# Start CPU, wait for halt, stop
./lab8reg cpu_start
# Wait ~1 second
./lab8reg cpu_status
# Should show all_halted=1
./lab8reg cpu_stop
```

```bash
# Read BRAM[1] after CPU — lower 32 bits should be +42 (0x2A)
./lab8reg fifo_read 1 1
```

**What to say:** "The lower 32 bits of BRAM[1] changed by exactly 42 (0x2A in hex). The CPU correctly read the packet data from FIFO BRAM, performed arithmetic on it, and wrote the result back. The upper 32 bits are unchanged because our ARM CPU has 32-bit registers."

```bash
# Echo the modified packet back out
./lab8reg packet_echo 01
```

**Alternative (automated):** If the manual sequence is tricky with timing, use the integrated `cpu_test` command instead — but note this writes a synthetic value (0x1000) to BRAM[1] rather than using the captured packet data. For the demo, the manual sequence above is more impressive since it modifies real packet data.

### Test D — GPU CUDA Kernels on Packet Data (5 kernels)

**What to say:** "Finally, we demonstrate our GPU coprocessor running CUDA-style kernels on real network packet data. Our GPU is a 4-lane SIMD processor with 64-bit registers — each register holds four 16-bit integers or four BFloat16 values. We use DMA to copy packet data from the FIFO BRAM to the GPU's data memory, run a kernel, then DMA the results back. We'll demonstrate all five kernels."

For each kernel, the sequence is:

1. Reset FIFO, wait for new packet
2. Run `gpu_test <kernel.hex>`

#### D1 — vec_add_i16 (INT16 vector addition)

**What to say:** "The first kernel is vec_add_i16 — SIMD integer addition. It loads two 64-bit words from the packet, treats each as four 16-bit integers, adds them lane-by-lane with 16-bit wrapping, and stores the result."

```bash
./lab8reg reset
# Wait for packet
./lab8reg status
./lab8reg gpu_test vec_add_i16.hex
```

**What to verify:** DMEM[2] / BRAM[3] should be the lane-by-lane 16-bit sum of BRAM[1] and BRAM[2]. Example from previous test:

```
BRAM[1]: FFFF FFFF FFFF A036
BRAM[2]: 9F0A 106B 0806 0001
Result:  9F09 106A 0805 A037   (each lane wraps at 16 bits)
```

#### D2 — vec_sub_i16 (INT16 vector subtraction)

**What to say:** "Next, vec_sub_i16 — same structure but subtraction. v2 = v0 - v1."

```bash
./lab8reg reset
# Wait for packet
./lab8reg status
./lab8reg gpu_test vec_sub_i16.hex
```

**What to verify:** BRAM[3] should be lane-by-lane 16-bit difference of BRAM[1] minus BRAM[2].

#### D3 — bf16_mul (BFloat16 multiplication)

**What to say:** "bf16_mul performs BFloat16 floating-point multiplication. BFloat16 is a 16-bit format used in machine learning — same exponent range as IEEE 754 float32 but with reduced mantissa precision. Our GPU implements this in hardware."

```bash
./lab8reg reset
# Wait for packet
./lab8reg status
./lab8reg gpu_test bf16_mul.hex
```

**What to verify:** BRAM[3] should be lane-by-lane BF16 product of BRAM[1] and BRAM[2]. The raw packet bytes interpreted as BF16 will produce some floating-point result (the arithmetic correctness was verified in Lab 7 simulation).

#### D4 — bf16_fma (BFloat16 fused multiply-add)

**What to say:** "bf16_fma is fused multiply-add — the core operation in neural network inference. It computes v3 = v0 * v1 + v2 in a single fused operation, which is more accurate than separate multiply and add. This kernel uses 6 instructions including three VLOADs."

```bash
./lab8reg reset
# Wait for packet
./lab8reg status
./lab8reg gpu_test bf16_fma.hex
```

**What to verify:** BRAM[4] (DMEM[3]) should contain the FMA result. Note this kernel stores to DMEM[3] not DMEM[2].

#### D5 — relu_i16 (INT16 ReLU activation)

**What to say:** "The last kernel is relu_i16 — the ReLU activation function, max(x, 0). This is the most common activation in deep learning. Each 16-bit lane is independently clamped to zero if negative."

```bash
./lab8reg reset
# Wait for packet
./lab8reg status
./lab8reg gpu_test relu_i16.hex
```

**What to verify:** BRAM[2] (DMEM[1]) should have each lane clamped: negative int16 values become 0, positive values unchanged. Since ARP packet bytes are mostly positive when interpreted as int16, most lanes will pass through unchanged. Lanes with values >= 0x8000 (negative in signed int16) will become 0.

---

## Closing Statement

**What to say:** "In summary, we demonstrated the full data path of our network processor: real packets arrive from the Ethernet, get captured by the FIFO with automatic boundary detection, can be processed by either the ARM CPU or the GPU SIMD coprocessor, and are then routed back out through the NF2.1 output queues. We ran all five GPU kernels — integer add, integer subtract, BFloat16 multiply, BFloat16 fused multiply-add, and ReLU activation — on real network packet data, demonstrating that our design can execute CUDA-style kernels on the NetFPGA hardware."

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `pkt_ready=0` after reset | Wait a few more seconds. If still empty, run `ping -c 1 10.0.0.2` from node0 terminal to generate ARP traffic. |
| BRAM[1] shows unexpected value after `cpu_load_imem` | Bug #2 (in_rdy not gated by mode). Network packet overwrote BRAM during IMEM load. Just re-read — the CPU still adds 42 to whatever value is there. |
| `kernel_done not set` in gpu_test | GPU may be stuck. Run `./lab8reg gpu_stop` then retry. Check `gpu_status`. |
| `packet_echo` says "No packet in FIFO" | Packet was already drained or FIFO was reset. Capture a new one first. |
| node0 says "Destination Host Unreachable" on ping | Expected. Our FIFO captures the ARP and never forwards it, so node0 can't resolve the MAC. This is fine — the ARP itself is our test packet. |

---

## Quick Reference — Command Cheat Sheet

```bash
# Setup
nf_download ~/integration_lab8/nf2_top_par.bit
cd ~/integration_lab8

# Test A: Capture
./lab8reg reset                          # reset FIFO
./lab8reg status                         # check pkt_ready
./lab8reg fifo_read 0 8                  # read captured packet

# Test B: Echo
./lab8reg packet_echo 01                 # rewrite dst_port + drain
./lab8reg status                         # verify empty

# Test C: CPU
./lab8reg reset                          # capture new packet
./lab8reg fifo_read 1 1                  # read BRAM[1] before
./lab8reg cpu_load_imem test_4t_v2.hex   # load CPU program
./lab8reg mode 1                         # CPU mode
./lab8reg fifo_read 1 1                  # read current value
./lab8reg cpu_start                      # run CPU
./lab8reg cpu_status                     # check all_halted
./lab8reg cpu_stop                       # stop CPU
./lab8reg fifo_read 1 1                  # read BRAM[1] after (+42)
./lab8reg packet_echo 01                 # drain modified packet

# Test D: GPU (repeat for each kernel)
./lab8reg reset                          # capture new packet
./lab8reg gpu_test vec_add_i16.hex       # kernel 1
./lab8reg reset && sleep 3 && ./lab8reg gpu_test vec_sub_i16.hex    # kernel 2
./lab8reg reset && sleep 3 && ./lab8reg gpu_test bf16_mul.hex       # kernel 3
./lab8reg reset && sleep 3 && ./lab8reg gpu_test bf16_fma.hex       # kernel 4
./lab8reg reset && sleep 3 && ./lab8reg gpu_test relu_i16.hex       # kernel 5
```
