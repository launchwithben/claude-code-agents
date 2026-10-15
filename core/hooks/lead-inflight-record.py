#!/usr/bin/env python3
"""lead-inflight-record.py <dispatch|done> - writes the lead's in-flight ledger (<root>/tmp/lead/inflight.jsonl).

  dispatch  PostToolUse on Agent|Task: appends {ev,time,agent_id,tool_use_id,subagent_type,description,issue,session_id}
  done      SubagentStop: appends {ev:"done",agent_id,agent_type,commit,branch} IF that agent_id was dispatched
            (an unknown agent writes nothing, so registering this hook for every session is harmless).
The ledger is written by a hook, not by the lead's memory, so it survives compaction. Reader: bin/inflight.mjs.
Never blocks: always exits 0.
"""
import datetime
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _kit  # noqa: E402


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "dispatch"
    raw = sys.stdin.read()
    if not raw.strip():
        return
    p = json.loads(raw)
    root = _kit.find_root(p)
    d = os.environ.get("LEAD_LEDGER_DIR") or os.path.join(root, "tmp", "lead")
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    os.makedirs(d, exist_ok=True)
    f = os.path.join(d, "inflight.jsonl")
    if mode == "dispatch":
        ti = p.get("tool_input") or {}
        tr = p.get("tool_response")
        trs = tr if isinstance(tr, str) else json.dumps(tr or "")
        aid = ""
        if isinstance(tr, dict):
            aid = str(tr.get("agentId") or tr.get("agent_id") or "")
        if not aid:
            m = re.search(r'agent_?[iI]d["\s:=]+([A-Za-z0-9_-]{6,})', trs)
            aid = m.group(1) if m else ""
        prompt = str(ti.get("prompt") or "")
        m = re.search(r"#(\d{2,5})\b", prompt) or re.search(r"/issues/(\d{2,5})\b", prompt)
        rec = {"ev": "dispatch", "time": now, "agent_id": aid, "tool_use_id": p.get("tool_use_id") or "",
               "subagent_type": ti.get("subagent_type") or "general-purpose",
               "description": str(ti.get("description") or "")[:120],
               "issue": int(m.group(1)) if m else None, "session_id": p.get("session_id") or ""}
    else:
        aid = str(p.get("agent_id") or "")
        if not aid or not os.path.exists(f):
            return
        known = False
        for ln in open(f):
            try:
                if json.loads(ln).get("agent_id") == aid:
                    known = True
                    break
            except Exception:
                pass
        if not known:
            return
        msg = str(p.get("last_assistant_message") or "")
        c = re.search(r"^\s*COMMIT:\s*([0-9a-f]{7,40})(?:\s+on branch\s+(\S+))?", msg, re.M | re.I)
        rec = {"ev": "done", "time": now, "agent_id": aid, "agent_type": p.get("agent_type") or "",
               "commit": c.group(1) if c else None, "branch": c.group(2) if c and c.group(2) else None}
    with open(f, "a") as fh:
        fh.write(json.dumps(rec) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
