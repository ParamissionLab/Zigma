"""Render Zigma example output as SVG terminal screenshots for the README.

The images are generated from the real example binaries, so they always show
actual Zigma output. Regenerate after changing examples or widgets:

    zig build install
    python docs/showcase/render.py

Requires Python 3.8+ and no third-party packages.
"""

from __future__ import annotations

import html
import os
import re
import subprocess
import sys
import unicodedata
from dataclasses import dataclass, replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / "zig-out" / "bin"
OUT = Path(__file__).resolve().parent

# (file name, program, arguments)
SHOWCASES = [
    ("single-command", "zigma-basic", ["--name", "Zigma", "--loud"]),
    ("app-help", "zigma-advanced", ["--help"]),
    ("diagnostics", "zigma-advanced", ["hello", "--nme", "Zigma"]),
    ("widgets", "zigma-tui", []),
    ("tui-primitives", "zigma-advanced", ["dashboard"]),
]

FONT_SIZE = 14
CELL_W = 8.4
LINE_H = 20
PAD_X = 20
PAD_TOP = 52
PAD_BOTTOM = 20
MIN_COLS = 64

BACKGROUND = "#0d1117"
TITLE_BAR = "#161b22"
BORDER = "#30363d"
DEFAULT_FG = "#c9d1d9"
PROMPT = "#7ee787"
PALETTE = [
    "#484f58", "#ff7b72", "#3fb950", "#d29922", "#58a6ff", "#bc8cff", "#39c5cf", "#b1bac4",
    "#8b949e", "#ffa198", "#56d364", "#e3b341", "#79c0ff", "#d2a8ff", "#56d4dd", "#ffffff",
]

SGR = re.compile(r"\x1b\[([0-9;]*)m")


@dataclass(frozen=True)
class Style:
    fg: str = DEFAULT_FG
    bold: bool = False


def cell_width(ch: str) -> int:
    """Match Zigma's text.width: combining/format marks 0, wide East Asian 2."""
    if unicodedata.category(ch) in ("Mn", "Me", "Cf"):
        return 0
    return 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1


def apply_sgr(style: Style, params: str) -> Style:
    codes = [int(c) for c in params.split(";") if c] or [0]
    i = 0
    while i < len(codes):
        code = codes[i]
        if code == 0:
            style = Style()
        elif code == 1:
            style = replace(style, bold=True)
        elif code == 22:
            style = replace(style, bold=False)
        elif 30 <= code <= 37:
            style = replace(style, fg=PALETTE[code - 30])
        elif 90 <= code <= 97:
            style = replace(style, fg=PALETTE[code - 90 + 8])
        elif code == 39:
            style = replace(style, fg=DEFAULT_FG)
        elif code == 38 and i + 2 < len(codes) and codes[i + 1] == 5:
            style = replace(style, fg=PALETTE[codes[i + 2]] if codes[i + 2] < 16 else DEFAULT_FG)
            i += 2
        elif code == 38 and i + 4 < len(codes) and codes[i + 1] == 2:
            r, g, b = codes[i + 2 : i + 5]
            style = replace(style, fg=f"#{r:02x}{g:02x}{b:02x}")
            i += 4
        i += 1
    return style


def parse_line(line: str) -> list[tuple[int, str, Style]]:
    """Split a line into (column, word, style) runs, breaking at spaces and style changes."""
    runs: list[tuple[int, str, Style]] = []
    style = Style()
    col = 0
    word = ""
    word_col = 0
    word_style = style

    def flush() -> None:
        nonlocal word
        if word:
            runs.append((word_col, word, word_style))
        word = ""

    pos = 0
    for match in list(SGR.finditer(line)) + [None]:
        end = match.start() if match else len(line)
        for ch in line[pos:end]:
            if ch == " ":
                flush()
                col += 1
                continue
            if not word:
                word_col, word_style = col, style
            word += ch
            col += cell_width(ch)
        if match:
            flush()
            style = apply_sgr(style, match.group(1))
            pos = match.end()
    flush()
    return runs


def line_cells(line: str) -> int:
    return sum(cell_width(ch) for ch in SGR.sub("", line))


def word_cells(word: str) -> int:
    return sum(cell_width(ch) for ch in word)


def render_svg(command: str, output: str) -> str:
    lines = [f"$ {command}"] + output.rstrip("\n").split("\n")
    cols = max(MIN_COLS, max(line_cells(line) for line in lines) + 2)
    width = PAD_X * 2 + cols * CELL_W
    height = PAD_TOP + len(lines) * LINE_H + PAD_BOTTOM

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:.0f}" height="{height}" '
        f'viewBox="0 0 {width:.0f} {height}" role="img" aria-label="{html.escape(command)}">',
        f"<title>{html.escape(command)}</title>",
        f'<rect x="0.5" y="0.5" width="{width - 1:.0f}" height="{height - 1}" rx="10" '
        f'fill="{BACKGROUND}" stroke="{BORDER}"/>',
        f'<path d="M0.5 32V10.5a10 10 0 0 1 10-10h{width - 21:.0f}a10 10 0 0 1 10 10V32z" fill="{TITLE_BAR}"/>',
        f'<line x1="0.5" y1="32" x2="{width - 0.5:.0f}" y2="32" stroke="{BORDER}"/>',
        '<circle cx="20" cy="16" r="6" fill="#ff5f57"/>',
        '<circle cx="40" cy="16" r="6" fill="#febc2e"/>',
        '<circle cx="60" cy="16" r="6" fill="#28c840"/>',
        f'<g font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, \'Liberation Mono\', monospace" '
        f'font-size="{FONT_SIZE}">',
    ]
    for row, line in enumerate(lines):
        y = PAD_TOP + row * LINE_H + FONT_SIZE
        runs = parse_line(line)
        if row == 0:
            runs = [(c, w, Style(fg=PROMPT if c == 0 else DEFAULT_FG, bold=c == 0)) for c, w, _ in runs]
        for col, word, style in runs:
            x = PAD_X + col * CELL_W
            # textLength pins each run to its terminal cell width, so columns
            # stay aligned whatever monospace font the viewer falls back to.
            attrs = f'x="{x:.1f}" y="{y}" fill="{style.fg}"'
            cells = word_cells(word)
            if cells > 0:
                attrs += f' textLength="{cells * CELL_W:.1f}" lengthAdjust="spacingAndGlyphs"'
            if style.bold:
                attrs += ' font-weight="700"'
            parts.append(f"<text {attrs}>{html.escape(word)}</text>")
    parts.append("</g></svg>")
    return "\n".join(parts) + "\n"


def run_example(program: str, args: list[str]) -> str:
    exe = BIN / (program + (".exe" if os.name == "nt" else ""))
    if not exe.exists():
        sys.exit(f"missing {exe}; run `zig build install` first")
    env = dict(os.environ, CLICOLOR_FORCE="1", TERM="xterm-256color")
    env.pop("NO_COLOR", None)
    # Diagnostics exit non-zero by design; only stdout is rendered.
    result = subprocess.run([str(exe), *args], capture_output=True, env=env, cwd=ROOT)
    return result.stdout.decode("utf-8").replace("\r\n", "\n")


def main() -> None:
    for name, program, args in SHOWCASES:
        output = run_example(program, args)
        command = " ".join([program, *args])
        (OUT / f"{name}.svg").write_text(render_svg(command, output), encoding="utf-8", newline="\n")
        print(f"wrote docs/showcase/{name}.svg")


if __name__ == "__main__":
    main()
