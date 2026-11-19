# PZD-43 — Player Profile (practice records & badge collection)

## Scope

Personal overview, version-aware Easy/Medium/Hard practice bests, and a data-driven badge grid. Distinct from official Tournament leaderboards.

## Persistence

- Device-local JSON via `PracticeStore`, scoped by sanitized player label.
- History capped at 40 rows; personal bests survive pruning.
- Practice ruleset for free play remains `core-001.v2` / `gen-001.v1`.
- Never uploaded to ranked claim/publication/leaderboard APIs.
- Guest scope does not auto-merge into signed-in scope.
- Reinstall / wiped temp directory loses data (same limitation as PZD-42 UAT state).

## Badges

- Catalog is data-driven (`badge_catalog.dart`). v1 ships On-Time only.
- Earned counts come from `GET /v1/tournament/me/badges` (candidate backend).
- Offline / unauthorized / error states show locked tiles without fabricating counts.
- Practice completions never grant On-Time.

## Navigation

Home profile icon → `PlayerProfileScreen` (imperative `Navigator.push`). Back returns to Home without resetting an active tournament route.

## Physical iPhone UAT checklist

Manual owner testing remains `NOT_RUN` until performed.

1. Home → Profile
2. Profile → Home
3. First practice completion appears on Profile
4. New personal best replaces prior score
5. Lower score does not replace personal best
6. Easy / Medium / Hard isolation
7. Force-quit and relaunch; bests remain
8. Airplane mode: practice records still visible; badge banner shows offline + retry
9. Tournament results remain separate from practice bests
10. On-Time earned/locked presentation matches server
11. Badge detail sheet shows rule + provenance
12. Switch `PZD_UAT_PLAYER` (or equivalent label): no cross-player practice leak
13. Dynamic Type / small iPhone layout
14. VoiceOver labels on profile header and badge tiles
15. TR and EN copy
16. After completed Tournament, Profile navigation still works (no loop)

### Launch (UAT defines)

Use the project’s existing Tournament UAT launch with bearer/base URL defines from PZD-42. Example shape:

```bash
cd apps/mobile
flutter run --dart-define=PZD_UAT_BASE_URL=<uat-base> \
  --dart-define=PZD_UAT_BEARER=<bearer> \
  --dart-define=PZD_UAT_PLAYER=<label>
```

Exact values come from the owner’s UAT server (`uat:issue` / `uat:server`) — never commit live tokens.
