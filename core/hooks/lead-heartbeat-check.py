#!/usr/bin/env python3
"""lead-heartbeat-check.py - session-scoped Stop hook body for the lead seat.

When the lead is about to stop its turn and NO role is running, but the in-flight ledger shows finished-and-unlanded
work, or the chains file (roles.config.json "chains", default docs/pm/chains.md) has a launchable chain under
"## Ready chains" (### headings), block ONCE with "land X / dispatch Y". Then release: the same state (session +
ledger/chains signature) never blocks twice, so the lead can always answer "idle, nothing to do" next time.
Roles running (ledger) => allow. stop_hook_active => allow. A session that never dispatched => allow (keyed by
session_id). Fails OPEN on any error of its own. Exit 2 = block.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _kit  # noqa: E402


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        return 0
    p = json.loads(raw)
    if p.get("stop_hook_active"):
        return 0
    sid_raw = str(p.get("session_id") or "")
    if not sid_raw:
        return 0
    root = _kit.find_root(p)
    cfg = _kit.load_config(root)
    state = os.environ.get("LEAD_LEDGER_DIR") or os.path.join(root, "tmp", "lead")
    chains_file = os.environ.get("LEAD_CHAINS_FILE") or os.path.join(root, str(cfg.get("chains") or "docs/pm/chains.md"))
    os.makedirs(state, exist_ok=True)
    reader = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "inflight.mjs")
    env = dict(os.environ, LEAD_LEDGER_DIR=state, CLAUDE_PROJECT_DIR=root)
    snap = subprocess.run(["node", reader, "--json", "--session", sid_raw], capture_output=True, text=True,
                          env=env, timeout=20)
    if snap.returncode != 0 or not snap.stdout.strip():
        return 0
    s = json.loads(snap.stdout)
    if not s.get("total") or s.get("running"):
        return 0  # this session dispatched nothing, or a role is running: waiting is correct
    unl = s.get("finishedUnlanded") or []
    chains = []
    try:
        txt = open(chains_file).read()
        m = re.search(r"^## Ready chains\s*$(.*?)(?=^## |\Z)", txt, re.M | re.S)
        if m:
            chains = [h.strip() for h in re.findall(r"^### (.+)$", m.group(1), re.M)]
    except Exception:
        chains = []
    if not unl and not chains:
        return 0
    sig = hashlib.sha1(json.dumps([sorted(x["agent_id"] for x in unl), chains]).encode()).hexdigest()[:12]
    sid = re.sub(r"[^A-Za-z0-9_.-]", "_", sid_raw)
    marker = os.path.join(state, "heartbeat-%s.sig" % sid)
    try:
        if open(marker).read().strip() == sig:
            return 0  # already nudged for exactly this state
    except FileNotFoundError:
        pass
    try:
        open(marker, "w").write(sig)
    except Exception:
        return 0  # cannot record the release, so do not block
    bits = []
    for x in unl[:5]:
        bits.append("LAND %s%s commit %s (%s)" % (x.get("type"), " #" + str(x["issue"]) if x.get("issue") else "",
                                                  x.get("commit"), x.get("description")))
    if chains:
        bits.append("DISPATCH a launchable chain from %s: %s" % (os.path.relpath(chains_file, root), "; ".join(chains[:3])))
    sys.stderr.write("LEAD HEARTBEAT (one-time for this state): no role is running, and there is work you can move. "
                     + " | ".join(bits) + ". QA the diff, land and gate it, or dispatch the next role; if you judge "
                     "none of it should move now, say why in one line and stop.\n")
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
