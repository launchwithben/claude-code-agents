#!/usr/bin/env python3
"""role-routing-guard.py - PreToolUse hook body for the Agent tool: the prompt-regex routing guard.

1. A dispatch to a main-session role (default: <prefix>-lead) is denied: that seat is a chat you start, not a subagent.
2. If the project has a territory file (roles.config.json "territory" and the file exists) the territory guard
   (role-territory-guard.py) owns routing and this guard stands down: it is the FALLBACK for repos without one.
3. Otherwise: a GENERIC worker (config "genericAgents") whose prompt asks to EDIT/BUILD UI is denied and pointed to
   <prefix>-ui / <prefix>-concept; one asked for any other repo change (change verb + repo path or commit) is
   denied and pointed to <prefix>-dev. Read-only passes ("read-only", "do not edit", "report only"...).
Denials are logged to <root>/tmp/role-routing/denials.jsonl for roles-pulse. Fails OPEN. Exit 2 = deny.
"""
import datetime
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _kit  # noqa: E402

READONLY = re.compile(r"read[- ]only|do not edit|don't edit|report only|no edits|without editing|do not modify", re.I)
VERB = re.compile(r"\b(edit|build|implement|create|add|write|modify|change|redesign|restyle|refactor|rewrite|rework|fix|update|polish|tweak|style|design|make)\b")
# No bare "style": "match the existing code style" is not a UI task.
UI = re.compile(r"\.(astro|vue|svelte|jsx|tsx|css|scss)\b|\bcomponents?/|\bstyles?/|\blayouts?/|\bstyling\b|\bdesign\b|\bcss\b|tailwind|stylesheet")
CHANGE = re.compile(r"\b(edit|implement|modify|change|refactor|rewrite|rework|fix|update|patch|restore|replace|remove|delete|rename|migrate|wire|add|create)\b")
REPO = re.compile(r"\bcommit\b|(^|[\s`(])(src|scripts|docs|public|lib|app|tests?|\.github)/|\.(mjs|js|ts|json|md|sh|yml|yaml|py)\b")


def log(root, kind, st, ti):
    try:
        d = os.path.join(root, "tmp", "role-routing")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "denials.jsonl"), "a") as f:
            f.write(json.dumps({"at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"), "kind": kind,
                                "subagent_type": st, "description": str(ti.get("description") or "")[:120]}) + "\n")
    except Exception:
        pass


def app_route(cfg, role):
    lead = cfg.get("lead")
    route = lead.get("appRoute") if isinstance(lead, dict) else None
    return "use `%s`" % route if route else "run `/%s-rules` in a new chat" % role


def deny(msg):
    sys.stderr.write(msg + "\n")
    return 2


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        return 0
    p = json.loads(raw)
    ti = p.get("tool_input") or {}
    st = (ti.get("subagent_type") or "").strip()
    base = st.split(":")[-1]  # plugin:bulk-worker -> bulk-worker
    root = _kit.find_root(p)
    cfg = _kit.load_config(root)
    pfx = _kit.prefix(cfg)

    for r in _kit.main_session_roles(cfg):
        if base == "%s-%s" % (pfx, r):
            log(root, "main-session", st, ti)
            return deny("ROUTING GUARD: `%s` is a main-session seat, not a subagent. Start it as the chat itself: "
                        "CLI `claude --agent %s`, or in the desktop app %s. "
                        "Dispatch the other roles from there." % (base, base, app_route(cfg, "%s-%s" % (pfx, r))))

    tf = cfg.get("territory")
    if tf and os.path.isfile(os.path.join(root, str(tf))):
        return 0  # the territory guard owns routing in this repo

    generic = set(cfg.get("genericAgents") or _kit.DEFAULT_GENERIC_AGENTS) | {""}
    if base not in generic:
        return 0
    low = " ".join(str(ti.get(k) or "") for k in ("prompt", "description")).lower()
    if READONLY.search(low):
        return 0
    who = st or "default"
    if VERB.search(low) and UI.search(low):
        log(root, "ui", st, ti)
        return deny("ROUTING GUARD: this dispatch asks a generic worker (%s) to edit/build UI. Route to `%s-ui` "
                    "(build UI in code) or `%s-concept` (direction: 'show 3 ways'). If it is genuinely read-only "
                    "analysis, say 'read-only, do not edit' in the prompt." % (who, pfx, pfx))
    if CHANGE.search(low) and REPO.search(low):
        log(root, "repo", st, ti)
        return deny("ROUTING GUARD: this dispatch asks a generic worker (%s) to change repo files. Repo edits go to a "
                    "role, which carries this repo's rules and gate: `%s-dev` (scripts, data, content, config) or "
                    "`%s-ui` (components, styles). If it is genuinely read-only, say 'read-only, do not edit' in the "
                    "prompt." % (who, pfx, pfx))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
