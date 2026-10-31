#!/usr/bin/env python3
"""_kit.py - shared helpers for the role-kit hooks (stdlib only, python 3.8+).

Every hook is a thin bash wrapper around a python file that imports this module. Nothing here may raise
into a hook: callers wrap their work in try/except and exit 0 on error (fail open).

Command line (used by the shell scripts):
    python3 _kit.py cfg <root> <dotted.key> [default]     print one value from <root>/roles.config.json
"""
import json
import os
import re
import sys

CONFIG_NAME = "roles.config.json"

DEFAULT_CONTRACTS = {
    "dev": ["gate"],
    "ui": ["gate", "screenshots"],
    "concept": ["screenshots", "concept-note"],
    "pm": ["cursor"],
    "design": ["line:FRAMES", "line:EXPORTS", "line:CALLS", "line:REQUESTER", "line:OWNER-SIGNOFF"],
}
DEFAULT_GENERIC_AGENTS = ["bulk-worker", "general-purpose", "full-stack-developer", "haiku-worker", "claude"]
DEFAULT_MAIN_SESSION = ["lead"]


def find_root(payload=None):
    """Project root: $CLAUDE_PROJECT_DIR, else the nearest parent of the payload cwd that holds a config or .git."""
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env and os.path.isdir(env):
        return os.path.realpath(env)
    cwd = (payload or {}).get("cwd") or os.getcwd()
    d = os.path.realpath(cwd)
    while True:
        if os.path.exists(os.path.join(d, CONFIG_NAME)) or os.path.exists(os.path.join(d, ".git")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return os.path.realpath(cwd)
        d = parent


def load_config(root):
    try:
        with open(os.path.join(root, CONFIG_NAME)) as f:
            c = json.load(f)
        return c if isinstance(c, dict) else {}
    except Exception:
        return {}


def get(cfg, dotted, default=None):
    cur = cfg
    for part in dotted.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return default
    return cur


def prefix(cfg):
    p = cfg.get("prefix") if isinstance(cfg, dict) else None
    return p if isinstance(p, str) and p else "role"


def suffix_of(name, pfx):
    """'acme-ui' -> 'ui' when the prefix is 'acme'; otherwise the last dash segment."""
    name = name or ""
    if pfx and name.startswith(pfx + "-"):
        return name[len(pfx) + 1:]
    return name.rsplit("-", 1)[-1]


def contracts(cfg):
    out = dict(DEFAULT_CONTRACTS)
    hb = cfg.get("handback")
    if isinstance(hb, dict):
        for k, v in hb.items():
            if isinstance(v, list):
                out[k] = [str(x) for x in v]
    for r in cfg.get("extraRoles") or []:
        if isinstance(r, dict) and r.get("name") and isinstance(r.get("contract"), list):
            out.setdefault(r["name"], [str(x) for x in r["contract"]])
    return out


def main_session_roles(cfg):
    v = cfg.get("mainSessionRoles")
    return [str(x) for x in v] if isinstance(v, list) else list(DEFAULT_MAIN_SESSION)


def rel_to_root(root, path):
    """Absolute path -> root-relative, also stripping a worktree prefix (.claude/worktrees/<name>/)."""
    p = os.path.normpath(path)
    root = os.path.normpath(root)
    if p == root:
        return ""
    if not p.startswith(root + os.sep):
        return None
    rel = p[len(root) + 1:]
    m = re.match(r"^\.claude/worktrees/[^/]+/(.*)$", rel)
    return m.group(1) if m else rel


def _cli(argv):
    if len(argv) >= 4 and argv[1] == "cfg":
        v = get(load_config(argv[2]), argv[3], argv[4] if len(argv) > 4 else "")
        if isinstance(v, (dict, list)):
            print(json.dumps(v))
        elif v is not None:
            print(v)
        return 0
    print("usage: _kit.py cfg <root> <dotted.key> [default]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(_cli(sys.argv))
    except Exception:
        sys.exit(0)
