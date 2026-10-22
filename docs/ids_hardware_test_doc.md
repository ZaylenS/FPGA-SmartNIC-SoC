# IDS Hardware Test Documentation

## Test Date: 2026-03-31

## Summary

End-to-end ML-based network intrusion detection verified on NetFPGA hardware.
UDP packets carrying BF16 feature vectors are sent from node0, received by the
NetFPGA FIFO, processed by the GPU coprocessor running a trained MLP kernel,
and classified as NORMAL or ATTACK. No RTL changes — same bitfile as Lab 8/9.

## Test Environment

| Component | Details |
|-----------|---------|
| FPGA host | nf5.usc.edu (Team 5 board) |
| Node0 | nf6.usc.edu |
| FPGA interface | nf2c0, IP 10.0.0.2, MAC 00:4E:46:32:43:00 |
| Node0 interface | port0, IP 10.0.0.3, MAC A0:36:9F:0A:10:6B |
| Bitfile | nf2_top_par.bit (Lab 8/9, unchanged) |
| Kernel | ann_ids_11_16_8_2.hex (211 instructions) |
| Weights | data_ids_trained.hex (383 DMEM words, trained on NSL-KDD) |

## Test Results

### Test 1: Attack Traffic Classification

**Node0 command:**
```bash
python send_ids.py
```
Sends default attack sample (normalized features from NSL-KDD).

**nf5 command:**
```bash
python lab10reg.py ids_from_packet
```

**Output:**
```
Extracted 11 BF16 features from BRAM[7..9]:
  x[ 0] = 0x0000 (0.0000)    # src_bytes
  x[ 1] = 0x0000 (0.0000)    # dst_bytes
  x[ 2] = 0x3D23 (0.0398)    # same_srv_rate
  x[ 3] = 0x3D75 (0.0598)    # diff_srv_rate
  x[ 4] = 0x3D23 (0.0398)    # dst_host_same_srv_rate
  x[ 5] = 0x0000 (0.0000)    # logged_in
  x[ 6] = 0x3D1F (0.0388)    # dst_host_srv_count
  x[ 7] = 0x3D75 (0.0598)    # dst_host_diff_srv_rate
  x[ 8] = 0x0000 (0.0000)    # dst_host_srv_serror_rate
  x[ 9] = 0x0000 (0.0000)    # dst_host_same_src_port_rate
  x[10] = 0x3EE5 (0.4473)    # count

Classification Result:
  Logit[0] (normal): -5.5000
  Logit[1] (attack): 8.8125
  ==> ATTACK <==
```

**Result: PASS** -- correctly classified as ATTACK with strong confidence.

### Test 2: Normal Traffic Classification

**Node0 command:**
```bash
python send_ids.py 0.0 0.0 1.0 0.0 0.61 0.0 0.337 0.04 0.0 0.61 0.002
```

**Output:**
```
Extracted 11 BF16 features from BRAM[7..9]:
  x[ 0] = 0x0000 (0.0000)    # src_bytes
  x[ 1] = 0x0000 (0.0000)    # dst_bytes
  x[ 2] = 0x3F80 (1.0000)    # same_srv_rate
  x[ 3] = 0x0000 (0.0000)    # diff_srv_rate
  x[ 4] = 0x3F1C (0.6094)    # dst_host_same_srv_rate
  x[ 5] = 0x0000 (0.0000)    # logged_in
  x[ 6] = 0x3EAC (0.3359)    # dst_host_srv_count
  x[ 7] = 0x3D23 (0.0398)    # dst_host_diff_srv_rate
  x[ 8] = 0x0000 (0.0000)    # dst_host_srv_serror_rate
  x[ 9] = 0x3F1C (0.6094)    # dst_host_same_src_port_rate
  x[10] = 0x3B03 (0.0020)    # count

Classification Result:
  Logit[0] (normal): 2.0625
  Logit[1] (attack): -0.0688
  ==> NORMAL <==
```

**Result: PASS** -- correctly classified as NORMAL.

## Data Flow (Verified)

```
node0 (nf6)                              NetFPGA (nf5)
==========                               =============

python send_ids.py
  | 11 floats -> BF16
  | 6-byte padding + 32-byte data
  | UDP broadcast to 10.0.3.255:9999
  |
  +---- Ethernet/IP/UDP frame (80 bytes) --->  FIFO BRAM
                                                |
                                              python lab10reg.py ids_from_packet
                                                |
                                                | 1. Poll STATUS_REG for pkt_ready
                                                | 2. Switch to mode 2, check EtherType
                                                |    (skip ARP, accept IPv4/UDP)
                                                | 3. Read BRAM[7..9]: 11 BF16 features
                                                | 4. Replicate each to {v,v,v,v}
                                                | 5. Write to GPU DMEM[0..10]
                                                | 6. Release GPU reset
                                                | 7. Poll kernel_done (~6 ms wall-clock)
                                                | 8. Read GPU DMEM[381..382]: logits
                                                | 9. argmax -> NORMAL or ATTACK
                                                v
                                              Classification result on terminal
```

## Issues Encountered and Resolved

### 1. ARP Flooding

**Problem:** The single-packet FIFO was constantly filled by ARP requests from
node0 (10.0.0.3 asking for 10.0.0.2). The NetFPGA cannot respond to ARP, so
node0 retries indefinitely.

**Fix:** Added ARP filtering loop in `_wait_for_udp_packet()`. The script resets
the FIFO, polls for packets, checks EtherType at BRAM[2] (0x0800=IPv4 vs
0x0806=ARP), and discards non-UDP packets automatically.

### 2. FIFO BRAM Port B Mode Restriction

**Problem:** In FIFO mode (mode 0), BRAM Port B address is hardwired to `rd_ptr`,
not the PCI address register. So `bram_read(N)` always reads BRAM[0] regardless
of N.

**Root cause** (convertible_fifo.v lines 116-127):
```verilog
case (mode)
    2'd1, 2'd2: begin
        bram_addr_b = proc_addr;    // PCI address works
    end
    default: begin
        bram_addr_b = rd_ptr;       // mode 0: ignores PCI address!
    end
endcase
```

**Fix:** Switch to mode 2 before reading BRAM, then back to mode 0 to receive
the next packet. The `_wait_for_udp_packet()` function handles this automatically.

### 3. UDP Packets Not Reaching NetFPGA

**Problem:** `send_ids.py` sent to 10.0.0.2 (unicast), but node0 couldn't resolve
the MAC address via ARP (NetFPGA doesn't respond to ARP). The OS silently dropped
UDP packets after ARP timeout. No sudo access to add static ARP entry.

**Fix:** Changed destination to broadcast address 10.0.3.255 (subnet broadcast for
10.0.0.0/22) with `SO_BROADCAST` socket option. Broadcast uses dst MAC
FF:FF:FF:FF:FF:FF, bypassing ARP entirely.

### 4. FIFO Word Count Off-by-One

**Problem:** Feature x[10] read as zero. The NF2.1 header reported word_length=9
for a 72-byte frame. The FIFO stores word_length-1 = 8 data words = 64 bytes.
Feature 10 at frame byte 64-65 was outside the stored range.

**Root cause:** The FIFO's `words_remaining = word_length - 1` subtracts 1 for the
header word. For a 72-byte frame, word_length = ceil(72/8) = 9, giving only 8 data
words (64 bytes). Features at bytes 64+ are lost.

**Fix:** Added trailing padding in `send_ids.py` to increase payload from 24 to 32
bytes. Total frame = 42 + 6 + 32 = 80 bytes. word_length = ceil(80/8) = 10. FIFO
stores 9 data words = 72 bytes, covering all features at BRAM[7..9].

### 5. Python 2.4 Compatibility

**Problem:** NetFPGA hosts run Python 2.4 which lacks `b''` byte literals (Python 2.6+),
ternary expressions `x if c else y` (Python 2.5+), and `with` statements (Python 2.5+).

**Fix:** Replaced all incompatible syntax: `b'\x00'` -> `'\x00'`, ternary -> if/else
blocks, `ord()` for byte access, `%` formatting instead of f-strings.

## Performance

| Metric | Value |
|--------|-------|
| GPU kernel cycles | 2402 (from simulation) |
| GPU kernel time | ~19.2 us at 125 MHz |
| Wall-clock inference time | ~6 ms (includes PCI register overhead) |
| Model accuracy (BF16, test set) | 75.8% on NSL-KDD |
| Parameters | 346 (320 weights + 26 biases) |
| IMEM usage | 211 / 1024 instructions (20.6%) |
| DMEM usage | 383 / 1024 words (37.4%) |

Note: The 6 ms wall-clock time is dominated by PCI register read/write overhead
(~100 us per regread/regwrite x ~40 register operations for loading 11 features +
polling). The actual GPU computation is ~19 us.

## Files on Hardware

**nf5 (~/zil_team12/refinements_lab10/):**
- lab10reg.py -- deployment script (ids_load, ids_from_packet, ids_test, etc.)
- lab9reg.py -- base register interface (imported by lab10reg.py)
- ann_ids_11_16_8_2.hex -- GPU kernel (211 instructions)
- data_ids_trained.hex -- trained weights + default test input
- nf2_top_par.bit -- FPGA bitfile (Lab 8/9, unchanged)

**node0 (~/zil_team12/):**
- send_ids.py -- UDP feature sender (broadcast to 10.0.3.255:9999)

## Demo Commands

```bash
# Step 1 -- Program FPGA (once):
nf_download nf2_top_par.bit

# Step 2 -- Load model (once):
python lab10reg.py ids_load

# Step 3 -- Classify attack (nf5 first, then node0):
python lab10reg.py ids_from_packet           # nf5: waits for packet
python send_ids.py                           # node0: sends attack features
# Result: ==> ATTACK <==

# Step 4 -- Classify normal:
python lab10reg.py ids_from_packet           # nf5: waits
python send_ids.py 0.0 0.0 1.0 0.0 0.61 0.0 0.337 0.04 0.0 0.61 0.002  # node0
# Result: ==> NORMAL <==
```
