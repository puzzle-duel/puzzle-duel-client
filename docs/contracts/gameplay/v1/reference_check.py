#!/usr/bin/env python3
"""Independent PZD-11 walkthrough.

Recomputes golden fixtures from the written contract rules and compares the
result with the JSON. This is not the product engine and it is not imported
by application code. Node's validate.mjs is a separate implementation.
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


def apply_move(state, move):
    code = reject_code(state, move["tap"])
    if code is not None:
        return {"legal": False, "error": {"code": code}, "state": clone(state)}
    nxt = clone(state)
    piece = nxt["offers"][move["offerIndex"]]
    land = landing(nxt, piece, move["tap"])
    nxt["cells"][land[0]][land[1]] = {"shape": piece["shape"], "direction": piece["direction"]}
    waves, nxt["cells"] = collect_waves(nxt["cells"], nxt["blocked"], matches)
    score_delta = sum(wave["scoreDelta"] for wave in waves)
    # Empty futurePieces is unspecified. Abort instead of inventing a replacement.
    if not nxt["futurePieces"]:
        raise RuntimeError("checker abort: empty piece stream is not specified")
    nxt["offers"][move["offerIndex"]] = nxt["futurePieces"].pop(0)
    nxt["turnsUsed"] += 1
    nxt["score"] += score_delta
    nxt["status"] = "ended" if nxt["turnsUsed"] >= nxt["moveLimit"] or empty_legal(nxt) == 0 else "in_progress"
    return {
        "legal": True,
        "landing": land,
        "turnsUsed": nxt["turnsUsed"],
        "scoreDelta": score_delta,
        "waves": waves,
        "finalState": nxt,
    }


def apply_match(given):
    cleared = matches(given["cells"])
    cells = clone(given["cells"])
    for row, col in cleared:
        cells[row][col] = None
    return {"cleared": cleared, "scoreDelta": len(cleared) * 100 * given["wave"], "cells": cells}


def apply_shift(given):
    cells, moved = shift(given["cells"], given["blocked"])
    return {"moved": moved, "cells": cells}


def check_fixture(doc):
    for scenario in doc["scenarios"]:
        label = f"{doc['id']}/{scenario['name']}"
        if doc["kind"] == "fullMove":
            state = clone(scenario["given"]["state"])
            produced = []
            for move, expected in zip(scenario["when"]["moves"], scenario["expected"]["steps"]):
                result = apply_move(state, move)
                produced.append(result)
                found = diff(result, expected)
                if found:
                    fail(f"{label}: {found}")
                state = result["finalState"] if result["legal"] else state
            repeat = scenario["expected"].get("repeat")
            if repeat:
                again = clone(scenario["given"]["state"])
                second = []
                for move in scenario["when"]["moves"]:
                    result = apply_move(again, move)
                    second.append(result)
                    again = result["finalState"] if result["legal"] else again
                found = diff(second, produced)
                if found:
                    fail(f"{label} repeat: {found}")
        elif doc["phase"] == "match":
            found = diff(apply_match(scenario["given"]), scenario["expected"])
            if found:
                fail(f"{label}: {found}")
        else:
            found = diff(apply_shift(scenario["given"]), scenario["expected"])
            if found:
                fail(f"{label}: {found}")


def contract_literals(by_id):
    hand_two_wave = 3 * 100 * 1 + 3 * 100 * 2
    if hand_two_wave != 900:
        fail("hand arithmetic for two waves drifted")
    if 5 * 100 * 1 != 500 or 6 * 100 != 600:
        fail("hand arithmetic for the cross drifted")

    right = by_id["place_right_free"]["scenarios"][0]["expected"]["steps"][0]
    if right["landing"] != [2, 3] or right["turnsUsed"] != 1 or right["scoreDelta"] != 0 or right["waves"] != []:
        fail("place_right_free does not match the contract example")

    blocked = by_id["place_blocked_neighbor"]["scenarios"][0]["expected"]["steps"][0]
    if blocked["landing"] != [2, 2] or blocked["turnsUsed"] != 1 or blocked["scoreDelta"] != 0:
        fail("place_blocked_neighbor does not match the contract example")

    edge = by_id["place_edge"]["scenarios"][0]["expected"]["steps"][0]
    if edge["landing"] != [0, 2]:
        fail("place_edge does not match the contract example")

    horizontal = by_id["horizontal_match"]["scenarios"][0]["expected"]["steps"][0]
    if horizontal["landing"] != [2, 2] or horizontal["scoreDelta"] != 300 or len(horizontal["waves"]) != 1:
        fail("horizontal_match score or wave count drifted")
    if horizontal["waves"][0]["cleared"] != [[2, 0], [2, 1], [2, 2]]:
        fail("horizontal_match clear set drifted")

    cross = by_id["cross_union"]["scenarios"][0]["expected"]
    if cross["scoreDelta"] != 500 or len(cross["cleared"]) != 5 or cross["scoreDelta"] == 600:
        fail("cross_union is not the unique-5 / 500 result")

    contested = by_id["contested_shift"]["scenarios"][0]
    if contested["expected"]["moved"] != [] or contested["expected"]["cells"] != contested["given"]["cells"]:
        fail("contested_shift moved a piece")

    preoccupied = by_id["preoccupied_shift"]["scenarios"][0]["expected"]["cells"]
    if preoccupied[2][1]["direction"] != "right" or preoccupied[2][2] is not None:
        fail("preoccupied_shift let [2,1] enter the occupied cell")

    cascade = by_id["two_wave_cascade"]["scenarios"][0]["expected"]["steps"][0]
    if len(cascade["waves"]) < 2 or cascade["scoreDelta"] != hand_two_wave:
        fail("two_wave_cascade score was not independently recomputed as 900")
    if cascade["waves"][0]["scoreDelta"] != 300 or cascade["waves"][1]["scoreDelta"] != 600:
        fail("two_wave_cascade wave split drifted")

    replay = by_id["replay_determinism"]["scenarios"][0]["expected"]
    if replay["steps"][1]["scoreDelta"] != 300 or replay["steps"][1]["finalState"]["score"] != 600:
        fail("wave multiplier did not reset between player moves")
    if replay["steps"][1]["waves"][0]["wave"] != 1:
        fail("second move did not start again at wave 1")

    reopen = by_id["cascade_reopen_end"]["scenarios"][0]["expected"]["steps"][0]
    if reopen["scoreDelta"] != 300 or reopen["finalState"]["status"] != "in_progress":
        fail("PD-09 reopen with turns remaining did not continue")
    if reopen["finalState"]["turnsUsed"] >= reopen["finalState"]["moveLimit"]:
        fail("PD-09 reopen case exhausted the move limit")
    limited = by_id["cascade_reopen_end"]["scenarios"][1]["expected"]["steps"]
    if limited[0]["scoreDelta"] != 300 or limited[0]["finalState"]["status"] != "ended":
        fail("PD-09 move-limit cascade did not end after resolution")
    if limited[0]["waves"][0]["cleared"] != [[2, 0], [2, 1], [2, 2]]:
        fail("PD-09 move-limit cascade clear set drifted")
    for step in limited[1:]:
        if step["error"]["code"] != "game_ended" or step["state"] != limited[0]["finalState"]:
            fail("PD-10 ended tap changed state or used a cell error")


def check_initial_boards(docs):
    for doc in docs:
        if doc["kind"] != "fullMove":
            continue
        for scenario in doc["scenarios"]:
            if matches(scenario["given"]["state"]["cells"]):
                fail(f"{doc['id']}/{scenario['name']}: initial board already matches")
    phase = next(doc for doc in docs if doc["id"] == "cross_union")
    if not matches(phase["scenarios"][0]["given"]["cells"]):
        fail("match-phase fixture lost its intentional match")
    probe = json.loads((ROOT / "invalid" / "unresolved-initial-match.json").read_text(encoding="utf-8"))
    cells = probe["fixture"]["scenarios"][0]["given"]["state"]["cells"]
    if not matches(cells):
        fail("PD-08 negative probe does not contain a starting match")


def check_empty_stream(by_id):
    state = clone(by_id["place_right_free"]["scenarios"][0]["given"]["state"])
    state["futurePieces"] = []
    original = clone(state)
    try:
        apply_move(state, {"offerIndex": 0, "tap": [2, 2]})
        fail("empty futurePieces invented a replacement")
    except RuntimeError as error:
        if "empty piece stream" not in str(error):
            fail(f"empty stream raised the wrong error: {error}")
    if state != original:
        fail("empty stream mutated the caller state")


def blank_board():
    return [[None for _ in range(5)] for _ in range(5)]


def scripted_find(limit):
    calls = {"n": 0}

    def find(_board):
        calls["n"] += 1
        if calls["n"] <= limit:
            return [[0, 0], [0, 1], [0, 2]]
        return []

    return find


def placed_cascade(doc):
    state = clone(doc["scenarios"][0]["given"]["state"])
    move = doc["scenarios"][0]["when"]["moves"][0]
    piece = state["offers"][move["offerIndex"]]
    land = landing(state, piece, move["tap"])
    state["cells"][land[0]][land[1]] = {"shape": piece["shape"], "direction": piece["direction"]}
    return state


def occupied(board):
    found = []
    for row, cells in enumerate(board):
        for col, cell in enumerate(cells):
            if cell is not None:
                found.append([row, col, cell["shape"]])
    return found


def piece_field(count, size=8):
    board = [[None for _ in range(size)] for _ in range(size)]
    placed = 0
    for row in range(size):
        for col in range(size):
            if placed >= count:
                return board
            board[row][col] = {"shape": "circle", "direction": "up"}
            placed += 1
    return board


def progress_find(limit):
    calls = {"n": 0}

    def find(board):
        calls["n"] += 1
        if calls["n"] > limit:
            return []
        found = []
        for row, cells in enumerate(board):
            for col, cell in enumerate(cells):
                if cell is not None:
                    found.append([row, col])
                    if len(found) == 3:
                        return found
        return found

    return find


def check_boundaries(by_id):
    """Hang-guard and corrupt-cascade checks. Neither is a product wave cap."""
    waves, board = collect_waves(piece_field(60), [], progress_find(CHECKER_WAVE_ABORT), CHECKER_WAVE_ABORT)
    if len(waves) != CHECKER_WAVE_ABORT or waves[-1]["wave"] != CHECKER_WAVE_ABORT or count_occupied(board) != 0:
        fail("exact 20-wave cascade was rejected or truncated")
    if len(waves) > 60 // 3:
        fail("progressing cascade exceeded the piece-removal bound")
    try:
        collect_waves(piece_field(63), [], progress_find(CHECKER_WAVE_ABORT + 1), CHECKER_WAVE_ABORT)
        fail("cascade still matching at the review boundary was accepted")
    except CheckerAbort as error:
        if error.applied != CHECKER_WAVE_ABORT or count_occupied(error.board) != 3:
            fail(f"continuing cascade applied {error.applied} waves")
    waves, _board = collect_waves(piece_field(6), [], progress_find(2), CHECKER_WAVE_ABORT)
    if len(waves) != 2:
        fail("normal short cascade was not accepted")
    try:
        collect_waves(blank_board(), [], scripted_find(5), CHECKER_WAVE_ABORT)
        fail("non-progressing cascade was accepted")
    except CascadeCorrupt as error:
        if error.applied != 0:
            fail(f"non-progressing cascade recorded {error.applied} waves")
    try:
        collect_waves(piece_field(3), [], scripted_find(5), CHECKER_WAVE_ABORT)
        fail("cascade that stops removing pieces was accepted")
    except CascadeCorrupt as error:
        if error.applied != 1:
            fail(f"stalled cascade recorded {error.applied} waves")

    state = placed_cascade(by_id["two_wave_cascade"])
    waves, board = collect_waves(state["cells"], state["blocked"], matches, 2)
    if len(waves) != 2 or sum(wave["scoreDelta"] for wave in waves) != 900:
        fail("real cascade ending exactly on the ceiling was rejected")
    if occupied(board):
        fail("real cascade ending exactly on the ceiling left pieces")

    state = placed_cascade(by_id["two_wave_cascade"])
    try:
        collect_waves(state["cells"], state["blocked"], matches, 1)
        fail("real cascade still matching at the ceiling was accepted")
    except CheckerAbort as error:
        if error.applied != 1:
            fail(f"real continuing cascade applied {error.applied} waves")
        want = [[4, 0, "diamond"], [4, 1, "diamond"], [4, 2, "diamond"]]
        if occupied(error.board) != want:
            fail(f"wave beyond the ceiling was applied or the shift differed: {occupied(error.board)}")

    state = placed_cascade(by_id["two_wave_cascade"])
    bound = count_occupied(state["cells"]) // 3
    waves, board = collect_waves(state["cells"], state["blocked"], matches)
    if len(waves) != 2 or sum(wave["scoreDelta"] for wave in waves) != 900 or occupied(board):
        fail("normal two-wave cascade failed under the default review ceiling")
    if len(waves) > bound:
        fail("normal cascade exceeded the piece-removal bound")


def main():
    docs = []
    for path in sorted(FIXTURES.glob("*.json")):
        docs.append(json.loads(path.read_text(encoding="utf-8")))
    if len(docs) != 13:
        fail(f"expected 12 fixtures, found {len(docs)}")
    by_id = {doc["id"]: doc for doc in docs}
    check_boundaries(by_id)
    check_initial_boards(docs)
    check_empty_stream(by_id)
    contract_literals(by_id)
    for doc in docs:
        check_fixture(doc)
    if FAILURES:
        print("reference_check: FAIL")
        for message in FAILURES:
            print(f"- {message}")
        return 1
    print("reference_check: PASS cascade boundary")
    print("reference_check: PASS 13 golden fixtures")
    print("reference_check: hand arithmetic 3*100*1+3*100*2=900 and 5*100*1=500")
    print("reference_check: NOT_RUN Dart engine, TypeScript product engine, client copy")
    return 0


if __name__ == "__main__":
    sys.exit(main())
