# Fortinet AI / ML-Based IPS Detection (FortiGate / FortiOS 7.6)

Source URLs:
- https://docs.fortinet.com/document/fortigate/7.6.6/administration-guide/408891/ai-and-ml-based-ips-detection
- https://docs.fortinet.com/document/fortigate/7.6.4/administration-guide/408891/ai-and-ml-based-ips-detection
- https://docs.fortinet.com/document/fortigate/7.6.0/new-features/408891/ai-and-ml-based-ips-detection-7-6-3

## What this is
The FortiOS Administration Guide page describing the AI/ML feature added to the FortiGate IPS engine starting in 7.6.3. This is **inside FortiOS** -- it runs on the FortiGate's main CPU (not on the NP7 ASIC).

## Key technical excerpts (paraphrased / from search snippets, since the live docs page only renders a navigation index when fetched)

> "AI and machine learning-based models are trained on features extracted during protocol decoding, such as HTTP traffic. These models act as classifiers, distinguishing exploits from clean traffic through supervised learning."

> "Instead of applying machine learning models blindly across all traffic, signatures are first used for preliminary filtering, allowing AI-based detection to be more targeted and efficient. This hybrid approach reduces false positives while maintaining high performance."

> "The AI/Machine Learning IPS Definitions package is downloaded by FortiOS from FortiGuard through FortiGuard updates."

> CLI: `config ips global / set machine-learning-detection {enable | disable} / end`

## Architecture summary
- **Pipeline placement:** ML classifier sits **after** the existing Aho-Corasick / pattern signature stage. Signatures pre-filter; ML re-scores survivors.
- **Feature extraction:** done during protocol decoding (HTTP fields are explicitly named in the docs).
- **Algorithm class:** supervised classifier, trained off-box in FortiGuard Labs, distributed as a downloadable "AI/Machine Learning IPS Definitions" package.
- **Hardware path:** runs in **FortiOS software on the FortiGate management/control CPU**, not on the NP7 packet engine. NP7 is below this stage.
- **Goal:** reduce false positives on existing signature triggers, not to detect zero days from scratch.

## Killer detail
ML detection is **gated by signatures** -- the model never sees clean traffic. It is a re-scorer, not a primary classifier.
