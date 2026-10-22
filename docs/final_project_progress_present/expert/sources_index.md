# Sources index for the "expert" beat (competitor deep-dive)

Each file is a self-contained note pulled together from public docs / search snippets / paper excerpts. WebFetch was unable to extract some PDFs and was intermittently denied for some HTML pages -- where that happened we relied on WebSearch result snippets, which still surface the canonical phrases.

| File | Competitor | Topic |
|---|---|---|
| `fortinet_aiml_ips.md` | Fortinet | AI/ML IPS classifier in FortiOS 7.6 (CPU software, gated by signatures) |
| `fortinet_np7_brief.md` | Fortinet | NP7 network ASIC (200 Gbps, no ML) |
| `fortinet_fortindr_brief.md` | Fortinet | FortiNDR appliance (separate GPU box for deep neural net) |
| `paloalto_sp3_summary.md` | Palo Alto | SP3 architecture + Cavium OCTEON substrate |
| `paloalto_atp_inline_ml.md` | Palo Alto | ATP inline ML (cloud-based, not on-box) |
| `snort3_mpse_hyperscan.md` | Snort 3 / Talos | Detection engine, MPSE engines, Hyperscan integration, fast pattern matcher |
| `snort3_openappid.md` | Snort 3 / Talos | OpenAppID Lua application detectors |
| `pigasus_osdi2020_summary.md` | Pigasus (CMU) | FPGA IDS: hot/slow split, MSPM, 100 Gbps, 38x power saving |
| `hyperscan_nsdi19_notes.md` | (Hyperscan) | Engine internals (FDR / Teddy / Sheng / NFA-DFA hybrid) |

## Notes on data quality
- Fortinet does **not** publicly disclose the NP7's process node, gate count, or any block-diagram detail beyond the high-level offload list. All architectural specifics for NP7 in the docs above come from FortiOS admin-guide language about supported features.
- Palo Alto does not disclose the specific ML model topologies behind ATP. They name "deep learning" and "machine learning" only in the marketing register; technical filings would be needed to go deeper.
- Hyperscan, Snort, and Pigasus are the only three of the four with peer-reviewed papers and/or open source. Treat all Pigasus numbers (3.3 MB BRAM, 5 CPU cores, 38x power, 100 Gbps) as published OSDI 2020 / SIGCOMM 2022 facts.
