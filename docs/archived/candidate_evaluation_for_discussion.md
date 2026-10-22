# Final Project Candidate Evaluation (Updated)

EE533 Team 5 — Zilin, Guillermo, Parker
Updated March 24, 2026 after TA feedback session. Prepared for Tuesday discussion with Professor Cho and TAs (March 25, 2026).

---

## TA Feedback Summary (March 24)

We presented three initial candidates. The TA's feedback:

1. **Predictive Maintenance** — Not feasible / not aligned with the class. The core objection: "why use a SmartNIC for this?" A SmartNIC is not the most suitable platform for vibration monitoring. The data originates from sensors, not from the network itself — any server with a GPU would serve this purpose better.
2. **ML-based Network Intrusion Detection** — Looks solid. The TA did something similar for this class. Our concern about Lab 3/4 overlap remains, but the TA endorsed the approach.
3. **Breast Cancer Classification** — Can be good only if it aligns with real-time / network packet needs. Image classification does not fit the "network" topic. The tabular version is possible but the network story is weak.

Based on this feedback, we eliminated predictive maintenance and breast cancer, kept IDS, and added a new candidate: **SmartNIC-accelerated market microstructure scoring** (financial ML). This document presents the two viable candidates.

---

## Our Hardware at a Glance

Before evaluating candidates, here is what our SmartNIC can and cannot do.
These numbers come from the actual synthesized design running on the NetFPGA V2 (Virtex-II Pro XC2VP50).

| Resource | Capacity | What it means for an ANN |
|----------|----------|--------------------------|
| GPU DMEM | 1024 words x 64 bits (8 KB) | Each word holds 4 BF16 values. After reserving space for inputs, outputs, and intermediate activations, roughly 2000–3000 BF16 weight slots are available. |
| GPU IMEM | 1024 x 32-bit instructions | Enough for looped matrix-vector multiply kernels with several hundred iterations. |
| Compute | 4-lane BF16 SIMD, FMA + ReLU | One FMA processes 4 multiply-accumulates per cycle. Natural fit for small MLP inference. |
| Data path | Packet in -> FIFO BRAM -> DMA -> GPU DMEM -> DMA -> FIFO BRAM -> Packet out | End-to-end inference on a single packet, fully in hardware. |
| Slice utilization | 96% | No room for significant RTL additions. The project is about software/firmware and application, not new hardware. |

The design principle for both candidates is the same: a host extracts features and sends a compact feature vector as a UDP packet; the SmartNIC runs a small MLP on the GPU; the result is written back into the packet and forwarded.

We already have a working 3-layer BF16 ANN kernel, DMA round-trip, and packet send/receive scripts. The main work is adapting the kernel for matrix-vector multiply (different layer sizes), training on real data, and building the end-to-end demo pipeline.

---

## Candidate 1 (Primary): SmartNIC-Accelerated Market Microstructure Scoring

**Application.** Financial exchanges broadcast market data (order book updates, trades, quotes) as UDP multicast packets. A SmartNIC sitting on the network receives these packets, extracts market microstructure features, runs a small MLP to produce a score (trade direction prediction, order flow toxicity, or anomaly flag), and forwards the scored result as a new packet — all without involving the host CPU in the critical path. This is the canonical application of FPGA SmartNICs: every major vendor (Xilinx Alveo, Exablaze/Cisco, Napatech, Algo-Logic) leads with financial trading as the top use case.

**Specific task: Trade Flow Classifier.** Classify whether recent trading activity indicates net buying pressure, selling pressure, or neutral flow. This is the hardware equivalent of the Lee-Ready algorithm or Bulk Volume Classification, but using a learned MLP instead of hand-coded rules. The output helps market makers adjust quotes and institutional traders minimize market impact.

Alternative task (same architecture): **Order Flow Toxicity Monitor** (VPIN-inspired). Detect whether current order flow is dominated by informed traders. High toxicity warns market makers to widen spreads or reduce exposure. VPIN famously spiked one hour before the May 6, 2010 Flash Crash.

### Why a SmartNIC Is the Right Platform

This is where the TA's predictive-maintenance objection ("why use a SmartNIC?") does not apply. In HFT/financial ML:

- **The data IS network packets.** Market data arrives as UDP multicast (ITCH, FAST, OPRA protocols). Orders are sent as network packets. The entire pipeline is packet-in → process → packet-out. No hand-waving about "packetizing sensor data" — the data is inherently network traffic.
- **Latency in the network path is the critical metric.** The value of a SmartNIC is that it processes data inline, at the NIC level, without involving the host CPU. In financial trading, every microsecond in the data path matters. A 2022 study by Xelera found that "5 microseconds of delay can draw the line between a successful and unsuccessful trading strategy" at the ML inference tier.
- **The entire FPGA SmartNIC industry is built on this use case.** Solarflare (now AMD/Xilinx) cards are used by 90% of financial exchanges. Exablaze (now Cisco Nexus SmartNIC) was designed specifically for HFT. Napatech partners with Xelera for AI inference acceleration in trading. AMD acquired Pensando for $1.9B partly for financial inline processing.

### Feasibility

**Model — Trade Flow Classifier MLP (15 -> 16 -> 8 -> 3):**

| Component | BF16 parameters | DMEM words (4 BF16 per word) |
|-----------|----------------|------------------------------|
| Layer 1: 15x16 weights + 16 biases | 256 | 64 |
| Layer 2: 16x8 weights + 8 biases | 136 | 34 |
| Layer 3: 8x3 weights + 3 biases | 27 | 7 |
| Input + intermediates + output | ~30 | 8 |
| **Total** | **~449** | **~113 / 1024 (11%)** |

This is the **smallest model of any candidate we have evaluated**, using only 11% of DMEM. Leaves 90% of memory free for scratch space, larger models, or multiple models loaded simultaneously.

Alternative model — Toxicity Monitor MLP (20 -> 16 -> 8 -> 1): ~511 BF16 params, ~129 DMEM words (13%).

**Input features** (computed by host from tick stream, sent as UDP packet):
- Price returns over multiple horizons (1s, 5s, 30s): 3 features
- Volume imbalance at best bid/ask: 1 feature
- Trade arrival rate: 1 feature
- Bid-ask spread: 1 feature
- Order book imbalance at 3 depth levels: 3 features
- Recent trade direction (fraction buyer-initiated): 1 feature
- Volatility estimate: 1 feature
- Volume ratio (current / historical average): 1 feature
- Momentum indicators: 3 features
- **Total: 15 BF16 features = 30 bytes = 4 data words + padding. Fits in one small UDP packet.**

**Output**: 3 BF16 scores (buy/hold/sell probabilities) = 1 data word.

**Dataset — Cryptocurrency tick data (free and abundant):**
Binance, Coinbase, and Kraken provide free historical tick data via API. Kaggle hosts several order book datasets (e.g., "Bitcoin Historical Data," "Crypto Order Book Snapshots"). Training data is labeled by subsequent price movement: if price rises >0.1% in next N seconds → buy, drops >0.1% → sell, otherwise → hold.

Also usable: Lobster (NASDAQ tick data, academic pricing), public OHLCV from any exchange, synthetic data generated from known market microstructure models.

**Expected accuracy**: 55–65% directional accuracy is realistic and commercially useful. Unlike IDS or medical classification where 90%+ is expected, financial prediction at 55% accuracy is already profitable (better than random). The model's value comes from consistency over many trades, not from being right on any single prediction. BF16 quantization introduces minimal degradation (~1–2% vs FP32) because the model is small and the exponent range of BF16 matches the feature scale.

**Kernel implementation**: Same matrix-vector multiply kernel as IDS candidate. Uses LD, FMA (4-lane BF16), RELU, ST, BLT. Estimated ~150–200 instructions, well within 1024 IMEM. Even smaller than the IDS kernel due to fewer parameters.

**Packet mapping:**
- Input: 15 BF16 features = 30 bytes + 6 bytes padding = 5 data words.
- Output: 3 BF16 scores = 6 bytes = 1 data word.

### Competition and Secrecy — Why This Works for a Course Project

A natural question: the HFT space is extremely competitive and secretive. How does that affect us?

**The competition is an advantage, not a problem.** The FPGA-HFT ecosystem spans a huge range:
- **Top tier**: Prop trading firms (Citadel Securities, Jump Trading, Virtu Financial, Two Sigma, DE Shaw) spend billions on custom hardware, co-location, and microwave links. They operate at sub-100ns tick-to-trade latency.
- **Middle tier**: SmartNIC vendors (Xilinx Alveo, Napatech, Exablaze/Cisco) sell hardware to the top tier and to banks. They target 100ns–1μs.
- **Academic tier**: University projects (Waterloo, Columbia, MIT, U of Toronto, NYU) demonstrate the architectural concepts on educational platforms. They target microseconds.

We are firmly in the academic tier. **Professor Cho does not expect us to outperform industry** — our Virtex-II Pro is from 2003. The project demonstrates the same architectural pattern at a different scale: receive a market data packet, run ML inference inline at the NIC, produce a scored result packet. The honest pitch: "Industry does this at 100ns on a $10K Alveo SN1022. We demonstrate the same concept at ~5μs on a 23-year-old educational platform."

**HFT secrecy works in our favor.** Firms do not publish their:
- Proprietary trading strategies or alpha signals
- System architectures or latency numbers
- Training data, feature engineering, or model weights

This means:
1. **No one can say "your implementation is wrong"** — there is no public reference implementation to compare against.
2. **The academic concepts are freely available.** Order flow toxicity (VPIN), trade classification (Lee-Ready), microstructure features — these are published in peer-reviewed finance journals (Easley, Lopez de Prado, O'Hara). We implement well-documented academic concepts, not proprietary secrets.
3. **Our contribution is architectural, not strategic.** The interesting part is "we built a SmartNIC that runs BF16 MLP inference on market data in the data path" — not the specific weights or trading strategy.
4. **Free data exists.** Cryptocurrency exchanges provide free tick data with full order book depth. The model works the same regardless of asset class.

### Academic Precedent

Multiple university course projects have implemented HFT on FPGAs:

| University | Year | Platform | What they built |
|-----------|------|----------|-----------------|
| **U of Waterloo** | — | **NetFPGA** (same platform family) | Cross-market equity trading, FIX 4.2 compliance, sponsored by ITG |
| Columbia (CSEE 4840) | 2024 | DE1-SoC | ITCH protocol parser + order book construction |
| MIT (6.111) | 2019 | Artix-7 | Market data processing + order generation pipeline |
| U of Toronto (ECE1373) | 2016 | Xilinx FPGA | FAST decoder + order book, <450ns roundtrip |
| NYU (FRE Capstone) | — | Zynq-7020 | LSTM for order book pattern detection, 2.52μs inference |

The **Waterloo NetFPGA project** is direct precedent: a student project using the same platform family for financial trading, sponsored by a real trading technology firm.

Key papers:
- UCSC (Leber, Geib, Litz): Complete HFT pipeline on Virtex-4, >70% latency reduction vs. software
- Imperial College (Morris, Thomas, Luk, IEEE HotI 2009): FAST protocol feed handler, 4μs average latency
- Zynq-7000 (ScienceDirect, April 2024): MACD/RSI/Aroon on Bitcoin/Ethereum, 30x speedup
- Black-Scholes on Virtex-II Pro (same FPGA family): ~1% of Mathematica computation time

### Commercial Value

The HFT and financial technology market dwarfs all other candidates:
- HFT firms collectively manage hundreds of billions in capital
- The FPGA accelerator market for finance is growing rapidly as firms push latency boundaries
- SmartNIC vendors for finance: Xilinx/AMD ($2.4B FPGA security market alone), Napatech ("reduced TCO by several million dollars" for one HFT client), Exablaze/Cisco (568ns trigger-to-response)
- Every market maker, every exchange, and every institutional broker needs trade flow analysis

The value proposition: inline ML inference on market data at the NIC level, microsecond latency, zero host CPU in the critical path. This is exactly what NVIDIA's BlueField DPU, AMD's Pensando, and Xilinx's Alveo are built to do.

### Honest Pros and Cons

- (+) **Strongest SmartNIC narrative of any candidate** — the canonical FPGA SmartNIC use case
- (+) **Data IS packets** — market data is UDP multicast, orders are network packets, no "packetize external data" needed
- (+) **Smallest model** of any candidate (11% DMEM) — lowest implementation risk
- (+) **No overlap** with any prior lab
- (+) **Rich academic precedent** — 5+ university projects including one on NetFPGA specifically
- (+) **Massive, well-funded industry** — strongest commercial story when measured by total market capital
- (+) **Secrecy works in our favor** — no public reference to be measured against, academic concepts freely published
- (+) **Free training data** — cryptocurrency exchanges provide tick data at no cost
- (-) **The term "HFT" may seem aspirational** for a Virtex-II Pro. Must be framed as "ML inference tier" (~5μs), not "tick-to-trade tier" (~100ns). Call it "market microstructure scoring" not "high-frequency trading."
- (-) **Feature extraction on the host** weakens the "inline processing" story (same limitation as all candidates)
- (-) **Lower accuracy ceiling** than classification tasks — 55–65% directional accuracy is good in finance but may seem low to someone expecting 95%+. Needs framing: in finance, 55% is profitable.
- (-) **No actual exchange connectivity** — demo uses crafted UDP packets from node0, same as all candidates

---

## Candidate 2 (Backup): Network Intrusion Detection (ML-based IDS)

**Application.** A SmartNIC that classifies each network flow as normal or attack based on statistical features extracted from packet headers and flow metadata. Unlike traditional signature-based IDS (which matches known byte patterns), an ML-based IDS learns statistical decision boundaries from labeled traffic data and can flag novel attack variants that no signature covers.

The TA endorsed this candidate and mentioned he did something similar for this class.

### How This Differs from Lab 3/4 Mini-IDS

We built a mini-IDS in Lab 3/4, but the two systems share only the word "IDS." The table below makes the architectural difference concrete:

| Aspect | Lab 3/4 (Signature IDS) | Lab 10 (ML IDS) |
|--------|------------------------|------------------|
| Detection method | Exact 7-byte string matching | Neural network inference (MLP) |
| Data examined | Raw packet payload bytes | 41 flow-level statistical features |
| Hardware used | Custom comparator array (combinational logic) | BF16 SIMD GPU coprocessor with FMA pipeline |
| Compute type | Shift register → comparator (no arithmetic) | Matrix-vector multiply + ReLU activation (heavy arithmetic) |
| Can detect zero-day attacks? | No — only matches known patterns | Yes — generalizes from training data |
| Reconfigurable at runtime? | No — patterns fixed in silicon at synthesis | Yes — weights loaded via network packets |
| Parameters | 7 byte patterns = 56 bits | ~2,000 BF16 weights = 32,000 bits |
| Paradigm | Syntactic matching (byte-level) | Statistical classification (feature-level) |
| Analogy | `grep` for "ATTACK" in packet payload | Spam filter that learned what spam looks like |

The comparison is: Lab 3/4 was an ACL (access control list) — match against a known list. Lab 10 is a learned behavioral classifier that understands traffic patterns, not just byte sequences. Different hardware blocks (GPU vs. comparators), different data representation (BF16 features vs. ASCII bytes), different detection paradigm (probabilistic vs. deterministic).

### Feasibility

**Model — MLP (41 -> 32 -> 16 -> 1), binary classification:**

| Component | BF16 parameters | DMEM words |
|-----------|----------------|------------|
| Layer 1: 41x32 weights + 32 biases | 1,344 | 336 |
| Layer 2: 32x16 weights + 16 biases | 528 | 132 |
| Layer 3: 16x1 weights + 1 bias | 17 | 5 |
| Input + intermediates + output | ~90 | 23 |
| **Total** | **~1,979** | **~496 / 1024 (48%)** |

Fits with room to spare. A reduced-feature variant (8 best features -> 16 -> 8 -> 1) uses only 153 parameters.

**Dataset — NSL-KDD:**
41 features per flow (duration, protocol, service, flag, src/dst bytes, error rates, etc.). ~125K training records, binary and multi-class labels. The standard IDS benchmark with hundreds of published baselines. A single-hidden-layer MLP with 38 inputs achieves 95.6%; two hidden layers exceed 97.8%.

Also available: CICIDS2017 (modern attack types, 78 features), UNSW-NB15 (49 features).

**Expected accuracy**: 88–94% binary accuracy on NSL-KDD KDDTest+ with a ~2,000-parameter BF16 MLP. BF16 quantization loses only 1–2% vs FP32 because the exponent range is sufficient for normalized network features.

**Feature extraction:** The ARM CPU can extract header fields (5-tuple, byte counts, TCP flags) directly from the FIFO BRAM — the features are already in the packet. For flow-level statistics (duration, packet count), the host maintains a small flow table and appends computed features before sending to the SmartNIC. This is a natural data path because the input data is literally network traffic.

**Packet mapping:**
- Input: 41 BF16 features = 82 bytes = 11 data words.
- Output: 1 BF16 score (attack probability).

### Commercial Value

The IDS/IPS market is $5.7 billion (2024), growing at 7.3% CAGR. The FPGA security market alone is $2.34 billion. Key players: Cisco, Palo Alto Networks, Fortinet, Check Point. AMD acquired Pensando for $1.9 billion largely for inline network security on DPUs. Napatech markets SmartNICs specifically for IDS acceleration (Snort, Suricata). NVIDIA's BlueField DPU pitch includes inline security inspection.

The industry is converging on "ML inference in the data plane for security." Cisco Encrypted Traffic Analytics uses ML to classify encrypted traffic (which signature matching cannot do). Palo Alto's "Inline ML" (PAN-OS 10+) runs ML models in the data plane for zero-day detection. NVIDIA Morpheus is their AI cybersecurity framework for DPUs/SmartNICs.

### Honest Pros and Cons

- (+) **TA already endorsed it** — lowest approval risk
- (+) Data is already network packets — natural SmartNIC application
- (+) Massive, well-established market with clear commercial buyers
- (+) Feature extraction partially doable on the ARM CPU (packet headers in BRAM)
- (+) Extensive published baselines and comparison points
- (+) High expected accuracy (88–94%) — easy to demonstrate value
- (+) Simple binary output — easy to evaluate and demo ("attack" vs "normal")
- (-) **Overlaps in domain name** with Lab 3/4 mini-IDS, even though technique is completely different
- (-) Flow-level features (duration, packet count) require state tracking across multiple packets, adding host-side complexity
- (-) NSL-KDD is from 2009 and sometimes criticized as dated; CICIDS2017 is more modern but has 78 features
- (-) Larger model than financial candidate (48% vs 11% DMEM)

---

## Side-by-Side Comparison

| Criterion | Market Microstructure Scoring | Network IDS |
|-----------|------------------------------|-------------|
| Model size (BF16 params) | ~449 | ~1,979 |
| DMEM usage | 11% | 48% |
| Fits in hardware? | Yes, with 89% headroom | Yes, with 52% headroom |
| Primary dataset | Crypto tick data (free) | NSL-KDD (free) |
| Expected accuracy | 55–65% (normal for finance) | 88–94% (binary classification) |
| Market size | Hundreds of billions (HFT capital) | $5.7B (7% CAGR) |
| Would someone buy this? | Every market maker, exchange, broker | Cisco, Palo Alto, Fortinet, etc. |
| SmartNIC fit (data path) | **Best** — data IS UDP market packets | **Very good** — data IS network traffic |
| "Why a SmartNIC?" answer | "Canonical FPGA SmartNIC use case, inline ML on market data" | "Inline ML classification at wire speed, zero host CPU" |
| Overlap with prior labs | None | Same domain name as Lab 3/4 (different technique) |
| Academic precedent | Strong — 5+ university projects, one on NetFPGA | Moderate — several FPGA-IDS papers |
| Implementation effort | Low — smallest model, ~150 instructions | Medium — larger model, ~300 instructions |
| Demo appeal | High — "predict market direction" | High — "detect network attacks" |
| Competition/secrecy | HFT secrecy means no public reference; academic concepts freely published | Open research field with many published baselines |
| TA status | Not yet presented | Endorsed |

---

## Eliminated Candidates (with reasons)

### Predictive Maintenance — Eliminated by TA

The TA's objection: a SmartNIC is not the most suitable platform for vibration monitoring. The data originates from accelerometers, not from the network. The "one SmartNIC on the factory switch monitors many machines" angle is creative but ultimately does not overcome the fundamental question: why not just use a server with a GPU? Any compute platform can receive UDP packets — the SmartNIC's value is in processing data that is already in the network path, and vibration data is not.

Model (Autoencoder 33→16→8→16→33): ~1,485 BF16 params, 36% DMEM. Technically feasible but not aligned with course objectives.

### Breast Cancer Classification — Eliminated by TA Feedback

The TA's condition: only viable if it aligns with real-time / network packet needs. The Wisconsin dataset contains 30 tabular features derived from cell images — there is no natural reason this data would be network packets. Image classification (the real clinical workflow) does not fit the "network" topic. Even the tabular version requires the same hand-waving as predictive maintenance: "we packetize external data and send it to the NIC," which any compute platform could do.

Model (MLP 30→16→8→2): ~708 BF16 params, 17% DMEM. Simplest to implement but weakest network story.

---

## What We Need Guidance On

1. **Candidate preference.** We are leaning toward market microstructure scoring (strongest SmartNIC narrative, smallest model, no lab overlap, canonical FPGA use case). We have IDS as a solid backup with TA endorsement. Which direction does the professor prefer?

2. **Framing for financial ML.** We plan to call it "SmartNIC-Accelerated Market Microstructure Scoring" rather than "HFT" to set appropriate expectations for our Virtex-II Pro platform. We target the ML inference tier (~5μs), not the tick-to-trade tier (~100ns). Is this framing appropriate?

3. **Accuracy expectations in finance.** 55–65% directional prediction accuracy is commercially useful in finance (better than random, profitable over many trades). This is very different from the 90%+ accuracy expected in classification tasks. We want to confirm this will be evaluated fairly.

4. **Scope calibration.** Both candidates assume the host does feature extraction and the SmartNIC runs the final classifier. Is this split acceptable, or does the professor expect more of the pipeline to run on the NetFPGA itself?

5. **Evaluation metrics.** We plan to report: inference latency (GPU cycles), end-to-end packet latency (arrival to result), throughput (inferences/sec under single-packet buffering), accuracy vs. host-side reference (BF16 vs FP32 agreement), and resource utilization breakdown. Are there other metrics expected?

6. **Kernel complexity.** The matrix-vector multiply kernel rewrite uses the same ISA — no hardware changes. We want to confirm this firmware-level adaptation counts as sufficient "refinement" for Lab 10.
