# Milestone 1 Business PPT Generation Prompt

**Instructions for LLM**: Create an animated PowerPoint presentation (or Google Slides) based on the content below. The audience is non-technical — imagine explaining this to grandparents. Use simple language, large text, icons/illustrations where possible, and minimal jargon. The presentation should be attention-grabbing and persuasive about why this project matters. Target: 8-10 slides, suitable for a 2-3 minute narrated video.

**Style**: Clean, modern, dark or navy background with white/accent text. Use simple icons or illustrations (shield, chip, network, lock). Avoid technical diagrams. Each slide should have minimal text — the speaker notes carry the detail.

---

## Slide 1: Title

**Title**: Smart Chip Stops Cyber Attacks

**Subtitle**: ML-Powered Intrusion Detection at the Network Edge

**Visual**: Simple icon of a shield with a chip inside it

**Speaker notes**: Today we are going to talk about a growing problem — cyberattacks — and a hardware solution that can detect them in real time, right where data enters the network.

---

## Slide 2: The Problem

**Title**: Cyberattacks Are Everywhere

**Bullet points** (appear one at a time):
- 2,200 cyberattacks happen every single day
- Average cost of a data breach: $4.5 million
- Attacks on hospitals, power grids, and smart homes are rising fast

**Visual**: Simple red warning icon or lock icon

**Speaker notes**: Cyberattacks are not just a tech company problem anymore. Hospitals, power plants, and even smart home devices get attacked daily. The average data breach costs over 4 million dollars, and attacks are growing every year.

---

## Slide 3: Why Current Solutions Fall Short

**Title**: Software Alone Is Not Fast Enough

**Bullet points** (appear one at a time):
- Traditional firewalls check a list of known threats — new attacks slip through
- Software-based detection runs on big servers — too slow for real-time
- IoT devices (cameras, sensors, thermostats) have no room for security software

**Visual**: Hourglass or slow/speed comparison icon

**Speaker notes**: Most security today is software running on large servers. It checks traffic against known attack patterns, but new attacks get through. And for small devices like smart cameras or sensors, there is simply no room to run security software. We need something faster and smaller.

---

## Slide 4: Our Solution

**Title**: A Tiny Chip That Thinks Like a Security Guard

**Bullet points** (appear one at a time):
- A custom chip that sits directly on the network cable
- Uses machine learning to recognize attack patterns — even new ones
- Inspects every packet in microseconds — 1000x faster than software

**Visual**: Simple chip icon with a magnifying glass or brain icon

**Speaker notes**: Our solution is a custom chip that sits right at the network entry point. Instead of checking a list, it uses a trained neural network to recognize suspicious patterns in network traffic. It processes each packet in about 20 microseconds — over a thousand times faster than a software solution running on a server.

---

## Slide 5: How It Works (Simple)

**Title**: Three Simple Steps

**Step 1**: Network traffic arrives at the chip

**Step 2**: The chip extracts 11 key statistics from each connection — things like how much data was sent, how many connections came from the same source, and whether the user is logged in

**Step 3**: A neural network on the chip scores the traffic as NORMAL or ATTACK in microseconds

**Visual**: Three-step horizontal flow diagram with simple icons (arrow in -> chip -> green check / red X)

**Speaker notes**: The process is straightforward. Traffic comes in. The chip pulls out 11 statistics that are good indicators of attacks, things like unusual connection patterns or suspiciously low data transfer. Then a small neural network scores it. The whole thing takes microseconds — fast enough to check every single packet without slowing down the network.

---

## Slide 6: Real Results

**Title**: It Works — On Real Hardware

**Key numbers** (large, bold):
- 75% accuracy detecting real attacks from the NSL-KDD benchmark
- 5-7 ms per classification (limited by software interface, not the chip)
- 20 microseconds of actual chip computation time
- 346 learned parameters — fits on a tiny chip

**Visual**: Checkmark icon, green accent color for numbers

**Speaker notes**: We built this on a real FPGA — not a simulation. Using the industry-standard NSL-KDD intrusion detection dataset, our system correctly classifies 75% of network connections as normal or attack. The chip itself computes in 20 microseconds. The 5 millisecond number you see in our demo is the overhead of talking to the chip through the PCI bus — in a production design, that overhead would disappear. And the entire neural network has only 346 parameters, small enough for even the tiniest chip.

---

## Slide 7: Why This Matters

**Title**: Security Where It Is Needed Most

**Bullet points** (appear one at a time):
- Protects devices that cannot protect themselves — IoT sensors, medical devices, smart home gadgets
- Works at the network edge — no cloud server needed
- Low cost — could be built into a $5 network chip
- Fortinet (the market leader) sells firewall boxes for $10,000+ — they do not serve the small device market

**Visual**: Icons for IoT devices (camera, thermostat, heart monitor)

**Speaker notes**: The big insight is where this technology goes. Companies like Fortinet sell enterprise firewalls for tens of thousands of dollars. They do not serve the billions of small devices being connected every year — security cameras, medical monitors, factory sensors. Our approach puts intelligence directly into the network chip, at a cost that could be under 5 dollars. That opens a market that the incumbents are not addressing.

---

## Slide 8: The Market Opportunity

**Title**: 30 Billion IoT Devices Need Protection

**Key numbers**:
- 30B+ IoT devices connected by 2030
- IoT security market: $40B by 2028
- Edge AI chip market growing 25% per year

**Visual**: Growth chart going up (simple, not detailed)

**Speaker notes**: By 2030, there will be over 30 billion IoT devices connected to the internet, and most of them have minimal or no security. The IoT security market is projected to reach 40 billion dollars by 2028. Our technology targets exactly this gap — bringing intelligent security to the network edge at a price point that works for mass deployment.

---

## Slide 9: What Is Next

**Title**: Milestone 1 Complete — More to Come

**Completed** (with checkmarks):
- Neural network running on custom GPU hardware
- End-to-end packet processing pipeline
- Batch testing with real NSL-KDD attack data

**Next steps** (with arrows):
- Improve accuracy (larger network, more features)
- Measure hardware performance counters
- Optimize chip utilization

**Visual**: Roadmap style, left-to-right timeline

**Speaker notes**: For milestone 1, we have the full pipeline working end to end — real network packets come in, the chip classifies them, and results are reported. Next, we plan to improve the accuracy by exploring larger networks and more input features, add hardware-level performance measurement, and optimize the chip design to use less area.

---

## Slide 10: Thank You

**Title**: Smart Security on a Chip

**Subtitle**: Team 6 — EE533 Final Project

**Bottom text**: Built on the NetFPGA platform with custom ARM CPU + GPU coprocessor

**Visual**: Same shield+chip icon from slide 1

**Speaker notes**: Thank you for watching. We are excited about bringing machine learning to network security hardware, and we look forward to showing more in the next milestone.

---

## Design Notes for PPT Generator

- Animations: Bullet points should appear one at a time (click or timed). Slides should have simple fade transitions.
- Color scheme: Navy/dark blue background (#1a1a2e or #16213e), white text, accent color teal (#0f969c) or green (#6bcb77) for positive numbers, red (#ff6b6b) for threat/attack mentions.
- Fonts: Sans-serif (Calibri, Arial, or similar). Title: 36-44pt bold. Body: 24-28pt.
- Keep text minimal on each slide — the speaker notes are for narration, not for showing on screen.
- If the tool supports it, add simple shape animations (icons sliding in, numbers counting up).
