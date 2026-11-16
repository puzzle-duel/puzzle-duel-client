# PZD-23 SFX assets (UAT)

## Dependency

- `audioplayers: 6.5.1` — presentation-only playback.

## Assets

Procedurally generated mono WAV tones (22.05 kHz, soft envelope):

| File | Event |
| --- | --- |
| `apps/mobile/assets/sfx/place.wav` | Piece placement |
| `apps/mobile/assets/sfx/reject.wav` | Invalid / rejected tap |
| `apps/mobile/assets/sfx/clear.wav` | First clear wave |
| `apps/mobile/assets/sfx/cascade.wav` | Additional cascade wave |
| `apps/mobile/assets/sfx/chain_complete.wav` | Chain / settle after clears |
| `apps/mobile/assets/sfx/round_end.wav` | Round complete overlay |

## Licensing

These tones were generated in-repo for development/UAT (no third-party sample packs). Replace with final licensed art before store release if desired.

## Mute

`GameSfx.muted` is the toggle hook. No settings UI yet.
