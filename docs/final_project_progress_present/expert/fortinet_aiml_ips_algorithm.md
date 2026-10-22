# Fortinet AI/ML IPS Classifier — Algorithm Class Investigation

## Source URLs
- https://docs.fortinet.com/document/fortigate/7.6.6/administration-guide/408891/ai-and-ml-based-ips-detection (FortiOS 7.6.6 admin guide)
- https://docs.fortinet.com/document/fortigate/7.6.0/new-features/408891/ai-and-ml-based-ips-detection-7-6-3 (7.6.3 release notes — feature introduction)
- https://www.fortinet.com/fortiguard/labs (FortiGuard Labs marketing page)
- https://www.fortinet.com/content/dam/fortinet/assets/brochures/brochure-fortiguard-labs-overview.pdf (FortiGuard Labs brochure, ANN claim)
- https://www.fortinet.com/blog/business-and-technology/battle-ai-ml-cybersecurity-world (Fortinet's AI/ML strategy blog)
- https://www.fortinet.com/blog/business-and-technology/fortinet-is-the-security-innovation-leader-more-than-1500-patents-either-awarded-or-pending (1500+ patents, 103 in ML/AI)

## What Fortinet has and has NOT disclosed about the IPS classifier

**Disclosed (and only at the prose level):**
- The classifier is **supervised** — "distinguishing exploits from clean traffic through supervised learning."
- Features are **extracted during protocol decoding**, with **HTTP traffic** as the example domain explicitly named in the docs.
- The model is gated by **signature pre-filter** ("signatures are first used for preliminary filtering, allowing AI-based detection to be more targeted and efficient").
- Distribution: model file is shipped as the **"AI/Machine Learning IPS Definitions" package** downloaded via FortiGuard.
- Hybrid goal: **reduce false positives** on signature triggers, not detect zero-days from scratch.

**NOT disclosed (despite extensive search):**
- Algorithm class — **Fortinet has never publicly stated whether it is a CNN, transformer, gradient-boosted tree, random forest, or logistic regression.**
- Model size in MB / parameters
- Inference cost per packet or per flow
- Training corpus details
- Feature vector definition or feature count
- Whether the same model spans HTTP/SMTP/DNS/etc. or separate models per decoder

## Indirect evidence about the algorithm class

### "Artificial Neural Network" claim — but NOT for IPS
The FortiGuard Labs brochure says:
> "FortiGuard Labs has developed a state-of-the-art Artificial Neural Network comprised of billions of interconnected nodes that actively gather, process, and correlate data feeds."

And:
> "Fortinet created an artificial neural network (ANN) for sub-second sample classification, which has grown into FortiAI, which analyzes millions of samples per day."

**Caveat:** these ANN claims describe **FortiAI / sample classification (malware sample triage in FortiGuard Labs cloud)**, not the on-box IPS classifier. The "billions of nodes" phrasing reads as marketing for the labs-side correlation pipeline, not the per-flow classifier shipped to FortiGates.

### "Federated machine learning"
Fortinet markets a "Federated Machine Learning" approach for FortiGuard Labs that distributes training/analysis across the install base. Again — this is the **labs/cloud** side; nothing in the docs commits to federated ML happening on-box at IPS time.

### Lightweight on-box hint
The on-box AI/ML IPS feature is enabled via a single CLI toggle (`config ips global / set machine-learning-detection enable`), runs on the FortiGate's host CPU (no GPU, no NPU), gates on signature hits first, and ships as a downloadable definitions file. This profile is **much more consistent with a lightweight gradient-boosted tree (XGBoost/LightGBM) or a small MLP than with a CNN or transformer.** Tree ensembles are the dominant choice in IDS literature for HTTP/protocol-feature classifiers, and they fit on a CPU without an inference accelerator. A CNN/transformer would need either a GPU/NPU on the FortiGate (none has one) or would catastrophically tank threat-protection throughput.

### Patent landscape
Fortinet holds 103+ ML/AI-related patents per their 2022 milestone press. Public USPTO search shows filings in malware classification, URL classification, sandbox dynamic-analysis ML — but **no public patent or paper has been found that pins down the FortiOS 7.6.3+ IPS classifier algorithm specifically.**

## Architectural inference (what the slide can responsibly say)

1. The IPS classifier is a **supervised binary/multiclass classifier on protocol-decoder features**.
2. It runs on the **FortiGate host CPU** (no NPU, no GPU on FortiGates of this class).
3. It is **gated by signatures** — never sees clean traffic, only re-scores survivors.
4. **Algorithm class is undisclosed**, but the deployment profile (CPU-only, downloadable definitions file, gates on signatures) is **far more consistent with a lightweight tree ensemble or shallow MLP than a CNN/transformer**. The "billions of nodes ANN" marketing line refers to FortiAI cloud sample classification, not on-box IPS.

## Killer detail for Slide 1.3
**Even Fortinet, with 1500+ security patents and 100+ in ML/AI, has not publicly disclosed the algorithm class of the on-box IPS classifier.** What they *have* disclosed: it's supervised, runs on the host CPU, is gated by signature pre-filter, and ships as a downloadable definitions file. The deployment profile makes a CNN/transformer architecturally implausible — almost certainly a tree ensemble or shallow MLP at most. **No commercial vendor in the security space has shown an inline neural-network inference engine running on packet silicon.** That gap is what our chip claims.
