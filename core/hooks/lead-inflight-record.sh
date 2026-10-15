#!/usr/bin/env bash
# lead-inflight-record.sh - thin wrapper for lead-inflight-record.py (the python file says what the hook does).
# Exits 2 (block) ONLY when the python file asks for it. A missing python3, a crash or a syntax error in the
# python file all exit 0: a hook of this kit must never wedge a session. This file stays tiny on purpose,
# because a bash syntax error exits 2 = block; its fixture starts with `bash -n`.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
python3 "$here/lead-inflight-record.py" "$@"
[ "$?" = 2 ] && exit 2
exit 0
