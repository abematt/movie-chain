#!/usr/bin/env python3
"""Mechanical checks for the Swift conventions in CLAUDE.md ("Swift conventions").

Catches the patterns a grep can see — the judgment calls (value vs reference,
`some` vs `any`, actor reentrancy) are left to review with /swift-review.

Usage:
  scripts/swift-check.py [FILE...]   check the given files (default: all app + test Swift)
  scripts/swift-check.py --staged    check staged Swift files (the git pre-commit hook)
  scripts/swift-check.py --hook      Claude Code PostToolUse hook: reads the tool call
                                     from stdin, checks the edited file, exits 2 on a hit

A line containing `swift-check:ignore` is exempt — say why on the same line.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIRS = ("movie-quiz", "movie-quizTests")
IGNORE = "swift-check:ignore"

# (id, pattern matched against the code part of a line, why/what instead)
LINE_RULES = [
    ("xctest", re.compile(r"\bXCTestCase\b"),
     "new tests use Swift Testing (@Test, #expect); XCTest is only for UI automation and XCTMetric"),
    ("task-detached", re.compile(r"\bTask\.detached\b"),
     "Task.detached inherits nothing; use a @concurrent func or a child task"),
    ("dispatch-main", re.compile(r"\bDispatchQueue\.main\b"),
     "use the main actor (the module default) instead of GCD"),
    ("locale-current", re.compile(r"locale:\s*\.current\b"),
     "string matching must not depend on the device locale; pass locale: nil"),
    ("print", re.compile(r"(?<![\w.])print\("),
     "use Logger from os, not print"),
    ("observable-object", re.compile(r"\bObservableObject\b|@Published\b|@StateObject\b|@ObservedObject\b"),
     "use @Observable with @State / @Bindable"),
]


def code_part(line):
    """The line with any // comment removed (not inside a URL)."""
    stripped = line.lstrip()
    if stripped.startswith("//"):
        return ""
    return re.sub(r"(?<!:)//.*$", "", line)


def check_file(path):
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return []
    hits = []

    def report(index, rule, message):
        hits.append(f"{path.relative_to(ROOT)}:{index + 1}: [{rule}] {message}")

    for i, line in enumerate(lines):
        if IGNORE in line:
            continue
        code = code_part(line)
        if not code.strip():
            continue

        for rule, pattern, message in LINE_RULES:
            if pattern.search(code):
                report(i, rule, message)

        # A `nonisolated ... async` func runs on its caller's actor under
        # Approachable Concurrency — the bug that kept TMDB decoding on main.
        if re.search(r"\bnonisolated\b", code) and re.search(r"\bfunc\b", code):
            signature = " ".join(code_part(l) for l in lines[i:i + 6])
            signature = signature.split("{", 1)[0]
            attributes = " ".join(lines[max(0, i - 3):i + 1])
            if re.search(r"\basync\b", signature) and "@concurrent" not in attributes:
                report(i, "nonisolated-async",
                       "a nonisolated async func runs on the caller's actor (main, here); "
                       "add @concurrent to leave it, or swift-check:ignore if that's intended")

        # A Task started in onAppear outlives the view; `.task` is cancelled with it.
        if re.search(r"\.onAppear\s*\{", code):
            depth = 0
            for j in range(i, min(len(lines), i + 40)):
                body = code_part(lines[j])
                if re.search(r"\bTask\s*[{(]", body) and IGNORE not in lines[j]:
                    report(i, "onappear-task",
                           "use .task / .task(id:), which is cancelled when the view goes away")
                    break
                depth += body.count("{") - body.count("}")
                if depth <= 0:          # the onAppear closure has closed
                    break

    return hits


def all_sources():
    for directory in SOURCE_DIRS:
        yield from sorted((ROOT / directory).rglob("*.swift"))


def staged_sources():
    out = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "--", "*.swift"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout
    return [ROOT / name for name in out.splitlines() if name]


def in_scope(path):
    try:
        relative = path.resolve().relative_to(ROOT)
    except ValueError:
        return False
    return path.suffix == ".swift" and relative.parts[0] in SOURCE_DIRS


def main(argv):
    if argv[:1] == ["--hook"]:
        try:
            event = json.load(sys.stdin)
        except json.JSONDecodeError:
            return 0
        file_path = (event.get("tool_input") or {}).get("file_path")
        if not file_path or not in_scope(Path(file_path)):
            return 0
        hits = check_file(Path(file_path).resolve())
        if hits:
            print("swift-check found convention violations (see CLAUDE.md → Swift conventions):",
                  file=sys.stderr)
            print("\n".join(hits), file=sys.stderr)
            return 2
        return 0

    if argv[:1] == ["--staged"]:
        files = staged_sources()
    elif argv:
        files = [Path(a).resolve() for a in argv]
    else:
        files = list(all_sources())

    hits = [hit for f in files if in_scope(f) for hit in check_file(f)]
    if hits:
        print("\n".join(hits), file=sys.stderr)
        print(f"\nswift-check: {len(hits)} violation(s). Fix them, or mark a deliberate "
              f"exception with `// {IGNORE} — <why>`.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
