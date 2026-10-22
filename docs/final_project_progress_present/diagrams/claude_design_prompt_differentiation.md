# Claude Design Prompt — Differentiation Diagram (Clip C-DIFF)

**Created 2026-04-21**: chosen framing = 2x2 on **Detection paradigm (Signature ↔ ML)** × **Data-path locality (Off-NIC ↔ Inline at NIC)**. Matches user-spec §E requirement: *"a diagram of your solution that differentiates your solution from existing solutions."*

Selected over the earlier cloud/edge × general/app-specific framing (drafted in `../part3_expert.md` §3.5) because these axes better answer Prof Cho's "SoC advantage" framing (his 2026-03-26 feedback) and because the "empty quadrant" claim is more defensible to an expert audience — edge-viability is architectural-only on NetFPGA V2, whereas "inline ML at the NIC" is a structural fact about our data path. The old cloud/edge framing is retained in `part3_expert.md` §3.5 as a reference but superseded by this prompt.

Paste everything below the `---` line into a fresh Claude Design conversation. Target output: 5-stage animated HTML prototype with autoplay (~40-sec screen-recordable clip for Google Slides embedding).

**Google Slides integration path**:
- Recommended: click "Play" → screen-record the full autoplay (~40 sec) with OBS / Win+G / Loom → export MP4 → Google Slides `Insert > Video > Google Drive`.
- Alternative: screenshot each of the 5 stages at 1920×1080 → insert as 5 sequential slides with Fade transition.

---

Create an animated "differentiation diagram" for a graduate electrical-engineering class progress presentation. The diagram is a **2x2 matrix** that places our custom ML-based intrusion-detection network processor against existing solutions along two axes that matter architecturally: **where detection runs** (off-NIC vs inline at the NIC) and **what detection paradigm is used** (signature/pattern matching vs ML classification). The payoff: the top-right quadrant (inline + ML) is structurally novel among shipping products, and our SoC is the only *open, programmable* entry in it.

**Aspect ratio**: 16:9, target export resolution 1920×1080.

**Style**: technical educator / YouTube-channel clean — Branch Education, 3Blue1Brown, Ben Eater. Calm authoritative, not corporate-slick, not playful-cartoon. White background, strong color coding by category, clear sans-serif typography, arrow weights consistent. Visual style must match the companion C-ARCH diagram (same fonts, same color palette, same minimal-chrome feel).

**Layout**:
- Central 2x2 grid filling ~65-70% of the canvas, centered.
- Axis labels and subtitles positioned outside the grid.
- **X-axis (horizontal, below grid)**: left label = "Signature / Pattern matching", right label = "ML classification". Small subtitle below: *"known attacks only ↔ learned, including novel attacks"*
- **Y-axis (vertical, left of grid)**: bottom label = "Off-NIC (host CPU / host GPU / cloud)", top label = "Inline at NIC". Small subtitle (rotated): *"packet crosses PCIe ↔ packet stays on the NIC"*
- Four quadrants with small header badges anchored to the top of each quadrant:
  - Top-left: "Inline signature matching"
  - Top-right: "Inline ML classification" ← the novel quadrant
  - Bottom-left: "Off-NIC signature IDS"
  - Bottom-right: "Off-NIC ML IDS"

**Color system** (must match C-ARCH for visual continuity):
- Axis lines: stroke `#4a5568`, 1.5px
- Axis labels: text `#1a365d`, bold
- Quadrant grid backgrounds: pure white `#ffffff`
- Quadrant header badges: fill `#edf2f7`, stroke `#2b6cb0`, text `#1a365d`, small rounded rect
- Incumbent competitor boxes: fill `#f7fafc`, stroke `#4a5568`, text `#2d3748`, sans-serif
- Fortinet SP5 "proprietary ASIC" box: fill `#fef5e7`, stroke `#c05621` (GPU-orange from C-ARCH, signals "closed silicon we can't inspect"), small lock icon 🔒 in top-right corner of the box
- Prof Cho 2005 box: fill `#f7fafc`, stroke `#6b46c1` **dashed** (purple — matches the cross-row dashed arrows in C-ARCH), label in italic
- **Our SoC block**: fill `#c6f6d5` (green — matches the FIFO color in C-ARCH for visual continuity), stroke `#2f855a` 3px, faint outer glow on reveal
- Empty-quadrant spotlight (Stage 4): radial fade `#fed7aa` at ~30% opacity, fills the top-right quadrant background
- Background: pure white `#ffffff`

**Quadrant population** (aim for 2-3 named entries per filled quadrant — dense enough to be credible, sparse enough to read as a pitch not a literature review):

**Bottom-left — Off-NIC + Signature** (1 box):
- "Snort / Suricata" — subtitle *"software, x86 CPU"*

**Top-left — Inline + Signature** (3 boxes):
- "NVIDIA BlueField DPI" — subtitle *"DOCA regex"*
- "AMD Pensando" — subtitle *"P4 match-action"*
- "Prof Cho 2005" (purple dashed stroke, italic) — subtitle *"FPGA pattern co-processor (DAC '05) — influential prior work"*

**Bottom-right — Off-NIC + ML** (3 boxes):
- "CrowdStrike" — subtitle *"cloud ML"*
- "Zscaler" — subtitle *"cloud ML"*
- "Darktrace" — subtitle *"cloud NDR"*

**Top-right — Inline + ML** (2 boxes, appearing in Stages 4 and 5):
- "Fortinet SP5" (with 🔒 lock icon) — subtitle *"proprietary ASIC, closed"* (appears Stage 4)
- **"Our SoC"** (green, prominent, slightly larger than the other boxes) — subtitle *"open RTL, student-built, programmable"* (appears Stage 5)

**Prior-art arrow** (Stage 5 only):
- Thin dashed purple arrow from the `Prof Cho 2005` box (top-left) to `Our SoC` (top-right), arcing gently upward through the top edge of the grid
- Arrow label (italic, gray `#4a5568`, small): *"informed by"*

**DO NOT include**: specific throughput numbers (Gbps), latency microsecond values (save for Q&A), feature counts, company trademarks/logos (use text labels only), revenue or market cap numbers (that territory belongs to the investor video, not this expert clip), "BCAST" / "3.28x" cycle-count claims (those belong in C-BCAST, not C-DIFF), or claims that our solution is *faster* than commercial products (it is not — our claim is *structural novelty*, not raw speed).

**5 animation stages** with Previous/Next buttons, keyboard arrow shortcuts, stage counter top-right ("Stage N of 5"), and a **"Play" button** that auto-advances through all stages with ~8-sec pauses on each.

**Stage 1 — Axes appear**
Show: the two axes with their labels and subtitles, faint grid lines for the 2x2, empty quadrants. No competitors, no quadrant badges yet.
Subtitle at bottom: *"Two axes matter for network intrusion detection — what you detect, and where you detect it."*

**Stage 2 — Quadrant labels populate**
Add the four quadrant header badges sequentially, ~0.3 sec each.
Subtitle: *"Four combinations. Each has real tradeoffs."*

**Stage 3 — Three established quadrants fill**
Populate bottom-left, top-left, and bottom-right with their competitor boxes. Boxes fade in sequentially, ~0.3 sec each. The top-right remains empty.
Subtitle: *"Three quadrants have established players — software signature engines, NIC regex accelerators, and cloud-based ML."*

**Stage 4 — Top-right spotlight**
- A soft orange radial glow fills the top-right quadrant background.
- `Fortinet SP5` box fades in with its 🔒 lock icon and short subtle pulse.
Subtitle: *"Inline ML classification at the NIC is nearly empty. One shipping product — Fortinet's SP5 — sits here, but it's a closed proprietary ASIC."*

**Stage 5 — Our SoC lands + prior-art arrow**
- `Our SoC` (green box) fades in next to `Fortinet SP5`, slightly larger, with a brief glow pulse.
- Thin dashed purple arrow from `Prof Cho 2005` (top-left) arcs up and over to `Our SoC`, label "informed by" fading in along the arrow.
- The whole diagram softly glows once to signal completion.
Subtitle: *"Ours is the open, programmable entry in this quadrant — the same design philosophy Prof Cho's 2005 co-processor pioneered, now applied to ML classification."*

**Interactivity requirements**:
- **Play button**: auto-advances all 5 stages with 8-sec pauses, smooth transitions. When autoplay finishes, remains on Stage 5.
- **Previous/Next buttons**: manual stepping, each transition ~0.3 sec fade.
- Keyboard arrow keys as shortcuts (Left = Previous, Right = Next, Space = Play).
- Stage counter top-right: "Stage N of 5".
- No tooltips, no hover-only effects, no sounds.

**Typography**:
- Axis labels (end labels): sans-serif bold, 22pt
- Axis subtitles: sans-serif, 14pt, gray `#4a5568`
- Quadrant header badges: sans-serif bold, 16pt
- Competitor box labels: sans-serif, 16-18pt
- Competitor subtitles: sans-serif italic, 12-13pt, gray `#4a5568`
- Our SoC label: sans-serif bold, 19pt
- Our SoC subtitle: sans-serif italic, 13-14pt, color `#22543d` (dark green to match box)
- Bottom captions: sans-serif italic, 16pt, gray `#4a5568`
- Stage counter: sans-serif, 14pt, gray `#718096`

**Output**: single self-contained HTML artifact that I can open, click Play for the autoplay demo, screenshot each stage at 1920×1080 for Google Slides, or screen-record the full autoplay sequence for MP4 embedding.
