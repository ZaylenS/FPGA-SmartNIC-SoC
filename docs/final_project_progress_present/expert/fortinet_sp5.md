# Fortinet FortiSP5 Security Processor (SoC, Feb 2023)

## Source URLs
- https://www.fortinet.com/corporate/about-us/newsroom/press-releases/2023/fortinet-unveils-new-asic-accelerate-networking-security-convergence-across-network-edges (official press release, Feb 6 2023)
- https://www.theregister.com/2023/02/07/fortinet_sp5_asic/ (The Register coverage, "2.5G of SSL inspection at the edge")
- https://www.servethehome.com/fortinet-fortisp5-asic-launched/ (ServeTheHome architecture summary)
- https://packetpushers.net/blog/fortinet-announces-a-new-system-on-chip-soc-for-its-firewall-appliances/ (Packet Pushers, Drew Conry-Murray analysis)
- https://www.fortinet.com/blog/business-and-technology/john-maddison-on-fortisp5-asic (Fortinet Exec Q&A)
- https://docs.fortinet.com/document/fortigate/7.6.6/hardware-acceleration/512774/np7lite-processors (NP7Lite docs identifying SP5 SoC contents)

## What FortiSP5 actually is
A **System-on-Chip (SoC)**, not a discrete accelerator. The Packet Pushers analysis is explicit: *"The SP5 is a System on a Chip (SoC) built around two ARM CPUs as well as a dedicated network processor and a content processor."* Fortinet itself describes it as "more akin to a mobile system-on-chip like Apple's A15 or M1."

Fortinet's own docs confirm the internal block contents:
> "The NP7Lite processor is a component of the Fortinet SOC5 (also called the SP5). The SOC5 includes a CPU, the NP7Lite network processor, and a CP10 content processor."

So FortiSP5 = ARM CPU(s) + NP7Lite (network processor) + CP10 (content processor) on one die at TSMC 7 nm.

## Architectural relationship to NP7
- **NP7** = standalone discrete ASIC, ships in flagship 100 GE/400 GE FortiGates (3500F, 3800G, 4200F, 4400F). 200 Gbps per chip.
- **FortiSP5** = entry/mid-range SoC that *embeds* a cut-down NP7 (called NP7Lite, max 40 Gbps) plus a content processor (CP10) plus general-purpose CPU(s) on one die.
- Fortinet's strategy: use the *same* security IP block across product tiers. NP7 IP scales up as a discrete chip for the data center; the same-generation NP7Lite IP scales down inside SP5 SoC for the branch/edge.

## Functions FortiSP5 offloads
Per the press release and admin docs:
- L4-L7 firewalling (built-in L7 firewall)
- IPsec VPN encryption: 37 Gbps (32x faster than standard CPU)
- SSL deep inspection: 2.5 Gbps (the "killer feature" for branch SSL inspection)
- VXLAN/GRE hardware encapsulation
- Hardware-accelerated QoS / traffic shaping
- Volumetric DDoS protection
- ZTNA, SD-WAN forwarding
- Pattern matching for IPS and application identification (CP10 block)

## Performance vs CPU baseline (vendor claims)
- 17x firewall throughput vs leading standard CPU
- 3.5x NGFW throughput vs leading standard CPU
- 32x encryption throughput
- 88% lower power per workload
- 2.8 Gbps threat-protection throughput (FG-90G class)

## Why two purpose-built chips
**NP7 is for fast-path / data-plane scale.** It serves the 1U+ chassis FortiGates that need 100 GE / 400 GE I/O and pure forwarding throughput. It is paired *separately* with a CP9/CP10 content processor on the same board.

**FortiSP5 is for branch/edge integration economics.** A 1U branch box does not need 200 Gbps and cannot afford 4 separate ASICs. SP5 fuses CPU + NP7Lite + CP10 into one die so the bill of materials and power envelope fit a desktop/branch form factor. *That's also why SSL inspection is the headline feature: it's the function the CPU could not do at line rate at the edge.*

## Process node
**7 nm** (Fortinet press release, "fifth-generation, 7-nm chip"). This is the *only* publicly disclosed node geometry for any Fortinet chip — NP7's node remains undisclosed. Likely TSMC N7, given timing and Arm SoC industry norm.

## Killer detail for Slide 1.3
**Fortinet built two purpose-built chips because one geometry doesn't fit both ends of the product line.** NP7 = pure 200 Gbps data-plane forwarding ASIC for big iron. FortiSP5 = 7 nm SoC embedding NP7Lite + CP10 + ARM CPUs for branch boxes that need SSL inspection at 2.5 Gbps. **Neither chip carries an ML inference unit on the data path.** The CPU side (ARM cores in SP5; host x86 in NP7-equipped boxes) is still where the AI/ML IPS classifier runs.
