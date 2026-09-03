# House style: Elastic dark ops

Source: Elastic brand (`hive-elastic-brand-html` skill) reinterpreted onto a dark
operations canvas, plus the dark-mode Kibana screenshots this deck presents.
Tone: dark, data-forward, calm. Operations-room, not marketing hero.

Audience is UK public sector and non-technical. Copy carries the value; the
palette stays out of the way.

## Colour

| Role | Value | Notes |
| ---- | ----- | ----- |
| background | `#1C1E23` | Dark Ink. Slide canvas on every content slide |
| surface | `#252830` | Cards, panels, flow nodes |
| text | `#FFFFFF` | Headings and body |
| muted | `rgba(255,255,255,0.55)` | Subtitles, labels, sublabels |
| accent | `#48EFCF` | Light Teal. One accent. Punctuation, not fill |
| accent-text | `#0A2E28` | Text sitting on a teal chip |
| brand | `#0B64DD` | Elastic Blue. Cover/close canvas, 5px left bar |
| rule | `rgba(255,255,255,0.10)` | Hairlines, card borders, unplayed flow edges |

Cover and close invert: Elastic Blue canvas, white type, one teal rule. Teal is
used there as a graphic only (3.7:1 on blue) and never as small text.

Chart extras (charts and data callouts only, never as backgrounds or type):
Yellow `#FEC514`, Light Poppy `#FF957D`, Pink `#F04E98`.

Light Poppy is bound to one meaning in this deck: an emergency signal. It appears
only as the alert marker on `live-picture.html` (`--alert`). Do not reuse it
decoratively.

## Type

| Role | Family | Weights | Use |
| ---- | ------ | ------- | --- |
| display | Inter | 700-800 | Titles, node labels |
| body | Inter | 400 | Prose, subtitles, sublabels |
| numeric | Space Mono | 700 | Stats, codes, tabular figures |

Google Fonts URL:
`https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800&family=Space+Mono:wght@400;700&display=swap`

Mier B is the licensed Elastic headline face. It is deliberately **not** used or
shipped here; Inter Bold is the sanctioned fallback.

## Scale

- kicker: 13px / 700 / `0.22em` tracking / uppercase / accent
- h1 (cover): 68px / 800 / `-0.03em`
- h1 (content): 52px / 800 / `-0.02em`
- lede: 24px / 400 / muted / max-width 760px
- body: 20-22px / 400
- label: 15px / 600
- sublabel: 14px / 400 / muted
- stat: 108-136px / Space Mono 700 / accent

Never drop body type below 20px on this canvas.

## Chrome

- Canvas: 1280x720, pad-x 90px, pad-y 64px
- Device: 5px Elastic Blue bar down the left edge of every content slide
- Texture: none
- Radius: 8px on cards; 999px on chips
- Accent rule: 64x3px under the kicker or a card header. Never full-width

## Motion

- Keyframes: `up` = fade + `translateY(14px)`, 0.5s ease, `forwards`
- Stagger classes: `.f1` `.f2` `.f3` `.f4` at 0.10s / 0.25s / 0.40s / 0.55s
- Flow slide (`flow.html`) extends the same idea: `.n1`-`.n5` nodes and
  `.e1`-`.e4` edges on a single non-looping chain, all `forwards`, so the
  diagram settles and stays put while the presenter talks
- Entrances do not loop; each slide visit is a fresh iframe, so sequences replay
  for free. One exception, on `live-picture.html` only: the emergency pings and
  the movers running the tracks loop, because "live" is the point of that slide.
  Everything else there settles and stays put

## Layout kit

The first slide of each role is the kit. Clone the nearest role when adding a
slide; do not run `fslides add-slide --template` (its layouts are hardcoded to
a different palette and will desync the deck).

| Role | Kit file | When |
| ---- | -------- | ---- |
| Cover | `cover.html` | First slide. Blue canvas |
| Number | `problem.html` | One metric carries the argument |
| Grid | `analogue.html` | Three or four peer domains/ideas |
| Flow | `flow.html` | Sequenced pipeline, CSS boxes and bars |
| Figure | `live-picture.html` | Animated SVG diagram, a short claim, and a legend |
| Split | `context.html` | Two sides, one idea each |
| Point | `drill.html` | Narrative beat, heading plus prose |
| Panel | `explore.html` | Mocked product surface (question/answer, message) |
| Process | `triage.html` | Numbered steps, left to right |
| Close | `close.html` | Handover to the live system. Blue canvas |

## Do not

- Recreate Kibana chrome, nav bars, or marketing heroes as slides
- Use Developer Blue `#101C3F` as a background (outlines only, per brand)
- Use more than one accent; keep chart extras out of type
- Ship Mier B font files
- Use emoji, gradients, or full-width teal bars
- Put speaker notes on a slide (they live in `notes.json`)
- Name a slide `index.html` (the built player owns that name)
