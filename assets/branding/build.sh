#!/usr/bin/env bash
# Rasterize textus brand assets from the generated SVGs.
# Requires: python3, ImageMagick 7 (magick). Run from this directory.
set -euo pipefail
cd "$(dirname "$0")"

FONT="/Users/nqhuy25/.claude/plugins/marketplaces/patrick-nexus/plugins/patrick/skills/vendor/anthropic/canvas-design/canvas-fonts/GeistMono-Regular.ttf"
INK="#0E1116"; PAPER="#FAFAF8"; MUTED="#6B7280"
R="magick -background none -depth 8"

echo "1/6 regenerating SVGs"
python3 build_assets.py >/dev/null

echo "2/6 favicons (transparent)"
for s in 16 32 48; do $R favicon.svg -resize ${s}x${s} favicon-${s}.png; done
magick favicon-16.png favicon-32.png favicon-48.png favicon.ico
echo "   favicon.ico ← 16/32/48"

echo "3/6 square PNG icons (paper bg)"
$R icon-square-paper.svg -resize 180x180 apple-touch-icon.png
$R icon-square-paper.svg -resize 192x192 icon-192.png
$R icon-square-paper.svg -resize 512x512 icon-512.png

echo "4/6 transparent maskable variants"
$R icon-square.svg -resize 512x512 icon-512-transparent.png

echo "5/6 wordmark.png (mark + Geist Mono), light + dark"
build_wordmark () {  # $1=mark-svg $2=text-color $3=out
  $R "$1" -resize x220 /tmp/_mark.png
  magick -background none -fill "$2" -font "$FONT" -pointsize 200 -kerning 8 \
         label:"textus" /tmp/_txt.png
  magick /tmp/_mark.png /tmp/_txt.png -background none -gravity Center +smush 36 \
         -bordercolor none -border 28 -depth 8 "$3"
}
build_wordmark logo.svg      "$INK"   wordmark.png
build_wordmark logo-dark.svg "$PAPER" wordmark-dark.png

echo "6/6 og-image.png (1200x630)"
# lockup ~640px wide, centered slightly above middle; tagline below in muted mono
magick wordmark.png -resize 660x og-lockup.png
magick -size 1200x630 xc:"$PAPER" \
  og-lockup.png -gravity Center -geometry +0-26 -composite \
  -font "$FONT" -pointsize 30 -fill "$MUTED" -kerning 2 \
  -gravity Center -annotate +0+96 "durable, multi-writer context for code" \
  -depth 8 og-image.png
rm -f og-lockup.png

echo "cleaning intermediates"
rm -f icon-square.svg icon-square-paper.svg /tmp/_mark.png /tmp/_txt.png

echo "done. artifacts:"
ls -1 *.svg *.png *.ico | sort
