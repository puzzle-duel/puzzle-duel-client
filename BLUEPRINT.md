# Puzzle Duel — Product Blueprint v1.0 (DRAFT)
Status: **Proposed for review** · Scope: Client + Backend · Source of truth for agreed product behavior once accepted.

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

## Difficulty profiles CORE-LEVEL-001
All numbers below are **prototype settings, not validated difficulty**:
| Profile | Board | Turns | Static obstacles | Release |
| --- | --- | --- | --- | --- |
| Easy | 5x5 | 15 | 1 | MVP candidate |
| Medium | 6x6 | 12 | 2 | MVP candidate |
| Hard | 7x7 | 10 | 4 | MVP candidate |
| Monster | 8x8 | 9 | 6 | Experimental POST-MVP |
Grid, turns, initial layout, piece stream and obstacle coordinates must be versioned challenge config. Larger boards alone do not prove higher difficulty. Profiles need playtesting + validity checks. Monster tournament mode is POST-MVP and **not accepted for delivery**.

## Player journeys
- Start as guest, without forced sign-in and without an ad before first play.
- Free play: short sessions, immediate replay, offline-capable, personal best; challenges need sufficient variation and no unwinnable generated layouts without explicit design intent.
- Daily challenge: identical versioned board + ordered piece stream for everyone in the same challenge. One official first attempt; repeats are practice only. Guest can try before connecting account. If identity is linked later, prevent duplicate official attempts, account switching abuse, and replay promotion.
- Global rankings: iOS + Android in **one server-side leaderboard**; no mixing raw scores from different challenge/configs. Daily and all-time definitions need a separate approved metric; do not presume summed raw points is fair.
- MVP has no realtime multiplayer. Invite-to-challenge, league and tournament mechanics are future proposals.

## Identity and competition
Guest identity is local/anonymous; permanent player ID is server-owned. Apple/Google are external verified login methods, **not the primary player ID**. Game Center / Play Games are distinct from sign-in providers. Account linking needs explicit security design; do not auto-merge on email alone.
Ranked submission requires account and backend-verifiable moves. Client-submitted score is informational and never authoritative. One official attempt must be claimed atomically server-side; retries idempotent.

## Ads and money
Initial ad policy hypothesis: first nine **completed games** without forced interstitial; first eligible interstitial only after game #10; later session intervals 8 then 6 completed games; **never less than 6 in MVP**. No mid-game ads or blocking game while ad unavailable. Use feature flags and session counters, clear definitions for session reset, consent, offline and cooldown in ADR before enabling ads.
Optional cosmetic palettes only; no team crest, name or trademark licensing assumption. Basic theme free, theme selection accessible without color dependence. Paid cosmetics / IAP postponed until purchase demand is validated.
Age-appropriate privacy, parental controls where required, ad SDK settings and store regulations MUST be reviewed before release.

## MVP candidates
F01 deterministic puzzle core and animation; F02 instant guest and offline free play; F03 configurable easy/medium/hard; F04 daily challenge and one cross-platform leaderboard; F05 optional verified Apple/Google sign-in; F06 independently validated scores and anti-replay; F07 frequency-capped interstitial policy; F08 small free theme selection (P1); F09 minimal privacy-conscious telemetry, crash tracking and remote configuration.
MVP exclusions: Monster release, tournament/PvP, advanced progression, AI, cash prizes, pay-to-win.

## Acceptance evidence before release
1. Engine golden fixtures: blocked, out of bounds, contested movement, cross match, multi-wave cascade, no-space, exactly-one-move consumption.
2. Client/backend parity across fixture suite and seed/config versions.
3. Ranked attempts: tampering, duplicate submit, concurrent submit, account relink, replay and offline recovery.
4. Playtest first game comprehension, next-round voluntary replays, D1/D7 retention, performance/accessibility. Targets are hypotheses, not proof.
5. Monetization test must measure continuation and churn after ads, not only impressions.

## Governance
Accepted ADRs supersede proposals for technical decisions but may not silently alter accepted game rules. No direct commits to main; changes via feature branch + PR. Product deviations require explicit owner approval, blueprint version update, corresponding tests and ADR where architecture changes. No merge, deploy or store release without approval.
