#!/usr/bin/env bash
# role-routing-guard.sh — PreToolUse hook on the Agent tool.
#
# Denies (exit 2) a dispatch to a GENERIC worker whose prompt asks to EDIT/BUILD UI (an edit or
# build verb plus .astro / src/components / styles / design / CSS), and tells the lead to route to
# role-ui (build) or role-concept (direction). It also denies a generic worker any NON-UI repo
# change (change verb + repo path or commit) and names role-dev. Read-only passes. Fails OPEN.
# A prompt that says "read-only" / "do not edit" / "report only" / "no edits" passes by design.
# Fixtures: bash scripts/hooks/role-routing-guard.test.sh
# Edit GENERIC below if your setup has other general-purpose agent types.
payload="$(cat 2>/dev/null)" || exit 0
[ -n "$payload" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
out="$(PAYLOAD="$payload" python3 - <<'PY' 2>/dev/null
import json, os, re
try:
    p = json.loads(os.environ["PAYLOAD"])
    ti = p.get("tool_input") or {}
    st = (ti.get("subagent_type") or "").strip()
    base = st.split(":")[-1]                       # daily-skills:bulk-worker -> bulk-worker
    generic = {"", "bulk-worker", "general-purpose", "full-stack-developer", "haiku-worker", "claude"}
    if base not in generic:
        print("ALLOW"); raise SystemExit
    text = " ".join(str(ti.get(k) or "") for k in ("prompt", "description"))
    low = text.lower()
    if re.search(r"read[- ]only|do not edit|don't edit|report only|no edits|without editing|do not modify", low):
        print("ALLOW"); raise SystemExit
    verb = re.search(r"\b(edit|build|implement|create|add|write|modify|change|redesign|restyle|refactor|rewrite|rework|fix|update|polish|tweak|style|design|make)\b", low)
    # No bare "style": "match the existing code style" is not a UI task (false deny, 2026-10-13).
    ui = re.search(r"\.astro\b|src/components|src/styles|src/layouts|\bstyling\b|\bdesign\b|\bcss\b|tailwind|stylesheet", low)
    # Non-UI repo edits: a change verb plus a repo path or a commit. "write a summary" alone is not one.
    # Without this branch, a content or script edit sails through: the UI-word check cannot see it.
    change = re.search(r"\b(edit|implement|modify|change|refactor|rewrite|rework|fix|update|patch|restore|replace|remove|delete|rename|migrate|wire|add|create)\b", low)
    repo = re.search(r"\bcommit\b|(^|[\s\x60(])(src|scripts|docs|public|functions|popups|concepts|\.github)/|\.(mjs|js|ts|json|md|sh|yml|yaml)\b", low)
    def log(kind):
        # Local evidence for the next roles pulse: without it a guard that never fires and one
        # that fires daily look identical .
        try:
            import datetime
            root = os.environ.get("CLAUDE_PROJECT_DIR")
            if not root: return                # no project dir: skip rather than litter the cwd
            d = os.path.join(root, "tmp", "role-routing")
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "denials.jsonl"), "a") as f:
                f.write(json.dumps({"at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"), "kind": kind,
                                    "subagent_type": st, "description": str(ti.get("description") or "")[:120]}) + "\n")
        except Exception:
            pass
    if verb and ui:
        log("ui")
        print("DENY|ROUTING GUARD: this dispatch asks a generic worker (" + (st or "default") + ") to edit/build UI. "
              "Route to `role-ui` (build UI in code) or `role-concept` (direction: 'show 3 ways'). "
              "If it is genuinely read-only analysis, say 'read-only, do not edit' in the prompt.")
    elif change and repo:
        log("repo")
        print("DENY|ROUTING GUARD: this dispatch asks a generic worker (" + (st or "default") + ") to change repo files. "
              "Repo edits go to a role, which carries this repo's build rules and gates: `role-dev` (scripts, data, content, config), "
              "`role-ui` (components, styles). If it is genuinely read-only, say 'read-only, do not edit' in the prompt. "
              "See docs/agents-sop/agent-roles.md")
    else:
        print("ALLOW")
except SystemExit:
    pass
except Exception:
    print("ALLOW")
PY
)" || exit 0
case "$out" in
  DENY\|*) printf '%s\n' "${out#DENY|}" >&2; exit 2 ;;
  *) exit 0 ;;
esac
