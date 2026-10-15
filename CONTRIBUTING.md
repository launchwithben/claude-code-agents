# Contributing

Issues and pull requests are welcome. Keep in mind this is a small kit maintained by one person, so replies are best-effort.

- **Found a bug or a Claude Code change that broke a hook?** Open an issue with your Claude Code version, what you expected and what happened.
- **Using it?** Open a "Report a result" issue. It tells me what works and what does not, and it is the only usage signal I get, because the kit has no telemetry.
- **Pull requests:** keep them small and single-purpose. Every hook or script change needs a fixture that fails without it (next to the script as `*.test.sh`, or in `tests/install.test.sh`), and every fixture file starts by parsing the script it tests. Run `bash kit-check` before you open the PR; it must print `GREEN`.
- **A fix you found in your own project** belongs here as a fixture plus a change in `core/`, not as a patch to your installed copy (see `MAINTENANCE.md`).
- **Please do not** add dependencies, network calls or telemetry, or anything specific to one project (names, paths, ids): that is overlay config. The kit's promise is that it has no telemetry and no network calls.
- Be decent to each other. That is the whole code of conduct.
