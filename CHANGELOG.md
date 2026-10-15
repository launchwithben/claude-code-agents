# Changelog

All notable changes to this kit are listed here, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). To hear about releases, use GitHub's **Watch → Custom → Releases**.

## [Unreleased]

### Fixed
- Docs: MAINTENANCE.md, CONTRIBUTING.md and AGENTS.md said the kit makes no network calls, which stopped being true with the PM delta (it calls the user's own `gh`). They now say what is true: no telemetry, nothing sent anywhere, one script that uses `gh`.

## [0.2.0] - 2026-10-15

The kit becomes the single master copy: projects install a pinned version and keep only a small overlay. **Breaking: the repo layout and every install path changed** (see "Changed"); a 0.1.0 install is replaced by running `install.sh`.

### Added
- **Lead role** (`<prefix>-lead`): the main-session seat that scopes, files one issue per unit, dispatches roles in parallel worktrees, QAs the diff and lands. Never dispatched as a subagent; the picker and the routing guard say how to start it. Loop and modes: `docs/lead.md`.
- **PM role** (`<prefix>-pm`): triages only the board delta since its last run (cursor file named by the overlay), gives each issue one verdict, and writes chains of agent-ready work for the lead. `bin/pm-delta.mjs` reads the delta over REST; board specifics are overlay config.
- **In-flight ledger and heartbeat**: `lead-inflight-record` (PostToolUse on Agent plus SubagentStop) writes `tmp/lead/inflight.jsonl`; `bin/inflight.mjs` reads it (liveness is the subagent transcript's mtime, never worktree commits; landed means the handback sha is an ancestor of the main branch); `lead-heartbeat-check` is an agent-scoped Stop hook that blocks once per session and state when nothing runs and work can move.
- **Territory guard** (`role-territory-guard`): a file maps paths to owning roles, checked on every tool call. A rewrite, not a port (see "Fixed").
- **Overlay** `roles.config.json`: prefix, gate(s), handback contracts per role, territory and skills files, chains path, generic agent types to police, main-session roles, extra roles, lead and PM settings, install scope (project or user), kit version pin.
- **`install.sh`** with `--init` and `--check`: copies the core, renders the agents, merges hooks into `settings.json` (never overwrites; unrelated hooks survive; re-install does not duplicate), builds generated skills, records the version, prints the gate lines to add. `--check` reports MISSING, DRIFT and STALE and exits 1.
- **`build_skills.sh`**: generates rules skills from sections of your docs; `--check` fails on drift.
- **`ask.sh`**: headless dispatch with a cost log; recovers a handback that later chatter buried.
- **`kit-check`**: runs every fixture, hooks and installer. Every hook has a fixture that parses the script first and feeds malformed JSON.
- Extra roles declared in the overlay, rendered from a generic template; handback contracts from the overlay (kinds `gate`, `screenshots`, `concept-note`, `cursor`, `commit`, `line:NAME`).
- `docs/lead.md`.

### Changed
- Layout: the kit is now `core/` (hooks, bin, agent and skill templates), `lib/install.py`, `install.sh`, `examples/`. Nothing is copied by hand any more.
- Every hook is a tiny bash wrapper plus a python file. A crash or syntax error in the python exits 0; the wrapper exits 2 only when the python asks to block.
- Agents and skills are named with your prefix (`<prefix>-dev`, `<prefix>-build-rules`); hook paths are rendered into them.
- The handback contract per role is read from the overlay; the defaults match 0.1.0 (plus `pm`: a `CURSOR:` line).
- The routing guard reads the generic agent list from the overlay, and stands down when a territory file is configured.
- `roles-pulse.mjs` defaults its prefix from the overlay.

### Fixed (in the prototype the territory guard was rewritten from)
- **Territory ownership was taken from the first territory path anywhere in the text**, and any `>`, `tee` or `cp` anywhere made a command a "write". So `bash scripts/x.sh > /tmp/out.txt`, a `cp` from another territory to `/tmp`, and a brief that merely mentioned another role's file were all routed to the wrong role. Writes are now judged per target (redirect target, `tee`/`cp`/`mv`/`ln` destination, `rm`/`touch`/`mkdir` arguments, `sed -i` file, interpreter code that opens a file for writing), and a brief is denied only when none of the territories it names belongs to the dispatched agent. Fixtures: the three misroutes plus the true positives.

### Known limits
- The two-block cap in the sign-off hook is shared across agents of a role in a session (issue #2).
- Hooks in agent files do not run under `claude -p`, and the desktop app's own handback bypasses the Stop hook.

## [0.1.0] - 2026-10-14

First public release.

### Added
- Three roles: `role-dev`, `role-ui`, `role-concept`, each with its own scope, rules skill and (for the roles that edit code) its own worktree.
- Sign-off hook (`role-handback-check.sh`): a role cannot hand back without a `GATE:` line, or a `GATE-SKIPPED:` line with a reason.
- Routing guard and role picker hooks, and the `/roles` command.
- `roles-pulse.mjs`: reads Claude Code transcripts and reports use, evidence and cost per role run.
- `AGENTS.md`: an install procedure for an agent.
- Tests for every hook, each starting with a `bash -n` syntax check.

### Known limits
- The two-block cap in the sign-off hook is shared across agents of a role in a session (issue #2).
- Hooks in agent files do not run under `claude -p`, and the desktop app's own handback bypasses the Stop hook.
