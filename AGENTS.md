# AGENTS.md — installing claude-code-agents into a project

You are an agent asked to install this kit into the user's project. Read `README.md` for what each file does; this file is the procedure. Work from the target project's root; commands below are relative to it, but give absolute paths in anything you report. Prerequisites: `bash`, `python3` (the hooks and tests use it), `git`, and `node` 18+ only for the pulse script. If you have a local copy of this repo instead of network access, use it in place of the README's `git clone`.

## What the kit is
Three Claude Code subagents (`role-dev` non-UI work, `role-ui` components and styles, `role-concept` "show me 3 ways" mockups), each with its project rules preloaded from a skill, plus three bash hooks: a Stop hook that blocks a role from finishing until its report has a `GATE: <command> -> PASS` line or `GATE-SKIPPED: <reason>`, a routing guard that stops the lead sending edits to a generic agent, and a role picker. `scripts/roles-pulse.mjs` reads Claude Code transcripts and reports use, evidence and cost. Nothing in the kit makes a network call or installs a package.

## Procedure
1. **Detect, do not assume.** Find the project's real check command (`package.json` scripts, `Makefile`, CI config, `AGENTS.md`/`CLAUDE.md`). Check whether `.claude/agents/`, `.claude/skills/` and `.claude/settings.json` already exist and whether `.claude/` is gitignored. If there is no check command, say so and ask the user which command proves a change works. Never invent one.
2. **Copy the files** exactly as the README's Install block lists them. Do not rewrite the hook scripts.
3. **`.claude/settings.json`**: if the file does not exist, copy the kit's. If it exists, **merge** the kit's `PreToolUse` (matcher `Agent|Task`) and `UserPromptSubmit` entries into it. Never overwrite the user's settings. Method: parse the existing JSON, append the kit's entries to the existing `PreToolUse` and `UserPromptSubmit` arrays (create the arrays if missing, keep the user's entries first), leave every other key untouched, write it back, and confirm it still parses. Formatting changes are fine; lost content is not.
4. **Fill in `.claude/skills/build-rules/SKILL.md`** with the real check command and the project's actual rules, taken from the project's own docs, under about 900 words, citing only files that exist in this project. If the project has a UI and a design doc, fill in `design-rules` from it. If it has no UI, delete `role-ui.md`, `role-concept.md` and `.claude/skills/design-rules/` rather than leaving example rules for those roles to load, and tell the user you did. If the project has no written rules at all, keep only the check command in `build-rules`, delete the example rules and the "EXAMPLE" comment, and say the file is a thin start. In each role's report template, `<check command>` stays a placeholder for the role to resolve from `build-rules`.
5. **Prove the hooks**: run `for t in scripts/hooks/*.test.sh; do bash "$t" | tail -1; done`. Each must print `ALL PASS`. Run `bash -n` on every script you edited.
6. If `.claude/` is gitignored, tell the user that roles in a fresh worktree will not exist unless the files are committed with `git add -f`. Do not change `.gitignore` yourself.
7. **Report to the user what you cannot do**: (a) restart Claude Code if `.claude/agents/` did not exist when the session started; (b) accept the workspace trust prompt, because hooks in agent files run only in a trusted folder; (c) hooks do not fire under `claude -p`.

## Rules
- Do not edit the hook scripts unless a test requires it, and if you do, re-run `bash -n` first. A bash syntax error exits 2, which Claude Code reads as "block", so a broken hook blocks everything.
- Do not rename the role suffixes (`-dev`, `-ui`, `-concept`): the handback hook selects its contract by suffix.
- Do not commit, push or change git config. Leave the install as uncommitted changes for the user to review.
- The handback check reads what a role reports, not what it ran. State that limit if the user asks what the hook guarantees.

## Where the limits are documented
`README.md` § Known limits. The long write-up with real cost numbers is at https://launchwithben.com/notes/claude-code-agents (free signup, not needed to install).

## Maintaining this repo (for agents working on it)
- Every change that alters behaviour gets a `CHANGELOG.md` entry in the same commit, and a release tag when it ships (`gh release create vX.Y.Z --notes-from-tag` or with notes copied from the changelog).
- Keep the status line at the top of `README.md` and `MAINTENANCE.md` true. If the project is being sunset, follow the four steps in `MAINTENANCE.md` in order and do not archive the repo without the owner's say-so.
- Never add telemetry, network calls or dependencies. The README and the launchwithben.com write-up promise there are none.
