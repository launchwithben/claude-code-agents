# Security policy

## Read this before you install
This kit installs shell scripts as Claude Code hooks. They run with your user's permissions every time the matching event fires. That is the whole point of a hook, and it is also the risk, so read the scripts in `scripts/hooks/` before you copy them. There are three, none makes a network call, and none installs anything.

## Reporting a vulnerability
Please report it privately using **GitHub's "Report a vulnerability"** button on the repository's Security tab, not in a public issue. I will acknowledge a report within 7 days on a best-effort basis and credit you in the changelog if you want that.

## Supported versions
Only the latest release is supported.
