# PZD-43 — Offline-first Practice & performance gate

Status: measurement targets for owner physical iPhone UAT. Widget tests prove functional offline paths; they do **not** mark numerical frame budgets PASS.

## Functional gates (automated + device)

| Gate | Target |
|---|---|
| Cold launch without network | Local Home visible; Practice enabled before any network timeout completes |
| Expired / unauthorized bearer | Practice remains enabled; Tournament shows an in-Home status banner |
| Tournament timeout / offline | No full-screen recovery that blocks Practice |
| Offline Practice Easy/Medium/Hard | Completes locally; never POSTs ranked commands/claims |
| Restart | Practice personal bests survive; identity scopes do not merge |
| Cache | Last-known Tournament Home summary shows explicit stale/offline copy |
| Isolation | Player A snapshot files are never read for Player B or guest |

## Performance targets (physical iPhone only)

Enable marks with `--dart-define=PZD_PERF=true` and Flutter DevTools Performance.

| Metric | Aim |
|---|---|
| Time to first usable local Home | Must not wait for network timeouts |
| Offline Practice entry | Works with airplane mode |
| p95 UI/raster frame (60 Hz) | ≤ 16.7 ms during ordinary Practice moves |
| Repeated long frames | None during ordinary local taps |
| Local tap → visible feedback | < 100 ms (measured) |
| First board presentation | No visible frozen board after difficulty pick |
| Input-critical path | No synchronous disk write on the UI isolate |

## Instrumentation hooks

- `InteractionPerf` marks: `tournament.beginLocal`, `tournament.refresh.*`, `session.startRound.*`, `session.submitTap.*`, `sfx.prepare.*`
- Distinguish Practice (local `applyMove`) from Tournament (server-authoritative; never treat pending HTTP as accepted)

## NOT_RUN until owner device session

Numerical frame-time and tap-latency criteria remain **NOT_RUN** until measured on the owner iPhone.
