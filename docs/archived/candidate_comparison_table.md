# Final Project Candidates — Quick Comparison (Updated)

Updated March 24, 2026 after TA feedback. Predictive maintenance eliminated (TA: "not aligned with class, why use SmartNIC"). Breast cancer eliminated (TA: "only if aligned with network/real-time needs" — it isn't). Market microstructure scoring added as new primary candidate.

Hardware context: GPU has 1024 x 64-bit DMEM (4096 BF16 slots), 4-lane BF16 SIMD with FMA, 1024 instructions. Both candidates use the same pattern: host extracts features, sends as UDP packet, GPU runs inference, result returned in packet.

||**Market Microstructure Scoring (Primary)**|**Network Intrusion Detection (Backup)**|
|-|-|-|
|**What it does**|Score trade flow direction (buy/hold/sell) or order flow toxicity from market microstructure features extracted from UDP market data packets|Classify network flows as normal vs. attack using statistical features from packet headers and flow metadata|
|**Model**|MLP: 15→16→8→3 (trade flow) or 20→16→8→1 (toxicity)|MLP: 41→32→16→1|
|**Parameters**|~449 BF16 (trade flow) or ~511 (toxicity)|~1,979 BF16|
|**DMEM usage**|113 / 1024 words (11%) or 129 / 1024 (13%)|496 / 1024 words (48%)|
|**Input per packet**|15 features (4 data words) or 20 features (5 data words)|41 features (11 data words)|
|**Output**|3 class scores (1 word) or 1 toxicity score (1 word)|Attack probability (1 word)|
|**Dataset**|Crypto tick data from Binance/Coinbase (free), Kaggle order book datasets, Lobster NASDAQ (academic pricing)|NSL-KDD (free, 125K records, 41 features)|
|**Expected accuracy**|55–65% directional (commercially useful in finance; >50% = profitable)|88–94% binary classification on KDDTest+|
|**Market**|HFT firms manage hundreds of billions; FPGA SmartNIC vendors (Xilinx, Napatech) are billion-dollar businesses|$5.7B (2024), 7.3% CAGR|
|**Who buys this**|Every market maker (Citadel, Virtu, Jump), every exchange, every institutional broker|Cisco, Palo Alto, Fortinet, Napatech|
|**SmartNIC fit**|Best — canonical FPGA SmartNIC use case, market data IS UDP multicast, orders ARE network packets|Very good — input data is network traffic, most natural after financial|
|**"Why a SmartNIC?"**|"This IS what FPGA SmartNICs are built for. Solarflare/Xilinx cards in 90% of exchanges."|"Inline ML at wire speed, zero host CPU. Industry moving to ML-in-data-plane for security."|
|**Prior lab overlap**|None|Same domain name as Lab 3/4 mini-IDS, but completely different technique (learned MLP vs. string matcher comparators)|
|**Academic precedent**|Strong — Waterloo (NetFPGA!), Columbia, MIT, U of Toronto, NYU, plus papers on Virtex-II Pro Black-Scholes|Moderate — several FPGA-IDS papers with NSL-KDD|
|**Implementation effort**|Low — smallest model of any candidate, ~150 instructions|Medium — larger model, ~300 instructions|
|**Competition/secrecy**|HFT firms never publish systems; no public reference to compare against; academic concepts (VPIN, Lee-Ready) freely published|Open research field with many published baselines to compare against|
|**What makes it interesting**|Canonical SmartNIC use case. Data IS packets. Smallest model. No lab overlap. "We built a SmartNIC that scores market data inline — same pattern as Xilinx Alveo / Exablaze, on a 2003-era educational platform."|TA endorsed. Natural network application. High accuracy. Well-studied domain with extensive baselines.|
|**Main risk**|Term "HFT" may seem aspirational — must frame as "ML inference tier" at ~5μs, not tick-to-trade at ~100ns. 55% accuracy needs financial context.|Lab 3/4 domain name overlap requires careful framing despite fundamentally different technique.|
|**TA status**|Not yet presented|Endorsed|
