"""Chain the 11 grandma/grandpa clips with smooth video + audio transitions.

Renders 3 variants to ./transitions/ for side-by-side comparison:
  A — classic 1.0 s crossfade everywhere (safe baseline)
  B — cinematic 1.5 s crossfade everywhere (more contemplative)
  C — storybook beats: mixed (longer fades on narrative beats, fade-black on
      scene changes, fade-white into the endcard)

Each variant uses ffmpeg's `xfade` for video and `acrossfade` (qsin curve,
which preserves perceived loudness for music) for the embedded music bed.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "transitions")
os.makedirs(OUT_DIR, exist_ok=True)

CLIPS = [
    os.path.join(HERE, f"grandma_grandpa_golden_retriever_{i}.mp4")
    for i in range(1, 12)
]
N = len(CLIPS)

FFMPEG = (
    "C:/Users/shao4/AppData/Local/Microsoft/WinGet/Packages/"
    "Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/"
    "ffmpeg-8.1-full_build/bin/ffmpeg.exe"
)
FFPROBE = (
    "C:/Users/shao4/AppData/Local/Microsoft/WinGet/Packages/"
    "Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/"
    "ffmpeg-8.1-full_build/bin/ffprobe.exe"
)


def probe_duration(path):
    out = subprocess.check_output(
        [FFPROBE, "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", path], text=True)
    return float(out.strip())


def build_filter(transitions, t_durs, clip_durs):
    """Construct ffmpeg -filter_complex string for chained xfade + acrossfade.

    Clips are mixed 1920x1080 and 1280x720, so every video input is first
    normalized to 1080p60 with square pixels before xfade can chain them.

    Returns (filter_str, last_v_label, last_a_label, total_duration).
    """
    parts = []
    # Normalize every video input: scale up 720p->1080p, force SAR=1, force 60fps.
    for i in range(N):
        parts.append(
            f"[{i}:v]scale=1920:1080:flags=lanczos,setsar=1,fps=60,format=yuv420p[s{i}]"
        )
    last_v = "[s0]"
    last_a = "[0:a]"
    acc_len = clip_durs[0]
    for i in range(N - 1):
        td = t_durs[i]
        offset = acc_len - td
        v_out = f"[v{i + 1}]"
        a_out = f"[a{i + 1}]"
        parts.append(
            f"{last_v}[s{i + 1}]xfade=transition={transitions[i]}:"
            f"duration={td}:offset={offset:.4f}{v_out}"
        )
        parts.append(
            f"{last_a}[{i + 1}:a]acrossfade=d={td}:c1=qsin:c2=qsin{a_out}"
        )
        last_v = v_out
        last_a = a_out
        acc_len = acc_len + clip_durs[i + 1] - td
    return ";".join(parts), last_v, last_a, acc_len


def render(name, transitions, t_durs, clip_durs):
    fcomplex, last_v, last_a, total = build_filter(transitions, t_durs, clip_durs)
    out_path = os.path.join(OUT_DIR, name)
    cmd = [FFMPEG, "-hide_banner", "-loglevel", "warning", "-stats", "-y"]
    for c in CLIPS:
        cmd += ["-i", c]
    cmd += [
        "-filter_complex", fcomplex,
        "-map", last_v, "-map", last_a,
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        "-movflags", "+faststart",
        out_path,
    ]
    print(f"=== {name}  (predicted ~{total:.2f}s) ===")
    subprocess.run(cmd, check=True)
    sz = os.path.getsize(out_path) / (1024 * 1024)
    print(f"   wrote {out_path}  ({sz:.1f} MB)")


def main():
    print("Probing clip durations...")
    cd = [probe_duration(c) for c in CLIPS]
    raw_total = sum(cd)
    print(f"  raw concat would be {raw_total:.2f}s")

    # === Option A: Classic — uniform 1.0 s crossfade everywhere ===
    render(
        "transitions_A_classic_1s.mp4",
        transitions=["fade"] * (N - 1),
        t_durs=[1.0] * (N - 1),
        clip_durs=cd,
    )

    # === Option B: Cinematic — uniform 1.5 s crossfade everywhere ===
    render(
        "transitions_B_cinematic_1p5s.mp4",
        transitions=["fade"] * (N - 1),
        t_durs=[1.5] * (N - 1),
        clip_durs=cd,
    )

    # === Option C: Storybook beats — mix per narrative ===
    # Index i = transition between clip (i+1) and clip (i+2) in the prompt list.
    # Clip map (for reference):
    #   1 cozy kitchen / phone rings    2 unknown number close-up
    #   3 envelopes outside cottage     4 envelopes at window, dog growl
    #   5 zoom INTO phone, tiny guard   6 guard sorts good vs bad
    #   7 pull-out, the chip pulses     8 chip stamps hospital/bank/datacenter
    #   9 inside data center            10 back to kitchen at sunset
    #   11 endcard
    c_trans = [
        "fade",       # 1->2  same scene, gentle continuation
        "fadeblack",  # 2->3  inside -> outside scene change
        "fade",       # 3->4  outside -> inside (window)
        "fade",       # 4->5  magical zoom INTO phone (long fade)
        "fade",       # 5->6  inside chip world, continuation
        "fade",       # 6->7  inside chip world, continuation
        "fade",       # 7->8  pull-out reveal (long fade)
        "fade",       # 8->9  data world continuation
        "fadeblack",  # 9->10 back to kitchen at sunset (scene change)
        "fadewhite",  # 10->11 endcard reveal
    ]
    c_durs = [
        0.8,
        1.0,
        0.8,
        1.5,  # longer for the magical zoom-in beat
        0.8,
        0.8,
        1.5,  # longer for the pull-out reveal
        0.8,
        1.0,
        1.2,
    ]
    render(
        "transitions_C_storybook_beats.mp4",
        transitions=c_trans,
        t_durs=c_durs,
        clip_durs=cd,
    )

    print("\nAll variants written to:", OUT_DIR)


if __name__ == "__main__":
    main()
