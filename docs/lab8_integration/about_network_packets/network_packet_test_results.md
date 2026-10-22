# Lab 8 — Real Network Packet Test Results

**Group 12** — Zilin Shao, YungChing Chang, Parker Chang

---

## Test Environment

- **FPGA node:** Team 5, `netfpga@nf5.usc.edu`
- **Sub-node:** `node0@nf6.usc.edu`, connected to FPGA port nf2c0 (MAC0) via Intel GbE (`port0`)
- **Bitfile:** `nf2_top_par.bit` (Lab 8 network processor, synthesized March 6 2026)
- **Control script:** `lab8reg` (Perl, PCI register access via `regread`/`regwrite`)
- **IP addresses:** FPGA nf2c0 = 10.0.0.2, node0 port0 = 10.0.0.3

The Lab 8 design replaces the standard NF2 reference NIC data path with a convertible FIFO that captures one complete network packet, holds it for processing by the ARM CPU or GPU coprocessor, then drains it back out through the NF2.1 output queues.

---

## Test A — Packet Capture and Inspection

After loading the bitfile and resetting the FIFO, a packet from node0 (ARP broadcast) was captured automatically within a few seconds.

```
./lab8reg status
STATUS = 0x08000803
  pkt_ready=1  fifo_full=1  fifo_empty=0
  pkt_word_cnt=8  head=0  tail=8
  mode=0 (FIFO)
```

Reading the FIFO contents via PCI:

```
BRAM[  0]: ctrl=0xff  data=0x00020008_0000003c    ← NF2.1 module header
BRAM[  1]: ctrl=0x00  data=0xffffffff_ffffa036    ← Ethernet dst: FF:FF:FF:FF:FF:FF (broadcast)
BRAM[  2]: ctrl=0x00  data=0x9f0a106b_08060001    ← Ethernet src + EtherType 0x0806 (ARP)
BRAM[  3]: ctrl=0x00  data=0x08000604_0001a036    ← ARP: HW=Ethernet, Proto=IPv4, Op=Request
BRAM[  4]: ctrl=0x00  data=0x9f0a106b_0a000003    ← Sender MAC + Sender IP: 10.0.0.3
BRAM[  5]: ctrl=0x00  data=0x00000000_00000a00    ← Target MAC (zero) + Target IP start
BRAM[  6]: ctrl=0x00  data=0x00020000_00000000    ← Target IP: 10.0.0.2 + padding
BRAM[  7]: ctrl=0x00  data=0x00000000_00000000    ← padding
```

The module header decodes as:

| Field | Bits | Value | Meaning |
|-------|------|-------|---------|
| dst_port | [63:48] | 0x0002 | CPU0 (reference_nic routes incoming packets to CPU queue) |
| word_length | [47:32] | 0x0008 | 8 words total (header + 7 data words) |
| src_port | [31:16] | 0x0000 | Not set by output_port_lookup |
| byte_length | [15:0] | 0x003C | 60 bytes (minimum Ethernet frame, ARP) |

The captured packet is an ARP request from node0 (10.0.0.3, MAC A0:36:9F:0A:10:6B) asking "who has 10.0.0.2?" — confirming the FIFO correctly captured a real packet arriving on MAC port 0 from the physical Ethernet link.

---

## Test B — Packet Echo (Header Rewrite and Drain)

Using the `packet_echo` command, the module header's dst_port field was rewritten from 0x0002 (CPU queue) to 0x0001 (MAC0 output port), and the packet was drained back through the NF2.1 output queues:

```
./lab8reg packet_echo 01

5. Rewriting header: dst_port 0x0002 -> 0x0001 (ctrl=0xFF preserved)...
   Verify: ctrl=0xff  data=0x00010008_0000003c
6. Switching to FIFO mode and draining...
   Drain triggered.
```

The ctrl byte (0xFF) was preserved during the PCI write — this is required for the output queues to recognize the first word as a module header. The packet was drained to MAC0 for transmission back to node0.

---

## Test D — ARM CPU Modifies Packet Data

A new ARP packet was captured, then the ARM CPU modified the first data word (BRAM[1]).

The CPU program (`test_4t_v2.hex`) performs: load BRAM word 1 into register, add 42 (0x2A), store back.

**Before CPU:**
```
BRAM[  1]: ctrl=0x00  data=0xffffffff_ffffa036
```

**After CPU (add 42 to lower 32 bits):**
```
BRAM[  1]: ctrl=0x00  data=0xffffffff_ffffa060
```

Verification: `0xa060 - 0xa036 = 0x002A = 42`. The CPU correctly read the real packet data from FIFO BRAM, performed arithmetic, and wrote the result back.

The modified packet was then routed back to MAC0 via `packet_echo 01` (header rewrite + drain).

---

## Test D — GPU SIMD Processes Packet Data (5 Kernels)

For each kernel, a fresh ARP packet was captured, the DMA engine copied data words BRAM[1..7] to GPU DMEM[0..6], the kernel executed, and DMA copied results back to BRAM.

### D1: vec_add_i16 (INT16 vector addition)

```
VLOAD v0, DMEM[0]   ; VLOAD v1, DMEM[1]   ; VADD v2, v0, v1   ; VSTORE v2, DMEM[2]   ; HALT
```

| Lane | DMEM[0] (v0) | DMEM[1] (v1) | DMEM[2] (v2 = v0+v1) |
|------|-------------|-------------|---------------------|
| [63:48] | 0xFFFF | 0x9F0A | 0x9F09 |
| [47:32] | 0xFFFF | 0x106B | 0x106A |
| [31:16] | 0xFFFF | 0x0806 | 0x0805 |
| [15:0]  | 0xA036 | 0x0001 | 0xA037 |

All lanes correct (16-bit wrapping addition).

### D2: vec_sub_i16 (INT16 vector subtraction)

| Lane | DMEM[0] (v0) | DMEM[1] (v1) | DMEM[2] (v2 = v0-v1) |
|------|-------------|-------------|---------------------|
| [63:48] | 0xFFFF | 0x9F0A | 0x60F5 |
| [47:32] | 0xFFFF | 0x106B | 0xEF94 |
| [31:16] | 0xFFFF | 0x0806 | 0xF7F9 |
| [15:0]  | 0xA036 | 0x0001 | 0xA035 |

All lanes correct (16-bit wrapping subtraction).

### D3: bf16_mul (BFloat16 multiplication)

| Lane | DMEM[0] (v0) | DMEM[1] (v1) | DMEM[2] (v2 = v0*v1) |
|------|-------------|-------------|---------------------|
| [63:48] | 0xFFFF (NaN) | 0x9F0A | 0x7FC0 (NaN) |
| [47:32] | 0xFFFF (NaN) | 0x106B | 0x7FC0 (NaN) |
| [31:16] | 0xFFFF (NaN) | 0x0806 | 0x7FC0 (NaN) |
| [15:0]  | 0xA036 | 0x0001 | 0x8000 (-0) |

NaN * anything = NaN. Last lane: small negative * tiny denorm = negative zero.

### D4: bf16_fma (BFloat16 fused multiply-add)

```
VLOAD v0, DMEM[0]   ; VLOAD v1, DMEM[1]   ; VLOAD v2, DMEM[2]
VFMA  v3, v0, v1, v2   ; VSTORE v3, DMEM[3]   ; HALT
```

| Lane | Result (v3 = v0*v1+v2) |
|------|----------------------|
| [63:48] | 0x7FC0 (NaN) |
| [47:32] | 0x7FC0 (NaN) |
| [31:16] | 0x7FC0 (NaN) |
| [15:0]  | 0xA036 |

NaN propagates for first 3 lanes. Last lane: A036*0001 + A036 = -0 + A036 = A036.

### D5: relu_i16 (INT16 ReLU activation)

```
VLOAD v0, DMEM[0]   ; VRELU v1, v0   ; VSTORE v1, DMEM[1]   ; HALT
```

| Lane | DMEM[0] (v0) | DMEM[1] (v1 = max(v0,0)) |
|------|-------------|------------------------|
| [63:48] | 0xFFFF (-1) | 0x0000 |
| [47:32] | 0xFFFF (-1) | 0x0000 |
| [31:16] | 0xFFFF (-1) | 0x0000 |
| [15:0]  | 0xA036 (-24522) | 0x0000 |

All lanes are negative in signed int16 (bit[15]=1), all correctly clamped to zero.

---

## Summary

| Test | Operation | Verified |
|------|-----------|----------|
| A | FIFO captures real ARP packet from node0 via MAC0 | Packet contents decoded, match expected ARP format |
| B | PCI rewrites module header dst_port, preserves ctrl=0xFF, drains to MAC port | Header readback confirms 0x0002 -> 0x0001, ctrl intact |
| C | ARM CPU reads packet data word, adds 42, writes back | BRAM[1] low word: 0xa036 -> 0xa060 (diff = 0x2A) |
| D1 | GPU vec_add_i16 on packet data via DMA | DMEM[2] = int16 sum, all 4 lanes correct |
| D2 | GPU vec_sub_i16 on packet data via DMA | DMEM[2] = int16 diff, all 4 lanes correct |
| D3 | GPU bf16_mul on packet data via DMA | DMEM[2] = BF16 product, NaN propagation correct |
| D4 | GPU bf16_fma on packet data via DMA | DMEM[3] = FMA result, NaN propagation + last lane correct |
| D5 | GPU relu_i16 on packet data via DMA | DMEM[1] = ReLU, all negative lanes clamped to 0 |

All capabilities of the network processor -- packet capture, header rewriting, CPU processing, and GPU SIMD processing (all 5 kernels) -- were tested and verified with real network packets on the NetFPGA hardware.
