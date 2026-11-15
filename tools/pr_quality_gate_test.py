#!/usr/bin/env python3
"""Positive and negative tests for the pull-request quality gate."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import pr_quality_gate as gate

FAILURES: list[str] = []


def fail(message: str) -> None:
    FAILURES.append(message)


def expect_error(errors: list[str], needle: str, label: str) -> None:
    if not any(needle in error for error in errors):
        fail(f"{label}: missing {needle!r} in {errors}")


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def valid_body() -> str:
    parts = ["## Jira", "PZD-16 https://puzzle-duel-app.atlassian.net/browse/PZD-16"]
    for heading in gate.REQUIRED_HEADINGS[1:]:
        if heading == "Tests":
            parts.extend(["## Tests", "```bash", "python3 tools/pr_quality_gate_test.py", "```"])
        else:
            parts.extend([f"## {heading}", "recorded"])
    return "\n".join(parts) + "\n"


def test_repository_passes() -> None:
    errors = gate.check_repository(gate.repo_root())
    if errors:
        fail("current repository failed: " + "; ".join(errors))


def test_broken_link() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        write(root / "docs" / "adr" / "ADR-001.md", "Status: Proposed\n\n[Missing](missing.md)\n")
        errors = gate.check_markdown_links(root)
        expect_error(errors, "broken link", "broken link")
        write(root / "docs" / "note.md", "[Here](adr/ADR-001.md)\n")
        errors = gate.check_markdown_links(root)
        if any("note.md" in error for error in errors):
            fail(f"valid relative link was rejected: {errors}")


def test_adr_status() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        write(root / "docs" / "adr" / "ADR-009.md", "Status: Banana\n")
        errors = gate.check_adr_statuses(root)
        expect_error(errors, "Banana", "malformed status")
    root = gate.repo_root()
    for path in (root / "docs" / "adr").glob("ADR-*.md"):
        token = gate.status_token(next(line for line in path.read_text(encoding="utf-8").splitlines() if line.startswith("Status:")))
        if token not in gate.ALLOWED_ADR_STATUS:
            fail(f"historical ADR status rejected: {path.name} {token}")


def test_secrets() -> None:
    live = "ghp_" + ("a" * 36)
    private = "-----BEGIN " + "RSA PRIVATE KEY-----"
    allowed = "documented example token ghp_example_not_a_secret"
    if not gate.secret_hits(live):
        fail("secret-like token was accepted")
    if not gate.secret_hits(private):
        fail("private key header was accepted")
    if gate.secret_hits(allowed):
        fail("labeled example token was rejected")
    if gate.secret_hits("The word password appears in a sentence."):
        fail("the word password was treated as a secret")


def test_pull_request_metadata() -> None:
    errors = gate.check_pull_request("[PZD-16] Example", "all tests passed\n")
    expect_error(errors, "Jira", "missing metadata")
    expect_error(errors, "Tests", "missing tests section")
    vague = valid_body().replace("```bash\npython3 tools/pr_quality_gate_test.py\n```", "all tests passed")
    errors = gate.check_pull_request("[PZD-16] Example", vague)
    expect_error(errors, "fenced command", "vague pass claim")
    errors = gate.check_pull_request("docs only", valid_body())
    expect_error(errors, "PZD-number", "title without issue key")
    errors = gate.check_pull_request("docs only", "Policy exception: hotfix owner requested\n" + valid_body())
    if any("PZD-number" in error for error in errors):
        fail(f"documented hotfix exception was rejected: {errors}")
    errors = gate.check_pull_request("[PZD-16] Example", valid_body())
    if errors:
        fail(f"complete PR metadata was rejected: {errors}")


def test_immutable_fixtures() -> None:
    changed = gate.immutable_fixture_errors([
        "docs/contracts/gameplay/v1/fixtures/01-place-right-free.json",
        "docs/contracts/gameplay/v1/fixtures/13-cascade-reopen-end.json",
        "docs/contracts/gameplay/v2/fixtures/01-terminal-null-slot.json",
        "docs/process/PZD-16-QUALITY-GATES.md",
    ])
    if changed != ["immutable fixture changed: docs/contracts/gameplay/v1/fixtures/01-place-right-free.json"]:
        fail(f"immutable selection drifted: {changed}")


def main() -> int:
    test_repository_passes()
    test_broken_link()
    test_adr_status()
    test_secrets()
    test_pull_request_metadata()
    test_immutable_fixtures()
    if FAILURES:
        print("pr_quality_gate_test: FAIL")
        for message in FAILURES:
            print(f"- {message}")
        return 1
    print("pr_quality_gate_test: PASS current repository")
    print("pr_quality_gate_test: PASS broken link is rejected")
    print("pr_quality_gate_test: PASS malformed ADR status is rejected")
    print("pr_quality_gate_test: PASS secret-like text is rejected and labeled examples are kept")
    print("pr_quality_gate_test: PASS incomplete PR metadata is rejected")
    print("pr_quality_gate_test: PASS historical fixtures 13 and v2 are not treated as 01-12")
    return 0


if __name__ == "__main__":
    sys.exit(main())
