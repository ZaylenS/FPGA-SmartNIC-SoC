# Lab 8 — Design & Implementation Log

This document explains **what was built, how it works, and how it was verified** for each implementation batch. It is a companion to `implementation_plan.md` (which covers *what to build*).

> **Document status (refreshed 2026-05-17).** This file is the project log written as Lab 8 was being built (2026-03 timeframe). It accurately describes the design state captured by commit `44baf38` (2026-03-25) — the original Lab 8 → Lab 10 baseline. **Subsequent refinements (2026-04-13 BCAST + cycle counter; 2026-05-10 ARM orchestrator) are *not* folded into the batch-by-batch narratives below.** They are documented at the walkthrough level instead — see:
>
> - `walkthrough_batch2_wrapper.md` §1.5, §2.4, §2.8, §2.9, §2.11, §2.12, §2.13 for cycle counter + readback mux refactor + register-alias window + Fix B
> - `walkthrough_batch3_cpu_integration.md` §1, §3, §4.4, §5.1, §5.3 for the ARM-side alias window + Fix B
> - `walkthrough_batch4_gpu_integration.md` §2, §6.1, §8 for cycle-counter register + Fix B in DMA path + soft-reset auto-clear
> - `walkthrough_batch5_synthesis_hw.md` §7, §8 for the 2026-04-13 readback-mux trim bug + BCAST timing closure
> - `../lab7_gpu/walkthrough_batch{1,3,4}_*.md` for the BCAST GPU-core RTL
> - `../lab6_arm/walkthrough_arm_cpu.md` §1.1, §12 for the ARM-side alias-window ports
>
> Read the per-batch walkthroughs as the canonical current-state reference. This file remains the canonical record of *how the original design was built and why*.

---

## Batch 1: Convertible FIFO

### Files Created

| File | Purpose |
|------|---------|
| `src/fifo/fifo_bram.v` | 256 x 72-bit true dual-port BRAM |
| `src/fifo/convertible_fifo.v` | FIFO controller with state machine and port MUX |
| `tb/tb_convertible_fifo.v` | Testbench: 6 test cases |

### 1.1 — BRAM: `fifo_bram.v`

The BRAM stores one full network packet. Each entry is **72 bits** = 8-bit `ctrl` + 64-bit `data`, matching the NF2.1 word width.

```
  71      64 63                              0
 ┌──────────┬──────────────────────────────────┐
 │  ctrl[7:0] │           data[63:0]            │
 └──────────┴──────────────────────────────────┘
```

256 entries = max 256 words per packet. True dual-port means two independent address/data/write-enable sets (Port A and Port B) can operate simultaneously on the same clock.

**Key code — synchronous read pattern:**

```verilog
always @(posedge clk) begin
    if (we_a)
        mem[addr_a] <= din_a;   // write (non-blocking)
    dout_a <= mem[addr_a];      // synchronous read (non-blocking)
end
```

This pattern is critical for Xilinx BRAM inference. The read is **registered** (output appears one clock cycle after the address is presented). This 1-cycle latency is the root cause of Bug #2 described below.

**Why 72 bits?** The NF2.1 pipeline carries `{ctrl, data}` together. Storing them as a single 72-bit word means we don't need separate ctrl/data memories and both are always consistent.

### 1.2 — FIFO Controller: `convertible_fifo.v`

#### Port Organization

The FIFO has two BRAM ports wired through MUXes:

```
                        ┌─────────────┐
  Network write ──────► │  Port A MUX │ ──► BRAM Port A
  (in_data, in_ctrl)    │  (always    │     (write-only during receive)
                        │   FIFO wr)  │
                        └─────────────┘

                        ┌─────────────┐
  FIFO drain read ──┬──►│  Port B MUX │ ──► BRAM Port B
  CPU proc port  ───┤   │  (mode      │     (read or write)
  GPU proc port  ───┘   │   selects)  │
                        └─────────────┘
```

**Port A** is always driven by the FIFO's write logic (incoming network data). During receive, it writes `{in_ctrl, in_data}` at the `wr_ptr` address.

**Port B** is multiplexed by the `mode` input:
- `mode = 0` (FIFO mode): Port B address = `rd_ptr`, read-only, used for drain
- `mode = 1` (CPU mode): Port B driven by `proc_addr`, `proc_din`, `proc_we`
- `mode = 2` (GPU mode): same wiring as CPU mode

#### State Machine

```
         reset
           │
           ▼
      ┌─────────┐   fifo_wr_active &&    ┌─────────────┐
      │  S_IDLE  │──  ctrl != 0     ────► │ S_RECEIVING │◄─┐
      │  (0)     │   (header word)        │   (1)       │──┘ more words
      └────▲─────┘                        └──────┬──────┘
           │                              words_remaining == 1
           │                                     │
           │                                     ▼
           │                              ┌──────────────┐
           │                              │S_PKT_BUFFERED│
           │                              │    (2)       │
           │                              └──────┬───────┘
           │                              drain_start
           │                                     │
           │                                     ▼
           │                              ┌──────────────┐
           │                              │S_DRAIN_WAIT1 │  present addr to BRAM
           │                              │    (3)       │
           │                              └──────┬───────┘
           │                                     │  (1 cycle)
           │                                     ▼
           │                              ┌──────────────┐
           │                              │S_DRAIN_WAIT2 │  BRAM output valid,
           │                              │    (4)       │  latch into register
           │                              └──────┬───────┘
           │                                     │  (1 cycle)
           │                                     ▼
           │    last word accepted         ┌─────────────┐
           └───────────────────────────────│ S_DRAINING  │◄─┐ next word
                                           │    (5)      │──┘ (pipeline from BRAM)
                                           └─────────────┘
```

**S_IDLE (0):** Waiting for a packet. When the first word arrives (`in_ctrl != 0`, indicating a module header), extract the packet length from the header and transition to RECEIVING.

**S_RECEIVING (1):** Accept data words one per cycle. Decrement `words_remaining`. When the last word is written, set `pkt_stored = 1` and go to PKT_BUFFERED.

**S_PKT_BUFFERED (2):** The packet is fully stored in BRAM. The FIFO asserts `pkt_ready` and `fifo_full`, and deasserts `in_rdy` (backpressure — no new packets accepted). In this state, the CPU or GPU can switch `mode` to 1 or 2 and read/write BRAM contents via the processor port. When done, the external controller asserts `drain_start` to begin output.

**S_DRAIN_WAIT1 (3):** First prefetch cycle. See Section 1.4 below.

**S_DRAIN_WAIT2 (4):** Second prefetch cycle. See Section 1.4 below.

**S_DRAINING (5):** Output words to downstream one per cycle. When the last word is accepted (`drain_cnt + 1 == pkt_len`), reset everything and return to IDLE.

#### Flow Control

- **Input backpressure:** `in_rdy` is only asserted while in IDLE or RECEIVING and no packet is stored. Once a full packet is buffered, `in_rdy` goes low, stalling the upstream module.
- **Output backpressure:** During DRAINING, if `out_rdy` is deasserted by the downstream module, the FIFO holds the current word in `drain_word_reg` and does not advance. The BRAM address stays the same (since `rd_ptr` doesn't advance), so `bram_dout_b` keeps re-reading the same next word — no data is lost.

### 1.3 — Bug Fix #1: NF2.1 Header Word Length Extraction

#### The NF2.1 Module Header Format

When a packet enters the NetFPGA pipeline, the **first word** has `ctrl = 0xFF` and `data` laid out as:

```
  Bit position:  63        48 47        32 31        16 15         0
                ┌────────────┬────────────┬────────────┬────────────┐
    data[63:0]  │  src_port  │ word_length │byte_length │  dst_port  │
                │  [15:0]    │  [15:0]    │  [15:0]    │  [15:0]    │
                └────────────┴────────────┴────────────┴────────────┘
```

- `src_port` (bits [63:48]): which physical port the packet arrived on
- **`word_length`** (bits [47:32]): total number of 8-byte words in the packet **including the header word itself**
- `byte_length` (bits [31:16]): payload byte count (excluding header word)
- `dst_port` (bits [15:0]): destination port bitmask

#### The Bug

The initial implementation extracted the word length from the **wrong 16-bit field**:

```verilog
// BUG: reads byte_length (bits [31:16]) instead of word_length (bits [47:32])
pkt_len <= in_data[23:16];   // gets the low byte of byte_length!
```

For the test packet `64'h0001_0006_0028_0000`:
- `in_data[23:16]` = `0x28` = **40 decimal** (this is `byte_length` low byte)
- The state machine expected 40 words but only got 6, so it **never left S_RECEIVING**

#### The Fix

```verilog
// FIXED: reads word_length field (bits [47:32]), low 8 bits
pkt_len <= in_data[39:32];   // gets the low byte of word_length
```

- `in_data[39:32]` = `0x06` = **6 decimal** (correct word count)

**Why only the low 8 bits?** Our BRAM has 256 entries (8-bit address), so packets can be at most 256 words. Standard Ethernet frames are ~190 words maximum at 64 bits/word, so 8 bits is sufficient.

#### Concrete Example

```
Test packet: 64'h0001_0006_0028_0000
                 ^^^^                  src_port  = 0x0001
                      ^^^^             word_length = 0x0006  ← we need this
                           ^^^^        byte_length = 0x0028 (=40)
                                ^^^^   dst_port  = 0x0000

data[47:32] = 0x0006  →  data[39:32] = 0x06 = 6 ✓
data[31:16] = 0x0028  →  data[23:16] = 0x28 = 40 ✗ (wrong field!)
```

### 1.4 — Bug Fix #2: BRAM Read Latency and the Drain Pipeline

This is the most subtle part of the design. The BRAM has **1-cycle read latency**: you present an address on cycle N, and the data appears on `dout` at cycle N+1. If you try to read `dout` on the same cycle you present the address, you get **stale data** from the previous address.

#### Why This Matters (the Verilog Non-Blocking Assignment Problem)

In Verilog, `always @(posedge clk)` blocks use **non-blocking assignments** (`<=`). All `<=` assignments in a clock cycle are **scheduled** at the posedge but don't take effect until **after** all blocks have evaluated. This means:

```verilog
// BRAM (inside fifo_bram.v):
always @(posedge clk) begin
    dout_b <= mem[addr_b];    // (A) schedules dout_b update
end

// FIFO controller (inside convertible_fifo.v):
always @(posedge clk) begin
    drain_word_reg <= bram_dout_b;  // (B) reads CURRENT dout_b, not the one being scheduled
end
```

At any given posedge, statement (B) reads the **old** value of `dout_b` (from the previous cycle's address), not the one being computed by statement (A) at the same posedge.

#### Cycle-by-Cycle Trace of the Drain Pipeline

Here's what happens when `drain_start` is asserted while in `S_PKT_BUFFERED`, for a packet with 6 words at BRAM addresses 0-5:

```
Cycle │ State         │ rd_ptr │ bram_addr_b │ bram_dout_b  │ drain_word_reg │ out_wr │ Action
──────┼───────────────┼────────┼─────────────┼──────────────┼────────────────┼────────┼────────────────
  T   │ PKT_BUFFERED  │ ?→0    │ (proc/old)  │ (old)        │ (old)          │ 0      │ drain_start=1:
      │               │        │             │              │                │        │   rd_ptr <= 0
      │               │        │             │              │                │        │   state <= DRAIN_WAIT1
──────┼───────────────┼────────┼─────────────┼──────────────┼────────────────┼────────┼────────────────
  T+1 │ DRAIN_WAIT1   │ 0→1    │ 0 (comb)    │ (old/stale)  │ (old)          │ 0      │ BRAM captures addr=0
      │               │        │             │              │                │        │   dout_b <= mem[0]  (NBA)
      │               │        │             │              │                │        │   rd_ptr <= 1
      │               │        │             │              │                │        │   state <= DRAIN_WAIT2
──────┼───────────────┼────────┼─────────────┼──────────────┼────────────────┼────────┼────────────────
  T+2 │ DRAIN_WAIT2   │ 1→2    │ 1 (comb)    │ mem[0] ✓     │ ← mem[0]      │ 0      │ bram_dout_b now valid!
      │               │        │             │              │                │        │   drain_word_reg <= mem[0]
      │               │        │             │              │                │        │   drain_data_valid <= 1
      │               │        │             │              │                │        │   rd_ptr <= 2
      │               │        │             │              │                │        │   state <= DRAINING
──────┼───────────────┼────────┼─────────────┼──────────────┼────────────────┼────────┼────────────────
  T+3 │ DRAINING      │ 2→3    │ 2 (comb)    │ mem[1]       │ mem[0] → out   │ 1 ✓    │ OUTPUT word 0 (header)
      │               │        │             │              │ ← mem[1]       │        │   drain_cnt: 0→1
      │               │        │             │              │                │        │   drain_word_reg <= mem[1]
      │               │        │             │              │                │        │   rd_ptr <= 3
──────┼───────────────┼────────┼─────────────┼──────────────┼────────────────┼────────┼────────────────
  T+4 │ DRAINING      │ 3→4    │ 3 (comb)    │ mem[2]       │ mem[1] → out   │ 1 ✓    │ OUTPUT word 1
      │               │        │             │              │ ← mem[2]       │        │   drain_cnt: 1→2
──────┼───────────────┼────────┼─────────────┼──────────────┼────────────────┼────────┼────────────────
  ...  (continues for words 2, 3, 4)
──────┼───────────────┼────────┼─────────────┼──────────────┼────────────────┼────────┼────────────────
  T+8 │ DRAINING      │ 7      │ 7 (comb)    │ mem[5]       │ mem[5] → out   │ 1 ✓    │ OUTPUT word 5 (last)
      │               │        │             │              │                │        │   drain_cnt+1 == 6 == pkt_len
      │               │        │             │              │                │        │   → IDLE, reset all
──────┼───────────────┼────────┼─────────────┼──────────────┼────────────────┼────────┼────────────────
```

**Key insight:** `rd_ptr` is always **2 ahead** of the word being output. This is the read pipeline:

```
  rd_ptr presents address  ──► (1 cycle) ──►  BRAM outputs data  ──►  latch into drain_word_reg  ──►  output
       (cycle N)                                 (cycle N+1)              (cycle N+1, same posedge)      (cycle N+2)
```

The first version tried to do this in one state (collapsed WAIT1 + WAIT2 into a single PREFETCH), which meant it latched `bram_dout_b` on the **same cycle** the BRAM was computing it — getting stale data instead.

#### The Original (Broken) Drain

```verilog
// BROKEN: only 1 prefetch state
S_DRAIN_PREFETCH: begin
    drain_data_valid <= 1'b1;
    drain_word_reg   <= bram_dout_b;  // ✗ stale! BRAM hasn't output mem[0] yet
    rd_ptr           <= rd_ptr + 8'd1;
    state            <= S_DRAINING;
end
```

At the posedge entering `S_DRAIN_PREFETCH`, the BRAM is *simultaneously* computing `dout_b <= mem[0]`. Due to non-blocking assignment semantics, `bram_dout_b` still holds whatever it had from the **previous cycle** (garbage/old data). The latch captures junk.

#### The Fixed Drain (Two Wait States)

```verilog
// FIXED: two wait states to account for BRAM latency
S_DRAIN_WAIT1: begin
    // addr 0 is on BRAM. BRAM will register dout_b <= mem[0] on THIS posedge.
    // But we can't read dout_b yet (it's the OLD value).
    rd_ptr <= rd_ptr + 8'd1;   // advance to addr 1 for pipelining
    state  <= S_DRAIN_WAIT2;
end

S_DRAIN_WAIT2: begin
    // NOW bram_dout_b has mem[0] (updated by BRAM on the previous posedge).
    drain_word_reg   <= bram_dout_b;  // ✓ valid data!
    drain_data_valid <= 1'b1;
    rd_ptr           <= rd_ptr + 8'd1;
    state            <= S_DRAINING;
end
```

In `S_DRAINING`, the pipeline continues: each cycle, `bram_dout_b` has the *next* word (from the address presented 2 cycles earlier), so we can latch it directly:

```verilog
S_DRAINING: begin
    if (out_rdy && drain_data_valid) begin
        drain_cnt <= drain_cnt + 8'd1;
        if (drain_cnt + 8'd1 == pkt_len) begin
            // last word — go back to IDLE
        end else begin
            drain_word_reg <= bram_dout_b;  // pipeline: next word is ready
            rd_ptr         <= rd_ptr + 8'd1;
        end
    end
    // backpressure: if !out_rdy, hold everything (rd_ptr doesn't advance,
    // BRAM keeps re-reading the same address, no data lost)
end
```

### 1.5 — Testbench: `tb_convertible_fifo.v`

#### Test Overview

| Test | What it verifies | Key check |
|------|-----------------|-----------|
| 1. Inject 6-word packet | Packet capture, header parsing | `pkt_ready=1`, `fifo_full=1`, `pkt_word_cnt=6` |
| 2. CPU read BRAM | Processor port read in `mode=1` | `proc_dout` matches written data |
| 3. CPU modify word | Processor port write in `mode=1` | Read-back of modified word matches |
| 4. Drain packet | Full drain pipeline, output correctness | 6 words output, modified word preserved |
| 5. Return to IDLE | Post-drain state cleanup | `fifo_empty=1`, `pkt_ready=0`, `in_rdy=1` |
| 6. Second packet | FIFO reuse after drain | 3-word packet buffered and drained correctly |

#### Test Packet Construction

Test 1 injects a 6-word packet (1 header + 5 data words):

```
Word 0 (header):  ctrl=0xFF  data=64'h0001_0006_0028_0000
                                    ╰─┬──╯╰─┬──╯╰─┬──╯╰─┬──╯
                                   src=1  wlen=6  blen=40 dst=0

Word 1 (data):    ctrl=0x00  data=64'hDEAD_BEEF_CAFE_BABE
Word 2 (data):    ctrl=0x00  data=64'h1111_2222_3333_4444
Word 3 (data):    ctrl=0x00  data=64'h5555_6666_7777_8888
Word 4 (data):    ctrl=0x00  data=64'hAAAA_BBBB_CCCC_DDDD
Word 5 (data):    ctrl=0x00  data=64'hEEEE_FFFF_0000_1111
```

- `word_length = 6`: total words including the header itself
- `byte_length = 40`: 5 data words x 8 bytes each (excludes header)

#### Testbench Timing: The `#1` Delay Pattern

A Verilog race condition was discovered during testing. In iverilog, when an `initial` block and an `always @(posedge clk)` block both trigger at the same posedge, the execution order is **indeterminate**. This caused `drain_start` to never be seen by the state machine.

**Problem pattern:**
```verilog
drain_start = 1'b1;    // set at exact posedge time
@(posedge clk);        // state machine triggers at same event — race!
drain_start = 1'b0;
```

**Fixed pattern:**
```verilog
#1 drain_start = 1'b1;  // set 1 time-unit AFTER posedge (no race)
@(posedge clk);          // state machine captures drain_start=1 cleanly
#1 drain_start = 1'b0;
```

The `#1` delay ensures the testbench's blocking assignment completes *between* clock edges, so the next posedge samples a stable value. This is standard testbench practice — real hardware doesn't have this issue because flip-flop setup/hold times provide the separation naturally.

### 1.6 — Simulation Commands

```bash
cd "C:/Dev/EE533Labs/Lab8_fifo"

# Compile
/c/iverilog/bin/iverilog -g2001 -o tb_fifo \
    src/fifo/fifo_bram.v \
    src/fifo/convertible_fifo.v \
    tb/tb_convertible_fifo.v

# Run
/c/iverilog/bin/vvp tb_fifo
```

### 1.7 — Final Test Results

```
=== Test 1: Inject 6-word packet ===
PASS: pkt_ready asserted
PASS: fifo_full asserted
PASS: pkt_word_cnt = 6

=== Test 2: CPU mode — read BRAM contents ===
PASS: header ctrl = 0xFF
PASS: data word 1 matches

=== Test 3: CPU mode — modify word 1 ===
PASS: modified word verified

=== Test 4: Drain packet ===
  OUT[0]: ctrl=ff data=0001000600280000
  OUT[1]: ctrl=00 data=123456789abcdef0    ← CPU-modified word
  OUT[2]: ctrl=00 data=1111222233334444    ← unmodified
  OUT[3]: ctrl=00 data=5555666677778888
  OUT[4]: ctrl=00 data=aaaabbbbccccdddd
  OUT[5]: ctrl=00 data=eeeeffff00001111
PASS: 6 words drained
PASS: output header ctrl correct
PASS: output word 1 shows CPU modification
PASS: output word 2 unchanged

=== Test 5: Verify FIFO returns to IDLE ===
PASS: fifo_empty after drain
PASS: pkt_ready cleared
PASS: in_rdy ready for next packet

=== Test 6: Second packet (verify reuse) ===
PASS: 2nd packet buffered
PASS: 2nd packet drained correctly (3 words)

========================================
ALL TESTS PASSED
========================================
```

---

## Batch 2: NF2 Wrapper + PCI Register Interface

### Files Created

| File | Purpose |
|------|---------|
| `include/lab8_reg_defines.vh` | Register address definitions (simulation + synthesis) |
| `src/lab8_wrapper.v` | FIFO + NF2.1 register ring interface (was `lab8_wrapper.v`) |
| `src/user_data_path.v` | Lab8 NF2 top-level data path chain (synthesis only) |
| `tb/tb_lab8_wrapper.v` | Testbench: 5 test cases for wrapper |

### 2.1 — Architecture Overview

The wrapper sits between `output_port_lookup` and `output_queues` in the NF2.1 pipeline. It has two interfaces:

```
                    lab8_wrapper.v
               ┌─────────────────────────────┐
  NF2.1 data   │                             │  NF2.1 data
  in_data ────►│    convertible_fifo         ├────► out_data
  in_ctrl ────►│    (Batch 1)                ├────► out_ctrl
  in_wr   ────►│                             ├────► out_wr
  in_rdy  ◄────│                             │◄──── out_rdy
               │                             │
  PCI reg ring │    Register decode          │  PCI reg ring
  reg_req_in──►│    + software registers     ├────► reg_req_out
  reg_addr_in─►│    (read/write/strobe)      ├────► reg_data_out
  reg_data_in─►│                             ├────► reg_ack_out
               └─────────────────────────────┘
```

The **data path** connects directly to the convertible FIFO's NF2.1 ports (in/out). Packets flow through automatically.

The **register ring** provides PCI control: read status, switch modes, access BRAM contents, trigger drain. This follows the NF2.1 UDP register protocol.

### 2.2 — Register Map: `lab8_reg_defines.vh`

```
Offset  Name            R/W   Description
──────  ──────────────  ────  ─────────────────────────────────
0x00    LAB8_CTRL       RW    bit[0] = soft_reset
0x04    LAB8_STATUS     RO    {pkt_word_cnt[7:0], head[7:0], tail[7:0],
                               5'b0, empty, full, pkt_ready}
0x08    LAB8_FIFO_MODE  RW    mode[1:0]: 0=FIFO, 1=CPU, 2=GPU
0x0C    LAB8_FIFO_DRAIN RW    bit[0] = drain_start (auto-clear)
0x10    LAB8_BRAM_ADDR  RW    BRAM address [7:0]
0x14    LAB8_BRAM_WD_LO RW    write data [31:0]
0x18    LAB8_BRAM_WD_HI RW    write data [63:32]
0x1C    LAB8_BRAM_WCTRL RW    write ctrl [7:0]
0x20    LAB8_BRAM_CMD   RW    bit[0] = write strobe (auto-clear)
0x24    LAB8_BRAM_RD_LO RO    read data [31:0] (live from BRAM)
0x28    LAB8_BRAM_RD_HI RO    read data [63:32]
0x2C    LAB8_BRAM_RCTRL RO    read ctrl [7:0]
```

**Why split data into LO/HI?** The NF2 PCI bus is 32 bits wide, but BRAM words are 72 bits (8 ctrl + 64 data). So each BRAM word requires 3 register reads (lo, hi, ctrl) or 3 register writes + 1 strobe.

**Auto-clear strobes:** `LAB8_FIFO_DRAIN[0]` and `LAB8_BRAM_CMD[0]` clear themselves to 0 on the cycle after being written to 1. This means PCI software writes a 1 to trigger the action, and doesn't need to write 0 afterward. Implemented via:

```verilog
// Auto-clear strobes
if (reg_fifo_drain[0]) reg_fifo_drain[0] <= 1'b0;
if (reg_bram_cmd[0])   reg_bram_cmd[0]   <= 1'b0;
```

**Simulation vs synthesis:** The `ifndef` guards at the top of the file protect `UDP_REG_ADDR_WIDTH` and `CPCI_NF2_DATA_WIDTH` — these are only defined here for standalone iverilog simulation. On the NetFPGA VM, the NF2 build system provides them from XML-generated `registers.v`. The Lab8-specific defines (`LAB8_BLOCK_ADDR`, all register offsets) are needed for **both** simulation and synthesis.

### 2.3 — NF2.1 Register Ring Protocol

The NF2.1 register bus is a **daisy-chain ring**: each module in the chain receives a request on its `_in` ports, processes it (or passes through), and forwards the result on its `_out` ports. Key signals:

| Signal | Direction | Meaning |
|--------|-----------|---------|
| `reg_req_in` | in | A register request is active |
| `reg_ack_in` | in | Request already handled by a previous module |
| `reg_rd_wr_L_in` | in | 1 = read, 0 = write |
| `reg_addr_in` | in | 23-bit address: upper 15 bits = block addr, lower 8 bits = register offset |
| `reg_data_in` | in | Write data (for writes) or previous read result (for reads) |

**Address decode:**

```verilog
wire block_match = (reg_addr_in[22:8] == `LAB8_BLOCK_ADDR);  // upper 15 bits
wire [7:0] local_offset = reg_addr_in[7:0];                   // lower 8 bits
```

A module claims a request when: `reg_req_in && !reg_ack_in && block_match`. It sets `reg_ack_out = 1` to tell downstream modules the request has been handled.

### 2.4 — Register Ring State Machine

The wrapper uses a **1-cycle pipeline**: latch all incoming signals, decode, and output in one clock cycle.

```verilog
always @(posedge clk) begin
    // Default: pass through everything
    reg_req_held     <= reg_req_in;
    reg_ack_held     <= reg_ack_in;
    reg_rd_wr_L_held <= reg_rd_wr_L_in;
    reg_addr_held    <= reg_addr_in;
    reg_rd_data      <= reg_data_in;     // ← KEY: default overwrites every cycle
    reg_src_held     <= reg_src_in;

    if (reg_req_in && !reg_ack_in && block_match) begin
        reg_ack_held <= 1'b1;            // claim it
        if (!reg_rd_wr_L_in)
            // WRITE: update the target register
        else
            // READ: override reg_rd_data with register value
    end
end
```

The output ports are `assign` wires driven from the latched registers:

```verilog
assign reg_data_out = reg_rd_data;
assign reg_ack_out  = reg_ack_held;
// etc.
```

### 2.5 — BRAM Read via PCI: Timing

Reading BRAM contents from PCI requires two steps:

1. **Write the BRAM address:** `pci_write(LAB8_BRAM_ADDR, address)`
2. **Read the data:** `pci_read(LAB8_BRAM_RD_LO)` / `pci_read(LAB8_BRAM_RD_HI)`

The FIFO's `proc_addr` is driven combinationally from `reg_bram_addr[7:0]`. The BRAM has 1-cycle read latency. So after the PCI write updates `reg_bram_addr`, the BRAM output (`fifo_proc_dout`) is valid on the next clock cycle. The PCI bus turnaround (write→read) naturally provides this 1-cycle gap:

```
Cycle 1: PCI write BRAM_ADDR=1  →  reg_bram_addr <= 1  →  proc_addr = 1 (combinational)
Cycle 2: BRAM latches addr=1    →  dout_b <= mem[1]     (non-blocking, BRAM internal)
Cycle 3: PCI read BRAM_RD_LO   →  fifo_proc_dout = mem[1] is now valid  →  reg_rd_data <= dout[31:0]
Cycle 4: reg_data_out has the result
```

In the testbench, we add `repeat(2) @(posedge clk)` between the address write and the data read to guarantee the BRAM output has stabilized.

### 2.6 — BRAM Write via PCI: Strobe Pattern

Writing a BRAM word requires staging data in registers, then triggering with a strobe:

```
pci_write(LAB8_BRAM_ADDR,  address);    // which BRAM entry
pci_write(LAB8_BRAM_WD_LO, low_32);     // data[31:0]
pci_write(LAB8_BRAM_WD_HI, high_32);    // data[63:32]
pci_write(LAB8_BRAM_WCTRL, ctrl_8);     // ctrl[7:0]
pci_write(LAB8_BRAM_CMD,   1);          // write strobe → auto-clears
```

The `fifo_proc_we` signal is driven combinationally from `reg_bram_cmd[0]`. When the strobe register is written to 1, `proc_we` goes high for one cycle (because the auto-clear sets it back to 0 on the next cycle). The BRAM captures `{wctrl, wd_hi, wd_lo}` at the `proc_addr` address during that one cycle.

### 2.7 — Bug Fix: PCI Read Timing (Testbench)

#### The Problem

All PCI reads returned `0x00000000` even though the wrapper's internal `reg_rd_data` was correct during the processing cycle.

#### Root Cause

The wrapper's default assignment fires **every cycle**:

```verilog
reg_rd_data <= reg_data_in;   // default: pass through
```

This means:
- **Cycle N:** PCI read request arrives. Wrapper decodes it, overrides `reg_rd_data <= reg_status` (correct value).
- **Cycle N+1:** No request active. Default assignment fires: `reg_rd_data <= reg_data_in` (which is 0). The correct value is overwritten.

If the testbench captures `reg_data_out` on Cycle N+1 or later, it sees 0.

#### The Fix

The `pci_read` task must capture `reg_data_out` immediately after the processing posedge (Cycle N+1), before the **next** posedge overwrites it:

```verilog
task pci_read;
    input [7:0] offset;
    begin
        @(posedge clk); #1;             // Cycle N: present request
        reg_req_in     = 1'b1;
        reg_rd_wr_L_in = 1'b1;          // read
        reg_addr_in    = make_addr(offset);

        @(posedge clk); #1;             // Cycle N+1: wrapper has processed
        pci_rd_result  = reg_data_out;   // capture IMMEDIATELY (before next posedge)
        reg_req_in     = 1'b0;           // then clear request
    end
endtask
```

The `#1` delay after `@(posedge clk)` ensures we read the output **after** the non-blocking assignments have taken effect but **before** the next clock edge triggers another default overwrite. This is the same `#1` pattern used in Batch 1 to avoid testbench race conditions.

**Note:** This is a testbench-only issue. In real NF2 hardware, the `udp_reg_master` captures the ring output on the correct cycle. The wrapper's pass-through default is the standard NF2 pattern — it works correctly in the daisy-chain because each module only has one cycle to respond before the request moves on.

### 2.8 — `user_data_path.v` (Synthesis Only)

This file defines the NF2.1 top-level data path chain for the NetFPGA build system. It cannot be simulated standalone because it instantiates NF2 IP cores (`input_arbiter`, `output_port_lookup`, `output_queues`, `udp_reg_master`).

**Data path chain:**

```
input_arbiter → output_port_lookup → lab8_wrapper → output_queues
```

**Register ring (daisy-chain):**

```
udp_reg_master → input_arbiter → output_port_lookup → lab8_wrapper → output_queues → udp_reg_master
```

The wrapper (`lab8_wrapper`) replaces whatever processing module was previously in the chain (e.g., the simple passthrough in `reference_nic`).

### 2.9 — Simulation Commands

```bash
cd "C:/Dev/EE533Labs/Lab8_fifo"

# Compile
/c/iverilog/bin/iverilog -g2001 -I include -o tb_wrapper \
    src/fifo/fifo_bram.v \
    src/fifo/convertible_fifo.v \
    src/lab8_wrapper.v \
    tb/tb_lab8_wrapper.v

# Run
/c/iverilog/bin/vvp tb_wrapper
```

### 2.10 — Final Test Results

```
=== Test 1: Inject 4-word packet, check status via PCI ===
STATUS = 0x04000403
PASS: pkt_ready set in STATUS
PASS: fifo_full set in STATUS
PASS: pkt_word_cnt = 4

=== Test 2: PCI BRAM read (CPU mode) ===
BRAM[0] ctrl = 0xff
PASS: header ctrl = 0xFF
BRAM[0] data_lo = 0x00180000
PASS: BRAM[1] data_lo matches
PASS: BRAM[1] data_hi matches

=== Test 3: PCI BRAM write (modify word 1) ===
PASS: modified BRAM[1] lo verified
PASS: modified BRAM[1] hi verified

=== Test 4: Drain via PCI ===
  OUT[0]: ctrl=ff data=0001000400180000
  OUT[1]: ctrl=00 data=123456789abcdef0   ← PCI-modified word
  OUT[2]: ctrl=00 data=1111222233334444   ← unmodified
  OUT[3]: ctrl=00 data=5555666677778888
Drained 4 words
PASS: 4 words drained
PASS: output word 1 shows PCI modification
PASS: output word 2 unchanged

=== Test 5: Verify IDLE, second packet ===
PASS: fifo_empty after drain
PASS: pkt_ready cleared
PASS: 2nd packet buffered
PASS: 2nd packet drained correctly (3 words)

========================================
ALL TESTS PASSED
========================================
```

---

## Batch 3: ARM CPU Integration

### Files Modified/Created

| File | Purpose |
|------|---------|
| `src/arm/data_mem.v` | Added `ext_mem` port: addr[7]=1 routes to FIFO BRAM |
| `src/arm/processor.v` | Pass-through ext_mem signals to top level |
| `src/lab8_wrapper.v` | CPU instantiation, 15 CPU registers, proc port MUX |
| `tb/tb_cpu_fifo.v` | CPU-FIFO integration testbench |
| `tb/sim_primitives.v` | XOR2/AND2/OR3 stubs for iverilog |
| `sw/test_4t_v2.hex` | Fixed 4-thread test program (HALT+B. pattern) |

### 3.1 — Architecture: CPU-FIFO Data Path

The CPU accesses FIFO BRAM directly through its MEM stage — no PCI round-trip ("Use Network, NO PCI"):

```
  ARM CPU Pipeline          lab8_wrapper.v            convertible_fifo.v
  ┌──────────────┐       ┌──────────────────┐       ┌───────────────┐
  │ data_mem.v   │       │ Proc Port MUX    │       │               │
  │ addr[7]=1 ──►│──────►│ cpu_drives_proc? │──────►│ Port B        │
  │ ext_mem_addr │       │  yes → CPU sigs  │       │ (proc port)   │
  │ ext_mem_din  │       │  no  → PCI sigs  │       │               │
  │ ext_mem_we   │       │                  │       │ 256x72 BRAM   │
  │ ext_mem_dout◄│───────│◄ fifo_proc_dout  │◄──────│               │
  └──────────────┘       └──────────────────┘       └───────────────┘
```

Address mapping: CPU address 128 → FIFO BRAM[0], 129 → BRAM[1], etc. The `was_ext` register in data_mem.v delays the output mux select by one cycle to match BRAM read latency.

### 3.2 — Proc Port MUX

```verilog
wire cpu_drives_proc = (reg_fifo_mode_r[1:0] == 2'd1) && cpu_running;

always @(*) begin
   if (cpu_drives_proc) begin
      fifo_proc_addr = cpu_ext_mem_addr;
      fifo_proc_din  = {8'h00, cpu_ext_mem_din};  // ctrl=0, 64-bit data
      fifo_proc_we   = cpu_ext_mem_we;
   end else begin
      fifo_proc_addr = reg_bram_addr[7:0];
      fifo_proc_din  = {reg_bram_wctrl[7:0], reg_bram_wd_hi, reg_bram_wd_lo};
      fifo_proc_we   = reg_bram_cmd[0];
   end
end
```

### 3.3 — CPU Register Map (offsets 0x0C–0x1A)

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x0C | CPU_CTRL | SW | bit[0]=start_stop, bit[1]=cpu_reset |
| 0x0D | CPU_STATUS | HW | {all_halted, cpsr_3..0, thread_id, running, ~reset} |
| 0x0E–0x10 | CPU_IMEM | SW/HW | IMEM address, write data, command strobe, readback |
| 0x12–0x17 | CPU_DMEM | SW/HW | DMEM address, write data lo/hi, command, readback lo/hi |
| 0x18–0x1A | CPU_LA | SW/HW | Logic analyzer address, readback lo/hi |

### 3.4 — Test Program (test_4t_v2.hex)

Thread 0 (5 instructions + B. padding):
```
MOV r1, #128        ; FIFO BRAM base = CPU addr 128
LDR r2, [r1, #1]    ; load BRAM[1]
ADD r2, r2, #42      ; modify
STR r2, [r1, #1]    ; store back
HALT                 ; signal completion
B .                  ; trap PC (prevent re-execution)
```

Threads 1–3: HALT + B. immediately.

### 3.5 — Hardware Verification

Test: Write BRAM[1]=0x1000 via PCI, run CPU, verify BRAM[1]=0x102A (0x1000+42).

**Result: PASS** — confirmed on NetFPGA V2, March 5 2026.

See `docs/walkthrough_batch3_cpu_integration.md` for full details including LA trace analysis.

---

## Batch 4: GPU + DMA Integration

### Files Added/Modified

| File | Purpose |
|------|---------|
| `src/gpu/*.v` (15 files) | GPU pipeline copied from Lab 7 (6-stage: F/D/EX1/EX2/EX3/WB) |
| `src/lab8_wrapper.v` | GPU instantiation, 12 GPU registers, 4 DMA registers, DMA engine, extended proc port MUX |
| `tb/tb_gpu_integration.v` | GPU-DMA round-trip testbench |

### 4.1 — Architecture: GPU + DMA

```
                    lab8_wrapper.v
  ┌──────────────────────────────────────────────────┐
  │                                                  │
  │  convertible_fifo ◄──── Proc Port MUX ◄──┬── PCI (default)
  │  (256x72 BRAM)          (3-way)          ├── CPU ext_mem (mode=1)
  │                                           └── DMA engine (mode=2)
  │                                                  │
  │  gpu_top ◄──── GPU DMEM ext MUX ◄────┬── PCI (default)
  │  (6-stage SIMD pipeline)              └── DMA engine (active)
  │  IMEM: 1024x32  DMEM: 1024x64                   │
  │                                                  │
  │  DMA Engine: 3-state FSM (IDLE→READ→COPY)        │
  │    FIFO→GPU: reads FIFO proc port, writes GPU DMEM│
  │    GPU→FIFO: reads GPU DMEM, writes FIFO proc port│
  │    1 word/cycle after 1-cycle setup               │
  └──────────────────────────────────────────────────┘
```

### 4.2 — DMA Engine

The DMA engine copies data between FIFO BRAM and GPU DMEM. It uses a 3-state FSM:

```
  IDLE ──(start && mode==2 && length!=0)──► READ ──(1 cycle)──► COPY ──(length words)──► IDLE
```

- **Direction bit**: 0 = FIFO→GPU, 1 = GPU→FIFO
- **Pipeline**: rd_ptr leads wr_ptr by 1 (accounts for BRAM read latency)
- **Throughput**: 1 word/cycle after 1-cycle setup latency
- **Gating**: DMA only starts when mode==2 (GPU mode) and length!=0

### 4.3 — Extended Proc Port MUX (3-way)

```verilog
wire cpu_drives_proc = (mode == 2'd1) && cpu_running;
wire dma_drives_proc = (mode == 2'd2) && dma_active;

always @(*) begin
   if (cpu_drives_proc)       // CPU ext_mem signals
   else if (dma_drives_proc)  // DMA engine signals (direction-dependent)
   else                       // PCI register signals (default)
end
```

### 4.4 — GPU Register Map (offsets 0x20–0x2F)

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x20 | GPU_CTRL | SW | bit[0]=gpu_reset (1=hold in reset) |
| 0x21 | GPU_STATUS | HW | bit[0]=kernel_done, bit[1]=dma_busy |
| 0x22–0x25 | GPU_IMEM | SW/HW | IMEM address, write data, command, readback |
| 0x26–0x2B | GPU_DMEM | SW/HW | DMEM address, write data lo/hi, command, readback lo/hi |
| 0x2C | DMA_CTRL | SW | bit[0]=start (auto-clear), bit[1]=direction |
| 0x2D | DMA_FIFO_ADDR | SW | FIFO BRAM start address [7:0] |
| 0x2E | DMA_GPU_ADDR | SW | GPU DMEM start address [9:0] |
| 0x2F | DMA_LENGTH | SW | Word count [7:0] |

### 4.5 — GPU Default State

GPU starts in reset (`reg_gpu_ctrl` resets to 0x1). Software must explicitly release reset to run a kernel. The GPU IMEM and DMEM ext ports (Port B) work regardless of GPU reset state — Port B is independent of the core pipeline.

### 4.6 — Simulation Verification

Round-trip test: inject packet → DMA FIFO→GPU → run vec_add kernel → DMA GPU→FIFO → verify BRAM matches expected results. **PASS** in iverilog simulation.

---

## Batch 5: NetFPGA Synthesis + Hardware Verification

### 5.1 — Synthesis Issues and Fixes

#### Fix 1: PCI BRAM Write Strobe (Bug #4)

**Problem:** PCI BRAM writes via `reg_bram_cmd[0]` read back as all zeros on hardware. CPU writes and IMEM loads worked fine.

**Root Cause:** The `reg_bram_cmd[0]` auto-clear signal passed through a 3-way combinational proc port MUX before reaching `fifo_proc_we`. With 4816 timing violations at 125 MHz (due to GPU routing congestion), this multi-level combinational path failed to meet timing — the write-enable pulse was lost.

**Evidence:**
- CPU ext_mem writes work: `cpu_ext_mem_we` is a registered pipeline output (clean 1-cycle pulse)
- CPU IMEM writes work: `cpu_imem_wen = reg_cpu_imem_cmd[0]` is a direct assign (no mux)
- Only PCI BRAM writes through the mux chain fail

**Fix:** Dedicated registered PCI write strobes that bypass the auto-clear + mux chain:

```verilog
wire pci_wr_hit = reg_req_in && !reg_ack_in && block_match && !reg_rd_wr_L_in;

reg bram_pci_wr_strobe;
reg gpu_dmem_pci_wr_strobe;

always @(posedge clk) begin
   if (reset) begin
      bram_pci_wr_strobe     <= 1'b0;
      gpu_dmem_pci_wr_strobe <= 1'b0;
   end else begin
      bram_pci_wr_strobe     <= pci_wr_hit
                             && (local_offset == `LAB8_BRAM_CMD)
                             && reg_data_in[0];
      gpu_dmem_pci_wr_strobe <= pci_wr_hit
                             && (local_offset == `LAB8_GPU_DMEM_CMD)
                             && reg_data_in[0];
   end
end
```

The proc port MUX else branch now uses `bram_pci_wr_strobe` instead of `reg_bram_cmd[0]`, and the GPU DMEM ext port MUX uses `gpu_dmem_pci_wr_strobe` instead of `reg_gpu_dmem_cmd[0]`.

#### Fix 2: `in_rdy` Mode Gating (Bug #2 — applied)

Previously identified in Batch 3 but deferred. Now applied in `convertible_fifo.v`:

```verilog
assign in_rdy = (mode == 2'd0)
             && (state == S_IDLE || state == S_RECEIVING)
             && !pkt_stored;
```

Prevents network packets from writing into FIFO BRAM via Port A while CPU/GPU uses Port B.

#### Fix 3: `gpu_nf2_wrapper.v` Removal

The NF2 build system auto-includes all `.v` files under `src/`. `gpu_nf2_wrapper.v` (Lab 7's standalone wrapper) referenced `` `GPU_REG_ADDR_WIDTH `` which was defined in the now-removed `gpu.xml`. Since lab8_wrapper.v replaces it, the file was deleted from `src/gpu/`.

#### Fix 4: `project.xml` — Remove `gpu` Instance

After removing `gpu.xml` from `include/`, the `<nf:instance name="gpu"/>` in `project.xml` memalloc caused register generation failure. Removed the instance line.

### 5.2 — Timing Analysis

**Core clock (125 MHz / 8ns period):** 4816 setup timing violations.

Worst critical path is in the **GPU DECODE stage** (not execute):
```
IMEM BRAM read (Port B)
  → instruction decoder (alu_op, mem_write, etc.)
    → register file address decode + read (dec_rs2_addr: 196 fanout, 1.740ns routing)
      → signed branch comparison (64-bit carry chain)
        → PC update
Total: 16.670ns (5.374ns logic + 11.296ns routing = 67.8% routing)
```

Key observations:
- The EX1/EX2/EX3 pipeline (from Lab 7) already fixed the execute stage — it's no longer critical
- Adding EX4 would NOT help: the bottleneck is DECODE, not EXECUTE
- 67.8% of the delay is routing (placement congestion from large design), not logic depth
- Fixing properly would require splitting DECODE into DECODE1+DECODE2 (significant rework)

**Pragmatic approach:** Accept timing violations with `XIL_TIMING_ALLOW_IMPOSSIBLE=1`. The registered PCI strobes ensure reliable register operations. GPU operates on buffered data (not real-time), so occasional timing glitches are tolerable.

### 5.3 — Hardware Test Results (March 7, 2026)

All 6 tests pass on NetFPGA V2:

| # | Test | Result | Key Output |
|---|------|--------|------------|
| 1 | FIFO status | PASS | `fifo_empty=1, mode=0` |
| 2 | PCI BRAM write/read | **PASS** | Readback matches written data (strobe fix verified) |
| 3 | CPU-FIFO (cpu_test) | PASS | `BRAM[1] = 0x0000102A` (0x1000 + 42) |
| 4 | GPU DMEM PCI write/read | PASS | `CAFE0000_BABE0001` readback correct |
| 5 | GPU kernel (vec_add_i16) | PASS | `DMEM[2] = 0x0000000C_00000005` (INT16: 5+7=12, 3+2=5) |
| 6 | DMA round-trip (both dirs) | PASS | FIFO→GPU and GPU→FIFO data matches |

**Test 2** was the critical validation — PCI BRAM writes previously returned all zeros. The registered strobe fix resolved this.

**Test 5** demonstrates end-to-end GPU kernel execution:
- Load `vec_add_i16.hex` (5 instructions: VLOAD, VLOAD, VADD, VSTORE, HALT)
- Pre-load DMEM[0]=0x00000005_00000003, DMEM[1]=0x00000007_00000002
- Release GPU from reset, wait for kernel_done
- Result: DMEM[2]=0x0000000C_00000005 (lane-wise INT16 addition: 5+7=12, 3+2=5)

**Test 6** validates the DMA engine in both directions:
- FIFO→GPU: wrote 0x00001111_22223333 and 0x44445555_66667777 to FIFO BRAM, DMA'd to GPU DMEM, readback matched
- GPU→FIFO: wrote 0xAAAA0000_BBBB0000 and 0xCCCC0000_DDDD0000 to GPU DMEM, DMA'd to FIFO BRAM, readback matched

### 5.4 — `all_halted` Timeout (Cosmetic)

During cpu_test, the `all_halted` flag times out after 1 second (`CPU_STATUS=0x00000403`), but BRAM[1]=0x102A confirms correct execution. This happens because the HALT instruction sets `halted[thread_id]` in the ID stage, but the PC continues advancing through B. (self-branch) instructions. The CPU is technically still "running" (fetching B. instructions in an infinite loop), so `all_halted` may not be reliably detectable via the current status polling approach.

`CPU_STATUS=0x00000403` decodes as:
- bit[0]=1: not in reset
- bit[1]=1: running (start_stop=1)
- bit[10]=1: thread_id=? (current fetch thread)
- bit[31]=0: all_halted NOT set

This is cosmetic — the program completed correctly. The `all_halted` detection issue is tracked in `docs/improvements_and_optimizations.md`.

---

## Complete Register Map

All registers use word-indexed 6-bit offsets from `LAB8_BLOCK_ADDR` (17'h00011).
PCI byte address = 0x2001100 + offset * 4.

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x00 | CTRL | SW | bit[0]=soft_reset |
| 0x01 | STATUS | HW | {pkt_word_cnt[7:0], head[7:0], tail[7:0], 5'b0, empty, full, pkt_ready} |
| 0x02 | FIFO_MODE | SW | 0=FIFO, 1=CPU, 2=GPU |
| 0x03 | FIFO_DRAIN | SW | bit[0]=drain_start (auto-clear) |
| 0x04 | BRAM_ADDR | SW | BRAM address [7:0] |
| 0x05 | BRAM_WD_LO | SW | Write data [31:0] |
| 0x06 | BRAM_WD_HI | SW | Write data [63:32] |
| 0x07 | BRAM_WCTRL | SW | Write ctrl [7:0] |
| 0x08 | BRAM_CMD | SW | bit[0]=write strobe (auto-clear) |
| 0x09 | BRAM_RD_LO | HW | Read data [31:0] |
| 0x0A | BRAM_RD_HI | HW | Read data [63:32] |
| 0x0B | BRAM_RCTRL | HW | Read ctrl [7:0] |
| 0x0C | CPU_CTRL | SW | bit[0]=start_stop, bit[1]=cpu_reset |
| 0x0D | CPU_STATUS | HW | {all_halted, cpsr_3..0, thread_id, running, ~reset} |
| 0x0E | CPU_IMEM_ADDR | SW | IMEM address [8:0] |
| 0x0F | CPU_IMEM_WDATA | SW | IMEM write data [31:0] |
| 0x10 | CPU_IMEM_CMD | SW | bit[0]=write strobe (auto-clear) |
| 0x11 | CPU_IMEM_RDATA | HW | IMEM readback [31:0] |
| 0x12 | CPU_DMEM_ADDR | SW | DMEM address [7:0] |
| 0x13 | CPU_DMEM_WD_LO | SW | DMEM write data [31:0] |
| 0x14 | CPU_DMEM_WD_HI | SW | DMEM write data [63:32] |
| 0x15 | CPU_DMEM_CMD | SW | bit[0]=write strobe (auto-clear) |
| 0x16 | CPU_DMEM_RD_LO | HW | DMEM readback [31:0] |
| 0x17 | CPU_DMEM_RD_HI | HW | DMEM readback [63:32] |
| 0x18 | CPU_LA_ADDR | SW | LA address [10:0] |
| 0x19 | CPU_LA_RD_LO | HW | LA readback [31:0] |
| 0x1A | CPU_LA_RD_HI | HW | LA readback [63:32] |
| 0x1B–0x1F | (reserved) | — | Padding to align GPU at 0x20 |
| 0x20 | GPU_CTRL | SW | bit[0]=gpu_reset (1=hold) |
| 0x21 | GPU_STATUS | HW | bit[0]=kernel_done, bit[1]=dma_busy |
| 0x22 | GPU_IMEM_ADDR | SW | IMEM address [9:0] |
| 0x23 | GPU_IMEM_WDATA | SW | IMEM write data [31:0] |
| 0x24 | GPU_IMEM_CMD | SW | bit[0]=write strobe (auto-clear) |
| 0x25 | GPU_IMEM_RDATA | HW | IMEM readback [31:0] |
| 0x26 | GPU_DMEM_ADDR | SW | DMEM address [9:0] |
| 0x27 | GPU_DMEM_WD_LO | SW | DMEM write data [31:0] |
| 0x28 | GPU_DMEM_WD_HI | SW | DMEM write data [63:32] |
| 0x29 | GPU_DMEM_CMD | SW | bit[0]=write strobe (auto-clear) |
| 0x2A | GPU_DMEM_RD_LO | HW | DMEM readback [31:0] |
| 0x2B | GPU_DMEM_RD_HI | HW | DMEM readback [63:32] |
| 0x2C | DMA_CTRL | SW | bit[0]=start (auto-clear), bit[1]=direction (0=FIFO→GPU, 1=GPU→FIFO) |
| 0x2D | DMA_FIFO_ADDR | SW | FIFO BRAM start address [7:0] |
| 0x2E | DMA_GPU_ADDR | SW | GPU DMEM start address [9:0] |
| 0x2F | DMA_LENGTH | SW | Word count [7:0] |

---

## Bug Summary

| # | Bug | Discovery | Root Cause | Fix | Status |
|---|-----|-----------|------------|-----|--------|
| 1 | NF2.1 header word length | Batch 1 sim | Extracted `data[23:16]` (byte_length) instead of `data[39:32]` (word_length) | Changed to `in_data[39:32]` | Fixed (RTL) |
| 2 | BRAM drain pipeline stale data | Batch 1 sim | Single prefetch state; BRAM 1-cycle read latency means `dout_b` is stale at the same posedge | Split into DRAIN_WAIT1 + DRAIN_WAIT2 (two-cycle prefetch) | Fixed (RTL) |
| 3 | PCI read returns zero | Batch 2 sim | Default `reg_rd_data <= reg_data_in` overwrites valid read result next cycle | Capture `reg_data_out` immediately after processing posedge in testbench | Fixed (TB) |
| 4 | CPU pipeline runs wild | Batch 3 HW | `start_stop=0, rst=0`: IF stage runs but thread counter frozen; T0 executes at 4x speed | Never allow `rst=0, start_stop=0` — atomic start/stop transitions in lab8reg | Fixed (SW) |
| 5 | FIFO Port A race (network corruption) | Batch 3 HW | `in_rdy` not gated by `mode`; network packets overwrite BRAM during CPU/GPU mode | `in_rdy = (mode == 0) && ...` | Fixed (RTL, Batch 5) |
| 6 | CPU PC wrap (program re-executes) | Batch 3 HW | HALT sets `halted` flag but IF_stage PC always advances; 9-bit offset wraps → program loops | Fill IMEM with B. (self-branch `0xEAFFFFFE`) after HALT | Fixed (SW) |
| 7 | PCI BRAM writes return zeros | Batch 5 HW | `reg_bram_cmd[0]` auto-clear through 3-way combinational mux fails timing at 125 MHz with 4816 violations | Dedicated registered PCI write strobes (`bram_pci_wr_strobe`) | Fixed (RTL) |
| 8 | `gpu_nf2_wrapper.v` compilation error | Batch 5 synth | NF2 build auto-includes all `.v` in `src/`; file referenced removed `GPU_REG_ADDR_WIDTH` | Deleted `gpu_nf2_wrapper.v` from `src/gpu/` | Fixed (file removal) |
| 9 | `project.xml` gpu instance error | Batch 5 synth | `<nf:instance name="gpu"/>` referenced deleted `gpu.xml` | Removed instance from memalloc | Fixed (XML) |

---

## Hardware Test Sequence (Batch 5 — Final)

```bash
# Program FPGA
nf_download nf2_top_par.bit

# Test 1: Status
./lab8reg status

# Test 2: PCI BRAM write/read
./lab8reg fifo_write 0 DEADBEEF 12345678
./lab8reg fifo_write 1 AABBCCDD 11223344
./lab8reg fifo_read 0 4

# Test 3: CPU-FIFO integration
./lab8reg cpu_test test_4t_v2.hex

# Test 4: GPU register access
./lab8reg gpu_status
./lab8reg gpu_write_dmem 0 CAFE0000 BABE0001

# Test 5: GPU kernel execution
./lab8reg gpu_reset
./lab8reg gpu_load_imem vec_add_i16.hex
./lab8reg gpu_write_dmem 0 00000005 00000003
./lab8reg gpu_write_dmem 1 00000007 00000002
./lab8reg gpu_start
sleep 1
./lab8reg gpu_status
./lab8reg gpu_read_dmem 0 4
./lab8reg gpu_stop

# Test 6: DMA round-trip
./lab8reg fifo_write 0 00001111 22223333
./lab8reg fifo_write 1 44445555 66667777
./lab8reg mode 2
./lab8reg dma_fifo_to_gpu 0 0 2
./lab8reg gpu_read_dmem 0 2
./lab8reg gpu_write_dmem 0 AAAA0000 BBBB0000
./lab8reg gpu_write_dmem 1 CCCC0000 DDDD0000
./lab8reg dma_gpu_to_fifo 0 0 2
./lab8reg fifo_read 0 2
./lab8reg mode 0
```

---

## File Inventory (Complete)

| File | Purpose |
|------|---------|
| **FIFO** | |
| `src/fifo/fifo_bram.v` | 256x72 dual-port BRAM (inferred) |
| `src/fifo/convertible_fifo.v` | Packet FIFO with proc access, state machine, mode-gated in_rdy |
| **ARM CPU** | |
| `src/arm/IF_stage.v` | Instruction fetch, per-thread PC confinement |
| `src/arm/ID.v` | Instruction decode, register read, branch resolve |
| `src/arm/EX.v` | Execute stage (ALU) |
| `src/arm/data_mem.v` | DMEM with ext_mem port for FIFO BRAM access |
| `src/arm/processor.v` | Top-level ARM with 4-thread barrel, ext_mem pass-through |
| `src/arm/logic_analyzer.v` | 2048x64-bit trace buffer |
| `src/arm/*.v` (other) | Pipeline registers (ifid, idex, exmem, memwb), ALU components |
| **GPU** | |
| `src/gpu/gpu_top.v` | GPU top-level (6-stage pipeline, SIMD) |
| `src/gpu/core_top.v` | Core pipeline instantiation |
| `src/gpu/fetch_stage.v` | Instruction fetch from IMEM |
| `src/gpu/decode_stage.v` | Instruction decode + branch resolve |
| `src/gpu/execute_stage.v` | SIMD ALU + BF16 FMA (3-stage: EX1/EX2/EX3) |
| `src/gpu/writeback_stage.v` | Register file writeback |
| `src/gpu/data_memory.v` | 1024x64 DMEM, dual-port (core + external) |
| `src/gpu/instruction_memory.v` | 1024x32 IMEM, dual-port (core + external) |
| `src/gpu/simd_alu.v` | 4-lane SIMD (INT16 + BF16) |
| `src/gpu/bf16_fma_unit.v` | BFloat16 fused multiply-add |
| `src/gpu/hazard_unit.v` | Stall-based hazard detection |
| `src/gpu/register_file.v` | 16x64-bit register file |
| `src/gpu/*.v` (other) | Pipeline registers, ALU components |
| **Wrapper** | |
| `src/lab8_wrapper.v` | NF2.1 wrapper: FIFO + CPU + GPU + DMA + 48 registers |
| `src/user_data_path.v` | NF2 top-level data path chain (synthesis only) |
| **Config** | |
| `include/lab8_reg_defines.vh` | Register offset defines (sim + synthesis) |
| `include/lab8.xml` | NF2 register generator input (48 registers) |
| `include/project.xml` | NF2 project definition (module list, memalloc) |
| `include/gpu_params.vh` | GPU parameters (widths, depths, SIMD lanes) |
| **Test** | |
| `tb/tb_convertible_fifo.v` | Batch 1 FIFO testbench |
| `tb/tb_lab8_wrapper.v` | Batch 2 wrapper testbench |
| `tb/tb_cpu_fifo.v` | Batch 3 CPU-FIFO testbench |
| `tb/tb_gpu_integration.v` | Batch 4 GPU-DMA testbench |
| `tb/sim_primitives.v` | Xilinx primitive stubs for iverilog |
| **Software** | |
| `sw/lab8reg` | Perl PCI control script (all commands) |
| `sw/test_4t_v2.hex` | ARM test program (HALT+B. pattern, 4 threads) |
| `sw/kernels/compiled/*.hex` | GPU kernels (vec_add, vec_sub, bf16_mul, bf16_fma, relu) |
