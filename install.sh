#!/usr/bin/env bash
# install.sh - install the role kit into a project from its overlay (roles.config.json), or check for drift.
#
#   cd your-project && git clone --branch v0.2.0 <kit url> ../claude-code-agents   # pin a tag
#   bash ../claude-code-agents/install.sh --init      # writes a starter roles.config.json
#   $EDITOR roles.config.json                         # prefix, gate, territory...
#   bash ../claude-code-agents/install.sh             # install (safe to re-run: it MERGES settings.json)
#   bash ../claude-code-agents/install.sh --check     # clean, or lists MISSING / DRIFT / STALE and exits 1
#
# Options: --target DIR (default: current directory), --config FILE, --check, --init, --force.
# The work is in lib/install.py (python3, stdlib only).
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "install.sh needs python3" >&2; exit 1; }
exec python3 "$here/lib/install.py" "$@"
