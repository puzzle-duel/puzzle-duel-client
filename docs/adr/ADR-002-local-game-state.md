# ADR-002 — Guest, offline and local state
Status: Proposed
Local guest identity and free-play progress persist with bounded data; official attempts require remote transaction and verified identity. Persist resumable session if product approves. Do not leak account tokens, do not falsely mark offline scores as ranked. Decide exact retry/eviction and account upgrade semantics before shipping.

## PZD-14 compatibility note

Status stays Proposed. This note does not accept the ADR and does not add storage.

When resume is later specified, the saved attempt must include its `rulesVersion`. A `core-001.v1` save is not replayed as `core-001.v2`, and the reverse is not allowed. A locally computed score is never marked ranked. Official ranking stays on the server replay. See [PZD-14-GAMEPLAY-PARITY.md](../architecture/PZD-14-GAMEPLAY-PARITY.md).
