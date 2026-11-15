import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const RV = "core-001.v1";
// Hang-guard for review commands only. The contract defines no wave cap.
const CHECKER_WAVE_ABORT = 20;
const SHAPES = new Set(["circle", "diamond", "triangle"]);
const DIRS = new Set(["up", "right", "down", "left"]);
const DELTA = { up: [-1, 0], down: [1, 0], left: [0, -1], right: [0, 1] };
const RULES = [
  "CORE-001",
  "PZD-11-PLACEMENT",
  "PZD-11-INVALID-MOVE",
  "PZD-11-MATCH",
  "PZD-11-SHIFT",
  "PZD-11-SCORE",
  "PZD-11-END",
  "PZD-11-OFFER-STREAM",
  "PZD-11-REPLAY",
];
const CATALOG = [
  ["01-place-right-free.json", "place_right_free", "fullMove", 1],
  ["02-place-blocked-neighbor.json", "place_blocked_neighbor", "fullMove", 2],
  ["03-place-edge.json", "place_edge", "fullMove", 3],
  ["04-illegal-tap.json", "illegal_tap", "fullMove", 4],
  ["05-horizontal-match.json", "horizontal_match", "fullMove", 5],
  ["06-cross-union.json", "cross_union", "phase", 6, "match"],
  ["07-contested-shift.json", "contested_shift", "phase", 7, "shift"],
  ["08-preoccupied-shift.json", "preoccupied_shift", "phase", 8, "shift"],
  ["09-blocked-shift.json", "blocked_shift", "phase", 9, "shift"],
  ["10-two-wave-cascade.json", "two_wave_cascade", "fullMove", 10],
  ["11-end-conditions.json", "end_conditions", "fullMove", 11],
  ["12-replay-determinism.json", "replay_determinism", "fullMove", 12],
];
const INVALID = [
  ["duplicate-blocked.json", "duplicate_blocked"],
  ["blocked-out-of-range.json", "blocked_out_of_range"],
  ["malformed-shape.json", "malformed_shape"],
  ["malformed-direction.json", "malformed_direction"],
  ["illegal-turn-count.json", "illegal_turn_count"],
  ["unknown-rules-version.json", "unknown_rules_version"],
  ["blocked-cell-occupied.json", "blocked_cell_occupied"],
  ["malformed-offers.json", "malformed_offers"],
  ["extra-piece-property.json", "unexpected_property"],
];

const errors = [];
const fail = (message) => errors.push(message);
const clone = (value) => JSON.parse(JSON.stringify(value));
const load = (file) => JSON.parse(readFileSync(file, "utf8"));

function diff(actual, expected, at = "$") {
  if (Object.is(actual, expected)) return null;
  if (actual === null || expected === null || typeof actual !== "object" || typeof expected !== "object") {
    return `${at}: ${JSON.stringify(actual)} !== ${JSON.stringify(expected)}`;
  }
  if (Array.isArray(actual) || Array.isArray(expected)) {
    if (!Array.isArray(actual) || !Array.isArray(expected)) return `${at}: array mismatch`;
    if (actual.length !== expected.length) return `${at}: length ${actual.length} !== ${expected.length}`;
    for (let i = 0; i < actual.length; i += 1) {
      const found = diff(actual[i], expected[i], `${at}[${i}]`);
      if (found) return found;
    }
    return null;
  }
  const keys = [...new Set([...Object.keys(actual), ...Object.keys(expected)])];
  for (const key of keys) {
    if (!Object.prototype.hasOwnProperty.call(actual, key) || !Object.prototype.hasOwnProperty.call(expected, key)) {
      return `${at}.${key}: missing side`;
    }
    const found = diff(actual[key], expected[key], `${at}.${key}`);
    if (found) return found;
  }
  return null;
}

function exactKeys(obj, keys, label) {
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) {
    fail(`${label}: expected object`);
    return false;
  }
  const actual = Object.keys(obj);
  const missing = keys.filter((key) => !actual.includes(key));
  const extra = actual.filter((key) => !keys.includes(key));
  if (missing.length || extra.length) {
    fail(`${label}: missing [${missing.join(", ")}] extra [${extra.join(", ")}]`);
    return false;
  }
  return true;
}

function rowMajor(coords, label) {
  for (let i = 1; i < coords.length; i += 1) {
    const [r0, c0] = coords[i - 1];
    const [r1, c1] = coords[i];
    if (r1 < r0 || (r1 === r0 && c1 <= c0)) fail(`${label}: not strictly row-major`);
  }
}

function scanPiece(piece, issues) {
  if (!piece || typeof piece !== "object" || Array.isArray(piece)) {
    issues.push("malformed_piece");
    return;
  }
  const extra = Object.keys(piece).filter((key) => key !== "shape" && key !== "direction");
  if (extra.length) issues.push("unexpected_property");
  if (!SHAPES.has(piece.shape)) issues.push("malformed_shape");
  if (!DIRS.has(piece.direction)) issues.push("malformed_direction");
}

function scanBlocked(boardSize, blocked, cells, issues) {
  const seen = new Set();
  for (const item of blocked ?? []) {
    if (!Array.isArray(item) || item.length !== 2 || !Number.isInteger(item[0]) || !Number.isInteger(item[1])) {
      issues.push("blocked_out_of_range");
      continue;
    }
    const [row, col] = item;
    const key = `${row},${col}`;
    if (seen.has(key)) issues.push("duplicate_blocked");
    seen.add(key);
    if (row < 0 || col < 0 || row >= boardSize || col >= boardSize) {
      issues.push("blocked_out_of_range");
      continue;
    }
    if (cells?.[row]?.[col] != null) issues.push("blocked_cell_occupied");
  }
}

function scanCells(boardSize, cells, issues) {
  if (!Array.isArray(cells) || cells.length !== boardSize) {
    issues.push("malformed_board");
    return;
  }
  for (const row of cells) {
    if (!Array.isArray(row) || row.length !== boardSize) {
      issues.push("malformed_board");
      continue;
    }
    for (const cell of row) if (cell !== null) scanPiece(cell, issues);
  }
}

function emptyLegal(state) {
  const blocked = new Set((state.blocked ?? []).map(([row, col]) => `${row},${col}`));
  let count = 0;
  for (let row = 0; row < state.boardSize; row += 1) {
    for (let col = 0; col < state.boardSize; col += 1) {
      if (state.cells[row][col] === null && !blocked.has(`${row},${col}`)) count += 1;
    }
  }
  return count;
}

function scanState(state, issues) {
  if (!state || typeof state !== "object") {
    issues.push("malformed_board");
    return;
  }
  if (state.rulesVersion !== RV) issues.push("unknown_rules_version");
  if (!Number.isInteger(state.boardSize) || state.boardSize < 1) issues.push("malformed_board");
  scanCells(state.boardSize, state.cells, issues);
  scanBlocked(state.boardSize, state.blocked, state.cells, issues);
  if (!Array.isArray(state.offers) || state.offers.length !== 3) issues.push("malformed_offers");
  else state.offers.forEach((piece) => scanPiece(piece, issues));
  if (!Array.isArray(state.futurePieces)) issues.push("malformed_offers");
  else state.futurePieces.forEach((piece) => scanPiece(piece, issues));
  const turnsOk = Number.isInteger(state.moveLimit) && Number.isInteger(state.turnsUsed)
    && state.moveLimit >= 1 && state.turnsUsed >= 0 && state.turnsUsed <= state.moveLimit;
  if (!turnsOk) issues.push("illegal_turn_count");
  else if (Array.isArray(state.cells) && state.cells.length === state.boardSize) {
    const ended = state.turnsUsed >= state.moveLimit || emptyLegal(state) === 0;
    if ((state.status === "ended") !== ended || (state.status !== "in_progress" && state.status !== "ended")) {
      issues.push("inconsistent_status");
    }
  }
  if (!Number.isInteger(state.score) || state.score < 0) issues.push("malformed_score");
}

function issuesFor(doc) {
  const issues = [];
  if (doc.rulesVersion !== RV) issues.push("unknown_rules_version");
  if (doc.kind === "fullMove") {
    for (const scenario of doc.scenarios ?? []) {
      scanState(scenario.given?.state, issues);
      if (scenario.given?.state?.cells && findMatches(scenario.given.state.cells).length > 0) {
        issues.push("unresolved_initial_match");
      }
    }
  } else {
    for (const scenario of doc.scenarios ?? []) {
      const given = scenario.given ?? {};
      if (given.rulesVersion !== RV) issues.push("unknown_rules_version");
      scanCells(given.boardSize, given.cells, issues);
      scanBlocked(given.boardSize, given.blocked, given.cells, issues);
    }
  }
  return [...new Set(issues)];
}

function findMatches(cells) {
  const size = cells.length;
  const hit = Array.from({ length: size }, () => Array(size).fill(false));
  for (let row = 0; row < size; row += 1) {
    let col = 0;
    while (col < size) {
      const piece = cells[row][col];
      if (!piece) {
        col += 1;
        continue;
      }
      let end = col + 1;
      while (end < size && cells[row][end] && cells[row][end].shape === piece.shape) end += 1;
      if (end - col >= 3) for (let i = col; i < end; i += 1) hit[row][i] = true;
      col = end;
    }
  }
  for (let col = 0; col < size; col += 1) {
    let row = 0;
    while (row < size) {
      const piece = cells[row][col];
      if (!piece) {
        row += 1;
        continue;
      }
      let end = row + 1;
      while (end < size && cells[end][col] && cells[end][col].shape === piece.shape) end += 1;
      if (end - row >= 3) for (let i = row; i < end; i += 1) hit[i][col] = true;
      row = end;
    }
  }
  const cleared = [];
  for (let row = 0; row < size; row += 1) {
    for (let col = 0; col < size; col += 1) if (hit[row][col]) cleared.push([row, col]);
  }
  return cleared;
}

function shiftInPlace(state) {
  const size = state.boardSize;
  const blocked = new Set(state.blocked.map(([row, col]) => row * size + col));
  const occupants = new Map();
  for (let row = 0; row < size; row += 1) {
    for (let col = 0; col < size; col += 1) {
      if (state.cells[row][col]) occupants.set(row * size + col, state.cells[row][col]);
    }
  }
  const proposals = [];
  for (const [index, piece] of occupants) {
    const row = Math.floor(index / size);
    const col = index % size;
    const [dr, dc] = DELTA[piece.direction];
    const tr = row + dr;
    const tc = col + dc;
    const target = tr * size + tc;
    const ok = tr >= 0 && tc >= 0 && tr < size && tc < size && !blocked.has(target) && !occupants.has(target);
    proposals.push({ index, row, col, piece, tr, tc, target, ok });
  }
  const claims = new Map();
  for (const proposal of proposals) {
    if (!proposal.ok) continue;
    claims.set(proposal.target, (claims.get(proposal.target) ?? 0) + 1);
  }
  const next = state.cells.map((row) => row.map((cell) => (cell ? { shape: cell.shape, direction: cell.direction } : null)));
  const movers = proposals.filter((proposal) => proposal.ok && claims.get(proposal.target) === 1);
  for (const proposal of movers) next[proposal.row][proposal.col] = null;
  const moved = [];
  for (const proposal of movers) {
    if (next[proposal.tr][proposal.tc] !== null) throw new Error(`overwrite at ${proposal.tr},${proposal.tc}`);
    next[proposal.tr][proposal.tc] = { shape: proposal.piece.shape, direction: proposal.piece.direction };
    moved.push({
      sourceIndex: proposal.index,
      from: [proposal.row, proposal.col],
      to: [proposal.tr, proposal.tc],
      shape: proposal.piece.shape,
      direction: proposal.piece.direction,
    });
  }
  moved.sort((a, b) => a.sourceIndex - b.sourceIndex);
  state.cells = next;
  return moved;
}

function inside(state, row, col) {
  return row >= 0 && col >= 0 && row < state.boardSize && col < state.boardSize;
}

function isBlocked(state, row, col) {
  return state.blocked.some(([br, bc]) => br === row && bc === col);
}

function collectWaves(cells, blocked, find, ceiling = CHECKER_WAVE_ABORT) {
  // A cascade that finishes on wave `ceiling` is kept. A further match aborts
  // without applying that next wave. `ceiling` is not a game rule.
  let board = cells;
  const waves = [];
  while (waves.length < ceiling) {
    const cleared = find(board);
    if (cleared.length === 0) break;
    for (const [row, col] of cleared) board[row][col] = null;
    const state = { boardSize: board.length, blocked, cells: board };
    const moved = shiftInPlace(state);
    board = state.cells;
    const waveNo = waves.length + 1;
    waves.push({ wave: waveNo, cleared, scoreDelta: cleared.length * 100 * waveNo, moved });
  }
  if (find(board).length > 0) {
    const error = new Error("checker abort: cascade has no contracted wave cap");
    error.applied = waves.length;
    error.board = board;
    throw error;
  }
  return { waves, cells: board };
}

function applyMove(state, move) {
  if (state.status !== "in_progress") {
    return { legal: false, error: { code: "game_ended" }, state: clone(state) };
  }
  const [row, col] = move.tap;
  if (!inside(state, row, col)) throw new Error("tap outside the pinned board");
  if (isBlocked(state, row, col)) return { legal: false, error: { code: "blocked_tap" }, state: clone(state) };
  if (state.cells[row][col] !== null) return { legal: false, error: { code: "occupied_tap" }, state: clone(state) };
  const next = clone(state);
  const piece = next.offers[move.offerIndex];
  const [dr, dc] = DELTA[piece.direction];
  const tr = row + dr;
  const tc = col + dc;
  const land = inside(next, tr, tc) && !isBlocked(next, tr, tc) && next.cells[tr][tc] === null ? [tr, tc] : [row, col];
  next.cells[land[0]][land[1]] = { shape: piece.shape, direction: piece.direction };
  const collected = collectWaves(next.cells, next.blocked, findMatches);
  next.cells = collected.cells;
  const { waves } = collected;
  const scoreDelta = waves.reduce((sum, wave) => sum + wave.scoreDelta, 0);
  // Empty futurePieces is unspecified. Abort instead of inventing a replacement.
  if (next.futurePieces.length === 0) throw new Error("checker abort: empty piece stream is not specified");
  const [taken] = next.futurePieces.splice(0, 1);
  next.offers[move.offerIndex] = taken;
  next.turnsUsed += 1;
  next.score += scoreDelta;
  next.status = next.turnsUsed >= next.moveLimit || emptyLegal(next) === 0 ? "ended" : "in_progress";
  return { legal: true, landing: land, turnsUsed: next.turnsUsed, scoreDelta, waves, finalState: next };
}

function applyMatch(given) {
  const cleared = findMatches(given.cells);
  const cells = clone(given.cells);
  for (const [row, col] of cleared) cells[row][col] = null;
  return { cleared, scoreDelta: cleared.length * 100 * given.wave, cells };
}

function applyShift(given) {
  const state = { boardSize: given.boardSize, blocked: clone(given.blocked), cells: clone(given.cells) };
  const moved = shiftInPlace(state);
  return { moved, cells: state.cells };
}

function checkRuleIds(ids, label) {
  if (!Array.isArray(ids) || !ids.includes("CORE-001")) fail(`${label}: CORE-001 missing`);
  let prev = -1;
  for (const id of ids ?? []) {
    const index = RULES.indexOf(id);
    if (index < 0 || index <= prev) fail(`${label}: ruleIds not canonical (${id})`);
    prev = index;
  }
}

function checkOffers(before, after, index, label) {
  if (before.futurePieces.length === 0) {
    fail(`${label}: consumed an empty stream`);
    return;
  }
  for (let slot = 0; slot < 3; slot += 1) {
    const found = diff(after.offers[slot], slot === index ? before.futurePieces[0] : before.offers[slot]);
    if (found) fail(`${label}: offer slot ${slot}: ${found}`);
  }
  const tail = diff(after.futurePieces, before.futurePieces.slice(1));
  if (tail) fail(`${label}: futurePieces: ${tail}`);
}

function checkFull(doc) {
  const top = ["id", "number", "kind", "rulesVersion", "ruleIds", "summary", "scenarios"];
  exactKeys(doc, top, doc.id);
  for (const scenario of doc.scenarios) {
    const label = `${doc.id}/${scenario.name}`;
    exactKeys(scenario, ["name", "given", "when", "expected", "derivation"], label);
    if ((scenario.derivation ?? "").length < 80) fail(`${label}: derivation too short`);
    exactKeys(scenario.given, ["state"], `${label} given`);
    exactKeys(scenario.when, ["moves"], `${label} when`);
    const expectedKeys = scenario.expected.repeat ? ["steps", "repeat"] : ["steps"];
    exactKeys(scenario.expected, expectedKeys, `${label} expected`);
    if (doc.id === "replay_determinism" && !scenario.expected.repeat) fail(`${label}: missing repeat`);
    if (doc.id !== "replay_determinism" && scenario.expected.repeat) fail(`${label}: unexpected repeat`);
    if (scenario.expected.repeat) {
      exactKeys(scenario.expected.repeat, ["runs", "sameInitialState", "deepEqual"], `${label} repeat`);
      if (scenario.expected.repeat.runs !== 2) fail(`${label}: repeat.runs`);
    }
    exactKeys(scenario.given.state, [
      "rulesVersion", "boardSize", "moveLimit", "blocked", "cells", "offers", "futurePieces", "turnsUsed", "score", "status",
    ], `${label} state`);
    rowMajor(scenario.given.state.blocked, `${label} blocked`);
    if (scenario.when.moves.length !== scenario.expected.steps.length) fail(`${label}: step count`);
    let state = clone(scenario.given.state);
    const produced = [];
    scenario.when.moves.forEach((move, index) => {
      exactKeys(move, ["offerIndex", "tap"], `${label} move ${index}`);
      if (![0, 1, 2].includes(move.offerIndex)) fail(`${label}: offerIndex`);
      const before = clone(state);
      const result = applyMove(state, move);
      produced.push(result);
      const found = diff(result, scenario.expected.steps[index]);
      if (found) fail(`${label} step ${index}: ${found}`);
      if (result.legal) {
        exactKeys(result, ["legal", "landing", "turnsUsed", "scoreDelta", "waves", "finalState"], `${label} legal`);
        if (result.turnsUsed !== before.turnsUsed + 1) fail(`${label}: turn did not increase by 1`);
        if (result.finalState.score !== before.score + result.scoreDelta) fail(`${label}: score`);
        const waveSum = result.waves.reduce((sum, wave) => sum + wave.scoreDelta, 0);
        if (waveSum !== result.scoreDelta) fail(`${label}: wave sum`);
        result.waves.forEach((wave, waveIndex) => {
          exactKeys(wave, ["wave", "cleared", "scoreDelta", "moved"], `${label} wave`);
          if (wave.wave !== waveIndex + 1) fail(`${label}: wave number`);
          if (wave.scoreDelta !== wave.cleared.length * 100 * wave.wave) fail(`${label}: wave score`);
          rowMajor(wave.cleared, `${label} cleared`);
          rowMajor(wave.moved.map((item) => [item.sourceIndex, 0]), `${label} moved`);
          wave.moved.forEach((item) => exactKeys(item, ["sourceIndex", "from", "to", "shape", "direction"], `${label} moved item`));
        });
        checkOffers(before, result.finalState, move.offerIndex, label);
        state = result.finalState;
      } else {
        exactKeys(result, ["legal", "error", "state"], `${label} illegal`);
        exactKeys(result.error, ["code"], `${label} error`);
        const unchanged = diff(result.state, before);
        if (unchanged) fail(`${label}: illegal move mutated state: ${unchanged}`);
        if (result.error.code === "game_ended") {
          const [r, c] = move.tap;
          if (before.status !== "ended" || !inside(before, r, c) || isBlocked(before, r, c) || before.cells[r][c] !== null) {
            fail(`${label}: game_ended is pinned only for an otherwise legal cell`);
          }
        }
        if (result.error.code === "blocked_tap" && !isBlocked(before, move.tap[0], move.tap[1])) {
          fail(`${label}: blocked_tap cell is not blocked`);
        }
        if (result.error.code === "occupied_tap" && (isBlocked(before, move.tap[0], move.tap[1]) || before.cells[move.tap[0]][move.tap[1]] === null)) {
          fail(`${label}: occupied_tap cell is not occupied`);
        }
      }
    });
    if (scenario.expected.repeat) {
      let again = clone(scenario.given.state);
      const second = scenario.when.moves.map((move) => {
        const result = applyMove(again, move);
        again = result.legal ? result.finalState : again;
        return result;
      });
      const repeated = diff(second, produced);
      if (repeated) fail(`${label} repeat: ${repeated}`);
    }
  }
}

function checkPhase(doc) {
  exactKeys(doc, ["id", "number", "kind", "phase", "rulesVersion", "ruleIds", "summary", "scenarios"], doc.id);
  for (const scenario of doc.scenarios) {
    const label = `${doc.id}/${scenario.name}`;
    exactKeys(scenario, ["name", "given", "when", "expected", "derivation"], label);
    if ((scenario.derivation ?? "").length < 80) fail(`${label}: derivation too short`);
    exactKeys(scenario.when, ["phase"], `${label} when`);
    if (scenario.when.phase !== doc.phase) fail(`${label}: phase mismatch`);
    const givenKeys = doc.phase === "match"
      ? ["rulesVersion", "boardSize", "blocked", "cells", "wave"]
      : ["rulesVersion", "boardSize", "blocked", "cells"];
    exactKeys(scenario.given, givenKeys, `${label} given`);
    rowMajor(scenario.given.blocked, `${label} blocked`);
    const produced = doc.phase === "match" ? applyMatch(scenario.given) : applyShift(scenario.given);
    const expectedKeys = doc.phase === "match" ? ["cleared", "scoreDelta", "cells"] : ["moved", "cells"];
    exactKeys(scenario.expected, expectedKeys, `${label} expected`);
    const found = diff(produced, scenario.expected);
    if (found) fail(`${label}: ${found}`);
    if (doc.phase === "match") {
      rowMajor(produced.cleared, `${label} cleared`);
      if (produced.scoreDelta !== produced.cleared.length * 100 * scenario.given.wave) fail(`${label}: match score`);
    } else {
      produced.moved.forEach((item, index) => {
        exactKeys(item, ["sourceIndex", "from", "to", "shape", "direction"], `${label} moved`);
        if (index > 0 && item.sourceIndex <= produced.moved[index - 1].sourceIndex) fail(`${label}: moved order`);
      });
    }
  }
}

function contractLiterals(byId) {
  const hand = 3 * 100 * 1 + 3 * 100 * 2;
  if (hand !== 900 || 5 * 100 * 1 !== 500) fail("hand arithmetic constants drifted");
  const right = byId.place_right_free.scenarios[0].expected.steps[0];
  if (diff(right.landing, [2, 3]) || right.turnsUsed !== 1 || right.scoreDelta !== 0 || right.waves.length !== 0) {
    fail("place_right_free literal");
  }
  const blocked = byId.place_blocked_neighbor.scenarios[0].expected.steps[0];
  if (diff(blocked.landing, [2, 2]) || blocked.turnsUsed !== 1 || blocked.scoreDelta !== 0) fail("place_blocked_neighbor literal");
  const edge = byId.place_edge.scenarios[0].expected.steps[0];
  if (diff(edge.landing, [0, 2])) fail("place_edge literal");
  const horizontal = byId.horizontal_match.scenarios[0].expected.steps[0];
  if (diff(horizontal.landing, [2, 2]) || horizontal.scoreDelta !== 300 || horizontal.waves.length !== 1) fail("horizontal_match literal");
  if (diff(horizontal.waves[0].cleared, [[2, 0], [2, 1], [2, 2]])) fail("horizontal_match clears");
  const cross = byId.cross_union.scenarios[0].expected;
  if (cross.scoreDelta !== 500 || cross.cleared.length !== 5) fail("cross_union literal");
  const contested = byId.contested_shift.scenarios[0];
  if (contested.expected.moved.length !== 0 || diff(contested.expected.cells, contested.given.cells)) fail("contested_shift literal");
  const busy = byId.preoccupied_shift.scenarios[0].expected.cells;
  if (!busy[2][1] || busy[2][2] !== null) fail("preoccupied_shift literal");
  const cascade = byId.two_wave_cascade.scenarios[0].expected.steps[0];
  if (cascade.waves.length !== 2 || cascade.scoreDelta !== 900 || cascade.waves[0].scoreDelta !== 300 || cascade.waves[1].scoreDelta !== 600) {
    fail("two_wave_cascade literal");
  }
  const replay = byId.replay_determinism.scenarios[0].expected;
  if (replay.steps[1].scoreDelta !== 300 || replay.steps[1].finalState.score !== 600 || replay.steps[1].waves[0].wave !== 1) {
    fail("replay multiplier literal");
  }
  const ended = byId.end_conditions.scenarios[0].expected.steps;
  if (ended[0].finalState.status !== "ended" || ended[1].error.code !== "game_ended") fail("end_conditions literal");
  const filled = byId.end_conditions.scenarios[1].expected.steps[0];
  if (filled.finalState.status !== "ended" || filled.finalState.turnsUsed >= filled.finalState.moveLimit) {
    fail("no-space end was not distinct from the move limit");
  }
}

function walk(dir, base, acc) {
  for (const entry of readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.name === "CHECKSUMS.txt" || entry.name.startsWith("_")) continue;
    const abs = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(abs, base, acc);
    else acc.push(path.relative(base, abs).split(path.sep).join("/"));
  }
}

function checkChecksums() {
  const files = [];
  walk(ROOT, ROOT, files);
  const file = path.join(ROOT, "CHECKSUMS.txt");
  let text;
  try {
    text = readFileSync(file, "utf8");
  } catch {
    fail("CHECKSUMS.txt missing");
    return;
  }
  const listed = new Map();
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    const match = /^([0-9a-f]{64})  (\S+)$/.exec(line);
    if (!match) {
      fail(`checksum line not sha256: ${line}`);
      continue;
    }
    listed.set(match[2], match[1]);
  }
  for (const rel of files) {
    const digest = createHash("sha256").update(readFileSync(path.join(ROOT, rel))).digest("hex");
    if (listed.get(rel) !== digest) fail(`checksum mismatch ${rel}`);
  }
  for (const rel of listed.keys()) if (!files.includes(rel)) fail(`checksum lists missing file ${rel}`);
}

function checkCascadeBoundary(doc) {
  const blank = () => Array.from({ length: 5 }, () => Array.from({ length: 5 }, () => null));
  const scripted = (limit) => {
    let calls = 0;
    return () => {
      calls += 1;
      return calls <= limit ? [[0, 0], [0, 1], [0, 2]] : [];
    };
  };
  const exact = collectWaves(blank(), [], scripted(CHECKER_WAVE_ABORT), CHECKER_WAVE_ABORT);
  if (exact.waves.length !== CHECKER_WAVE_ABORT || exact.waves.at(-1).wave !== CHECKER_WAVE_ABORT) {
    fail("exact 20-wave cascade was rejected or truncated");
  }
  try {
    collectWaves(blank(), [], scripted(CHECKER_WAVE_ABORT + 1), CHECKER_WAVE_ABORT);
    fail("cascade still matching at the review boundary was accepted");
  } catch (error) {
    if (error.applied !== CHECKER_WAVE_ABORT) fail(`continuing cascade applied ${error.applied} waves`);
  }
  const short = collectWaves(blank(), [], scripted(2), CHECKER_WAVE_ABORT);
  if (short.waves.length !== 2) fail("normal short cascade was not accepted");

  const placed = (ceiling) => {
    const state = clone(doc.scenarios[0].given.state);
    const move = doc.scenarios[0].when.moves[0];
    const piece = state.offers[move.offerIndex];
    const [row, col] = move.tap;
    const [dr, dc] = DELTA[piece.direction];
    const tr = row + dr;
    const tc = col + dc;
    const land = inside(state, tr, tc) && !isBlocked(state, tr, tc) && state.cells[tr][tc] === null ? [tr, tc] : [row, col];
    state.cells[land[0]][land[1]] = { shape: piece.shape, direction: piece.direction };
    return collectWaves(state.cells, state.blocked, findMatches, ceiling);
  };
  const finished = placed(2);
  const finishedScore = finished.waves.reduce((sum, wave) => sum + wave.scoreDelta, 0);
  if (finished.waves.length !== 2 || finishedScore !== 900) fail("real cascade ending exactly on the ceiling was rejected");
  if (finished.cells.some((row) => row.some((cell) => cell))) fail("real cascade ending exactly on the ceiling left pieces");
  try {
    placed(1);
    fail("real cascade still matching at the ceiling was accepted");
  } catch (error) {
    if (error.applied !== 1) fail(`real continuing cascade applied ${error.applied} waves`);
    const occupied = [];
    error.board.forEach((row, r) => row.forEach((cell, c) => {
      if (cell) occupied.push([r, c, cell.shape]);
    }));
    if (diff(occupied, [[4, 0, "diamond"], [4, 1, "diamond"], [4, 2, "diamond"]])) {
      fail(`wave beyond the ceiling was applied or the shift differed: ${JSON.stringify(occupied)}`);
    }
  }
  const normal = placed(CHECKER_WAVE_ABORT);
  const normalScore = normal.waves.reduce((sum, wave) => sum + wave.scoreDelta, 0);
  if (normal.waves.length !== 2 || normalScore !== 900 || normal.cells.some((row) => row.some((cell) => cell))) {
    fail("normal two-wave cascade failed under the default review ceiling");
  }
}

function sameMembers(actual, expected, label) {
  const left = [...actual].sort();
  const right = [...expected].sort();
  if (diff(left, right)) fail(`${label}: ${JSON.stringify(left)} !== ${JSON.stringify(right)}`);
}

function checkDuplicateCoordinate() {
  const cells = Array.from({ length: 5 }, () => Array.from({ length: 5 }, () => null));
  const issues = [];
  scanBlocked(5, [[1, 2], [1, 2]], cells, issues);
  if (issues.length !== 1 || issues[0] !== "duplicate_blocked") {
    fail(`[[1,2],[1,2]] issues [${issues.join(", ")}] wanted duplicate_blocked`);
  }
  const probe = load(path.join(ROOT, "invalid", "duplicate-blocked.json"));
  if (diff(probe.fixture.scenarios[0].given.state.blocked, [[1, 2], [1, 2]])) {
    fail("duplicate-blocked.json must repeat [1,2]");
  }
}

function checkSchemaDocument() {
  const schema = load(path.join(ROOT, "fixture.schema.json"));
  const defs = schema.$defs;
  if (defs.rulesVersion.const !== RV) fail("schema rulesVersion const drifted");
  sameMembers(defs.shape.enum, SHAPES, "schema shapes");
  sameMembers(defs.direction.enum, DIRS, "schema directions");
  sameMembers(defs.status.enum, ["in_progress", "ended"], "schema status");
  sameMembers(defs.errorCode.enum, ["blocked_tap", "occupied_tap", "game_ended"], "schema errors");
  if (defs.piece.additionalProperties !== false) fail("schema piece allows unknown fields");
  const blockedSchemas = [
    defs.state.properties.blocked,
    defs.matchGiven.properties.blocked,
    defs.shiftGiven.properties.blocked,
  ];
  if (blockedSchemas.some((blocked) => blocked.uniqueItems !== true)) {
    fail("schema blocked coordinates must set uniqueItems, which deep-compares [row, column]");
  }
  if (defs.matchExpected?.additionalProperties !== false) fail("schema match expected is open");
  if (defs.shiftExpected?.additionalProperties !== false) fail("schema shift expected is open");
  const refs = (defs.phaseFixture.properties.scenarios.items.properties.expected.oneOf ?? []).map((item) => item.$ref);
  if (diff(refs, ["#/$defs/matchExpected", "#/$defs/shiftExpected"])) {
    fail("phase expected is not closed over match and shift results");
  }
}

function main() {
  const names = readdirSync(path.join(ROOT, "fixtures")).filter((name) => name.endsWith(".json")).sort();
  if (diff(names, CATALOG.map(([name]) => name))) fail("fixture filename catalog mismatch");
  const byId = {};
  for (const [file, id, kind, number, phase] of CATALOG) {
    const doc = load(path.join(ROOT, "fixtures", file));
    byId[id] = doc;
    if (doc.id !== id || doc.kind !== kind || doc.number !== number || doc.rulesVersion !== RV) {
      fail(`${file}: catalog identity mismatch`);
    }
    if ((doc.summary ?? "").length < 20) fail(`${id}: summary too short`);
    checkRuleIds(doc.ruleIds, id);
    const issues = issuesFor(doc);
    if (issues.length) fail(`${id}: structural issues ${issues.join(", ")}`);
    try {
      if (kind === "fullMove") checkFull(doc);
      else {
        if (doc.phase !== phase) fail(`${id}: phase catalog mismatch`);
        checkPhase(doc);
      }
    } catch (error) {
      fail(`${id}: ${error.message}`);
    }
  }
  contractLiterals(byId);

  const invalidNames = readdirSync(path.join(ROOT, "invalid")).filter((name) => name.endsWith(".json")).sort();
  if (diff(invalidNames, INVALID.map(([name]) => name).sort())) fail("invalid filename catalog mismatch");
  for (const [file, code] of INVALID) {
    const probe = load(path.join(ROOT, "invalid", file));
    exactKeys(probe, ["expectCode", "fixture"], file);
    if (probe.expectCode !== code) fail(`${file}: expectCode`);
    const issues = issuesFor(probe.fixture);
    if (issues.length !== 1 || issues[0] !== code) fail(`${file}: issues [${issues.join(", ")}] wanted ${code}`);
  }

  checkCascadeBoundary(byId.two_wave_cascade);
  checkDuplicateCoordinate();
  checkSchemaDocument();
  checkChecksums();
  if (errors.length) {
    console.log("validate: FAIL");
    for (const message of errors) console.log(`- ${message}`);
    process.exit(1);
  }
  console.log("validate: PASS 12 golden fixtures");
  console.log("validate: PASS cascade boundary");
  console.log("validate: PASS schema agreement");
  console.log("validate: PASS duplicate blocked [[1,2],[1,2]]");
  console.log("validate: PASS 9 structural rejection probes");
  console.log("validate: PASS sha256 CHECKSUMS.txt");
  console.log("validate: second walkthrough agrees with the golden JSON");
  console.log("NOT_RUN backend application unit/integration tests (no app harness in this repository)");
  console.log("NOT_RUN Dart/Flutter client engine (not this repository; no engine is implemented)");
  console.log("NOT_RUN cross-runtime parity execution (the shared vector is these files; engines do not exist yet)");
}

main();
