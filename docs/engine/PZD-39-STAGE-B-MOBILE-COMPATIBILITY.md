# PZD-39 — Stage B mobile compatibility gate

**Gate outcome:** **STAGE B — INTEGRATION VERIFIED**  
**Verified HEAD:** `03be6724611fbe0e8142b50c86d5f33d3363970e`  
**PR:** https://github.com/puzzle-duel/puzzle-duel-client/pull/18  
**Base:** `docs/core-001-v3-ruleset-design`  
**Evidence UTC:** 2026-11-17T03:27:28Z  
**Prior review comment:** [#6931837055](https://github.com/puzzle-duel/puzzle-duel-client/pull/18#issuecomment-6931837055)

Working tree at verification: clean (documentation update committed after this evidence).

---

## 1. Worktree safety

| Worktree | Branch / HEAD | Preserved |
| --- | --- | --- |
| Stage B (this work) | `feature/PZD-39-core001v3-dart-engine` @ `03be672` | Yes |
| Client PZD-22 | `feature/PZD-22-flutter-app-bootstrap` | Yes (untouched) |
| Client PZD-23 | detached + staged visuals | Yes (untouched) |
| Client design | `docs/core-001-v3-ruleset-design` @ `a09866b` | Yes |
| Backend Phase A | `feature/PZD-38-trusted-ingress` | Yes |
| Backend design | `docs/core-001-v3-ruleset-design` @ `727e1b4` | Yes |

Host Homebrew Flutter left at **3.47.8**. No brew upgrade, no PATH rewrite, no force-push.

---

## 2. Flutter / Dart SDK (isolated)

| Item | Value |
| --- | --- |
| Install strategy | Official `flutter/flutter` git tag `3.50.0` shallow clone |
| Framework revision | `ab2912035e` (matches tag) |
| Reproducible location | `$HOME/Developer/flutter-sdks/flutter-3.50.0` (outside git worktrees; **not committed**) |
| Executable | `$HOME/Developer/flutter-sdks/flutter-3.50.0/bin/flutter` |
| Flutter | **3.50.0** |
| Dart (bundled) | **3.14.0** |
| Host brew Flutter | Still **3.47.8** / Dart **3.13.7** (unchanged) |
| Pure Dart package SDK | Worktree `.dart-sdk/bin/dart` **3.14.0** (gitignored) |

---

## 3. Public API migration (already on HEAD)

`GameState.offers`: `List<Piece?>` → `List<OfferSlot>`.

Stage B `apps/mobile` consumers use:

- `OfferSlot.isSelectable` for selection gating
- `OfferSlot.pieceOrNull` for live piece extraction

Historical v1/v2 JSON wire unchanged (`OfferEmpty` → JSON `null`).

---

## 4. Mobile evidence (Flutter 3.50.0)

| Check | Exit | Result |
| --- | ---: | --- |
| `flutter pub get` | 0 | Got dependencies; **no lockfile/git changes** |
| `flutter analyze` | 0 | **No issues found** |
| `flutter test` | 0 | **180 PASS / 0 FAIL / 0 SKIP** |
| `flutter build ios --simulator --no-codesign` | 0 | **Built** `build/ios/iphonesimulator/Runner.app` |

### iOS build notes

- Xcode **27.0** (27A266a); arm64 host.
- First attempt failed on stale generated `ios/.symlinks/plugins/audioplayers_darwin` (“File exists”). Cleared **generated** `ios/.symlinks` only (not tracked) and rebuilt successfully.
- CocoaPods warning: recommended ≥1.16.2; host has 1.14.2 — build still succeeded.
- Simulator compile is integration evidence, **not** visual/device UAT. Screenshot tests in the suite are not claimed as approved visual UAT.

---

## 5. Pure Dart re-verification (same HEAD)

From `packages/puzzle_duel_rules` with `.dart-sdk/bin/dart` 3.14.0:

| Check | Exit | Result |
| --- | ---: | --- |
| `dart format --set-exit-if-changed .` | 0 | clean |
| `dart analyze` | 0 | No issues found |
| `dart test` | 0 | **140 PASS / 0 FAIL / 0 SKIP** |

### Historical regression

| Check | Result |
| --- | --- |
| v1 Python / Node checkers | PASS (exit 0) |
| v2 Python / Node checkers | PASS (exit 0) |
| v1 CHECKSUMS | **27/27 OK** |
| v2 CHECKSUMS | **8/8 OK** |
| Independent Python CV-01…09 | **fail=0** |

---

## 6. Defects

| Sev | Item | Status |
| --- | --- | --- |
| P1 | OfferSlot mobile type break | Fixed earlier on this branch; verified under Flutter 3.50 |
| Env | Flutter 3.50 missing | Resolved via isolated SDK install |
| P2 | CocoaPods host version <1.16.2 | Nonblocking warning |
| P2 | Package README still v1/v2-oriented | Open (docs polish) |

No unresolved P0/P1.

---

## 7. Final decision

**STAGE B — INTEGRATION VERIFIED**

Mandatory gates on HEAD `03be672`:

- Flutter 3.50.0 / Dart 3.14.0 verified  
- `flutter pub get` / `analyze` / `test` PASS  
- iOS simulator build PASS  
- Pure Dart package PASS  
- Historical fixtures + CV digests PASS  
- Unrelated worktrees preserved  

---

## 8. NOT_RUN / remaining

- TypeScript Stage C engine  
- Stage D dual-engine golden freeze / full GameState hash freeze  
- Tournament / PZD-38 ranked integration  
- Device UAT / approved visual golden UAT  
- GitHub Actions CI PASS claim without inspecting Actions logs  
- Merge / deploy / marking PZD-39 Done  

### Stage C prerequisites

1. Port Dart CORE-001.v3 contract to pure TypeScript replay.  
2. Shared freeze protocol for boards/scores/hashes.  
3. Keep client hash non-authoritative for ranking.
