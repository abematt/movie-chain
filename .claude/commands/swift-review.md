---
description: Review Swift changes against the write-swift guide and this repo's Swift conventions
argument-hint: "[base ref, default main]"
---

Review the Swift changes on this branch before they merge.

1. Load the `write-swift` skill, then read the "Swift conventions" section of CLAUDE.md.
2. The base ref is `$ARGUMENTS`; if that's empty, use `main`. Diff the branch against
   it (`git diff <base>...HEAD -- '*.swift'`), plus any uncommitted Swift changes.
   Read each changed file in full where the diff alone doesn't show enough context.
3. Run `scripts/swift-check.py` on the changed files and include anything it reports.
4. Review for what a script can't see: value vs reference types, enums for exclusive
   state, `some` vs `any`, isolation and actor reentrancy across `await`, unstructured
   tasks that should be structured, cancellation, algorithmic cost, and test coverage
   for new logic (Swift Testing, parameterized where it's a table). For a user-facing
   change, also check it reports through `Telemetry` per docs/ANALYTICS.md (a property
   before an event, nothing from the engine) and that the plan was updated with it.
5. Report findings most-severe first, each with a `file:line` link, what's wrong, and
   the fix. Separate "fix before merge" from "worth doing" and say plainly if the
   diff is clean. Don't edit code unless asked.
