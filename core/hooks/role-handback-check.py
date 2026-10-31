#!/usr/bin/env python3
"""role-handback-check.py <role> - agent-scoped Stop (SubagentStop) hook body for role agents.

Blocks (exit 2, message on stderr) unless the evidence the role's contract names is in `last_assistant_message`.
Contracts come from roles.config.json ("handback": {"<suffix or full role name>": ["gate", "screenshots", ...]});
defaults: dev [gate], ui [gate, screenshots], concept [screenshots, concept-note], pm [cursor],
design [line:FRAMES, line:EXPORTS, line:CALLS, line:REQUESTER, line:OWNER-SIGNOFF]. A role whose
suffix has no contract is allowed. Evidence kinds: gate, screenshots, concept-note, cursor, commit, line:NAME, line:NAME~REGEX.
Any role may instead end with `GATE-SKIPPED: <reason>`.
Fails OPEN on its own errors and lets an agent through after 2 consecutive blocks.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _kit  # noqa: E402

EVIDENCE = {
    "gate": (r"^\s*GATE:.*(\bPASS(ED)?\b|exit\s*(code\s*)?0\b)",
             "a line `GATE: <command> -> PASS` (the real gate you ran)"),
    "screenshots": (r"^\s*SCREENSHOTS:\s*\S+", "a line `SCREENSHOTS: <path>` (light/dark/mobile)"),
    "concept-note": (r"^\s*CONCEPT-NOTE:\s*\S+", "a line `CONCEPT-NOTE: <path to your note>`"),
    "cursor": (r"^\s*CURSOR:\s*\S+", "a line `CURSOR: <ISO time> -> ACKED`"),
    "commit": (r"^\s*COMMIT:\s*[0-9a-f]{7,40}\b", "a line `COMMIT: <sha> on branch <name>`"),
}


def evidence(kind):
    """-> (regex, message) or None. `line:NAME` wants a `NAME: <something>` line; `line:NAME~REGEX` wants the text
    after `NAME:` to match REGEX (e.g. `line:CURSOR~\\S+ -> ACKED`). A regex that does not compile is ignored (fail open)."""
    if kind in EVIDENCE:
        return EVIDENCE[kind]
    m = re.match(r"^line:([A-Za-z][A-Za-z0-9_-]*)(?:~(.+))?$", kind)
    if m:
        name, pat = m.group(1), m.group(2)
        if pat is None:
            return (r"^\s*" + re.escape(name) + r":\s*\S+", "a line `" + name + ": <value>`")
        try:
            re.compile(pat)
        except re.error:
            return None
        return (r"^\s*" + re.escape(name) + r":\s*(?:" + pat + ")", "a line `" + name + ": ...` matching /" + pat + "/")
    return None


def main():
    role = sys.argv[1] if len(sys.argv) > 1 else ""
    raw = sys.stdin.read()
    if not raw.strip():
        return 0
    p = json.loads(raw)
    root = _kit.find_root(p)
    cfg = _kit.load_config(root)
    atype = p.get("agent_type") or ""
    if atype and role and atype != role:
        return 0  # not our role: never judge another agent
    contract_map = _kit.contracts(cfg)
    contract = contract_map.get(role)
    if contract is None:
        contract = contract_map.get(_kit.suffix_of(role, _kit.prefix(cfg)))
    if not contract:
        return 0  # unknown role or empty contract: fail open
    msg = p.get("last_assistant_message") or ""
    key = re.sub(r"[^A-Za-z0-9_.-]", "_", str(p.get("agent_id") or p.get("session_id") or "unknown"))
    state = os.path.join(root, "tmp", "role-handback")
    try:
        os.makedirs(state, exist_ok=True)
    except Exception:
        state = os.path.join(os.environ.get("TMPDIR", "/tmp"), "role-handback")
        os.makedirs(state, exist_ok=True)
    cnt_file = os.path.join(state, "%s-%s.count" % (role or "role", key))

    def has(rx):
        return re.search(rx, msg, re.I | re.M) is not None

    skipped = has(r"^\s*GATE-SKIPPED:\s*\S+")
    needs = []
    for kind in contract:
        ev = evidence(kind)
        if ev and not has(ev[0]):
            needs.append(ev[1])
    if skipped or not needs:
        try:
            os.remove(cnt_file)
        except OSError:
            pass
        return 0
    n = 0
    try:
        n = int(open(cnt_file).read().strip() or 0)
    except Exception:
        n = 0
    if n >= 2:  # already blocked twice: let it through
        try:
            os.remove(cnt_file)
        except OSError:
            pass
        return 0
    try:
        open(cnt_file, "w").write(str(n + 1))
    except Exception:
        return 0  # cannot count, so cannot guarantee release: fail open
    sys.stderr.write(
        "HANDBACK BLOCKED (%s, attempt %d of 2): your final message must include %s. "
        "Run the gate / produce the evidence now and report it, or write `GATE-SKIPPED: <reason>` if it genuinely "
        "cannot run. See .claude/agents/%s.md\n" % (role, n + 1, " AND ".join(needs), role))
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
