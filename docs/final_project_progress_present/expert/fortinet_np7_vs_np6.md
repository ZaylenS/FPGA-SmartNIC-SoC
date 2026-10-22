# Fortinet Network Processor Generations: NP6 → NP6XLite → NP7Lite → NP7

## Source URLs
- https://docs.fortinet.com/document/fortigate/7.6.6/hardware-acceleration/575471/network-processors-np7-np7lite-np6-np6xlite-and-np6lite (current admin guide, all variants in one page)
- https://docs.fortinet.com/document/fortigate/7.6.6/hardware-acceleration/512774/np7lite-processors (NP7Lite-specific page)
- https://docs.fortinet.com/document/fortigate/7.6.6/hardware-acceleration/177344/np6-np6xlite-and-np6lite-acceleration (NP6 family acceleration page)
- https://www.fortinet.com/blog/business-and-technology/hyperscale-security-enables-the-art-of-whats-possible (Hyperscale + NP7 launch context, Feb 2020)
- https://docs.fortinet.com/document/fortigate/6.2.17/hardware-acceleration/575471/network-processors-np7-np6-np6xlite-np6lite-and-np4 (older docs showing NP4 → NP6 history)

## Throughput, by generation

| Variant   | Max throughput | Interfaces                                  | SoC family |
|-----------|---------------|---------------------------------------------|------------|
| NP4       | 10 Gbps       | (legacy, FortiASIC NP4)                    | -          |
| NP6Lite   | 10 Gbps       | 2x QSGMII + 2x RGMII                        | SOC3       |
| NP6XLite  | 36 Gbps       | 4x KR/USXGMII/QSGMII + 2x RGMII            | SOC4       |
| NP6       | 40 Gbps       | 4x 10GE XAUI/QSGMII (or 3x10GE+16x1GE)     | discrete   |
| NP7Lite   | 40 Gbps       | 1x 40 GE                                    | SOC5 (= FortiSP5) |
| **NP7**   | **200 Gbps**  | **2x 100 GE**                              | discrete   |

The big architectural jump is **NP6 → NP7: 5x throughput** (40 → 200 Gbps), which Fortinet positions as supporting "100 Gbps of data flows — an exponentially greater performance level than the NP6." NP7 launched alongside the FortiGate 1800F in Feb 2020.

## Functional offload progression

**NP6 offloaded:**
- IPv4/IPv6 forwarding
- IPsec VPN encryption (basic)
- CAPWAP
- NAT44/66/64/46 session setup
- Multicast

**NP6XLite added (SOC4 generation, ~2018):**
- AES128-GCM and AES256-GCM offload for IPsec
- Same feature set as NP6 at slightly lower throughput (36 Gbps)

**NP7 added on top of NP6:**
- **GTP** (mobile-core tunneling for 5G/4G operators)
- **VXLAN** (data-center overlay)
- **Suite B** crypto (NSA-approved IPsec ciphers)
- **DoS protection** (volumetric, in NP7 fast path)
- Hyperscale-licensed mode: **CGN** (Carrier Grade NAT), **hardware logging**, **HA hardware session sync**
- Native 100 GE serdes

**NP7Lite (SoC5 / FortiSP5 internal block, 2023):**
- Same feature set as NP7, **except no hyperscale (no hardware sessions table)**
- Added: IPsec **SHA3-256 / SHA3-384 / SHA3-512** offload
- Removed: defrag/reassembly (DFR) is no longer offloaded
- Targets entry/mid-range FortiGates (FG-90G, FG-200G)

## Process node hints
- **NP6 / NP6Lite / NP6XLite:** undisclosed publicly. SOC3/SOC4 era (pre-2020). Not believed to be 7 nm.
- **NP7:** undisclosed. Launched Feb 2020.
- **NP7Lite:** **7 nm**, since it's the network-processor block inside FortiSP5 (officially "fifth-generation, 7-nm chip" per Fortinet press release). This is the *only* Fortinet chip with a publicly disclosed process node.

So per-watt comparison is somewhat apples-to-oranges: standalone NP7 may be on an older node than the NP7Lite block, even though they share architecture.

## Crypto evolution
- NP6: IPsec only; AES-CBC era.
- NP6XLite: + AES-GCM (authenticated encryption).
- NP7: + Suite B (ECC, AES-256, SHA-2 family).
- NP7Lite: + SHA-3 family (post-quantum-friendly hashes for IPsec authentication).

This is the clearest architectural progression in the NP family — each generation added a crypto cipher tier, not just throughput. **None of them added an ML / neural network unit.** All three generations remain purely fixed-function packet engines.

## Functions still NOT in the NP family (any generation)
- Pattern matching (that lives in CP9/CP10 content processors)
- IPS signature evaluation (CPU + CP9/CP10 hybrid)
- AI/ML IPS classifier (CPU only)
- L7 application identification (CPU + CP9/CP10)

The "NP" in NP7 stands for **Network Processor**. Fortinet has been very disciplined about keeping the NP a pure data-plane chip for 4+ generations. Inspection intelligence lives elsewhere in the SoC stack (CP9/CP10 ASIC + host CPU).

## Killer detail for Slide 1.3
**Four NP generations over ~10 years, 5x throughput jump from NP6 (40 Gbps) to NP7 (200 Gbps), and a steady ladder of crypto offload (AES-CBC → AES-GCM → Suite B → SHA-3). But zero ML offload — the entire NP roadmap is fixed-function packet forwarding plus crypto.** That is the architectural gap our chip targets: a programmable SIMD ML datapath in front of (or beside) the NP, evaluating model inference at the same line rate the NP forwards.
