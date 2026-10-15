# Security policy

## Read this before you install
This kit installs shell scripts as Claude Code hooks. They run with your user's permissions every time the matching event fires. That is the whole point of a hook, and it is also the risk, so read the scripts in `core/hooks/` and `core/bin/` before you install them. None makes a network call (the PM delta calls the `gh` you already have, and only if you run it), and none installs anything. `install.sh` writes only inside the project (or `~/.claude/` for a user-scope install) and merges into `settings.json` without removing your own entries.

## Reporting a vulnerability
Please report it privately using **GitHub's "Report a vulnerability"** button on the repository's Security tab, not in a public issue. I will acknowledge a report within 7 days on a best-effort basis and credit you in the changelog if you want that.

## Supported versions
Only the latest release is supported.
