#!/usr/bin/env bash
# Cut investor interview into 4 highlight clips.
# Frame-accurate re-encode (libx264 CRF 18 + AAC). Tweak ranges below and re-run.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
INPUT="$HERE/Interviewee investor part presentation video.mp4"
OUTDIR="$HERE/clips"
mkdir -p "$OUTDIR"

# Locate ffmpeg: prefer PATH, fall back to winget install location.
if command -v ffmpeg >/dev/null 2>&1; then
  FFMPEG="ffmpeg"
else
  FFMPEG="/c/Users/shao4/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.1-full_build/bin/ffmpeg.exe"
fi

cut() {
  local start="$1" end="$2" out="$3" label="$4"
  printf "  cutting %s  %s -> %s\n" "$label" "$start" "$end"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -ss "$start" -to "$end" -i "$INPUT" \
    -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p \
    -c:a aac -b:a 192k \
    -movflags +faststart \
    "$OUTDIR/$out"
}

# Clip 1 — Market is huge, touches many industries (Q line 36-37 + A lines 38-42)
cut "00:01:44.700" "00:02:04.500" "01_market_size.mp4"            "market size"

# Clip 2 — Specialized ML on hardware sets you apart (lines 74-77)
cut "00:04:25.700" "00:04:51.500" "02_specialized_ml_diff.mp4"    "ML differentiation"

# Clip 3 — What I'd want before investing (lines 105-111)
cut "00:07:08.000" "00:07:57.000" "03_invest_criteria.mp4"        "invest criteria"

# Clip 4 — What acquirers are paying for (mix of IP + team, lines 119-121)
cut "00:08:19.300" "00:09:09.500" "04_acquisition_value.mp4"      "acquisition value"

echo "Done. Clips written to: $OUTDIR"
ls -lh "$OUTDIR"
