# Pigasus -- 100 Gbps Intrusion Prevention on a Single Server (CMU, OSDI 2020)

Source URLs:
- https://www.usenix.org/conference/osdi20/presentation/zhao-zhipeng (paper landing page)
- https://www.usenix.org/system/files/osdi20-zhao_zhipeng.pdf (PDF -- WebFetch could not extract due to compressed encoding)
- https://justinesherry.com/papers/zhao-osdi20.pdf (alternate PDF)
- https://users.ece.cmu.edu/~jhoe/distribution/2021/zhao.pdf (followup tutorial paper)
- https://blog.acolyer.org/2020/11/16/pigasus/ ("the morning paper" expert summary, used for pipeline details)
- https://github.com/crossroadsfpga/pigasus (open-source release)
- https://deepwiki.com/crossroadsfpga/pigasus/2.1-single-fpga-design (deep architecture wiki)
- https://www.justinesherry.com/papers/zhao-sigcomm22-poster.pdf (Pigasus 2.0 update)

Authors: Zhipeng Zhao, Hugo Sadok, Nirav Atre, James C. Hoe, Vyas Sekar, Justine Sherry. CMU + collaborators.

## Headline claim
> "Pigasus can support 100 Gbps using an average of 5 cores and 1 FPGA, using **38x less power** than a CPU-only approach."

> Target metrics: **100 Gbps line rate, 10,000+ rules concurrent, 100,000+ concurrent connections.**

## Architecture: FPGA-first, CPU as fallback

```
100GbE -> FPGA: Reassembler (R) -> MSPM Header Match -> MSPM Exact String Match
                                                             |
                                                             v (only ~5% of packets)
                                                      DMA Engine -> CPU Full Matcher
                                                             |
                                                      Verdict back to FPGA -> egress
```

**Pipeline stages on FPGA (named modules):**
1. **Ethernet IP core** (100 GbE MAC + PHY).
2. **Reassembler (R)** -- reconstructs TCP streams from out-of-order packet fragments. Runs entirely on FPGA. Stores per-flow state in BRAM.
3. **Multi-String Pattern Matcher (MSPM)** -- two phases:
   - **Header matcher** for all 10,000 Snort rules.
   - **Exact-string match** filter to determine which rules might possibly match.
4. **DMA Engine** -- when MSPM flags a possible match, packet + rule IDs cross PCIe to CPU.
5. **PCIe IP core** -- bulk DMA bus to CPU.

**On CPU:**
6. **Full Matcher** -- runs Aho-Corasick / regex over the small subset of "suspicious" packets to confirm matches. Polls a ring buffer populated by the FPGA's DMA engine.

## Key design idea: filter cascade

> "Pigasus FPGA performs TCP reassembly directly on the FPGA so that it can immediately apply exact string matching algorithms over payload data to determine which 'suspicious' packets need to enter a 'full match' mode requiring additional string matches and regular expression matching, leaving to the CPU only the final match stage to check a small number of signatures on excerpts of the bytestream **(on average, 1.1 signatures/packet and 5% of packets are sent to the CPU)**."

This is the same "fast pattern -> full rule" funnel Snort 3 uses, but with the fast filter implemented in **silicon** (FPGA) instead of SIMD CPU code.

## Resource footprint
- **FPGA card:** Intel Stratix 10 MX FPGA Development card (part `1SM21BHU2F53E1VG`). 16 MB BRAM distributed across 6,847 M20K blocks.
- **MSPM uses 3.3 MB of BRAM** total. "BRAM is reserved only for modules which require either latency-sensitive or throughput-demanding memory accesses, namely the Reassembler and the Multi-Pattern String Matcher."
- Choice between BRAM and on-die eSRAM for packet buffer (USE_BRAM parameter).
- CPU side: **5 cores average** suffice at 100 Gbps line-rate.

## Rule corpus
**Snort Registered Ruleset, ~10,000 rules.** Same rule format as commercial Snort 3 -- Pigasus reuses the existing rule corpus rather than inventing one.

## Comparison to Snort 3 (CPU baseline)
- Snort 3 alone needs many cores to hit even 10-20 Gbps. Pigasus matches 100 Gbps with 5 cores + 1 FPGA. Order-of-magnitude throughput per watt.
- Same algorithm class -- Aho-Corasick / regex -- just spatially mapped instead of temporally executed.

## Pigasus 2.0 (SIGCOMM '22 poster)
- Disaggregates Pigasus 1.0 into modules with "natural module boundaries" and standard interfaces.
- Adds multi-FPGA scaling via "FPGA-to-FPGA networked connection with credit-based flow control."
- DSP utilization optimized down to 0 (multipliers replaced with adders/shifters).

## Killer detail
**Pigasus uses 38x less power than CPU-only at 100 Gbps -- and still has no neural network anywhere.** It's a spatially mapped Aho-Corasick + regex pipeline. The hot/slow split is the trick. They are our closest academic peer in *kind* (custom silicon for IDS), but their algorithm is signature-matching, not ML. Our project answers a different question: does ML inference beat literal pattern matching at the FPGA's edge?
