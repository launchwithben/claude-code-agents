#!/usr/bin/env python3
"""role-picker.py - UserPromptSubmit hook body: a bare `@agent-<prefix>` (no role after it) gets the role menu.

Nobody memorises role names. Typing `@agent-<prefix>` alone, or a name that is not a role (`@agent-<prefix>-uii`),
injects the list of <prefix>-* agents, read from .claude/agents/ (project) and ~/.claude/agents/ (user), never
typed here, and tells the assistant to ask which one to run. A full, valid `@agent-<prefix>-<role>` is left alone,
EXCEPT a main-session role (default: lead): that seat is never dispatched as a subagent, so the hook prints how
to start it as a chat instead (CLI `claude --agent <prefix>-lead`, or its rules skill in the desktop app).
Adds context only, never blocks. Fails OPEN and silent on any error.
"""
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _kit  # noqa: E402


def agents(root, pfx):
    found = {}
    dirs = [os.path.join(os.path.expanduser("~"), ".claude", "agents"), os.path.join(root, ".claude", "agents")]
    for d in dirs:  # project wins over user
        for f in sorted(glob.glob(os.path.join(d, pfx + "-*.md"))):
            txt = open(f).read()
            name = re.search(r"^name:\s*(\S+)", txt, re.M)
            desc = re.search(r"^description:\s*>-?\s*\n\s+(.+?)(?:\n\S|\Z)", txt, re.M | re.S) or \
                re.search(r"^description:\s*(.+)$", txt, re.M)
            if name:
                d_ = re.sub(r"\s+", " ", desc.group(1)).strip() if desc else ""
                two = ". ".join(d_.split(". ")[:2])
                found[name.group(1)] = two if len(two) <= 200 else two[:200].rsplit(" ", 1)[0] + "…"
    return found


def main():
    p = json.loads(sys.stdin.read() or "{}")
    prompt = p.get("prompt") or ""
    root = _kit.find_root(p)
    cfg = _kit.load_config(root)
    pfx = _kit.prefix(cfg)
    mentions = re.findall(r"@agent-(" + re.escape(pfx) + r"[\w-]*)", prompt)
    if not mentions:
        return 0
    roles = agents(root, pfx)
    if not roles:
        return 0
    seats = {"%s-%s" % (pfx, r) for r in _kit.main_session_roles(cfg)}
    if all(m in roles for m in mentions) and not any(m in seats for m in mentions):
        return 0
    dispatchable = {k: v for k, v in roles.items() if k not in seats}
    mine = {k: v for k, v in roles.items() if k in seats}
    print("<role-picker>")
    if any(m in seats for m in mentions) and all(m in roles for m in mentions):
        print("The owner named a main-session role. It is a chat seat, NOT a subagent: do not dispatch it with the Agent tool.")
    else:
        print("The owner typed a bare or unknown `@agent-%s` mention. Do NOT start any agent yet. Ask which role to run "
              "with AskUserQuestion: one option per dispatchable role below (label = role name, description = its line), "
              "plus the owner can type a task with it. Once chosen, dispatch that role (Agent tool, subagent_type = the "
              "role) with the rest of their message as the brief." % pfx)
    for r, d in dispatchable.items():
        print("- %s: %s" % (r, d))
    for r, d in mine.items():
        print("- %s (main-session seat, never dispatched): %s" % (r, d))
        route = (cfg.get("lead") or {}).get("appRoute") if isinstance(cfg.get("lead"), dict) else None
        app = "`%s`" % route if route else "run `/%s-rules` in a new chat" % r
        print("    start it as the chat itself: CLI `claude --agent %s`; desktop app: %s to load its rules." % (r, app))
    print("Tell the owner they can skip this menu next time by typing @agent-<role> <task>.")
    print("</role-picker>")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
