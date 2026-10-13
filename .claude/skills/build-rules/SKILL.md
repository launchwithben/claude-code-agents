---
name: build-rules
description: >-
  This project's non-negotiable build rules: the check command, git hygiene, and the traps that already cost us a day. Preloaded into role-dev, role-ui and role-concept; use for any code, script or data change in this repo.
---

# Build rules (distilled; the source is cited on every rule)

<!--
  HOW TO FILL THIS IN
  - Keep it under ~900 words. It is pasted into every role at start, so every line costs tokens on every run.
  - One rule per line, written as an order, with the file it came from in brackets.
  - Only rules an agent would otherwise break. "Write clean code" is not a rule.
  - The cited file wins on conflict. Change a rule at its source -> change it here in the same commit.
  Everything below is an EXAMPLE. Replace it with your project's real rules.
-->

## The check
1. THE check is `npm run check`. It must pass before any handback. `npm run build` alone is NOT the check. (package.json)
2. A new check must be wired into `npm run check` and shown to FAIL on a known-bad input. A check that reports zero problems has not proven anything yet. (CONTRIBUTING.md)

## Git
3. Commit with a pathspec: `git commit -m "..." -- path/a path/b`. A bare `git add . && git commit` in a shared checkout commits other people's work.
4. Never merge, push to main, or deploy. The lead does that after reviewing your diff.

## Data and numbers
5. Any number you report comes from a command you ran this session. Re-check numbers quoted in your brief before building on them. (AGENTS.md)

## Project traps (replace with yours)
6. Example: every user-visible string goes through `t(lang, 'key')`; never hard-code English. (docs/i18n.md)
7. Example: database migrations are never run by an agent. Write the migration, stop, and say so. (docs/db.md)
