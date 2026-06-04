#!/usr/bin/env python3
"""Generate textus brand SVGs from the DESIGN.md "Lanes" grid spec.

Single source of geometry: the 24-unit grid below. Everything (logo, dark,
mono, favicon, square icons, wordmark) is derived from `MARK`. Rasterization
to PNG/ICO and the OG image are handled by build.sh via ImageMagick.
"""
import pathlib

OUT = pathlib.Path(__file__).parent

# ---- tokens (mirror DESIGN.md) -------------------------------------------
INK    = "#0E1116"
PAPER  = "#FAFAF8"
SIGNAL = "#14B8A6"

# ---- mark geometry on a 24x24 grid ---------------------------------------
# five lanes (one per zone), left-aligned, ragged right edges
LANE_H = 2
LANES = [  # (y_top, width)
    (1, 16),   # identity
    (6, 11),   # working
    (11, 14),  # intake
    (16, 9),   # review
    (21, 13),  # output
]
THREAD_X, THREAD_W = 7, 2          # single vertical thread, crosses every lane
THREAD_Y, THREAD_H = 1, 22         # spans top lane .. bottom lane

# tight bounding box of all ink/thread content
BBOX_X0, BBOX_Y0 = 0, 1
BBOX_W,  BBOX_H  = 16, 22


def mark_rects(lane_fill, thread_fill):
    """Return the lane + thread <rect> elements (raw 24-grid coords)."""
    r = []
    for y, w in LANES:
        r.append(f'<rect x="0" y="{y}" width="{w}" height="{LANE_H}" fill="{lane_fill}"/>')
    # thread drawn last so it weaves over the lanes
    r.append(f'<rect x="{THREAD_X}" y="{THREAD_Y}" width="{THREAD_W}" '
             f'height="{THREAD_H}" fill="{thread_fill}"/>')
    return "\n  ".join(r)


def svg(view, body, extra_attrs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}" '
            f'{extra_attrs}>\n  {body}\n</svg>\n')


def write(name, content):
    (OUT / name).write_text(content)
    print(f"  wrote {name}")


# ---- rectangular logo (mark only) ----------------------------------------
PAD = 2
RECT_VIEW = f"{BBOX_X0-PAD} {BBOX_Y0-PAD} {BBOX_W+2*PAD} {BBOX_H+2*PAD}"

# ---- square icon view (mark centered) ------------------------------------
CX = BBOX_X0 + BBOX_W / 2          # 8
CY = BBOX_Y0 + BBOX_H / 2          # 12
SQ_PAD = 2
HALF = max(BBOX_W, BBOX_H) / 2 + SQ_PAD   # 13
SQ_VIEW = f"{CX-HALF:g} {CY-HALF:g} {2*HALF:g} {2*HALF:g}"   # -5 -1 26 26


def main():
    print("generating SVGs from grid spec…")

    # 1. logo.svg — light: ink lanes, teal thread, transparent bg
    write("logo.svg", svg(RECT_VIEW, mark_rects(INK, SIGNAL)))

    # 2. logo-dark.svg — paper lanes, teal thread (for dark surfaces)
    write("logo-dark.svg", svg(RECT_VIEW, mark_rects(PAPER, SIGNAL)))

    # 3. logo-mono.svg — single colour via currentColor (defaults to ink)
    write("logo-mono.svg",
          svg(RECT_VIEW, mark_rects("currentColor", "currentColor"),
              'fill="currentColor" color="#0E1116"'))

    # 4. favicon.svg — square, transparent
    write("favicon.svg", svg(SQ_VIEW, mark_rects(INK, SIGNAL)))

    # 5. square master with paper bg (source for apple-touch / 192 / 512 / og)
    bg = (f'<rect x="{CX-HALF:g}" y="{CY-HALF:g}" width="{2*HALF:g}" '
          f'height="{2*HALF:g}" fill="{PAPER}"/>\n  ')
    write("icon-square-paper.svg", svg(SQ_VIEW, bg + mark_rects(INK, SIGNAL)))

    # 6. square master transparent (for PNG icons on arbitrary bg)
    write("icon-square.svg", svg(SQ_VIEW, mark_rects(INK, SIGNAL)))

    # 7. wordmark.svg — mark + "textus" in embedded Geist Mono, portable
    font_b64 = _font_data_uri()
    write("wordmark.svg", _wordmark_svg(font_b64, INK, INK))        # light
    write("wordmark-dark.svg", _wordmark_svg(font_b64, PAPER, PAPER))  # dark

    print("done.")


def _font_data_uri():
    import base64
    fp = pathlib.Path(
        "/Users/nqhuy25/.claude/plugins/marketplaces/patrick-nexus/plugins/"
        "patrick/skills/vendor/anthropic/canvas-design/canvas-fonts/"
        "GeistMono-Regular.ttf")
    b = base64.b64encode(fp.read_bytes()).decode()
    return f"data:font/ttf;base64,{b}"


def _wordmark_svg(font_uri, lane_fill, text_fill):
    # layout: mark (height 26) on left, gap, then "textus"
    H = 26
    scale = H / (BBOX_H + 2 * PAD)            # fit rect logo height into H
    mark_w = (BBOX_W + 2 * PAD) * scale
    gap = 8
    fs = 18                                    # font-size for wordmark
    text_x = mark_w + gap
    total_w = text_x + 6 * fs * 0.62 + 4       # 6 mono glyphs ~0.62em
    # mark group: translate so rect-view origin maps to 0,0 then scale
    tx = -(BBOX_X0 - PAD) * scale
    ty = -(BBOX_Y0 - PAD) * scale
    style = (f'<style>@font-face{{font-family:"Geist Mono";'
             f'src:url({font_uri}) format("truetype");font-weight:400;}}</style>')
    g = (f'<g transform="translate({tx:g},{ty:g}) scale({scale:g})">'
         f'{mark_rects(lane_fill, SIGNAL)}</g>')
    txt = (f'<text x="{text_x:g}" y="{H*0.72:g}" font-family="Geist Mono,monospace" '
           f'font-size="{fs}" letter-spacing="0.04em" fill="{text_fill}">textus</text>')
    return svg(f"0 0 {total_w:g} {H}",
               f"{style}\n  {g}\n  {txt}",
               'width="{:g}" height="{}"'.format(total_w, H))


if __name__ == "__main__":
    main()
