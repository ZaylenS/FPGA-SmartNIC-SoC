"""Transcribe the investor interview WAV using faster-whisper (large-v3, GPU).

Outputs (in this folder):
  interview_transcript.srt   subtitle file with timestamps (drop into a video editor)
  interview_transcript.txt   plain text, one segment per line, [hh:mm:ss] prefixed
  interview_transcript.json  machine-readable, includes per-word timestamps
"""
import json
import os
import site
import sys
import time

# ctranslate2 4.7 ships against CUDA 12, but this machine has CUDA 13.1 system-wide.
# Make the bundled cu12 DLLs (cublas64_12.dll, cudnn64_9.dll, nvrtc64_120_0.dll)
# discoverable. ctranslate2's compiled loader uses the legacy DLL search path,
# so we have to prepend to PATH; os.add_dll_directory is added too for any
# Python-level ctypes loads that happen along the way.
_dll_dirs = []
for _site in site.getsitepackages() + [site.getusersitepackages()]:
    for _sub in ("cublas", "cudnn", "cuda_nvrtc", "cuda_runtime"):
        _bin = os.path.join(_site, "nvidia", _sub, "bin")
        if os.path.isdir(_bin):
            _dll_dirs.append(_bin)
            os.add_dll_directory(_bin)
if _dll_dirs:
    os.environ["PATH"] = os.pathsep.join(_dll_dirs) + os.pathsep + os.environ.get("PATH", "")

from faster_whisper import WhisperModel  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO = os.path.join(HERE, "interview_audio.wav")
BASE = os.path.join(HERE, "interview_transcript")


def fmt_ts(t, sep=","):
    h = int(t // 3600)
    m = int((t % 3600) // 60)
    s = int(t % 60)
    ms = int(round((t - int(t)) * 1000))
    if ms == 1000:
        s += 1
        ms = 0
    return "%02d:%02d:%02d%s%03d" % (h, m, s, sep, ms)


def main():
    if not os.path.exists(AUDIO):
        sys.exit("Audio file not found: %s" % AUDIO)

    print("Loading large-v3 on CUDA (float16)...")
    t0 = time.time()
    model = WhisperModel("large-v3", device="cuda", compute_type="float16")
    print("  loaded in %.1fs" % (time.time() - t0))

    print("Transcribing %s ..." % AUDIO)
    t0 = time.time()
    segments, info = model.transcribe(
        AUDIO,
        language="en",
        vad_filter=True,
        word_timestamps=True,
        beam_size=5,
    )
    print("  detected language=%s prob=%.2f duration=%.1fs"
          % (info.language, info.language_probability, info.duration))

    # The generator is lazy; iterating drives the actual decode.
    all_segs = []
    for seg in segments:
        all_segs.append(seg)
        # Live progress: show end time of each segment as we go.
        sys.stdout.write("\r  segment %4d  t=%s" % (len(all_segs), fmt_ts(seg.end, ".")))
        sys.stdout.flush()
    print("\n  decoded %d segments in %.1fs" % (len(all_segs), time.time() - t0))

    # SRT (for video editors)
    with open(BASE + ".srt", "w", encoding="utf-8") as f:
        for i, seg in enumerate(all_segs, 1):
            f.write("%d\n%s --> %s\n%s\n\n" % (
                i, fmt_ts(seg.start), fmt_ts(seg.end), seg.text.strip()))

    # Plain text with timestamps
    with open(BASE + ".txt", "w", encoding="utf-8") as f:
        for seg in all_segs:
            f.write("[%s] %s\n" % (fmt_ts(seg.start, "."), seg.text.strip()))

    # JSON with per-word timestamps
    def seg_to_dict(seg):
        return {
            "id": seg.id,
            "start": seg.start,
            "end": seg.end,
            "text": seg.text,
            "words": [
                {"start": w.start, "end": w.end, "word": w.word, "prob": w.probability}
                for w in (seg.words or [])
            ],
        }

    with open(BASE + ".json", "w", encoding="utf-8") as f:
        json.dump({
            "language": info.language,
            "language_probability": info.language_probability,
            "duration": info.duration,
            "segments": [seg_to_dict(s) for s in all_segs],
        }, f, indent=2)

    print("Wrote: %s.{srt,txt,json}" % BASE)


if __name__ == "__main__":
    main()
