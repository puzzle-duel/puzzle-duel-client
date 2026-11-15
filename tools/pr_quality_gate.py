#!/usr/bin/env python3
"""Dependency-free pull-request quality gate.

The historical gameplay fixtures 01-12 are immutable.
Proposed and Accepted ADR statuses are both legal.
A matched token is ignored only when its own value is an obvious placeholder.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ALLOWED_ADR_STATUS = {"Proposed", "Accepted", "Rejected", "Superseded", "Deprecated"}
REQUIRED_HEADINGS = (
    "Jira",
    "Scope",
    "Files",
    "Blueprint and ADR impact",
    "Acceptance criteria",
    "Tests",
    "NOT_RUN",
    "Security and privacy",
    "Dependencies and blockers",
    "Cross-repository parity",
    "Merge and deploy",
)
IMMUTABLE_FIXTURE = re.compile(
    r"^docs/contracts/gameplay/v1/fixtures/(?:0[1-9]|1[0-2])-[^/]+\.json$"
)
SECRET_PATTERNS = (
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\bghp_[A-Za-z0-9]{20,}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"\bsk_live_[A-Za-z0-9]{8,}\b"),
)
PLACEHOLDER_MARKERS = ("example", "dummy", "redacted", "placeholder", "not_a_secret", "xxxx")
LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)\)")
FENCE_RE = re.compile(r"```.*?```", re.DOTALL)
TEXT_SUFFIXES = {".md", ".yml", ".yaml", ".json", ".py", ".mjs", ".txt", ".js", ".ts", ".sh", ".dart"}
SKIP_DIRS = {".git", "__pycache__", "node_modules", ".dart_tool"}


def repo_root(start: Path | None = None) -> Path:
    return (start or Path(__file__).resolve().parent.parent).resolve()


def status_token(line: str) -> str:
    text = line.split(":", 1)[1].replace("*", "").strip()
    token = re.split(r"[\s.—–-]", text, maxsplit=1)[0]
    return token.strip(".,;:")


def check_adr_statuses(root: Path) -> list[str]:
    errors = []
    for path in sorted((root / "docs" / "adr").glob("ADR-*.md")):
        lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line.startswith("Status:")]
        if not lines:
            errors.append(f"ADR status missing: {path.relative_to(root)}")
            continue
        token = status_token(lines[0])
        if token not in ALLOWED_ADR_STATUS:
            errors.append(f"ADR status {token!r} is not allowed: {path.relative_to(root)}")
    return errors


def markdown_links(text: str) -> list[str]:
    stripped = FENCE_RE.sub("", text)
    return [match.group(1) for match in LINK_RE.finditer(stripped)]


def check_markdown_links(root: Path) -> list[str]:
    errors = []
    for path in sorted(root.rglob("*.md")):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        for target in markdown_links(path.read_text(encoding="utf-8")):
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            relative = target.split("#", 1)[0].split("?", 1)[0]
            if not relative:
                continue
            destination = (path.parent / relative).resolve()
            if not destination.exists():
                errors.append(f"broken link {target} in {path.relative_to(root)}")
    return errors


def token_is_placeholder(token: str) -> bool:
    lowered = token.lower()
    return any(marker in lowered for marker in PLACEHOLDER_MARKERS)


def secret_hits(text: str) -> list[str]:
    """Return pattern sources for live matches. Never return matched token text."""
    hits = []
    for line in text.splitlines():
        for pattern in SECRET_PATTERNS:
            matches = list(pattern.finditer(line))
            if matches and any(not token_is_placeholder(match.group(0)) for match in matches):
                hits.append(pattern.pattern)
    return hits


def check_secrets(root: Path) -> list[str]:
    errors = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        hits = secret_hits(path.read_text(encoding="utf-8", errors="replace"))
        if hits:
            errors.append(f"secret-like content in {path.relative_to(root)}")
    return errors


def immutable_fixture_errors(paths: list[str]) -> list[str]:
    return [f"immutable fixture changed: {path}" for path in paths if IMMUTABLE_FIXTURE.match(path)]


def changed_paths(root: Path) -> list[str]:
    base = os.environ.get("PR_BASE_SHA") or "origin/main"
    result = subprocess.run(
        ["git", "diff", "--name-only", f"{base}...HEAD"],
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"git diff failed for {base}")
    return [line for line in result.stdout.splitlines() if line]


def check_immutable_fixtures(root: Path) -> list[str]:
    try:
        paths = changed_paths(root)
    except RuntimeError as error:
        return [f"immutable fixture check failed: {error}"]
    return immutable_fixture_errors(paths)


def section_body(body: str, heading: str) -> str:
    pattern = re.compile(rf"^## {re.escape(heading)}\s*$", re.MULTILINE)
    match = pattern.search(body)
    if not match:
        return ""
    rest = body[match.end():]
    next_heading = re.search(r"^## ", rest, re.MULTILINE)
    return rest[: next_heading.start()] if next_heading else rest


def check_pull_request(title: str, body: str) -> list[str]:
    errors = []
    exception = re.search(r"^Policy exception:\s*(automation|dependency update|hotfix)\b", body or "", re.MULTILINE)
    if not re.search(r"\bPZD-\d+\b", title or "") and not exception:
        errors.append("PR title needs a PZD-number, or the body needs a Policy exception line")
    for heading in REQUIRED_HEADINGS:
        if not section_body(body or "", heading).strip():
            errors.append(f"PR section missing or empty: {heading}")
    jira = section_body(body or "", "Jira")
    if jira and not re.search(r"https://puzzle-duel-app\.atlassian\.net/browse/PZD-\d+", jira):
        errors.append("Jira section needs a browse link")
    tests = section_body(body or "", "Tests")
    if tests and "```" not in tests:
        errors.append("Tests section needs a fenced command block, not a bare pass claim")
    if re.search(r"all tests passed", tests, re.IGNORECASE) and "```" not in tests:
        errors.append("Tests section says all tests passed without a command")
    return errors


def check_event_file(path: Path) -> list[str]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    pull = payload.get("pull_request")
    if not isinstance(pull, dict):
        return ["pull request metadata missing from the event payload"]
    return check_pull_request(str(pull.get("title") or ""), str(pull.get("body") or ""))


def check_repository(root: Path, event_path: Path | None = None) -> list[str]:
    errors = []
    errors.extend(check_markdown_links(root))
    errors.extend(check_adr_statuses(root))
    errors.extend(check_secrets(root))
    errors.extend(check_immutable_fixtures(root))
    if event_path is not None:
        errors.extend(check_event_file(event_path))
    return errors


def main() -> int:
    root = repo_root()
    event = os.environ.get("GITHUB_EVENT_PATH")
    event_path = Path(event) if event else None
    errors = check_repository(root, event_path)
    if errors:
        print("quality-gate: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    print("quality-gate: PASS markdown links")
    print("quality-gate: PASS ADR status vocabulary")
    print("quality-gate: PASS secret scan")
    print("quality-gate: PASS immutable fixtures 01-12")
    if event_path:
        print("quality-gate: PASS pull request metadata")
    else:
        print("quality-gate: NOT_RUN pull request metadata (no GITHUB_EVENT_PATH)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
