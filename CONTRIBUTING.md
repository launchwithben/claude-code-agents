# Contributing

Issues and pull requests are welcome. Keep in mind this is a small kit maintained by one person, so replies are best-effort.

- **Found a bug or a Claude Code change that broke a hook?** Open an issue with your Claude Code version, what you expected and what happened.
- **Using it?** Open a "Report a result" issue. It tells me what works and what does not, and it is the only usage signal I get, because the kit has no telemetry.
- **Pull requests:** keep them small and single-purpose. Every hook change needs a fixture in its `*.test.sh`, and `bash -n` on the script must pass first. Run `for t in scripts/hooks/*.test.sh; do bash "$t" | tail -1; done` before you open the PR; all three must print `ALL PASS`.
- **Please do not** add dependencies, network calls or telemetry. The kit's promise is that it has none.
- Be decent to each other. That is the whole code of conduct.
