#!/usr/bin/env python3
"""role-territory-guard.py - PreToolUse hook body: a territory file maps paths to the role that owns them.

Territory file (roles.config.json "territory": a path relative to the project root; no key = this guard is off):

    <role> <mode> <path>        first matching line wins
      role  a role suffix (`dev` for `acme-dev`), a full role name, or `-` = owned by nobody (the lead keeps it)
      mode  all   only the owner may read, search, edit, or brief an agent about these paths (a whole subsystem)
            edit  anyone may read; only the owner may CHANGE them
      path  relative to the project root; a prefix match (`scripts/ads/` and `runs/ads-` both work), or
            `re:<regex>` searched in the root-relative path (the absolute path for files outside the root)

Who is calling: payload `agent_type` (set on every sub-agent tool call) or env ROLE_KIT_ROLE (headless runs).
ROOT is $CLAUDE_PROJECT_DIR. A path under `<root>/.claude/worktrees/<name>/` is judged as if it were at the root.

WHAT COUNTS AS A WRITE (v0.2.0 rewrite; the first version looked for `>`/`tee`/`cp` ANYWHERE in a command and took
the owner of the FIRST territory path anywhere in the text, so `bash scripts/x.sh > /tmp/out.txt`, a `cp` FROM
another territory to /tmp, and a brief that merely MENTIONED another role's file were all routed to the wrong role):
  a write is judged PER TARGET: only a redirect target, a `tee`/`cp`/`mv`/`install`/`ln` destination, the paths a
  `rm`/`touch`/`mkdir`/`chmod`/`truncate` names, a `sed -i`/`perl -i` file, or a path inside interpreter code that
  opens a file for writing. A path that is only read or executed is not a write to it.
  A brief to an agent is denied only when NONE of the territories it names belongs to the dispatched agent.
Fails OPEN on any error of its own. Override when the owner asks for hands-on work: `touch <root>/tmp/role-override`
(valid 30 minutes). Always allowed: git, the kit's own scripts, the configured gate.
"""
import json
import os
import re
import shlex
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _kit  # noqa: E402


WRITE_CODE = re.compile(r"""open\([^)]*['"][wax]\+?b?['"]|write_text|write_bytes|writeFile|appendFile|createWriteStream|\.write\(|shutil\.(copy|move)|os\.(rename|remove|unlink)|fs\.(rename|unlink|rm|copyFile)|\bunlink\b|File\.write""")
INTERPRETERS = {"python", "python3", "node", "bash", "sh", "zsh", "ruby", "perl", "php", "deno", "bun"}
SKIP_PREFIX = {"sudo", "env", "command", "nohup", "time", "nice", "exec"}
WRITES_ALL_ARGS = {"rm", "rmdir", "touch", "mkdir", "chmod", "chown", "truncate", "unlink", "shred"}
DEST_LAST = {"cp", "install", "rsync", "ln"}
VALUE_FLAGS = {"-m", "--message", "--body", "--title", "-t", "--subject", "-F", "--body-file", "--notes"}
EDIT_BRIEF = re.compile(r"\b(fix|change|edit|add|implement|update|refactor|write|create|remove|delete|rename|build|modify|rewrite|patch|wire|replace|commit)\b", re.I)
READONLY = re.compile(r"read-only|read only|do not edit|don't edit|report only|no edits|without editing|do not modify", re.I)
CONTEXT_CUE = re.compile(r"(context|for reference|reference|\bsee\b|\bas in\b|compare[sd]?|mirror(s|ing)?|modell?ed on|patterned on|look at)[^.\n]{0,60}$", re.I)


# ---------------------------------------------------------------- territory file

def load_rows(root, cfg):
    rel = cfg.get("territory")
    if not rel:
        return []  # no "territory" in the overlay: this guard is off (role-routing-guard is the fallback)
    rows = []
    try:
        for line in open(os.path.join(root, str(rel))):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(None, 2)
            if len(parts) == 3 and parts[1] in ("all", "edit"):
                rows.append((parts[0], parts[1], parts[2].strip()))
    except Exception:
        return []
    return rows


class Territory:
    def __init__(self, root, rows, pfx):
        self.root, self.rows, self.pfx = root, rows, pfx

    def owner_key(self, role):
        return role if role == "-" else _kit.suffix_of(role, self.pfx)

    def lookup(self, abspath):
        """(owner suffix, mode) of the first matching row, else None."""
        rel = _kit.rel_to_root(self.root, abspath)
        for role, mode, path in self.rows:
            if path.startswith("re:"):
                try:
                    if re.search(path[3:], rel if rel is not None else abspath):
                        return self.owner_key(role), mode
                except re.error:
                    continue
            elif rel is not None and (rel.startswith(path) or rel == path.rstrip("/")):
                return self.owner_key(role), mode
        return None


# ---------------------------------------------------------------- path helpers

def looks_like_path(tok):
    if not tok or tok.startswith("-") or re.search(r"\s", tok) or len(tok) > 300:
        return False
    if tok.startswith(("/", "~", "./", "../")) or "/" in tok:
        return True
    return re.search(r"\.\w{1,5}$", tok) is not None


def candidates(tok):
    """Path-like strings a token may carry (`--file=a/b`, `of=a/b`)."""
    t = tok.strip("\"'`,;:()[]{}")
    out = []
    m = re.match(r"^(-{1,2}[\w-]+|\w+)=(.+)$", t)
    if m:
        t = m.group(2)
    if looks_like_path(t) and not re.match(r"^https?://", t):
        out.append(t)
    return out


def resolve(tok, cwd):
    # realpath, so a symlinked project dir and its resolved path are the same place
    return os.path.realpath(os.path.join(cwd, os.path.expanduser(tok)))


# ---------------------------------------------------------------- bash analysis

def split_heredocs(cmd):
    """-> (command with heredoc bodies removed, [(command line, body)])."""
    lines = cmd.split("\n")
    out, bodies, i = [], [], 0
    while i < len(lines):
        ln = lines[i]
        out.append(ln)
        m = re.search(r"<<-?\s*['\"]?(\w+)['\"]?", ln)
        i += 1
        if m:
            tag, body = m.group(1), []
            while i < len(lines) and lines[i].strip() != tag:
                body.append(lines[i])
                i += 1
            i += 1  # the terminator
            bodies.append((ln, "\n".join(body)))
    return "\n".join(out), bodies


def tokenize(cmd):
    s = cmd.replace("\\\n", " ").replace("\n", " ; ")
    lex = shlex.shlex(s, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


OPS = {";", "&&", "||", "|", "&", ";;", "|&"}


def segments(tokens):
    seg = []
    for t in tokens:
        if t in OPS:
            if seg:
                yield seg
            seg = []
        else:
            seg.append(t)
    if seg:
        yield seg


def analyze_bash(cmd, cwd, gate, kit_names):
    """-> (writes, mentions): lists of (token, abspath) for targets written / paths merely named."""
    writes, mentions = [], []
    body_cmd, heredocs = split_heredocs(cmd)
    eff = cwd
    try:
        toks = tokenize(body_cmd)
    except ValueError:
        return writes, mentions  # unbalanced quoting: cannot judge, fail open
    for seg in segments(toks):
        # redirects first: they write whatever the command is (even `git log > f`)
        args, i = [], 0
        while i < len(seg):
            t = seg[i]
            if re.match(r"^(&>>?|>>?|>\||>&)$", t) and i + 1 < len(seg):
                tgt = seg[i + 1]
                i += 2
                if tgt in ("/dev/null", "-") or re.match(r"^\d+$", tgt) or tgt.startswith("&"):
                    continue
                for c in candidates(tgt) or ([tgt] if not re.search(r"\s", tgt) else []):
                    writes.append((c, resolve(c, eff)))
                continue
            if re.match(r"^<{1,3}$", t):  # input redirect / here-string: the operand is read
                i += 2
                continue
            args.append(t)
            i += 1
        # drop env assignments and prefix words
        while args and (re.match(r"^\w+=", args[0]) or args[0] in SKIP_PREFIX):
            args = args[1:]
        if not args:
            continue
        name = os.path.basename(args[0])
        rest = args[1:]
        seg_text = " ".join(args)
        if name == "cd" and rest:
            eff = resolve(rest[0], eff)
            continue
        if name == "git":
            continue
        if gate and seg_text.startswith(gate):
            continue
        if any(k in args[0] or (len(args) > 1 and k in args[1]) for k in kit_names):
            continue
        # strip value flags (commit messages, issue text): prose, not paths
        clean, skip = [], False
        for a in rest:
            if skip:
                skip = False
                continue
            if a in VALUE_FLAGS:
                skip = True
                continue
            clean.append(a)
        nonflag = [a for a in clean if not a.startswith("-")]
        targets = []  # tokens this command writes
        if name == "tee":
            targets = nonflag
        elif name in WRITES_ALL_ARGS:
            targets = nonflag
        elif name == "mv":
            targets = nonflag  # source is removed, destination is written
        elif name in DEST_LAST:
            tflag = None
            for j, a in enumerate(clean):
                if a in ("-t", "--target-directory") and j + 1 < len(clean):
                    tflag = clean[j + 1]
            targets = [tflag] if tflag else nonflag[-1:]
        elif name in ("sed", "perl", "awk", "gawk") and any(
                re.match(r"^(-[a-zA-Z]*i[a-zA-Z.]*|--in-place(=.*)?)$", a) for a in clean):
            has_script = any(a in ("-e", "-f") for a in clean)
            targets = nonflag if has_script else nonflag[1:]
        elif name == "dd":
            targets = [a[3:] for a in clean if a.startswith("of=")]
        inline_code = None
        if name in INTERPRETERS:
            for j, a in enumerate(clean):
                if a in ("-c", "-e", "-p") and j + 1 < len(clean):
                    inline_code = clean[j + 1]
        tset = set(targets)
        for a in clean:
            for c in candidates(a):
                ap = resolve(c, eff)
                if a in tset:
                    writes.append((c, ap))
                elif inline_code is not None and a == inline_code:
                    pass
                else:
                    mentions.append((c, ap))
        for a in targets:  # a target with no extension and no slash (`touch notes`) is still a target
            if not candidates(a) and a and not a.startswith("-") and not re.search(r"\s", a):
                writes.append((a, resolve(a, eff)))
        if inline_code is not None:
            is_w = WRITE_CODE.search(inline_code) is not None
            for m in re.findall(r"""['"]([^'"\s]+)['"]""", inline_code):
                for c in candidates(m):
                    (writes if is_w else mentions).append((c, resolve(c, eff)))
    for line, body in heredocs:
        first = re.sub(r"^\s*(\w+=\S+\s+)*", "", line).split()
        interp = bool(first) and os.path.basename(first[0]) in INTERPRETERS
        if not interp and len(first) > 1:
            interp = os.path.basename(first[0]) in SKIP_PREFIX and os.path.basename(first[1]) in INTERPRETERS
        if interp:  # code fed to an interpreter may write files
            is_w = WRITE_CODE.search(body) is not None
            for m in re.findall(r"""['"]([^'"\s]+)['"]""", body):
                for c in candidates(m):
                    (writes if is_w else mentions).append((c, resolve(c, eff)))
    return writes, mentions


# ---------------------------------------------------------------- decision

def violation(terr, abspath, me, is_write):
    hit = terr.lookup(abspath)
    if not hit:
        return None
    owner, mode = hit
    if owner == "-" or owner == me:
        return None
    if mode == "edit" and not is_write:
        return None
    return owner, mode


def brief_named(terr, text, cwd):
    """[(owner, mode, token, context_only)] for territory paths named in a brief."""
    out = []
    for m in re.finditer(r"[^\s\"'`,;()\[\]{}<>]+", text):
        tok = m.group(0)
        for c in candidates(tok):
            hit = terr.lookup(resolve(c, cwd))
            if hit:
                window = text[max(0, m.start() - 70):m.start()]
                out.append((hit[0], hit[1], c, CONTEXT_CUE.search(window) is not None))
    return out


def check_brief(terr, ti, cwd, me):
    text = " ".join(str(ti.get(k) or "") for k in ("prompt", "description"))
    st = (ti.get("subagent_type") or "").strip().split(":")[-1]
    dispatched = _kit.suffix_of(st, terr.pfx) if st.startswith(terr.pfx + "-") else st
    named = [n for n in brief_named(terr, text, cwd) if n[0] != "-"]
    if not named:
        return None
    owners = {n[0] for n in named}
    if dispatched in owners or (me and me in owners):
        return None  # the dispatched agent owns at least one territory the brief names: a hand-over, not a misroute
    if any(n[1] == "all" for n in named):
        hit = next(n for n in named if n[1] == "all")
        return hit[0], hit[1], hit[2]
    if READONLY.search(text) or not EDIT_BRIEF.search(text):
        return None
    real = [n for n in named if not n[3]]  # a path cited only as context does not make the brief an edit of it
    if not real:
        return None
    return real[0][0], real[0][1], real[0][2]


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": "deny", "permissionDecisionReason": reason}}))
    return 0


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        return 0
    data = json.loads(raw)
    root = _kit.find_root(data)
    cfg = _kit.load_config(root)
    rows = load_rows(root, cfg)
    if not rows:
        return 0  # no territory file: this guard stands down (role-routing-guard.py is the fallback)
    ov = os.path.join(root, "tmp", "role-override")
    if os.path.exists(ov) and time.time() - os.path.getmtime(ov) < 1800:
        return 0
    pfx = _kit.prefix(cfg)
    terr = Territory(root, rows, pfx)
    tool = data.get("tool_name", "")
    ti = data.get("tool_input") or {}
    caller = data.get("agent_type") or os.environ.get("ROLE_KIT_ROLE", "")
    me = _kit.suffix_of(caller, pfx) if caller else ""
    cwd = data.get("cwd") or os.getcwd()
    found = None  # (owner, mode, what, is_write)

    if tool in ("Read", "Edit", "Write", "NotebookEdit", "MultiEdit"):
        p = ti.get("file_path") or ti.get("notebook_path") or ""
        if p:
            w = tool != "Read"
            v = violation(terr, resolve(p, cwd), me, w)
            if v:
                found = (v[0], v[1], p, w)
    elif tool in ("Grep", "Glob"):
        p = ti.get("path") or ""
        if p:
            v = violation(terr, resolve(p, cwd), me, False)
            if v and v[1] == "all":
                found = (v[0], v[1], p, False)
    elif tool == "Bash":
        gate = str(cfg.get("gate") or "").strip()
        kit_names = ("roles-kit/bin/ask.sh", "roles-kit/bin/build_skills.sh", "roles-kit/bin/kit-check", "roles-kit/install.sh")
        writes, mentions = analyze_bash(ti.get("command", ""), cwd, gate, kit_names)
        for tok, ap in writes:
            v = violation(terr, ap, me, True)
            if v:
                found = (v[0], v[1], tok, True)
                break
        if not found:
            for tok, ap in mentions:
                v = violation(terr, ap, me, False)
                if v and v[1] == "all":
                    found = (v[0], v[1], tok, False)
                    break
    elif tool in ("Agent", "Task"):
        v = check_brief(terr, ti, cwd, me)
        if v:
            found = (v[0], v[1], v[2], True)

    if not found:
        return 0
    owner, mode, what, is_write = found
    kit_bin = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin")
    full = "%s-%s" % (pfx, owner)
    scope = "this subsystem" if mode == "all" else "changes here"
    return deny(
        "ROLE TERRITORY: %s (%s) belong to the `%s` role. Hand it over instead of doing it yourself: "
        "Agent(subagent_type: \"%s\", prompt: \"<one task + the facts you hold; 'Read-only, do not edit' for a question>\") "
        "or headless: bash %s/ask.sh %s \"<brief>\". QA its handback and diff (git show is allowed), then land it. "
        "Only if the owner explicitly asked you to do it yourself: touch %s/tmp/role-override (30 min)."
        % (scope, what, owner, full, kit_bin, owner, root))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        if os.environ.get("ROLE_KIT_DEBUG"):  # still exits 0 (fail open); this only shows why
            import traceback
            traceback.print_exc()
        sys.exit(0)
