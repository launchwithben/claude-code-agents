# Changelog

All notable changes to this kit are listed here, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). To hear about releases, use GitHub's **Watch → Custom → Releases**.

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
