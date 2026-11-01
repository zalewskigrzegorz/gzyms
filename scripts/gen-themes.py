#!/usr/bin/env python3
"""Writes Sources/GzymsCore/Themes.gen.swift: the terminal palettes tuios ships that stay readable as Gzyms themes.

Usage: scripts/gen-themes.py <bubbletint tints.gen.go>
The ids come from `tuios --list-themes`, the colours from bubbletint, the library tuios takes them from. Take
tints.gen.go at the version tuios was built with (`go version -m $(command -v tuios)`, v2.0.2 for tuios 0.12.1):
newer ones renamed some palettes. tuios' own few (charmtone, gilt) are not in it and are skipped.

Kept only when it reads well (Greg, 2026-11-01: trust the contrast, not the eye): text at least 7:1 on the
background (WCAG AAA) and every accent at least 4.5:1 on the background and on a chip. Each accent takes the
terminal's normal or bright shade, whichever reads better; the secondary text gets just enough light for 4.5:1.
"""
import re, subprocess, sys
from pathlib import Path

TEXT_MIN, ACCENT_MIN, MUTED_MIN = 7.0, 4.5, 4.5
# Kept even when they fail: every colour that falls short is moved towards white (on a dark background) or black
# (on a light one) until it passes, in the same hue (Greg: the popular ones stay, the ones that already read well too).
POPULAR = {
    "catppuccin_mocha", "catppuccin_macchiato", "catppuccin_frappe", "catppuccin_latte", "dracula", "nord",
    "tokyonight", "tokyonight_storm", "tokyonight_day", "gruvbox_dark", "gruvbox_light", "one_dark", "one_half_dark",
    "one_half_light", "atom_one_light", "rose_pine", "rose_pine_moon", "rose_pine_dawn", "kanagawa",
    "builtin_solarized_dark", "builtin_solarized_light", "ayu", "ayu_mirage", "ayu_light", "github", "monokai_pro",
    "material", "cobalt_2", "synthwave",
}
COLORS = ["Bg", "Fg", "Red", "Green", "Yellow", "Blue", "Purple", "Cyan",
          "BrightRed", "BrightGreen", "BrightYellow", "BrightBlue", "BrightPurple", "BrightCyan"]


def lum(h):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(int(h[0:2], 16)) + 0.7152 * lin(int(h[2:4], 16)) + 0.0722 * lin(int(h[4:6], 16))


def contrast(a, b):
    x, y = sorted([lum(a), lum(b)], reverse=True)
    return (x + 0.05) / (y + 0.05)


def mix(a, b, t):
    return "".join("%02x" % round(int(a[i:i + 2], 16) + (int(b[i:i + 2], 16) - int(a[i:i + 2], 16)) * t) for i in (0, 2, 4))


def theme(c, fix):
    """The Gzyms tokens of one palette, and whether it reads well. `fix` pushes what falls short until it passes."""
    bg, fg = c["Bg"], c["Fg"]
    dark = lum(bg) < 0.18
    away = "ffffff" if dark else "000000"

    def push(x, ok):
        if not fix:
            return x
        return next((mix(x, away, s / 100) for s in range(0, 101, 2) if ok(mix(x, away, s / 100))), mix(x, away, 1))

    fg = push(fg, lambda x: contrast(x, bg) >= TEXT_MIN)
    surface = mix(bg, fg, 0.1)
    reads = lambda x: min(contrast(x, bg), contrast(x, surface))
    best = lambda name: push(max(c[name], c["Bright" + name], key=reads), lambda x: reads(x) >= ACCENT_MIN)
    red, green, gold, blue, mauve, sky = (best(n) for n in ["Red", "Green", "Yellow", "Blue", "Purple", "Cyan"])
    peach = push(mix(red, gold, 0.5), lambda x: reads(x) >= ACCENT_MIN)
    pink = push(c["BrightPurple"] if c["BrightPurple"] != mauve else c["Purple"], lambda x: reads(x) >= ACCENT_MIN)
    # The least light from the background towards the text that still reads at 4.5:1.
    overlay = next((mix(bg, fg, t / 100) for t in range(30, 91, 2) if contrast(mix(bg, fg, t / 100), bg) >= MUTED_MIN), mix(bg, fg, 0.9))
    t = {"base": bg, "surface": surface, "overlay": overlay, "text": fg, "mauve": mauve, "pink": pink, "lavender": blue,
         "green": green, "gold": gold, "peach": peach, "red": red, "sky": sky, "hud": mix(bg, "000000" if dark else "ffffff", 0.4)}
    ok = contrast(fg, bg) >= TEXT_MIN and all(reads(a) >= ACCENT_MIN for a in [red, green, gold, peach, sky, mauve])
    return t, ok


src = Path(sys.argv[1]).read_text()
ids = subprocess.run(["tuios", "--list-themes"], capture_output=True, text=True, check=True).stdout.split()
palettes = {}
for block in re.findall(r"= &Tint\{(.*?)\n\}", src, re.S):
    tid = re.search(r'ID:\s+"([^"]+)"', block).group(1)
    colors = {n: "%02x%02x%02x" % (int(r), int(g), int(b))
              for n, r, g, b in re.findall(r"(\w+):\s+&Color\{R: (\d+), G: (\d+), B: (\d+)", block)}
    if all(f in colors for f in COLORS):
        palettes[tid] = colors

TOKENS = ["base", "surface", "overlay", "text", "mauve", "pink", "lavender", "green", "gold", "peach", "red", "sky", "hud"]
rows, dropped = [], 0
for i in ids:
    if i not in palettes or i in {"mocha-neon", "grayscale"}:
        continue
    t, ok = theme(palettes[i], fix=False)
    if not ok and i in POPULAR:
        t, ok = theme(palettes[i], fix=True)
    if ok:
        rows.append(i + " " + " ".join(t[k] for k in TOKENS))
    else:
        dropped += 1
missing = POPULAR - {r.split()[0] for r in rows}
if missing:
    sys.exit(f"popular themes that could not be fixed or are not in tuios: {sorted(missing)}")
out = Path(__file__).resolve().parent.parent / "Sources/GzymsCore/Themes.gen.swift"
out.write_text(
    "// Generated by scripts/gen-themes.py from bubbletint, the palettes tuios ships. Do not edit by hand.\n\n"
    "extension Theme {\n"
    f"    /// id, then {' '.join(TOKENS)} as hex: only palettes that pass the contrast check in the script.\n"
    '    static let terminalPalettes = """\n'
    + "\n".join("    " + r for r in rows)
    + '\n    """\n}\n'
)
print(f"{len(rows)} themes kept, {dropped} dropped for contrast, written to {out}")
