#!/usr/bin/env bash
# role-picker.sh — UserPromptSubmit hook: a bare `@agent-role` (no role after it) gets the role menu.
#
# Nobody memorises role names. Typing `@agent-role` alone, or a name that is not a role
# (`@agent-role-uii`), injects the list of role-* agents — read from .claude/agents/, never
# typed here — and tells the assistant to ask which one to run. A full, valid `@agent-role-<name>`
# is left alone: the app already invokes that role.
# Fails OPEN and silent on any error: it may only add context, never block a prompt.
# Fixtures: scripts/hooks/role-picker.test.sh
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || exit 0
agents="$(cd "$here/../.." 2>/dev/null && pwd)/.claude/agents"
command -v python3 >/dev/null 2>&1 || exit 0
AGENTS="$agents" python3 -c '
import json, os, re, sys, glob
try:
    prompt = json.load(sys.stdin).get("prompt") or ""
    roles = {}
    for f in sorted(glob.glob(os.path.join(os.environ["AGENTS"], "role-*.md"))):
        txt = open(f).read()
        name = re.search(r"^name:\s*(\S+)", txt, re.M)
        desc = re.search(r"^description:\s*>-?\s*\n\s+(.+?)(?:\n\S|\Z)", txt, re.M | re.S) or re.search(r"^description:\s*(.+)$", txt, re.M)
        if name:
            d = re.sub(r"\s+", " ", desc.group(1)).strip() if desc else ""
            two = ". ".join(d.split(". ")[:2]); roles[name.group(1)] = two if len(two) <= 200 else two[:200].rsplit(" ", 1)[0] + "…"
    mentions = re.findall(r"@agent-(role[\w-]*)", prompt)
    if not mentions or all(m in roles for m in mentions) or not roles:
        sys.exit(0)
    print("<role-picker>")
    print("The owner typed a bare or unknown `@agent-role` mention. Do NOT start any agent yet. Ask which role to run with AskUserQuestion: one option per role below (label = role name, description = its line), plus the owner can type a task with it. Once chosen, dispatch that role (Agent tool, subagent_type = the role) with the rest of their message as the brief.")
    for r, d in roles.items():
        print(f"- {r}: {d}")
    print("Tell the owner they can skip this menu next time by typing @agent-<role> <task>.")
    print("</role-picker>")
except Exception:
    sys.exit(0)
' 2>/dev/null
exit 0
