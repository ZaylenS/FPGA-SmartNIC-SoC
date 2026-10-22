#!/usr/bin/env python3
"""Generate ElevenLabs narration for the 11 grandma/grandpa clips (v2 script).

Wording is anchored in real senior-targeted scams (grandparent scam, AI voice
cloning, fake bank / Medicare calls) so the story is concretely relatable
rather than abstract. See narration_script.md for the rationale per clip.

Usage:
  XI_API_KEY=<your_key> python generate_audio.py

Voice and tuning are fixed below. Edit CLIPS or VOICE_SETTINGS to iterate.
"""
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

API_KEY = os.environ.get("XI_API_KEY")
if not API_KEY:
    sys.exit("ERROR: set XI_API_KEY environment variable before running.")

VOICE_ID = "DLsHlh26Ugcm6ELvS0qi"
MODEL_ID = "eleven_multilingual_v2"

VOICE_SETTINGS = {
    "stability": 0.60,
    "similarity_boost": 0.75,
    "style": 0.35,
    "use_speaker_boost": True,
}

OUT_DIR = Path(__file__).resolve().parent / "audios"
OUT_DIR.mkdir(parents=True, exist_ok=True)

CLIPS = [
    (
        "clip01_phone_rings.mp3",
        "A quiet afternoon. The phone rings. "
        "Unknown number. Maybe your doctor. Maybe the bank."
    ),
    (
        "clip02_unknown_number.mp3",
        "Or — one of those calls you've heard about. "
        "A grandson in trouble. A voice that sounds like family."
    ),
    (
        "clip03_threats_drift.mp3",
        "These days, the bad ones don't knock on the door. "
        "They slip in — through your phone, your email, your TV."
    ),
    (
        "clip04_what_they_want.mp3",
        "They want your password. Your photos. Your savings. "
        "Even the voice of someone you love — to use against you."
    ),
    (
        "clip05_tiny_guard.mp3",
        "But what if a tiny guard lived right inside your phone? "
        "One who never sleeps — and who knows who's family."
    ),
    (
        "clip06_guard_sorts.mp3",
        "The real call from your grandson — straight through. "
        "The fake one — gently turned away. No fuss. No worry."
    ),
    (
        "clip07_calls_through.mp3",
        "So the calls that matter most — Sunday with the grandkids — "
        "those always come through. Clear, safe, and yours."
    ),
    (
        "clip08_scaleup_intro.mp3",
        "And it's not just your phone. Your hospital has one. "
        "Your bank has one. Even the big computers behind today's AI."
    ),
    (
        "clip09_ai_threats.mp3",
        "Because the same tricksters who copy your grandson's voice — "
        "they whisper to those big computers, too."
    ),
    (
        "clip10_warm_close.mp3",
        "So tonight — the phone is quiet. The dog is asleep. "
        "And the little guard is still watching."
    ),
    (
        "clip11_endcard.mp3",
        "Security that fits in your pocket. "
        "Looking out for what — and who — you love."
    ),
]

URL = f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}"
HEADERS = {
    "xi-api-key": API_KEY,
    "Content-Type": "application/json",
    "Accept": "audio/mpeg",
}

failures = 0
for filename, text in CLIPS:
    out_path = OUT_DIR / filename
    print("  -> %s (%d chars)... " % (filename, len(text)), end="", flush=True)
    body = json.dumps({
        "text": text,
        "model_id": MODEL_ID,
        "voice_settings": VOICE_SETTINGS,
    }).encode("utf-8")
    req = urllib.request.Request(URL, data=body, headers=HEADERS, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            audio = resp.read()
            out_path.write_bytes(audio)
            print("OK (%d bytes)" % len(audio))
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print("FAIL [%d] %s" % (e.code, err_body[:300]))
        failures += 1
    except urllib.error.URLError as e:
        print("FAIL (network): %s" % e)
        failures += 1

print("")
if failures:
    print("Done with %d failure(s). Output dir: %s" % (failures, OUT_DIR))
    sys.exit(1)
print("All %d clips saved to: %s" % (len(CLIPS), OUT_DIR))
