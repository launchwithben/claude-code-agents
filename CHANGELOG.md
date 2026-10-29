# Changelog

All notable changes to this kit are listed here, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). To hear about releases, use GitHub's **Watch → Custom → Releases**.

## [0.4.0] - 2026-10-28

Design source and sign-off, an approvals ledger with an edit-do-not-redesign default, a quieter lead, and a size warning for generated skills (#20, #21, #22, #14). No breaking changes: a project that sets none of the new keys gets the same agents plus the new default rules below. Re-run `install.sh` to render the agents again.

### Added
- **`design` overlay key** (#20): `{source, file, signoff, exportsDir, callBudget, ledger}`. `source: "figma"` (any design tool; `file` required) makes `concept` render in the design file and `ui` build only from a frame the owner signed off (`signoff`, default true), read exported frames from `exportsDir` before spending design-tool quota, stay within `callBudget` calls and report the count, and end with `FRAME-SYNC: <frame> needs sync | none`. Default `source: "code"` renders nothing extra. Invalid values are refused.
- **Approvals ledger** (#21): `design.ledger` points at a `KEEP` / `KILL` / `CHANGE-REQUESTED` ledger the `ui` and `concept` roles read first, and `ui` hands back `LEDGER: changed <ids> | kept <ids>`. A ledger path that does not exist is a warning. Template: `examples/design-ledger.md`.
- **`build_skills.sh` warns** (#14) when a generated skill exceeds about 900 words (stderr, also under `--check`; never an error). `ROLE_KIT_SKILL_MAX_WORDS` changes the threshold.
- Fixtures for all of the above; the installer fixture now asserts the default and the figma renders of both roles.

### Changed
- **`ui` and `concept` always carry "Edit, do not redesign"** (#21): change only what the ask names, call out approved elements before touching them, return a before/after of the same page and a changed/kept list. It applies with or without a ledger.
- **Lead reports state, not narration** (#22): no step narration (one line before a long step at most); a background event that changes nothing gets no user-facing text and no new report; every reply that speaks ends with one state block. These rules stay when `lead.reportRule` replaces the block's format. The default Executive brief now has the sections **Live**, **Running**, **Needs you**, **Blocked**, **Suggest** (Running is new; Live replaces Done). In the lead agent, the lead rules skill and `docs/lead.md`.

## [0.3.0] - 2026-10-19

The lead's report to the owner is now an **Executive brief** by default, and an overlay can replace it (#18). Re-run `install.sh` to render the lead again.

### Changed
- **Default owner report:** a block that starts with the literal `**Executive brief**`, then only the non-empty sections Needs you (each decision a question, with `Recommend` and `Waiting costs` bullets), Blocked, Suggest and Done. No issue numbers, paths or tool names in it, and nothing after it. It replaces the 8-line `Shipped / Running / Needs you` report in the lead agent, the lead rules skill and `docs/lead.md`.

### Added
- **`lead.reportRule`** (one line): replaces the default report rule in both the lead agent and the lead rules skill.
- Fixtures: the default renders the brief and not the old report; `reportRule` replaces it in both files; `--check` stays clean.

## [0.2.3] - 2026-10-16

The ui and concept roles get a craft bar, not only a correctness bar (#17). No breaking changes; re-run `install.sh` to render the agents again.

### Added
- **Craft bar** in `<prefix>-ui` and `<prefix>-concept`, seven generic rules:
  - accent budget (one accent primary per view, never confetti)
  - constants adapt, never move
  - structure by hairline
  - hierarchy by type, not colour
  - detail
  - tokens only
  - the primary action rewards attention (a few hidden touches allowed, motion limits and `prefers-reduced-motion` respected)

  The project's own design rules still win on any conflict.
- `<prefix>-ui` reports accent-coloured elements per view, before and after, counted from the DOM, for any visual change.
- Fixtures: both rendered agents must carry the section.

## [0.2.2] - 2026-10-15

Five gaps found migrating the first real project onto the kit (#11). No breaking changes; re-run `install.sh`. (The v0.2.1 tag's README header line has a version typo; it is fixed here.)

### Added
- **Pattern evidence in handback contracts:** `line:NAME~REGEX`. A PM run that did not ack its cursor (`CURSOR: <ts> -> ACKED`) can now be blocked; `cursor` alone only wanted any value. A regex that does not compile is ignored (fail open).
- **`lead.appRoute`:** how the desktop app starts the lead (e.g. `/lead-agent`), used verbatim by the picker, the roles menu skill and the routing guard.
- **`lead.hookScope`: `"agent"` (default) or `"project"`.** `project` registers the in-flight recorder (PostToolUse) and the heartbeat (Stop) in `settings.json` for every session, and the lead agent file stops carrying its own copy. Both are keyed by `session_id`, so a session that never dispatched is never nudged.
- **Per-role body files for built-ins:** `"roles": {"pm": {"bodyFile": "...", "bodyMode": "append" | "replace"}}`. A project keeps its own PM procedure in the agent file instead of a side doc.
- **`lead.extraRulesFile`:** appended to the lead rules as "Project rules".
- **`build_skills.sh` 4th column** declares extra frontmatter (`user-invocable: true`), so a lead-rules skill can be generated from docs.

### Changed
- The lead-rules template now carries the generic rules that were left out: visible child session vs background agent (always background when the owner is away; archive a child session after landing), and verify EVERY "blocked" claim before accepting it.
- An `extraRoles` entry that collides with a built-in name is refused with a message saying how to change a built-in instead.
- The roles menu skill no longer hardcodes the desktop start route.

## [0.2.1] - 2026-10-15

### Fixed
- **`install.sh` warns about the starter example left in place** (prefix `acme`, `pm.repo` `acme/widgets`, an `extraGates` script that does not exist, a missing `territory` or `skills` file, the example `docs` role). An agent installing the untouched `--init` output used to get a silent exit 0 with a fake gate and a fake PM repo baked into every role. Warnings, not errors; fixtures added. `--init` now says it writes a populated example.
- AGENTS.md: the example-config trap, where AGENTS.md is read from, the `skills.txt` note, the real `kit-check` output and the `--check` path caveat.
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
