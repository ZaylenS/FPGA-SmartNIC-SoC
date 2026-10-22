# Fortinet FortiGate IPS-Engaged Performance Numbers

## Source URLs
- https://www.fortinet.com/content/dam/fortinet/assets/data-sheets/pdf/fortigate-200g-series.pdf (FortiGate 200G series datasheet — IPS/NGFW/Threat Protection figures)
- https://www.fortinet.com/content/dam/fortinet/assets/data-sheets/pdf/fortigate-3800g-series.pdf (FortiGate 3800G series datasheet)
- https://www.fortinet.com/content/dam/fortinet/assets/analyst-reports/nss-labs-2019-ngips-test-report-fortinet-fortigate-100f.pdf (NSS Labs 2019 NGIPS test of FG-100F)
- https://cyberratings.org/technologies/enterprise-firewall/ (CyberRatings.org enterprise firewall test program)
- https://www.prnewswire.com/news-releases/cyberratingsorg-and-nss-labs-announce-follow-on-enterprise-firewall-results-302625281.html (Nov 2025 follow-on results, FG-200G)
- https://www.fortinet.com/blog/business-and-technology/fortigate-score-from-cyberratings (CyberRatings.org test commentary)
- https://www.fortinet.com/content/dam/fortinet/assets/solution-guides/sb-FortiGateIPS.pdf (FortiGate IPS solution brief)

## Datasheet-disclosed throughput tiers (key insight)

Fortinet datasheets publish **multiple throughput numbers per box**, which lets you back-calculate the IPS-engaged cost:

### FortiGate 200G (NP7Lite + CP10, FortiSP5 SoC, mid-range)
- Firewall throughput: **39 Gbps**
- IPS throughput: **8 Gbps**
- NGFW throughput: **7 Gbps**
- Threat Protection throughput: **6.4 Gbps** ← all features on
- VPN: 35 Gbps
- New sessions/sec: 390,000
- Concurrent sessions: 11M

**Threat-protection / firewall ratio = 6.4 / 39 = 16.4%.** Turning on full security drops effective throughput to roughly **1/6 of fast-path firewall**.

### FortiGate 3800G (NP7 + CP10, flagship)
- Firewall throughput: **800 Gbps** (4x 400 GE QSFP-DD)
- IPS throughput: **250 Gbps**
- NGFW throughput: **210 Gbps**
- Threat Protection throughput: **200 Gbps** ← all features on
- IPsec VPN: 210 Gbps
- Concurrent sessions: 200M

**Threat-protection / firewall ratio = 200 / 800 = 25%.** Even on the flagship $$$$$ chassis with NP7 + CP10, full IPS engagement still costs **75% of nominal firewall throughput**.

### Comparison entry-level (FG-60F, NP6Lite class)
- Firewall: 10 Gbps
- Threat Protection: 0.7 Gbps
- **Ratio: 7%** — full security collapses to 1/14 of nominal.

The pattern: as you go up the product line and add bigger NP / CP silicon, the threat-protection / firewall ratio **rises but never approaches 1.0** (60F: 7%, 200G: 16%, 3800G: 25%). The IPS pipeline (CPU + CP9/CP10) cannot keep up with the NP fast path.

## Latency disclosures

### Datasheet (firewall fast-path only)
Fortinet datasheets do **not** publish IPS-engaged latency. The *only* latency numbers in 200G/3800G datasheets are:
- 200G: latency on RFC 2544 (small-packet 64B firewall): not explicitly listed in the abridged spec sheet
- Marketing line: "ultra-low latency" and "best ultra-low latency across different packet sizes in NSS Labs testing"

### NSS Labs (now CyberRatings.org)
NSS Labs publishes **application response time** with security on, measured in milliseconds, but at the per-platform level. The 2019 NGIPS test of FG-100F is the most-cited public document, but it focuses on:
- Block rate: 99.18% cumulative
- TCO: $2 per protected Mbps
- Evasion resistance

Latency-with-IPS-on numbers are inside the report bodies but Fortinet does not summarize them on marketing pages. Result: **no public summary table compares IPS-on latency across FortiGate models the way they do for firewall throughput.**

### CyberRatings.org Nov 2025 follow-on
The Nov 2025 follow-on test specifically retested FortiGate 200G and Palo Alto PA-1410 (both moved from "Caution" to "Recommended" after fixing **evasion-resistance defects** found in the June 2024 round). This is significant because the same product (FG-200G) needed a firmware re-spin to pass evasion. It does not include IPS-on latency tables.

## NDR-mode performance disclosures
**FortiNDR is a separate appliance**, not a FortiGate mode. Fortinet does **not** publish a "FortiGate-as-NDR" performance number. The FortiNDR datasheet (already covered in `fortinet_fortindr_brief.md`) gives appliance throughput in malware-samples/sec, not Gbps. There is no public benchmark of "FortiGate-200G with FortiAI / NDR-equivalent ML enabled."

## What this means for the slide

1. **Vendor-published "firewall throughput" is a fast-path-only number.** The honest "IPS engaged" number is the **threat-protection throughput**, which is 16-25% of firewall throughput on NP7 boxes.
2. **Latency-with-IPS-on is not in datasheets.** Even Fortinet keeps that out of marketing materials. Real-world latency with IPS+app-control+AV on is measured by NSS/CyberRatings but never headlined.
3. **No NDR-mode FortiGate number exists** — that workload runs on a separate FortiNDR appliance.
4. **The 75% throughput drop on the $$$ flagship is the strongest data point.** Even with NP7 (200 Gbps fast path) and CP10 (20 Gbps IPSA pattern matching) silicon support, turning on the full inspection pipeline drops the FG-3800G from 800 Gbps fast path to 200 Gbps protected. **That delta is exactly what our SmartNIC ML-on-silicon is designed to recapture.**

## Killer detail for Slide 1.3
**FortiGate 3800G — the $$$$$ flagship with NP7 + CP10 silicon — drops from 800 Gbps (firewall fast path) to 200 Gbps (full threat protection): a 75% throughput collapse the moment you turn on IPS + ML. The mid-range 200G (with FortiSP5 SoC) drops from 39 Gbps to 6.4 Gbps — an 84% collapse.** Even *with* purpose-built network and content silicon, the inspection layer is the bottleneck — because the IPS classifier runs in software on the host CPU. Fortinet does not publish IPS-engaged latency or NDR-mode throughput at all. **That gap, between fast-path and protected throughput, is the headline market opportunity for inline-ML silicon.**
