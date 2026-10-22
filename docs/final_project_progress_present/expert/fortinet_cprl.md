# Fortinet CPRL — Content Pattern Recognition Language

## Source URLs
- https://patents.google.com/patent/US8140660B1/en (US patent 8,140,660 B1, Wells et al., assigned to Fortinet, granted March 2012)
- https://patents.google.com/patent/US20120102196A1/en (companion application)
- https://www.fortinetguru.com/2018/09/inside-fortios-antivirus/ (Inside FortiOS: AntiVirus, references CPRL inside FortiASIC content processor)
- https://docs.fortinet.com/document/fortigate/7.6.6/hardware-acceleration/622344/content-processors-cp10-cp9-cp9xlite-cp9lite (CP9/CP10 docs, confirming pattern-matching offload)
- https://cookbook.fortinet.com/glossary/cprl/ (Fortinet glossary entry, "deep-inspection, proactive signature-detection technology")

## What CPRL is
A **patented domain-specific bytecode language** for representing network/AV signatures. Compiled, not interpreted as text. Designed by Fortinet so that *the same signature artifact* can be evaluated either in software on the CPU or executed natively by Fortinet's content-processor ASIC. Originally created for AV signatures; later extended with regex-like syntax to cover IPS/application-ID patterns.

## Patent-disclosed execution model
US8140660B1 ("Content pattern recognition language processor and methods of using the same") describes the full architecture:

> "Each predicate of a signature is compiled into a byte stream that controls a logic of processor."

> "Code values represent bytes that follow the 0xDF (extended) byte that tells the interpreter that it is now dealing with a CPRL predicate."

So a CPRL signature is a **byte stream of opcodes** consumed by a small predicate-evaluation engine. The 0xDF prefix is the escape that switches the engine from raw byte-match mode to predicate-evaluation mode.

> "CPRL includes five families of predicates: Test, Decision, Iteration, Function, and Pointer."

This is a small ISA — branches, loops, function calls, pointer arithmetic — embedded in a signature. The patent is explicit that this is **more powerful than regex / Aho-Corasick**: a CPRL signature can express loops, conditionals, and stateful evaluation, where Aho-Corasick can only express deterministic literal/multi-string match.

## Where CPRL executes
**Inside the FortiASIC Content Processor (CP9 today, CP10 in latest 200G/3800G).** The Inside FortiOS: AntiVirus document is explicit:

> "By utilizing the unique Content Pattern Recognition Language (CPRL) built into the FortiASIC Content Processor, FortiOS is able to deliver high performance and low latency anti-malware capabilities."

The CP9/CP10 admin docs back this up by listing "pattern matching acceleration" as a CP capability and naming IPSA (IPS Acceleration) — the offload path that ships flow-based pattern matching from CPU into the content processor. **CP10 doubles CP9's IPS pattern-matching throughput to 20 Gbps and grows the rule database 6x.**

## Architectural significance
CPRL is Fortinet's answer to the same problem we're solving: *how do you do deep content inspection at line rate without burning host CPU?* Their answer: define a custom signature language, compile to bytecode, build a hardware co-processor (CP9/CP10) that executes that bytecode directly. The CP is logically *parallel* to the NP7 fast path: NP7 does packet forwarding; CP9/CP10 does content/payload inspection. **Both are below the host CPU's IPS engine and the AI/ML IPS classifier — the ML model is still software.**

> "A single CPRL signature can catch 50,000 or more variants of a family of malware."

This is the value proposition Fortinet uses to justify CPRL over plain-regex: one CPRL predicate replaces a whole family of regex variants, because the bytecode can branch and re-enter.

## Where CPRL fits in the IPS pipeline
1. NP7 forwards packets and reassembles flows.
2. NTurbo path delivers reassembled flow bytes to a memory region the IPS engine watches.
3. **CP9/CP10 runs CPRL bytecode against that flow content** (IPSA offload). Aho-Corasick-style multi-string filter is part of this stage.
4. Surviving alerts are passed up to the FortiOS IPS engine on the host CPU.
5. **The AI/ML IPS classifier (FortiOS 7.6.3+)** rescores those alerts on the host CPU. ML is *above* CPRL, not inside the CP.

## Killer detail for Slide 1.3
**Fortinet's pattern-matching IP is a custom bytecode language (CPRL) compiled and executed by a dedicated content-processor ASIC (CP9/CP10) — not regex on a CPU.** This is exactly the "Aho-Corasick co-processor" architecture from Prof Cho's 2005 DAC paper, generalized into a patented bytecode and shipped in every FortiGate. **But CPRL still does not do ML.** CP9/CP10 is a fixed-function pattern engine; the AI/ML classifier sits one layer up on the host CPU. The ML detection layer remains the part that has *not* been silicon-accelerated by anyone in the industry.
