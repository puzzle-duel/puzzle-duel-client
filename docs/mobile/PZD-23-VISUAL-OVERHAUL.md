# PZD-23 — Visual experience overhaul (pre–visual UAT)

Status: **READY_FOR_VISUAL_UAT** (owner device approval still required)  
Branch: `feature/PZD-23-accessible-game-board`  
PR: #16 (do not merge until owner visual acceptance)

## Owner UAT evidence

Owner iPhone recording (iOS 27.0.1) was **not accessible** in this Cursor workspace. Redesign follows written owner rejection: menu / game UI / animations unacceptable; core mechanics preserve.

Internal UAT seed remains `kUatChallengeSeed = 42`. Seed is **not** shown on the primary player-facing UI.

## Before → after

| Surface | Before | After |
| --- | --- | --- |
| Theme | Light Material demo feel | Dark navy arcade (`PuzzleDuelTheme.dark`, `GameTokens`) |
| Home | Full-width diagnostic buttons + seed 42 | Brand title, invitation, difficulty cards (size + moves), Play CTAs |
| HUD | Score/moves under board as debug text | Compact top HUD with SCORE / MOVES LEFT above maximized board |
| Pieces | Flat tiny glyphs | Custom-painted silhouette + deep shade + bold chevron |
| Tray | Flat slots | Elevated tray, selected border/glow/scale |
| End | Bare text + buttons | Modal overlay: final score, Play Again, Change Difficulty |
| Animations | Basic place/clear/shift | Place pulse, clear flash, eased simultaneous shifts; canonical scoreDelta chip |

## Design system

- Tokens: `apps/mobile/lib/theme/game_tokens.dart`
- Theme: `apps/mobile/lib/theme/app_theme.dart`
- Backdrop: `apps/mobile/lib/presentation/widgets/arcade_backdrop.dart`
- Piece painter: `apps/mobile/lib/presentation/widgets/piece_glyph.dart`

Shape families: circle (teal), diamond (violet), triangle (amber). Direction remains chevron-driven (not color-only).

## Gameplay safety (unchanged)

- No engine scoring or matching in presentation
- Animation uses `MoveApplied` / `WaveResult` / `MovedPiece` / `finalState` only
- `completeResolution(generation, resolutionId)` dual-token gate retained
- Rapid-tap ignored while resolving
- Reduced motion settles to canonical board
- Flame remains `IgnorePointer` visual layer

## Visual evidence paths

Widget/golden captures (inspected):

| File | Content |
| --- | --- |
| `docs/mobile/uat-evidence/pzd23-visual/01-home-menu.png` | Main menu difficulty cards |
| `docs/mobile/uat-evidence/pzd23-visual/02-easy-board.png` | Easy 5×5 HUD + board + tray |
| `docs/mobile/uat-evidence/pzd23-visual/03-medium-board.png` | Medium board |
| `docs/mobile/uat-evidence/pzd23-visual/04-hard-board.png` | Hard board |
| `docs/mobile/uat-evidence/pzd23-visual/05-selected-piece.png` | Selected offer chrome |
| `docs/mobile/uat-evidence/pzd23-visual/06-match-clear-resolving.png` | Clear / resolving frame |
| `docs/mobile/uat-evidence/pzd23-visual/07-directional-shift.png` | Clear flash / shift frame |
| `docs/mobile/uat-evidence/pzd23-visual/08-completed-round.png` | End overlay |

Simulator:

| File | Content |
| --- | --- |
| `docs/mobile/uat-evidence/pzd23-visual/sim-01-home.png` | iPhone 16 Pro (iOS 18.3) home |
| `docs/mobile/uat-evidence/pzd23-visual/sim-gameplay.mp4` | Short simulator recording (home idle) |

Regenerate goldens: `cd apps/mobile && flutter test test/visual/pzd23_screenshot_capture_test.dart --update-goldens`

## Automated results

- `packages/puzzle_duel_rules`: `dart analyze` clean; `dart test` **+96**
- `apps/mobile`: `flutter analyze` clean; `flutter test` **+38**
- Physical device frame timing: **NOT_RUN**
- Owner visual acceptance: **pending** (do not mark Done)
