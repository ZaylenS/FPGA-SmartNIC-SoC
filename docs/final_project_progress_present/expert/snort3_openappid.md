# Snort 3 -- OpenAppID Application Identification

Source URLs:
- https://blog.snort.org/2014/03/firing-up-openappid.html (announcement)
- https://blog.snort.org/2020/10/better-application-logging-with-snort3.html
- https://github.com/redBorder/snort/blob/master/doc/README.appid (developer docs)
- https://snort-org-site.s3.amazonaws.com/production/document_files/files/000/000/066/original/OpenAppID-Community-Webinar.pdf
- https://deepwiki.com/snort3/snort3/4.3-application-identification

## What this is
A detection layer Snort 3 uses to identify applications running over arbitrary ports / TLS / HTTP. Released open-source in 2014. Companion to the rule corpus -- not a replacement.

## Detection model

Four detector classes (from the AppID architecture):

| Class | Identifies |
|---|---|
| Service Detection | Server-side application (e.g. "this TCP/443 is Slack") |
| Client Detection | Client-side application (e.g. "this is Outlook") |
| Payload Detection | Content type (e.g. "this is a YouTube video segment") |
| Misc Detection | Contextual signals |

## How it is implemented
- **Lua plugin model.** Each application detector is a Lua script.
- Snort 3 ships with **LuaJIT** embedded; plugins run JIT-compiled.
- "The libs subdirectory contains the Lua libraries needed to run application detection, the lua directory contains the bulk of the detectors."
- Open Detector Package (ODP) downloadable from snort.org -- thousands of community-contributed detectors.

## Why this matters as a competitor
- **Snort's "AI-ish" feature is just Lua scripting**, not ML.
- Application identification without ML; pattern logic for common app fingerprints (TLS SNI, JA3 hashes, HTTP user agents, payload byte signatures).
- Similar in spirit to Palo Alto's App-ID but ships open source.

## Killer detail
The "intelligence" in Snort 3 is **community Lua scripts**. There is no model, no classifier, no training. Every signature is a hand-written rule. That is the academic/industrial baseline our project is out-classing on the ML axis.
