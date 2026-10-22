# Deep Research Report: High-Frequency Trading on FPGAs and SmartNICs

**Purpose:** Evaluate whether HFT is a viable final project candidate for EE533 Team 5's NetFPGA V2 (Virtex-II Pro XC2VP50) with custom GPU coprocessor (4-lane BF16 SIMD, 8KB DMEM, 1024 instructions).

**Date:** 2026-03-24

---

## 1. What HFT Tasks Actually Run on FPGAs in Industry?

Industry FPGA-based HFT systems implement a well-defined pipeline of tasks, each targeting a specific latency-critical function. The pipeline is typically:

**Packet Receive -> Protocol Decode -> Market Data Parse -> Order Book Update -> Signal Generation -> Risk Check -> Order Generation -> Packet Transmit**

### 1.1 Market Data Feed Handling (Protocol Parsing)

The most common and foundational FPGA task. FPGAs decode financial protocols at the wire level:

- **FAST protocol** (FIX Adapted for STreaming): Compressed market data format used by many exchanges. FPGA decoding achieves 2.6 us reception + decode latency, vs. tens of microseconds in software. (Morris, Thomas, Luk -- Imperial College London, IEEE HotI 2009)
- **ITCH protocol** (NASDAQ TotalView): Uncompressed order-by-order feed. FPGA-based ITCH feed handlers achieve 2.7 us turnaround latency with very little jitter. (IEEE Low-Latency FPGA Financial Data Feed Handler)
- **FIX protocol**: The standard for order entry and execution reports.
- **OUCH protocol**: NASDAQ's order entry protocol.

The FPGA advantage: parsing can be fully pipelined and parallelized. A state-of-the-art ITCH parser achieves sub-25ns per-message parsing latency, processing up to 8.5 million messages/second during peak hours.

### 1.2 Order Book Construction and Maintenance

Maintaining a sorted order book (price-time priority) from streaming market updates:

- **Cuckoo hashing approach**: Average latency of 253ns per order book operation while tracking 119,275 instruments using 144 Mbit QDR SRAM. (IEEE "Low Latency Book Handling in FPGA for HFT," 2014)
- **Hybrid binary-linear search**: Maintains top-of-book (best bid/ask) and market depth using combined data structures on FPGA. (IEEE FPL 2023)
- **Heap-based structures**: ~80ns average for insertion/deletion.
- **Scalable architectures**: 0.5-1.3 us per message on average, 1-2 orders of magnitude faster than software.

### 1.3 Signal Generation / Trading Strategy Execution

The decision-making logic that determines whether to trade:

- **Technical indicators**: MACD, RSI, Aroon implemented on Zynq-7000 SoC, achieving 30x speedup over software for Bitcoin/Ethereum data. (ScienceDirect, April 2024)
- **Statistical arbitrage**: Detecting when correlated assets diverge for mean-reversion trades. CPU: 100-500 us. FPGA: sub-microsecond.
- **Moving average crossover**: Buy when short MA crosses above long MA, sell on reverse crossing. Simple streaming computation natural for FPGA.
- **Order book imbalance**: Ratio = (BidVol - AskVol) / (BidVol + AskVol). FPGA implementations compute this in <25ns across multiple price levels.

### 1.4 Pre-Trade Risk Checks

Regulatory requirement (SEC Rule 15c3-5, MiFID II). FPGAs perform inline:

- Position limit checks (is this order within allowed exposure?)
- Credit/collateral checks
- Price reasonableness checks (is this order within a valid price band?)
- Notional value limits

These run at nanosecond speeds but only check simple thresholds -- they do not require complex computation.

### 1.5 Order Generation and Transmission

Converting internal trade decisions into exchange-compliant order messages (FIX, OUCH) and transmitting with minimal latency.

### 1.6 Portfolio Risk Monitoring

Continuous real-time assessment of portfolio value and loss scenarios. This was historically done end-of-day but FPGAs enable continuous monitoring. Less latency-critical than the trading path itself.

### 1.7 Options Pricing (Black-Scholes)

A well-studied FPGA application. Black-Scholes on Virtex-II Pro achieves computation in ~1% of the time compared to Mathematica. Speedups of 11-146x on Virtex-IV family depending on data types and widths. One implementation processes 180 million transactions/second at 179 MHz with 208 clock cycles initial latency.

---

## 2. Realistic Latency Requirements

### 2.1 The Ultra-Low-Latency Tier (Sub-Microsecond)

The most competitive HFT strategies (market-making, statistical arbitrage on correlated instruments) require tick-to-trade latency under 1 microsecond. As of 2024, leading firms achieve single to double-digit nanosecond tick-to-trade latency on FPGA/ASIC.

Key benchmarks from industry:
- **Exablaze/Cisco Nexus K3P-S**: Software trigger-to-response latency as low as 568ns
- **Algo-Logic FPGA tick-to-trade**: Sub-microsecond end-to-end
- **Magmio FPGA system**: Average 480ns round-trip latency
- **ECE1373 (U of Toronto) project**: <450ns roundtrip using FAST decoder + order book on Xilinx FPGA
- **Leading prop-trading firm** (cited in literature): Replaced 10 us CPU path with 250ns FPGA pipeline (40x improvement)

Pipeline stage breakdown for a typical FPGA HFT system:
| Stage | Latency |
|-------|---------|
| Ethernet MAC receive | ~15 ns |
| Protocol parsing (ITCH) | 20-25 ns |
| Order book update | 30-40 ns (or 253 ns with cuckoo hashing) |
| Signal evaluation | 10-50 ns (simple threshold) |
| Risk check | 10-30 ns |
| Order generation + transmit | 20-50 ns |
| **Total pipeline** | **100-250 ns** |

### 2.2 The Medium-Latency Tier (1-100 Microseconds)

Several HFT-adjacent tasks operate at microsecond timescales and are still commercially valuable:

- **ML inference for alpha signals**: 5-10 us margin between successful and unsuccessful trades in many "trade races." ML inference "often takes up most of the latency of the trading loop."
- **FAST protocol decoding**: 2.6 us (still valuable, just not the absolute fastest)
- **ITCH feed handling**: 2.7 us in early academic implementations
- **Monte Carlo risk calculations**: GPU-accelerated at 100+ us (50-800x faster than CPU)
- **Gradient Boosted Tree inference**: Sub-microsecond achievable on FPGA (Xelera)

### 2.3 Tasks That Do NOT Require Sub-Microsecond Latency

Several commercially important financial computing tasks operate at millisecond to second timescales:

- **Alpha signal computation**: Short-term direction prediction, liquidity shift forecasting, volatility estimation. The signal calculation itself may be slower -- the critical latency is in order execution, not signal generation.
- **Risk calculations**: Portfolio VaR, stress testing, exposure aggregation. Historically end-of-day; now moving toward real-time but at ms timescales.
- **VWAP computation**: Tracking volume-weighted average price across a trading session. Updated on each trade but the result is used over minutes/hours.
- **Market microstructure analysis**: Order flow imbalance, VPIN (Volume-Synchronized Probability of Informed Trading), trade classification. These are computed over buckets of trades, not per-tick.
- **Backtesting and strategy optimization**: Offline or near-real-time.
- **Regulatory reporting**: Post-trade, seconds to minutes acceptable.

**Key insight for this project**: The signal generation / feature extraction tier at 1-10 us is a realistic target. The project does NOT need to compete with sub-100ns market-making systems.

---

## 3. Academic Papers and University Projects

### 3.1 Directly Relevant University Course Projects

**Columbia University CSEE 4840 (Spring 2024) -- "HFT Book Builder"**
- Platform: DE1-SoC (Altera/Intel FPGA)
- Implemented: ITCH protocol parser + order book construction
- Course: Embedded System Design (Prof. Stephen Edwards)
- Status: Full report with implementation details available

**MIT 6.111 (Fall 2019) -- "HFT Accelerator"**
- Platform: Course FPGA board (likely Artix-7 based)
- Implemented: Market data processing and order generation pipeline
- Student team: Endrias, Tony, Natnael

**University of Toronto ECE1373 (2016) -- "HFT on FPGA"**
- Platform: Xilinx FPGA via Vivado HLS
- Implemented: FAST protocol decoder, order book management, threshold/filtering
- Architecture: 4 IP cores communicating via AXI Streams
- Latency: <450ns roundtrip
- Language: 71.2% Verilog, 16.1% VHDL

**University of Waterloo -- "Hardware Accelerated Trading System"**
- Platform: **NetFPGA** (the same platform family as this project)
- Implemented: Cross-market equity trading strategy with FIX 4.2 compliance
- Sponsor: Investment Technology Group, Inc. (ITG)
- Target: Microsecond-level trade execution
- Notable: This is the closest precedent -- a student project using NetFPGA specifically for financial trading

**NYU FRE Capstone -- "FPGA Orderbook Analysis"**
- Platform: Xilinx Zynq-7020
- Implemented: LSTM neural network for order book pattern detection
- Model: Single LSTM layer, 32 hidden units, 8-bit quantized
- Input: 5 timesteps of 64 market features
- Estimated latency: 2.52 us inference
- Resource utilization: 71.7% LUTs, 47.1% BRAM
- Accuracy: Macro F1 = 0.41 (limited by 98% "no change" class imbalance)
- Tool flow: PyTorch + Brevitas -> ONNX -> FINN (not fully completed)

### 3.2 Key Academic Papers

**"High Frequency Trading Acceleration using FPGAs" (UCSC -- Leber, Geib, Litz)**
- Platform: Xilinx Virtex-4 FX100
- Implemented: Complete HFT pipeline in synthesizable Verilog RTL
- Features: Hardware Ethernet/IP/UDP + FAST protocol decoding
- Architecture: HT-core at 200 MHz, HTAX on-chip network at 160 MHz, GbE MAC at 125 MHz
- Result: >70% latency reduction vs. software

**"FPGA Accelerated Low-Latency Market Data Feed Processing" (Imperial College London, IEEE HotI 2009)**
- Authors: Morris, Thomas, Luk
- Focus: FAST-compressed OPRA market data feed
- Result: 4 us average latency from packet arrival to message delivery
- Significance: One of the foundational papers in the field

**"Low Latency Book Handling in FPGA for HFT" (IEEE 2014)**
- Cuckoo hashing for order book
- 253ns average latency, 119,275 instruments
- 144 Mbit QDR SRAM

**"Building Low-Latency Order Books with Hybrid Binary-Linear Search" (IEEE FPL 2023)**
- Novel data structure combining binary and linear search
- Optimized for maintaining top-of-book on FPGA

**"Speed vs. Efficiency: HFT Algorithms on FPGA using Zynq SoC" (ScienceDirect, April 2024)**
- Platform: Xilinx Zynq-7000
- Implemented: MACD, RSI, Aroon indicators
- Applied to: Bitcoin and Ethereum data
- Result: MACD achieves 30x speedup over software
- Significance: Shows technical indicators on small/medium FPGAs

**"Low-Latency FPGA Based Financial Data Feed Handler" (IEEE)**
- Platform: Stone Ridge RDX-11
- Implemented: ITCH feed handler
- Result: 2.7 us turnaround latency with minimal jitter

**"FPGA-Based Design of Black-Scholes Financial Model" (2013)**
- Platform: Virtex-II Pro (same family as XC2VP50)
- Implemented: Black-Scholes options pricing
- Result: ~1% of Mathematica computation time

**"FPGA-based Block Minifloat Training Accelerator for Time Series Prediction" (ACM TRETS)**
- Uses block minifloat (BM) arithmetic with 4-bit DSP packing
- Achieves 779 Gops throughput
- Applications: anomaly detection, HFT, sensor prediction

### 3.3 Open-Source Projects

- **Kodoh/Orderbook** (GitHub): Open-source HFT order book with FPGA acceleration, C++17, MIT license
- **mustafabbas/ECE1373_2016_hft_on_fpga** (GitHub): U of Toronto course project, FAST decoder + order book in Verilog
- **XhovaniM8/fpga-orderbook-analysis** (GitHub): NYU capstone, LSTM on Zynq-7020
- **OpenResearchInstitute/lowpass_ema** (GitHub): EMA filter in VHDL for FPGA

---

## 4. Realistic HFT-Adjacent Application for This Hardware

### 4.1 Hardware Constraints Recap

| Resource | Value | Implication |
|----------|-------|-------------|
| GPU DMEM | 1024 x 64-bit (8 KB) | ~4096 BF16 values. After I/O buffers, ~2000-3000 usable for weights |
| GPU IMEM | 1024 x 32-bit | Enough for looped matrix-vector multiply |
| Compute | 4-lane BF16 SIMD FMA + ReLU | 4 multiply-accumulates per cycle |
| Clock | 125 MHz (with timing violations) | ~8ns cycle, ~40ns for a 5-cycle FMA pipeline |
| Data path | Packet -> FIFO BRAM -> DMA -> GPU -> DMA -> FIFO -> Packet | End-to-end in hardware |
| Round-trip latency | ~5 us estimated (DMA + kernel + DMA) | Too slow for sub-us market making |
| Slice utilization | 96% | No room for new RTL |

### 4.2 What Is Realistic: Market Data Feature Extraction + ML Scoring

The best fit for this hardware is NOT the ultra-low-latency tick-to-trade pipeline (that requires sub-100ns and dedicated protocol parsers). Instead, the project fits the **"ML inference on streaming market features"** tier.

**Proposed application: Streaming Market Microstructure Scorer**

A host or upstream system extracts features from market data (order book snapshots, trade ticks) and sends compact feature vectors as UDP packets. The SmartNIC runs a small MLP to produce a score (e.g., short-term price direction, order flow toxicity, or anomaly flag). The result is written back into the packet and forwarded.

### 4.3 Candidate Sub-Applications (Ranked by Feasibility)

#### Candidate A: Trade Flow Classifier (Buy/Sell Pressure Scoring)

**What it does**: Classify whether recent trading activity indicates net buying or selling pressure. This is the hardware equivalent of the Lee-Ready algorithm or Bulk Volume Classification, but using a learned MLP instead of simple rules.

**Input features** (computed by host from tick stream):
- Price returns over multiple horizons (1s, 5s, 30s): 3 features
- Volume imbalance at best bid/ask: 1 feature
- Trade arrival rate: 1 feature
- Spread (ask - bid): 1 feature
- Order book imbalance at 3 depth levels: 3 features
- Recent trade direction (fraction buyer-initiated): 1 feature
- **Total: ~10-15 BF16 features = 3-4 DMEM words**

**Model**: MLP 15 -> 16 -> 8 -> 3 (buy/hold/sell)
| Component | BF16 params | DMEM words |
|-----------|-------------|------------|
| Layer 1: 15x16 + 16 bias | 256 | 64 |
| Layer 2: 16x8 + 8 bias | 136 | 34 |
| Layer 3: 8x3 + 3 bias | 27 | 7 |
| I/O + scratch | ~30 | 8 |
| **Total** | **~449** | **~113 / 1024 (11%)** |

**Training data**: Tick-by-tick data with labels derived from subsequent price movement. Publicly available from Lobster (NASDAQ), Kaggle financial datasets, or cryptocurrency exchanges.

**Why it works on this hardware**: Tiny model, clean packet mapping, the host does the heavy feature extraction, and the SmartNIC provides low-latency scoring of each feature vector.

**Commercial relevance**: Trade flow classification is used by market makers to adjust quotes, by institutional traders to minimize market impact, and by exchanges for surveillance.

#### Candidate B: Order Flow Toxicity Monitor (VPIN-inspired)

**What it does**: Compute a real-time toxicity score indicating the probability that current order flow is dominated by informed traders. High toxicity warns market makers to widen spreads or reduce exposure.

**Input features** (host computes volume-bucketed statistics):
- Buy volume fraction in last N volume buckets: ~8-16 features
- Volume arrival rate deviation from historical: 1 feature
- Price volatility in recent buckets: 1 feature
- Spread dynamics: 1 feature
- **Total: ~12-20 BF16 features**

**Model**: MLP 20 -> 16 -> 8 -> 1 (toxicity score, 0-1)
| Component | BF16 params | DMEM words |
|-----------|-------------|------------|
| Layer 1: 20x16 + 16 bias | 336 | 84 |
| Layer 2: 16x8 + 8 bias | 136 | 34 |
| Layer 3: 8x1 + 1 bias | 9 | 3 |
| I/O + scratch | ~30 | 8 |
| **Total** | **~511** | **~129 / 1024 (13%)** |

**Background**: VPIN was developed by Easley, Lopez de Prado, and O'Hara. It notably spiked one hour before the May 6, 2010 Flash Crash. A learned approximation of VPIN (or a more general toxicity metric) could be the target.

**Commercial relevance**: Every market maker needs this. Virtu Financial, Citadel Securities, Jump Trading all monitor order flow toxicity in real time.

#### Candidate C: Simple Alpha Signal (Moving Average Crossover + ML Enhancement)

**What it does**: Compute a trading signal based on a combination of technical indicators (EMA crossovers, RSI-like momentum, volume trends) using a small neural network instead of hard-coded rules.

**Input features** (host computes from OHLCV stream):
- Fast EMA / Slow EMA ratio: 1 feature
- RSI (14-period): 1 feature
- Volume ratio (current/average): 1 feature
- Price momentum (returns at 5 horizons): 5 features
- Volatility estimate: 1 feature
- Spread: 1 feature
- **Total: ~10-12 BF16 features**

**Model**: MLP 12 -> 16 -> 8 -> 1 (signal strength, -1 to +1)
- Fits easily in DMEM (~100 words, <10%)

**Training data**: Historical OHLCV data from any exchange, widely available.

**Commercial relevance**: This is the most common retail/prop trading pattern, but the FPGA acceleration adds a latency advantage angle.

#### Candidate D: Market Anomaly Detector (Autoencoder)

**What it does**: Detect unusual market conditions (flash crashes, liquidity droughts, spoofing patterns) by learning "normal" market behavior and flagging deviations.

**Input features**: Similar to Candidate A, 15-30 market microstructure features.

**Model**: Autoencoder 20 -> 12 -> 6 -> 12 -> 20 (reconstruction error = anomaly score)
| Component | BF16 params | DMEM words |
|-----------|-------------|------------|
| Enc L1: 20x12 + 12 | 252 | 63 |
| Enc L2: 12x6 + 6 | 78 | 20 |
| Dec L1: 6x12 + 12 | 84 | 21 |
| Dec L2: 12x20 + 20 | 260 | 65 |
| I/O + scratch | ~50 | 13 |
| **Total** | **~724** | **~182 / 1024 (18%)** |

**Commercial relevance**: Exchange surveillance, risk management, flash crash detection.

### 4.4 Feasibility Comparison

| Criterion | Trade Flow Classifier | Toxicity Monitor | Alpha Signal | Anomaly Detector |
|-----------|----------------------|-----------------|--------------|-----------------|
| DMEM usage | 11% | 13% | <10% | 18% |
| Model complexity | Simple MLP | Simple MLP | Simple MLP | Autoencoder |
| Feature count | 10-15 | 12-20 | 10-12 | 15-30 |
| SmartNIC fit | Excellent | Excellent | Good | Good |
| Training data access | Lobster, Kaggle, crypto | Harder (need tick data) | Easy (OHLCV) | Medium |
| Commercial story | Strong | Very strong | Moderate | Strong |
| Demo appeal | High ("classify trades") | High ("predict crashes") | Medium | High ("detect anomalies") |
| Implementation effort | Low-Medium | Low-Medium | Low | Medium |

---

## 5. How HFT Relates to "Network Processing"

### 5.1 The Fundamental Connection

HFT is, at its core, a network packet processing problem. The entire trading pipeline maps directly to the SmartNIC/network processor paradigm:

1. **Market data arrives as network packets** -- UDP multicast for market data feeds (ITCH, FAST, OPRA)
2. **The processor must parse, interpret, and act on packet contents** -- this is literally what a network processor does
3. **The response is a new network packet** -- an order message sent back to the exchange
4. **Latency from packet-in to packet-out is the critical metric** -- identical to the SmartNIC use case

This is arguably a MORE natural SmartNIC application than IDS, because in HFT the data IS network traffic AND the response IS also network traffic. In IDS, the response is typically a metadata action (drop/forward); in HFT, the response is a fully formed new packet.

### 5.2 The SmartNIC Framing

The course is about network processors. A SmartNIC is a network processor with integrated compute. The project's architecture maps perfectly:

| HFT SmartNIC Function | Project Hardware Equivalent |
|-----------------------|---------------------------|
| Receive market data packet | NetFPGA MAC -> Convertible FIFO |
| Parse packet payload | ARM CPU reads FIFO BRAM |
| Extract features | ARM CPU or host pre-computation |
| Run inference/signal generation | GPU coprocessor (BF16 FMA) |
| Generate response packet | Write result back to FIFO BRAM |
| Transmit response | FIFO -> NetFPGA MAC |

### 5.3 What EE533 Teaches vs. What Industry Does

| Concept | EE533 Project | Industry HFT SmartNIC |
|---------|--------------|----------------------|
| Packet pipeline | FIFO -> CPU -> GPU -> FIFO | NIC -> Parser -> Strategy -> NIC |
| Inline compute | GPU kernel on packet data | FPGA logic on market data |
| Protocol handling | UDP/IP (via host or NF2 pipeline) | ITCH/FAST/FIX (on FPGA) |
| Latency target | ~5 us | ~100-500 ns |
| Memory constraint | 8 KB DMEM | MB-scale SRAM/HBM |
| Throughput | 1 packet at a time | Millions of messages/sec |

The project demonstrates the SAME architectural concepts at a different scale. This is pedagogically valuable.

---

## 6. The "SmartNIC Story" for HFT

### 6.1 Industry SmartNIC Vendors for HFT

**Xilinx/AMD (Alveo)**
- Alveo U25, U50, U55C, SN1000/SN1022 SmartNICs
- SN1022 combines Solarflare low-latency networking with FPGA programmability
- Sub-microsecond trading latency
- FINN framework for DNN inference on FPGA
- "Solarflare cards in use by 90% of financial exchanges"

**Exablaze (now Cisco)**
- ExaNIC X25 -> Cisco Nexus K3P-S/K3P-Q
- 568ns trigger-to-response latency
- Designed specifically for HFT

**Napatech**
- NT200A02 SmartNIC with Link-Capture software
- 100 Gbps line-rate capture, zero packet loss
- FPGA-based packet processing with nanosecond precision
- Partners with Xelera for AI inference acceleration in trading
- "Reduced TCO by several million dollars" for one HFT client

**Algo-Logic**
- FPGA tick-to-trade IP cores
- Sub-microsecond end-to-end latency
- AI-driven hardware-accelerated trading system

**Enyx**
- nxFeed: FPGA-based feed handler for market data
- Processing on FPGA, delivery via SmartNIC

**AMD/Pensando**
- Acquired for $1.9 billion (2022)
- DPU-based approach to inline network processing
- Financial services is a key market

### 6.2 How the Student Project Compares

| Aspect | Industry SmartNIC | NetFPGA V2 Project |
|--------|-------------------|-------------------|
| FPGA generation | Virtex UltraScale+ / Versal | Virtex-II Pro (2003) |
| Network speed | 10-100 GbE | 1 GbE |
| On-chip memory | MB of BRAM + external SRAM/DDR | 8 KB DMEM + 18 KB FIFO BRAM |
| Compute | Dedicated DSP blocks, HBM | 4-lane BF16 SIMD |
| Protocol parsing | Full ITCH/FAST/FIX in hardware | Simplified via host or ARM CPU |
| Latency | 100-568 ns | ~5 us |
| Commercial viability | Production-grade | Educational demonstrator |

**The honest pitch**: "We implemented the same architectural pattern used by companies like Exablaze and Napatech -- a network processor with integrated compute that processes financial data inline at the NIC level. Our platform is 20+ years older and much smaller, but it demonstrates the core concept: receive a market data packet, run inference on the data, and produce a result packet without involving the host CPU in the critical path."

### 6.3 The University of Waterloo Precedent

Notably, the University of Waterloo's Systems Design Engineering department completed a student project titled "Hardware Accelerated Trading System" that used a **NetFPGA** (the same platform family) to implement a cross-market equity trading strategy with FIX 4.2 compliance. This was sponsored by Investment Technology Group (ITG). This is direct precedent for using NetFPGA as a financial trading platform in an academic setting.

---

## 7. Honest Assessment: Is HFT Viable for This Project?

### 7.1 Strengths

1. **Strongest SmartNIC narrative of any candidate**. HFT is THE canonical application of FPGA SmartNICs. Every SmartNIC vendor (Xilinx, Exablaze, Napatech, Algo-Logic) leads with financial trading as the top use case. Framing the project as "SmartNIC-accelerated financial ML" is more natural than any other candidate.

2. **The data IS packets**. Market data arrives as UDP multicast. Orders are sent as network packets. This is literally a network processing application -- no "we packetize sensor data" hand-waving needed.

3. **Rich academic precedent**. Multiple university projects (Columbia, MIT, U of Toronto, Waterloo, NYU) have implemented HFT on FPGAs as course projects. The Waterloo project specifically used NetFPGA.

4. **Tiered latency means the project doesn't need to be fast**. Industry sub-100ns systems are out of reach, but the ML inference tier (1-10 us) is realistic and still commercially valuable. The project can honestly say: "Our system operates at the ML inference tier, comparable to GPU-based signal generation that runs alongside FPGA tick-to-trade systems."

5. **Models are tiny**. Trade flow classifiers and toxicity monitors need only 100-200 DMEM words (10-20% of capacity). This is even smaller than the predictive maintenance autoencoder.

6. **Massive, well-funded industry**. HFT firms (Citadel, Jump Trading, Virtu, Two Sigma, DE Shaw) collectively manage hundreds of billions. SmartNIC vendors for finance (Xilinx, Napatech) are billion-dollar businesses.

7. **No overlap with any prior lab**. Entirely new domain.

### 7.2 Weaknesses

1. **Training data access is harder than other candidates**. Order book tick data is expensive (Lobster costs money; exchange data feeds require subscriptions). Mitigations:
   - Cryptocurrency exchanges provide free tick data (Binance, Coinbase via API)
   - Kaggle has several free order book datasets
   - Can synthesize training data from public OHLCV feeds
   - The project can use pre-extracted features; the exact source matters less than the architecture demonstration

2. **The ~5 us round-trip latency is NOT competitive for real HFT**. Industry systems operate at 100-500ns. The project must be carefully framed as "ML inference tier" not "tick-to-trade tier." This is honest but requires clear positioning.

3. **No actual exchange connectivity**. The demo sends crafted UDP packets from node0, not real market data feeds. This is the same limitation as all other candidates (they also use crafted packets), but it feels more salient in HFT where the whole point is speed.

4. **Feature extraction on the host weakens the "inline processing" story**. If the host extracts features and sends them as packets, the SmartNIC is just an inference accelerator, not a full trading system. Same weakness as the predictive maintenance candidate.

5. **The professor may find it too "aspirational"**. HFT is a loaded term. Claiming to do HFT on a Virtex-II Pro from 2003 requires careful framing to avoid seeming naive.

### 7.3 Comparison with Existing Candidates

| Criterion | HFT/Market Scoring | Predictive Maint. | Network IDS | Breast Cancer |
|-----------|-------------------|-------------------|-------------|---------------|
| SmartNIC narrative | Best -- canonical use case | Good | Very good | Moderate |
| Data is packets? | Yes -- inherently | No -- sensor data packetized | Yes -- inherently | No -- tabular data packetized |
| Model size (DMEM) | 11-18% | 36% | 48% | 17% |
| Training data | Medium (crypto free, Lobster $) | Easy (CWRU free) | Easy (NSL-KDD free) | Trivial (sklearn) |
| Commercial market | Massive (HFT is $$$) | $15.6B | $5.7B | Regulated |
| Academic precedent | Strong (5+ university projects) | Moderate | Moderate | Weak |
| Prior lab overlap | None | None | Lab 3/4 domain | None |
| Implementation effort | Low-Medium | Medium | Medium | Low |
| "Wow factor" | High | High | Medium-High | Medium |
| Risk of seeming naive | Medium-High (must frame carefully) | Low | Low | Low |

### 7.4 Recommendation

HFT is a strong candidate, potentially the strongest for the "SmartNIC story" angle. However, it requires more careful framing than predictive maintenance. The recommended approach:

1. **Don't call it "HFT"** -- call it "SmartNIC-Accelerated Market Microstructure Scoring" or "Inline Financial ML on a Network Processor." This avoids the expectation of sub-microsecond tick-to-trade latency.

2. **Choose Trade Flow Classification (Candidate A) or Toxicity Monitoring (Candidate B)** as the specific task. These have clear commercial relevance, tiny models, and natural packet mappings.

3. **Use cryptocurrency data** for training (free, abundant, real-time accessible). The model works the same regardless of asset class.

4. **Emphasize the architecture**, not the speed. The demo shows: "A market data feature vector arrives as a UDP packet. The SmartNIC runs BF16 MLP inference in the data path. The scored result leaves as a packet. No host CPU in the critical path."

5. **Cite the Waterloo NetFPGA precedent** to establish that financial applications on NetFPGA are not unprecedented in academic settings.

---

## 8. Concrete Implementation Sketch (Trade Flow Classifier)

### 8.1 Data Pipeline

```
node0 (nf6)                        NetFPGA (nf5)
+--------------+                   +---------------------------+
| Python script|  UDP packet       | NF2.1 pipeline            |
| - Read tick  |  (15 BF16 feats   | -> Convertible FIFO       |
|   data file  |   = 30 bytes      | -> DMA to GPU DMEM[0..3]  |
| - Compute    |   + 6-byte pad    | -> GPU: MLP 15->16->8->3  |
|   features   |   = 36 bytes      | -> DMA DMEM[output]->FIFO |
| - Pack as    |   = 5 data words) | -> Drain packet out       |
|   BF16       |   ------------->  |                           |
| - Send UDP   |                   | Result: 3 BF16 scores     |
+--------------+                   | (buy/hold/sell probs)     |
                                   +---------------------------+
```

### 8.2 GPU Kernel (Matrix-Vector Multiply)

Same kernel architecture as the existing ANN kernel, adapted for 15->16->8->3 dimensions. Uses:
- LD: Load input features from DMEM
- FMA: 4-lane BF16 fused multiply-add for dot products
- RELU: Activation after hidden layers
- ST: Store output scores
- BLT/BGE: Loop control

Estimated instruction count: ~150-200 instructions (well within 1024 IMEM).

### 8.3 DMEM Layout

```
[0..3]   Input: 15 BF16 features (4 words, 16 slots, 15 used + 1 pad)
[4..67]  Layer 1 weights: 15x16 = 240 BF16 (60 words)
[68..71] Layer 1 biases: 16 BF16 (4 words)
[72..75] Layer 1 output / Layer 2 input: 16 BF16 (4 words)
[76..107] Layer 2 weights: 16x8 = 128 BF16 (32 words)
[108..109] Layer 2 biases: 8 BF16 (2 words)
[110..111] Layer 2 output / Layer 3 input: 8 BF16 (2 words)
[112..117] Layer 3 weights: 8x3 = 24 BF16 (6 words)
[118]    Layer 3 biases: 3 BF16 (1 word)
[119]    Output: 3 BF16 scores (1 word)
Total: 120 / 1024 words (12%)
```

### 8.4 Training Pipeline

```python
# On development machine (not NetFPGA)
import pandas as pd
from sklearn.neural_network import MLPClassifier

# Load tick data (e.g., from Binance or Lobster)
ticks = pd.read_csv('tick_data.csv')

# Feature engineering
features = compute_microstructure_features(ticks)  # 15 features
labels = classify_direction(ticks, horizon=100)     # buy/hold/sell

# Train small MLP
model = MLPClassifier(hidden_layer_sizes=(16, 8), activation='relu')
model.fit(features, labels)

# Export weights as BF16 hex for GPU DMEM
export_bf16_hex(model, 'data_trade_classifier.hex')
```

### 8.5 Evaluation Metrics

1. **Accuracy**: Compare GPU BF16 inference output vs. Python float32 reference on same feature vectors
2. **Latency**: Measure GPU kernel cycles (from PCI register reads of cycle counter)
3. **End-to-end latency**: Packet arrival to result packet emission
4. **Throughput**: Inferences per second (bounded by single-packet FIFO)
5. **BF16 vs. float32 agreement**: Quantify precision loss from BF16 quantization

---

## Sources

### Academic Papers
- [UCSC: High Frequency Trading Acceleration using FPGAs (Leber, Geib, Litz)](https://people.ucsc.edu/~hlitz/papers/hft_fpga.pdf)
- [Columbia CSEE 4840: HFT Book Builder (Spring 2024)](https://www.cs.columbia.edu/~sedwards/classes/2024/4840-spring/reports/HFT-Book-Builder-report.pdf)
- [MIT 6.111: HFT Accelerator (Fall 2019)](https://web.mit.edu/6.111/volume2/www/f2019/projects/endrias_Project_Design_Presentation.pdf)
- [U of Toronto ECE1373: HFT on FPGA (2016)](https://github.com/mustafabbas/ECE1373_2016_hft_on_fpga)
- [Imperial College: FPGA Accelerated Low-Latency Market Data Feed Processing (IEEE HotI 2009)](https://www.doc.ic.ac.uk/~wl/papers/09/hoti09dt.pdf)
- [IEEE: Low Latency Book Handling in FPGA for HFT (2014)](https://ieeexplore.ieee.org/document/6868785/)
- [IEEE FPL 2023: Building Low-Latency Order Books with Hybrid Data Structures](https://ieeexplore.ieee.org/document/10296447/)
- [IEEE: Low-Latency FPGA Based Financial Data Feed Handler](https://ieeexplore.ieee.org/iel5/5771180/5771238/05771256.pdf)
- [ScienceDirect: Speed vs. Efficiency -- HFT on Zynq SoC (April 2024)](https://www.sciencedirect.com/science/article/pii/S1110016824003119)
- [IEEE: FPGA for High-Frequency Trading -- Reducing Latency in Financial Systems](https://ieeexplore.ieee.org/document/10841781/)
- [ACM TRETS: FPGA-based Block Minifloat Training Accelerator for Time Series Prediction](https://dl.acm.org/doi/10.1145/3707209)
- [Imperial College: Reconfigurable Platforms for Order Book Update (FPL 2017)](https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf)
- [FPGA-Based Design of Black Scholes Financial Model](https://www.academia.edu/47124319/FPGA_Based_Design_of_Black_Scholes_Financial_Model_for_High_Performance_Trading)

### University Projects
- [U of Waterloo: Hardware Accelerated Trading System (NetFPGA)](https://uwaterloo.ca/systems-design-engineering/hardware-accelerated-trading-system)
- [NYU FRE Capstone: FPGA Orderbook Analysis (LSTM on Zynq-7020)](https://github.com/XhovaniM8/fpga-orderbook-analysis)
- [Columbia CSEE 4840: Building the Book -- Nasdaq ITCH (2013)](https://www.cs.columbia.edu/~sedwards/classes/2013/4840/reports/Itch.pdf)

### Industry and SmartNIC Vendors
- [Velvetech: FPGA in High-Frequency Trading](https://velvetech.com/blog/fpga-in-high-frequency-trading/)
- [Algo-Logic: FPGA Tick-to-Trade](https://www.algo-logic.com/fpga-tick-to-trade)
- [Napatech: Deploying SmartNIC for HFT (Case Study)](https://www.napatech.com/support/resources/case-studies/deploying-napatech-smartnic-for-high-frequency-trading/)
- [Napatech + Xelera: AI Inference Acceleration for Trading](https://www.napatech.com/solutions/partners/ai-inference-acceleration-for-trading-with-xelera/)
- [Magmio: FPGA System for Ultra-Low Latency Trading](https://www.magmio.com/product)
- [Xilinx: Alveo SN1000 FPGA SmartNIC](https://www.servethehome.com/xilinx-alveo-sn1000-fpga-powered-100gbe-smartnic/)
- [Cisco Nexus SmartNIC (formerly Exablaze)](https://www.cisco.com/c/en/us/products/collateral/interfaces-modules/nexus-smartnic/datasheet-c78-743827.html)
- [Xelera: Low-Latency ML Inference for HFT](https://www.xelera.io/post/low-latency-machine-learning-inference-for-high-frequency-trading)
- [Orthogone: How FPGAs Are Shaping HFT](https://orthogone.com/fpgas-future-of-high-frequency-trading/)

### Market Microstructure and Financial Concepts
- [Databento: What is Tick-to-Trade Latency?](https://databento.com/microstructure/tick-to-trade)
- [Pico: Lowest Tick-to-Order Latency without FPGAs](https://www.pico.net/kb/what-is-the-lowest-tick-to-order-or-tick-to-trade-latency-achievable-without-the-use-of-fpgas/)
- [Brett Harrison on FPGAs vs GPUs in HFT](https://x.com/BrettHarrison88/status/1800954431552303225)
- [QuestDB: Order Book Imbalance](https://questdb.com/glossary/order-book-imbalance/)
- [Order Flow Imbalance as a Trading Signal](https://dm13450.github.io/2022/02/02/Order-Flow-Imbalance.html)
- [VPIN: Volume-Synchronized Probability of Informed Trading (Easley et al.)](https://www.quantresearch.org/VPIN.pdf)
- [From PIN to VPIN: Introduction to Order Flow Toxicity](https://www.quantresearch.org/From%20PIN%20to%20VPIN.pdf)
- [VisualHFT: VPIN and Real-Time Order Toxicity](https://www.visualhft.com/blog/vpin-real-time-order-toxicity-what-your-execution-stack-cannot-see)
- [Lee-Ready Trade Classification Algorithm](https://www.sciencedirect.com/science/article/abs/pii/S1042443100000482)

### FPGA Technical References
- [OpenResearchInstitute: EMA Filter for FPGA (VHDL)](https://github.com/OpenResearchInstitute/lowpass_ema)
- [Intel: Quantized Neural Networks for FPGA Inference](https://www.intel.com/content/www/us/en/products/docs/programmable/fpga-ai-quantization-white-paper.html)
- [BF16 Advantages for AI Inference](https://semiengineering.com/advantages-of-bfloat16-for-ai-inference/)
- [AMD Xilinx: Accelerating Option Pricing with Vitis](https://www.xilinx.com/developer/articles/accelerating-option-pricing-with-vitis-quantitative-finance.html)
- [Xilinx: Algorithmic Trading Solution Brief](https://www.xilinx.com/publications/solution-briefs/xilinx-algorithmic-trading-solution-brief.pdf)

### NetFPGA Platform
- [NetFPGA Publications List](https://netfpga.org/Publications.html)
- [NetFPGA 1G Platform Page](https://netfpga.org/NetFPGA-1G.html)
- [NetFPGA Wikipedia](https://en.wikipedia.org/wiki/NetFPGA)
- [NetFPGA: An Open Platform for Teaching (Stanford)](http://yuba.stanford.edu/~nickm/papers/NetFPGA_Stanford.pdf)

### Open-Source Implementations
- [Kodoh/Orderbook: Open-Source HFT Order Book with FPGA Acceleration](https://github.com/Kodoh/Orderbook)
- [ECE1373 HFT on FPGA (Vivado HLS)](https://github.com/mustafabbas/ECE1373_2016_hft_on_fpga)
- [FPGA Orderbook Analysis with LSTM (NYU)](https://github.com/XhovaniM8/fpga-orderbook-analysis)

---

## 9. Professor's Questions: "How Much Are Your Competitors Making?" (Appended 2026-03-25)

*Based on questions asked by Professor Cho in response to the HFT candidate proposal email.*

### 9.1 Direct Competitors: FPGA SmartNIC Vendors for Financial Trading

These are companies selling the same type of product our project demonstrates — FPGA/SmartNIC-based hardware for low-latency financial processing.

| Company | Status | Revenue / Valuation | Notes |
|---------|--------|-------------------|-------|
| **Napatech** | Acquired by Rohde & Schwarz (2023) | **~$340M acquisition price** (NOK 3.6B); ~$50M/yr revenue pre-acquisition | Publicly traded on Oslo Bors (NAPA.OL). Best-documented competitor. SmartNICs for HFT + cybersecurity |
| **Exablaze** | Acquired by Cisco (2020) | Est. **$50-200M** acquisition (undisclosed) | ExaNIC X25 -> Cisco Nexus K3P-S. 568ns trigger-to-response latency. Designed specifically for HFT |
| **Enyx** | Acquired by Murata Electronics (2022) | Undisclosed; est. low single-digit millions EUR revenue | French company. FPGA-based ultra-low-latency market data and order entry IP |
| **Algo-Logic** | Private (active) | Est. single-digit millions USD revenue | San Jose. Sells FPGA IP cores for ticker plant, order entry, market data parsing |
| **Magmio** | Startup (active) | Seed/Series A, single-digit millions EUR | Czech (spun from CESNET). FPGA SmartNIC platform for networking and financial applications |
| **Xelera** | Pivoted / unclear status | Low single-digit millions (EU grant-backed) | German. FPGA acceleration for financial ML inference, partnered with Napatech |

**Key takeaway**: The direct competitors are small companies ($10M-$300M) but they are being acquired by major corporations (Cisco, Rohde & Schwarz, Murata) — demonstrating strategic value of this technology.

### 9.2 Upstream Platform Vendors (FPGA/DPU Makers)

These companies supply the silicon that SmartNIC vendors (and our project) build on.

| Company | Event | Value |
|---------|-------|-------|
| **Xilinx** | Acquired by AMD (Feb 2022) | **$49 billion** |
| **Altera** | Acquired by Intel (2015); spun back out as subsidiary (2023) | **$16.7 billion** acquisition |
| **Pensando** | Acquired by AMD (May 2022) | **$1.9 billion** |

Xilinx's total pre-acquisition revenue was ~$3.5B/year. FPGA revenue specifically from financial/trading customers is estimated at **$200M-$500M globally**, with Xilinx holding ~60-70% market share in HFT FPGA sockets.

### 9.3 HFT Firms: The Customers Using FPGA SmartNICs

These firms are the end-users of the technology our project demonstrates. Their revenue shows the economic value of low-latency hardware-accelerated trading.

| Firm | Revenue | Notes |
|------|---------|-------|
| **Jane Street** | **~$8-10B** net trading revenue (2023-24) | Private. Reportedly generated more revenue than Goldman Sachs' entire trading division |
| **Citadel Securities** | **~$5B+** revenue (2023); **$22B valuation** (2024 stake sale) | Sold $1.15B stake to Sequoia/Paradigm at $22B valuation |
| **Virtu Financial** | **~$1.8-2.0B** revenue (2024); **$5-6B** market cap | NASDAQ: VIRT. Publicly traded — most transparent HFT firm. SEC filings available |
| **Jump Trading** | Est. **$1-3B**/year | Private. Known as one of the heaviest FPGA users — has entire hardware engineering division |
| **Tower Research Capital** | Est. hundreds of millions to low billions/year | Known FPGA user for market-making |
| **Two Sigma** | Est. **$3-5B**/year; ~$60B AUM | More quant/ML-focused than pure low-latency HFT |
| **D.E. Shaw** | Est. **$3-5B**/year; ~$60B AUM | Similar to Two Sigma — quant-focused |

### 9.4 Market Sizes

| Market | Size | Growth |
|--------|------|--------|
| **Global HFT market** | **$8-12B** (2024) | Projected $15-20B by 2030 (CAGR ~8-10%) |
| **FPGA in financial services** | **$500M-$1B** (2024 est.) | CAGR ~10-15% |
| **SmartNIC market (all sectors)** | **$3-4B** (2023) | Projected $8-12B by 2028-30 (CAGR ~20-25%) |
| **Low-latency trading technology** | **$2-4B** (2024) | Includes co-location, switches, FPGAs, microwave links |

HFT accounts for ~50-60% of US equity trading volume and ~35-40% of European equity volume.

### 9.5 The Answer in One Paragraph

The direct competitors — companies selling FPGA SmartNICs for trading — are $10M-$300M businesses, but they are being acquired by Cisco, Murata, and Rohde & Schwarz because the technology is strategic. The FPGA platforms they build on generated $49B (Xilinx) and $16.7B (Altera) in acquisition value. The customers using these SmartNICs — Jane Street ($8-10B revenue), Citadel Securities ($22B valuation), Virtu ($5-6B market cap) — are among the most profitable firms in finance. The overall HFT market is $8-12B, with FPGA-based financial hardware a $500M-$1B subsegment growing at 10-15% annually.

---

## 10. Professor's Questions: "Why Is Your SoC Better Than Others?" (Appended 2026-03-25)

### 10.1 Commercial DPU/SmartNIC Landscape

| Product | Architecture | ML Accelerator? | Cost |
|---------|-------------|-----------------|------|
| **NVIDIA BlueField-3** | 16x ARM A78 + ConnectX-7 NIC + eSwitch | **No** — ML inference runs on ARM cores (slow) or must go to host GPU | ~$3,600/card |
| **AMD Pensando (Elba/Giglio/Salina)** | 16x ARM A72 + P4-programmable pipeline | **Partial** — P4 pipeline acceleration, not a dedicated neural network engine | Enterprise pricing |
| **AMD/Xilinx Alveo (U25, U55C)** | Pure FPGA fabric | **No** — users must synthesize ML from scratch via HLS | $1,000-$5,500 |
| **Intel IPU (E2100/E2200)** | FPGA + ASIC + embedded cores | **No** — focused on crypto, storage, NVMe offload | Enterprise pricing |
| **Marvell OCTEON 10** | ARM Neoverse N2 + ML inference tiles + NIC | **Yes** — tiled ML engine with SRAM + MAC arrays, 20-100 TOPS | ~$2,000+ |
| **Our NetFPGA SoC** | 4-thread ARM + 4-lane BF16 SIMD GPU + Convertible FIFO | **Yes** — dedicated GPU with FMA+ReLU, 6-stage pipeline | ~$0 (lab equipment) |

### 10.2 The Key Insight: Most SmartNICs Lack Inline ML Compute

**NVIDIA BlueField-3** has ARM cores and a network ASIC, but no ML accelerator. To run inference, packets must be sent to the ARM cores (slow, general-purpose) or punted to a host GPU (defeats the purpose of on-NIC processing).

**AMD Alveo** has FPGA fabric that CAN implement ML, but there's no pre-built ML engine — users must design everything from scratch in HLS or RTL.

**Intel IPU** focuses on crypto offload, storage, and RDMA — no ML compute at all.

**Only Marvell OCTEON 10** integrates CPU + dedicated ML inference engine + NIC on one chip — and our design independently implements this same architectural pattern at educational scale.

### 10.3 Architectural Comparison: Our SoC vs. Marvell OCTEON 10

| Component | Our Design | Marvell OCTEON 10 |
|-----------|-----------|-------------------|
| CPU | 4-thread ARM pipeline | Neoverse N2 (up to 36 cores) |
| ML Accelerator | 4-lane BF16 SIMD, FMA+ReLU, 6-stage pipeline | Tiled ML engine, INT8/FP16, 20-100 TOPS |
| Network Interface | Convertible FIFO, 1 GbE | 25-400 GbE |
| Data Path | DMA: FIFO BRAM <-> GPU DMEM, inline | ML engine in data pipeline, inline |
| Programmability | Full RTL visible, custom ISA | Proprietary firmware (black box) |

Our design is a miniature Marvell OCTEON 10 — the same architectural concept at 1/100,000th the performance but with full transparency.

### 10.4 Why Our SoC Is "Better" (Honest Framing)

Our SoC is not better in raw performance. A Marvell OCTEON 10 delivers 20-100 TOPS vs. our ~0.001 TOPS. The advantages are in different dimensions:

**1. Architectural Concept Validation**
Our SoC demonstrates the same principle Marvell validates commercially: placing a dedicated ML inference engine directly in the network data path, controlled by an integrated CPU, eliminates the data movement penalty of sending packets to a host for ML processing. We independently arrived at the CPU + ML accelerator + NIC integration that the industry is converging on — most commercial SmartNICs (BlueField, Alveo, Intel IPU) have NOT reached this integration point yet.

**2. Full-Stack Transparency**
Every clock cycle from packet ingress to inference result is visible in our Verilog RTL. We can measure and optimize each pipeline stage independently. Commercial DPUs are black boxes — you cannot inspect Marvell's ML tile microarchitecture or NVIDIA's eSwitch pipeline. For HFT research, understanding every cycle of latency is critical.

**3. Domain-Specific Customizability**
Commercial DPUs have fixed ML engines optimized for general inference (INT8/FP16 matrix multiply). Our GPU has a custom ISA with domain-specific instructions — RELU as a first-class opcode, BF16 FMA. For an HFT application, we could add custom opcodes for financial functions (fixed-point price comparison, order book operations). This is impossible on a commercial DPU without buying FPGA fabric.

**4. Accessibility as a Research Platform**
- NVIDIA BlueField-3: ~$3,600/card, requires proprietary DOCA SDK
- AMD Alveo U55C: ~$5,500, requires Vivado license
- Marvell OCTEON 10: not available to individual researchers
- Our platform: NetFPGA V2 (university lab, $0), open RTL, open toolchain
- NetFPGA has been used in 400+ academic papers (Stanford-designed teaching/research platform)

**5. The HFT-Specific Argument**
The research question "can ML inference run inline on the NIC data path for trading signals?" is exactly what companies like Xelera and Napatech explore commercially. Our design provides a fully transparent testbed: packet arrives -> DMA to ML engine -> BF16 inference -> result in packet -> packet out. Every stage is measurable, modifiable, and open.

### 10.5 The Answer in One Paragraph

Our SoC is not faster than commercial DPUs — it operates at 1/100,000th the throughput. But it demonstrates an architectural pattern that most commercial SmartNICs have NOT achieved: integrating a CPU, a dedicated ML inference engine, and a network interface on a single data path. NVIDIA BlueField has no ML accelerator. AMD Alveo has no pre-built ML compute. Intel IPU has neither. Only Marvell's OCTEON 10 matches our architecture — CPU + ML engine + NIC — and it costs thousands of dollars and is closed-source. Our platform costs nothing, every pipeline stage is visible in RTL, and we can add domain-specific instructions (BF16 FMA, ReLU) that commercial fixed-function ML engines cannot support. It is better as a teaching, research, and prototyping platform for inline ML inference on network data.

### 10.6 Additional Sources

- [NVIDIA BlueField-3 DPU Datasheet](https://www.nvidia.com/content/dam/en-zz/Solutions/Data-Center/documents/datasheet-nvidia-bluefield-3-dpu.pdf)
- [NVIDIA BlueField-4 Analysis (Chiplog, 2026)](https://www.chiplog.io/p/analysis-of-nvidias-bluefield-4-dpu)
- [AMD Pensando DPU Hardware Strategy White Paper](https://www.amd.com/content/dam/amd/en/documents/pensando-technical-docs/white-papers/pensando-comparison-of-dpu-hardware-strategies.pdf)
- [Marvell OCTEON 10 ML White Paper](https://www.marvell.com/content/dam/marvell/en/public-collateral/embedded-processors/marvell-octeon-10-dpu-platform-white-paper.pdf)
- [Intel IPU E2200 at Hot Chips 2025 (Chips and Cheese)](https://chipsandcheese.com/p/intels-e2200-mount-morgan-ipu-at)
- [ML-NIC: Accelerating ML Using Smart NICs (Frontiers in CS, 2024)](https://www.frontiersin.org/journals/computer-science/articles/10.3389/fcomp.2024.1493399/full)
- [In-Network ML on P4-Programmable FPGA SmartNICs (PEARC 2025)](https://dl.acm.org/doi/10.1145/3708035.3736086)
- [Survey on Heterogeneous Computing Using SmartNICs and DPUs (2025)](https://arxiv.org/html/2504.03653v2)
- [AMD Adaptive SmartNIC White Paper](https://www.amd.com/content/dam/xilinx/publications/white-papers/adaptive_smartnic_whitepaper.pdf)
- [Xelera: Low-Latency ML Inference for HFT](https://www.xelera.io/post/low-latency-machine-learning-inference-for-high-frequency-trading)
- [NetFPGA: Rapid Prototyping of Networking Devices (ACM SIGCOMM)](https://dl.acm.org/doi/10.1145/2829988.2790029)
