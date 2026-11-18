# PZD-42 gameplay and navigation recovery

Manual iPhone UAT is still not passed. This note records the audit, the navigation model, and what the owner should play.

## Issue matrix

| Severity | Evidence | Cause | Resolution |
| --- | --- | --- | --- |
| P0 | Completed day opened Results whenever Home refreshed. Leaderboard Back called that refresh, so Daily → Back returned to Results. | `refreshHome()` treated a completed claim as navigation. | Home load stores the day. Back uses the screen that opened the leaderboard. Results Back goes Home. A later Home visit does not claim again. |
| P0 | A rejected or stale move replaced the board with an error page. | Non-200 command responses called the generic failure path. | Stay on the server board, show a player sentence, and keep the error code as a reference. |
| P0 | An unknown command could be mistaken for success, or followed by a different tap. | The in-flight tap was not locked to one body. | The same command object is kept. Another tap is ignored until that command resolves. |
| P1 | Home, transitions, results, and leaderboards were debug layouts. Back sat at the bottom. | The first UAT slice only proved the HTTP path. | Home, overview, play, transition, results, and both leaderboards use the existing arcade tokens. Back is top-left. |
| P1 | Idle time was shown as if it were the puzzle clock. | The payload field is the server idle deadline. | The HUD labels it "Time to move" and shows moves remaining from the authoritative state. |
| P0 | Every accepted move shifted the board. | Pending text, notices, and the score banner were inserted above an `Expanded` board, so its square constraint changed. | The play column keeps a fixed HUD, a 44px feedback slot, a square board viewport, and a 152px offer tray. |
| P0 | Tournament play was silent and had no distinct haptics. | The host forced `SilentGameSfx`, and haptics were only a generic platform call. | The device build uses the existing wav assets. Haptics are event-specific. Sound and haptics live on the Settings screen and persist. |
| P0 | A finished daily tournament left no way to play again. | Practice was not a product path. | Home always offers Practice. It uses the canonical generator locally and never posts a claim, command, or ranked score. |
| P0 | Leaderboard entry was two peer buttons and ALL was the last chip. | Daily and Weekly were separate Home actions. | Home has one Leaderboard action. It opens Weekly / All on the server's current week. Daily is a tab. |
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

Placement preview uses `canPlaceAt` and is drawn only after a piece is selected. It is a 1.2px accent border and a small center dot, not a filled rectangle, and it does not change the cell size. It is not a confirmed move. The local engine is not called for a tournament tap. Home's Leaderboard action opens WEEKLY / ALL on the first week returned by the server, which is the current canonical week. Daily is a tab on that screen. ALL is the combined category, listed first.

A line clear is not animated from a local prediction. After the server accepts a move, a positive score banner is the difference of the two server series scores. A zero difference shows no banner. The device build plays the existing wav assets only after that acceptance: `place.wav` for a selection or a non-scoring placement, `clear.wav` when the server score increases, `reject.wav` for a rejected command, `round_end.wav` when a game ends, and `chain_complete.wav` when the six-game result opens. Rapid repeats are debounced by the existing player. Widget tests keep a silent sink. No music track was added.

Haptics are separate from mute. Selection uses a selection click, an accepted placement a light impact, a rejection a heavy impact, a scoring clear a medium impact, and game or tournament completion a heavy impact. Medium and heavy completion cues are skipped when the platform reduce-motion setting is on. Sound and haptics switches are stored in `pzd-settings.json` beside the UAT session file. Home no longer shows those switches. The gear opens Settings, which has only those two rows, and Back returns Home. The profile icon is reserved for PZD-43 and does not open a profile.

## Stable play frame

On a 390×844 test surface with no safe-area inset, the board viewport is (8, 251) and 374×374 for 5×5, 6×6, and 7×7. The offer tray is y=692 and 152px tall. Those rectangles stayed inside 0.5px through piece selection, an in-flight command, a +0 acceptance, a +12 acceptance, a rejection, and legal-cell highlighting. Cell sides on that surface were about 71.6, 59.7, and 51.1 points. A rotation or a different window size is a new layout, not a move transition.

## Practice

Practice is a route pushed over Home. It is not a tournament place and it does not call the tournament API. The player chooses Easy 5×5/15, Medium 6×6/12, or Hard 7×7/10. Each start calls `generateChallenge` with `gen-001.v1`. The generator's rules identity is `core-001.v2`; practice records keep that identity and set `verifiedRank` to false. They are not server-verified `core-001.v3` results and they do not award On-Time.

A finished session appends one local record: session id, difficulty, rules version, generator version, seed, score, terminal reason, and UTC timestamp. The file keeps the newest 40 records. Seeds increment from `practice-seed.txt` and wrap inside the generator's accepted range. Replay uses the same seed. New puzzle takes the next seed. Leaving a game that already used a move asks first. Backgrounding keeps the in-memory board. Process death does not.

The files live in the same directory as the UAT session file. The device entry currently uses the temporary directory. iOS can purge it, uninstall deletes it, and it does not move to another phone. A durable player profile remains PZD-43 and needs an authenticated profile API. This build does not add that UI or that API.

## Home and Settings

Home is a branded header, a profile icon reserved for PZD-43, a settings gear, one daily-tournament hero, and two equal action cards. The hero uses the claim and board payload for status, the six-stage progression, the verified total when the day is published, and one primary action: play, continue, or view results. Leaderboard and Practice are the only other actions. Sound and haptics are not on Home.

## Leaderboard

Opening Leaderboard from Home selects Weekly, All, and `weeks.first` from `GET /v1/tournament/leaderboards/weeks`. That first value is the backend's current canonical week, not a Monday computed on the phone. Opening it again from Home resets Weekly / All. Opening it from Results does the same reset and Back returns to Results. Weekly and Daily are the segmented control. Previous and next week stay on Weekly and keep the category. All, Easy, Medium, and Hard filter that period, with All first.

The personal card shows `self.rank` and `self.score` from the selected board. It does not infer a rank from a row index or a local score. A missing `self` says the player is unranked. While the first page is still loading, that card and the list say the scores are loading instead of looking empty. Ranks 1, 2, and 3 use gold, silver, and bronze. A podium is drawn only when the payload has at least three rows. One verified row stays one row.

The authenticated leaderboard does not return a display name or a public player id. The current player's row says "You" / "Sen". Every other row says "Player" / "Oyuncu". No username is invented and no identity endpoint was added. Week labels are formatted from the server UTC date, for example `16–22 November 2026`. Provisional and Final stay the server `state`. Practice records never enter this board. A further page is requested only when the response includes `nextCursor`.

A leaderboard request that fails authentication or the writer check still opens the existing recovery screen. That path was not replaced with a second error panel.

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

1. Home shows the branded header, the daily hero, Practice, and one Leaderboard action. Sound and haptics are on the gear screen and survive leaving the app. Home does not jump to Results. Practice remains after the day is complete.
2. E1–E3 are 5×5 with 15 moves, M1–M2 are 6×6 with 12, and H1 is 7×7 with 10. The board does not jump when a move is sent, accepted, rejected, or scored. A +0 placement shows no score banner.
3. With sound on, selection, placement, rejection, a scoring clear, game completion, and the six-game result are audible from the iPhone speaker. Haptics match those events and stop when the switch is off. This has not been confirmed on a phone yet.
4. Leaderboard from Home opens Weekly / All on the current server week. Daily is a tab. Back returns Home. From Results, Back returns to Results.
5. Practice asks for Easy, Medium, or Hard, can be replayed or replaced, and does not change the daily claim or the ranked board.
6. A rejected tap stays on the board and does not add a local score.
7. After each of E1–M2, the transition shows that game's server score, the series total, and Continue.
8. After H1, Results shows the verified total, the six stage scores, Easy / Medium / Hard, the On-Time state, View Leaderboard, Practice, and Return Home.
9. Leaving a ranked game or an in-progress practice game asks first. Home can resume the same ranked series.
10. Player B uses the same command with `PZD_UAT_BEARER_B` and `PZD_UAT_PLAYER="Player B"`. A second device remains `WRITER_NOT_AUTHORIZED`.
11. This phone session needs a new `pzd_uat` database. An existing claim from earlier today still has the old boards.

## Portrait only

The phone build is portrait upright. `main` calls `SystemChrome.setPreferredOrientations` with `portraitUp` after the binding is ready and before `runApp`. iPhone and iPad `Info.plist` arrays list only `UIInterfaceOrientationPortrait`. The Xcode target is universal (`TARGETED_DEVICE_FAMILY` 1 and 2). The Android activity sets `screenOrientation="portrait"`, and the application is `appCategory="game"`.

That Flutter call does not override a window the system has already decided to resize.

iPadOS offers Split View and Slide Over only when an app declares all four orientations. This app does not, so those modes are not offered. Stage Manager can still change the window size of a portrait-only app. The interface stays portrait, but the available area can change, and the board follows that area. `SystemChrome` cannot stop that resize.

Android 16 (API 36, this app's target) ignores `screenOrientation` on screens at least 600dp wide, except phones and apps marked as games. The game category is what keeps the portrait lock on large Android screens. Desktop windowing can still override orientation. The temporary `PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY` opt-out is not used: Android documents that it does not lock large-screen orientation, and API 37 removes it. A physical rotation check is still required.

Physical iPhone audio, haptics, the stable board frame, this visual redesign, and the portrait lock are NOT_RUN. Widget tests cover the frame at 390×844, the completed-day loop, Practice isolation, Settings persistence, and Home at 320, 390, and 430 points, including Turkish copy and a larger text scale.

Rendered review images, not device photos, are in `docs/tournament/uat-evidence/pzd42-visual/`. Open `index.html` for the contact sheet. Those images use labeled test fixtures. The running app does not invent players or scores. Linux CI skips the golden comparison because its pixels differ from these macOS captures. A physical-iPhone visual UAT is still required before this screen set can pass.
