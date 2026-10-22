# Snort 3 -- Multi-Pattern Search Engine (MPSE) and Hyperscan Integration

Source URLs:
- https://blog.snort.org/2020/09/snort-3-hyperscan-.html (official Snort blog -- WebFetch denied, content from search snippets)
- https://www.intel.com/content/www/us/en/developer/articles/technical/hyperscan-and-snort-integration.html
- https://docs.snort.org/rules/options/payload/fast_pattern (Snort 3 Rule Writing Guide)
- https://blog.talosintelligence.com/using-snort-fast-patterns-wisely-for/ (Talos blog on fast patterns)
- https://snort.org/documents/optimization-of-pattern-matches-for-ids (Marc Norton's foundational paper)
- https://www.usenix.org/conference/nsdi19/presentation/wang-xiang (Hyperscan NSDI 2019 paper, Wang et al.)
- https://branchfree.org/2019/02/28/paper-hyperscan-a-fast-multi-pattern-regex-matcher-for-modern-cpus/ (Geoff Langdale walkthrough)

## Snort 3 architecture vs Snort 2

| | Snort 2 | Snort 3 |
|---|---|---|
| Threading | Single-threaded process; need N processes for N cores | One control thread + up to **32 packet threads** in a single process |
| Config | Each process loads its own config and rule trees | Single shared config / network map / rule trees |
| Language | C | C++ |
| Memory per core | Linear in #cores | Shared across threads |

## The fast pattern matcher = Snort's first-stage filter

Snort detects intrusions in **two stages**:
1. **MPSE (Multi-Pattern Search Engine):** scans the packet payload for any of thousands of literal substrings drawn from the rule corpus. One literal per rule is selected by the rule writer (`fast_pattern` keyword) or auto-picked as the longest content. This is the expensive shared scan.
2. **Per-rule detection engine:** when MPSE flags a candidate rule, Snort runs the full rule -- remaining content matches in declared order, PCRE, byte_test, byte_jump, flow conditions.

Without the MPSE filter, Snort would have to evaluate every rule against every packet -- impossible at line rate with 10,000+ rules.

## MPSE engine choices in Snort 3

| Engine | Algorithm | Trade-off |
|---|---|---|
| `ac_full` | Aho-Corasick DFA, full table | Fastest of the AC family; high memory |
| `ac_bnfa` | Aho-Corasick NFA / sparse | Lower memory; slower than ac_full |
| `lowmem` | trie-based, caseless | Smallest memory footprint |
| `hyperscan` | Intel Hyperscan (FDR/Teddy + NFA hybrid) | **Default recommended.** Fastest; uses SIMD |

> "Hyperscan is up to two times faster than the ac_full engine and three times faster than ac_bnfa."

> "The overall memory footprint of the original Snort is more than 12 times larger than that of Snort optimized by Hyperscan."

> Caseness: "The hyperscan MPSE is case sensitive. lowmem is caseless which helps reduce memory. ac_bnfa and ac_full are also caseless."

## Inside Hyperscan (NSDI 2019, Wang et al.)

Two acceleration cores, both SIMD-driven:

- **FDR ("Flooded DFA Replacement")** -- "bucketed SIMD shift-or matcher with supercharacters." For 80 to tens-of-thousands of strings. Uses 128-bit shift-or masks updated with 128-bit SIMD instructions (`pslldq` for left-shift, `por` for or). Holds a "much larger set of simple state machines" simultaneously.
- **Teddy** -- SIMD literal matching engine. "Parallelly match up to 64 characters with only 16 SIMD operations." Built on Glushkov NFA bit-parallelism.
- For regex, Hyperscan does **NFA -> DFA hybrid decomposition**: chops a regex into multiple sub-automata, dispatches each to whichever engine (DFA, NFA, FDR, Teddy, Sheng, lookaround) is cheapest.
- Compiles to a Hyperscan **bytecode** offline; runtime is mostly stream / block scanning of the bytecode.
- SIMD substrate: SSE4.2, AVX2, AVX-512 on x86. Authors: Xiang Wang, Yang Hong, Harry Chang, KyoungSoo Park, Geoff Langdale, Jiayu Hu, Heqing Zhu (Intel). Used in Snort, Suricata, Bro/Zeek, ClamAV.

## Algorithm history
The original Aho-Corasick paper is from 1975. Marc Norton (Sourcefire / Snort) wrote the seminal "Optimizing Pattern Matching for Intrusion Detection" paper extending AC with Boyer-Moore-style skipping. AC-BNFA, AC-FULL, AC-SPARSE, AC-BANDED are all tabulation choices for the same DFA.

## OpenAppID (in Snort 3)

Search results:
> "Application Identification (AppId) is a network detection capability in Snort3 that identifies applications on the network based on traffic analysis."

> "OpenAppID consists of a set of LUA libraries for detecting applications, as well as the application detectors themselves."

> "Lua JIT is a high performance, low memory footprint, scripting language that is flexible, multi-platform."

Detectors classify into Service, Client, Payload, Misc. Implemented as Lua scripts loaded as plugins. Lets community members add app identification without recompiling Snort.

## Killer detail
**Snort 3 ships open-source Aho-Corasick from 1975 and Hyperscan from 2008-2019.** The whole IDS industry sits on top of literal pattern matching with a regex back-end -- there is no neural classifier in the open-source baseline.
