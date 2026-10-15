---
name: {{PREFIX}}-build-rules
description: >-
  This project's non-negotiable build rules: the check command, git hygiene, and the traps that already cost us a day. Preloaded into the dev, ui and concept roles; use for any code, script or data change in this repo.
---

# Build rules (distilled; the source is cited on every rule)

<!--
  HOW TO FILL THIS IN (this starter is written once and never overwritten by install.sh)
  - Keep it under ~900 words. It is pasted into every role at start, so every line costs tokens on every run.
  - One rule per line, written as an order, with the file it came from in brackets.
  - Only rules an agent would otherwise break. "Write clean code" is not a rule.
  - Better: GENERATE it from your docs so it cannot drift (roles/skills.txt + build_skills.sh), then delete this file.
  Everything below is an EXAMPLE. Replace it with your project's real rules.
-->

## The check
1. THE check is `{{CHECK}}`. It must pass before any handback. (the project's gate)
2. A new check must be wired into that command and shown to FAIL on a known-bad input. A check that reports zero problems has not proven anything yet.

## Git
3. Commit with a pathspec: `git commit -m "..." -- path/a path/b`. A bare `git add . && git commit` in a shared checkout commits other people's work.
4. Never merge, push to main, or deploy. The lead does that after reviewing your diff.

## Data and numbers
5. Any number you report comes from a command you ran this session. Re-check numbers quoted in your brief before building on them.

## Project traps (replace with yours)
6. Example: every user-visible string goes through the shared copy helper; never hard-code it in a component. (docs/copy.md)
7. Example: database migrations are never run by an agent. Write the migration, stop, and say so. (docs/db.md)
