# Palo Alto Networks -- Advanced Threat Prevention (ATP) with Inline Machine Learning

Source URLs:
- https://www.paloaltonetworks.com/network-security/advanced-threat-prevention
- https://www.paloaltonetworks.com/cyberpedia/what-is-inline-deep-learning
- https://docs.paloaltonetworks.com/advanced-threat-prevention/getting-started/about-advanced-threat-prevention
- https://docs.paloaltonetworks.com/pan-os/10-2/pan-os-new-features/content-inspection-features/inline-cloud-analysis
- PAN-OS 10.2 Nebula press release

## What this is
The cloud-assisted ML upgrade Palo Alto added on top of SP3 starting with PAN-OS 10.0 / 10.2 ("Nebula"). Marketed as "industry's first inline deep learning protection."

## Architecture (as documented)

> "Inline deep learning is the process of taking the analysis capabilities of deep learning and placing it inline, where it is used to analyze and detect malicious traffic as it enters a network, and block threats in real time."

> "Palo Alto Networks operates a series of ML-based detection engines in the Advanced Threat Prevention cloud to analyze traffic for advanced C2 (command-and-control) and spyware threats in real-time."

> "Inline cloud analysis supports five analysis engines for C2-based threats over HTTP, HTTP2, SSL, unknown-UDP, and unknown-TCP."

> "By operating cloud-based detection engines, organizations can access a wide array of detection mechanisms that are updated and deployed automatically without requiring the user to download update packages or operate process intensive, firewall-based analyzers."

So "inline" here means **inline relative to the user's traffic flow** -- the firewall holds the packet and asks the cloud. It is **not** "inline on the chip."

## Pipeline

```
packet -> SP3 single-pass scan
       -> ATP inline classifier extracts features (HTTP headers, TLS metadata, payload byte features)
       -> Features posted to PAN-OS ATP cloud
       -> Cloud returns verdict (malicious / benign / suspicious)
       -> Firewall blocks/allows
```

## Algorithm class
- **Deep learning models** (Palo Alto explicitly uses the phrase "inline deep learning"). Architecture not disclosed -- presumably feedforward and recurrent classifiers per traffic class. Documentation does not name LSTM, transformer, or other specific topologies.
- **Five separate engines**, one per protocol family (HTTP, HTTP2, SSL, unknown-UDP, unknown-TCP).
- **Training data** comes from WildFire (PAN's malware sandbox network).

## Performance / accuracy claims
- "Block up to 95% of never-before-seen file and web-based threats."
- PAN-OS 10.2 Nebula: "six times faster prevention and 48% more evasive threats detected."
- **Latency:** roundtrip to cloud is the floor. PAN does not publish a hard number.

## Killer detail
**The ML inference does not run on the firewall.** PAN's "inline" ML is a cloud roundtrip. They scaled by moving the ML off the box, not by putting it in silicon.
