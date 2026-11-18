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
| P0 | E1–H1 reused 2×2, 3×3 and 5×5 contract fixtures, including two duplicated boards. | The UAT manifest was pinned to engine-test fixtures instead of the approved profiles. | New claims use six distinct `gen-001.v1` boards projected into `core-001.v3`: Easy 5×5/15, Medium 6×6/12, Hard 7×7/10. The generator algorithm is unchanged. A claim already stored for today keeps its old digest. |

## Six-game mechanics

The client does not invent these boards. `gen-001.v1` still emits `core-001.v2`. ADR-E01 forbids changing that generator. The tournament engine is `core-001.v3`, whose schema already allows these sizes and budgets. Each pinned board is that generator's output with the three offers wrapped as `{kind: piece}`. A v2 move and the same v3 move are checked for the same score and cells.

| Game | Profile | Seed | Board | Moves | Obstacles |
| --- | --- | --- | --- | --- | --- |
| E1 | easy | 0 | 5×5 | 15 | 1 |
| E2 | easy | 1 | 5×5 | 15 | 1 |
| E3 | easy | 2 | 5×5 | 15 | 1 |
| M1 | medium | 0 | 6×6 | 12 | 2 |
| M2 | medium | 1 | 6×6 | 12 | 2 |
| H1 | hard | 5 | 7×7 | 10 | 4 |

The six layouts are different. Each opening has more than one legal placement and more than one score. An occupied cell is rejected with the score unchanged. A deterministic legal play reaches `move_limit_reached`. Active content version is `pzd-42-v4`. The previous `pzd-42-uat` manifest stays registered so a claim already stored today can still be published. It does not change into the new boards. Play the new set from a fresh `pzd_uat` database.

Placement preview uses `canPlaceAt` and is drawn only after a piece is selected. It is not a confirmed move. The local engine is not called for a tournament tap. Home's weekly action opens WEEKLY / ALL on the first week returned by the server, which is the current canonical week.

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
2. E1–E3 are 5×5 with 15 moves, M1–M2 are 6×6 with 12, and H1 is 7×7 with 10. Each shows three offers, a selected-piece label, highlighted empty cells, the server score, moves left, and the idle deadline.
3. Weekly from Home opens All on the current week shown by the server. Daily remains a separate action.
4. A rejected tap stays on the board and does not add a local score.
5. After each of E1–M2, the transition shows that game's server score, the series total, and Continue.
6. After H1, Results shows the verified total, Easy / Medium / Hard, the On-Time state, and Return Home.
7. Daily and Weekly open from Home or Results. Back returns to that screen, including after the day is complete.
8. Leaving a game asks first. Home can resume the same series.
9. Player B uses the same command with `PZD_UAT_BEARER_B` and `PZD_UAT_PLAYER="Player B"`.
10. This phone session is a new `pzd_uat` database. An existing claim from earlier today still has the old boards.

Screenshots of this recovery were not captured on the phone. The widget tests cover the completed-day loop at a tall phone size and the home layout at 320, 390, and 430 points, including Turkish copy and a larger text scale.
