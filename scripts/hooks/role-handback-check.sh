#!/usr/bin/env bash
# role-handback-check.sh <role> — agent-scoped Stop (SubagentStop) hook for role agents.
#
# Reads the hook JSON on stdin and exits 2 (block, message to the agent) unless the role's
# contract evidence is in `last_assistant_message`:
#   *-dev        GATE line (PASS / exit 0)
#   *-ui         GATE line (PASS / exit 0)  +  SCREENSHOTS: line
#   *-concept    SCREENSHOTS: line  +  CONCEPT-NOTE: line
#   any role     OR an explicit `GATE-SKIPPED: <reason>` line (reason required)
# The role is matched by its SUFFIX, so `role-ui`, `acme-ui` and `ui` all get the UI contract.
# Prove it: bash scripts/hooks/role-handback-check.test.sh
#
# Built not to wedge an agent: it fails OPEN on its own runtime errors (missing python, bad JSON,
# unwritable state), and after 2 consecutive blocks for the same agent it allows through.
# EXCEPT a bash syntax error in this file: bash exits 2, which Claude Code reads as BLOCK. The
# test file runs `bash -n` first for that reason.
# Block counts live in <repo>/tmp/role-handback/ (gitignored) or $TMPDIR as a fallback.
role="${1:-}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || exit 0
repo="$(cd "$here/../.." 2>/dev/null && pwd)" || exit 0
state_dir="$repo/tmp/role-handback"
mkdir -p "$state_dir" 2>/dev/null || state_dir="${TMPDIR:-/tmp}/role-handback"
mkdir -p "$state_dir" 2>/dev/null || exit 0

payload="$(cat 2>/dev/null)" || exit 0
[ -n "$payload" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

out="$(ROLE="$role" STATE="$state_dir" PAYLOAD="$payload" python3 - <<'PY' 2>/dev/null
import json, os, re, sys
try:
    role = os.environ["ROLE"]
    state = os.environ["STATE"]
    p = json.loads(os.environ["PAYLOAD"])
    atype = p.get("agent_type") or ""
    if atype and role and atype != role:
        print("ALLOW"); sys.exit(0)          # not our role: never judge another agent
    msg = p.get("last_assistant_message") or ""
    key = re.sub(r"[^A-Za-z0-9_.-]", "_", str(p.get("agent_id") or p.get("session_id") or "unknown"))
    cnt_file = os.path.join(state, f"{role or 'role'}-{key}.count")

    def line(rx):
        return re.search(rx, msg, re.I | re.M)

    skipped = line(r"^\s*GATE-SKIPPED:\s*\S+")
    gate_ok = line(r"^\s*GATE:.*(\bPASS(ED)?\b|exit\s*(code\s*)?0\b)")
    shots = line(r"^\s*SCREENSHOTS:\s*\S+")
    note = line(r"^\s*CONCEPT-NOTE:\s*\S+")

    kind = role.rsplit("-", 1)[-1]
    if kind == "ui":
        ok = bool(skipped) or (bool(gate_ok) and bool(shots))
        need = "a line `GATE: <command> -> PASS` (the project's real check command) AND a line `SCREENSHOTS: <path>` (light/dark/mobile)"
    elif kind == "concept":
        ok = bool(skipped) or (bool(shots) and bool(note))
        need = "a line `SCREENSHOTS: <path>` (light/dark/mobile) AND a line `CONCEPT-NOTE: <path to your note>`"
    elif kind == "dev":
        ok = bool(skipped) or bool(gate_ok)
        need = "a line `GATE: <command> -> PASS` (the real gate you ran)"
    else:
        print("ALLOW"); sys.exit(0)           # unknown role: fail open

    if ok:
        try: os.remove(cnt_file)
        except OSError: pass
        print("ALLOW"); sys.exit(0)

    n = 0
    try: n = int(open(cnt_file).read().strip() or 0)
    except Exception: n = 0
    if n >= 2:                                  # already blocked twice: let it through
        try: os.remove(cnt_file)
        except OSError: pass
        print("ALLOW"); sys.exit(0)
    try: open(cnt_file, "w").write(str(n + 1))
    except Exception:
        print("ALLOW"); sys.exit(0)           # cannot count, so cannot guarantee release: fail open
    print("BLOCK|" + f"HANDBACK BLOCKED ({role}, attempt {n+1} of 2): your final message must include {need}. "
          "Run the gate / screenshots now and report them, or write `GATE-SKIPPED: <reason>` if it genuinely cannot run. "
          "See .claude/agents/" + role + ".md")
except Exception:
    print("ALLOW")
PY
)" || exit 0

case "$out" in
  BLOCK\|*) printf '%s\n' "${out#BLOCK|}" >&2; exit 2 ;;
  *) exit 0 ;;
esac
