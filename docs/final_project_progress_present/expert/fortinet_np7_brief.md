# Fortinet NP7 Network Processor

Source URLs:
- https://docs.fortinet.com/document/fortigate/7.6.0/hardware-acceleration/46115/fortigate-np7-architectures
- https://docs.fortinet.com/document/fortigate/7.6.6/hardware-acceleration/575471/network-processors-np7-np7lite-np6-np6xlite-and-np6lite

## What this is
Fortinet's purpose-built ASIC for line-rate packet processing inside FortiGate appliances. Compute substrate for the data plane. Does not run ML.

## Key facts disclosed in docs
- **Throughput:** 200 Gbps maximum (2 x 100 Gbps interfaces) per NP7.
- **Variants:** NP7, NP7Lite, NP6, NP6XLite, NP6Lite (each successive generation adds throughput / functions).
- **Offload list** (from FortiOS 7.6 docs):
  - IPv4/IPv6 traffic forwarding
  - IPsec VPN encryption (Suite B included)
  - GTP, CAPWAP, VXLAN tunneling
  - NAT44, NAT66, NAT64, NAT46 session setup
  - DoS protection
  - On hyperscale-licensed FortiGates: CGN, hardware logging, HA session sync
- **Internal blocks named in docs:** Integrated Switch Fabric (ISF), inter-VDOM link acceleration, NP7 traffic shaping, `config np-queues` for protocol prioritization.
- **Process node:** **not disclosed publicly**. Fortinet does not publish the NP7's process geometry, gate count, or die size.
- **Toolchain:** programmed and configured via FortiOS, no public SDK.

## What NP7 does NOT do
- No machine learning inference (no neural network unit, no SIMD ALU described in public docs).
- No deep packet inspection beyond fixed-function tunneling / NAT / ACL.
- IPS pattern matching, signature evaluation, and AI/ML IPS classifier all execute on the FortiGate **CPU**, not the NP7.

## Killer detail
A 200 Gbps purpose-built network ASIC on a competitor box that **explicitly does not contain the ML detection engine**. Their AI/ML IPS runs in software on the host CPU above NP7. That is the architectural gap our chip targets.
