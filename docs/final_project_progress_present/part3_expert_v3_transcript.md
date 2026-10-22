# Part 3 Expert — Speaking Transcript (v3 cliff-anchored, 2026-04-27)

Spoken-form version of the v3 speaker notes. Same content, conversational delivery. Read aloud to time it; estimated speaking time ~3 min.

---

## Beat 0 — Hook (no slide)

> "So, how do our competitors' solutions actually work?"

---

## Slide 1.1 — Industry network-security silicon

> "So there are two camps. On the left, specialized security hardware. On the right, general-purpose DPUs. Neither of them does on-die ML inference for intrusion detection. We're going to dig into the four biggest names — Fortinet, Palo Alto, Snort 3, and Pigasus — at the level of architecture, algorithm, and tricks."

---

## Slide 1.2 — Walkthrough

> "Let's go through them. Pigasus is the academic peer — comes out of CMU. Custom FPGA silicon for IDS, but pure pattern matching, no ML. Palo Alto's SP3 isn't custom silicon — it's just commodity Cavium cores — and their so-called inline ML is actually a cloud roundtrip. Snort 3 — Aho-Corasick from 1975, sped up with SIMD. No ML. And Nvidia Morpheus does real ML for IDS, but on commodity GPU and DPU."

---

## Slide 1.3 — Fortinet deep-dive

> "Now Fortinet — biggest name in network security. They actually did invest in custom silicon for security — the NP7 ASIC, 200 gigabits — but it only does signature offload. They kept ML off the chip. Instead, ML runs on the FortiGate's host CPU after signatures filter the traffic, then on a separate FortiNDR appliance with its own GPU off to the side, and finally in their FortiGuard cloud. So that's three different chips, three different latency tiers. And here's the cliff — their flagship hits 800 gigabits firewall throughput, but the moment you turn IPS on, it drops to 200. They built the silicon and stopped one step short. We put inspection right in the silicon."

---

## Slide 2.1 — ML inference at the silicon packet path

> "So Fortinet built custom silicon for security and stopped one step short — they kept ML off the chip. We took that next step. Custom silicon plus on-die ML — that combination isn't shipping anywhere. And we're sized for the edge — IoT, embedded systems, phones, anything low-power. Places the big players can't really reach."

---

## Slide 2.2 — Headline result

> "So 82.4 percent accuracy on the full NSL-KDD KDDTest+ benchmark — that's about 22 and a half thousand packets. The FPGA agrees with our dev replay bit-for-bit. The live demo right here shows 18 of 20 classified correctly, and every attack got caught. Six milliseconds per packet, end-to-end."

---

## Slide 3.1 — Measured FPGA + projected ASIC

> "So we measured the full chip at 2.67 watts on the FPGA — that's at 90 nanometer, and it includes all the NetFPGA platform overhead. Now if we apply Kuon and Rose's published FPGA-to-ASIC scaling, plus standard process scaling, our SoC projects down to about 90 to 110 milliwatts at 28 nanometer. At 7 nanometer it'd be around 30 to 50. And that's conservative — the only Fortinet chip with a disclosed process node is their FortiSP5, at 7 nanometer."

---

## Slide 3.2 — Power positioning

> "For context — Fortinet's current mid-range runs at 145 watts. Their flagship, 1.5 kilowatts. BlueField up to 150 watts. Our projected design point at 28 nanometer is under 200 milliwatts. That's three-plus orders of magnitude lower. And that's why we focus on the edge — power is the limiter, and nothing else fits."

---

## End — stop here. No outro.
