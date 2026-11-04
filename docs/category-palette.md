# Category palette: records, measurements and derivation targets

Status: designer deliverable for redesign Story 2 (#12) and feedback-plan task 3.3. Input to
ADR 005 (palette plus custom colour) and to `CategoryPalette` (#1 task 3.4) and `DerivationTargets.measured`
(#1 task 3.3b). No app code is changed by this document.

Written 2026-11-04. Every number below was computed by hand (no shell was available). Read
"How these were measured" before trusting any single digit.

## 0. Decisions in one screen

- Twelve swatches. Slots 0 to 5 are the six built-ins, in their existing order, so a stored
  `paletteIndex` for a built-in does not change meaning. Slots 6 to 11 are new.
- Each swatch is one record per mode: `spine`, `fill`, `border`, `onFill`, all `#RRGGBB` sRGB.
- `onFill` is the mode's ink: `#000000` in light, `#FFFFFF` in dark (the `.primary` value). It is the
  same for all twelve, so it is not repeated in the swatch table.
- `admin` becomes teal (finding M9). It no longer shares a colour family with meetings.
- Light fills sit at CIELAB L* 81 to 87 and dark fills at L* 28 to 34. That narrow band is deliberate: it is
  what lets a derived custom colour sit beside the curated ones.
- Every floor in ADR 005 passes for all twelve swatches in both modes, by hand measurement.
  Margins are thin in three places, listed in section 3.6.
- The weakest pair under normal vision is Teal and Sky in light mode (ΔE 11.6 against a floor of 10).
  Colour-blind results are in section 3.5 and are weaker, as the epic plan expected.

## 1. Surfaces assumed

Story 1 has not published the canvas yet, so these are my assumptions. If Story 1 picks different
values, rerun the checks (the qa test does this for free once `SRGB` and `CategoryColorMath` exist).

| Surface | Light | Dark | Basis |
|---|---|---|---|
| `canvas` | `#FAF8F5` | `#1C1C1E` | Dark is the value `docs/design-review.md` section 5 measured against. Light is the "soft off-white" of the epic plan. |
| `meetingFill` | `#EEECE9` | `#2A2A2C` | `Color.primary` at 5 percent (light) and 6 percent (dark), the alphas at `TimelineCanvas.swift:462`, composited over the canvas in sRGB space and rounded to bytes. Light: black 5 percent over `#FAF8F5`. Dark: white 6 percent over `#1C1C1E`. |

CIELAB (D65) of the surfaces: canvas light (97.7, 0.1, 1.7), canvas dark (10.5, 0.5, -1.2), meeting light
(93.5, 0.1, 1.7), meeting dark (17.1, 0.5, -1.3). Relative luminance Y: 0.9405, 0.01187, 0.8405, 0.02329.

## 2. The twelve swatches

Palette order is the order of `paletteIndex`. Names are working titles for the picker's VoiceOver
labels; the editor shows swatches without text.

### 2.1 Light mode

| # | Name | Built-in | spine | fill | border |
|---|---|---|---|---|---|
| 0 | Blue | deep | `#4664DC` | `#C8D2FA` | `#5A78E6` |
| 1 | Orange | meeting | `#D26428` | `#FAC8A0` | `#D26E32` |
| 2 | Teal | admin | `#1E8C96` | `#A0DCE6` | `#3296A0` |
| 3 | Green | personal | `#3C965A` | `#AADCAA` | `#469664` |
| 4 | Pink | health | `#D25082` | `#FABED2` | `#DC648C` |
| 5 | Violet | rest | `#826EB4` | `#DCBEF0` | `#9682BE` |
| 6 | Red | new | `#D2463C` | `#FAC8BE` | `#DC5A50` |
| 7 | Gold | new | `#A07800` | `#E6D278` | `#AA8214` |
| 8 | Lime | new | `#648C1E` | `#C8DC82` | `#6E9628` |
| 9 | Mint | new | `#149678` | `#A0E6C8` | `#1E9678` |
| 10 | Sky | new | `#1E82C8` | `#AADCFA` | `#288CD2` |
| 11 | Plum | new | `#B446AA` | `#FAB4F0` | `#BE5AB4` |

### 2.2 Dark mode

| # | Name | spine | fill | border |
|---|---|---|---|---|
| 0 | Blue | `#82A0FA` | `#284682` | `#506EBE` |
| 1 | Orange | `#FAA06E` | `#6E3C1E` | `#B46E46` |
| 2 | Teal | `#5AC8D2` | `#145064` | `#328CA0` |
| 3 | Green | `#6ED28C` | `#1E5A32` | `#46965A` |
| 4 | Pink | `#FA8CB4` | `#82325A` | `#BE5A82` |
| 5 | Violet | `#BEAAFA` | `#5A3C82` | `#8C6EBE` |
| 6 | Red | `#FA786E` | `#783232` | `#BE5A50` |
| 7 | Gold | `#E6BE3C` | `#5A5014` | `#A08228` |
| 8 | Lime | `#AAD246` | `#46501E` | `#789632` |
| 9 | Mint | `#50D2B4` | `#145046` | `#328C78` |
| 10 | Sky | `#64B4FA` | `#145078` | `#3C82BE` |
| 11 | Plum | `#E68CE6` | `#783278` | `#AA5AAA` |

### 2.3 Role logic (so a future swatch can be authored the same way)

| Role | Light | Dark |
|---|---|---|
| `spine` | The full category colour. Dark enough for at least 3.4:1 on canvas. Close to the existing tint. | The existing "lifted" tint, bright (6.4:1 or more on canvas). |
| `fill` | Pale tint, opaque. Luminance ratio to canvas of at least 1.35. | Deep tint, opaque, brighter than the meeting fill. Luminance ratio to canvas of at least 1.8. |
| `border` | Spine moved a little toward the fill, held above 3:1. In light this leaves very little room, so border and spine are close. | Roughly midway between spine and fill, 3.5:1 or more. |
| `onFill` | `#000000` | `#FFFFFF` |

### 2.4 What changed from the six current tints (`BlockCategory.swift:68-77`)

Hue identity is kept for five of six. Values are the old ones rounded to the nearest 10 per channel, except:

| Built-in | Light spine, old to new | Dark spine, old to new | Why |
|---|---|---|---|
| deep | (74,102,222) to `#4664DC` | (133,158,255) to `#82A0FA` | Rounding only. |
| meeting | (217,107,61) to `#D26428` | (255,158,107) to `#FAA06E` | Light spine darkened and made redder so the 1pt border can stay above 3:1 with margin. Still orange. |
| admin | grey-blue (102,112,138) to teal `#1E8C96` | grey-blue (168,181,209) to teal `#5AC8D2` | Finding M9. The grey was the app's word for "fixed, not yours". |
| personal | (61,153,92) to `#3C965A` | (112,212,143) to `#6ED28C` | Rounding only. |
| health | (212,84,130) to `#D25082` | (255,140,181) to `#FA8CB4` | Rounding only. |
| rest | (133,112,184) to `#826EB4` | (189,168,242) to `#BEAAFA` | Rounding only. |

Fills and borders are new values, not alpha math. The old chip fill was the tint at 16 to 30 percent alpha
over whatever was behind it, which is why hour rules showed through (M9).

The rounding to multiples of 10 is a measurement convenience (it let one linearisation table serve every
colour). It is not a design rule. A later swatch may use any byte.

### 2.5 Slot and hash notes for #1 task 3.4

- Indices 0 to 5 keep today's meaning: deep, meeting, admin, personal, health, rest. Indices 6 to 11 are
  Red, Gold, Lime, Mint, Sky, Plum.
- This is not hue order. The picker should present them in hue order: Red, Orange, Gold, Lime, Green, Mint,
  Teal, Sky, Blue, Violet, Plum, Pink. That is a display permutation in `CategoryPalette`, not a change
  to what an index means.
- The FNV-1a stand-in colour is `hash mod 12`. The pinned test value in ADR 005 will change from `mod 6`
  semantics only for unknown slugs, which have no stored colour to lose.

## 3. Measurements

### 3.1 How these were measured

Same methods as `docs/design-review.md` (M9, M10), as ADR 005 requires.

1. **Contrast ratio** (WCAG 2). Linearise each byte: `c = v/255`; if `c <= 0.04045` then `c/12.92`, else
   `((c + 0.055)/1.055)^2.4`. Luminance `Y = 0.2126 R + 0.7152 G + 0.0722 B` on the linear values. Ratio
   is `(Y_lighter + 0.05) / (Y_darker + 0.05)`.
2. **CIELAB ΔE76.** From the linear values: `X = 0.4124 R + 0.3576 G + 0.1805 B`, `Z = 0.0193 R + 0.1192 G
   + 0.9505 B`, white `(0.95047, 1, 1.08883)`. Then `f(t) = cbrt(t)` for `t > 0.008856` (every colour here
   is above it). `L* = 116 f(Y) - 16`, `a* = 500 (f(X/Xn) - f(Y))`, `b* = 200 (f(Y) - f(Z/Zn))`.
   ΔE76 is the Euclidean distance in (L*, a*, b*).
3. **Worked example, the Orange light fill `#FAC8A0` (250, 200, 160).** Linear (0.9560, 0.5776, 0.3515).
   `X = 0.6642`, `Y = 0.6417`, `Z = 0.4214`. Ratios to white: `X/Xn = 0.6988`, `Z/Zn = 0.3870`. Cube roots
   0.8874, 0.8626, 0.7288. So L* = 84.06, a* = 12.43, b* = 26.76.
4. **Cube roots** were done by a Newton step from a table of known roots, with a second-order correction.
   Channels were limited to multiples of 10 so one linearisation table covered everything; the canvas
   bytes 248 and 245 were linearised directly.
5. **Tolerance.** I estimate ±0.2 on L*, ±0.3 on a* and b*, so ±0.5 on a ΔE, and ±0.02 on a contrast
   ratio. A figure within 0.5 of a floor should be treated as a tie. **Nothing here was run by a machine.**
   The qa test (Story 2, qa task) must recompute every number from the hex values; where it disagrees with
   this document by more than the tolerance, the test is right and this document has an arithmetic error.

### 3.2 Per-swatch floors, light mode

Floors from ADR 005: spine and border on canvas at least 3:1; fill on canvas at least ΔE 8 and 1.3:1;
`onFill` on fill at least 4.5:1 (aim 7:1); fill against meeting fill at least ΔE 15.

| Swatch | spine:canvas | border:canvas | fill ΔE to canvas | fill:canvas ratio | onFill:fill | fill ΔE to meeting | fill C* |
|---|---|---|---|---|---|---|---|
| Blue | 4.81 | 3.76 | 26.3 | 1.41 | 14.1 | 24.6 | 21.2 |
| Orange | 3.54 | 3.29 | 31.1 | 1.43 | 13.8 | 29.5 | 29.5 |
| Teal | 3.77 | 3.30 | 25.0 | 1.43 | 13.9 | 23.0 | 20.0 |
| Green | 3.47 | 3.41 | 34.5 | 1.47 | 13.5 | 33.0 | 32.3 |
| Pink | 3.80 | 3.17 | 28.8 | 1.48 | 13.4 | 26.8 | 24.6 |
| Violet | 4.10 | 3.18 | 34.2 | 1.56 | 12.7 | 32.4 | 28.6 |
| Red | 4.23 | 3.52 | 23.1 | 1.41 | 14.1 | 21.0 | 20.1 |
| Gold | 3.82 | 3.35 | 47.4 | 1.43 | 13.9 | 46.4 | 47.1 |
| Lime | 3.73 | 3.27 | 47.1 | 1.41 | 14.0 | 46.1 | 46.7 |
| Mint | 3.50 | 3.48 | 31.1 | 1.35 | 14.7 | 29.8 | 29.1 |
| Sky | 3.90 | 3.43 | 26.5 | 1.38 | 14.3 | 24.8 | 21.8 |
| Plum | 4.50 | 3.73 | 43.9 | 1.54 | 12.9 | 42.5 | 40.0 |
| **Minimum** | 3.47 (Green) | 3.17 (Pink) | 23.1 (Red) | 1.35 (Mint) | 12.7 (Violet) | 21.0 (Red) | 20.0 (Teal) |

CIELAB of the light fills (L*, a*, b*): Blue (84.6, 4.8, -20.7), Orange (84.1, 12.4, 26.8), Teal
(84.2, -16.7, -11.0), Green (83.3, -25.8, 19.4), Pink (82.8, 24.5, -1.6), Violet (80.9, 19.7, -20.8),
Red (84.7, 16.4, 11.7), Gold (84.1, -4.8, 46.9), Lime (84.5, -20.6, 41.9), Mint (86.1, -28.1, 7.7),
Sky (85.3, -9.2, -19.8), Plum (81.4, 34.7, -19.8).

### 3.3 Per-swatch floors, dark mode

| Swatch | spine:canvas | border:canvas | fill ΔE to canvas | fill:canvas ratio | onFill:fill | fill ΔE to meeting | fill C* |
|---|---|---|---|---|---|---|---|
| Blue | 6.75 | 3.48 | 42.3 | 1.85 | 9.2 | 39.7 | 38.5 |
| Orange | 8.34 | 4.25 | 40.0 | 1.88 | 9.0 | 37.1 | 33.6 |
| Teal | 8.59 | 4.36 | 28.7 | 1.91 | 8.9 | 24.2 | 20.4 |
| Green | 9.10 | 4.67 | 42.2 | 2.07 | 8.2 | 39.0 | 34.2 |
| Pink | 7.66 | 4.02 | 45.0 | 2.07 | 8.2 | 42.0 | 39.3 |
| Violet | 8.34 | 4.11 | 48.8 | 1.94 | 8.7 | 46.2 | 45.2 |
| Red | 6.45 | 3.85 | 39.8 | 1.86 | 9.1 | 36.9 | 34.2 |
| Gold | 9.53 | 4.62 | 43.2 | 2.10 | 8.1 | 40.1 | 35.1 |
| Lime | 9.71 | 5.02 | 38.3 | 1.96 | 8.7 | 35.1 | 30.3 |
| Mint | 9.07 | 4.16 | 29.6 | 1.83 | 9.3 | 25.8 | 21.6 |
| Sky | 7.64 | 4.14 | 34.8 | 1.98 | 8.6 | 31.0 | 28.2 |
| Plum | 7.48 | 3.84 | 52.5 | 2.04 | 8.3 | 49.9 | 48.4 |
| **Minimum** | 6.45 (Red) | 3.48 (Blue) | 28.7 (Teal) | 1.83 (Mint) | 8.1 (Gold) | 24.2 (Teal) | 20.4 (Teal) |

CIELAB of the dark fills: Blue (30.5, 10.1, -37.2), Orange (31.0, 19.2, 27.6), Teal (31.4, -11.2, -17.0),
Green (33.6, -29.4, 17.5), Pink (33.5, 38.8, -6.5), Violet (31.8, 28.8, -34.8), Red (30.7, 30.6, 15.2),
Gold (33.9, -3.4, 34.9), Lime (32.1, -12.5, 27.6), Mint (30.2, -21.6, 0.4), Sky (32.4, -3.5, -28.0),
Plum (33.2, 40.7, -26.1).

In dark mode the meeting fill (L* 17.1) is dimmer than every block fill (L* 30 to 34), so the M10
inversion stays fixed. Meeting C* is 1.4 in both modes.

### 3.4 Pairwise ΔE76 between fills, all 66 pairs, normal vision

Floor is 10. Upper triangle, row swatch against column swatch. Order: Blue, Orange, Teal, Green, Pink,
Violet, Red, Gold, Lime, Mint, Sky, Plum. Entries under 15 are in bold.

**Light**

| | Orange | Teal | Green | Pink | Violet | Red | Gold | Lime | Mint | Sky | Plum |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Blue** | 48.1 | 23.6 | 50.4 | 27.5 | 15.4 | 34.4 | 68.3 | 67.6 | 43.5 | **14.0** | 30.1 |
| **Orange** | | 47.7 | 38.9 | 30.9 | 48.2 | 15.7 | 26.5 | 36.3 | 44.8 | 51.4 | 51.7 |
| **Teal** | | | 31.8 | 42.3 | 37.8 | 40.1 | 59.1 | 53.0 | 22.0 | **11.6** | 52.2 |
| **Green** | | | | 54.5 | 60.8 | 42.9 | 34.6 | 23.1 | **12.3** | 42.6 | 72.1 |
| **Pink** | | | | | 19.8 | 15.7 | 56.7 | 62.7 | 53.5 | 38.4 | 20.9 |
| **Violet** | | | | | | 32.9 | 72.1 | 74.6 | 55.9 | 29.2 | 15.0 |
| **Red** | | | | | | | 41.1 | 47.8 | 44.7 | 40.6 | 36.6 |
| **Gold** | | | | | | | | 16.6 | 45.6 | 66.8 | 77.6 |
| **Lime** | | | | | | | | | 35.0 | 62.8 | 83.0 |
| **Mint** | | | | | | | | | | 33.4 | 68.7 |
| **Sky** | | | | | | | | | | | 44.1 |

Light minimum: **Teal and Sky, 11.6.** Next: Green and Mint 12.3, Sky and Blue 14.0.

**Dark**

| | Orange | Teal | Green | Pink | Violet | Red | Gold | Lime | Mint | Sky | Plum |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Blue** | 65.4 | 29.4 | 67.5 | 42.1 | 18.9 | 56.3 | 73.4 | 68.6 | 49.2 | 16.6 | 32.7 |
| **Orange** | | 54.0 | 49.7 | 39.4 | 63.2 | 16.9 | 23.9 | 31.7 | 49.0 | 60.1 | 57.9 |
| **Teal** | | | 39.2 | 51.2 | 43.8 | 52.8 | 52.5 | 44.6 | 20.4 | **13.5** | 52.7 |
| **Green** | | | | 72.3 | 78.4 | 60.1 | 31.3 | 19.7 | 19.1 | 52.4 | 82.6 |
| **Pink** | | | | | 30.0 | 23.4 | 59.1 | 61.6 | 60.8 | 47.5 | 19.7 |
| **Violet** | | | | | | 50.0 | 76.8 | 74.8 | 61.5 | 33.0 | **14.8** |
| **Red** | | | | | | | 39.4 | 44.9 | 54.3 | 55.1 | 42.6 |
| **Gold** | | | | | | | | **11.8** | 39.2 | 62.9 | 75.3 |
| **Lime** | | | | | | | | | 28.8 | 56.3 | 75.6 |
| **Mint** | | | | | | | | | | 33.8 | 67.8 |
| **Sky** | | | | | | | | | | | 44.2 |

Dark minimum: **Gold and Lime, 11.8.** Next: Teal and Sky 13.5, Violet and Plum 14.8.

Both modes clear the floor of 10. The overall weakest pair under normal vision is Teal and Sky in light
mode at 11.6, a margin of about 1.6 over the floor, which is three times my stated tolerance.

### 3.5 Colour-blind approximation (light fills only)

**This is an approximation, not a clinical result.** I applied the Machado, Oliveira and Fernandes (2009)
dichromacy matrices at severity 1.0 to the linear RGB of each light fill, then took CIELAB and ΔE76 as
above. The matrices are written from memory of the paper, not checked against a source in this session.
A simulation is a model of one kind of deficiency, not a person. Dark fills were **not** simulated (see
section 6). I screened all 66 pairs by lightness and the blue-yellow axis (the axis that survives both
deficiencies), then ran the full simulation on the 24 swatch-mode combinations; the table lists every pair
that came out under 10 in either deficiency, plus its normal-vision value. I did not tabulate all 132
simulated pair values.

Floor in the epic plan: best effort 6 under deuteranopia and protanopia, backed by the glyph.

| Pair (light fills) | Normal | Deuteranopia | Protanopia | Under 6? |
|---|---|---|---|---|
| **Blue and Sky** | 14.0 | **0.4** | 3.4 | both |
| Violet and Plum | 15.0 | 3.1 | 2.0 | both |
| Blue and Violet | 15.4 | 3.1 | 5.7 | both |
| Orange and Green | 38.9 | 11.2 | 3.1 | protanopia |
| Gold and Lime | 16.6 | 6.1 | 3.3 | protanopia (deuteranopia at the line) |
| Sky and Violet | 29.2 | 3.3 | 8.8 | deuteranopia |
| Blue and Plum | 30.1 | 4.2 | 7.5 | deuteranopia |
| Sky and Plum | 44.1 | 4.6 | 10.7 | deuteranopia |
| Plum and Teal | 52.2 | 4.1 | 18.0 | deuteranopia |
| Pink and Mint | 53.5 | 4.7 | 18.9 | deuteranopia |
| Red and Green | 42.9 | 5.3 | 14.4 | deuteranopia |
| Violet and Teal | 37.8 | 7.0 | 16.1 | no |
| Red and Mint | 44.7 | 8.4 | 6.0 | no (protanopia at the line) |
| Teal and Pink | 42.3 | 13.9 | 6.0 | no (protanopia at the line) |
| Blue and Teal | 23.6 | 8.2 | 12.4 | no |
| Sky and Teal | 11.6 | 8.6 | 9.5 | no |

Reading it:

- **Weakest pair overall: Blue and Sky.** Under deuteranopia they differ by about 0.4, which is the same
  colour for practical purposes. Both are cool, mid-light fills whose only difference is a red-green
  tilt.
- The cool cluster Blue, Sky, Violet, Plum (and Teal near it) collapses into one family under both
  deficiencies. That is structural: four hues inside one 60 degree arc cannot be separated by hue for
  a red-green-deficient viewer at one fixed lightness.
- Nine pairs fall under 6 for deuteranopia and five for protanopia. The glyph is the real distinguishing
  channel, as the plan says. I would not try to fix this by retuning colours.

**Recommendation.** Sky is the most redundant swatch: dropping it removes the weakest pair and three more
under-6 deuteranopia pairs, and it is also the weakest pair under normal vision (with Teal). If the
owner does not need twelve, ship eleven. This is a provisional swatch; keep it in the data until the
owner answers one question: does the owner have a colour-vision deficiency? This is a one-person app, and
if not, these rows matter only as a general legibility cost, and the required emoji already carries them.

### 3.6 Margins and what would break them

| Floor | Tightest swatch | Value | Floor | Margin |
|---|---|---|---|---|
| Border:canvas, light | Pink | 3.17 | 3.0 | 0.17 |
| Border:canvas, light | Violet | 3.18 | 3.0 | 0.18 |
| Fill:canvas luminance, light | Mint | 1.35 | 1.3 | 0.05 |
| Fill pairwise ΔE, light | Teal and Sky | 11.6 | 10 | 1.6 |
| Fill pairwise ΔE, dark | Gold and Lime | 11.8 | 10 | 1.8 |
| Border:canvas, dark | Blue | 3.48 | 3.0 | 0.48 |

Every other margin is larger. Two dependencies to carry into Story 1:

- **The light canvas must stay lighter than about L* 96** (relative luminance 0.90, roughly `#F6F4F0`).
  Below that, Mint's fill drops under the 1.3:1 luminance floor. A pure white canvas improves every ratio.
- **The meeting fill must stay grey.** All margins against it are 6 or more ΔE, but they assume C* of
  about 1.5. If Story 3 gives the meeting chip a tint, rerun section 3.2 and 3.3.

## 4. DerivationTargets for derived custom colours

A custom pick contributes OKLCH **hue and chroma**. Lightness comes from the table below. Chroma for a
role is `min(cap, factor * C_pick)`, then reduced by gamut mapping if it does not fit sRGB. `onFill` is
not derived: `#000000` in light, `#FFFFFF` in dark.

OKLab used the standard Ottosson matrices (coefficients from memory, to six places), same hand method as
section 3.1.

### 4.1 Targets

| Role | Mode | Target L | Chroma factor | Chroma cap | Curated L range (sample) | Curated C range (sample) |
|---|---|---|---|---|---|---|
| spine | light | 0.57 | 1.00 | 0.19 | 0.549 to 0.603 | 0.125 to 0.186 |
| fill | light | 0.86 | 0.45 | 0.12 | 0.843 to 0.874 (all 12) | 0.057 to 0.117 (all 12) |
| border | light | 0.60 | 0.90 | 0.17 | 0.606 to 0.633 | 0.110 to 0.169 |
| spine | dark | 0.74 | 0.90 | 0.16 | 0.721 to 0.785 | 0.136 to 0.161 |
| fill | dark | 0.41 | 0.60 | 0.11 | 0.404 to 0.418 | 0.091 to 0.107 |
| border | dark | 0.58 | 0.80 | 0.14 | 0.554 to 0.607 | 0.116 to 0.131 |

How these were fitted:

- The reference chroma is the **light spine**, because that is the closest curated analogue to "the colour
  the user picked". Each factor is the mean of (role chroma / light spine chroma) over the sample.
- **Sample.** Light fill was computed for all twelve swatches. Every other row was computed for three
  swatches spread around the hue circle: Red, Green, Blue. That is thin, and the factors vary a lot by hue
  (the light fill factor was 0.33, 0.69 and 0.31). Treat the factors as a first fit, and the hue-sweep test
  in the ADR (A.4b) as the real check.
- **Light lightness targets are shifted about 0.01 to 0.02 darker than the sample mean** (spine 0.57 against
  mean 0.581, border 0.60 against 0.616). At a fixed OKLab L, WCAG luminance varies by roughly 10 to 15
  percent with hue (yellow-greens are brighter than blues). The shift keeps a derived light border above
  3:1 for the brightest hue at that L. Without it, the estimate for a yellow-green pick sits near 3.05.
- Dark fill and light fill targets have wide margins against the canvas floors: at L 0.41 the dark fill
  is about 1.8:1 or more against canvas, and at L 0.86 the light fill is about 1.4:1 or more.
- Expected outcome: `lowContrast` should almost never fire (as the ADR predicts). The concerns users will
  see are `looksLikeMeeting` and `closeTo`.

### 4.2 Chroma gap against the meeting fill

| Quantity | Light | Dark |
|---|---|---|
| Meeting fill C* (CIELAB) | 1.7 | 1.4 |
| Lowest curated fill C* | 20.0 (Teal) | 20.4 (Teal) |
| Gap, lowest curated fill minus meeting | 18.3 | 19.0 |
| Lowest curated fill OKLCH C | 0.057 (Blue), all 12 measured | about 0.056, estimated from C* (only 3 swatches computed) |

**`chromaGap` = 0.040 OKLCH chroma on the derived fill, in each mode.** That is about 14 units of C*.
It sits 0.016 below the lowest curated fill, so every curated swatch passes. It is also slightly stricter than
the ΔE 15 rule in light mode: the lightness difference between a light fill and the meeting fill is only about 9
L*, so a fill needs about 12 C* to reach ΔE 15, and the chroma gap binds first. In dark mode the lightness
difference is about 14 L*, and ΔE 15 is the looser of the two.

Consequence for the picker: a pick with OKLCH chroma below about 0.09 (a muted or pastel colour)
derives a light fill under the gap (0.45 * 0.09 = 0.040), and below about 0.07 in dark (0.60 * 0.07 = 0.042).
Those picks should read "Looks like a meeting". That is intended: the owner asked for a warning, and a
pale colour really would read as a meeting on this canvas.

A pick with OKLCH chroma under 0.02 has no usable hue (ADR 005, Greys). It derives to greys and is
flagged for the same reason.

## 5. The owner question: derived lightness or the colour verbatim

**Recommendation: keep derived lightness, and say so in plain words next to the picker.** A colour that
reads well on white (the spine) is exactly the colour that disappears as a dark-mode fill; this repo has already
paid for that once (finding M10, fills at 1.17 to 1.27:1). Showing the pick verbatim in dark mode would
reintroduce it for every custom category, and the owner has no way to know, because the pick looked fine in
the picker. The cost is real: a bright pick such as pure yellow becomes a darker mustard spine in light
mode, and it will not match the swatch the owner tapped. Two things keep that honest. The editor shows the
derived chip in both modes directly under the picker, so the owner sees what blocks will actually look like
before saving. And the one line of copy under the picker says the adjustment is deliberate, so a mismatch
reads as a feature. I would not add a "use my exact colour" override: it is a second path to a failing
contrast ratio, and the ADR's warn-only rule already lets the owner keep a colour that scores badly if they
insist.

### 5.1 Editor copy (the ADR leaves the words to the designer)

| Where | String |
|---|---|
| Colour row label | `Colour` |
| Last swatch in the row | `Other…` |
| Line under the picker | `Blockey adjusts brightness for light and dark mode. Your pick sets the hue.` |
| Preview captions | `Light` and `Dark` |
| `lowContrast` | `Title may be hard to read in {light or dark} mode` |
| `looksLikeMeeting` | `Looks like a meeting in {light or dark} mode` |
| `closeTo(slug)` | `Close to {category name} in {light or dark} mode` |
| Grey pick (chroma under 0.02) | `Too grey to tell apart from a meeting` |
| VoiceOver for a swatch | `{Name}, colour {n} of 12` and `Selected` when chosen |
| VoiceOver for the preview | `Preview in light mode` and `Preview in dark mode` |

Show only the worst concern, worst first, as the ADR specifies. Save stays enabled.

## 6. What I could not measure

- **Nothing was run by a machine.** Every figure is hand arithmetic, with a stated tolerance of ±0.5 ΔE and
  ±0.02 contrast. The qa test must recompute them from the hex values and, where it disagrees beyond that
  tolerance, it wins.
- **Dark-mode colour blindness.** Not simulated. The dark fills share the hue arrangement of the light ones, so I expect the same cool cluster
  and the same Red and Green and Orange and Green weakness, but I have no number.
- **Protanopia and deuteranopia for all 132 pair values.** I screened and then simulated, but only the
  pairs under 10 are tabulated.
- **Tritanopia** is not covered.
- **OKLCH for most of the set.** Computed for the twelve light fills and for Red, Green and Blue in the other
  six role-mode rows. The factors in section 4.1 rest on that three-swatch sample.
- **Derived colours themselves.** No custom colour has been derived, because `derive` does not exist. The
  claim "every derived light border clears 3:1" is an estimate from the Y-to-L relationship, not a result.
- **Secondary text.** Time labels on a fill use `.secondary` (about 60 percent ink). I measured the title
  ink only. A time label on the lightest dark fill is likely above 4.5:1, but I did not compute it.
- **Display P3.** Everything is sRGB hex as the ADR specifies; I did not model how iOS renders it.
- **A real screen.** The simulator cannot show emoji and I did not look at any screenshot. How a derived
  colour sits next to the curated ones is a judgement for a device screenshot, as the ADR says.
- **Canvas and meeting fill** are my assumed values (section 1), not Story 1's.

## 7. Hand-off to frontend-engineer and qa-engineer

- Create `SRGB` (with `init?(hex:)` and `var hex`), `CategoryColorRecord`, `CategoryColors` in `Catalog/`,
  with the 12 records above as `static let` data in palette order. The six built-ins are the first six.
- `CategoryStyle` is built from a `CategoryColors` plus title, emoji and symbol, as in ADR 005's seam notes.
- qa test: for every record and mode, recompute spine and border against canvas (3:1), fill against canvas
  (ΔE 8 and 1.3:1), `onFill` against fill (4.5:1), fill against meeting fill (ΔE 15), and all 66 fill pairs
  (ΔE 10). Add a gap test: each fill's OKLCH chroma is at least `chromaGap`. Pin the numbers in section 3 with
  a tolerance of 0.5 so a drifting formula is caught.
- Story 1 must publish `canvas` and `meetingFill` as numeric `SRGB` pairs. The values in section 1 are placeholders until it does.
- #1 task 3.3b takes the table in section 4.1 as `DerivationTargets.measured` and should treat it as a
  first fit pending the hue-sweep test.

## Verification, 2026-11-04

Recomputed by script from the hex values above (WCAG 2 relative luminance, CIE76 in CIELAB with a D65 white, the same assumed canvas and meeting fills). Every floor passes in both modes and the minimums agree with the hand figures to within 0.05: border on the light canvas 3.17 (Pink), fill-to-canvas luminance in light 1.35 (Mint), fill against the light meeting fill ΔE 20.96 (Red), weakest pair in light ΔE 11.59 (Teal/Sky), weakest pair in dark ΔE 11.78 (Gold/Lime). The colour-blindness figures and the DerivationTargets were not rechecked.

## Owner decisions, 2026-11-04

- Keep all 12 swatches. The owner has no colour-vision deficiency, so the deuteranopia and protanopia collapses above are noted, not acted on. The required emoji still separates categories.
- Custom colours keep the picked hue and derive lightness per mode (the recommendation). The picker says so in one line: "Blockey adjusts brightness for light and dark mode. Your pick sets the hue."
