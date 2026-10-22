# Brainstorm — Market Sizing for Investor Pitch

Goal: 2-3 defensible market numbers to cite in the investor video. Investors discount narrative; numbers anchor a pitch.

## 1. Three Market Layers

Our technology touches three overlapping markets. Pick one to lead with; name the others as adjacent.

### 1.1 Edge AI / IoT Security
- IoT device count: ~30 billion connected by 2030 (Cisco / IoT Analytics forecasts).
- Edge AI inference market: projected to reach ~$60B by 2028 (MarketsandMarkets, IDC).
- Growth rate: ~25-30% CAGR.
- Driver: privacy regulations push compute to the device (EU AI Act, California privacy laws).

**[DIG DEEPER]:** Pin down a *single* citation for each number. Research agent output in `../deep-research-report-IDS-on-SmartNIC.md` likely has some; verify freshness (prefer 2024+ data).

### 1.2 SmartNIC / Enterprise Network Security
- SmartNIC market: ~$8-12B by 2028 (mid-range estimates across analysts).
- Network security market overall: ~$200B (Gartner 2024).
- Growth rate: SmartNIC ~25-30% CAGR; network security overall ~8-10%.
- Incumbents: NVIDIA BlueField, AMD Pensando, Intel IPU, Marvell.

**[DIG DEEPER]:** Our system is not a competitive SmartNIC yet — don't claim head-to-head. Position as "specialized cousin: ML-first SmartNIC for security workloads."

### 1.3 AI Supply-Chain Security
- Not yet a standalone market category in analyst reports (early 2026).
- Adjacent categories: AI risk management, MLOps security, enterprise AI governance.
- Anchor documents: NIST AI RMF (2023) and EU AI Act (2024) both call out supply-chain threats.
- Growth: implicit in the $100B+ being poured into AI infrastructure — a small fraction goes to securing it.

**[DIG DEEPER]:** Find a single Gartner / IDC / Forrester line that says "AI security will be $X by 202Y." If none exists, position as "category being formed right now" — that's an investor narrative hook in itself ("ground floor").

**[DIG DEEPER]:** Pull the NIST AI RMF document and cite one specific supply-chain attack category (data poisoning, model theft, weight tampering). Anchor the user's "hundreds of thousands to tamper a billion-dollar model" story with this citation.

## 2. Reference Reports Already in Repo

Two deep research reports in `../` are existing source material:
- `../deep-research-report-IDS-on-SmartNIC.md` — pull SmartNIC market data and IDS-on-NIC positioning here
- `../deep-research-report-SmartNIC-ann.md` — ML-on-SmartNIC specifics

**[DIG DEEPER]:** Re-read these two reports end-to-end; extract 3-5 pull-quotes with numbers. They're already researched — this is low-hanging fruit.

## 3. Growth Rate Story

Investors discount single numbers; they value *trajectory*. Story structure:

> "In 2020, the SmartNIC market was $2B. By 2024, it was $6B. By 2028, analysts project $12B. That's a 6x in 8 years. The driver? AI workloads are eating network bandwidth, and general-purpose CPUs can't keep up with security inspection at line rate. Specialized hardware is the only answer."

**[DIG DEEPER]:** Verify those trajectory numbers. Even a rough trajectory chart (smooth upward) is more persuasive than a static TAM.

## 4. Comparable Companies (for investor signaling)

| Company | Category | Valuation signal |
|---------|----------|------------------|
| CrowdStrike | Enterprise endpoint security | ~$80B market cap (2024) — "security in software is huge" |
| Palo Alto Networks | Network security | ~$100B — "network-layer security is massive" |
| Fortinet | Network security hardware | ~$50B — closest analog (hardware security) |
| NVIDIA BlueField | SmartNIC (inside NVDA) | Not split out, but NVDA as a whole is the ultimate signal |
| AMD Pensando | SmartNIC | AMD acquired for $1.9B in 2022 — shows appetite |

**[DIG DEEPER]:** Professor mentioned Fortinet specifically (per `../../memory` `project_professor_meeting_0326.md`). Lean into this — it gives the pitch a local-credibility anchor and signals you did your homework.

**[DIG DEEPER]:** AMD Pensando acquisition price ($1.9B) is a useful "exit comp" — that's what a company in this space is worth when acquired. Investors love exit comps.

## 5. The "We're Different" Lead (differentiation)

Investors need to know why we're not a me-too:
1. **ML-first ISA** — we extended our GPU's ISA with BCAST specifically for ML workloads. Incumbents built general-purpose compute; we built security-ML compute.
2. **Measured speedup** — 3.28x on the IDS workload, hardware-verified 2026-04-17.
3. **Open toolchain** — we built the assembler, compiler path, and kernel library. Enterprises increasingly want customizable silicon.
4. **Solo-team engineering** — implicit signal: capital-efficient team. (Investor catnip.)

**[DIG DEEPER]:** Validate each claim on camera. "ML-first ISA" is true (BCAST was added for ML SIMD patterns). "3.28x" is against our own scalar baseline, not a competitor. Honest framing required.

**[DIG DEEPER]:** Competitive landscape chart — could be a 2x2 matrix (specialized / general × on-prem / cloud). We're the top-left quadrant (specialized, on-prem edge).

## 6. Dollar Hooks (short punchy lines for the video)

Options to pick from:
- "The SmartNIC market crosses $10 billion before the end of the decade."
- "Every data center has a network security bill. It's $200 billion a year."
- "Companies spend billions training AI. They spend almost nothing protecting it."
- "Fortinet is worth $50 billion and they don't do edge AI. That's the gap we're filling."

**[DIG DEEPER]:** Pick ONE to be the video's headline dollar line. The rest are supporting.

## 7. Honest Caveats (never say these on camera, but know them)

- Our 3.28x speedup is against our own baseline, not a commercial benchmark.
- We have no customers, no revenue, no pilot.
- Our 75% IDS accuracy is on NSL-KDD, a dataset critiqued as obsolete (COMIDDS).
- A real product needs far more ML work (retrain on modern traffic), hardware work (in-FPGA filter path), and business work (compliance, deployments).

**[DIG DEEPER]:** Don't overstate — investors can smell hype. Lead with the market and the differentiation; let the technical work speak as supporting evidence, not as the whole pitch.

## 8. Priority Research List (before filming)

Ranked by expected value per hour:

1. **[HIGH]** Pull 3 TAM numbers with sources (SmartNIC, edge AI, network security).
2. **[HIGH]** Find one cite-able AI supply-chain attack incident (news article, report, NIST doc).
3. **[MEDIUM]** Find the AMD Pensando acquisition price announcement (PR Newswire or SEC filing).
4. **[MEDIUM]** Confirm Fortinet market cap in 2026 (current — not 2024).
5. **[LOW]** Optional: read the 2024 Verizon DBIR for a DDoS / IDS stat if needed.
