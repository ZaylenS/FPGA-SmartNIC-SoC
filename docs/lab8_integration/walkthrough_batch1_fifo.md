# Batch 1 — Convertible FIFO Walkthrough

> **Updated 2026-07-14:** Stale walkthrough content was reconciled with the current RTL implementation by Codex (GPT-5).

**Files covered:** `fifo_bram.v` → `convertible_fifo.v`

These two files implement the core data storage and packet-buffering logic. The FIFO captures one NF2.1 network packet into dual-port BRAM, then allows a processor (CPU or GPU) to read/modify the contents before draining the packet downstream.

> **Refreshed 2026-05-17.** Unchanged from the Lab 8 baseline (commit `44baf38`, 2026-03-25). The 2026-04-13 BCAST refactor, the 2026-04-13 cycle counter, and the 2026-05-10 ARM orchestrator do **not** touch `src/fifo/` -- the FIFO is the system's stable substrate.

---

## 1. fifo_bram.v — 256×72-bit True Dual-Port BRAM

This is the raw storage element. Everything else in the design reads and writes through this BRAM.

### 1.1 Why 72 bits wide?

NF2.1 words are `{ctrl[7:0], data[63:0]}` = 72 bits. By storing the full 72-bit word, we preserve the ctrl byte (which marks packet boundaries) alongside the data. When the packet is drained back out, we can reconstruct the exact NF2.1 word stream.

### 1.2 Why 256 entries deep?

The NF2.1 MTU is ~1500 bytes. At 8 bytes per word, that's ~188 words, so 256 entries (8-bit address) give comfortable storage headroom. In the recorded VP50 mapped build, this 256×72 logical memory uses two RAMB16 blocks in parallel, each supplying a 36-bit-wide slice.

### 1.3 Module Ports

```verilog
module fifo_bram (
    input         clk,
    // Port A
    input  [7:0]  addr_a,          // 8-bit address → 256 locations
    input  [71:0] din_a,           // 72-bit write data (ctrl + data)
    input         we_a,            // Write enable
    output reg [71:0] dout_a,      // 72-bit read data (synchronous, 1-cycle latency)
    // Port B
    input  [7:0]  addr_b,          // Independent address for second port
    input  [71:0] din_b,           // Independent write data
    input         we_b,            // Independent write enable
    output reg [71:0] dout_b       // Independent read data
);
```

**True dual-port** means both ports can read and write independently on every clock cycle. Port A and Port B can access different addresses simultaneously. The inferred configuration is read-first on each individual port. Same-address cross-port collisions, especially simultaneous writes, are not defined by this RTL and must be avoided.

### 1.4 Memory Array and Port Logic

```verilog
    reg [71:0] mem [0:255];        // 256 entries of 72 bits each
```

This is the **BRAM inference pattern** for Xilinx ISE 10.1. XST recognizes `reg [W] mem [0:D-1]` with synchronous read/write and maps it to Block RAM automatically. No `RAMB16` instantiation needed.

```verilog
    // Port A: synchronous read/write
    always @(posedge clk) begin
        if (we_a)
            mem[addr_a] <= din_a;  // Write: non-blocking, happens at clock edge
        dout_a <= mem[addr_a];     // Read: ALWAYS reads, even during write
    end                            //   (read-first: a same-port write/read returns old data)
```

**Key timing:** The read is registered — `dout_a` gets the value of `mem[addr_a]` at the CURRENT clock edge, but the output appears on `dout_a` ONE CYCLE LATER (it's a flip-flop, not a wire). This 1-cycle read latency is fundamental to how the drain pipeline works.

```verilog
    // Port B: synchronous read/write
    always @(posedge clk) begin
        if (we_b)
            mem[addr_b] <= din_b;
        dout_b <= mem[addr_b];
    end
```

Port B is identical. In our design:
- **Port A** is used for FIFO write (network packets in) and nothing else
- **Port B** is used for FIFO read (drain out) AND processor access (CPU/GPU reads/writes)

Port B is time-shared: during FIFO mode, the drain state machine drives it; during CPU/GPU mode, the processor drives it. They never overlap because the `mode` register selects which one has control.

---

## 2. convertible_fifo.v — Packet Buffering + Processor Access

This is the heart of the design. It has three responsibilities:
1. **Receive** one NF2.1 packet from upstream, word by word, into BRAM
2. **Allow processor access** to the buffered data (CPU can read/modify packet contents)
3. **Drain** the (possibly modified) packet downstream, word by word

### 2.1 Module Ports

```verilog
module convertible_fifo (
    input         clk,
    input         reset,
```

Single clock domain (125 MHz on NetFPGA). Synchronous reset.

```verilog
    // NF2.1 input (from upstream module)
    input  [63:0] in_data,        // 64-bit data from upstream (e.g., output_port_lookup)
    input  [7:0]  in_ctrl,        // 8-bit control: 0xFF=header, 0x00=data word
    input         in_wr,          // Write strobe: upstream asserts when data is valid
    output        in_rdy,         // Backpressure: WE accept data only when this is HIGH
```

**NF2.1 handshake:** The upstream module checks `in_rdy` before asserting `in_wr`. A word is transferred when BOTH `in_wr` AND `in_rdy` are high on a clock edge.

```verilog
    // NF2.1 output (to downstream module)
    output [63:0] out_data,       // 64-bit data to downstream (e.g., output_queues)
    output [7:0]  out_ctrl,       // Control byte for downstream
    output        out_wr,         // Write strobe to downstream
    input         out_rdy,        // Backpressure FROM downstream: they accept when HIGH
```

Here `out_wr` is the valid indication: it remains asserted whenever `drain_word_reg` is valid in `S_DRAINING`, even if `out_rdy` is low. A transfer occurs, and the FSM advances, only on an edge where both `out_wr` and `out_rdy` are high.

```verilog
    // Processor access port (directly from CPU MEM stage or GPU)
    input  [7:0]  proc_addr,      // BRAM address from processor (0-255)
    input  [71:0] proc_din,       // 72-bit write data from processor ({ctrl, data})
    input         proc_we,        // Write enable from processor
    output [71:0] proc_dout,      // 72-bit read data to processor
```

This is the **convertible** part. When mode=1 (CPU) or mode=2 (GPU), Port B of the BRAM is driven by these signals instead of the drain logic. The processor can read/write any BRAM address directly, as if it were a regular memory.

```verilog
    // Control
    input  [1:0]  mode,           // 0=FIFO, 1=CPU, 2=GPU
    input         drain_start,    // strobe: begin draining buffered packet
```

`mode` selects who drives Port B. `drain_start` is a one-shot trigger from the wrapper's FIFO-drain register, writable through PCI or the ARM alias window.

```verilog
    // Status
    output        pkt_ready,      // one packet fully buffered and available
    output        fifo_full,      // cannot accept more input
    output        fifo_empty,     // no packet buffered
    output [7:0]  pkt_word_cnt,   // total words in the buffered packet
```

Status outputs wired to the STATUS register, readable from PCI.

```verilog
    // Head/tail register access (for processor)
    input  [7:0]  head_wr_val,    // Write new head pointer value
    input         head_wr_en,     // Head pointer write enable
    input  [7:0]  tail_wr_val,    // Write new tail pointer value
    input         tail_wr_en,     // Tail pointer write enable
    output [7:0]  head_rd,        // Current head pointer (read address)
    output [7:0]  tail_rd         // Current tail pointer (write address)
);
```

Head/tail register access allows the processor to manipulate FIFO pointers. Currently tied off (not used), but available for advanced use cases.

### 2.2 State Machine

```verilog
    localparam S_IDLE          = 3'd0;  // No packet — waiting for input
    localparam S_RECEIVING     = 3'd1;  // Receiving packet words, counting down
    localparam S_PKT_BUFFERED  = 3'd2;  // One complete packet in BRAM — ready for proc access
    localparam S_DRAIN_WAIT1   = 3'd3;  // Drain: present addr 0 to BRAM
    localparam S_DRAIN_WAIT2   = 3'd4;  // Drain: BRAM output now valid, latch first word
    localparam S_DRAINING      = 3'd5;  // Drain: output words to downstream one by one

    reg [2:0] state;
```

The state machine has two "slow" paths that involve BRAM read latency:
- **Receiving** is simple — just write each word as it arrives
- **Draining** needs a 2-cycle startup because BRAM has 1-cycle read latency

```
Lifecycle:  IDLE → RECEIVING → PKT_BUFFERED → DRAIN_WAIT1 → DRAIN_WAIT2 → DRAINING → IDLE
                  ↑ packet in                  ↑ drain_start
                  ↑ ctrl≠0 (header)            ↑ (from PCI or ARM alias)
```

### 2.3 Pointers and Status

```verilog
    reg [7:0] wr_ptr;             // Next write address (increments during receive)
    reg [7:0] rd_ptr;             // Next read address (increments during drain)
    reg [7:0] pkt_len;            // Total words in current packet (from NF2.1 header)
    reg [7:0] words_remaining;    // Countdown during receive
    reg       pkt_stored;         // One full packet in BRAM (gates in_rdy)
    reg [7:0] drain_cnt;          // Words drained so far (for end-of-packet detection)
```

```verilog
    assign head_rd      = rd_ptr;
    assign tail_rd      = wr_ptr;
    assign pkt_ready    = pkt_stored;
    assign fifo_full    = pkt_stored;        // Full = one packet stored (single-packet FIFO)
    assign fifo_empty   = (state == S_IDLE) && !pkt_stored;
    assign pkt_word_cnt = pkt_len;
```

**Single-packet design:** This FIFO stores exactly one packet. `fifo_full = pkt_stored` — once one packet is buffered, no more input is accepted. This simplifies the design enormously (no wrap-around, no multiple-packet bookkeeping).

### 2.4 Input Ready Logic (in_rdy)

```verilog
    // Accept input only in FIFO mode, IDLE or RECEIVING states (not full).
    // Block network input when mode != 0 to prevent Port A writes from
    // corrupting BRAM while CPU/GPU is using Port B.
    assign in_rdy = (mode == 2'd0) &&
                    (state == S_IDLE || state == S_RECEIVING) &&
                    !pkt_stored;
```

Three conditions must ALL be true:
1. **`mode == 0`** — FIFO mode (not CPU or GPU). Without this check, network packets arriving on Port A would overwrite BRAM while the processor is reading/writing via Port B. This was **Bug #2** — the original code was missing this check, and network broadcast traffic corrupted BRAM during CPU tests.
2. **State is IDLE or RECEIVING** — not draining, not buffered
3. **`!pkt_stored`** — not already holding a packet

### 2.5 Port A MUX (Network Write Path)

```verilog
    wire fifo_wr_active = in_wr && in_rdy;   // Actual transfer happening this cycle
```

A word is written to BRAM only when BOTH sides agree: upstream asserts `in_wr` AND we assert `in_rdy`.

```verilog
    always @(*) begin
        if (fifo_wr_active) begin
            bram_addr_a = wr_ptr;              // Write to current write pointer
            bram_din_a  = {in_ctrl, in_data};  // Pack 8-bit ctrl + 64-bit data = 72 bits
            bram_we_a   = 1'b1;                // Enable write
        end else begin
            bram_addr_a = 8'd0;                // Default: don't care (write disabled)
            bram_din_a  = 72'd0;
            bram_we_a   = 1'b0;                // No write
        end
    end
```

Port A is exclusively for network packet input. It never reads (we don't need Port A's `dout_a`).

### 2.6 Port B MUX (Drain OR Processor Access)

```verilog
    always @(*) begin
        case (mode)
            2'd1, 2'd2: begin
                // CPU or GPU mode: processor drives Port B
                bram_addr_b = proc_addr;       // Processor chooses address
                bram_din_b  = proc_din;        // Processor provides write data
                bram_we_b   = proc_we;         // Processor controls write enable
            end
            default: begin
                // FIFO mode: drain logic drives Port B (read-only during drain)
                bram_addr_b = rd_ptr;          // Read from current read pointer
                bram_din_b  = 72'd0;           // Never writes during drain
                bram_we_b   = 1'b0;
            end
        endcase
    end
```

**This is the "convertible" switch.** The same BRAM Port B serves two completely different purposes:
- **Mode 0 (FIFO):** The drain state machine reads words sequentially using `rd_ptr`
- **Mode 1/2 (CPU/GPU):** The processor has random access to any BRAM location

```verilog
    // Processor read output (always wired to Port B output)
    assign proc_dout = bram_dout_b;
```

The processor always sees Port B's read output, regardless of who's driving the address. When the processor drives `proc_addr`, `bram_dout_b` reflects `mem[proc_addr]` (one cycle later due to BRAM latency).

### 2.7 Output Handshake (Drain Path)

```verilog
    reg        drain_data_valid;   // Is drain_word_reg holding valid data?
    reg [71:0] drain_word_reg;     // Latched word being output this cycle
```

```verilog
    assign out_data = drain_word_reg[63:0];        // Lower 64 bits = data
    assign out_ctrl = drain_word_reg[71:64];       // Upper 8 bits = ctrl
    assign out_wr   = drain_data_valid && (state == S_DRAINING);
```

We only assert `out_wr` when:
1. We have a valid word latched (`drain_data_valid`)
2. We're in the DRAINING state (not during the startup wait cycles)

### 2.8 State Machine Logic

#### IDLE State

```verilog
    S_IDLE: begin
        drain_data_valid <= 1'b0;
        if (fifo_wr_active && in_ctrl != 8'd0) begin
            // First word of packet (module header)
            // NF2.1 header: {dst_port, word_length, src_port, byte_length}
            // word_length is in data[47:32], we use low 8 bits: data[39:32]
            wr_ptr  <= wr_ptr + 8'd1;
            pkt_len <= in_data[39:32];
            if (in_data[39:32] <= 8'd1) begin
                // Single-word packet (header only): skip S_RECEIVING
                words_remaining <= 8'd0;
                pkt_stored      <= 1'b1;
                state           <= S_PKT_BUFFERED;
            end else begin
                words_remaining <= in_data[39:32] - 8'd1;
                state           <= S_RECEIVING;
            end
        end
    end
```

**Packet detection:** A packet starts when `ctrl != 0`. In NF2.1, the first word of every packet has `ctrl = 0xFF` (module header). The FIFO retains only `word_length[7:0]` from `data[39:32]`, so the representable supported nonzero range is 1–255 words. A programmed length of 256 truncates to zero, and zero/larger or malformed lengths are not valid inputs to this FSM.

**1-word packet fix (C2):** If `word_length == 1`, the header is the entire packet. We go directly to S_PKT_BUFFERED, skipping S_RECEIVING. Without the `<= 1` test, `words_remaining = 0` and S_RECEIVING's exit condition (`words_remaining == 1`) would never fire. The comparison also keeps a zero value out of S_RECEIVING, but it does not make zero a valid header-only length: the 8-bit drain counter then terminates only after wrapping through 256 transfers.

**Recorded real-stream caveat:** The repository's ARP capture records a header `word_length=8` followed by seven stored data words, while the FSM treats the length as the total number of emitted words including the header. Supporting handoff notes consequently record a drop-last-word/off-by-one behavior and a sacrificial-trailer workaround. The current RTL does not reconcile those two conventions; real packet framing should not be assumed correct from the simulation convention alone.

#### RECEIVING State

```verilog
    S_RECEIVING: begin
        if (fifo_wr_active) begin
            wr_ptr          <= wr_ptr + 8'd1;            // Advance write pointer
            words_remaining <= words_remaining - 8'd1;   // Count down
            if (words_remaining == 8'd1) begin           // This is the LAST word
                pkt_stored <= 1'b1;                      // Packet complete
                state      <= S_PKT_BUFFERED;            // → ready for processing
            end
        end
    end
```

We count words based on `word_length` from the header. When the last word arrives, `pkt_stored` goes HIGH, blocking further input (`in_rdy` goes LOW).

#### PKT_BUFFERED State

```verilog
    S_PKT_BUFFERED: begin
        if (head_wr_en) rd_ptr <= head_wr_val;   // Allow processor to set read pointer
        if (tail_wr_en) wr_ptr <= tail_wr_val;   // Allow processor to set write pointer

        if (drain_start) begin
            rd_ptr    <= 8'd0;                    // Start reading from address 0
            drain_cnt <= 8'd0;                    // Reset drain counter
            state     <= S_DRAIN_WAIT1;           // → begin drain pipeline
        end
    end
```

The FIFO sits in this state while the CPU/GPU processes the packet. The processor reads and writes BRAM via Port B (through the proc port MUX). Before pulsing `drain_start`, software must restore mode 0 so the FIFO's `rd_ptr` actually controls physical BRAM Port B; the FSM itself does not reject a drain request made in mode 1 or 2.

#### Drain Pipeline (3 states for 1-cycle BRAM latency)

This is the most subtle part of the design. BRAM has **1-cycle read latency** — you present an address on cycle N, and the data appears on cycle N+1. The drain pipeline accounts for this:

```verilog
    S_DRAIN_WAIT1: begin
        // rd_ptr=0 is on bram_addr_b (combinational mux in FIFO mode).
        // BRAM will register dout_b <= mem[0] on THIS posedge.
        // But we can't read dout_b yet (non-blocking: old value).
        // Advance rd_ptr so BRAM starts reading addr 1 next cycle.
        rd_ptr <= rd_ptr + 8'd1;     // Now rd_ptr=1 → BRAM reads addr 1 next cycle
        state  <= S_DRAIN_WAIT2;
    end
```

**Cycle N (DRAIN_WAIT1):**
- `bram_addr_b = rd_ptr = 0` (combinational)
- BRAM latches `mem[0]` internally (registered read)
- But `bram_dout_b` still has OLD data (non-blocking assignment)
- We advance `rd_ptr` to 1 so next cycle BRAM reads address 1

```verilog
    S_DRAIN_WAIT2: begin
        // bram_dout_b now has mem[0] (registered output from last posedge).
        // Latch it into drain_word_reg and start outputting.
        drain_word_reg   <= bram_dout_b;     // Latch word 0
        drain_data_valid <= 1'b1;            // Mark as valid for output
        rd_ptr           <= rd_ptr + 8'd1;   // Now rd_ptr=2 → BRAM reads addr 2
        state            <= S_DRAINING;
    end
```

**Cycle N+1 (DRAIN_WAIT2):**
- `bram_dout_b` now contains `mem[0]` (updated by last clock edge)
- Latch it into `drain_word_reg`
- BRAM is reading address 1 this cycle (will be available next cycle)

#### DRAINING State

```verilog
    S_DRAINING: begin
        if (out_rdy && drain_data_valid) begin
            drain_cnt <= drain_cnt + 8'd1;
            if (drain_cnt + 8'd1 == pkt_len) begin
                // Last word accepted by downstream
                drain_data_valid <= 1'b0;
                pkt_stored       <= 1'b0;        // FIFO now empty
                wr_ptr           <= 8'd0;         // Reset pointers
                rd_ptr           <= 8'd0;
                pkt_len          <= 8'd0;
                drain_cnt        <= 8'd0;
                state            <= S_IDLE;       // → ready for next packet
            end else begin
                // Pipeline: bram_dout_b has the next word (read last cycle)
                drain_word_reg <= bram_dout_b;   // Latch next word
                rd_ptr         <= rd_ptr + 8'd1; // Advance to read word after next
            end
        end
        // If !out_rdy, the currently presented drain_word_reg is held.
    end
```

**Steady-state drain pipeline:**
```
Cycle  bram_addr_b  bram_dout_b   drain_word_reg  out_data
  N      rd_ptr=2    mem[1]        mem[0]          mem[0] → downstream
  N+1    rd_ptr=3    mem[2]        mem[1]          mem[1] → downstream
  N+2    rd_ptr=4    mem[3]        mem[2]          mem[2] → downstream
```

The pipeline reads one word ahead: while `drain_word_reg` is being output, `bram_dout_b` already has the next word ready. This works at one word per cycle when `out_rdy` remains asserted.

**Current backpressure limitation:** the pending prefetched word exists only in `bram_dout_b`. At entry to `S_DRAINING`, `rd_ptr` has already advanced past that word. If `out_rdy` goes low mid-drain, the synchronous BRAM output is overwritten by the following address even though `drain_word_reg` remains stable. When readiness returns, the FSM can therefore skip the prefetched word. The current drain path is not lossless under mid-packet output stalls; it requires continuous `out_rdy` after draining begins.

### 2.9 Complete Data Flow

```
                    ┌─────────────────────────────────────────┐
                    │          convertible_fifo                │
                    │                                          │
  in_data/ctrl ───► │  Port A MUX ──► ┌──────────┐            │
  in_wr ──────────► │  (write only)   │ fifo_bram│            │
  in_rdy ◄──────── │                  │ 256×72   │            │
                    │                  │          │ ──► out_data/ctrl
                    │  Port B MUX ──► │ Port A   │     out_wr
                    │  mode=0: rd_ptr │ Port B   │     out_rdy
                    │  mode=1: proc   └──────────┘            │
                    │  mode=2: proc                           │
                    │                 drain_word_reg           │
                    │                   ↓                      │
                    │                 out_data/ctrl            │
                    └─────────────────────────────────────────┘
```

---

## Summary — What Batch 1 Establishes

1. **fifo_bram.v** — the raw storage: 256×72-bit true dual-port BRAM, inferred by ISE
2. **convertible_fifo.v** — the intelligence:
   - 6-state FSM for packet lifecycle (receive → buffer → drain)
   - Port B MUX switches between FIFO read and processor access based on `mode`
   - Single-packet design with `pkt_stored` gating `in_rdy`
   - Drain pipeline handles 1-cycle BRAM read latency with 2-cycle startup
   - Input backpressure through `in_rdy`; output uses valid/ready signaling but has a documented mid-drain prefetch-stall defect

**Next batch:** NF2.1 wrapper + PCI register interface (`lab8_wrapper.v`)
