# Palo Alto Networks -- SP3 (Single-Pass Parallel Processing) Architecture

Source URLs:
- https://media.paloaltonetworks.com/documents/Single_Pass_Parallel_Processing_Architecture.pdf (official whitepaper)
- https://www.firewall.cx/security/palo-alto-networks/palo-alto-firewall-single-pass-parallel-processing-hardware-architecture.html (vendor-neutral writeup)
- https://www.staffeldt.net/palo-alto-networks-firewall-hardware-internals/ (community hardware deep-dive)
- https://www.darkreading.com/perimeter/palo-alto-networks-designs-product-line-using-cavium-networks-octeon-ii-processor-family (Cavium relationship)

## What this is
Palo Alto's flagship NGFW architecture. The whole company is built on the SP3 marketing claim: "every security function executes once, in one pass, on a packet."

## SP3 has two halves

### 1. Single-Pass Software
> "Networking, user identification (User-ID), policy lookup, traffic classification with application identification (App-ID), decoding, signature matching for identifying threats and contents, are all performed once per packet."

> "Unified Threat Management (UTM), which processes the traffic using multi-pass architecture, results in process overhead, latency introduction and throughput degradation."

> "Single Pass Software scans the contents based on the same stream and it uses uniform signature matching patterns to detect and block threats."

Key innovation: **stream-based** content scanning, **uniform signature** format across malware/IPS/URL/spyware (no separate signature engines).

### 2. Parallel Processing Hardware (data plane)
Three processor types on the data plane, connected by **high-speed 1 Gbps busses**:

| Processor | Function |
|-----------|----------|
| **Security Matching Processor (SMP)** | Vulnerability and virus signature matching |
| **Security Processor (SP)** | Hardware acceleration for SSL decryption, IPsec decryption |
| **Network Processor (NP)** | Routing, NAT, QoS, route lookup, MAC lookup |

Plus a separated **Control Plane** with its own CPU, RAM, and disk for management / logging / reporting. The two planes do not contend.

## Silicon implementation
- All Palo Alto NGFWs use **Cavium OCTEON** multi-core MIPS64-based network processors (now Marvell). The SMP / SP / NP are not separate chips -- they are roles assigned to OCTEON cores plus OCTEON's hardware accelerators (TCP offload, RegEx, compression, crypto).
- Cavium press release: "OCTEON family integrates 1 to 32 cores, networking interfaces and industry leading hardware acceleration for packet processing, quality of service, TCP offload, iSCSI offload, RAID, de-duplication, security, compression / decompression and deep packet inspection (DPI)."
- OCTEON's HFA (Hyper Finite Automata) RegEx engine is the silicon underneath SP3's signature matcher.

## Inline ML extension (PAN-OS 10.0+)
- Layered on top of SP3 -- **not** a re-architecture.
- Advanced Threat Prevention (ATP) adds inline ML / deep-learning detection engines for C2 over HTTP, HTTP2, SSL, unknown-UDP, unknown-TCP.
- **Cloud-based** detection engines. The firewall extracts features inline, ships them to PAN's cloud, gets a verdict back. Marketed as "first IPS to stop zero-day attacks inline in real-time."
- Claims: "six times faster prevention," "48% more evasive threats detected," "block up to 95% of never-before-seen file and web-based threats."

## Killer detail
**SP3's "ASIC" is actually general-purpose Cavium OCTEON MIPS cores with bolt-on RegEx engines.** When PAN added inline ML, they did not redesign silicon -- they shipped traffic features to a cloud and waited for the verdict. The ML is **off-box**.
