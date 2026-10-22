# Hyperscan -- NSDI 2019 paper key facts

Source URLs:
- https://www.usenix.org/system/files/nsdi19-wang-xiang.pdf
- https://www.usenix.org/conference/nsdi19/presentation/wang-xiang
- https://branchfree.org/2019/02/28/paper-hyperscan-a-fast-multi-pattern-regex-matcher-for-modern-cpus/

Title: "Hyperscan: A Fast Multi-pattern Regex Matcher for Modern CPUs"
Authors: Xiang Wang, Yang Hong, Harry Chang, KyoungSoo Park, Geoff Langdale, Jiayu Hu, Heqing Zhu (Intel)
Venue: NSDI '19 (16th USENIX NSDI)

## What it is
The open-sourced Intel regex/string matcher. The default MPSE in Snort 3 and Suricata. Apache 2 license. Runs on x86 with SSE4.2/AVX2/AVX-512.

## Key concepts

### Pattern decomposition
A regex is broken into a graph of sub-automata. Each sub-automaton is dispatched to whichever specialized engine matches its profile (literal vs. character class vs. arbitrary regex). This is described as a **"hybrid automaton"** approach.

### Engine zoo
- **FDR** -- "bucketed SIMD shift-or matcher with supercharacters." For sets of literal patterns (~80 to tens of thousands). Uses 128-bit SIMD shift/OR instructions (`pslldq`, `por`) to maintain many shift-or state machines in parallel.
- **Teddy** -- highly optimized SIMD literal engine for **small** rule sets. "Parallelly match up to 64 characters with only 16 SIMD operations." Glushkov NFA bit-parallelism + SIMD.
- **Sheng** -- a small DFA engine using AVX-512 byte-shuffle instructions to do 16-state DFA transitions in one shuffle.
- **NFA / DFA / LBR** -- general-purpose backups for things FDR / Teddy can't handle.
- **Lookaround** acceleration for assertions.

### Compile -> bytecode -> scan
Hyperscan compiles a rule set off-line into a binary bytecode. The runtime is then mostly memory-bound bytecode interpretation across SIMD-accelerated engines. This is what enables the multi-pattern claim: **all rules scanned in one pass** rather than rule-at-a-time.

## Performance numbers (paper)
- 8.5x to 25x faster than RE2 on multi-pattern workloads
- Used in Snort, Suricata, Bro/Zeek, ClamAV, OpenWrt
- Up to 2x ac_full, 3x ac_bnfa in Snort 3 (per Snort blog)

## Why it matters for our pitch
Hyperscan is **the** state-of-the-art literal/regex matcher for IDS today, on x86 CPUs. Pigasus's MSPM is essentially "Hyperscan in silicon." Our project is "an ML classifier in silicon" -- a different algorithm class.
