#!/usr/bin/env bash
# Fixtures for lead-inflight-record (the writer) and bin/inflight.mjs (the reader).
#   bash core/hooks/lead-inflight.test.sh
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/_testlib.sh"
t_syntax "$here/lead-inflight-record.sh" "$here/lead-inflight-record.py"
command -v node >/dev/null 2>&1 || { echo "  skip node is not installed (the lead hooks need node 18+)"; echo "ALL PASS"; exit 0; }
W="$here/lead-inflight-record.sh"
READER="$here/../bin/inflight.mjs"
t_proj '{"prefix":"acme","mainBranch":"main"}'
export LEAD_PROJECTS_DIR="$T_ROOT/projects"; mkdir -p "$LEAD_PROJECTS_DIR"
L="$T_ROOT/tmp/lead/inflight.jsonl"
disp() { # <session> <agent_id> <prompt> [type]
  python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PostToolUse","tool_name":"Agent","session_id":sys.argv[1],"tool_use_id":"tu_"+sys.argv[2],"tool_input":{"subagent_type":sys.argv[4],"description":"desc","prompt":sys.argv[3]},"tool_response":{"agentId":sys.argv[2]}}))' "$1" "$2" "$3" "${4:-acme-dev}" | bash "$W" dispatch
}
done_() { # <agent_id> <message>
  python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"SubagentStop","agent_id":sys.argv[1],"agent_type":"acme-dev","last_assistant_message":sys.argv[2]}))' "$1" "$2" | bash "$W" done
}
echo "-- writer"
disp s1 agentaaaa1 "Do #42 now: fix the thing"
t_eq 1 "$(wc -l < "$L" | tr -d ' ')" "dispatch appends one row"
t_eq 42 "$(python3 -c 'import json;print(json.loads(open("'"$L"'").readline())["issue"])')" "issue number is read from the prompt"
t_eq agentaaaa1 "$(python3 -c 'import json;print(json.loads(open("'"$L"'").readline())["agent_id"])')" "agent id comes from tool_response"
done_ ghost999 $'COMMIT: abc1234 on branch x'
t_eq 1 "$(wc -l < "$L" | tr -d ' ')" "done for an agent that was never dispatched writes nothing"
printf '%s\n' '{"hook_event_name":"PostToolUse","session_id":"s1","tool_input":{"prompt":"x"},"tool_response":"agentId: textid1234 (done)"}' | bash "$W" dispatch
t_eq textid1234 "$(python3 -c 'import json;print(json.loads(open("'"$L"'").readlines()[1])["agent_id"])')" "agent id is scraped from a string response"
done_ agentaaaa1 $'all good\nCOMMIT: abc1234 on branch worktree-x'
t_eq abc1234 "$(python3 -c 'import json;print(json.loads(open("'"$L"'").readlines()[2])["commit"])')" "done row carries the COMMIT sha"
printf 'garbage' | bash "$W" dispatch >/dev/null 2>&1; t_eq 0 "$?" "garbage stdin exits 0"
printf '' | bash "$W" done >/dev/null 2>&1;            t_eq 0 "$?" "empty stdin exits 0"
printf '{"tool_input":' | bash "$W" dispatch >/dev/null 2>&1; t_eq 0 "$?" "truncated JSON exits 0"

echo "-- reader"
git init -q -b main "$T_ROOT" 2>/dev/null
git -C "$T_ROOT" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
MAINSHA="$(git -C "$T_ROOT" rev-parse HEAD)"
git -C "$T_ROOT" checkout -q -b lane
git -C "$T_ROOT" -c user.name=t -c user.email=t@t commit -q --allow-empty -m lane-work
LANESHA="$(git -C "$T_ROOT" rev-parse HEAD)"
git -C "$T_ROOT" checkout -q main
: > "$L"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; OLD="$(python3 -c 'import datetime;print((datetime.datetime.utcnow()-datetime.timedelta(minutes=90)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
row() { printf '{"ev":"dispatch","time":"%s","agent_id":"%s","subagent_type":"acme-dev","description":"d","issue":7,"session_id":"%s"}\n' "$1" "$2" "$3" >> "$L"; }
fin() { printf '{"ev":"done","time":"%s","agent_id":"%s","commit":"%s","branch":"b"}\n' "$NOW" "$1" "$2" >> "$L"; }
row "$NOW" runner s1
row "$OLD" stalled s1
row "$NOW" unlanded s1;  fin unlanded "$LANESHA"
row "$NOW" landed s1;    fin landed "$MAINSHA"
row "$NOW" nocommit s1;  printf '{"ev":"done","time":"%s","agent_id":"nocommit","commit":null,"branch":null}\n' "$NOW" >> "$L"
row "$NOW" other s2
J="$(node "$READER" --json --session s1)"
jf() { python3 -c 'import json,sys;d=json.loads(sys.argv[1]);print(len(d[sys.argv[2]]))' "$J" "$1"; }
t_eq 1 "$(jf running)" "a fresh dispatch with no transcript counts as running"
t_eq 1 "$(jf stalled)" "a dispatch idle for 90 minutes is stalled"
t_eq 1 "$(jf finishedUnlanded)" "a finished sha NOT on main is finished-unlanded"
t_eq 1 "$(jf landed)" "a finished sha that is an ancestor of main is landed"
t_eq 1 "$(jf finishedNothingToLand)" "a finished row with no commit has nothing to land"
t_eq 5 "$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["total"])' "$J")" "the session filter drops the other session"
# liveness is the TRANSCRIPT mtime, not the dispatch time: a fresh transcript rescues an old dispatch
mkdir -p "$LEAD_PROJECTS_DIR/p/sess/subagents"; : > "$LEAD_PROJECTS_DIR/p/sess/subagents/agent-stalled.jsonl"
J="$(node "$READER" --json --session s1)"
t_eq 2 "$(jf running)" "a fresh subagent transcript makes an old dispatch running again"
t_eq 0 "$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["total"])' "$(node "$READER" --json --session '')")" "an empty --session matches nothing"
node "$READER" >/dev/null 2>&1; t_eq 0 "$?" "human summary runs"
t_done
