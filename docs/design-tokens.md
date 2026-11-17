# Design tokens

Taken from the interactive prototype. Use these values through a single `ThemeData` and a `ThottamTokens` class; do not hard-code colours in widgets.

## Colour

| Token | Hex | Use |
| --- | --- | --- |
| ground | #F4F6F1 | Screen background |
| surface | #FFFFFF | Cards, sheets, nav bar |
| ink | #14201A | Primary text |
| muted | #56635B | Secondary text (passes 4.5:1 on surface and ground) |
| line | #DDE3DA | Borders |
| lineSoft | #ECEFEA | Dividers, bar tracks |
| primary | #1B6B3A | Primary buttons, active states, income bars |
| primaryDark | #0F3D22 | Dark cards, text on tints |
| primaryTint | #E9F3EB | Selected or positive backgrounds |
| primaryPill | #D5EBDA | Active tab pill, positive change chip |
| accent | #F2B01E | Highlights on dark cards, focus ring, pulse |
| accentTint | #FFF1C7 | Warm chips (text #6B4A00 or #3D2A00) |
| noticeBg / noticeLine | #FFF6DC / #EBCB73 | "Last time" and due banners |
| expense | #E08A1E | Expense bars |
| expenseTint | #FBEEDD | Expense backgrounds (text #8A4B00 or #6E4310) |
| negativeTint | #FBE3D2 | Low stock, price down (text #7A2E05) |
| danger | #B4440A | Destructive outline (text #8A3306) |
| infoTint | #E4ECF7 | Info banners, group tag (text #14335E or #1F4E8C) |
| switchOff | #8B978D | Switch track when off |
| toast | #14201A | Toast background, white text |

Income is green, expense is orange; always pair with a label or sign (+ / −), never colour alone.

## Type

- Headings and large numbers: **Anek Malayalam** 600/700.
- Body: **Inter** for Latin and digits, falling back to **Noto Sans Malayalam** for Malayalam (400/500/600/700).
- Tabular figures on for all amounts.

| Style | Size / weight |
| --- | --- |
| Display number | 40 / 700 |
| Screen title | 24 to 28 / 700 |
| Section title | 19 / 600 |
| Card title | 17 / 700 |
| Body | 15 to 16 / 400 or 600 |
| Caption | 13 to 14 / 400 |
| Tab label | 12 / 500 (700 when active) |

Malayalam line height 1.45 to 1.5. Large-text mode scales content by 1.12.

## Shape and spacing

- Screen padding 20; gap between cards 14; card padding 14 to 18.
- Radius: cards 18 to 22, buttons 16, chips 999, small tiles 12 to 15, bottom sheet 28 (top corners).
- Touch targets: minimum 44, primary buttons 58, list rows 56 to 68.
- Bottom nav 78 high, four tabs plus a centre add button (62, raised 34).

## Components

- **Primary button:** primary fill, white text, Anek Malayalam 18/600.
- **Outline button:** 1.5 border primary, text primaryDark.
- **Chip (choice):** pill, selected = primary fill and white text, unselected = white with #C3CBC1 border.
- **Segmented control:** track #E3E8E0, selected segment white with primaryDark text.
- **Switch:** 54 × 34, knob 28, track primary when on.
- **Stepper:** two 46 round outline buttons with a 26/700 number between.
- **Tint icon tile:** 40 to 52 square, radius 13 to 16, tinted background with matching dark icon.
- **Icons:** one line set, 24 grid, stroke 1.9 to 2, round caps and joins. Use an equivalent Flutter line icon set consistently.

## Motion

- Screen and list entry: fade plus 16 px rise, 320 to 420 ms, staggered 50 ms per item, curve (0.2, 0.8, 0.2, 1).
- Bottom sheet: slide up 360 ms, scrim fade 220 ms.
- Bars: grow from left 800 ms; width changes animate 450 ms.
- Switch knob 240 ms; buttons scale to 0.95 on press.
- Toast: pop in 320 ms, auto-dismiss after about 1.9 s.
- Add button and voice button: soft accent pulse.
- Respect the system "reduce motion" setting: disable all of the above.
