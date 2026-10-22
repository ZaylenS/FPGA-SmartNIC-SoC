# Part 3 Expert — References & Source Links (v3, 2026-04-27)

All sources cited in `part3_expert_v3.md` and the supporting research notes in `expert/`. Organized by topic. Use for the slide deck's references panel, Q&A backup, or reading list.

---

## 1. Fortinet — primary deep-dive subject (Slide 1.3)

### NP7 ASIC and packet-engine family
- **NP7 architectures** — https://docs.fortinet.com/document/fortigate/7.6.0/hardware-acceleration/46115/fortigate-np7-architectures
- **NP7 / NP7Lite / NP6 / NP6XLite / NP6Lite (one-page summary)** — https://docs.fortinet.com/document/fortigate/7.6.6/hardware-acceleration/575471/network-processors-np7-np7lite-np6-np6xlite-and-np6lite
- **NP7Lite-specific page** — https://docs.fortinet.com/document/fortigate/7.6.6/hardware-acceleration/512774/np7lite-processors
- **NP6 family acceleration** — https://docs.fortinet.com/document/fortigate/7.6.6/hardware-acceleration/177344/np6-np6xlite-and-np6lite-acceleration
- **NP roadmap historical context (NP4 → NP6)** — https://docs.fortinet.com/document/fortigate/6.2.17/hardware-acceleration/575471/network-processors-np7-np6-np6xlite-np6lite-and-np4
- **Hyperscale / NP7 launch context (Feb 2020)** — https://www.fortinet.com/blog/business-and-technology/hyperscale-security-enables-the-art-of-whats-possible

### FortiSP5 SoC (7 nm, Feb 2023)
- **Fortinet press release** — https://www.fortinet.com/corporate/about-us/newsroom/press-releases/2023/fortinet-unveils-new-asic-accelerate-networking-security-convergence-across-network-edges
- **The Register coverage** *("2.5 G of SSL inspection at the edge")* — https://www.theregister.com/2023/02/07/fortinet_sp5_asic/
- **ServeTheHome architecture summary** — https://www.servethehome.com/fortinet-fortisp5-asic-launched/
- **Packet Pushers analysis (Drew Conry-Murray)** — https://packetpushers.net/blog/fortinet-announces-a-new-system-on-chip-soc-for-its-firewall-appliances/
- **Fortinet exec Q&A (John Maddison on FortiSP5)** — https://www.fortinet.com/blog/business-and-technology/john-maddison-on-fortisp5-asic

### CPRL — Content Pattern Recognition Language
- **US Patent 8,140,660 B1** *(Wells et al., assigned to Fortinet, granted March 2012)* — https://patents.google.com/patent/US8140660B1/en
- **Companion application US 2012/0102196 A1** — https://patents.google.com/patent/US20120102196A1/en
- **Inside FortiOS: AntiVirus** *(references CPRL inside FortiASIC content processor)* — https://www.fortinetguru.com/2018/09/inside-fortios-antivirus/
- **Content Processors CP9 / CP10 / CP9XLite / CP9Lite** — https://docs.fortinet.com/document/fortigate/7.6.6/hardware-acceleration/622344/content-processors-cp10-cp9-cp9xlite-cp9lite
- **Fortinet glossary entry** — https://cookbook.fortinet.com/glossary/cprl/

### FortiOS AI / ML-based IPS (introduced in 7.6.3)
- **FortiOS 7.6.6 admin guide** — https://docs.fortinet.com/document/fortigate/7.6.6/administration-guide/408891/ai-and-ml-based-ips-detection
- **FortiOS 7.6.4 admin guide** — https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/408891/ai-and-ml-based-ips-detection
- **7.6.3 release notes** — https://docs.fortinet.com/document/fortigate/7.6.0/new-features/408891/ai-and-ml-based-ips-detection-7-6-3
- **FortiGuard Labs marketing page** — https://www.fortinet.com/fortiguard/labs
- **FortiGuard Labs brochure** *(ANN claim, "billions of nodes")* — https://www.fortinet.com/content/dam/fortinet/assets/brochures/brochure-fortiguard-labs-overview.pdf
- **Fortinet AI/ML strategy blog** — https://www.fortinet.com/blog/business-and-technology/battle-ai-ml-cybersecurity-world
- **Fortinet patent leadership blog** *(1,500+ patents, 100+ in ML/AI)* — https://www.fortinet.com/blog/business-and-technology/fortinet-is-the-security-innovation-leader-more-than-1500-patents-either-awarded-or-pending

### FortiNDR (separate appliance)
- **Introducing FortiNDR (blog)** — https://www.fortinet.com/blog/business-and-technology/introducing-fortindr
- **Loading the ANN database to FortiNDR** — https://docs.fortinet.com/document/fortindr/7.2.1/administration-guide/369868/loading-the-ann-database-to-fortindr-for-malware-detection
- **FortiNDR product overview** — https://www.fortinet.com/products/network-detection-and-response
- **FortiNDR datasheet (PDF)** — https://www.fortinet.com/content/dam/fortinet/assets/data-sheets/fortindr.pdf

### FortiGate appliance datasheets (200G / 3800G — for the inspection-cliff numbers)
- **FortiGate 200G series datasheet (PDF)** — https://www.fortinet.com/content/dam/fortinet/assets/data-sheets/pdf/fortigate-200g-series.pdf
- **FortiGate 3800G series datasheet (PDF)** — https://www.fortinet.com/content/dam/fortinet/assets/data-sheets/pdf/fortigate-3800g-series.pdf
- **FortiGate IPS solution brief** — https://www.fortinet.com/content/dam/fortinet/assets/solution-guides/sb-FortiGateIPS.pdf
- **FortiGate next-generation firewall product line** — https://www.fortinet.com/products/next-generation-firewall

### Independent test reports (IPS-engaged perf)
- **NSS Labs 2019 NGIPS test of FG-100F (PDF)** — https://www.fortinet.com/content/dam/fortinet/assets/analyst-reports/nss-labs-2019-ngips-test-report-fortinet-fortigate-100f.pdf
- **CyberRatings.org enterprise firewall test program** — https://cyberratings.org/technologies/enterprise-firewall/
- **CyberRatings + NSS Labs Nov-2025 follow-on results (FG-200G recertified)** — https://www.prnewswire.com/news-releases/cyberratingsorg-and-nss-labs-announce-follow-on-enterprise-firewall-results-302625281.html
- **Fortinet response to CyberRatings tests** — https://www.fortinet.com/blog/business-and-technology/fortigate-score-from-cyberratings

---

## 2. Palo Alto Networks (Slide 1.2 walkthrough)

### SP3 architecture
- **Single-Pass Parallel Processing whitepaper (PDF)** — https://media.paloaltonetworks.com/documents/Single_Pass_Parallel_Processing_Architecture.pdf
- **Firewall.cx writeup of SP3** — https://www.firewall.cx/security/palo-alto-networks/palo-alto-firewall-single-pass-parallel-processing-hardware-architecture.html
- **Community hardware deep-dive (staffeldt.net)** — https://www.staffeldt.net/palo-alto-networks-firewall-hardware-internals/
- **Cavium / OCTEON relationship (DarkReading)** — https://www.darkreading.com/perimeter/palo-alto-networks-designs-product-line-using-cavium-networks-octeon-ii-processor-family

### Advanced Threat Prevention with Inline ML
- **PAN Advanced Threat Prevention product** — https://www.paloaltonetworks.com/network-security/advanced-threat-prevention
- **What is Inline Deep Learning (Cyberpedia)** — https://www.paloaltonetworks.com/cyberpedia/what-is-inline-deep-learning
- **About Advanced Threat Prevention (docs)** — https://docs.paloaltonetworks.com/advanced-threat-prevention/getting-started/about-advanced-threat-prevention
- **PAN-OS 10.2 inline cloud analysis (release notes)** — https://docs.paloaltonetworks.com/pan-os/10-2/pan-os-new-features/content-inspection-features/inline-cloud-analysis

---

## 3. Snort 3 / Cisco Talos (Slide 1.2 walkthrough)

### Snort 3 / Hyperscan MPSE
- **Snort 3 + Hyperscan official blog** — https://blog.snort.org/2020/09/snort-3-hyperscan-.html
- **Intel: Hyperscan and Snort integration** — https://www.intel.com/content/www/us/en/developer/articles/technical/hyperscan-and-snort-integration.html
- **Snort 3 fast_pattern rule writing guide** — https://docs.snort.org/rules/options/payload/fast_pattern
- **Talos blog on fast patterns** — https://blog.talosintelligence.com/using-snort-fast-patterns-wisely-for/
- **Marc Norton's foundational paper** *(optimization of pattern matches for IDS)* — https://snort.org/documents/optimization-of-pattern-matches-for-ids
- **Hyperscan NSDI 2019 paper landing** — https://www.usenix.org/conference/nsdi19/presentation/wang-xiang
- **Hyperscan NSDI 2019 PDF** — https://www.usenix.org/system/files/nsdi19-wang-xiang.pdf
- **Geoff Langdale walkthrough (branchfree.org)** — https://branchfree.org/2019/02/28/paper-hyperscan-a-fast-multi-pattern-regex-matcher-for-modern-cpus/

### OpenAppID
- **Firing Up OpenAppID (announcement)** — https://blog.snort.org/2014/03/firing-up-openappid.html
- **Better application logging with Snort 3** — https://blog.snort.org/2020/10/better-application-logging-with-snort3.html
- **Developer docs (redBorder fork)** — https://github.com/redBorder/snort/blob/master/doc/README.appid
- **OpenAppID community webinar (PDF)** — https://snort-org-site.s3.amazonaws.com/production/document_files/files/000/000/066/original/OpenAppID-Community-Webinar.pdf
- **Snort 3 application identification (DeepWiki)** — https://deepwiki.com/snort3/snort3/4.3-application-identification

---

## 4. Pigasus (Slide 1.2 walkthrough; CMU OSDI 2020 — academic peer)

- **Paper landing page (USENIX)** — https://www.usenix.org/conference/osdi20/presentation/zhao-zhipeng
- **Paper PDF (USENIX)** — https://www.usenix.org/system/files/osdi20-zhao_zhipeng.pdf
- **Alternate PDF (Justine Sherry's site)** — https://justinesherry.com/papers/zhao-osdi20.pdf
- **Followup tutorial paper (Hoe, CMU)** — https://users.ece.cmu.edu/~jhoe/distribution/2021/zhao.pdf
- **"the morning paper" expert summary** — https://blog.acolyer.org/2020/11/16/pigasus/
- **Open-source release (GitHub)** — https://github.com/crossroadsfpga/pigasus
- **Architecture deep wiki** — https://deepwiki.com/crossroadsfpga/pigasus/2.1-single-fpga-design
- **Pigasus 2.0 (SIGCOMM 2022 poster, PDF)** — https://www.justinesherry.com/papers/zhao-sigcomm22-poster.pdf

---

## 5. NVIDIA Morpheus + BlueField (Slide 1.2 walkthrough)

- **Sensors 2025, 25, 130** — Chiriac, Anton, Ioniță, Vasilică. *"A Modular AI-Driven Intrusion Detection System for Network Traffic Monitoring in Industry 4.0, Using Nvidia Morpheus and Generative Adversarial Networks."* DOI: https://doi.org/10.3390/s25010130 — local file: `docs/final_project_progress_present/sensors-25-00130.pdf` (and `.txt`).
- **Morpheus GitHub** — https://github.com/nv-morpheus/Morpheus
- **Morpheus docs** — https://docs.nvidia.com/morpheus/index.html
- **ABP Detection Example** — https://docs.nvidia.com/morpheus/examples/abp_pcap_detection/readme.html
- **Triton Inference Server** — https://catalog.ngc.nvidia.com/orgs/nvidia/containers/tritonserver

---

## 6. Power-projection scaling (Beat 4 / Slide 3.1)

- **Kuon & Rose, "Measuring the Gap Between FPGAs and ASICs," IEEE Transactions on CAD of Integrated Circuits and Systems, 2007.** *(Cited inline; primary source for the FPGA-to-ASIC dynamic-power gap factor used in our 90 nm → 28 nm projection. IEEE Xplore: https://ieeexplore.ieee.org/document/4068926)*

---

## 7. Vendor Wikipedia pages (logo sources for Slides 1.1 / 1.2)

Logos pulled from Wikipedia Commons under fair-use educational. Saved at `docs/final_project_progress_present/expert/img/`:

- **Fortinet** — https://en.wikipedia.org/wiki/Fortinet
- **Palo Alto Networks** — https://en.wikipedia.org/wiki/Palo_Alto_Networks *(logo not auto-fetched; manual fetch needed)*
- **Cisco** — https://en.wikipedia.org/wiki/Cisco
- **NVIDIA** — https://en.wikipedia.org/wiki/Nvidia
- **AMD** — https://en.wikipedia.org/wiki/AMD
- **Intel** — https://en.wikipedia.org/wiki/Intel
- **Marvell Technology** — https://en.wikipedia.org/wiki/Marvell_Technology
- **Carnegie Mellon University** *(wordmark used as Pigasus attribution)* — https://en.wikipedia.org/wiki/Carnegie_Mellon_University

---

## 8. Local research notes (in repo)

All saved to `docs/final_project_progress_present/expert/`:

- `fortinet_aiml_ips.md` — FortiOS AI/ML IPS basics
- `fortinet_aiml_ips_algorithm.md` — algorithm class undisclosed; deployment profile rules out CNN
- `fortinet_np7_brief.md` — NP7 200 Gbps + offload list
- `fortinet_np7_vs_np6.md` — generation progression (NP6Lite → NP7), zero ML offload added
- `fortinet_sp5.md` — FortiSP5 SoC (NP7Lite + CP10 + ARM, 7 nm)
- `fortinet_cprl.md` — Content Pattern Recognition Language
- `fortinet_fortindr_brief.md` — FortiNDR appliance basics
- `fortinet_ips_engaged_perf.md` — inspection-cliff numbers (FG-3800G 800→200 Gbps with IPS engaged)
- `paloalto_sp3_summary.md` — SP3 architecture (Cavium-based)
- `paloalto_atp_inline_ml.md` — ATP cloud-roundtrip ML
- `snort3_mpse_hyperscan.md` — Snort 3 multi-pattern search engine + Hyperscan
- `snort3_openappid.md` — OpenAppID (Lua, no ML)
- `hyperscan_nsdi19_notes.md` — Hyperscan NSDI 2019 paper notes
- `pigasus_osdi2020_summary.md` — Pigasus paper summary
- `sources_index.md` — index across the above
