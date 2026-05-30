---
# DESIGN.md — visual identity for textus
# Format: https://github.com/google-labs-code/design.md (alpha)
# Direction: "Lanes" — the five zones as parallel write-lanes woven by one thread.
name: textus
version: 0.1.0
status: draft

tokens:
  colors:
    # Core neutrals — terminal-native
    ink: "#0E1116"        # near-black, primary foreground
    paper: "#FAFAF8"      # off-white, primary background
    muted: "#6B7280"      # slate, secondary text / labels
    line: "#E2E2DD"       # hairline rules, borders

    # Single brand accent
    signal: "#14B8A6"     # teal — the thread that merges lanes (review→promote)
    signalInk: "#0B7C72"  # darker teal for text-on-paper contrast (AA)

    # Zone palette — one muted hue per write-lane (docs, diagrams, badges)
    zoneIdentity: "#6B7280"  # human-authoritative
    zoneWorking: "#14B8A6"   # the daily fabric
    zoneIntake: "#D9882E"    # external data in
    zoneReview: "#8B7FD6"    # proposals awaiting accept
    zoneOutput: "#4F9D69"    # published artifacts

  typography:
    fontFamilyDisplay: "Geist Mono"        # mono-forward wordmark + headings
    fontFamilyBody: "Instrument Sans"      # prose
    fontFamilyMono: "Geist Mono"           # code / CLI
    weightRegular: 400
    weightMedium: 500
    weightBold: 700
    letterSpacingTight: "-0.01em"
    letterSpacingWide: "0.04em"            # for the lowercase wordmark
    scale:
      xs: "12px"
      sm: "14px"
      base: "16px"
      lg: "20px"
      xl: "28px"
      "2xl": "40px"
      "3xl": "56px"

  spacing:
    # 4px base grid — lanes align to it
    "1": "4px"
    "2": "8px"
    "3": "12px"
    "4": "16px"
    "6": "24px"
    "8": "32px"
    "12": "48px"
    "16": "64px"

  radius:
    none: "0px"
    sm: "2px"        # default — crisp, grid-aligned
    md: "4px"

  logo:
    grid: "24x24"            # mark designed on a 24-unit grid
    lanes: 5                 # one per zone, top→bottom: identity, working, intake, review, output
    laneHeight: "2u"
    laneGap: "3u"
    laneLengths: ["16u", "11u", "14u", "9u", "13u"]  # varying — left-aligned ragged
    thread:
      orientation: vertical
      x: "7u"               # single thread crossing all lanes (sits within the 9u shortest lane)
      width: "2u"
      color: "{colors.signal}"
    silhouette: "reads as lowercase 't' / '≡'"
    clearspace: "1 lane-height on all sides"
    minSize: "16px (favicon); thread may collapse to 1px below 24px"

  components:
    wordmark:
      text: "textus"
      case: lowercase
      fontFamily: "{typography.fontFamilyDisplay}"
      fontWeight: "{typography.weightMedium}"
      letterSpacing: "{typography.letterSpacingWide}"
      color: "{colors.ink}"
    badge:                  # zone badges in docs
      backgroundColor: "{colors.paper}"
      textColor: "{colors.muted}"
      borderColor: "{colors.line}"
      radius: "{radius.sm}"
      fontFamily: "{typography.fontFamilyMono}"
    codeBlock:
      backgroundColor: "{colors.ink}"
      textColor: "{colors.paper}"
      accent: "{colors.signal}"
      radius: "{radius.sm}"
    link:
      textColor: "{colors.signalInk}"
      hoverColor: "{colors.signal}"
---

# textus — visual identity

> Direction: **Lanes**. *textus* is the fabric a text is woven from. The identity
> renders the protocol literally: five separate write-lanes (the zones) held in
> parallel, with a single thread crossing through them — the review→promote move
> that weaves them into one durable fabric.

## Philosophy

textus is a developer tool first. The identity should read as **precise, systemic,
and terminal-native** — not decorative. Everything sits on a 4px grid; corners are
crisp (2px); type is mono-forward. Restraint is the brand: **one** accent color
(`signal` teal) does all the work, against near-black ink and off-white paper. The
teal is never decoration — it is always *the thread*: the thing that connects lanes,
the active state, the promotion. If a teal mark doesn't represent connection or
action, it shouldn't be teal.

The mark is the protocol diagram compressed into a glyph: five stacked, ragged
horizontal lanes (one per zone) pierced by a single vertical thread. At a glance it
reads as a lowercase **t** or an `≡`. It is honest — it shows what the tool *does*,
not a metaphor about it.

## The mark

- **Grid:** designed on 24×24 units. Reproduce by scaling the grid, never by eyeballing.
- **Lanes:** 5 horizontal bars, `2u` tall, `3u` apart, left-aligned with ragged right
  edges (`16u, 11u, 14u, 9u, 13u` top→bottom). The ragged edge signals "lanes of
  different content," not a justified block.
- **Thread:** one vertical bar at `x=8u`, `2u` wide, in `signal` teal, crossing all
  five lanes. This is the only color in the mark.
- **Color modes:**
  - *Default* — ink lanes on paper, teal thread.
  - *Dark* — paper lanes on ink, teal thread (thread stays teal in both).
  - *Mono* — all ink (or all paper) including the thread, for single-color contexts
    (stamps, embroidery, favicon ≤16px).
- **Clearspace:** keep at least one lane-height of empty space on all sides.
- **Minimum size:** 16px. Below 24px the thread may render at 1px; below 16px use the
  mono favicon.

## Wordmark

`textus`, always lowercase, in **Geist Mono Medium**, `letterSpacing: 0.04em`. Pair
the mark to the left of the wordmark at equal cap-height. Never restyle the letters,
never add a tagline inside the lockup.

## Color usage

| Token | Use |
|-------|-----|
| `ink` | text, lanes (light mode), code backgrounds |
| `paper` | backgrounds, lanes (dark mode) |
| `signal` | the thread, links (hover), active/CLI accents — *connection & action only* |
| `signalInk` | teal text on paper where AA contrast is required |
| `muted` | secondary text, labels, badge text |
| `zone*` | per-lane color coding in docs, diagrams, zone badges only |

The five `zone*` colors exist for documentation and diagrams (coloring each lane).
They are **not** part of the logo and must not appear in the mark.

## Typography

- **Display / wordmark / headings:** Geist Mono.
- **Body / prose:** Instrument Sans.
- **Code:** Geist Mono.

Mono-forward everywhere reinforces "this is a tool you run." Prose uses Instrument
Sans for readability in long-form docs.

## Don'ts

- No gradients, no drop shadows, no 3D, no skeuomorphic "fabric" textures.
- No second accent color. If you need to differentiate, use the `zone*` palette in
  docs — never in the mark.
- Don't justify the lanes into an even block (kills the "different lanes" read).
- Don't rotate, outline, or animate the wordmark letters.

## Asset matrix (to generate from this spec)

```
docs/assets/branding/
  logo.svg              # master, light mode (ink lanes + teal thread)
  logo-dark.svg         # dark mode (paper lanes + teal thread)
  logo-mono.svg         # single-color
  wordmark.svg          # mark + "textus" lockup
  favicon.svg
  favicon.ico           # 16/32/48
  favicon-32.png
  apple-touch-icon.png  # 180×180, paper bg
  icon-192.png
  icon-512.png
  og-image.png          # 1200×630 social card
```
