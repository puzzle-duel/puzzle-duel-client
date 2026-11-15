# ADR-001 — Client stack
Status: Proposed
Decision candidate: Flutter + Flame for iOS and Android; pure Dart deterministic core independent of rendering. Reconsider performance, accessibility and animation fidelity in spike.
Rationale: one cross-platform ruleset, testability. Risks: platform integrations, maintainable assets and frame pacing.
Acceptance required before implementing platform scaffolding. No backend rules on device treated as trusted ranking.
