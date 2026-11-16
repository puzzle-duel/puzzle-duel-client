# CORE-001.v3 canonical JSON independent test vectors

Status: **SPECIFIED** (minimal atoms) / full GameState hashes **PENDING_FREEZE**
Method: Python 3 `hashlib.sha256` over exact UTF-8 bytes below (not a gameplay engine).

## Escaping rules (normative summary)

- Compact JSON; object keys sorted by UTF-8 bytes.
- Strings: `"` → `\"`, `\` → `\\`; controls `\u00XX` lowercase (enums are ASCII and need no controls).
- Integers: base-10, no `+`, no leading zeros except `0`.
- Reject floats / `-0` / non-ASCII enum tokens.

## Vectors

| ID | Canonical UTF-8 string (exact) | SHA-256 (lowercase hex) | Status |
| --- | --- | --- | --- |
| CV-01 | `{}` | `44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a` | SPECIFIED |
| CV-02 | `{"kind":"spent"}` | `684ab5937663746640cb17fa8b29254454be394376269cdaeca1743a7577fa82` | SPECIFIED |
| CV-03 | `{"direction":"up","kind":"piece","shape":"circle"}` | `1f18d4b9a43e29c7a72d1309f531088c32d792d4e6a31a9a7194637676916186` | SPECIFIED |
| CV-04 | `null` | `74234e98afe7498fb5daf1f36ac2d78acc339464f950703b8c019892f982b90b` | SPECIFIED |
| CV-05 | `0` | `5feceb66ffc86f38d952786c6d696c79c2dbc239dd4e91b46729d73a27fb57e9` | SPECIFIED |
| CV-06 | `900` | `bdc5d8a48c23897906b09a9a3680bd2e9c8b3121edbda36f949800f0959c8d55` | SPECIFIED |
| CV-07 | `"ended"` | `0f27529487e95082cf0bd9f021be1ede2adc650b34db2ba96235d8805ad49bb3` | SPECIFIED |
| CV-08 | `"a\\"b"` (bytes: quote a backslash quote b quote) | `8bbcb681750af483258c5ca72e83c5c397bf66aa01e7c7787c0d212fc1f6fa1d` | SPECIFIED |
| CV-09 | `"a\\\\b"` | `d6b4439bd2d0fecbb8aeb27d4370b0354683ea72adc84cca99b5fe80aa0b62d0` | SPECIFIED |

CV-03 proves key-order independence: authoring `{kind,shape,direction}` must canonicalize to the same bytes as CV-03.

Full `GameState` digests: **PENDING_FREEZE** until dual engines + oracle protocol.
