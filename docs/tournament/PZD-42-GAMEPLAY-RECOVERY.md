# PZD-42 gameplay and navigation recovery

Manual iPhone UAT is still not passed. This note records the audit, the navigation model, and what the owner should play.

## Issue matrix

| Severity | Evidence | Cause | Resolution |
| --- | --- | --- | --- |
| P0 | Completed day opened Results whenever Home refreshed. Leaderboard Back called that refresh, so Daily → Back returned to Results. | `refreshHome()` treated a completed claim as navigation. | Home load stores the day. Back uses the screen that opened the leaderboard. Results Back goes Home. A later Home visit does not claim again. |
| P0 | A rejected or stale move replaced the board with an error page. | Non-200 command responses called the generic failure path. | Stay on the server board, show a player sentence, and keep the error code as a reference. |
| P0 | An unknown command could be mistaken for success, or followed by a different tap. | The in-flight tap was not locked to one body. | The same command object is kept. Another tap is ignored until that command resolves. |
| P1 | Home, transitions, results, and leaderboards were debug layouts. Back sat at the bottom. | The first UAT slice only proved the HTTP path. | Home, overview, play, transition, results, and both leaderboards use the existing arcade tokens. Back is top-left. |
| P1 | Idle time was shown as if it were the puzzle clock. | The payload field is the server idle deadline. | The HUD labels it Idle and shows moves remaining from the authoritative state. |
| C | E1 and H1 are both `V3-02`. E3 and M2 are both `V3-09`. | The pinned UAT manifest reuses contract fixtures. | Not changed. The HUD shows the live board size and move limit. A new puzzle set needs an approved spec. |

## Six-game mechanics

The client does not generate these boards. The server pins:

| Game | Fixture | Board | Move limit | Recorded result |
| --- | --- | --- | --- | --- |
| E1 | V3-02 single wave | 3×3 | 5 | score 300, still in progress |
| E2 | V3-05 cascade reopen | 3×3 | 5 | score 300, still in progress |
| E3 | V3-09 move limit | 2×2 | 1 | score 0, ended by the move limit |
| M1 | V3-03 multi-wave | 5×5 | 5 | score 900, still in progress |
| M2 | V3-09 move limit | 2×2 | 1 | same fixture as E3 |
| H1 | V3-02 single wave | 3×3 | 5 | same fixture as E1 |

`apps/mobile/test/tournament/tournament_fixture_audit_test.dart` parses those fixtures and checks the recorded legal move, the score, an occupied-cell rejection, and a second move after the one-move games. Placement preview uses `canPlaceAt` and is drawn only after a piece is selected. It is not a confirmed move. The local engine is not called for a tournament tap.

A line clear is not animated from a local prediction. After the server accepts a move, the score change is the difference of the two server series scores. Sound is not enabled in this flow: the tournament host uses a silent audio sink so a failed prepare cannot block a move. Haptics call the platform API on selection and after the server response.

## Navigation

- Home is the root. System back there leaves the app.
- Overview, Results, and a confirmed leave from Play or Transition return Home.
- Daily and Weekly remember whether they were opened from Home, Overview, or Results.
- Switching category does not change that return target.
- Play and Transition ask before leaving. The series is not reset and the idle deadline is not extended.
- H1 publication opens Results. Return Home stays on the completed card.

## Owner checklist

Use the server commands in the backend note `docs/tournament/PZD-42-UAT.md`. On the paired iPhone:

```bash
cd /Users/gokhanaydin/Desktop/workspace/puzzle-duel-client-core001v3-dart/apps/mobile
export PATH="$HOME/Developer/flutter-sdks/flutter-3.50.0/bin:$PATH"
flutter run -d 00008160-001C5C993E80000A \
  --dart-define=PZD_UAT_BASE_URL=http://192.168.68.51:8787 \
  --dart-define=PZD_UAT_BEARER="$PZD_UAT_BEARER_A" \
  --dart-define=PZD_UAT_PLAYER="Player A"
```

Replace the LAN address if `ipconfig getifaddr en0` has changed. `127.0.0.1` on the phone is the phone.

Expect:

1. Home shows the daily card, six-game progress, and one primary action. It does not jump to Results.
2. E1 through H1 show a board, three offers, a selected-piece label, highlighted empty cells, the server score, moves left, and the idle deadline.
3. A rejected tap stays on the board and does not add a local score.
4. After each of E1–M2, the transition shows that game's server score, the series total, and Continue.
5. After H1, Results shows the verified total, Easy / Medium / Hard, the On-Time state, and Return Home.
6. Daily and Weekly open from Home or Results. Back returns to that screen, including after the day is complete.
7. Leaving a game asks first. Home can resume the same series.
8. Player B uses the same command with `PZD_UAT_BEARER_B` and `PZD_UAT_PLAYER="Player B"`.

Screenshots of this recovery were not captured on the phone. The widget tests cover the completed-day loop at a tall phone size and the home layout at 320, 390, and 430 points, including Turkish copy and a larger text scale.
