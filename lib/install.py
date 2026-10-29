#!/usr/bin/env python3
"""install.py - the body of install.sh. Installs (or checks) the role kit in a project from its overlay.

    install.sh [--target DIR] [--config FILE] [--init] [--check] [--force]

The kit is the base, the project keeps a small overlay (roles.config.json + optional territory.txt, skills.txt).
Install = copy the core at this kit version -> render the agents with the project's prefix and hook paths -> write the
core rules skills -> build the project's generated skills -> MERGE the kit's hooks into settings.json (never
overwrite) -> record the version. `--check` renders everything again in memory and reports MISSING / DRIFT / STALE
for anything that differs, exit 1 if any: run it in CI or after `git pull` of the kit.
Stdlib only, python 3.8+.
"""
import argparse
import json
import os
import re
import subprocess
import sys

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(KIT, "core")
ALL_ROLES = ["lead", "pm", "dev", "ui", "concept"]
MARK = "roles-kit/hooks/"
TERRITORY_MATCHER = "Agent|Task|Read|Edit|Write|MultiEdit|NotebookEdit|Grep|Glob|Bash"


def die(msg, code=1):
    print("install: " + msg, file=sys.stderr)
    sys.exit(code)


def kit_version():
    return open(os.path.join(KIT, "VERSION")).read().strip()


# ---------------------------------------------------------------- templates

def render(text, v):
    """{{KEY}}, {{#if KEY}}..{{/if}}, {{#unless KEY}}..{{/unless}} (not nested)."""
    def block(kind):
        rx = re.compile(r"\{\{#%s (\w+)\}\}(.*?)\{\{/%s\}\}" % (kind, kind), re.S)

        def sub(m):
            truthy = bool(v.get(m.group(1)))
            return m.group(2) if truthy == (kind == "if") else ""
        return rx, sub
    for kind in ("if", "unless"):
        rx, sub = block(kind)
        text = rx.sub(sub, text)
    out = re.sub(r"\{\{(\w+)\}\}", lambda m: str(v.get(m.group(1), m.group(0))), text)
    left = re.findall(r"\{\{[#/]?\w+\}\}", out)
    if left:
        die("unresolved template placeholder(s): " + ", ".join(sorted(set(left))))
    return out


def one_line(s):
    return re.sub(r"\s+", " ", str(s)).strip()


# ---------------------------------------------------------------- config

def load_config(path):
    try:
        cfg = json.load(open(path))
    except FileNotFoundError:
        die("no overlay at %s. Run `install.sh --init` to start from the example." % path)
    except ValueError as e:
        die("%s is not valid JSON: %s" % (path, e))
    if not isinstance(cfg, dict):
        die("%s must hold a JSON object" % path)
    if not re.match(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$", str(cfg.get("prefix") or "")):
        die('"prefix" is required in %s: lowercase words joined by dashes, e.g. "acme"' % path)
    roles = cfg.get("roles", ALL_ROLES)
    opts = {}
    if isinstance(roles, dict):  # {"pm": {"bodyFile": "...", "bodyMode": "append|replace"}}: per-role options
        for k, o in roles.items():
            if o is None:
                o = {}
            if not isinstance(o, dict):
                die('"roles.%s" must be an object like {"bodyFile": "docs/x.md", "bodyMode": "append"}' % k)
            if o.get("bodyMode", "append") not in ("append", "replace"):
                die('"roles.%s.bodyMode" must be "append" or "replace"' % k)
            opts[k] = o
        roles = list(roles)
    elif not isinstance(roles, list):
        die('"roles" must be a list of role names, or an object of per-role options')
    extras = [r for r in (cfg.get("extraRoles") or [])]
    names = {r.get("name") for r in extras if isinstance(r, dict)}
    for r in extras:
        if not isinstance(r, dict) or not re.match(r"^[a-z][a-z0-9-]*$", str(r.get("name") or "")) or not r.get("description"):
            die('each "extraRoles" entry needs a lowercase "name" and a "description"')
        if r["name"] in ALL_ROLES:
            die('"extraRoles" entry %r collides with the built-in role of the same name. To change what the built-in role '
                'says, use "roles": {"%s": {"bodyFile": "<file>", "bodyMode": "append" or "replace"}}; to add a different '
                'role, pick another name.' % (r["name"], r["name"]))
    for r in roles:
        if r not in ALL_ROLES and r not in names:
            die('unknown role %r in "roles" (built in: %s; add custom ones under "extraRoles")' % (r, ", ".join(ALL_ROLES)))
    cfg["_roles"] = [r for r in ALL_ROLES if r in roles]
    cfg["_roleopts"] = opts
    lead = cfg.get("lead") or {}
    if not isinstance(lead, dict):
        die('"lead" must be an object')
    if lead.get("hookScope", "agent") not in ("agent", "project"):
        die('"lead.hookScope" must be "agent" or "project"')
    d = cfg.get("design") or {}
    if not isinstance(d, dict):
        die('"design" must be an object like {"source": "figma", "file": "<url>", "ledger": "docs/design/ledger.md"}')
    if d.get("source", "code") not in ("code", "figma"):
        die('"design.source" must be "code" or "figma"')
    if d.get("source") == "figma" and not str(d.get("file") or "").strip():
        die('"design.source" is "figma": "design.file" (the design file url or key) is required')
    if "callBudget" in d and (isinstance(d["callBudget"], bool) or not isinstance(d["callBudget"], int) or d["callBudget"] < 1):
        die('"design.callBudget" must be a positive whole number')
    if "signoff" in d and not isinstance(d["signoff"], bool):
        die('"design.signoff" must be true or false')
    if "pageNaming" in d and not (isinstance(d["pageNaming"], str) and "{surface}" in d["pageNaming"] and "{n}" in d["pageNaming"]):
        die('"design.pageNaming" must be a string containing {surface} and {n}, like "{surface} v{n}"')
    for k in ("file", "exportsDir", "ledger", "pageNaming"):
        if k in d and not isinstance(d[k], str):
            die('"design.%s" must be a string' % k)
    cfg["_extras"] = extras
    return cfg


def scope_paths(cfg, target, scope):
    if scope == "user":
        home = os.path.expanduser("~")
        return {"kit": os.path.join(home, ".claude", "roles-kit"), "agents": os.path.join(home, ".claude", "agents"),
                "skills": os.path.join(home, ".claude", "skills"), "settings": os.path.join(home, ".claude", "settings.json"),
                "kit_expr": "$HOME/.claude/roles-kit"}
    return {"kit": os.path.join(target, "scripts", "roles-kit"), "agents": os.path.join(target, ".claude", "agents"),
            "skills": os.path.join(target, ".claude", "skills"), "settings": os.path.join(target, ".claude", "settings.json"),
            "kit_expr": "$CLAUDE_PROJECT_DIR/scripts/roles-kit"}


def design_vars(cfg, pfx):
    """The design-source and approvals-ledger sections of the ui and concept roles, rendered from core/templates/design.
    Default (source "code", no ledger) renders to nothing, so the agents are unchanged for a code-first project."""
    d = cfg.get("design") or {}
    figma = d.get("source") == "figma"
    signoff = d.get("signoff", True)
    flags = {
        "PREFIX": pfx,
        "DESIGN_FILE": str(d.get("file") or "").strip(),
        "DESIGN_EXPORTS": str(d.get("exportsDir") or "").strip(),
        "DESIGN_BUDGET": str(d.get("callBudget") or ""),
        "DESIGN_LEDGER": str(d.get("ledger") or "").strip(),
        "DESIGN_PAGE": str(d.get("pageNaming") or "{surface} v{n}").strip(),
        "DESIGN_F": "1" if figma else "",
        "DESIGN_FS": "1" if figma and signoff else "",
        "DESIGN_FN": "1" if figma and not signoff else "",
    }
    flags["DESIGN_FE"] = "1" if figma and flags["DESIGN_EXPORTS"] else ""
    flags["DESIGN_FB"] = "1" if figma and flags["DESIGN_BUDGET"] else ""
    tpl = os.path.join(CORE, "templates", "design")
    hb = ""
    if figma:
        hb += "FRAME-SYNC: <frame> needs sync | none\n"
    if flags["DESIGN_LEDGER"]:
        hb += "LEDGER: changed <ids> | kept <ids>\n"
    return {
        "DESIGN_UI": render(open(os.path.join(tpl, "ui.md")).read(), flags),
        "DESIGN_CONCEPT": render(open(os.path.join(tpl, "concept.md")).read(), flags),
        "DESIGN_HANDBACK_UI": hb,
    }


def variables(cfg, paths):
    pfx = cfg["prefix"]
    pm = cfg.get("pm") or {}
    lead = cfg.get("lead") or {}
    gate = str(cfg.get("gate") or "").strip()
    kit = paths["kit_expr"]
    dispatchable = [r for r in cfg["_roles"] if r != "lead"] + [e["name"] for e in cfg["_extras"]]
    rolelist = " / ".join("%s-%s" % (pfx, r) for r in dispatchable)
    routing = lead.get("routing")
    if not routing:
        bits = []
        if "ui" in cfg["_roles"]:
            bits.append("UI -> `%s-ui`" % pfx)
        if "concept" in cfg["_roles"]:
            bits.append("direction -> `%s-concept`" % pfx)
        if "pm" in cfg["_roles"]:
            bits.append("board -> `%s-pm`" % pfx)
        for e in cfg["_extras"]:
            bits.append("%s -> `%s-%s`" % (one_line(e.get("routes") or e["name"]), pfx, e["name"]))
        if "dev" in cfg["_roles"]:
            bits.append("everything else that edits -> `%s-dev`" % pfx)
        routing = ", ".join(bits) or "to the role that owns the work"
    rules = pm.get("rules") or []
    return dict(design_vars(cfg, pfx), **{
        "PREFIX": pfx,
        "CHECK": gate or "<check command>",
        "EXTRA_GATES": ", ".join("`%s`" % g for g in (cfg.get("extraGates") or [])),
        "HOOKS": kit + "/hooks",
        "KIT": kit,
        "CHAINS": cfg.get("chains") or "docs/pm/chains.md",
        "MAIN_BRANCH": cfg.get("mainBranch") or "main",
        "READY_LABEL": pm.get("readyLabel") or "agent-ready",
        "PM_CURSOR": pm.get("cursor") or "docs/pm/state.json",
        "PM_DELTA": pm.get("deltaCommand") or "node %s/bin/pm-delta.mjs" % kit,
        "PM_ACK": pm.get("ackCommand") or "node %s/bin/pm-delta.mjs --ack" % kit,
        "PM_PATHS": " ".join(pm.get("paths") or ["docs/pm"]),
        "PM_READ_FIRST": ", ".join("`%s`" % p for p in (pm.get("readFirst") or [])),
        "PM_RULES": "\n".join("- " + one_line(r) for r in rules),
        "FOCUS_CMD": lead.get("focusCommand") or "",
        "SHIP_STEP": lead.get("shipStep") or "",
        "PROMOTE_RULE": lead.get("promoteRule") or "",
        "REPORT_RULE": one_line(lead.get("reportRule") or ""),
        "ROLE_LIST": rolelist,
        "ROUTING": routing,
        "APP_START": ("use `%s`" % lead["appRoute"]) if lead.get("appRoute") else "run `/%s-lead-rules` in a new chat" % pfx,
        "HEARTBEAT_PROJECT": "1" if lead.get("hookScope") == "project" else "",
    })


# ---------------------------------------------------------------- the plan

def read(p):
    with open(p, "rb") as f:
        return f.read()


def skills_defined(cfg, target):
    names = set()
    p = os.path.join(target, str(cfg.get("skills") or "roles/skills.txt"))
    try:
        for ln in open(p):
            ln = ln.strip()
            if ln and not ln.startswith("#") and "|" in ln:
                names.add(ln.split("|", 1)[0].strip())
    except OSError:
        pass
    return names


def extra_agent(cfg, e, v, target):
    body = e.get("body") or ""
    if e.get("bodyFile"):
        try:
            body = open(os.path.join(target, e["bodyFile"])).read().strip()
        except OSError:
            die('extraRoles %s: bodyFile %s not found' % (e["name"], e["bodyFile"]))
    if isinstance(body, list):
        body = "\n".join(body)
    if not body:
        body = "You are this project's %s role. Do the one task you were given, run `%s`, commit in your worktree with a pathspec, report, and STOP." % (e["name"], v["CHECK"])
    skills = e.get("skills")
    if skills is None:
        skills = ["%s-build-rules" % cfg["prefix"]]
    ev = dict(v, NAME=e["name"], DESCRIPTION=one_line(e["description"]), MODEL=e.get("model") or "sonnet",
              COLOR=e.get("color") or "cyan", WORKTREE="1" if e.get("worktree", True) else "",
              SKILLS="\n".join("  - " + s for s in skills), BODY=body)
    return render(open(os.path.join(CORE, "templates", "agents", "extra.md")).read(), ev)


def project_file(target, rel, what):
    try:
        return open(os.path.join(target, rel)).read()
    except OSError:
        die('%s: %s not found (paths are relative to the project root)' % (what, rel))


def body_override(text, extra, mode):
    """append: the project's text goes after the kit's body. replace: it replaces the body (frontmatter is kept)."""
    m = re.match(r"^(---\n.*?\n---\n)", text, re.S)
    head = m.group(1) if m else ""
    if mode == "replace":
        return head + "\n" + extra.strip() + "\n"
    return text.rstrip("\n") + "\n\n" + extra.strip() + "\n"


def plan(cfg, target, scope):
    """-> (files {abs path: bytes}, starters {abs path: bytes}, settings entries [(event, matcher, command)])"""
    paths = scope_paths(cfg, target, scope)
    v = variables(cfg, paths)
    files, starters = {}, {}
    # 1. the core scripts, copied as they are
    for sub in ("hooks", "bin"):
        d = os.path.join(CORE, sub)
        for n in sorted(os.listdir(d)):
            if n == "__pycache__" or not os.path.isfile(os.path.join(d, n)):
                continue
            files[os.path.join(paths["kit"], sub, n)] = read(os.path.join(d, n))
    files[os.path.join(paths["kit"], "VERSION")] = (kit_version() + "\n").encode()
    # 2. the agents, rendered
    tpl = os.path.join(CORE, "templates", "agents")
    for r in cfg["_roles"]:
        text = render(open(os.path.join(tpl, r + ".md")).read(), v)
        o = cfg["_roleopts"].get(r) or {}
        if o.get("bodyFile"):
            text = body_override(text, project_file(target, o["bodyFile"], "roles.%s.bodyFile" % r), o.get("bodyMode", "append"))
        files[os.path.join(paths["agents"], "%s-%s.md" % (cfg["prefix"], r))] = text.encode()
    for e in cfg["_extras"]:
        files[os.path.join(paths["agents"], "%s-%s.md" % (cfg["prefix"], e["name"]))] = extra_agent(cfg, e, v, target).encode()
    # 3. skills: the menu and the lead rules are the kit's; build/design rules are starters; generated ones win
    gen = skills_defined(cfg, target)
    stpl = os.path.join(CORE, "templates", "skills")
    pfx = cfg["prefix"]

    lead_cfg = cfg.get("lead") or {}

    def skill(name, tplname, bucket):
        if name in gen:
            return
        text = render(open(os.path.join(stpl, tplname, "SKILL.md")).read(), v)
        if tplname == "lead-rules" and lead_cfg.get("extraRulesFile"):  # appended verbatim, never templated
            text = text.rstrip("\n") + "\n\n## Project rules\n\n" + project_file(target, lead_cfg["extraRulesFile"], "lead.extraRulesFile").strip() + "\n"
        bucket[os.path.join(paths["skills"], name, "SKILL.md")] = text.encode()
    skill("roles", "roles", files)
    if "lead" in cfg["_roles"]:
        skill(pfx + "-lead-rules", "lead-rules", files)
    skill(pfx + "-build-rules", "build-rules", starters)
    if "ui" in cfg["_roles"] or "concept" in cfg["_roles"]:
        skill(pfx + "-design-rules", "design-rules", starters)
    # 4. settings entries
    hooks = v["HOOKS"]

    def cmd(script, arg=""):
        return 'bash "%s/%s"%s' % (hooks, script, (" " + arg) if arg else "")
    ent = [("PreToolUse", "Agent|Task", cmd("role-routing-guard.sh")),
           ("UserPromptSubmit", None, cmd("role-picker.sh"))]
    if cfg.get("territory"):
        ent.insert(1, ("PreToolUse", TERRITORY_MATCHER, cmd("role-territory-guard.sh")))
    if "lead" in cfg["_roles"]:
        ent += [("PostToolUse", "Agent|Task", cmd("lead-inflight-record.sh", "dispatch")),
                ("SubagentStop", None, cmd("lead-inflight-record.sh", "done"))]
        if v["HEARTBEAT_PROJECT"]:  # every session, not only `--agent <prefix>-lead`; keyed by session_id, so safe
            ent.append(("Stop", None, cmd("lead-heartbeat-check.sh")))
    return paths, files, starters, ent


# ---------------------------------------------------------------- settings.json

def load_settings(path):
    if not os.path.exists(path):
        return {}
    try:
        d = json.load(open(path))
    except ValueError as e:
        die("%s is not valid JSON (%s). Fix it first; the installer will not overwrite a file it cannot parse." % (path, e))
    if not isinstance(d, dict):
        die("%s must hold a JSON object" % path)
    return d


def is_kit(h):
    return isinstance(h, dict) and MARK in str(h.get("command", ""))


def merge_settings(settings, ent):
    hooks = settings.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        die('"hooks" in settings.json is not an object')
    for event in list(hooks):  # drop every kit-owned hook first: re-install replaces, never duplicates
        lst = hooks[event]
        if not isinstance(lst, list):
            continue
        kept = []
        for entry in lst:
            hs = entry.get("hooks") if isinstance(entry, dict) else None
            if isinstance(hs, list) and any(is_kit(h) for h in hs):
                rest = [h for h in hs if not is_kit(h)]
                if rest:
                    entry = dict(entry, hooks=rest)
                    kept.append(entry)
            else:
                kept.append(entry)
        hooks[event] = kept
    for event, matcher, command in ent:
        e = {"hooks": [{"type": "command", "command": command, "timeout": 15 if "heartbeat" in command else 10}]}
        if matcher:
            e = dict({"matcher": matcher}, **e)
        hooks.setdefault(event, [])
        if not isinstance(hooks[event], list):
            die('hooks.%s in settings.json is not an array' % event)
        hooks[event].append(e)
    for event in [k for k, vv in hooks.items() if vv == []]:
        del hooks[event]
    return settings


def settings_has(settings, ent):
    missing = []
    for event, matcher, command in ent:
        ok = False
        for entry in (settings.get("hooks") or {}).get(event) or []:
            if not isinstance(entry, dict) or (entry.get("matcher") or None) != matcher:
                continue
            if any(h.get("command") == command for h in entry.get("hooks") or [] if isinstance(h, dict)):
                ok = True
        if not ok:
            missing.append("%s%s -> %s" % (event, " [%s]" % matcher if matcher else "", command))
    return missing


# ---------------------------------------------------------------- commands

def write(path, data, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    if mode:
        os.chmod(path, mode)


def check(cfg, target, scope):
    paths, files, starters, ent = plan(cfg, target, scope)
    bad = 0
    for p in sorted(files):
        short = os.path.relpath(p, target) if p.startswith(target + os.sep) else p
        if not os.path.exists(p):
            print("MISSING  %s" % short); bad += 1
        elif read(p) != files[p]:
            print("DRIFT    %s (differs from kit %s; reinstall to reset it, or move the change into the kit/overlay)" % (short, kit_version())); bad += 1
    for p in sorted(starters):
        if not os.path.exists(p):
            print("MISSING  %s (starter rules skill)" % (os.path.relpath(p, target) if p.startswith(target + os.sep) else p)); bad += 1
    for m in settings_has(load_settings(paths["settings"]), ent):
        print("MISSING  settings hook: %s" % m); bad += 1
    for sub in ("hooks", "bin"):  # a kit file the new version no longer ships
        d = os.path.join(paths["kit"], sub)
        if os.path.isdir(d):
            for n in sorted(os.listdir(d)):
                p = os.path.join(d, n)
                if os.path.isfile(p) and p not in files:
                    print("STALE    %s (not in kit %s)" % (os.path.relpath(p, target) if p.startswith(target + os.sep) else p, kit_version())); bad += 1
    bs = os.path.join(paths["kit"], "bin", "build_skills.sh")
    if os.path.exists(bs):
        r = subprocess.run(["bash", bs, "--check"], env=dict(os.environ, ROLE_KIT_ROOT=target), capture_output=True, text=True)
        if r.returncode != 0:
            for ln in (r.stdout + r.stderr).strip().splitlines():
                print("DRIFT    generated skill: " + ln)
            bad += 1
    if bad:
        print("install --check: %d problem(s)" % bad)
        return 1
    print("install --check: clean (kit %s, prefix %s, %d files)" % (kit_version(), cfg["prefix"], len(files)))
    return 0


def install(cfg, target, scope):
    paths, files, starters, ent = plan(cfg, target, scope)
    settings = merge_settings(load_settings(paths["settings"]), ent)  # parse BEFORE writing anything
    fresh_agents = not os.path.isdir(paths["agents"])
    for sub in ("hooks", "bin"):  # clear kit files this version no longer ships
        d = os.path.join(paths["kit"], sub)
        if os.path.isdir(d):
            for n in os.listdir(d):
                p = os.path.join(d, n)
                if os.path.isfile(p) and p not in files:
                    os.remove(p)
    for p, data in files.items():
        write(p, data, 0o755 if os.path.basename(os.path.dirname(p)) in ("hooks", "bin") else None)
    kept = []
    for p, data in starters.items():
        if os.path.exists(p):
            kept.append(p)
        else:
            write(p, data)
    write(os.path.join(paths["kit"], "INSTALLED"), ("%s\n%s\n" % (kit_version(), describe())).encode())
    write(paths["settings"], (json.dumps(settings, indent=2) + "\n").encode())
    bs = os.path.join(paths["kit"], "bin", "build_skills.sh")
    sk = os.path.join(target, str(cfg.get("skills") or "roles/skills.txt"))
    if os.path.exists(sk):
        r = subprocess.run(["bash", bs], env=dict(os.environ, ROLE_KIT_ROOT=target), capture_output=True, text=True)
        sys.stdout.write(r.stdout)
        if r.returncode != 0:
            sys.stderr.write(r.stderr)
            die("build_skills failed (see above); the rest of the install is in place")
    print("installed role kit %s into %s (scope: %s, prefix: %s)" % (kit_version(), target, scope, cfg["prefix"]))
    print("  agents  : %s" % ", ".join("%s-%s" % (cfg["prefix"], r) for r in cfg["_roles"] + [e["name"] for e in cfg["_extras"]]))
    print("  kit     : %s" % paths["kit"])
    print("  settings: %s (kit hooks merged; your own entries untouched)" % paths["settings"])
    if kept:
        print("  kept your existing rules skill(s): " + ", ".join(os.path.relpath(k, target) if k.startswith(target + os.sep) else k for k in kept))
    notes(cfg, target, scope, paths, fresh_agents, starters)
    return 0


def describe():
    try:
        return subprocess.run(["git", "-C", KIT, "describe", "--tags", "--always", "--dirty"], capture_output=True, text=True).stdout.strip()
    except Exception:
        return ""


def ignored(target, rel):
    try:
        return subprocess.run(["git", "-C", target, "check-ignore", "-q", rel], capture_output=True).returncode == 0
    except Exception:
        return False


def notes(cfg, target, scope, paths, fresh_agents, starters):
    print("")
    rel = lambda p: os.path.relpath(p, target) if p.startswith(target + os.sep) else p
    todo = []
    if scope == "project":
        if ignored(target, ".claude/agents") or ignored(target, ".claude/settings.json"):
            todo.append("`.claude/` is gitignored here: commit the roles with `git add -f .claude/ %s %s` or a fresh worktree will not have them."
                        % (rel(paths["kit"]), "roles.config.json"))
        if not ignored(target, "tmp/x"):
            todo.append("hooks write ledgers and logs under `tmp/`: add `tmp/` to .gitignore.")
    if fresh_agents:
        todo.append("restart Claude Code: a brand-new agents folder is not picked up until a new session (`/clear` is not enough).")
    todo.append("accept the workspace trust prompt: hooks in agent files only run in a trusted folder.")
    fill = [rel(p) for p in starters]
    if fill:
        todo.append("fill in the starter rules skill(s) with your real rules, or generate them from your docs (roles/skills.txt): " + ", ".join(fill))
    if not cfg.get("gate"):
        todo.append('set "gate" in roles.config.json (your real check command), then re-run install.sh: the agents print a placeholder until you do.')
    print("Next:")
    for i, t in enumerate(todo, 1):
        print("  %d. %s" % (i, t))
    print("")
    k = rel(paths["kit"])
    print("Add these to your project's gate so the kit cannot rot silently:")
    print("  bash %s/bin/kit-check" % k)
    if os.path.exists(os.path.join(target, str(cfg.get("skills") or "roles/skills.txt"))):
        print("  bash %s/bin/build_skills.sh --check" % k)
    print("  bash %s/install.sh --check      # run from your clone of the kit: reports drift against kit %s" % ("<kit clone>", kit_version()))
    if "lead" in cfg["_roles"]:
        print("")
        print("Start the lead as the main chat: `claude --agent %s-lead` (a main-session seat is never dispatched as a subagent)." % cfg["prefix"])


def unfinished(cfg, target):
    """Things in the overlay that look like the starter example left in place. Warnings, never errors:
    a real project may legitimately use any of them. (An agent installing the untouched starter used to get a
    silent exit 0 with a fake gate and a fake PM repo baked into every role.)"""
    out = []
    pm = cfg.get("pm") or {}
    if cfg.get("prefix") == "acme":
        out.append('"prefix" is still "acme" (the example). Use a short word for your project.')
    if "pm" in cfg["_roles"] and str(pm.get("repo") or "") == "acme/widgets":
        out.append('pm.repo is still "acme/widgets" (the example). Set your own "owner/name" or drop the "pm" role.')
    for g in (cfg.get("extraGates") or []):
        m = re.match(r"^(?:bash|sh|node|python3?)\s+(\S+)", str(g))
        if m and not os.path.exists(os.path.join(target, m.group(1))):
            out.append('extraGates "%s" points at %s, which does not exist, so every role would be told to run it. Delete the key or add the script.' % (g, m.group(1)))
    for key in ("territory", "skills"):
        if cfg.get(key) and not os.path.exists(os.path.join(target, str(cfg[key]))):
            out.append('"%s" points at %s, which does not exist. Create it, or delete the key to turn the feature off.' % (key, cfg[key]))
    d = cfg.get("design") or {}
    if d.get("ledger") and not os.path.exists(os.path.join(target, d["ledger"])):
        out.append('"design.ledger" points at %s, which does not exist. The ui and concept roles are told to read it first: create it (see examples/design-ledger.md in the kit) or delete the key.' % d["ledger"])
    if any(e.get("name") == "docs" and "Technical writer for the docs site" in str(e.get("description")) for e in cfg["_extras"]):
        out.append('extraRoles still holds the example "docs" role. Delete it or make it yours.')
    return out


def main():
    ap = argparse.ArgumentParser(prog="install.sh", description=__doc__.split("\n\n")[0])
    ap.add_argument("--target", default=os.getcwd(), help="project root (default: the current directory)")
    ap.add_argument("--config", help="overlay file (default: <target>/roles.config.json)")
    ap.add_argument("--init", action="store_true", help="write a starter roles.config.json and exit")
    ap.add_argument("--check", action="store_true", help="report drift against this kit version; change nothing")
    ap.add_argument("--force", action="store_true", help="install even if the overlay pins a different kit version")
    a = ap.parse_args()
    target = os.path.realpath(a.target)
    cfgpath = a.config or os.path.join(target, "roles.config.json")
    if a.init:
        if os.path.exists(cfgpath):
            die("%s already exists" % cfgpath)
        write(cfgpath, read(os.path.join(KIT, "examples", "roles.config.json")))
        print("wrote %s. It is a populated EXAMPLE, not a blank: set \"prefix\" and \"gate\", trim \"roles\" to what you use, and delete the keys that do not apply (extraGates, territory, skills, pm, extraRoles). install.sh warns about example values left in place." % cfgpath)
        return 0
    cfg = load_config(cfgpath)
    pin = str(cfg.get("kit") or "").lstrip("v")
    if pin and pin != kit_version() and not a.force:
        die("the overlay pins kit %s but this checkout is %s. `git checkout v%s` in the kit clone, or update \"kit\" "
            "in roles.config.json (or pass --force)." % (pin, kit_version(), pin))
    scope = cfg.get("scope") or "project"
    if scope not in ("project", "user"):
        die('"scope" must be "project" or "user"')
    if not a.check:
        for w in unfinished(cfg, target):
            print("WARNING: " + w, file=sys.stderr)
    return check(cfg, target, scope) if a.check else install(cfg, target, scope)


if __name__ == "__main__":
    sys.exit(main())
