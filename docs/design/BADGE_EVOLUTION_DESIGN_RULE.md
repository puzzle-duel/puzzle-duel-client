# BADGE EVOLUTION DESIGN — GOLDEN RULE

> **BADGE EVOLUTION DESIGN — GOLDEN RULE**  
> The owner-approved Badge Evolution Studio is the canonical visual reference for all Puzzle Duel achievement badges. All badge artwork must use the shared vector-based medallion and prestige-frame system defined in this document. Developers and AI coding agents must not redesign, simplify, replace, reinterpret or introduce alternative badge artwork without explicit owner approval. Any future badge must introduce a new approved center-artwork definition while reusing the existing prestige frame system. Exact geometry, gradients, palette, proportions, ornament counts, stroke widths and count capsule placement must be preserved. Any change to the canonical design requires explicit owner approval and updated visual regression tests.

**Feature:** PZD-56 — Badge Evolution & Prestige System  
**Status:** Binding visual contract  
**Canonical implementation:** Flutter `CustomPainter` under `apps/mobile/lib/badges/presentation/`

---

## 1. Badge identities (7)

| Badge ID | Turkish | English | Guest eligible | Verified required |
| --- | --- | --- | --- | --- |
| `loyalty` | Sadakat | Loyal Player | Yes | No |
| `on_time` | Zamanında | On Time | No | Yes (existing F2-B) |
| `practice_master` | Pratik Ustası | Practice Master | Yes | No |
| `tournament_guru` | Turnuva Gurusu | Tournament Guru | No | Yes |
| `champion` | Şampiyon | Champion | No | Yes |
| `rising_star` | Yükselen Yıldız | Rising Star | No | Yes |
| `unstoppable` | Durdurulamaz | Unstoppable | Yes | No |

Existing persisted `on_time` identity must not be renamed. New IDs above are canonical for new definitions.

## 2. Prestige tiers (6)

| ID | Turkish | English |
| --- | --- | --- |
| `bronze` | Bronz | Bronze |
| `silver` | Gümüş | Silver |
| `gold` | Altın | Gold |
| `platinum` | Platin | Platinum |
| `diamond` | Elmas | Diamond |
| `mythic` | Efsanevi | Mythic |

## 3. Threshold matrix

| Badge | Bronze | Silver | Gold | Platinum | Diamond | Mythic |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| loyalty | 1 | 10 | 50 | 100 | 250 | 1000 |
| on_time | 1 | 10 | 50 | 100 | 250 | 1000 |
| practice_master | 1 | 10 | 50 | 100 | 250 | 1000 |
| tournament_guru | 1 | 4 | 12 | 26 | 52 | 104 |
| champion | 1 | 3 | 10 | 25 | 50 | 100 |
| rising_star | 1 | 3 | 5 | 10 | 20 | 50 |
| unstoppable | 1 | 4 | 12 | 26 | 52 | 104 |

Prestige = highest threshold ≤ earned count. Zero earned → locked (no Bronze frame). Counts continue beyond Mythic; never cap persisted counts.

## 4. All 42 earned combinations

For each of the seven badge IDs × six prestige IDs, render:

`shared prestige frame + badge-specific center artwork + count capsule + prestige label`

Locked (zero) states are additional: seven muted silhouettes without earned Bronze frames.

---

## 5. CANONICAL VISUAL SPECIFICATION

All coordinates originate from the owner-approved interactive prototype. Use as a normalized vector coordinate system. Do not approximate with unrelated Flutter icons.

### 5.1. Reference canvas

Reference viewBox: `0 0 280 240`

- Canvas center X: `140`
- Medallion center Y: `103`
- Background reference: `#111929`

Composition: outer prestige ornaments, ambient aura, main circular medallion, inner circular border, badge-specific central artwork, earned count capsule, prestige level label.

Scale uniformly; preserve aspect ratio; do not stretch.

### 5.2. Exact prestige palette

| Prestige | Primary metal | Highlight |
| --- | --- | --- |
| Bronze | `#B77B4C` | `#F0BD83` |
| Silver | `#8D9FB6` | `#E3EDF9` |
| Gold | `#C99832` | `#FFE7A1` |
| Platinum | `#70AECB` | `#E0FBFF` |
| Diamond | `#9866E1` | `#E8D0FF` |
| Mythic | `#ED9B51` | `#FFF2B0` |

Dedicated badge prestige palette — do not substitute league colors.

### 5.3. Metallic gradient

Diagonal linear gradient top-left → bottom-right:

- 0.00: highlight
- 0.45: primary
- 0.70: highlight
- 1.00: primary

```dart
LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [highlight, primary, highlight, primary],
  stops: const [0.0, 0.45, 0.70, 1.0],
)
```

Apply shaders relative to object bounds. No flat fill for primary metal.

### 5.4. Ambient aura

- Center: `(140, 103)`
- Radius: `103`
- Radial: center prestige primary @ 28% opacity → edge @ 0%
- Behind all other geometry
- No bloom, particles, flares

### 5.5. Main medallion

- Center: `(140, 103)`
- Radius: `71`
- Radial fill: center `#344358` → edge `#131C30`
- Outer border: metallic gradient
- Outer stroke width: Bronze/Silver `5`; Gold/Platinum/Diamond/Mythic `9`

### 5.6. Inner medallion border

- Center: `(140, 103)`
- Radius: `60`
- Stroke: prestige primary, width `1.2`, opacity `0.7`
- No extra rings

### 5.7. First prestige ornament layer

Visible from Silver onward (hidden for Bronze). Exactly **12** ornaments.

Base path:

```svg
M140 19
L148 38
L140 46
L132 38
Z
```

Rotate around `(140, 103)` by increments of `30°`. Fill: metallic gradient.

Opacity: Silver/Gold `0.55`; Platinum/Diamond/Mythic `1.0`.

Draw **behind** the main medallion.

### 5.8. Second prestige ornament layer

Visible only for Diamond and Mythic. Exactly **8** outer diamond ornaments.

Base path:

```svg
M140 7
L145 17
L140 27
L135 17
Z
```

Rotate around `(140, 103)` by increments of `45°`. Fill: prestige highlight. Behind medallion.

### 5.9. Mythic-exclusive outer orbit

Visible only for Mythic.

- Center `(140, 103)`, radius `94`
- Stroke `#E3A6FF`, width `1.5`, dash `[3, 9]`
- No fill; no unapproved animation (optional Mythic motion needs separate owner approval; always respect reduced motion)

---

## 6. EXACT CENTRAL ICON GEOMETRY

Shared defaults unless overridden:

- Stroke: prestige highlight
- Stroke width: `3.5`
- Cap/join: round
- Default fill: none

### 6.1. Zamanında — Clock

- Outline center `(140, 100)`, radius `31`, stroke `4`, fill none
- Hands: `M140 80 V101 L155 111`, stroke `4.5`
- Hour markers: `M140 72 V77` rotated 0/90/180/270° around `(140, 100)`, stroke `2`
- Do **not** convert to stopwatch / crown / seconds hand

### 6.2. Sadakat — Heart Shield

Shield:

```svg
M140 64 L175 78 V101 Q175 125 140 143 Q105 125 105 101 V78 Z
```

Stroke `3`. Heart:

```svg
M140 118 C130 110 115 101 119 90 C123 80 135 82 140 91 C145 82 157 80 161 90 C165 101 150 110 140 118 Z
```

Heart fill: metallic gradient; heart stroke `1.5`.

### 6.3. Pratik Ustası — Geometric Pieces

- Purple square: x`107` y`73` w`29` h`29` r`5` fill `#9975DF` stroke `2.5`
- Green circle: center `(157, 87)` r`15` fill `#57B795` stroke `2.5`
- Yellow triangle: `M122 112 L139 139 H105 Z` fill `#EFC85B` stroke `2.5`
- Blue hexagon: `M157 108 L173 117 V135 L157 144 L141 135 V117 Z` fill `#6A92CC` stroke `2.5`

Independent badge artwork — do not modify gameplay piece assets.

### 6.4. Turnuva Gurusu — Crown

Crown fill metallic:

```svg
M107 84 L117 111 H163 L173 84 L153 96 L140 77 L127 96 Z
```

Stroke `2`. Base lines `M117 117 H163` and `M124 128 H156` stroke `5`. Upper diamond `M140 58 L145 66 L140 74 L135 66 Z` fill highlight stroke `1`. Jewel center `(140, 101)` r`4` fill `#17243B` stroke `1`.

### 6.5. Şampiyon — Trophy

Body metallic:

```svg
M119 75 H161 V96 Q161 116 140 119 Q119 116 119 96 Z
```

Handles:

```svg
M119 81 H105 V91 Q105 105 122 105
M161 81 H175 V91 Q175 105 158 105
```

Stem/base metallic:

```svg
M140 119 V133
M124 139 H156 L151 133 H129 Z
```

Star fill `#26334A`:

```svg
M140 84 L143 91 L151 92 L145 97 L147 105 L140 101 L133 105 L135 97 L129 92 L137 91 Z
```

### 6.6. Yükselen Yıldız — Rising Star

Main star metallic:

```svg
M140 64 L150 86 L175 89 L156 106 L162 131 L140 118 L118 131 L124 106 L105 89 L130 86 Z
```

Chevrons stroke `3`:

```svg
M112 143 L140 132 L168 143
M123 149 L140 142 L157 149
```

Facet lines stroke `#26334A` @ 0.35 opacity width `1.2`:

```svg
M140 64 L140 102 L175 89
M140 102 L162 131
M140 102 L118 131
M140 102 L105 89
```

### 6.7. Durdurulamaz — Flame

Outer flame metallic:

```svg
M145 63 C149 85 172 94 171 112 C170 131 155 140 140 140 C117 140 106 126 110 109 C113 96 122 90 126 78 C127 94 134 96 137 87 C143 76 145 63 145 63 Z
```

Inner flame `#26334A`:

```svg
M142 102 C142 116 155 119 151 129 Q140 143 129 129 C125 119 138 114 142 102 Z
```

---

## 7. EXACT COUNT CAPSULE

- Position: x`105` y`153` w`70` h`28` r`14`
- Fill `#121B2B`; border metallic gradient width `2`
- Text center X `140`, baseline Y `172`, size `14`, bold, prestige highlight, centered
- Format: `×76` (multiplication sign, not ASCII `x`)
- Overlaps lower medallion; not below prestige label
- Wide counts: fit or expand symmetrically without clipping; keep canonical size for normal counts

## 8. EXACT PRESTIGE LABEL

- Center X `140`, baseline Y `211`
- Size `15`, bold, letter spacing `1.1`, prestige highlight, centered
- Uppercase localized prestige name (locale-aware)
- Turkish examples: `BRONZ`, `GÜMÜŞ`, `ALTIN`, `PLATİN`, `ELMAS`, `EFSANEVİ`

---

## 9. Locked state

Zero awards:

- Muted silhouette of canonical artwork
- No Bronze earned frame
- Localized unlock requirement
- Layout parity with earned tiles

## 10. Progress indicator (detail / Studio)

- Track `#344054`, height `7`, fully rounded
- Fill: current prestige primary
- Visual progress = `earnedCount / nextPrestigeThreshold` clamped to \[0,1\]
- At Mythic: full bar; still show actual earned count

## 11. Responsive rendering

- Uniform scale from viewBox `280×240`
- Preserve aspect ratio at collection-grid and detail sizes
- `Canvas.save` / translate / scale / restore
- Cache immutable paths; correct `shouldRepaint`
- Respect reduced motion

## 12. Accessibility

- Semantics labels include badge name, earned/locked, count, prestige
- Contrast on count capsule and prestige label
- Large text: fit capsule / expand safely
- Shapes not color-only for Practice Master pieces

## 13. Visual regression testing

Mandatory minimum:

- **42** earned golden cases (7×6)
- 7 locked states
- Compact + expanded sizes
- Dark/Light theme wrappers
- Large accessibility text
- Capsule 1/2/3/4 digit counts
- Beyond-Mythic counts
- Long localized labels
- Narrow layout

Goldens must protect geometry (clock hands, radii, stroke widths, ornament count/rotation/opacity, gradients, capsule, Mythic dash, all seven centers). Owner UAT remains final visual acceptance.

## 14. Adding a future badge

1. Owner approves new center-artwork SVG paths (this document updated).
2. Add badge ID + thresholds + localization (not hardcoded in painters).
3. Implement one center-artwork painter; reuse shared frame.
4. Wire eligibility / evidence / idempotency on backend (and guest sync if applicable).
5. Extend golden suite for 6 prestige + locked.
6. Do **not** invent alternative artwork or break existing IDs.

## 15. Architecture separation

Keep separate: identity, eligibility, earned count, prestige resolution, palette, shared frame, center geometry, capsule, presentation/localization.

Never maintain 42 hand-edited bitmaps. Never use Material Icons / emoji / AI PNG medals as substitutes.
