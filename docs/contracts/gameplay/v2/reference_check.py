#!/usr/bin/env python3
"""Independent core-001.v2 walkthrough.

Recomputes the v2 terminal-offer fixture. core-001.v1 fixtures stay in v1.
This is not the product engine. Node's validate.mjs is a separate implementation.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT / "fixtures"
DIR = {"up": (-1, 0), "down": (1, 0), "left": (0, -1), "right": (0, 1)}
# Hang-guard for review commands only. The contract defines no wave cap.
CHECKER_WAVE_ABORT = 20
FAILURES: list[str] = []


class CheckerAbort(RuntimeError):
    def __init__(self, applied, board):
        super().__init__("checker abort: cascade has no contracted wave cap")
        self.applied = applied
        self.board = board


class CascadeCorrupt(RuntimeError):
    def __init__(self, applied):
        super().__init__("checker abort: cascade wave did not remove three pieces")
        self.applied = applied


def fail(message: str) -> None:
    FAILURES.append(message)


def clone(value):
    return json.loads(json.dumps(value))


def diff(actual, expected, path: str = "$"):
    if actual == expected:
        return None
    if isinstance(actual, dict) or isinstance(expected, dict):
        if not isinstance(actual, dict) or not isinstance(expected, dict):
            return f"{path}: type mismatch"
        keys = list(dict.fromkeys([*actual.keys(), *expected.keys()]))
        for key in keys:
            if key not in actual or key not in expected:
                return f"{path}.{key}: missing side"
            found = diff(actual[key], expected[key], f"{path}.{key}")
            if found:
                return found
        return None
    if isinstance(actual, list) or isinstance(expected, list):
        if not isinstance(actual, list) or not isinstance(expected, list):
            return f"{path}: type mismatch"
        if len(actual) != len(expected):
            return f"{path}: length {len(actual)} != {len(expected)}"
        for index, (left, right) in enumerate(zip(actual, expected)):
            found = diff(left, right, f"{path}[{index}]")
            if found:
                return found
        return None
    return f"{path}: {actual!r} != {expected!r}"


def blocked_set(blocked):
    return {tuple(item) for item in blocked}


def in_bounds(size, row, col):
    return 0 <= row < size and 0 <= col < size


def matches(cells):
    size = len(cells)
    found = set()
    for row in range(size):
        col = 0
        while col < size:
            piece = cells[row][col]
            if piece is None:
                col += 1
                continue
            end = col + 1
            while end < size and cells[row][end] is not None and cells[row][end]["shape"] == piece["shape"]:
                end += 1
            if end - col >= 3:
                found.update((row, index) for index in range(col, end))
            col = end
    for col in range(size):
        row = 0
        while row < size:
            piece = cells[row][col]
            if piece is None:
                row += 1
                continue
            end = row + 1
            while end < size and cells[end][col] is not None and cells[end][col]["shape"] == piece["shape"]:
                end += 1
            if end - row >= 3:
                found.update((index, col) for index in range(row, end))
            row = end
    return [[row, col] for row, col in sorted(found)]


def shift(cells, blocked):
    size = len(cells)
    obstacles = blocked_set(blocked)
    pieces = []
    occupied = set()
    for row in range(size):
        for col in range(size):
            piece = cells[row][col]
            if piece is not None:
                pieces.append((row, col, piece, row * size + col))
                occupied.add((row, col))
    proposals = []
    for row, col, piece, index in pieces:
        dr, dc = DIR[piece["direction"]]
        tr, tc = row + dr, col + dc
        ok = in_bounds(size, tr, tc) and (tr, tc) not in obstacles and (tr, tc) not in occupied
        proposals.append([row, col, piece, index, tr, tc, ok])
    claims = {}
    for proposal in proposals:
        if proposal[6]:
            key = (proposal[4], proposal[5])
            claims[key] = claims.get(key, 0) + 1
    for proposal in proposals:
        if proposal[6] and claims[(proposal[4], proposal[5])] > 1:
            proposal[6] = False
    nxt = clone(cells)
    for row, col, _piece, _index, _tr, _tc, ok in proposals:
        if ok:
            nxt[row][col] = None
    moved = []
    for row, col, piece, index, tr, tc, ok in proposals:
        if not ok:
            continue
        nxt[tr][tc] = {"shape": piece["shape"], "direction": piece["direction"]}
        moved.append({
            "sourceIndex": index,
            "from": [row, col],
            "to": [tr, tc],
            "shape": piece["shape"],
            "direction": piece["direction"],
        })
    moved.sort(key=lambda item: item["sourceIndex"])
    return nxt, moved


def empty_legal(state):
    obstacles = blocked_set(state["blocked"])
    count = 0
    size = state["boardSize"]
    for row in range(size):
        for col in range(size):
            if state["cells"][row][col] is None and (row, col) not in obstacles:
                count += 1
    return count


def landing(state, piece, tap):
    row, col = tap
    dr, dc = DIR[piece["direction"]]
    tr, tc = row + dr, col + dc
    obstacles = blocked_set(state["blocked"])
    if in_bounds(state["boardSize"], tr, tc) and (tr, tc) not in obstacles and state["cells"][tr][tc] is None:
        return [tr, tc]
    return [row, col]


def reject_code(state, tap):
    if state["status"] != "in_progress":
        return "game_ended"
    row, col = tap
    obstacles = blocked_set(state["blocked"])
    if (row, col) in obstacles:
        return "blocked_tap"
    if state["cells"][row][col] is not None:
        return "occupied_tap"
    return None


def count_occupied(board):
    return sum(cell is not None for row in board for cell in row)


def removable(board, cleared):
    seen = set()
    unique = []
    size = len(board)
    for row, col in cleared:
        key = (row, col)
        if key in seen:
            continue
        seen.add(key)
        if 0 <= row < size and 0 <= col < size and board[row][col] is not None:
            unique.append(key)
    return unique


def collect_waves(cells, blocked, find, ceiling=CHECKER_WAVE_ABORT):
    """Apply clears until `find` is empty. Do not apply a wave past `ceiling`.

    A cascade that finishes on wave `ceiling` is returned. A match that would
    start another wave raises CheckerAbort. `ceiling` is a review hang-guard,
    not a gameplay wave cap. A proposed clear that does not remove at least
    three occupied cells raises CascadeCorrupt and is not recorded.
    """
    board = cells
    waves = []
    while len(waves) < ceiling:
        cleared = find(board)
        if not cleared:
            break
        before = count_occupied(board)
        targets = removable(board, cleared)
        if len(targets) < 3:
            raise CascadeCorrupt(len(waves))
        for row, col in targets:
            board[row][col] = None
        board, moved = shift(board, blocked)
        if count_occupied(board) != before - len(targets):
            raise CascadeCorrupt(len(waves))
        wave_no = len(waves) + 1
        waves.append({
            "wave": wave_no,
            "cleared": cleared,
            "scoreDelta": len(cleared) * 100 * wave_no,
            "moved": moved,
        })
    if find(board):
        raise CheckerAbort(len(waves), board)
    return waves, board



def offer_issues(state):
    offers = state.get("offers")
    if not isinstance(offers, list) or len(offers) != 3:
        return ["malformed_offers"]
    nulls = sum(slot is None for slot in offers)
    issues = []
    if state.get("status") == "in_progress" and nulls:
        issues.append("null_offer_while_active")
    if nulls > 1:
        issues.append("multiple_null_offers")
    return issues


def apply_move(state, move):
    tray = offer_issues(state)
    if "multiple_null_offers" in tray:
        raise RuntimeError("checker abort: multiple null offers")
    if "null_offer_while_active" in tray:
        raise RuntimeError("checker abort: null offer in an active tray")
    code = reject_code(state, move["tap"])
    if code is not None:
        return {"legal": False, "error": {"code": code}, "state": clone(state)}
    nxt = clone(state)
    piece = nxt["offers"][move["offerIndex"]]
    land = landing(nxt, piece, move["tap"])
    nxt["cells"][land[0]][land[1]] = {"shape": piece["shape"], "direction": piece["direction"]}
    waves, nxt["cells"] = collect_waves(nxt["cells"], nxt["blocked"], matches)
    score_delta = sum(wave["scoreDelta"] for wave in waves)
    nxt["turnsUsed"] += 1
    nxt["score"] += score_delta
    # Null is approved only for the move-budget final move. An early full board
    # with an empty stream has no chosen tray, so it is not written as null.
    budget_exhausted = nxt["turnsUsed"] >= nxt["moveLimit"]
    board_full = empty_legal(nxt) == 0
    if not nxt["futurePieces"]:
        if budget_exhausted:
            nxt["offers"][move["offerIndex"]] = None
        elif board_full:
            raise RuntimeError("checker abort: empty piece stream on early board end is not specified")
        else:
            raise RuntimeError("checker abort: empty piece stream before the game has ended")
    else:
        nxt["offers"][move["offerIndex"]] = nxt["futurePieces"].pop(0)
    nxt["status"] = "ended" if budget_exhausted or board_full else "in_progress"
    if nxt["status"] == "in_progress" and any(slot is None for slot in nxt["offers"]):
        raise RuntimeError("checker abort: null offer in an active tray")
    return {
        "legal": True,
        "landing": land,
        "turnsUsed": nxt["turnsUsed"],
        "scoreDelta": score_delta,
        "waves": waves,
        "finalState": nxt,
    }


def check_fixture(doc):
    if doc.get("rulesVersion") != "core-001.v2":
        fail(f"{doc.get('id')}: rulesVersion")
    for scenario in doc["scenarios"]:
        label = f"{doc['id']}/{scenario['name']}"
        state = clone(scenario["given"]["state"])
        for move, expected in zip(scenario["when"]["moves"], scenario["expected"]["steps"]):
            result = apply_move(state, move)
            found = diff(result, expected)
            if found:
                fail(f"{label}: {found}")
            state = result["finalState"] if result["legal"] else state


def check_terminal(doc):
    given = doc["scenarios"][0]["given"]["state"]
    step = doc["scenarios"][0]["expected"]["steps"][0]
    offers = step["finalState"]["offers"]
    if len(offers) != 3 or offers[0] is not None:
        fail("terminal slot was not null inside a length-3 tray")
    if offers[1] != given["offers"][1] or offers[2] != given["offers"][2]:
        fail("unconsumed offer slots changed")
    if step["finalState"]["futurePieces"] != []:
        fail("a replacement piece was invented")
    if step["scoreDelta"] != 300 or not step["waves"] or step["finalState"]["status"] != "ended":
        fail("terminal cascade score was not preserved")
    if step["waves"][0]["cleared"] != [[2, 0], [2, 1], [2, 2]]:
        fail("terminal clear set drifted")
    for later in doc["scenarios"][0]["expected"]["steps"][1:]:
        if later["error"]["code"] != "game_ended" or later["state"] != step["finalState"]:
            fail("post-end tap mutated state or skipped game_ended")


def check_early_stream(doc):
    state = clone(doc["scenarios"][0]["given"]["state"])
    state["moveLimit"] = 5
    state["futurePieces"] = []
    original = clone(state)
    try:
        apply_move(state, {"offerIndex": 0, "tap": [2, 2]})
        fail("empty stream before the end produced an active state")
    except RuntimeError as error:
        if "before the game has ended" not in str(error):
            fail(f"early empty stream raised the wrong error: {error}")
    if state != original:
        fail("early empty stream mutated the caller state")


def check_active_null():
    probe = json.loads((ROOT / "invalid" / "null-offer-while-active.json").read_text(encoding="utf-8"))
    state = probe["fixture"]["scenarios"][0]["given"]["state"]
    if probe["expectCode"] != "null_offer_while_active" or offer_issues(state) != ["null_offer_while_active"]:
        fail("active-null probe is not an in-progress null slot")
    original = clone(state)
    try:
        apply_move(state, {"offerIndex": 0, "tap": [2, 2]})
        fail("an active null offer was playable")
    except RuntimeError as error:
        if "null offer" not in str(error):
            fail(f"active null raised the wrong error: {error}")
    if state != original:
        fail("active null mutated the caller state")


def check_early_board_end():
    probe = json.loads((ROOT / "invalid" / "early-board-end-empty-stream.json").read_text(encoding="utf-8"))
    state = probe["state"]
    if state["futurePieces"] or state["turnsUsed"] >= state["moveLimit"] or empty_legal(state) != 1:
        fail("early-board probe is not one empty cell before the move limit")
    original = clone(state)
    try:
        apply_move(state, probe["move"])
        fail("early board end with an empty stream produced a tray")
    except RuntimeError as error:
        if "early board end is not specified" not in str(error):
            fail(f"early board end raised the wrong error: {error}")
    if state != original:
        fail("early board end mutated the caller state")


def check_offer_counts():
    probe = json.loads((ROOT / "invalid" / "terminal-offer-counts.json").read_text(encoding="utf-8"))
    seen = {case["name"] for case in probe["cases"]}
    if seen != {"two_nulls", "three_nulls", "null_while_active", "one_spent_slot"}:
        fail(f"offer-count cases drifted: {sorted(seen)}")
    for case in probe["cases"]:
        state = case["state"]
        if offer_issues(state) != case["expectCodes"]:
            fail(f"{case['name']}: offer issues {offer_issues(state)} != {case['expectCodes']}")
        original = clone(state)
        if case["name"] == "one_spent_slot":
            result = apply_move(state, {"offerIndex": 1, "tap": [0, 0]})
            if result["error"]["code"] != "game_ended" or result["state"] != original:
                fail("one spent slot did not return game_ended unchanged")
            continue
        try:
            apply_move(state, {"offerIndex": 0, "tap": [0, 0]})
            fail(f"{case['name']} was playable")
        except RuntimeError as error:
            text = str(error)
            if case["name"] == "null_while_active" and "null offer" not in text:
                fail(f"{case['name']} raised the wrong error: {error}")
            if case["name"] in {"two_nulls", "three_nulls"} and "multiple null offers" not in text:
                fail(f"{case['name']} raised the wrong error: {error}")
        if state != original:
            fail(f"{case['name']} mutated the caller state")


def check_schema_null_limit():
    schema = json.loads((ROOT / "fixture.schema.json").read_text(encoding="utf-8"))
    rules = schema["$defs"]["state"]["allOf"]
    ended = next(rule for rule in rules if rule["if"]["properties"]["status"]["const"] == "ended")
    offers = ended["then"]["properties"]["offers"]
    if offers.get("minContains") != 0 or offers.get("maxContains") != 1:
        fail("schema does not limit an ended tray to at most one null")
    active = next(rule for rule in rules if rule["if"]["properties"]["status"]["const"] == "in_progress")
    if active["then"]["properties"]["offers"]["items"].get("$ref") != "#/$defs/piece":
        fail("schema still allows null in an active tray")


def main():
    docs = [json.loads(path.read_text(encoding="utf-8")) for path in sorted(FIXTURES.glob("*.json"))]
    if len(docs) != 1 or docs[0]["id"] != "terminal_null_slot":
        fail(f"expected the terminal_null_slot fixture, found {[doc.get('id') for doc in docs]}")
    else:
        check_fixture(docs[0])
        check_terminal(docs[0])
        check_early_stream(docs[0])
    check_active_null()
    check_early_board_end()
    check_offer_counts()
    check_schema_null_limit()
    if FAILURES:
        print("reference_check: FAIL")
        for message in FAILURES:
            print(f"- {message}")
        return 1
    print("reference_check: PASS core-001.v2 terminal null slot")
    print("reference_check: PASS early empty stream does not create an active null tray")
    print("reference_check: PASS early board end with an empty stream is not a null slot")
    print("reference_check: PASS active null offer is rejected")
    print("reference_check: PASS ended tray allows one null and rejects more")
    print("reference_check: NOT_RUN product engines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
