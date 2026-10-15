#!/usr/bin/env node
// inflight.mjs - reader for the lead's in-flight ledger (<root>/tmp/lead/inflight.jsonl).
//   node inflight.mjs            human summary: running / stalled / finished-not-landed
//   node inflight.mjs --json     machine form (used by lead-heartbeat-check)
//   node inflight.mjs --all      also list landed and finished-nothing-to-land
//   node inflight.mjs --session <id>   only rows THIS session dispatched (default: all sessions)
//                                      a row with no session_id never matches a --session filter
// The ledger is appended by hooks/lead-inflight-record.sh (PostToolUse Agent|Task + SubagentStop).
// <root> = $CLAUDE_PROJECT_DIR, else the current directory. Main branch = roles.config.json "mainBranch" (default main).
//
// LIVENESS comes from the agent's transcript mtime (~/.claude/projects/*/*/subagents/agent-<id>.jsonl),
// NOT from worktree commits or locks: a lane that is thinking or running a long gate has no new commit for
// an hour and is still alive. No transcript found => age of the dispatch.
// LANDED = the COMMIT sha from the role's handback is an ancestor of the main branch (a real git check, not a label).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const root = path.resolve(process.env.CLAUDE_PROJECT_DIR || process.cwd());
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(path.join(root, 'roles.config.json'), 'utf8')); } catch { /* no overlay: defaults */ }
const mainBranch = process.env.LEAD_MAIN_BRANCH || cfg.mainBranch || 'main';
const ledger = path.join(process.env.LEAD_LEDGER_DIR || path.join(root, 'tmp', 'lead'), 'inflight.jsonl');
const projectsDir = process.env.LEAD_PROJECTS_DIR || path.join(os.homedir(), '.claude', 'projects');
const STALE_MIN = Number(process.env.LEAD_STALE_MIN || 20);
const now = Date.now();
const argv = process.argv.slice(2);
const args = new Set(argv);
const si = argv.indexOf('--session');
const sessionFilter = si >= 0 ? (argv[si + 1] || '') : null; // '' (flag with no value) matches nothing: fail closed to "no rows"

function transcriptMtime(id) {
  if (!id) return null;
  try {
    for (const proj of fs.readdirSync(projectsDir)) {
      const pdir = path.join(projectsDir, proj);
      let subs;
      try { subs = fs.readdirSync(pdir); } catch { continue; }
      for (const s of subs) {
        const f = path.join(pdir, s, 'subagents', `agent-${id}.jsonl`);
        try { return fs.statSync(f).mtimeMs; } catch { /* next */ }
      }
    }
  } catch { /* no projects dir */ }
  return null;
}

function landed(sha) {
  if (!sha) return null;
  try {
    execFileSync('git', ['-C', root, 'merge-base', '--is-ancestor', sha, mainBranch], { stdio: 'ignore' });
    return true;
  } catch (e) {
    return e.status === 1 ? false : null; // 1 = not an ancestor; anything else = unknown sha
  }
}

const rows = new Map();
if (fs.existsSync(ledger)) {
  for (const ln of fs.readFileSync(ledger, 'utf8').split('\n')) {
    if (!ln.trim()) continue;
    let r; try { r = JSON.parse(ln); } catch { continue; }
    const key = r.agent_id || r.tool_use_id;
    if (!key) continue;
    if (r.ev === 'dispatch') {
      if (sessionFilter !== null && (!sessionFilter || r.session_id !== sessionFilter)) continue;
      rows.set(key, { ...r, done: null });
    } else if (r.ev === 'done' && rows.has(key)) rows.get(key).done = r;
  }
}

const out = { total: rows.size, running: [], stalled: [], finishedUnlanded: [], finishedNothingToLand: [], landed: [] };
for (const r of rows.values()) {
  const base = { agent_id: r.agent_id, type: r.subagent_type, issue: r.issue, description: r.description, dispatched: r.time };
  if (!r.done) {
    const m = transcriptMtime(r.agent_id) ?? Date.parse(r.time);
    const idleMin = Math.round((now - m) / 60000);
    (idleMin > STALE_MIN ? out.stalled : out.running).push({ ...base, idle_min: idleMin });
  } else {
    const l = landed(r.done.commit);
    const row = { ...base, commit: r.done.commit, branch: r.done.branch };
    if (!r.done.commit) out.finishedNothingToLand.push(row);
    else if (l === true) out.landed.push(row);
    else out.finishedUnlanded.push(row);
  }
}

if (args.has('--json')) {
  console.log(JSON.stringify(out));
  process.exit(0);
}
const fmt = (x) => `${x.type}${x.issue ? ` #${x.issue}` : ''} - ${x.description}`;
console.log(`running (${out.running.length})`);
for (const x of out.running) console.log(`  ${x.agent_id}  ${fmt(x)}  [transcript idle ${x.idle_min}m]`);
console.log(`stalled > ${STALE_MIN}m idle (${out.stalled.length}) - check the transcript before re-dispatching`);
for (const x of out.stalled) console.log(`  ${x.agent_id}  ${fmt(x)}  [transcript idle ${x.idle_min}m]`);
console.log(`finished, NOT landed (${out.finishedUnlanded.length})`);
for (const x of out.finishedUnlanded) console.log(`  ${x.agent_id}  ${fmt(x)}  commit ${x.commit}${x.branch ? ` on ${x.branch}` : ''}`);
if (args.has('--all')) {
  console.log(`finished, nothing to land (${out.finishedNothingToLand.length})`);
  for (const x of out.finishedNothingToLand) console.log(`  ${x.agent_id}  ${fmt(x)}`);
  console.log(`landed (${out.landed.length})`);
  for (const x of out.landed) console.log(`  ${x.agent_id}  ${fmt(x)}  commit ${x.commit}`);
}
if (!rows.size) console.log(`(ledger empty or missing: ${ledger})`);
