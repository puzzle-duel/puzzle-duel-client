# core-001.v2 terminal offers

`core-001.v2` adds the owner-approved nullable spent slot. `core-001.v1` stays in `../v1/` and is not rewritten.

`offers` is always length 3. An in-progress tray contains three pieces. After a resolved move that ends the game, an empty `futurePieces` list writes JSON `null` into the consumed slot only. The other slots stay. No replacement is generated. A move that would stay `in_progress` with an empty stream is rejected instead of producing an active null slot.

Out-of-bounds and malformed coordinates have no precedence. No migration from a v1 replay onto v2 is claimed.

```bash
python3 docs/contracts/gameplay/v2/reference_check.py
node docs/contracts/gameplay/v2/validate.mjs
cd docs/contracts/gameplay/v2 && shasum -a 256 -c CHECKSUMS.txt
```

These checkers are not product engines.
