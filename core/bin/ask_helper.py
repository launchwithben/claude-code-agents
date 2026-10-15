#!/usr/bin/env python3
"""ask_helper.py - JSON plumbing for ask.sh (no jq dependency).

    ask_helper.py list <agents-dir> <prefix>           one `name<TAB>description` line per role
    ask_helper.py parse < claude-json                  prints: result text, then (stderr-free) fields via --field
    ask_helper.py field <name> < claude-json           one top-level field (result, session_id, total_cost_usd, num_turns)
    ask_helper.py log <logfile> <role> <rc> <secs> <brief> < claude-json     append one JSON line
    ask_helper.py recover <session_id>                 last assistant message carrying a handback line, from the transcript
"""
import datetime
import glob
import json
import os
import re
import sys

HANDBACK = re.compile(r"^(ANSWER|COMMIT|GATE|GATE-SKIPPED|OUT-OF-SCOPE|CURSOR|SCREENSHOTS|CONCEPT-NOTE):", re.M)


def read_json():
    try:
        return json.loads(sys.stdin.read())
    except Exception:
        return {}


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "list":
        for f in sorted(glob.glob(os.path.join(argv[2], argv[3] + "-*.md"))):
            txt = open(f).read()
            m = re.search(r"^description:\s*>-?\s*\n((?:[ \t]+.*\n?)+)", txt, re.M) or re.search(r"^description:\s*(.+)$", txt, re.M)
            d = re.sub(r"\s+", " ", m.group(1)).strip() if m else ""
            print("%s\t%s" % (os.path.basename(f)[:-3], d))
    elif cmd == "field":
        v = read_json().get(argv[2])
        print("" if v is None else v)
    elif cmd == "log":
        o = read_json()
        rec = {"ts": datetime.datetime.now().astimezone().isoformat(timespec="seconds"), "role": argv[3], "rc": int(argv[4]),
               "secs": int(argv[5]), "cost_usd": o.get("total_cost_usd"), "turns": o.get("num_turns"), "brief": argv[6][:200]}
        os.makedirs(os.path.dirname(argv[2]), exist_ok=True)
        with open(argv[2], "a") as fh:
            fh.write(json.dumps(rec) + "\n")
    elif cmd == "recover":
        last = ""
        for f in glob.glob(os.path.join(os.path.expanduser("~"), ".claude", "projects", "*", argv[2] + ".jsonl")):
            for ln in open(f):
                try:
                    r = json.loads(ln)
                except Exception:
                    continue
                if r.get("type") != "assistant":
                    continue
                t = "\n".join(c.get("text", "") for c in ((r.get("message") or {}).get("content") or [])
                              if isinstance(c, dict) and c.get("type") == "text")
                if HANDBACK.search(t):
                    last = t
            if last:
                break
        print(last)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception:
        sys.exit(0)
