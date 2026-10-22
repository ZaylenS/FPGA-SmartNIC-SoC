"""Render the demo-video ending card as 1920x1080 PNG, matching Opening.html palette."""
import os
from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080

# Colors (match Opening.html CSS variables)
INK       = (26, 32, 72)     # close to #1a365d
BIG       = (44, 82, 130)    # #2c5282
MUTED     = (74, 85, 104)    # #4a5568
GRAY      = (113, 128, 150)  # #718096
BG_OUTER  = (255, 255, 255)
BG_INNER  = (251, 252, 254)  # subtle warm-white center

# Locate Windows fonts (Segoe UI matches the HTML decks' system-font stack)
FONTS_DIR = r"C:\Windows\Fonts"
def find_font(*names):
    for n in names:
        p = os.path.join(FONTS_DIR, n)
        if os.path.exists(p):
            return p
    return None

BOLD = find_font("segoeuib.ttf", "arialbd.ttf")
SEMI = find_font("seguisb.ttf", BOLD)
REG  = find_font("segoeui.ttf", "arial.ttf")

f_thank  = ImageFont.truetype(BOLD, 150)
f_title  = ImageFont.truetype(SEMI, 56)
f_bullet = ImageFont.truetype(REG,  34)
f_foot   = ImageFont.truetype(REG,  30)
f_name   = ImageFont.truetype(REG,  24)

# Soft radial gradient: subtle warm-white center fading to white
img = Image.new("RGB", (W, H), BG_OUTER)
overlay = Image.new("RGB", (W, H), BG_INNER)
mask = Image.new("L", (W, H), 0)
mdraw = ImageDraw.Draw(mask)
cx, cy = W // 2, int(H * 0.40)
r_max = int(max(W, H) * 0.65)
# Radial-style mask: bright at center, fades to 0 at edges (approximated with concentric circles)
for i in range(60):
    t = i / 59
    r = int(r_max * (0.15 + 0.85 * t))
    alpha = int(180 * (1 - t))
    mdraw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=alpha)
img = Image.composite(overlay, img, mask)
draw = ImageDraw.Draw(img)

def center_text(text, font, y, fill, kerning_adjust=0):
    bbox = draw.textbbox((0, 0), text, font=font)
    w = bbox[2] - bbox[0]
    x = (W - w) // 2 + kerning_adjust
    draw.text((x, y), text, font=font, fill=fill)

# --- Layout ---
# "Thank you" — primary headline, ink color
center_text("Thank you", f_thank, 200, INK)

# Accent rule
line_w = 320
line_y = 430
draw.rectangle(
    [((W - line_w) // 2, line_y), ((W + line_w) // 2, line_y + 4)],
    fill=BIG,
)

# Project title — secondary headline, big blue
center_text("Network Processor with Inline ML-IDS", f_title, 460, BIG)

# Recap bullets — muted
bullets = [
    "11→16→8→2 ANN  ·  82.4 % accuracy on KDDTest+",
    "Custom 4-lane SIMD GPU  ·  custom ISA + BCAST",
    "732 cycles per packet  ·  3.28× vs scalar mode",
    "On-chip ARM orchestrator runs the full round-trip on the FPGA",
]
y = 620
for b in bullets:
    center_text(b, f_bullet, y, MUTED)
    y += 56

# Footer
center_text("EE533 SP26  —  Team 7", f_foot, 920, GRAY)
center_text("Zilin Shao", f_name, 960, GRAY)

out = os.path.join(os.path.dirname(__file__), "ending_card.png")
img.save(out, "PNG")
print("Wrote", out)
