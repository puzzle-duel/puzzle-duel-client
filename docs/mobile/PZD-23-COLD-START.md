# PZD-23 First-interaction cold-start

## Reproduction (owner UAT video)

`ScreenRecording_11-16-2026 18-03-27_1.mov`

Approximate visual timeline (not frame timing):

| Window | Observation |
| --- | --- |
| 0–2 s | Menu → Easy board |
| 3–4 s | First offer selected |
| 4.5–6 s | Prolonged inactivity around first board interaction |
| 6 s+ | Move resolves; later play feels smoother |

## Measured local baselines (dev machine)

Environment: macOS host, Dart VM (not device FPS).

| Step | Result |
| --- | --- |
| `generateChallenge` easy seed 42 | ~0.6 ms |
| First `applyMove` | ~3.7 ms |

Conclusion: rules CPU is not the multi-second stall.

## Leading hypotheses (evidence-ranked)

1. **iOS audio cold start on first SFX** (place/reject) — first `AudioPlayer` + `AudioCache` asset copy + session activation. Aligns with “first interaction only”.
2. **First `MaskFilter.blur` shader compile** on piece glyphs — mitigated by removing blur from piece lift shadows.
3. Flame first animation frame — possible contributor; not proven without device timeline.

## Fix shipped

- `GameSfx.prepare()` warms `AudioCache` + bounded player pool (2) without audible playback.
- Prepare kicked after first home frame and again on game screen first frame (idempotent, non-blocking).
- `play()` never awaits prepare; gameplay proceeds if audio is late/failed.
- Piece lift shadow no longer uses `MaskFilter.blur`.
- Optional marks via `--dart-define=PZD_PERF=true`.

## Owner: real-device profile capture

Physical iPhone was **not** attached to this agent environment (`flutter devices` showed simulator only).

```bash
cd apps/mobile
flutter run --profile --dart-define=PZD_PERF=true -d <iphone_id>

# DevTools
flutter pub global activate devtools
dart devtools
# Open the profile app → Performance → record:
# cold launch → Easy → first offer → first cell tap → second move
```

Capture and attach:

1. Performance timeline screenshot around first offer + first place
2. Console `PZD_PERF ...` lines
3. Note whether first-interaction hitch remains

## Status

`READY_FOR_PERFORMANCE_UAT` — unit/CI green and iOS build verified; hardware hitch reduction not claimed until owner profile/UAT.
