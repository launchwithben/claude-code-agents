# Maintenance and status

**Current status: Active.** Maintained by [Launch With Ben](https://launchwithben.com). Last reviewed: 2026-10-14.

## What "active" means here
- I read issues and pull requests and answer on a best-effort basis. There is no SLA.
- Releases are tagged and listed in [CHANGELOG.md](CHANGELOG.md). Breaking changes bump the minor version while we are below 1.0 and are called out under "Changed".
- The kit is tested against Claude Code as it behaves today. Claude Code changes quickly; if a release of Claude Code breaks a hook, an issue here is the fastest way to tell me.

## How a fix found in a consuming project flows back here
This repo is the one master copy; a project holds an installed copy plus its overlay. So a fix is never made "just in the project":

1. **Reproduce it in the kit.** Add a fixture that fails (a `*.test.sh` next to the hook or script, or a case in `tests/install.test.sh`), with the smallest input from the project that shows it. A fix with no failing fixture first has not been understood yet.
2. **Fix it in `core/` (or `lib/`).** Never patch `scripts/roles-kit/` or `.claude/agents/<prefix>-*.md` in the project: the next install overwrites them, and `install.sh --check` reports the edit as DRIFT, which is how an in-place patch gets noticed.
3. **`bash kit-check` must be green**, `CHANGELOG.md` gets an entry in the same commit, and `VERSION` is bumped (patch for a fix, minor while below 1.0 for anything that changes behaviour or the overlay).
4. **Tag and release** (`vX.Y.Z`). Projects then `git checkout` the tag in their kit clone, run `install.sh --check` to see what changes, and `install.sh` to apply.
5. If the problem was project-specific (a rule, a path, a board detail), it is overlay config and stays in the project. Nothing project-specific enters this repo: no client names, paths, board ids or product rules, in code, fixtures or docs.

A project that finds a bug while a fix is urgent may carry a temporary local patch, but it files the issue here the same day and drops the patch on the next install.

## How you hear about changes
- **GitHub:** Watch → Custom → Releases.
- **Newsletter:** the free [AI Boss newsletter](https://launchwithben.com/newsletter) carries a note when something here changes in a way that matters.

## How I learn how it is used
Nothing in this kit phones home: no telemetry, no network calls, no tracking. I find out from GitHub itself (stars, forks, issues, clones) and from what you tell me. If you use it, the "Report a result" issue template takes one minute and is the most useful thing you can send.

## Reviews
The kit is reviewed on a fixed schedule. The first review is **2026-12-14**. At each review it is marked one of: **Active**, **Maintenance only** (security and breakage fixes, no new features) or **Sunset**.

## If this is sunset
A sunset will never be silent. In this order:
1. The top of the README and this file say **SUNSET**, with the date and the reason.
2. A final release is tagged with a changelog entry that says what to use instead, or that nothing replaces it.
3. The repository is archived (read-only), so it can still be cloned and forked, and the license stays MIT.
4. The write-up on launchwithben.com is updated to say the same.

Until one of those happens, assume the status at the top of this file is the truth.
