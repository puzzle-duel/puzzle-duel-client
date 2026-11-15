# Puzzle Duel — Product Blueprint v1.0 (DRAFT)
Status: **DRAFT — owner product decisions recorded; final review/acceptance pending** · Scope: Client + Backend · Ruleset: **`core-001.v1`** · Source of truth for agreed product behavior only once accepted.

**Decision basis:** PZD-10 PD-01...PD-13, owner responses recorded 2026-11-15 in `docs/product/PZD-10-DECISION-GATE.md`. This is a review-branch draft, not a merged or accepted product release. PD-05 ad counter persistence is approved but consent/cadence/rollout remain pending.

## Vision and non-goals
A 2D, one-finger, accessible strategy puzzle for broad ages. Three motivations: beat others, improve personal best, casually exercise thinking. Monetization must never alter ranked fairness.
Do not claim commercial viability is proven; V4.0 is a liked interaction prototype, not validated retention or revenue.
Non-goals for MVP: realtime PvP, friend matchmaking, tournament engine, paid competitive boosts, season pass, subscriptions, AI, traffic/vehicle theme, 3x bonus, auto move hints.

## Gameplay invariant CORE-001
- A square NxN grid contains three distinct shapes (circle, diamond, triangle), each with a direction (up, right, down, left), and optional static blocked cells.
- Each move: select one of three offered pieces, tap an empty grid cell. If the immediately adjacent cell in the piece's arrow direction is in bounds and empty/unblocked, **land there**, otherwise land on tapped cell. One placement consumes one move.
- Detect horizontal and vertical runs of >=3 of the same shape; union overlapping runs, clear each cell once.
- After each clear, every remaining piece attempts to move **one cell** along its arrow. A piece cannot enter a cell occupied at the start of the movement phase, blocked cell, or edge; simultaneous claims to one destination fail for all claimants. Then test matches again, repeat until none. No 3x/booster tiles.
- Score per cleared piece = 100 × cascade wave number (first wave 1, second 2, ...). No points for raw placements or movement. Use integer arithmetic.
- No highlighted potential landing cells; only selected-tray-piece emphasis. Show readable movement/clear/cascade animations; reduced-motion alternative required.
- The client and backend MUST implement identical rules, including edge cases. Canonical test vectors must pin results before production.
- **Ruleset version:** `core-001.v1` is the first official gameplay rules identifier. Any normative gameplay rule change requires a new version; ranked game records must retain the rules version under which they were started so historical replay uses that version, not the latest deployed rules. Production API field naming, status enum and error code catalog remain separate contract decisions (PD-13).
- **Board generation (PD-08):** initial playable board MUST contain no horizontal/vertical run of 3+ identical shapes. Only a legal player placement triggers first matching and scoring; no pregame auto-clear.
- **Piece supply (PD-07):** determine a finite ordered supply before game start, sufficient for the configured move budget. There is no on-demand random replenishment. No replacement piece is required after the final permitted move; the final offer tray/stream representation requires a versioned contract extension and updated PZD-11 edge-case vectors.
- **Movement event (PD-11):** canonical `moved` includes successful cell-changing moves only, ordered by initial source row-major within each shift; stationary failed attempts are omitted.
- **Cascade completion/game end (PD-09, PD-12):** resolve all valid match/clear/move cascade waves and score before checking termination against remaining move budget and final available unblocked empty cells. A last-cell placement that opens space through cascade is not game over if turns remain. Never cut off legitimate cascades after an arbitrary wave count. Detect malformed non-progress/non-terminating states separately and fail safely/deterministically; the PZD-11 checker 20-wave guard is not a gameplay limit.
- **Ended state input (PD-10):** when a game is already ended, an in-bounds tap on blocked or occupied space returns `game_ended` before those cell errors; the game state does not change. Malformed/out-of-bounds input precedence still requires a separately approved contract.

## Difficulty profiles CORE-LEVEL-001
All numbers below are **owner-approved, versioned, tunable MVP starting settings (PD-06), not validated difficulty**:
| Profile | Board | Turns | Static obstacles | Release |
| --- | --- | --- | --- | --- |
| Easy | 5x5 | 15 | 1 | MVP approved starting profile |
| Medium | 6x6 | 12 | 2 | MVP approved starting profile |
| Hard | 7x7 | 10 | 4 | MVP approved starting profile |
| Monster | 8x8 | 9 | 6 | Experimental POST-MVP |
Grid, turns, initial layout, piece stream and obstacle coordinates must be versioned challenge config. Larger boards alone do not prove higher difficulty. Profiles need playtesting + validity checks. Monster tournament mode is POST-MVP and **not accepted for delivery**.

## Player journeys
- Start as guest, without forced sign-in and without an ad before first play.
- Free play: short sessions, immediate replay, offline-capable, personal best; challenges need sufficient variation and no unwinnable generated layouts without explicit design intent.
- Daily challenge: one globally shared challenge-day cutoff at **00:00 UTC** (PD-02), with local-time display permitted. All participants in one daily challenge share an identical versioned board, ordered piece stream and difficulty config. The one official attempt is reserved **at start**, not at score submission (PD-01). A player may resume an interrupted **same** official attempt but may not open another official attempt that day; repeats are practice only. Server-side claiming/resume/idempotency mechanics require later detailed contract. Guest practice is never retrospectively promoted into an official ranked result (PD-04).
- Global **daily-only leaderboard** for MVP: iOS + Android compete on the **same server-side per-challenge ranking** using backend-verified official attempts (PD-03). Do not mix scores from different daily challenge/config versions. **All-time/lifetime rankings are post-MVP**, not part of v1 endpoints or UI; a lifetime metric remains unapproved.
- MVP has no realtime multiplayer. Invite-to-challenge, league and tournament mechanics are future proposals.

## Identity and competition
Guest identity is local/anonymous; permanent player ID is server-owned. Apple/Google are external verified login methods, **not the primary player ID**. Game Center / Play Games are distinct from sign-in providers. Account linking needs explicit security design; do not auto-merge on email alone. **Preserve local guest progress, practice history and personal best** after Apple/Google linking (PD-04). Only independently server-verified official attempts contribute to rankings; local guest practice results cannot be promoted retroactively. Cross-device merge/conflict behavior remains a later spec.
Ranked submission requires account and backend-verifiable moves. Client-submitted score is informational and never authoritative. One official attempt must be claimed atomically at official challenge **start** server-side; subsequent resume/finalize must not grant a second attempt. Claim/resume/finalize, expiry and retry idempotency semantics still require review.

## Ads and money
Initial ad policy hypothesis: first nine **completed games** without forced interstitial; first eligible interstitial only after game #10; later session intervals 8 then 6 completed games; **never less than 6 in MVP**. No mid-game ads or blocking game while ad unavailable. **PD-05 approved rule:** completed-game advertising counter persists across app termination/force quit/relaunch; reopening must not reset it. Use feature flags; consent, age compliance, actual ad cadence eligibility, cooldown, offline counting, reinstall/account-switch handling and rollout require further ADR/spec approval **before serving ads**. The above cadence remains a hypothesis, not final ad-shipping authorization.
Optional cosmetic palettes only; no team crest, name or trademark licensing assumption. Basic theme free, theme selection accessible without color dependence. Paid cosmetics / IAP postponed until purchase demand is validated.
Age-appropriate privacy, parental controls where required, ad SDK settings and store regulations MUST be reviewed before release.

## MVP candidates
F01 deterministic puzzle core and animation; F02 instant guest and offline free play; F03 configurable easy/medium/hard; F04 daily challenge and one cross-platform **daily-only** leaderboard; F05 optional verified Apple/Google sign-in; F06 independently validated scores and anti-replay; F07 frequency-capped interstitial policy; F08 small free theme selection (P1); F09 minimal privacy-conscious telemetry, crash tracking and remote configuration.
MVP exclusions: Monster release, tournament/PvP, advanced progression, **all-time leaderboard**, AI, cash prizes, pay-to-win.

## Acceptance evidence before release
1. Engine golden fixtures: blocked, out of bounds, contested movement, cross match, multi-wave cascade, no-space, exactly-one-move consumption.
2. Client/backend parity across fixture suite and seed/config versions.
3. Ranked attempts: tampering, duplicate submit, concurrent submit, account relink, replay and offline recovery.
4. Playtest first game comprehension, next-round voluntary replays, D1/D7 retention, performance/accessibility. Targets are hypotheses, not proof.
5. Monetization test must measure continuation and churn after ads, not only impressions.

## Open technical contract boundaries (not silently approved by PD-01...PD-13)
- Final-move piece offer representation and PZD-11 fixture compatibility (PD-07).
- Malformed/restored game state and input-coordinate error precedence (PD-08/PD-10).
- Formal cascade termination/fault semantics and client/backend engine parity test coverage (PD-12).
- Authentication, account-switching, interruption resume, official attempt expiry/idempotent claim and score finalization (PD-01/PD-04).
- Typed transport error/status vocabulary, canonical API field names and historical rules support policy (PD-13).
- Ad consent/privacy/age, actual cadence and cooldown, offline counters, rollout (PD-05; keep ads disabled until reviewed).
- PZD-11 currently provides fixture/checker parity, **not production engine parity**. New last-move/ended-state/cascade regression cases need versioned review without unapproved fixture mutation.

## Governance
Accepted ADRs supersede proposals for technical decisions but may not silently alter accepted game rules. No direct commits to main; changes via feature branch + PR. Product deviations require explicit owner approval, blueprint version update, corresponding tests and ADR where architecture changes. No merge, deploy or store release without approval.
