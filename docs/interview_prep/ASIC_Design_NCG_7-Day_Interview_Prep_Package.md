# NVIDIA ASIC Design Engineer — New College Grad 2026

## 7-Day Interview Preparation Package

**Target role:** ASIC Design Engineer — New College Grad 2026, Santa Clara  
**Requisition:** JR2020309  
**Application resume:** Zilin_Shao_Resume_ASIC_Design_RTL_Microarchitecture.tex  
**Prepared:** 2026-07-14  
**Default time budget:** 6 focused hours per day, plus an optional 1–2 hour stretch block

---

# 中文执行摘要

## 一句话结论

这是一份**可信、匹配度高，但会被追问“是否真的 timing-clean、是否真的理解自己写过的 RTL”**的应届申请。你的最佳打法不是继续堆新项目，也不是在七天内大规模刷 LeetCode；而是把 SmartNIC、U45N 和基础数字设计串成一条清晰证据链：

> 我能从规格出发做微架构和可综合 RTL，能用性能/面积数据解释取舍，也经历过实现、时序和板级调试；我清楚现有项目没有证明什么，并知道怎样把它推进到更接近 ASIC signoff 的标准。

## 三档优先级

### P0 — 保底，任何一项答错都可能直接出局

- 简历逐条事实边界，尤其是四组 timing 结果：
  - NetFPGA final-demo Fix B snapshot：`WNS = -4.394 ns`，817 个 failing core endpoints，没有 timing close；
  - U45N baseline OpenNIC：`WNS = -0.114 ns`、`TNS = -19.232 ns`，已加载并做过硬件 bring-up，但不 timing-clean；
  - U45N transparent TX-path pass-through build：`WNS = +0.003 ns`、`TNS = 0`，仅生成、没有刷写或流量验证；
  - U45N 可观测 AXI-Lite image：`WNS = -0.086 ns`、`TNS = -1.248 ns`、49 个 failing endpoints，已刷写但只验证了一个确定性 BAR2 test vector，最差路径位于上游 QDMA H2C aligner。
- blocking/nonblocking、组合逻辑 latch、setup/hold、WNS/TNS、同步 FIFO full/empty、ready/valid、单比特 CDC。
- 能现场完成：小 FSM、2-bit multiplier、sticky register、palindrome/数组最大值、简单 Python 文件解析。
- SmartNIC 30 秒版和 2 分钟版；U45N 90 秒版；每个数字都能说明测量边界。

### P1 — 正常技术轮应有的水平

- SmartNIC 做到 10–15 分钟深挖：CPU/GPU pipeline、thread scheduling、DMA/FIFO、BCAST 数据布局、3.28× 加速如何拆解、hazard、验证和未解决问题。
- 能白板设计并写出：参数化同步 FIFO、round-robin arbiter、ready/valid stage；能解释 async FIFO 而不必死背整份代码。
- 能讲清 STA 修复顺序、CDC 多比特方案、reset deassertion、AXI-Lite 独立通道、cache tag/index/offset、pipeline hazards。
- 有三个真实 debug 故事：症状、分层定位、证据、根因、修复、预防。

### P2 — 形成强竞争力

- 面对新规格，能主动澄清 interface、throughput、latency、burst、backpressure、ordering、reset 和 error behavior。
- 能从零给出 GPU work scheduler、DMA engine 或 interrupt controller 的状态、寄存器、invariant、assertion、验证计划和 PPA 取舍。
- 能诚实地把 FPGA 经验迁移到 ASIC：lint/CDC/RDC、约束、综合、STA、功耗、DFT、形式验证、LEC、物理反馈和 signoff。
- 能解释“如果今天重做项目，我会改什么”，而不是为已知限制辩解。

## 七天路线图

| 天 | 主线 | 当天必须产出 |
|---|---|---|
| Day 1 | 简历事实与首轮保底 | 一页 truth sheet；英文自我介绍；2-bit multiplier、FSM、latch、palindrome |
| Day 2 | SmartNIC 微架构 | 三分钟架构图；CPU/GPU/BCAST 深挖；同步 FIFO；一次 10 分钟英文项目 mock |
| Day 3 | STA / CDC / U45N | 四组 timing 结果无误；ready/valid；timing-report Python parser |
| Day 4 | Pipeline / cache / arbiter | cache 地址拆分；round-robin RTL；ring buffer；架构白板 |
| Day 5 | AXI / DMA / interrupt / debug | AXI-Lite 规则；DMA/interrupt 设计；三段 STAR debug 故事 |
| Day 6 | Verification / PPA / ASIC flow | assertions、scoreboard、coverage、PPA 修复树；完整技术 mock #1 |
| Day 7 | 转化与补洞 | 完整技术 mock #2；只修高频错误；最终口袋清单 |

正文保留英文答题脚本，是因为实际面试大概率需要直接用英文讲项目、澄清规格和解释 RTL。中文部分用于制定策略；英文部分用于逐句出声练习。

## 快速导航

- [七天详细日程](#5-seven-day-schedule)
- [项目讲解与简历深挖](#6-project-and-resume-package)
- [知识卡包](#7-knowledge-card-pack)
- [现场手撕与设计题](#8-live-coding-and-design-drill-pack)
- [P0 最小参考实现](#p0-self-check-reference-implementations)
- [Debug 框架与场景](#9-debug-framework-and-scenarios)
- [Mock interview 与评分](#11-mock-interview-scripts-and-scoring)
- [最终一页清单](#14-final-one-page-checklist)
- [检索来源](#15-primary-references)

---

# 0. How to use this package

This is a seven-day interview sprint, not a complete ASIC curriculum.

Use three priorities:

- **P0 — Must not fail:** Facts and fundamentals that can eliminate a candidate in one answer.
- **P1 — Interview-ready:** The depth needed to handle a normal technical screen and most panel rounds.
- **P2 — Differentiation:** New-spec design, PPA reasoning, verification planning, and team-IP questions that can turn a qualified candidate into a strong candidate.

For every day:

1. Speak project answers aloud in English.
2. Solve coding tasks in a plain editor or on paper, without AI or autocomplete.
3. Test the result and explain the hardware or complexity it implies.
4. Record mistakes in one error log and repair those mistakes the next morning.

If only three hours are available on a day, complete only the P0 blocks. Do not cut project truth-checking, FIFO/FSM/STA, or live RTL practice.

---

# 1. Bottom-line assessment

## 1.1 Fit

This is a credible, high-upside application. The strongest fit is not the IDS model itself; it is the combination of:

- a custom 5-stage, 4-thread CPU;
- a 6-stage, 4-lane BF16 SIMD datapath;
- DMA and packet-buffer control;
- a cross-lane BCAST ISA/RTL optimization with measured cycle reduction;
- SystemVerilog AXI-Lite work on U45N/OpenNIC;
- synthesis, implementation, post-route timing analysis, and real-board debug.

For a new-college-graduate role, that is meaningful evidence of microarchitecture and RTL ownership.

## 1.2 Main risks

The interview outcome is most likely to turn on five risks:

1. **Timing-clean wording:** the archived NetFPGA final-demo Fix B snapshot did not close its 8 ns core constraint.
2. **ASIC versus FPGA scope:** hands-on implementation is FPGA-based, not production ASIC tapeout/signoff.
3. **Verification depth:** directed/module tests and board validation are real, but there is no full UVM, coverage, formal, or signoff-quality regression flow.
4. **Breadth of resume claims:** “architected and implemented” invites register-, state-, and timing-level questions across CPU, GPU, DMA, and FIFO.
5. **SystemVerilog/CDC depth:** the resume lists SystemVerilog and synchronization-adjacent work, while the strongest full project is primarily Verilog-2001.

The seven-day goal is therefore:

> Defend every resume claim two levels deep, become mechanically reliable on RTL/STA/CDC fundamentals, and show that you can turn a new block specification into a clean microarchitecture and verification plan.

## 1.3 Recommended allocation

| Area | Core time | Why |
|---|---:|---|
| Resume and project deep dive | 35% | NVIDIA reports repeatedly describe resume/project probing |
| RTL, digital design, STA, CDC | 30% | Most consistent reported question cluster |
| Live RTL plus C++/Python | 20% | Official process allows coding exercises; candidate reports include both RTL and software |
| New-IP whiteboarding and PPA | 10% | Directly tied to scheduler, DMA, interrupt, and timing-clean JD language |
| Behavioral and questions for team | 5% | Needed for manager and cross-functional rounds |

---

# 2. What the research actually indicates

## 2.1 Official process

NVIDIA says full-time candidates normally begin with phone interviews and then move to virtual or in-person interviews. Individual interviews are usually 30–60 minutes. Technical candidates may receive a coding exercise through HackerRank, a whiteboard, or a provided laptop. The company says selected candidates ideally hear from recruiting within a couple of weeks, while the overall process normally takes a matter of weeks after the first interview.

Source: [NVIDIA — How We Hire](https://www.nvidia.com/en-us/about-nvidia/careers/how-we-hire/)

The exact number and order of rounds are team-dependent. Treat all forum reports as directional evidence, not a promised process.

## 2.2 High-relevance NVIDIA reports

| Report | Location / date | Reported content | Weight |
|---|---|---|---|
| NVIDIA New Grad ASIC Design | Interviewed Jun. 2025 | Project deep dive on a boot/fuse controller and its SoC role; build XNOR from 2:1 muxes; design a sticky register | **Very high; exact NCG title** |
| NVIDIA New Grad ASIC Design | San Jose, Sep. 2023 | 45-minute round: resume, STA, and CDC | **Very high; exact NCG and Bay Area** |
| NVIDIA New Grad ASIC Design | 2022 | Two rounds: wire/reg, if/case, resume project, small design approach; then specification→FSM→Verilog | **High; exact NCG, older** |
| NVIDIA ASIC Design Engineer | California, interviewed Sep. 2024 | Digital logic, computer architecture, STA, resume projects, FIFO, setup/hold, FSM on whiteboard | Very high |
| NVIDIA ASIC Design Engineer | Santa Clara, interviewed Mar. 2024 | 2-bit single-cycle multiplier, FSM for runs of ones, latch inference, palindrome | Very high |
| NVIDIA ASIC Design Engineer | Santa Clara, interviewed Sep. 2024 | Cache, coherence, CPU design, pipelining, interconnect | Very high |
| NVIDIA ASIC Engineer | Santa Clara, interviewed Aug. 2025 | Two screens then five-round panel; RTL basics, FIFO/depth, packed/unpacked arrays, Python/file/CSV parsing, retiming, debug, multiplier alternatives, data-loss diagnosis | **High as an upper-bound panel; level not disclosed** |
| NVIDIA ASIC Design Intern | Santa Clara, report Mar. 2026 | RTL, FSM, theoretical architecture; modulo-3 FSM | High; same function and location, intern level |
| NVIDIA ASIC Design Intern | Santa Clara, interviewed Jan. 2025 | Resume projects, C++, Verilog, technical plus behavioral | High |
| NVIDIA ASIC Design Engineer | Santa Clara, 2020 | CDC, clock mux/divider, FIFO depth, timing, FSM, max-in-array, palindrome | Medium-high; older but unusually specific |
| NVIDIA ASIC Design Engineer | Sunnyvale, 2020 | Walk through the complete design process for an arbiter; SystemVerilog coding | Medium-high |
| NVIDIA ASIC Design Engineer | Boston, 2021 | FSM/gates, roughly a dozen rapid questions, approach emphasized | Medium |
| NVIDIA ASIC Design Intern | Santa Clara, 2013 | Verilog, caches, pipelines, forwarding, branch prediction, FIFO, multithreading, setup/hold/skew/jitter | Pattern evidence only; old |

Primary collection: [Glassdoor — NVIDIA New Grad ASIC Design Engineer interviews](https://www.glassdoor.com/Interview/NVIDIA-New-Grad-ASIC-Design-Engineer-Interview-Questions-EI_IE7633.0%2C6_KO7%2C36.htm), [Glassdoor — NVIDIA ASIC Design Engineer interviews](https://www.glassdoor.com/Interview/NVIDIA-ASIC-Design-Engineer-Interview-Questions-EI_IE7633.0%2C6_KO7%2C27.htm), [Glassdoor — NVIDIA ASIC Engineer interviews](https://www.glassdoor.com/Interview/NVIDIA-ASIC-Engineer-Interview-Questions-EI_IE7633.0%2C6_KO7%2C20.htm), and [Glassdoor — NVIDIA ASIC Design Intern interviews](https://www.glassdoor.com/Interview/NVIDIA-ASIC-Design-Intern-Interview-Questions-EI_IE7633.0%2C6_KO7%2C25.htm).

## 2.3 Chinese-language North America reports

Publicly indexed Chinese sources are much thinner than English sources, and many 一亩三分地 bodies are login- or credit-gated. The research therefore separates publicly verifiable content from hidden content instead of reconstructing missing questions.

### Highest-value Chinese report: NVIDIA ASIC Verification → GPU Design Efficiency

A North America new-graduate candidate reported receiving an offer after an unusually long process: two early phone interviews, a Verification panel, redirection to Design Efficiency, then another phone interview and a four-round panel. Although the process began in verification, the later GPU Design Efficiency interviews centered on power, performance, and area, making it highly relevant to this JD.

The accessible full-text mirror and indexed original describe:

- **Software:** pass-by-value versus reference and two `swap` implementations; recursive/iterative Fibonacci; third maximum; merge two sorted arrays in-place; C/C++ memory, pointers, heap/stack; linked-list reversal; bit reversal; missing cards; Python regex/file replacement.
- **RTL/design:** blocking versus nonblocking and inferred hardware; palindrome and sequence detectors; Moore/Mealy and overlap; Fibonacci hardware; async FIFO interface/depth/pointers/full/empty/RTL; simultaneous read/write policy; FIFO verification; round-robin arbiter plus tests; missing-card streaming hardware.
- **Timing/CDC/PPA:** setup/hold calculation from a timing diagram; pipeline rebalancing; single-bit versus multi-bit CDC; clock-gating/latch behavior; ICG placement and setup risk; FIFO area optimization; SRAM/control physical separation; PnR congestion.
- **Architecture:** five-stage pipeline and hazards; cache organizations/address fields/replacement/LRU; MOESI; Tomasulo and load/store buffers; atomic operations and LL/SC; GPU/CUDA discussion.

Sources: [一亩三分地原帖](https://www.1point3acres.com/bbs/thread-739185-1-1.html) and [third-party full-text mirror](https://www.scribd.com/document/1030069501/%E9%AA%8C%E8%AF%81%E8%AE%B0%E5%BD%95). The mirror matches the indexed title/author/time signals but remains a re-upload, so it is used as interview-pattern evidence, not as an official NVIDIA question bank.

### Other NVIDIA reports

- A successful 2024 Santa Clara ASIC Design summer-intern report describes two technical rounds. The candidate had FPGA projects and a SoC-design internship. Its detailed question body is hidden; use it only to support the process and the value of project-based VLSI/FPGA, bus/IP, C/C++, and Python/Tcl preparation.  
  [NVIDIA 英伟达 24 Summer ASIC Design 面经](https://www.1point3acres.com/bbs/thread-1047704-1-1.html)
- A 2019 NVIDIA ASIC phone report publicly shows two 45-minute rounds: the hiring manager first probed several resume projects, then an engineer conducted the second round. The detailed second-round questions are hidden.  
  [NVIDIA ASIC 电面](https://www.1point3acres.com/bbs/thread-552586-1-1.html)
- A 2024 new-graduate pass report shows a process spanning roughly October to January, with two screens and two team rounds; a reply identifies the role as ASIC Design Engineer. The knowledge-point body is hidden.  
  [NVIDIA 硬件岗过经](https://www.1point3acres.com/bbs/thread-1039490-1-1.html)
- A North America NVIDIA hardware-DV report lists UVM, SystemVerilog, Verilog, C++, and CPU architecture. Because it is DV rather than design, use it only to justify verification and language basics.  
  [NVIDIA Hardware Design Verification 面经](https://www.1point3acres.com/bbs/thread-666739-1-1.html)
- A current Reddit discussion around an NVIDIA GPU ASIC Design intern interview emphasizes architecture, Verilog/SystemVerilog, digital/VLSI fundamentals, basic C/C++, STA, CDC, and practical design reasoning. It is preparation advice, not a completed debrief.  
  [NVIDIA ASIC Design Intern discussion](https://www.reddit.com/r/ECE/comments/1oelvro/nvidia_asic_design_intern_interview/)

### North America comparable-role Chinese reports

- **Google TPU RTL:** design a transmitter-to-receiver bridge with non-integer width/rate relationships; clarify clocks/reset/power; design an arbiter; parse a tree from a file and compute leaf-to-root distances. This is strong evidence for asking interface, throughput, buffering, and backpressure questions before coding.  
  [Google TPU phone and onsite](https://www.1point3acres.com/bbs/thread-560112-1-1.html)
- **Meta ASIC E5:** C++ fundamentals and a cache class in screening; cache design/optimization, pipeline trade-offs, and performance discussion onsite. This is an experienced-hire upper bound, not an NCG baseline.  
  [Meta ASIC E5 面试](https://www.1point3acres.com/bbs/thread-1097113-1-1.html)
- **Meta ASIC Design:** the recruiter described online coding, but the actual interview used paper block diagrams and handwritten code with incomplete specifications. The lesson is to clarify constraints before designing.  
  [Meta ASIC Design 挂经](https://www.1point3acres.com/bbs/thread-1017894-1-1.html)
- **Qualcomm ASIC Design:** producer at 5 Hz, consumer at 1 Hz, 50 continuous write cycles; calculate required FIFO depth. This directly motivates burst/rate-based FIFO sizing drills.  
  [Qualcomm ASIC Design 电面总结](https://www.1point3acres.com/bbs/thread-444445-1-1.html)
- A cross-company ASIC designer summary independently repeats minimum clock period/hold analysis, sequence detector, round-robin arbiter, and traffic-light FSM. The companies and locations are undisclosed, so it is low-weight corroboration only.  
  [ASIC Designer 高频题汇总](https://www.1point3acres.com/bbs/thread-743029-1-1.html)

## 2.4 Comparable North America roles

Comparable Apple and Qualcomm reports reinforce the same pattern:

- Apple RTL: synchronous FIFO depth, fixed/round-robin/weighted arbitration, cache experience, and optimizing a path for timing.
- Apple ASIC: CDC, metastability, sequence detectors, clock/power gating, timing constraints, AXI, Verilog, and resume projects.
- Apple GPU Design: block-level design from an I/O specification, C programming, Verilog coding, arbiter RTL, and timing optimization.
- Qualcomm ASIC Design in Canada: edge-detection logic, FSM, self-checking testbenches; other reports include counters, mux logic, CDC/lint violations, and setup/hold.

Sources: [Apple RTL Design interviews](https://www.glassdoor.com/Interview/Apple-Rtl-Design-Engineer-Interview-Questions-EI_IE1138.0%2C5_KO6%2C25.htm), [Apple ASIC Design interviews](https://www.glassdoor.com/Interview/Apple-ASIC-Design-Engineer-Interview-Questions-EI_IE1138.0%2C5_KO6%2C26.htm), [Apple GPU Design interviews](https://www.glassdoor.com/Interview/Apple-GPU-Design-Engineer-Interview-Questions-EI_IE1138.0%2C5_KO6%2C25.htm), and [Qualcomm ASIC Design interviews](https://www.glassdoor.com/Interview/Qualcomm-ASIC-Design-Engineer-Interview-Questions-EI_IE640.0%2C8_KO9%2C29.htm).

## 2.5 Evidence-weighted topic priority

| Likelihood / value | Topics |
|---|---|
| **Very high** | Resume/project depth; synthesizable RTL; FSM; FIFO; latch/sticky-register behavior; setup/hold/slack; basic timing fixes |
| **High** | Computer architecture, pipeline hazards, cache organization, interconnect; CDC/reset; basic C/C++ problem solving |
| **Medium-high** | Mux/logic construction, arbiter/scheduler, ready/valid, SystemVerilog semantics, scripting/file parsing, verification plan, synthesis/PPA trade-offs |
| **Medium, JD-driven** | AXI-Lite, DMA, interrupt controller, time/counter distribution, design-for-debug |
| **Possible but not primary** | Hard LeetCode, transistor-level CMOS/SRAM, deep coherence, UVM internals |

One NVIDIA intern report did include medium and hard algorithm questions. That justifies a small software-coding hedge; it does not justify replacing RTL/STA preparation with a LeetCode sprint.

---

# 3. JD-to-resume map

| JD need | Best evidence | Current level | What must be ready |
|---|---|---:|---|
| Microarchitecture and RTL | CPU, GPU, DMA, FIFO, BCAST | Strong | Draw registers/stages/control, alternatives, and corner cases |
| Performance-efficient design | 2402→732 cycles; 211→108 instructions | Strong | Baseline, measurement boundary, cause decomposition, correctness |
| Area-efficient design | INT16 scalarization removed 3 multipliers and about 275 LUTs | Medium-strong | Separate early +65 LUT BCAST cost from later scalarization; 383→128 is a DMEM image/working-set reduction, not physical BRAM shrinkage |
| Power-efficient design | Coursework; no reliable measured result | Weak | Explain general methods; do not use weak power projections |
| Fully verified delivery | Directed tests, frame checks, board tests | Medium | State limits; propose assertions, coverage, formal, regressions |
| Synthesis/timing clean | One unflashed U45N pass-through build closed; loaded/custom images did not | Weak-medium | Know all four timing results and never imply signoff |
| Scheduling/arbitration | Four-thread round robin | Medium-strong | Fairness, stalls, request changes, rotating priority |
| DMA/controller IP | Copy FSM and control/status path | Strong | Register/FSM/latency/backpressure/error behavior |
| Synchronization | Limited direct evidence | Weak | Two-flop, pulse, handshake, async FIFO, RDC/reset |
| Bus/interconnect | AXI-Lite/AXI-Stream and register path | Medium-strong | Independent channels, backpressure, WSTRB, ordering |
| Cache/interconnect networks | Coursework-level; no cache project | Weak-medium | First-level architecture only; do not claim hands-on cache design |
| Design for post-silicon debug | Cycle/status counters, signature/version/MMIO | Medium-strong | Observability, sticky errors, timeout, trace/perf counters |
| C/C++/Python | ATPG and project tooling | Strong | One C++ and one Python live exercise without library dependence |

## Recommended project order

1. **FPGA SmartNIC SoC — 60–70% of project discussion.** Lead with architecture, BCAST, timing and verification. Do not lead with ML accuracy.
2. **U45N/OpenNIC — 20–30%.** Lead with the SystemVerilog AXI-Lite block, post-route timing, MMIO observability, and layered debug.
3. **ATPG — roughly 10%.** Use as evidence for C++, graph/bit-parallel reasoning, and verification thinking.

---

# 4. Priority ladder and exit gates

| Capability | P0 — Must not fail | P1 — Interview-ready | P2 — Strong differentiation |
|---|---|---|---|
| Project | 30 sec + 2 min; every number and limitation correct | 10–15 min; answer first-order design/timing questions | Handle hostile follow-ups, redesign, ASIC migration |
| Fundamentals | 27 core cards at 80% cold recall | All P1 cards; explain mechanisms and failure modes | Cross-topic PPA and protocol trade-offs |
| RTL | FSM, multiplier, sync FIFO | Arbiter, ready/valid/skid, AXI-Lite | Scheduler, interrupt, DMA redesign |
| Software | Palindrome, max/second max, bit operations | Ring buffer and timing-log parser | Reference model or scheduler simulator |
| Debug | Structured hypothesis/test method | Three real stories plus new waveform cases | Add observability and prevention methodology |
| English | Two-minute project without notes | Recover cleanly after interruptions | Lead a 15-minute design discussion |

### P0 pass gate

- No incorrect answer on blocking/nonblocking, latch, setup/hold, FIFO full/empty, ready/valid, or two-flop synchronizer scope.
- Can state the four timing outcomes exactly.
- Can draw the SmartNIC architecture in three minutes.
- Can solve one FSM, one simple software question, and explain a sync FIFO.
- Any resume bullet can be questioned twice without a factual contradiction.

### P1 pass gate

- Complete a representative RTL block in 45 minutes, including tests and corner cases.
- Give a 10–15 minute SmartNIC deep dive with no truth-boundary errors.
- Explain CDC/async FIFO, AXI-Lite, ASIC front-end flow, cache basics, and five PPA trade-offs.
- Deliver three structured debug stories.

### P2 pass gate

- Given a new scheduler/DMA/interrupt specification, produce interfaces, state, datapath, invariants, assertions, and a verification plan.
- Complete two mock interviews without a red-line error.

---

# 5. Seven-day schedule

## Day 1 — Resume truth and first-screen survival

**Outcome:** No resume claim can surprise you.

| Block | Time | Priority | Deliverable |
|---|---:|---:|---|
| Build one-page truth sheet | 90 min | P0 | Claim, exact meaning, evidence, limitation, likely follow-up for every bullet |
| Targeted self-intro and project pitches | 60 min | P0 | 45-sec self-intro; 30-sec and 2-min SmartNIC; 90-sec U45N; 60-sec ATPG |
| Digital/RTL fundamentals cards 1–12 | 75 min | P0 | 80% cold recall; answer aloud |
| Exact reported drills | 90 min | P0 | 2-bit multiplier, runs-of-ones FSM, latch bug, palindrome |
| Timing facts and ASIC/FPGA boundary | 45 min | P0 | Rehearse the timing-clean answer below |
| Record one mock | 30 min | P0 | Listen once; log ambiguity and overclaiming |

**Optional P2:** Write “If I rebuilt this project today” with five specific fixes.

## Day 2 — SmartNIC microarchitecture

**Outcome:** The main project can survive a 15-minute deep dive.

| Block | Time | Priority | Deliverable |
|---|---:|---:|---|
| Draw architecture from memory | 45 min | P0 | Packet→FIFO→DMA→GPU→DMA→CPU/drain, with control/status |
| CPU deep dive | 60 min | P1 | Pipeline chart, thread rotation, per-thread state, hazard reasoning |
| GPU/BCAST deep dive | 90 min | P1 | ISA semantics, pipeline, hazard handling, lane mapping, 3.28× decomposition |
| RTL coding | 90 min | P0/P1 | Modulo-3 FSM and parameterized sync FIFO |
| C++ coding | 45 min | P0 | Palindrome plus max/second max; tests and complexity |
| English project mock | 30 min | P1 | 10-minute explanation plus 10 minutes of interruptions |

**Optional P2:** Analyze scaling from 4 to 8 lanes across bandwidth, RF/BRAM ports, fanout, area, timing, and power.

## Day 3 — STA, CDC, reset, and U45N

**Outcome:** Timing questions become a strength rather than an exposure.

| Block | Time | Priority | Deliverable |
|---|---:|---:|---|
| STA cards | 75 min | P0 | Setup/hold, WNS/TNS, skew, uncertainty, constraints, fixes |
| CDC/reset cards | 60 min | P0/P1 | Single-bit, pulse, multi-bit, handshake, async FIFO, reset deassertion |
| U45N story | 75 min | P0/P1 | Exact authorship, image states, AXI-Lite test, four timing results |
| Timing/debug case | 45 min | P1 | Explain BCAST register insertion and what it did not prove |
| RTL coding | 75 min | P1 | Ready/valid stage or skid buffer |
| Python coding | 45 min | P0/P1 | Parse a timing report and output worst paths plus WNS/TNS |
| Rapid oral quiz | 15 min | P0 | 20 questions, 20 seconds each |

**Optional P2:** Add two SVA properties each for FIFO, ready/valid, and AXI-Lite response stability.

## Day 4 — Computer architecture and arbitration

**Outcome:** Handle the repeated NVIDIA cache/pipeline/interconnect cluster.

| Block | Time | Priority | Deliverable |
|---|---:|---:|---|
| Pipeline and cache cards | 75 min | P0/P1 | Hazards, CPI, branch penalty, direct/set/fully associative cache |
| Cache-address exercises | 45 min | P1 | Tag/index/offset for three organizations |
| Interconnect and arbitration | 60 min | P1 | Fixed priority, round robin, weighted, fairness, starvation |
| RTL coding | 90 min | P1 | Parameterized round-robin arbiter with stable grant policy |
| C++ coding | 60 min | P1 | Fixed-capacity ring buffer and bit-field helpers |
| Whiteboard | 30 min | P2 | Design a small GPU work scheduler from a written spec |

**Optional P2:** First-level coherence: why private caches need a protocol; modified/shared/invalid states; snoop versus directory trade-off.

## Day 5 — AXI, DMA, interrupt, and debug-friendly design

**Outcome:** Translate the JD’s named IP blocks into interview-ready designs.

| Block | Time | Priority | Deliverable |
|---|---:|---:|---|
| AXI-Lite | 60 min | P1 | Five channels, independent AW/W, WSTRB, response stability, no bursts |
| DMA | 60 min | P1 | Registers/descriptors, FSM, burst/backpressure, completion/error |
| Interrupt/time distribution | 45 min | P1/P2 | pending/mask/clear/priority; coherent time snapshot |
| RTL design | 90 min | P1/P2 | Four-source interrupt controller or small DMA engine |
| Python reference model | 45 min | P1 | Round-robin scheduler or MMIO-register reference model |
| U45N attack mock | 45 min | P1 | AXI-Lite, ownership, timing, and what was not verified |
| Behavioral | 15 min | P0 | One collaboration and one failure story |

**Optional P2:** Add sticky error bits, timeout, performance counters, and interrupt behavior to the DMA design.

## Day 6 — Verification, PPA, and full panel simulation

**Outcome:** Demonstrate production-minded thinking despite limited signoff ownership.

| Block | Time | Priority | Deliverable |
|---|---:|---:|---|
| ASIC flow and collaboration | 60 min | P1 | Spec→microarchitecture→RTL→lint/CDC→DV→synthesis/STA→backend→signoff |
| Verification plan | 60 min | P1 | Directed, random, assertions, scoreboard, coverage, formal, regressions |
| PPA trade-offs | 60 min | P1/P2 | Pipeline, lanes, ports, forwarding, clock gating, operand isolation |
| Timed RTL mock | 60 min | P1 | One unseen FIFO/arbiter/ready-valid variant |
| Project attack mock | 45 min | P1 | 15 minutes talk + 30 minutes probing |
| Full 60-minute mock | 60 min | P2 | Mixed project, fundamentals, coding, behavioral |
| Repair log | 15 min | P0 | Rank every miss as fact, concept, coding, or communication |

## Day 7 — Conversion day

**Outcome:** Stable performance, not more content.

| Block | Time | Priority | Deliverable |
|---|---:|---:|---|
| Cold P0 exam | 45 min | P0 | 27 cards, four timing outcomes, architecture drawing |
| Mock 1: technical screen | 45 min | P1 | Score at least 80/100 and no red line |
| Repair | 60 min | P0/P1 | Re-solve only failed concepts/tasks |
| Mock 2: panel | 60 min | P2 | New block spec plus project attack |
| Manager/behavioral | 45 min | P0/P1 | Six STAR stories; why NVIDIA; why this role |
| Team questions | 20 min | P0 | Prepare five questions, choose two per interviewer |
| Final refresh pack | 40 min | P0 | One page only; no new study afterward |

Stop heavy studying after the final refresh. Sleep is worth more than a last new topic.

---

# 6. Project and resume package

## 6.1 Targeted 45-second introduction

> I recently completed my master’s in Computer Engineering at USC, where my strongest hands-on work has been RTL microarchitecture and FPGA implementation. I built a SmartNIC-style network processor that integrates a four-thread pipelined CPU, a four-lane BF16 SIMD engine, DMA, and packet buffering. I then added a cross-lane BCAST instruction and changed the RTL, assembler, data layout, and kernel, reducing hardware-measured GPU kernel execution from 2,402 to 732 cycles. More recently, I implemented and brought up a SystemVerilog AXI-Lite block on an AMD U45N through OpenNIC and used post-route timing and board-level evidence to debug the system. I’m now looking to bring that design and debug foundation into production ASIC RTL and grow deeper in timing, PPA, and cross-functional chip delivery.

## 6.2 SmartNIC 30-second version

> I built a heterogeneous FPGA network processor with a four-thread, five-stage custom CPU, a six-stage four-lane BF16 SIMD engine, a DMA copy engine, and a single-packet 256-by-72-bit mode-switchable dual-port BRAM buffer/FIFO. My main optimization was a cross-lane BCAST instruction spanning ISA, RTL, assembler, memory layout, and a hand-written inference kernel. For the same functional IDS inference/model and input, with an intentionally different instruction stream and repacked DMEM layout, it reduced execution from 2,402 to 732 measured GPU cycles. Repeated board runs produced bit-identical outputs. The project also taught me an important implementation lesson: board functionality is not the same as timing closure, and the complete design still had failing core paths.

## 6.3 SmartNIC two-minute structure

Use this order:

1. **Problem:** execute a compact inline ML inference workload inside an FPGA network-processor path.
2. **Architecture:** packet input, single-packet 256×72 mode-switchable dual-port BRAM buffer/FIFO, DMA, GPU DMEM, six-stage GPU, four-thread CPU, control/status path.
3. **CPU:** restricted 32-bit ARM encodings over a custom 64-bit datapath; per-thread PC/register/flags/halt; fine-grained round robin.
4. **GPU:** four BF16 SIMD lanes with a custom multiply-add datapath; stall-only RAW handling; one hardware context in the final wrapper.
5. **BCAST:** define the exact semantic, show lane mapping, then explain RTL/decode/assembler/data-layout/kernel changes.
6. **Result:** 2,402→732 cycles and 211→108 instructions; the initialized IDS DMEM image/working set fell from 383 to 128 64-bit words, but the physical 1024×64 DMEM allocation did not shrink; five bit-identical hardware runs.
7. **Trade-off:** initial combinational BCAST mux cost +65 4-input LUTs; subsequent input register and INT16 scalarization are a separate refinement.
8. **Verification:** module tests, scalar/BCAST regression, frame checks, board cycle/output checks.
9. **Limitation:** pre-extracted features, restricted ARM subset, limited translator, incomplete autonomous response, and no complete timing closure.

## 6.4 SmartNIC 10–15 minute deep-dive outline

Draw while speaking:

- Top-level data and control paths.
- CPU stage diagram and four-thread issue timeline.
- GPU stage diagram and RAW stall path.
- Before/after BCAST lane and memory layout.
- DMA FSM and BRAM synchronous-read timing.
- Start/done boundary of the cycle counter.
- Critical path before and after input registering.
- Verification pyramid: unit→integration→frame→board.
- A final “what I would change” box.

The deep dive must answer:

- What state exists in each block?
- What happens under backpressure?
- What is combinational versus registered?
- What is the throughput and latency?
- What corner case breaks the design?
- What evidence proves the claim?
- What remains unproven?

## 6.5 SmartNIC fact sheet

| Item | Interview-safe statement |
|---|---|
| CPU | Custom 64-bit datapath decoding a restricted subset of 32-bit ARM encodings; not a complete ARMv4T/Thumb core |
| CPU pipeline | Five stages; four fine-grained hardware threads; per-thread PC/register/flags/halt |
| GPU | Six stages, four physical BF16 lanes with a custom multiply-add datapath, one final hardware context, stall-only RAW handling |
| BCAST result | 2,402→732 cycles, 3.28×; 211→108 instructions; initialized IDS DMEM image/working set 383→128 64-bit words, without shrinking the physical 1024×64 DMEM allocation |
| Measurement | On-board hardware cycle counter; same functional IDS inference/model and input, with a different instruction stream and repacked DMEM layout; five repeated BCAST runs at exactly 732 cycles with bit-identical output |
| Frequency | Applied 125 MHz clock; 732 cycles is nominally about 5.9 μs kernel time, not end-to-end packet latency |
| Early BCAST area | +65 four-input LUTs and zero FF for the initial combinational mux |
| Later refinement | Input register plus scalarized INT16 control; removed three multipliers and about 275 LUTs; do not merge this with the early +65 LUT number |
| Archived final-demo Fix B snapshot utilization | 21,190/23,616 slices, 30,827 logic LUTs, 20,926 FFs, 108 RAMB16, 9 MULT18X18 |
| Archived final-demo Fix B snapshot timing | WNS −4.394 ns with 817 failing core endpoints; board-tested but not timing-clean/signoff. A later root diagnostic was −3.909 ns/735 endpoints; do not mix the two reports |
| IDS input | Eleven pre-extracted features; raw flow-feature extraction was not implemented on FPGA |
| Accuracy | 82.39% project benchmark on KDDTest+; snapshot/seed selection touched KDDTest+, so not an untouched production holdout |
| Compiler scope | Pattern-specific CUDA→PTX→custom flow for five primitive kernels; full IDS kernels were hand-written custom assembly |
| Response path | Board evidence covered ingress, DMA/GPU inference, raw-logit writeback, header rewrite, drain completion, and one malformed ARM-generated wire frame. A usable autonomous response did not close because of invalid broadcast-source semantics, a 7-byte transmit truncation, and a repeated external output-queue stall. The response carried raw replicated logits and residual feature words, not an on-chip verdict |

The external output-queue-stall attribution is supported by strong hardware-debug records, but the external `output_queues` source is absent from the local project copy, so do not present that root cause as locally re-proven from source.

### Known repository/design issues to be ready to discuss

- The delivered final RTL/program is on the group12networkprocessor branch rather than the stale main branch.
- A duplicated gpu_params header lacks the BCAST definitions.
- Data-memory reset behavior is incomplete.
- One processor case statement lacks a default.
- The 8-bit FIFO/DMA length cannot represent 256 even though the physical memory has 256 entries.
- A fully self-contained local top-level rebuild is blocked by missing NetFPGA reference modules.

Do not defend these as harmless. Explain the failure mode, priority, proposed fix, and regression that would prevent recurrence.

### If directly asked about AI-assisted implementation

Do not volunteer a tooling inventory in every project answer, but answer a direct authorship question honestly:

> I used AI coding assistants substantially for some initial RTL generation and debugging. I was responsible for integrating the design, running and interpreting simulation and synthesis, diagnosing failures, validating the hardware behavior, and deciding what evidence I could safely claim. I would not claim that I manually authored every initial line. That experience also made me much more conscious of reviewing generated RTL for reset, width, CDC, synthesis, and corner-case problems, and I am prepared to walk through the modules and the issues I found.

The only safe way to support this answer is to understand each resume-critical module at interface, state, pipeline, synthesized-hardware, and failure-mode level before the interview.

## 6.6 SmartNIC high-probability questions

For each answer, include mechanism, trade-off, verification, and limitation.

1. Walk me through the architecture.
2. Why four hardware threads?
3. Show exactly why a same-thread dependency is or is not safe in the pipeline.
4. Is this really an ARM processor?
5. Describe the six GPU stages and RAW-hazard behavior.
6. Give the exact BCAST instruction semantics.
7. Why was the speedup 3.28× rather than exactly 4×?
8. What was the start/stop boundary of the cycle counter?
9. Did the design meet timing?
10. What was the PPA cost of BCAST?
11. How does the DMA handle BRAM read latency and done generation?
12. Why use a dual-port convertible FIFO?
13. What happens on simultaneous ownership requests or mode changes?
14. How did you verify each layer?
15. What part of the packet-response path actually worked?
16. What did the PTX translator support?
17. How would eight SIMD lanes change timing, area, bandwidth, and ISA behavior?
18. What debug features did you add?
19. Which known RTL issues would you fix first?
20. If this moved to ASIC, what would change in reset, clocking, memory, DFT, CDC, power, and signoff?

### Mandatory code review before claiming BF16 FMA

Re-open the RTL and confirm:

- whether multiply and add are truly fused or separately rounded;
- internal precision;
- truncation versus round-to-nearest-even;
- behavior for zero, sign, overflow, underflow, NaN, infinity, and subnormal values;
- latency and valid alignment.

If it is not IEEE-complete or truly fused, say “custom simplified BF16 multiply-accumulate datapath” and state the supported subset.

## 6.7 U45N 90-second version

> In my current USC/ISI project I reproduced and documented an AMD U45N/OpenNIC build-and-bring-up flow, then added a host-visible SystemVerilog AXI-Lite register block in the 322 MHz user-plugin domain. I generated and programmed the AXI-Lite image and validated one deterministic BAR2 MMIO vector covering signature/version, operand writes, XOR, sum, popcount, checksum, and status. Separately, on baseline OpenNIC, I verified driver binding and debugged physical link, RX counters, and LLDP topology. I did not demonstrate U45N-to-peer traffic or packet-path custom-function throughput. The baseline image ran but missed timing at −0.114 ns WNS. The observable AXI-Lite image missed setup by 0.086 ns, with its worst reported path in the upstream QDMA aligner. A separately generated but unflashed transparent TX-path pass-through build closed at +0.003 ns WNS and was not traffic-validated. I would therefore describe the work as real FPGA implementation and board validation with carefully separated evidence, not ASIC signoff or a completely timing-clean custom image.

## 6.8 U45N authorship boundary

| Category | Statement |
|---|---|
| Upstream | OpenNIC shell, QDMA, CMAC, driver |
| Provided inputs | Some AU45N shell/XDC files |
| Your work | Integration/build flow, custom AXI-Lite function, build inclusion, image generation, flashing/recovery, MMIO validation, layered debug, documentation |
| Not proven | U45N-to-U45N traffic, packet-path custom-function throughput, full custom-image timing closure |

## 6.9 Four timing outcomes

Memorize these exactly:

1. **NetFPGA archived final-demo Fix B snapshot:** WNS −4.394 ns, 817 failing core endpoints. A later root diagnostic was −3.909 ns/735 endpoints; it is a different report.
2. **U45N baseline OpenNIC image:** WNS −0.114 ns, TNS −19.232 ns. It was programmed and used for bring-up, but was not timing-clean.
3. **U45N transparent TX-path pass-through build:** WNS +0.003 ns, TNS 0.000 ns. It was generated but not flashed or traffic-validated.
4. **U45N observable AXI-Lite image:** WNS −0.086 ns, TNS −1.248 ns, 49 failing endpoints. It was flashed and validated with one deterministic BAR2 vector; that does not prove packet-path function or throughput.

Recommended answer:

> My direct implementation experience is FPGA rather than ASIC signoff. I took the designs through synthesis and implementation and analyzed post-route timing. The archived final-demo SmartNIC Fix B snapshot did not close its 8 ns core constraint, at −4.394 ns WNS with 817 failing endpoints. On U45N, the programmed baseline image also missed timing at −0.114 ns WNS. A separately generated but unflashed transparent TX-path build closed at +0.003 ns WNS; it was not traffic-validated. The flashed AXI-Lite image missed by 0.086 ns, with its worst reported path in the upstream QDMA H2C aligner, and I validated one deterministic BAR2 vector. I therefore would not describe the loaded custom systems as timing-clean or ASIC-signoff complete.

## 6.10 U45N high-probability questions

1. What did you personally author versus integrate?
2. Explain all five AXI-Lite channels.
3. Why must AW and W be accepted independently?
4. How does WSTRB affect writes?
5. Does your block support more than one outstanding transaction?
6. What exactly runs at 322 MHz?
7. How did you validate the register function, and how many vectors?
8. Was the image timing-clean?
9. Synthesis versus implementation versus bitstream versus MCS?
10. Walk through PCIe enumeration→driver binding→interface→link→RX→traffic.
11. Why did the QSPI recovery offset change?
12. How would you add assertions, random tests, and coverage to the AXI-Lite block?

## 6.11 ATPG 60-second version

**Do not rehearse the script below until you have filled in personal ownership from your original code/history.** The numbers appear in the submitted resume, but the attached ATPG project-summary copy is empty.

> In a three-person project, our team built a C++ digital-circuit simulation and ATPG toolchain for combinational ISCAS-85-derived circuits. The system included logic simulation, word-parallel stuck-at fault simulation, PODEM, and integrated test-pattern generation. The parallel simulator packed up to 63 faulty scenarios per 64-bit pass, and the largest listed case had 6,288 circuit lines and 7,744 reduced fault targets. My specific ownership was [replace with verified modules and decisions]. I use this project mainly to demonstrate C++, graph/bit-level reasoning, and verification thinking. It was an academic combinational stuck-at flow, not production scan insertion or ATE ownership.

The attached ATPG summary copy is empty. Before using any detailed claim, verify:

- exact personal ownership versus teammates;
- 64-bit bit mapping;
- PODEM objective/backtrace/implication/backtrack implementation;
- correctness oracle and regression tests;
- detected, untestable, and aborted behavior;
- whether SCOAP changed ordering only or any functional decision.

## 6.12 Why this role

> This role matches the part of my work I most want to deepen: taking a feature from a specification through microarchitecture and clean RTL, measuring the performance and area trade-offs, and then working with verification and implementation teams until it is truly deliverable. My projects gave me a strong prototype-level loop across architecture, RTL, timing reports, and hardware debug. I now want to learn the production ASIC discipline behind timing-clean, power-aware GPU and SoC blocks.

## 6.13 Honest ASIC-scope statement

> My strongest hands-on experience is RTL microarchitecture and FPGA implementation rather than production ASIC signoff. I understand the broader front-end flow and the purpose of lint, CDC/RDC, synthesis, equivalence, multi-corner STA, DFT, physical implementation, and signoff, but I would distinguish that knowledge from direct tapeout ownership.

## 6.14 Six behavioral stories to prepare

Use Situation→Constraint→Action→Evidence→Lesson, and keep each to 90 seconds.

1. BCAST performance improvement.
2. BCAST/BF16 timing-path repair.
3. U45N device-support/CMAC-license blocker.
4. PCIe/driver/link/topology layered debug.
5. A design that functioned but did not meet timing.
6. A collaboration story from ATPG or USC/ISI, not the solo SmartNIC implementation.

For failure stories, do not turn the answer into blame. State what evidence changed your hypothesis and what process you would use next time.

---

# 7. Knowledge-card pack

Use each card in this order:

**Question → 20-second answer → 60-second mechanism → common trap → project connection.**

The short answers below are the minimum acceptable first sentence. Expand them aloud.

## P0 cards — Must not fail

### P0-01 — Combinational versus sequential logic

**20-second answer:** Combinational outputs depend only on current inputs; sequential behavior stores state, normally in edge-triggered flip-flops, so outputs depend on current inputs and prior state.  
**Trap:** Saying an HDL always block is inherently sequential; sensitivity and assignments describe behavior, not the keyword alone.  
**Project link:** DMA/FIFO control state versus BF16 combinational datapath.

### P0-02 — Blocking versus nonblocking

**20-second answer:** Use blocking assignments for ordered calculation inside combinational logic and nonblocking assignments for clocked state updates, so all registers sample old-state values and update together.  
**Trap:** Mixing styles without understanding simulation scheduling; missing default assignments in combinational logic.  
**Project link:** Pipeline register alignment and DMA next-state logic.

### P0-03 — How is an unintended latch inferred?

**20-second answer:** A latch is inferred when combinational procedural logic does not assign an output on every path, forcing it to retain its old value. Give defaults or complete every branch.  
**Trap:** “always_comb automatically fixes the latch.” It can help tools diagnose intent; it does not invent missing assignments.

### P0-04 — Latch versus flip-flop

**20-second answer:** A latch is level-sensitive and transparent during its active level; a flip-flop samples on an edge. Latches complicate time borrowing and analysis and should be intentional.  
**Trap:** Calling a latch simply an asynchronous flip-flop.

### P0-05 — Synchronous versus asynchronous reset

**20-second answer:** A synchronous reset is sampled on the clock edge; an asynchronous reset can assert independent of the clock. A common robust pattern is asynchronous assertion and synchronized deassertion in each clock domain.  
**Trap:** Releasing one asynchronous reset directly across many unrelated domains.

### P0-06 — Moore versus Mealy FSM

**20-second answer:** Moore outputs depend only on registered state; Mealy outputs depend on state and current inputs. Mealy can respond earlier but can create longer or glitch-sensitive combinational paths.  
**Trap:** Choosing by state count alone rather than output timing and interface requirements.

### P0-07 — Setup time

**20-second answer:** Setup time is how long input data must be stable before the capture edge. A setup violation means the maximum-delay data path arrives too late.  
**Typical fixes:** Reduce logic depth/fanout/routing, pipeline or retime, use a faster cell in ASIC, relax frequency if allowed, or correct an invalid constraint.

### P0-08 — Hold time

**20-second answer:** Hold time is how long data must remain stable after the capture edge. A hold violation means the minimum-delay path changes too soon.  
**Typical fixes:** Add data-path delay or adjust clock-path balance; lowering clock frequency normally does not fix hold.  
**Trap:** Giving the same fix list as setup.

### P0-09 — Slack, WNS, and TNS

**20-second answer:** Setup slack is required time minus arrival time; hold slack uses the minimum-delay relationship. Negative slack is a violation. WNS is the worst negative slack, and TNS sums negative slack over failing endpoints.  
**Project link:** Quote all four project timing outcomes exactly.

### P0-10 — Clock skew and jitter

**20-second answer:** Skew is spatial arrival-time difference between clock endpoints; jitter is temporal variation of clock edges. Both consume timing margin, but their physical causes and analysis are different.  
**Trap:** Treating useful skew as a free fix with no effect on other paths.

### P0-11 — Latency versus throughput

**20-second answer:** Latency is time or cycles for one item to traverse a design; throughput is sustained completion rate. Pipelining can increase latency while improving throughput by shortening stage delay.  
**Project link:** 732-cycle kernel latency is not end-to-end packet throughput.

### P0-12 — How do you fix a critical path?

**20-second answer:** First verify the path and constraints, then determine whether delay comes from logic, fanout, routing, or clocking. Possible fixes include pipelining, retiming, logic restructuring, replication, floorplanning, or reducing fanout.  
**Trap:** Adding a pipeline register without updating protocol latency, valid alignment, or verification.

### P0-13 — Synchronous FIFO full and empty

**20-second answer:** Empty means no unread entries; full means occupancy equals depth. Implement with a count or read/write pointers plus wrap information, and define simultaneous push/pop behavior explicitly.  
**Trap:** Comparing equal pointers without a wrap bit, or corrupting count on simultaneous push and pop.

### P0-14 — Ready/valid invariant

**20-second answer:** A transfer occurs on a clock edge when ready and valid are both high. The source must not wait for ready before asserting valid, and while valid is high and ready is low, valid and payload must remain stable.  
**Project link:** AXI/stream backpressure and packet integrity.

### P0-15 — Metastability and two-flop synchronizer

**20-second answer:** Sampling an asynchronous transition near a clock edge can make a receiving flip-flop metastable. A two-flop synchronizer reduces propagation probability for a single-bit level, but it does not make an arbitrary multi-bit bus coherent.  
**Trap:** Synchronizing every bit of a bus independently.

### P0-16 — Safe multi-bit CDC

**20-second answer:** Use a protocol that guarantees data coherence: a request/acknowledge handshake with stable data, an asynchronous FIFO, Gray-coded state, or another proven bridge. Do not independently synchronize related data bits.  
**Trap:** Assuming a slow-changing bus is automatically safe.

### P0-17 — Single-cycle multiplier trade-off

**20-second answer:** A single-cycle combinational multiplier has simple control and one-cycle latency but can dominate area and timing. A pipelined multiplier increases registers and possibly latency while allowing higher frequency and throughput.  
**Reported drill:** Design a 2-bit single-cycle multiplier, then discuss scaling.

### P0-18 — Signed arithmetic and width

**20-second answer:** Operand signedness and expression width determine extension, comparison, and overflow behavior. Explicitly size constants and intermediate results, and verify truncation at assignment boundaries.  
**Project link:** Legacy Verilog signed behavior and BF16/control arithmetic.

### P0-19 — Pipeline hazards

**20-second answer:** Structural hazards compete for a resource; data hazards arise from dependencies such as RAW; control hazards arise from uncertain next PC. Fixes include resource duplication, stalls, forwarding, scheduling, and prediction/flush.  
**Project link:** Four-thread CPU and stall-only GPU must be explained separately.

### P0-20 — Cache organization

**20-second answer:** Address bits divide into byte/block offset, set index, and tag. Direct-mapped has one way per set, set-associative has several, and fully associative has one set. More associativity reduces conflicts but increases lookup cost and often hit latency/energy.  
**Trap:** Claiming more associativity always improves total performance.

### P0-21 — Round-robin arbiter

**20-second answer:** A round-robin arbiter begins priority after the most recently granted requester, improving fairness over fixed priority. Define whether the pointer advances on grant or successful transfer and how requests changing under stall are handled.  
**Trap:** Rotating priority when no transfer occurred and thereby losing a stalled grant.

### P0-22 — Synthesis, implementation, and STA

**20-second answer:** Synthesis maps RTL to a technology netlist under constraints. Implementation places and routes it. STA checks timing paths over modeled corners without simulating every vector. A bitstream is an FPGA configuration artifact, not proof of timing closure.  
**Project link:** U45N build states.

### P0-23 — Verification plan for a small RTL block

**20-second answer:** Start from requirements and invariants; cover reset, legal traffic, boundary values, concurrency, backpressure, illegal inputs, and recovery. Use directed tests, a reference model/scoreboard, assertions, coverage, and regressions.  
**Trap:** Listing tools without tying them to risks.

### P0-24 — FPGA implementation versus ASIC flow

**20-second answer:** Both use RTL, verification, synthesis concepts, constraints, and timing analysis, but FPGA maps to fixed programmable resources, while ASIC maps to standard cells/memories and adds foundry libraries, multi-corner signoff, DFT, physical power integrity, equivalence, and tapeout requirements.  
**Trap:** Calling successful FPGA board behavior ASIC-equivalent signoff.

### P0-25 — wire, reg, and logic

**20-second answer:** In Verilog, wire is a net driven continuously or by a module output, while reg is a procedural variable and does not imply a physical register. In SystemVerilog, logic is a variable type that covers most RTL signals but still cannot have conflicting procedural drivers.  
**Trap:** Saying every reg synthesizes to a flip-flop or every logic signal is combinational.

### P0-26 — if/case and priority

**20-second answer:** An if/else chain expresses priority; a complete case normally expresses mutually exclusive selection. Incomplete assignment can infer latches, and wildcard cases can hide X/Z behavior, so defaults and unique/priority assumptions must match real intent.  
**Trap:** Using casex casually in synthesizable control logic.

### P0-27 — Sticky register

**20-second answer:** A sticky bit records that an event has occurred and remains set until reset or an explicit clear. Define simultaneous set/clear priority, CDC/event capture, software read-clear races, and whether a still-active level source immediately reasserts it.  
**Reported drill:** NVIDIA exact-NCG report; implement set-dominant and explain why.

## P1 cards — Interview-ready depth

### P1-01 — Asynchronous FIFO

**20-second answer:** Store data in dual-port memory, maintain binary pointers locally, convert pointers to Gray code, synchronize Gray pointers across domains, and generate full/empty from synchronized pointer state.  
**Trap:** Gray code reduces multi-bit transition ambiguity; synchronized pointers still have latency, so flags are conservative.

### P1-02 — Why Gray code?

**20-second answer:** Consecutive Gray values change one bit, reducing incoherent observation when a counter crosses domains. It does not eliminate metastability; each Gray bit still needs synchronization.  
**Trap:** Applying arbitrary non-unit pointer jumps to a Gray-counter assumption.

### P1-03 — Pulse crossing

**20-second answer:** A narrow pulse can be missed in a slower destination. Use a toggle synchronizer, stretch-and-ack handshake, or event counter depending on event rate and loss requirements.  
**Trap:** A two-flop synchronizer alone does not guarantee pulse capture.

### P1-04 — Reset-domain crossing

**20-second answer:** Reset assertion/deassertion is itself a crossing problem. Deassert asynchronously asserted resets through a per-domain synchronizer and verify recovery/removal plus state sequencing.  
**Trap:** One synchronized reset chain feeding unrelated clocks.

### P1-05 — False path and multicycle path

**20-second answer:** A false path is functionally never required to transfer data under the timing relationship; a multicycle path intentionally has more than one cycle. These are design-intent exceptions, not ways to hide violations.  
**Trap:** Adding an exception before proving the protocol behavior and paired hold requirement.

### P1-06 — Clock enable versus clock gating

**20-second answer:** A clock enable keeps the clock toggling and conditionally holds state; clock gating stops clock activity with a glitch-free integrated gating method. Gating saves more clock power but adds test, timing, and enable-safety concerns.  
**Trap:** Coding a raw combinational AND gate on a clock.

### P1-07 — Dynamic and leakage power

**20-second answer:** Dynamic switching power is approximately proportional to activity, capacitance, voltage squared, and frequency. Leakage exists without switching. Reduce power with clock gating, operand isolation, lower activity, less capacitance, voltage/frequency choices, and technology-aware cells.  
**Trap:** Optimizing toggles while ignoring clock-tree or memory power.

### P1-08 — Five PPA trade-offs

Be able to discuss:

1. deeper pipeline versus registers/latency/control;
2. more SIMD lanes versus area/power/bandwidth/fanout;
3. forwarding versus stalls/mux delay;
4. more memory ports versus area/timing;
5. clock gating/operand isolation versus control and verification complexity.

### P1-09 — always_comb and always_ff

**20-second answer:** always_comb expresses combinational intent and gives tool checks around sensitivity and multiple drivers; always_ff expresses edge-triggered state intent and restricts event controls/drivers. Correct constructs still require complete logic and sound reset semantics.  
**Trap:** Assuming these constructs guarantee synthesizability or correct hardware.

### P1-10 — Packed versus unpacked arrays

**20-second answer:** Packed dimensions form a contiguous bit vector and support arithmetic/slicing; unpacked dimensions form collections of elements such as memories. Know the left/right dimension ordering before mapping lanes or registers.  
**Project link:** SIMD register and memory layout.

### P1-11 — AXI channel structure

**20-second answer:** AXI has independent write-address, write-data, write-response, read-address, and read-data channels. Each channel transfers using ready/valid; ordering and responses are protocol-defined.  
**AXI-Lite:** single-beat transactions and no burst behavior.

### P1-12 — AXI-Lite AW/W decoupling

**20-second answer:** Write address and write data are independent channels and may arrive in different cycles or orders. A compliant slave must capture each safely and issue a response only after both required handshakes complete.  
**Trap:** Updating a register only when AWVALID and WVALID happen to be high together.

### P1-13 — WSTRB

**20-second answer:** Each write strobe qualifies a byte lane. A register slave must preserve bytes whose strobes are low and define behavior for read-only or unsupported locations.  
**Trap:** Ignoring partial writes in testing.

### P1-14 — Skid buffer

**20-second answer:** A skid buffer is a small elastic buffer that preserves one in-flight item when downstream ready drops, often breaking a long combinational ready path while maintaining full throughput.  
**Trap:** Changing output data while output valid is stalled.

### P1-15 — DMA microarchitecture

**20-second answer:** A DMA engine accepts source, destination, length, and control; issues reads, buffers/alines data, issues writes, tracks progress, and reports completion/error. Define zero length, alignment, backpressure, abort, and ownership.  
**Project link:** Your simpler BRAM-to-BRAM FSM is a foundation, not a descriptor-rich production DMA.

### P1-16 — Interrupt controller

**20-second answer:** Capture edge or level sources into pending state, apply masks, select by priority, present an interrupt, and define clear/ack semantics. Handle CDC, simultaneous set/clear, lost pulses, and software races.  
**Trap:** Clearing a still-asserted level interrupt permanently.

### P1-17 — Time distribution

**20-second answer:** Separate clock distribution from timestamp distribution. For a coherent multi-bit time value across domains, use a snapshot handshake, Gray/event scheme, or protocol bridge rather than independent bit synchronizers.  
**Trap:** Reading a free-running binary counter asynchronously as a coherent word.

### P1-18 — First-level cache coherence

**20-second answer:** When several caches can hold one address, coherence maintains a consistent write order and controls who may modify a line. Snooping broadcasts over a shared medium; directories track sharers more scalably but add state and messages.  
**Scope:** First-level answer only unless asked to go deeper.

### P1-19 — BF16

**20-second answer:** BF16 has one sign bit, eight exponent bits, and seven explicit fraction bits. It preserves FP32-like exponent range but has much less precision. Accumulation precision and rounding policy dominate numerical behavior.  
**Trap:** Calling a multiply followed by a separately rounded add a true fused operation.

### P1-20 — Lint, CDC, RDC, LEC

**20-second answer:** Lint finds structural/coding risks; CDC checks unsafe clock crossings; RDC checks reset interactions; logical equivalence checks that transformations preserve intended logic. None replaces functional verification or STA.  
**Trap:** Treating zero tool warnings as proof of correctness.

### P1-21 — Useful assertions

Know how to express these properties in words and simple SVA:

- valid and payload remain stable while stalled;
- FIFO never reads empty or writes full unless explicitly allowed;
- request eventually receives grant under stated fairness assumptions;
- done cannot assert before start;
- an AXI response remains valid until accepted.

### P1-22 — Design-for-debug

**20-second answer:** Add observability that localizes failure with low perturbation: signature/version, sticky error bits, status/state snapshots, timeout causes, counters, trace buffers, and clear ownership. Define reset and read/clear semantics.  
**Project link:** Cycle counter and BAR2 signature/status are direct evidence.

### P1-23 — C++ const, volatile, atomic

**20-second answer:** const restricts modification through an interface; volatile forces observable accesses but is not thread synchronization; atomic provides defined inter-thread operations and memory ordering.  
**Trap:** Using volatile to fix a data race.

### P1-24 — C++ lifetime and RAII

**20-second answer:** Object lifetime determines when storage contains a valid object. RAII binds resource acquisition/release to constructors/destructors, reducing leaks and exceptional-path bugs. Use ownership-aware smart pointers rather than raw owning pointers.  
**Trap:** Returning a pointer/reference to stack storage.

### P1-25 — Python as hardware tooling

**20-second answer:** Use Python for deterministic parsing, generation, reference models, test vectors, and regression triage. Validate input formats, preserve reproducibility, and separate model correctness from DUT correctness.  
**Project link:** Assembler, ML/data-image generation, and MMIO validation.

## P2 cards — Differentiation

### P2-01 — Scheduler invariants

Define acceptance, eligibility, arbitration, grant stability under stall, fairness window, backpressure, and completion. A scheduler is not just a priority encoder.

### P2-02 — DMA scaling

Discuss outstanding transactions, tags, reordering, burst splitting, alignment, credit/backpressure, error retirement, and completion ordering.

### P2-03 — Interrupt coalescing

Coalescing reduces interrupt rate by triggering after a count or timer threshold, trading software overhead against event latency and requiring flush/timeout semantics.

### P2-04 — Coherent time snapshot

Use request/acknowledge to latch a source-domain timestamp, hold it stable, transfer it, and acknowledge consumption; specify latency and concurrent requests.

### P2-05 — Retiming and protocol alignment

Moving registers can improve timing but requires data/control/valid alignment and may change externally visible latency. Re-prove invariants and update tests.

### P2-06 — Operand isolation

Prevent inactive combinational blocks from toggling by holding/gating their inputs. Check control timing, glitch behavior, verification, and whether isolation muxes hurt timing.

### P2-07 — Front-end handoff

A good RTL owner delivers a clear spec, interface/timing assumptions, clean lint/CDC, assertions, constraints/exceptions with justification, synthesis results, known issues, and debug hooks to DV and implementation teams.

### P2-08 — ASIC migration of the SmartNIC project

Discuss memory macros, clock/reset architecture, CDC/RDC, scan/DFT, test modes, clock gating, power intent, standard-cell synthesis, equivalence, multi-corner STA, physical feedback, IR/EM, and post-silicon observability.

---

# 8. Live coding and design drill pack

Do not memorize source code. Memorize the design process:

**Clarify spec → define interface → identify state → draw cycles → code → test normal/boundary/concurrent cases → explain synthesized hardware.**

## P0 exact/near-exact reported drills

### RTL-01 — 2-bit single-cycle multiplier

**Spec:** Two unsigned 2-bit inputs, one 4-bit combinational product. Then add registered output and discuss latency.  
**Target:** 10 minutes.  
**Tests:** 0×anything, 3×3, all 16 combinations.  
**Follow-up:** How does an N-bit multiplier affect timing/area? When pipeline it?

### RTL-02 — Runs-of-ones FSM

**Spec:** One input bit per cycle. Detect or count a run of ones that begins after zero and ends at zero. Clarify whether output pulses on the ending zero, whether overlap matters, and what a run of length zero means.  
**Target:** 20 minutes including state diagram and testbench.  
**Tests:** 0, 00, 010, 0110, 01110, reset mid-run.  
**Trap:** Coding before clarifying the exact output requirement.

### RTL-03 — Modulo-3 FSM

**Spec:** Given a serial binary stream, track the numeric value modulo 3, or alternatively pulse every third event. Ask which version is intended.  
**Target:** 20 minutes.  
**Follow-up:** Moore/Mealy, state encoding, reset, invalid state recovery.

### RTL-04 — Latch-inference debug

**Spec:** Review a combinational block with missing else/default and explain simulation/synthesis behavior; repair it.  
**Target:** 5 minutes.  
**Follow-up:** What changes if intentional latch behavior is required?

### RTL-04B — Sticky status register

**Spec:** Capture an event into a sticky bit; software can clear it. Define simultaneous event and clear as set-dominant. Add mask and reset as follow-ups.  
**Target:** 10 minutes.  
**Tests:** event pulse, clear, simultaneous set/clear, held-high source, reset.  
**Reported relevance:** Exact NVIDIA NCG report.

### LOGIC-01 — Build logic from muxes

**Spec:** Construct XNOR from 2:1 muxes, NAND from a mux, and a 10:1 mux from 4:1 muxes. State tied constants and select behavior before drawing.  
**Target:** 15 minutes total.  
**Evaluation:** Correct truth table, no floating input, clear select encoding.  
**Reported relevance:** Repeated in NVIDIA NCG and comparable-company reports.

### FIFO-DEPTH-01 — Burst-rate sizing

**Spec:** A producer and consumer have different clocks and burst duty cycles. Compute net accumulation over the worst burst window, include CDC/latency margin, and state whether long-term average rate is sustainable.  
**Target:** 20 minutes.  
**Trap:** Calculating only average rates or ignoring phase/worst-case burst alignment.

### C++-01 — Palindrome

**Spec:** Check whether a string is a palindrome. Clarify case, punctuation, Unicode, and empty input.  
**Target:** 12 minutes.  
**Expected:** Two-pointer O(n) time, O(1) extra space for a simple ASCII requirement.  
**Tests:** empty, one char, even/odd, mismatch at ends, ignored punctuation if requested.

### C++-02 — Maximum and second maximum

**Spec:** Return max and optionally distinct second max from one pass. Clarify empty input and duplicates.  
**Target:** 12 minutes.  
**Trap:** Uninitialized values, integer minimum, duplicate semantics.

### Python-01 — Timing report parser

**Spec:** Parse lines containing path group, slack, startpoint, and endpoint. Print WNS, TNS, failing count, and worst N paths per group.  
**Target:** 35 minutes.  
**Tests:** no violations, malformed line, positive/negative slack, repeated groups.  
**Evaluation:** Clear parsing errors, correct numeric ordering, deterministic output.

### Python-01B — File/CSV transformation and debug

**Spec:** Read a CSV or log, validate fields, group or transform records, and emit deterministic output. Then repair an intentionally flawed version that drops a final record or mishandles duplicate keys.  
**Target:** 30 minutes.  
**Reported relevance:** A recent NVIDIA ASIC Engineer panel included Python/file/CSV parsing and script-debug tasks.

## P1 core RTL drills

### RTL-05 — Parameterized synchronous FIFO

**Required behavior:**

- parameterized width/depth;
- push/pop handshakes;
- full, empty, and optional count;
- simultaneous push/pop;
- pointer wrap;
- defined reset behavior;
- non-power-of-two depth decision.

**Target:** 45 minutes plus 15-minute tests.  
**Assertions:** no underflow/overflow; occupancy stays in range; accepted writes emerge in order.

### RTL-06 — Ready/valid pipeline stage

Implement one register stage that supports one transfer per cycle after fill and holds data under downstream stall. Explain whether ready is combinational and how a skid buffer breaks the path.  
**Target:** 35 minutes.  
**Tests:** continuous flow, isolated bubbles, late stall, reset, alternating ready.

### RTL-07 — Round-robin arbiter

**Spec:** N requesters; one-hot grant; rotating priority; grant holds until accepted if downstream stalls.  
**Target:** 45 minutes.  
**Tests:** one requester, all requesters, changing requests, stalled grant, reset, fairness.  
**Follow-up:** weighted arbitration and starvation bound.

### RTL-08 — AXI-Lite register block

**Spec:** two writable operand registers, read-only result/status, byte strobes, one outstanding transaction. AW and W may arrive independently.  
**Target:** 60 minutes or 30-minute microarchitecture only.  
**Tests:** AW-first, W-first, same-cycle, partial write, back-to-back access, stalled B/R response, invalid address.

### RTL-09 — Small DMA engine

**Spec:** Copy N words between two ready/valid memory ports. Registers: source, destination, length, start; outputs: busy, done, error.  
**Clarify:** zero length, alignment, abort, read latency, buffering, simultaneous start.  
**Target:** 60-minute microarchitecture plus core FSM.

### RTL-10 — Four-source interrupt controller

**Spec:** mix of edge and level sources; mask, pending, clear, priority, interrupt output.  
**Target:** 45 minutes.  
**Tests:** simultaneous set/clear, masked pending source, level remains asserted, two sources same cycle, reset.  
**Follow-up:** CDC and interrupt coalescing.

## P1 software drills

### C++-03 — Fixed-capacity ring buffer

Implement push, pop, front, empty, full, and size. Define whether one slot is sacrificed or a count/wrap bit distinguishes full from empty.  
**Target:** 35 minutes.  
**Tests:** wrap, fill, drain, simultaneous-model discussion, capacity one.

### C++-04 — Packed register fields

Implement extract, set, clear, sign-extend, and popcount helpers for 32/64-bit register words.  
**Target:** 25 minutes.  
**Trap:** shifting by word width, signed shift, mask overflow.

### Python-02 — Scheduler reference model

Given per-cycle request and ready traces, simulate a grant-hold round-robin scheduler and report fairness/latency.  
**Target:** 40 minutes.  
**Value:** Demonstrates scripting, reference models, and hardware reasoning at once.

## Upper-bound panel extension

Only do these after the P0 and P1 drills above:

- Two-stage registered adder with correctly aligned valid.
- Accumulate values per address; define same-cycle read/write and collision semantics.
- Generate Fibonacci iteratively and recursively in Python, then design a serial FSM/datapath version in RTL.
- Implement a 4×4 multiplier three ways: combinational, pipelined, and one shared MAC/iterative datapath; compare latency, throughput, area, and control.
- Reverse a singly linked list in C++ and explain lifetime/ownership.
- Debug intermediate-expression width/sign loss in Verilog.
- Find data loss in a ready/valid or programmable-delay circuit from a waveform.

These come from a recent Santa Clara ASIC Engineer panel and should be treated as a realistic upper bound, not a guaranteed NCG sequence.

## P2 whiteboard drills

### DESIGN-01 — GPU work scheduler

Inputs: four work queues with valid/priority/context; one execution slot with ready; completion feedback.  
Produce:

- acceptance and queue policy;
- eligibility and arbitration;
- grant stability during stall;
- fairness/starvation policy;
- context/state storage;
- perf/debug counters;
- assertions and verification plan.

### DESIGN-02 — Time distribution block

Distribute a coherent 64-bit timestamp from a source clock to consumers in two unrelated domains. Compare continuous Gray transfer, snapshot handshake, and local counters periodically synchronized to an epoch.

### DESIGN-03 — Debug-friendly DMA

Add timeout, sticky errors, last-failed address, progress count, performance cycles, interrupt, and safe clear semantics without placing a large mux on a critical datapath.

## P0 self-check reference implementations

Use these only after a timed attempt. They are deliberately small reference points, not the only correct answers. In an interview, state assumptions first and explain reset, concurrency, widths, and inferred hardware.

### 1. Two-bit multiplier

```systemverilog
module mul2_comb (
  input  logic [1:0] a,
  input  logic [1:0] b,
  output logic [3:0] p
);
  assign p = a * b;
endmodule
```

For a registered result, put `p <= a * b;` in `always_ff`. State that this adds a register boundary and one cycle of latency; it does not by itself decompose a large multiplier into balanced pipeline stages.

### 2. Set-dominant sticky bit

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    sticky <= 1'b0;
  else
    sticky <= event_in | (sticky & ~clear);
end
```

If `event_in` and `clear` are both high, the result is set. If the event comes from another clock domain or is narrower than one destination cycle, add an appropriate CDC/event-capture scheme before this logic.

### 3. Run-of-ones detector

Assumption: reset acts like a previously observed zero, and `run_done` pulses on the zero that terminates any nonempty run of ones.

```systemverilog
typedef enum logic {SEEN_ZERO, IN_RUN} state_t;
state_t state, next;

always_comb begin
  next     = state;
  run_done = 1'b0;
  unique case (state)
    SEEN_ZERO: if (bit_in)  next = IN_RUN;
    IN_RUN:    if (!bit_in) begin
      next     = SEEN_ZERO;
      run_done = 1'b1;
    end
    default: next = SEEN_ZERO;
  endcase
end

always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) state <= SEEN_ZERO;
  else        state <= next;
end
```

If the interviewer requires a minimum/maximum run length or a count, add a counter and define overflow/saturation before coding.

### 4. One-entry ready/valid pipeline stage

```systemverilog
assign in_ready = !out_valid || out_ready;

always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    out_valid <= 1'b0;
  end else if (in_ready) begin
    out_valid <= in_valid;
    if (in_valid)
      out_data <= in_data;
  end
end
```

When `out_valid && !out_ready`, `in_ready` is low and both output valid and payload hold. When the stage is empty or the current item is accepted, it can accept a replacement in the same cycle.

### 5. Count-based synchronous FIFO core

This version supports arbitrary positive `DEPTH`, does not provide empty-state fall-through, and allows a push on a full cycle only when a pop is also accepted. `pop_data` is meaningful only when `pop_valid` is high. Confirm whether asynchronous-read memory is acceptable for the target technology.

```systemverilog
module sync_fifo #(
  parameter int WIDTH = 32,
  parameter int DEPTH = 8,
  localparam int AW = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
  localparam int CW = $clog2(DEPTH + 1)
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic             push_valid,
  output logic             push_ready,
  input  logic [WIDTH-1:0] push_data,
  output logic             pop_valid,
  input  logic             pop_ready,
  output logic [WIDTH-1:0] pop_data
);
  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [AW-1:0] wptr, rptr;
  logic [CW-1:0] count;
  logic push_fire, pop_fire;

  assign pop_valid  = (count != 0);
  assign pop_data   = mem[rptr];
  assign pop_fire   = pop_valid && pop_ready;
  assign push_ready = (count < DEPTH) || pop_fire;
  assign push_fire  = push_valid && push_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wptr  <= '0;
      rptr  <= '0;
      count <= '0;
    end else begin
      if (push_fire) begin
        mem[wptr] <= push_data;
        wptr <= (wptr == DEPTH-1) ? '0 : wptr + 1'b1;
      end
      if (pop_fire)
        rptr <= (rptr == DEPTH-1) ? '0 : rptr + 1'b1;

      unique case ({push_fire, pop_fire})
        2'b10: count <= count + 1'b1;
        2'b01: count <= count - 1'b1;
        default: count <= count;
      endcase
    end
  end
endmodule
```

Self-check questions: Does simultaneous push/pop preserve count? What happens at full and empty? Does `DEPTH=1` work? What memory style is inferred? What changes for synchronous-read SRAM/BRAM?

### 6. Exact-byte palindrome in C++

```cpp
#include <string_view>

bool is_palindrome(std::string_view s) {
    std::size_t left = 0;
    std::size_t right = s.size();
    while (left < right) {
        --right;
        if (s[left] != s[right]) return false;
        ++left;
    }
    return true;
}
```

This is `O(n)` time and `O(1)` extra space. If case/punctuation/Unicode normalization is required, clarify it before changing the implementation.

### 7. Distinct second maximum in C++

```cpp
#include <optional>
#include <vector>

std::optional<long long>
second_distinct_max(const std::vector<long long>& values) {
    std::optional<long long> first, second;
    for (long long x : values) {
        if (!first || x > *first) {
            if (first) second = first;
            first = x;
        } else if (x < *first && (!second || x > *second)) {
            second = x;
        }
    }
    return second;
}
```

State that duplicates of the maximum do not count. Empty, one-value, all-equal, negative, and integer-boundary inputs belong in the test set.

### 8. CSV timing-summary skeleton in Python

Assumption: the normalized input CSV has `group,slack,startpoint,endpoint` columns. A real Vivado/PrimeTime text report needs a format-specific state machine or regex parser before this aggregation step.

```python
import csv
from collections import defaultdict

def summarize(path, worst_n=5):
    # Keep only the worst path for each endpoint before computing TNS.
    by_group = defaultdict(dict)
    with open(path, newline="", encoding="utf-8") as f:
        for line_no, row in enumerate(csv.DictReader(f), start=2):
            try:
                slack = float(row.get("slack", ""))
                group = (row.get("group") or "").strip()
                start = (row.get("startpoint") or "").strip()
                end = (row.get("endpoint") or "").strip()
                if not group or not start or not end:
                    raise ValueError("missing required field")
            except (AttributeError, TypeError, ValueError) as exc:
                raise ValueError(f"bad row {line_no}: {row}") from exc
            candidate = (slack, start, end)
            previous = by_group[group].get(end)
            if previous is None or candidate < previous:
                by_group[group][end] = candidate

    result = {}
    for group in sorted(by_group):
        paths = sorted(by_group[group].values())
        failing = [p for p in paths if p[0] < 0.0]
        result[group] = {
            "wns": paths[0][0],
            "tns": sum(p[0] for p in failing),
            "failing": len(failing),
            "worst": paths[:worst_n],
        }
    return result
```

Tests: no rows, all positive, multiple groups, repeated endpoints, malformed slack, negative zero, and deterministic tie ordering.

---

# 9. Debug framework and scenarios

Use this answer structure every time:

1. Restate the symptom and success criterion.
2. Identify the first failing layer.
3. List the top three hypotheses in probability/impact order.
4. Name the observation that distinguishes them.
5. Run the smallest safe experiment.
6. Localize, fix, and add a regression/prevention check.

## Scenario 1 — FIFO duplicates one word under backpressure

Check ready/valid stability, pointer update conditions, simultaneous push/pop, read-memory latency, and whether output valid is tied incorrectly to current rather than accepted state.

## Scenario 2 — Setup violation after adding BCAST

Verify the real path and constraint; decompose logic versus routing/fanout; check broadcast fanout and BF16 mux depth; consider input register/retiming/replication; then verify latency/valid alignment and cycle-equivalent behavior.

## Scenario 3 — Hold violation

Do not propose lowering frequency. Inspect minimum data delay and clock skew; add data delay or rebalance clocking through the implementation flow; ensure no new setup regression.

## Scenario 4 — Two-bit status occasionally illegal after CDC

Independent synchronizers can capture different source transitions. Replace with encoded single-bit state, Gray counter, handshake snapshot, or async FIFO depending on semantics.

## Scenario 5 — AXI-Lite writes randomly disappear

Suspect a slave that requires AWVALID and WVALID in the same cycle. Capture channels independently, retain each until both are available, honor strobes, and hold BVALID until BREADY.

## Scenario 6 — DMA busy never clears

Check zero-length and off-by-one semantics, read-response accounting, write acceptance, outstanding counter, lost completion pulse, reset/abort, and whether done is gated by an unobserved ready.

## Scenario 7 — PCIe device enumerates but application fails

Separate device personality/BAR layout, driver binding, MMIO mapping, register signature/version, DMA/IOMMU, and network link. Enumeration proves only PCIe visibility, not driver, DMA, or Ethernet correctness.

## Scenario 8 — Board works despite negative WNS

State that one physical sample/workload/environment operating is empirical evidence, not proof across process/voltage/temperature, all endpoints, or all data. Reproduce timing, inspect failing paths, fix or constrain correctly, and re-run functional regression.

---

# 10. Verification and PPA answer templates

## 10.1 “How would you fully verify this block?”

Answer in this order:

1. Convert requirements into features, invariants, and illegal behavior.
2. Build a reference model and transaction scoreboard.
3. Directed smoke tests for reset/basic flow.
4. Randomized timing, backpressure, boundary, and concurrency.
5. Assertions for protocol and internal invariants.
6. Functional and code coverage, with exclusions justified.
7. CDC/RDC/lint and, where useful, formal proofs.
8. Regressions, seeds, triage, and signoff criteria.

Then admit the project scope:

> My project used directed/module tests, integration checks, and board evidence. It did not have a production UVM/coverage/formal closure flow; the steps above are what I would add.

## 10.2 “How would you optimize this for PPA?”

Do not answer with a random list. First define the bottleneck and constraints:

- performance target: latency, throughput, or frequency;
- area target and dominant resources;
- power target and switching/memory/clock contribution;
- correctness and interface latency constraints.

Then compare concrete options with costs:

- pipeline/retime;
- reduce precision/width;
- resource share versus replicate;
- change lane count;
- reduce mux depth/fanout;
- bank or reshape memory;
- forwarding versus stall;
- clock gate or operand-isolate;
- change arbitration/dataflow;
- add observability off the critical path.

## 10.3 “What would you hand to DV and backend?”

- executable spec and interface timing;
- block diagram, state/register descriptions, and latency;
- assertions and test plan;
- clean lint/CDC/RDC results or documented waivers;
- justified constraints/exceptions;
- synthesis/timing/PPA reports;
- reset/clock/test modes;
- known issues and debug registers;
- change log and reproducible build.

---

# 11. Mock interview scripts and scoring

## 11.1 45-minute first technical screen

1. 0–3 min: self-introduction.
2. 3–12 min: resume project and ownership.
3. 12–20 min: digital/STA rapid questions.
4. 20–38 min: FSM/FIFO/short coding task.
5. 38–43 min: follow-ups and trade-offs.
6. 43–45 min: candidate questions.

## 11.2 60-minute panel round

1. 0–15 min: SmartNIC deep dive.
2. 15–30 min: new scheduler/DMA/interrupt spec.
3. 30–45 min: RTL or C++/Python implementation.
4. 45–55 min: timing/verification/PPA.
5. 55–60 min: behavioral and questions.

## 11.3 100-point rubric

| Category | Points |
|---|---:|
| Facts, ownership, and limitations | 20 |
| Digital/RTL/STA correctness | 20 |
| Microarchitecture and trade-offs | 15 |
| Coding correctness and corner cases | 20 |
| Verification/debug method | 15 |
| Communication and collaboration | 10 |

**Pass:** 80+ and no red-line mistake.

### Red-line mistakes

- Blocking/nonblocking or latch explanation is fundamentally wrong.
- Setup and hold are reversed, or frequency reduction is offered as the primary hold fix.
- Two-flop synchronizer is proposed for a coherent multi-bit bus.
- FIFO ignores simultaneous push/pop or pointer wrap.
- Ready/valid payload changes while stalled.
- FPGA board behavior is described as timing signoff or ASIC tapeout.
- SmartNIC/U45N timing claims contradict the reports.
- CUDA/PTX or ARM compatibility is overstated.
- “Fully verified” is claimed without acknowledging missing coverage/formal/signoff.

---

# 12. Four-hour emergency plan

If an interview is scheduled for the next day:

1. **60 min:** resume truth sheet and four timing outcomes.
2. **45 min:** self-intro, SmartNIC two-minute version, U45N 90-second version.
3. **60 min:** blocking/nonblocking, latch, FSM, FIFO, ready/valid, setup/hold/slack, CDC.
4. **45 min:** one FSM plus one sync-FIFO walkthrough.
5. **20 min:** palindrome plus max-in-array.
6. **20 min:** cache organization, pipeline hazards, round robin.
7. **20 min:** why role, failure story, two interviewer questions.
8. **10 min:** close all notes and rest.

---

# 13. Questions to ask interviewers

Choose two per person:

1. Which blocks in this opening are closest to the work-scheduler, interrupt, time-distribution, or DMA examples in the posting?
2. At what point does a new-graduate designer begin owning microarchitecture decisions rather than only RTL implementation?
3. How does the team divide responsibility among design, DV, synthesis/timing, and backend?
4. What usually makes a new graduate successful in the first six months on this team?
5. Which constraints most often dominate this block: frequency, area, power, verification schedule, or debug visibility?
6. How early do designers receive physical/timing feedback, and how iterative is that loop?
7. What kinds of post-silicon observability does this team architect into its RTL?

Avoid asking information already answered by the posting.

---

# 14. Final one-page checklist

## Resume/project

- [ ] 45-second self-intro
- [ ] SmartNIC 30-second, 2-minute, and 10–15 minute versions
- [ ] U45N 90-second version and exact authorship boundary
- [ ] ATPG 60-second version with verified ownership
- [ ] Four timing outcomes memorized
- [ ] BCAST baseline, measurement, correctness, PPA, and limitation
- [ ] BF16 arithmetic behavior rechecked in RTL
- [ ] Five “what I would fix” items
- [ ] Three debug stories

## Fundamentals

- [ ] Blocking/nonblocking and latch
- [ ] FSM and sequence detector
- [ ] Setup/hold/slack/skew/jitter
- [ ] Sync and async FIFO
- [ ] Single-bit, pulse, multi-bit CDC
- [ ] Reset assertion/deassertion
- [ ] Ready/valid and skid buffer
- [ ] Pipeline hazards and caches
- [ ] Round-robin arbitration
- [ ] AXI-Lite, DMA, interrupt, time snapshot
- [ ] ASIC versus FPGA flow
- [ ] Verification, lint/CDC/RDC/LEC, PPA

## Timed implementation

- [ ] 2-bit multiplier
- [ ] Runs-of-ones or modulo-3 FSM
- [ ] Sync FIFO
- [ ] Ready/valid stage
- [ ] Round-robin arbiter
- [ ] Palindrome and max/second max
- [ ] C++ ring buffer or packed fields
- [ ] Python timing parser or scheduler model

## Final gate

- [ ] Two mocks at 80+ with no red-line error
- [ ] Answers remain accurate when interrupted
- [ ] No new topic on the final evening

---

# 15. Primary references

## Role and process

- [NVIDIA — ASIC Design Engineer, New College Grad 2026, JR2020309](https://jobs.nvidia.com/careers/job/893396250459)
- [NVIDIA — How We Hire](https://www.nvidia.com/en-us/about-nvidia/careers/how-we-hire/)

## Candidate-reported interviews

- [Glassdoor — NVIDIA New Grad ASIC Design Engineer](https://www.glassdoor.com/Interview/NVIDIA-New-Grad-ASIC-Design-Engineer-Interview-Questions-EI_IE7633.0%2C6_KO7%2C36.htm)
- [Glassdoor — NVIDIA ASIC Engineer](https://www.glassdoor.com/Interview/NVIDIA-ASIC-Engineer-Interview-Questions-EI_IE7633.0%2C6_KO7%2C20.htm)
- [Glassdoor — NVIDIA ASIC Design Engineer](https://www.glassdoor.com/Interview/NVIDIA-ASIC-Design-Engineer-Interview-Questions-EI_IE7633.0%2C6_KO7%2C27.htm)
- [Glassdoor — NVIDIA ASIC Design Engineer, page 2](https://www.glassdoor.com/Interview/NVIDIA-ASIC-Design-Engineer-Interview-Questions-EI_IE7633.0%2C6_KO7%2C27_IP2.htm)
- [Glassdoor — NVIDIA ASIC Design Engineer, page 3](https://www.glassdoor.com/Interview/NVIDIA-ASIC-Design-Engineer-Interview-Questions-EI_IE7633.0%2C6_KO7%2C27_IP3.htm)
- [Glassdoor — NVIDIA ASIC Design Engineer, page 4](https://www.glassdoor.com/Interview/NVIDIA-ASIC-Design-Engineer-Interview-Questions-EI_IE7633.0%2C6_KO7%2C27_IP4.htm)
- [Glassdoor — NVIDIA ASIC Design Intern](https://www.glassdoor.com/Interview/NVIDIA-ASIC-Design-Intern-Interview-Questions-EI_IE7633.0%2C6_KO7%2C25.htm)
- [Reddit — NVIDIA ASIC Hardware Design Engineer interview discussion](https://www.reddit.com/r/ECE/comments/1lworer/interview_at_nvidia_for_asic_hardware_design/)
- [一亩三分地 — NVIDIA 24 Summer ASIC Design](https://www.1point3acres.com/bbs/thread-1047704-1-1.html)
- [一亩三分地 — NVIDIA ASIC verification/design efficiency](https://www.1point3acres.com/bbs/thread-739185-1-1.html)
- [Scribd — NVIDIA ASIC verification/design efficiency full-text mirror](https://www.scribd.com/document/1030069501/%E9%AA%8C%E8%AF%81%E8%AE%B0%E5%BD%95)
- [一亩三分地 — NVIDIA ASIC phone interview](https://www.1point3acres.com/bbs/thread-552586-1-1.html)
- [一亩三分地 — NVIDIA new-grad hardware pass report](https://www.1point3acres.com/bbs/thread-1039490-1-1.html)
- [一亩三分地 — Google TPU RTL phone and onsite](https://www.1point3acres.com/bbs/thread-560112-1-1.html)
- [一亩三分地 — Meta ASIC E5](https://www.1point3acres.com/bbs/thread-1097113-1-1.html)
- [一亩三分地 — Meta ASIC Design](https://www.1point3acres.com/bbs/thread-1017894-1-1.html)
- [一亩三分地 — Qualcomm ASIC Design](https://www.1point3acres.com/bbs/thread-444445-1-1.html)

## Technical primary sources

- [Arm — Introduction to AMBA AXI4](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/Learn%20the%20Architecture/102202_0100_01_Introduction_to_AMBA_AXI.pdf)
- [Arm — AMBA AXI and ACE Protocol Specification](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf)
- [AMD — Vivado Design Analysis and Closure Techniques, UG906](https://docs.amd.com/r/en-US/ug906-vivado-design-analysis)
- [Clifford Cummings — CDC Design and Verification Techniques](https://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf)
- [Sunburst Design — Technical paper library, including asynchronous FIFO and reset papers](https://www.sunburst-design.com/papers/)

## Source-quality note

Official NVIDIA and protocol/tool documentation support process and technical facts. Interview reports are anonymous, self-selected, and team-specific; their value is in repeated patterns, not exact probability. Chinese forum details that were hidden or inaccessible were not reconstructed or treated as known facts. The Scribd item is a third-party re-upload and was used only where it aligned with the indexed original; it is not an authoritative NVIDIA source.
