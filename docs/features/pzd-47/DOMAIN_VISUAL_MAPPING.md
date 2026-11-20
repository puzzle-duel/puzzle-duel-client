# PZD-47 — Domain → Visual mapping (UAT)

**Status:** Temporary presentation mapping for physical-device UAT.  
**Do not** change generators, match rules, scoring, or serialized wire tokens.

| Domain (`Shape` / wire) | Visual silhouette | Material |
| --- | --- | --- |
| `circle` | Green glossy circle | Unchanged |
| `diamond` | Purple glossy 45° diamond | Unchanged |
| `triangle` | **Golden flat-top hexagon** | Hexagon gold resin |

## Rules

- Serialized piece `shape` values remain `circle` / `diamond` / `triangle`.
- Match logic continues to compare domain shape identity (including `triangle`).
- Accessibility / semantics labels present the third shape as **hexagon**.
- Body orientation is fixed; only the shared single-stroke chevron rotates.
- App icon bottom-left cell uses `Shape.triangle` → hexagon via `PremiumPieceRenderer`.

## Reference

- `docs/features/pzd-47/reference/hexagon-icon-visual-reference.png`
- SHA-256 `dff57723ed17a469f5bd437a589c0f51e5ef970c657248d59638de77c99b689c`
- Material version pin: `pzd47-hexagon-identity-v1`
