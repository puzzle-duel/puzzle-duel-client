# PZD-47 — Asset Hygiene Cleanup (APPLIED)

**Pre-cleanup tip:** `c2dfae64a81bc2877ed5802f08dda4de8c806165`  
**Base:** `origin/main` @ `9290732`  
**Branch:** `feature/PZD-47-premium-shapes-app-icon`  
**Prototype worktree:** `.worktrees/pzd47-proto` — **untouched**

Status: **CLEANUP APPLIED** — tests green (CI-equivalent + presentation goldens); commit/push to follow.

---

## Before / after (images in PR diff vs `origin/main`)

| Metrik | Önce (`c2dfae6` vs main) | Sonra (cleanup index vs main) |
| --- | --- | --- |
| Değişen dosya (ACMR) | **152** | **103** |
| Değişen görsel (png/jpg/svg/webp) | **130** | **89** |
| Toplam değişen görsel boyutu | **16.36 MB** | **6.84 MB** |

Hedef tahmin (~90 / ~8.5 MB) zorlanmadı; gerçek sonuç: **89 görsel / 6.84 MB**.

---

## Tam silinen dosyalar (vs `c2dfae6`)

### Runtime extract / atlas
- `apps/mobile/assets/branding/canonical/MANIFEST.json`
- `apps/mobile/assets/branding/canonical/circle_body.png`
- `apps/mobile/assets/branding/canonical/diamond_body.png`
- `apps/mobile/assets/branding/canonical/direction_chevron_up.png`
- `apps/mobile/assets/branding/canonical/triangle_body.png`
- `apps/mobile/assets/branding/canonical/trophy.png`
- `apps/mobile/lib/presentation/widgets/premium_shape_atlas.dart`

### Extraction tooling / docs
- `tools/pzd47/extract_canonical_shapes.py`
- `tools/pzd47/requirements.txt`
- `docs/features/pzd-47/AC03_DELTA_AND_CANONICAL_FIX.md`

### Duplicate reference
- `docs/features/pzd-47/reference/app_icon_clean_no_center_arrows.png` (byte-identical to `Neon_Puzzle_Trophy_Icon.png`, SHA `32d53c61…e48b`)
- `docs/features/pzd-47/reference/crops/trophy_extract.png` (byte-identical to `crops/trophy.png`)

### Temporary UAT / preview dumps
- `docs/features/pzd-47/uat/01-original-jira-icon.png`
- `docs/features/pzd-47/uat/02-icon-composed-from-canonical-masters.png`
- `docs/features/pzd-47/uat/02-icon-no-center-arrows.png`
- `docs/features/pzd-47/uat/08-ios-appicon-1024.png`
- `docs/features/pzd-47/uat/09-android-launcher-xxxhdpi.png`
- `docs/features/pzd-47/uat/icon-crop-circle.png`
- `docs/features/pzd-47/uat/icon-crop-diamond.png`
- `docs/features/pzd-47/uat/icon-crop-triangle.png`
- `docs/features/pzd-47/uat/previews/*` (8 files)

**Kanıt (canonical silinebilir):** `PremiumShapeAtlas` kaldırıldı; `piece_glyph.dart` / `premium_shape_materials.dart` / `main.dart` / `puzzle_duel_app.dart` / `pubspec.yaml` `147a90f` procedural baseline’a döndürüldü. `rg` sonrası runtime’da `branding/canonical` veya `PremiumShapeAtlas` referansı yok.

---

## Restore edilen dosyalar

### Renderer / entry / goldens → `147a90f`
- `apps/mobile/lib/presentation/widgets/piece_glyph.dart`
- `apps/mobile/lib/presentation/widgets/premium_shape_materials.dart`
- `apps/mobile/lib/main.dart`
- `apps/mobile/lib/app/puzzle_duel_app.dart`
- `apps/mobile/pubspec.yaml`
- `apps/mobile/test/presentation/goldens/*` (51)
- `apps/mobile/test/presentation/pzd47_premium_shapes_test.dart`
- `apps/mobile/test/presentation/piece_glyph_triangle_arrow_test.dart`
- `apps/mobile/test/visual/pzd47_uat_capture_test.dart` (+ atlas import strip via 147a90f)
- `apps/mobile/test/visual/pzd23_screenshot_capture_test.dart`
- `apps/mobile/test/visual/pzd42_surface_capture_test.dart`
- `docs/features/pzd-47/uat/{03,04,05,06,07,10}-*.png`
- `docs/features/pzd-47/EVIDENCE.md` / `VISUAL_PARITY_MANIFEST.md` (sonra cleanup path güncellemesi)

### PZD-23 / PZD-42 UAT → `origin/main` (byte-identical; PR diff’ten düşer)
- `docs/mobile/uat-evidence/pzd23-visual/*.png` (8)
- `docs/tournament/uat-evidence/pzd42-visual/*.png` (10)

Geçmiş main kanıtı korunur; tip’teki yeniden-capture şişmesi PR’dan çıkar.

---

## Korunan dosyalar

- `apps/mobile/assets/branding/app_icon_master_1024.png`
- iOS `AppIcon.appiconset/*` (15 PNG + Contents.json)
- Android `mipmap-*/ic_launcher.png` (5) + `drawable-*/ic_launcher_foreground.png` (5)
- `apps/mobile/test/presentation/goldens/**` (51 aktif golden)
- Nihai UAT: `uat/03`–`07`, `uat/10`
- `reference/Neon_Puzzle_Trophy_Icon.png` + `reference/crops/{circle,diamond,triangle,trophy,center}.png`
- `tools/pzd47/generate_app_icons.py`
- `.worktrees/pzd47-proto/**` (dokunulmadı)
- `docs/features/pzd-47/prototype/**` (local; commit’e alınmadı)
- Owner premium PNG referansı (`PZD-47-premium-shapes-reference.png` Downloads / proto)

---

## `.gitignore` ekleri

```gitignore
# Local visual debug / failure dumps (never commit)
apps/mobile/test/visual/failures/

# Extraction scratch (if regenerated locally)
docs/features/pzd-47/uat/previews/
apps/mobile/assets/branding/canonical/

# Local git worktrees (never commit)
.worktrees/
```

Goldens, nihai UAT, launcher icons, master branding, reference master **ignore edilmedi**.

---

## Test sonuçları

| Check | Result |
| --- | --- |
| `flutter analyze` | **PASS** — No issues found |
| `CI=true flutter test` | **PASS** — `+271 ~68` (visual captures CI-skip) |
| Presentation goldens (`pzd47_premium_shapes` + `piece_glyph_triangle_arrow`) | **PASS** — `+141` |
| `dart analyze` + `dart test` (`puzzle_duel_rules`) | **PASS** — `+140` |
| iOS `flutter build ios --no-codesign` | **PASS** — `Runner.app` 20.2MB |
| Android `flutter build apk --debug` | **PASS** — `app-debug.apk` |
| Icon assets present | iOS 15 / Android 5+5 / master OK |

**Not:** Local (non-CI) `flutter test` fails 14 visual capture goldens for pzd23/pzd42 because those PNGs are restored to **pre-PZD-47 main** while the branch still paints premium `PiecePainter`. CI skips these captures (`skip: _skipOnCi`). Bu, onaylı restore’un beklenen sonucu; test bypass edilmedi.

---

## Exact HEAD SHA

Pre-cleanup tip: `c2dfae64a81bc2877ed5802f08dda4de8c806165`  
**Cleanup commit SHA:** `8e90e626fe1d8c66615d2f6e436b5b4a2ece10ca`  
**Exact branch HEAD:** see `git rev-parse HEAD` on `feature/PZD-47-premium-shapes-app-icon` after push (docs-record commit on top of cleanup).
