# core-001.v2 terminal offers

`core-001.v2` adds the owner-approved nullable spent slot. `core-001.v1` stays in `../v1/` and is not rewritten.

`offers` is always length 3. An in-progress tray contains three pieces. JSON `null` is written only into the consumed slot when the resolved move reaches `moveLimit` and `futurePieces` is empty. The other slots stay. No replacement is generated. An empty stream on a move that stays `in_progress` is rejected. An empty stream when the board fills before the move limit is not a specified tray: the checkers abort and do not invent a null slot, a leftover piece, or a generated piece. An ended tray has at most one null.

Out-of-bounds and malformed coordinates have no precedence. No migration from a v1 replay onto v2 is claimed.

```bash
python3 docs/contracts/gameplay/v2/reference_check.py
node docs/contracts/gameplay/v2/validate.mjs
cd docs/contracts/gameplay/v2 && shasum -a 256 -c CHECKSUMS.txt
```

These checkers are not product engines.
