# How the Network Packet Tests Work — Technical Explanation

This document explains the data path and control flow behind each test,
referencing the Verilog RTL and the Perl `lab8reg` script. It is written
for the team's own understanding, not for the report.

---

## 1. How Packets Enter the FIFO

### The NF2.1 pipeline

The NetFPGA reference NIC data path is:

```
MAC0 RX → input_arbiter → output_port_lookup → [lab8_wrapper] → output_queues → MAC TX
```

Our `lab8_wrapper` replaces the processor module in this chain. Inside it,
`convertible_fifo` sits on the data path:

```verilog
// convertible_fifo.v — Port A handles network I/O
wire fifo_wr_active = in_wr && in_rdy;

always @(*) begin
    if (fifo_wr_active) begin
        bram_addr_a = wr_ptr;
        bram_din_a  = {in_ctrl, in_data};   // 72 bits: 8-bit ctrl + 64-bit data
        bram_we_a   = 1'b1;
    end ...
end
```

When a packet arrives from the upstream module, each 72-bit word (ctrl + data)
is written to BRAM Port A at the current `wr_ptr`, which increments each cycle.

### How `in_rdy` stalls after one packet

```verilog
assign in_rdy = (mode == 2'd0)
             && (state == S_IDLE || state == S_RECEIVING)
             && !pkt_stored;
```

Three conditions must be met:
1. `mode == 0` (FIFO mode, not CPU or GPU mode)
2. State machine is idle or mid-receive
3. No packet is already buffered (`!pkt_stored`)

Once `pkt_stored` goes high (all words received), `in_rdy` drops to 0 and
the upstream module is backpressured. The FIFO holds exactly one packet.

The `mode` gating is critical: when we switch to mode 1 (CPU) or mode 2 (GPU),
`in_rdy` goes low even if the FIFO is empty. This prevents new network packets
from writing into BRAM via Port A while the CPU or GPU is accessing BRAM via
Port B.

### How word count is determined

```verilog
if (fifo_wr_active && in_ctrl != 8'd0) begin
    // NF2.1 header: {dst_port[15:0], word_length[15:0], src_port[15:0], byte_length[15:0]}
    pkt_len         <= in_data[39:32];       // low 8 bits of word_length
    words_remaining <= in_data[39:32] - 8'd1;
    state           <= S_RECEIVING;
end
```

The first word with `in_ctrl != 0` is the module header. `in_ctrl = 0xFF`
marks this as an IOQ header. The word_length field at `data[47:32]` tells
the FIFO how many total words to expect (including the header itself).

### Why we captured an ARP, not an ICMP

node0 tried to ping 10.0.0.2 (the FPGA's nf2c0 IP). Before it can send
an ICMP echo request, it must resolve 10.0.0.2's MAC address via ARP.
node0 sent an ARP broadcast, which arrived on MAC0 and was captured by our
FIFO. Since the FIFO held the ARP and never forwarded it to the CPU queue,
the FPGA's Linux kernel never saw the ARP request and never sent a reply.
node0 got "Destination Host Unreachable."

The ARP packet itself is a valid 60-byte Ethernet frame. For testing purposes,
it exercises the same data path as any other packet type.

---

## 2. How `packet_echo` Works (Header Rewrite + Drain)

### The problem: dst_port

When `output_port_lookup` (reference_nic version) receives a packet from
MAC0, it sets `dst_port = 0x0002` (CPU0 queue). If we drain the packet
as-is, the output_queues module would route it to the CPU DMA queue
(back to the Linux kernel), not out to the wire.

To send the packet out MAC0, we need `dst_port = 0x0001`. This requires
rewriting BRAM[0] (the module header).

### Why the CPU can't rewrite the header

The CPU accesses FIFO BRAM through the proc port mux in `lab8_wrapper.v`:

```verilog
if (cpu_drives_proc) begin
    fifo_proc_din  = {8'h00, cpu_ext_mem_din};   // ctrl hardcoded to 0x00
    ...
end
```

The CPU's 64-bit write is prepended with `ctrl = 8'h00`. But the header
word needs `ctrl = 0xFF`. Writing BRAM[0] via the CPU would corrupt the
ctrl byte from 0xFF to 0x00, and the output_queues would not recognize it
as a module header.

### Why PCI CAN rewrite the header

The PCI path preserves the full 72-bit word:

```verilog
end else begin   // PCI (default)
    fifo_proc_din  = {reg_bram_wctrl[7:0], reg_bram_wd_hi, reg_bram_wd_lo};
    fifo_proc_we   = bram_pci_wr_strobe;
end
```

The `reg_bram_wctrl` register allows software to set the ctrl byte to any
value. The `lab8reg` script's `bram_write` subroutine sets all four PCI
registers:

```perl
sub bram_write {
    my ($bram_addr, $ctrl, $hi, $lo) = @_;
    regwrite($BRAM_ADDR_REG,  $bram_addr & 0xFF);
    regwrite($BRAM_WD_LO_REG, $lo);
    regwrite($BRAM_WD_HI_REG, $hi);
    regwrite($BRAM_WCTRL_REG, $ctrl & 0xFF);     # <-- this is the key
    regwrite($BRAM_CMD_REG,   0x1);               # write strobe
}
```

In `packet_echo`, the header rewrite constructs a new upper 32 bits with
the desired dst_port while preserving word_length:

```perl
# dst_port is data[63:48] = upper 16 bits of $hhi
my $new_hi = (($new_dst & 0xFFFF) << 16) | ($word_len & 0xFFFF);
bram_write(0, 0xFF, $new_hi, $hlo);   # ctrl=0xFF preserved
```

### How drain works

After the header rewrite, `packet_echo` switches back to FIFO mode and
triggers drain:

```perl
fifo_set_mode(0);     # regwrite(FIFO_MODE_REG, 0)
fifo_drain();         # regwrite(FIFO_DRAIN_REG, 1)  — auto-clear strobe
```

The FIFO state machine transitions through:

```
S_PKT_BUFFERED → S_DRAIN_WAIT1 → S_DRAIN_WAIT2 → S_DRAINING
```

During S_DRAINING, the FIFO reads words from BRAM Port B and outputs them:

```verilog
assign out_data = drain_word_reg[63:0];
assign out_ctrl = drain_word_reg[71:64];   // ctrl byte from BRAM is preserved
assign out_wr   = drain_data_valid && (state == S_DRAINING);
```

The output goes to `output_queues`, which reads `out_ctrl` to identify
the module header (ctrl=0xFF) and routes the packet to the port specified
by `dst_port` in the header data. Since we wrote `dst_port = 0x0001`,
the packet exits through MAC0 to node0.

---

## 3. How the CPU Test Works (Test D)

### Setup

```bash
./lab8reg cpu_load_imem test_4t_v2.hex    # loads 512 words into CPU IMEM, holds CPU in reset
./lab8reg mode 1                          # blocks new packets (in_rdy gated by mode)
```

`cpu_load_imem` keeps the CPU in reset after loading. This is important because
mode=1 alone doesn't prevent the CPU from running — the `cpu_drives_proc` signal
depends on both mode AND cpu_running:

```verilog
assign cpu_drives_proc = (reg_fifo_mode_r[1:0] == 2'd1) && cpu_running;
```

While cpu_running=0, PCI controls the proc port (for `fifo_read` to work).

### What the CPU program does

Thread 0 of `test_4t_v2.hex`:
```
MOV  r1, #128        ; r1 = 128 (FIFO BRAM base in CPU address space)
LDR  r2, [r1, #1]    ; r2 = mem[129] = FIFO BRAM word 1 (lower 32 bits)
ADD  r2, r2, #42     ; r2 = r2 + 42
STR  r2, [r1, #1]    ; mem[129] = r2  → writes back to FIFO BRAM word 1
HALT
B .                   ; self-branch (prevents PC wrap, see known_issues.md)
```

The CPU's `data_mem.v` maps addresses with bit [7]=1 to the external memory
port, which connects to the FIFO BRAM via the proc port mux. So CPU address
129 (128 + 1) maps to FIFO BRAM address 1.

### Why only the lower 32 bits changed

The ARM CPU in this design has 32-bit registers. A LDR/STR accesses the lower
32 bits of the 64-bit BRAM word. The upper 32 bits are untouched.

Before: `0xffffffff_ffffa036` → lower 32 = `0xffffa036`
After:  `0xffffffff_ffffa060` → lower 32 = `0xffffa060`

`0xffffa060 - 0xffffa036 = 0x2A = 42`. Correct.

### Packet routing after CPU modification

After `cpu_stop`, the CPU is held in reset and `cpu_drives_proc` goes low.
PCI regains control of the proc port. `packet_echo 01` then rewrites the
header and drains the modified packet, same as Test B.

---

## 4. How the GPU Test Works (Test E)

### DMA: FIFO BRAM → GPU DMEM

```bash
./lab8reg mode 2                          # GPU mode
./lab8reg dma_fifo_to_gpu 1 0 4           # FIFO[1..4] → GPU DMEM[0..3]
```

The DMA engine is a 3-state FSM in `lab8_wrapper.v`:

```
IDLE → READ → COPY (repeats for each word) → IDLE
```

For FIFO→GPU direction (`dma_dir=0`):
- DMA drives the FIFO proc port to read BRAM at `dma_fifo_base + dma_rd_ptr`
- One cycle later (BRAM read latency), the data appears at `fifo_proc_dout[63:0]`
- DMA writes it to GPU DMEM at `dma_gpu_base + dma_wr_ptr`
- Copies 1 word per cycle after 1-cycle pipeline startup

The skip of BRAM[0] (starting at FIFO address 1, GPU address 0) is deliberate:
BRAM[0] is the module header, not packet payload. The GPU should only process
actual Ethernet frame data.

### What vec_add_i16 does

The GPU is a 4-lane SIMD processor with 64-bit registers (4 x int16 per register).
`vec_add_i16.hex` contains 5 instructions:

```
VLOAD  v0, DMEM[0]     ; v0 = FIFO BRAM[1] data
VLOAD  v1, DMEM[1]     ; v1 = FIFO BRAM[2] data
VADD   v2, v0, v1      ; v2[lane_i] = v0[lane_i] + v1[lane_i], 16-bit wrapping
VSTORE v2, DMEM[2]     ; write result to DMEM[2] → will be copied back to BRAM[3]
HALT
```

Each 64-bit word is treated as 4 independent 16-bit integers. The addition
wraps at 16 bits (no carry between lanes).

### Verifying the arithmetic

```
v0 (BRAM[1]): FFFF  FFFF  FFFF  A036
v1 (BRAM[2]): 9F0A  106B  0806  0001
              ----  ----  ----  ----
v2 (BRAM[3]): 9F09  106A  0805  A037
```

Lane [63:48]: `FFFF + 9F0A = 19F09`, truncated to 16 bits = `9F09`.
Lane [47:32]: `FFFF + 106B = 1106A`, truncated to 16 bits = `106A`.
Lane [31:16]: `FFFF + 0806 = 10805`, truncated to 16 bits = `0805`.
Lane [15:0]:  `A036 + 0001 = A037`. No overflow.

All four lanes match the observed output.

### DMA: GPU DMEM → FIFO BRAM

```bash
./lab8reg dma_gpu_to_fifo 0 1 4           # GPU DMEM[0..3] → FIFO[1..4]
```

Same DMA engine, reverse direction (`dma_dir=1`):
- Reads GPU DMEM at `dma_gpu_base + dma_rd_ptr`
- Writes to FIFO BRAM at `dma_fifo_base + dma_wr_ptr`

The write path for GPU→FIFO:

```verilog
// GPU→FIFO: write to FIFO BRAM
fifo_proc_addr = dma_fifo_base + dma_wr_ptr;
fifo_proc_din  = {8'h00, gpu_dmem_rd_data};   // ctrl = 0x00 for data words
fifo_proc_we   = (dma_state == DMA_COPY);
```

Note `ctrl = 8'h00` — this is correct for data words (BRAM[1..N]). Only the
header (BRAM[0]) needs `ctrl = 0xFF`, and the DMA never touches BRAM[0].

After DMA completes, `packet_echo 01` rewrites the header and drains,
same as the other tests.

---

## 5. Why These Tests Cover the Design's Capabilities

| Capability | What is tested | How it is verified |
|---|---|---|
| **Packet capture** (Port A write) | FIFO receives an Ethernet frame from the physical MAC | Header and payload bytes decode correctly as ARP |
| **PCI inspection** (Port B read) | `fifo_read` reads all 72 bits including ctrl | ctrl=0xFF on header, ctrl=0x00 on data, content matches |
| **PCI header rewrite** (Port B write with ctrl) | `bram_write_full` / `packet_echo` writes BRAM[0] with ctrl=0xFF | Readback confirms new dst_port and ctrl byte preserved |
| **Packet drain** (Port A → output) | FIFO outputs stored words to output_queues | Drain completes, FIFO returns to empty state |
| **CPU read/write** (Port B via proc mux) | CPU reads BRAM[1] via ext_mem, modifies, writes back | BRAM[1] content changes by exactly +42 |
| **Mode gating** (`in_rdy`) | mode=1 or 2 blocks new packets from overwriting BRAM | No BRAM corruption during ~30 seconds of IMEM loading |
| **DMA FIFO→GPU** | DMA copies BRAM data words to GPU DMEM | GPU DMEM matches FIFO content (verified in previous tests) |
| **GPU SIMD execution** | vec_add_i16 kernel runs on packet data | Result matches hand-calculated int16 sum, all 4 lanes |
| **DMA GPU→FIFO** | DMA copies GPU DMEM results back to FIFO BRAM | BRAM[3] contains GPU output, other words unchanged |
| **Header routing** | Rewritten dst_port controls output port selection | Packet exits through specified MAC port (drain succeeds) |

The only path not directly testable from the FPGA side is confirming the
drained packet arrives at node0 — `tcpdump` is not available on the sub-nodes
due to restricted sudo. However, the PCI readback of the rewritten header
and the drain state transition (FIFO returns to empty) confirm the output
path is exercised correctly.
