"""Render simple black/white title cards for the investor clips.

Outputs (in this folder):
  q1_title.png / q1_title.mp4   5-second card before invester_clip1.mp4
  q2_title.png / q2_title.mp4   5-second card before invester_clip2.mp4

Layout: centered question label + question text + circular headshot + name/role.
"""
import os
import subprocess
import sys
import textwrap

from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
BG = (0, 0, 0)
WHITE = (255, 255, 255)
WHITE_DIM = (180, 180, 180)
WHITE_LABEL = (140, 140, 140)

HERE = os.path.dirname(os.path.abspath(__file__))
HEADSHOT = os.path.join(HERE, "interviewee_headshot_screenshot.png")

NAME = "Daniel C."
ROLE = "Communication Engineer"
NOTE = "(Institution withheld for privacy)"

QUESTIONS = [
    ("QUESTION 1",
     "How big is the AI cybersecurity market today?",
     "q1_title"),
    ("QUESTION 2",
     "NVIDIA BlueField and AMD Pensando already ship programmable SmartNICs. "
     "Can a startup win against them?",
     "q2_title"),
]

FONT_DIR = "C:/Windows/Fonts"
F_LABEL    = ImageFont.truetype(f"{FONT_DIR}/segoeuib.ttf", 30)  # bold caps label
F_QUESTION = ImageFont.truetype(f"{FONT_DIR}/segoeui.ttf",  60)  # regular
F_NAME     = ImageFont.truetype(f"{FONT_DIR}/segoeuib.ttf", 42)  # bold
F_ROLE     = ImageFont.truetype(f"{FONT_DIR}/segoeui.ttf",  30)  # regular
F_NOTE     = ImageFont.truetype(f"{FONT_DIR}/segoeui.ttf",  24)  # small

FFMPEG = (
    "C:/Users/shao4/AppData/Local/Microsoft/WinGet/Packages/"
    "Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/"
    "ffmpeg-8.1-full_build/bin/ffmpeg.exe"
)
DURATION = 5  # seconds
FPS = 30      # match user-edited clips


def circular_headshot(path, size):
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    s = min(w, h)
    img = img.crop(((w - s) // 2, (h - s) // 2, (w + s) // 2, (h + s) // 2))
    img = img.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size, size), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def wrap_to_width(text, font, draw, max_w):
    """Greedy word-wrap so each line fits within max_w pixels."""
    words = text.split()
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        bbox = draw.textbbox((0, 0), trial, font=font)
        if bbox[2] - bbox[0] <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def text_size(draw, text, font):
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def draw_centered(draw, text, font, fill, y):
    tw, th = text_size(draw, text, font)
    draw.text(((W - tw) // 2, y), text, font=font, fill=fill)
    return th


def make_card(label, question, base_name):
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)

    # Label "QUESTION N"
    label_y = 220
    lh = draw_centered(draw, label, F_LABEL, WHITE_LABEL, label_y)

    # Tiny divider rule
    rule_y = label_y + lh + 22
    draw.line((W // 2 - 36, rule_y, W // 2 + 36, rule_y), fill=WHITE_LABEL, width=2)

    # Question text, wrapped to ~70% screen width
    max_text_w = int(W * 0.72)
    lines = wrap_to_width(question, F_QUESTION, draw, max_text_w)

    line_spacing = 18
    line_h = text_size(draw, "Hg", F_QUESTION)[1]
    block_h = len(lines) * line_h + (len(lines) - 1) * line_spacing
    y = rule_y + 60
    for ln in lines:
        draw_centered(draw, ln, F_QUESTION, WHITE, y)
        y += line_h + line_spacing

    # Bottom block: circular headshot above name/role/note (all centered)
    hs_size = 160
    headshot = circular_headshot(HEADSHOT, hs_size)
    hs_x = (W - hs_size) // 2
    hs_y = 770
    img.paste(headshot, (hs_x, hs_y), headshot)

    name_y = hs_y + hs_size + 22
    nh = draw_centered(draw, NAME, F_NAME, WHITE, name_y)
    role_y = name_y + nh + 6
    rh = draw_centered(draw, ROLE, F_ROLE, WHITE_DIM, role_y)
    note_y = role_y + rh + 4
    draw_centered(draw, NOTE, F_NOTE, WHITE_LABEL, note_y)

    png_path = os.path.join(HERE, base_name + ".png")
    img.save(png_path)
    print(f"  wrote {png_path}")
    return png_path


def png_to_mp4(png_path, mp4_path):
    cmd = [
        FFMPEG, "-hide_banner", "-loglevel", "error", "-y",
        "-loop", "1", "-t", str(DURATION), "-i", png_path,
        "-f", "lavfi", "-t", str(DURATION),
        "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
        "-r", str(FPS),
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        "-movflags", "+faststart",
        "-shortest",
        mp4_path,
    ]
    subprocess.run(cmd, check=True)
    print(f"  wrote {mp4_path}")


def main():
    if not os.path.exists(HEADSHOT):
        sys.exit(f"Headshot not found: {HEADSHOT}")
    for label, question, base in QUESTIONS:
        png = make_card(label, question, base)
        mp4 = os.path.join(HERE, base + ".mp4")
        png_to_mp4(png, mp4)
    print("Done.")


if __name__ == "__main__":
    main()
