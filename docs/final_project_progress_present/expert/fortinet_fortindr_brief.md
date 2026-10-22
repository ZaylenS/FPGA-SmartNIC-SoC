# FortiNDR (Network Detection and Response) -- Fortinet's Neural-Network Appliance

Source URLs:
- https://www.fortinet.com/blog/business-and-technology/introducing-fortindr
- https://docs.fortinet.com/document/fortindr/7.2.1/administration-guide/369868/loading-the-ann-database-to-fortindr-for-malware-detection
- https://www.fortinet.com/products/network-detection-and-response (product overview)
- https://www.fortinet.com/content/dam/fortinet/assets/data-sheets/fortindr.pdf (datasheet, binary; cited via search)

## What this is
A **separate physical appliance** (e.g. FortiNDR-1000F, -3500F) that does the heavy ML work Fortinet's IPS does not do on the FortiGate itself. Marketed as the "Virtual Security Analyst (VSA)."

## Key technical excerpts

> "FortiNDR employs patent-pending Deep Neural Networks based on Advanced AI and Artificial Neural Network to provide sub-second investigation by harnessing deep learning technologies."

> "The state-of-the-art ANN is pre-trained in FortiGuard labs with 20M+ clean and malicious files and further learning is done on premises."

> "Pre-trained with more than 6 million malicious and safe features that can identify IT- and OT-based malware and classify it into threat categories."

> "ANN DB does not require updates daily. ANN is only updated once or twice a week."

> Two named DB files for the ANN: `moat_kdb_all.tar.gz`, `pae_kdb_all.tar.gz`. Update via FortiGuard FDN (1-2 hr) or USB load (~10 min).

> Files scanned over HTTP, SMB, SMTP.

## Architecture summary
- **Form factor:** dedicated appliance ("sensor mode" optional). Lives **off the data path** in most deployments -- traffic is mirrored to it.
- **Compute:** GPU + CPU (consistent with deep-net inference; specific GPU model not disclosed in public docs).
- **Algorithm:** deep neural network classifier on extracted file features. Pre-trained centrally, fine-tuned per customer.
- **Output:** classifies malware into categories, identifies "patient zero," reconstructs lateral spread.
- **Deployment model:** "cloud-plus-on-premises AI" with FortiGuard cloud doing training and threat intel, FortiNDR appliance doing inference.
- **Integration:** plugs into FortiOS, FortiNAC, FortiSwitch via Security Fabric APIs.

## Killer detail
**Deep learning is not on the FortiGate** -- it is on a separate purchased appliance with its own GPU. Fortinet's portfolio confirms the architectural pattern of decoupling the network ASIC (NP7) from the ML engine (FortiNDR). Our project collapses these into one chip.
