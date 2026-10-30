# MacDoats — Logo Guidelines

## 1. The logo
- **Idea:** the DotA 1 Necronomicon with ⌘ as its cover sigil. Your old item, bound to Mac keys.
- **Two drawings, one mark:**
  - **Flat mark** (`macdoats-symbol*.svg`): menu bar, favicon, lockups, one-colour uses.
  - **Detailed tome** (`macdoats-appicon.svg`, `MacDoats.icns`): the app icon only. It shows the book from
    below with the spine, page block and ribbon.
- **Versions:** horizontal lockup · stacked lockup · symbol · small-size symbol (`-small`, ≤ 32 px) · wordmark.
- **Files:** `export/` holds the SVGs, 1200 px PNGs, `MacDoats.icns`, and `web/` (favicon.ico, PNG icons,
  webmanifest, `<head>` snippet).
- **Source:** `build.py` (flat mark), `illus.py` (app icon, needs `shapely`), `wordmark.py` (lockups, needs `fonttools` + `uharfbuzz` and Inter). Edit these, never the exports.

## 2. Clear space
Keep a clear zone of **1 × the ⌘ loop** (the outer diameter of one ⌘ loop) on all sides. It scales with the logo.

## 3. Minimum size
| Version | Screen |
|---|---|
| Horizontal lockup | 96 px wide |
| Stacked lockup | 64 px wide |
| Symbol | 24 px (use `-small` from 32 px down to 16 px) |
| Menu bar | 18 pt template glyph (`Sources/Icon.swift`, mirrors the small cut) |

## 4. Colour
| Name | HEX | RGB | CMYK (approx.) |
|---|---|---|---|
| Dota Red | #B8312A | 184 49 42 | 0 73 77 28 |
| Dota Gold | #E0C387 | 224 195 135 | 0 13 40 12 |
| Mac Ink | #15181C | 21 24 28 | 25 14 0 89 |

The app icon also uses darker reds (#8E2520, #6A1814), a darker gold (#B98E45) and page cream (#EAD9B2)
for depth. Don't use these anywhere else.

**Approved pairs:**
- Colour symbol on white or on Mac Ink.
- Black on white.
- White on Mac Ink or Dota Red.
- Gold on Mac Ink.

## 5. Typography
- **Wordmark:** Inter SemiBold (opsz 32), tracked −1.2 %, outlined to paths. Never retype it.
- **Text:** the system font (SF Pro) inside the app; Inter on the web.
- **Licence:** Inter is under the SIL Open Font License, which allows logo use.

## 6. Don'ts
- Don't straighten the tilt (it's −15°) or flip the book.
- Don't use the detailed tome below 64 px, or the flat mark as the app icon.
- Don't recolour outside the palette.
- Don't add shadows, outlines or effects to the flat mark.
- Don't move the ⌘ off-centre, or swap it for another glyph.
- Don't rearrange or resize the parts of a lockup.

## 7. Notes
- **Trademarks:** Dota 2 and DotA are Valve's. The mark avoids their shield, but run a trademark check and a
  reverse-image search before any public release.
- **Tests run:**
  - svg_audit scored 100/100 for both flat masters.
  - Renders checked at 16, 32, 64 and 96 px, one-colour and reversed.
  - The menu-bar glyph was rendered from the Swift code.
