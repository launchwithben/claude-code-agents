#!/usr/bin/env node
// pm-delta.mjs - what changed on the GitHub board since the PM role's last run.
//   node pm-delta.mjs            print issues updated since the cursor; full detail goes to <root>/tmp/pm/delta.json
//   node pm-delta.mjs --ack      move the cursor to now (run ONLY after the board writes landed)
//   node pm-delta.mjs --ack --at 2026-01-31T10:00:00Z   move it to a given time
//   node pm-delta.mjs --json     the delta as JSON on stdout
// Cursor file: roles.config.json "pm.cursor" (default docs/pm/state.json), shape {"cursor": "<ISO time>"}.
// Repo: roles.config.json "pm.repo" ("owner/name"), else `gh repo view`. Board specifics (status fields, labels
// that mean "owner's ruling") are NOT here: point "pm.deltaCommand" at your own script if you need them.
// Uses only `gh api` (REST), so it spends no GraphQL budget. <root> = $CLAUDE_PROJECT_DIR, else the cwd.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const root = path.resolve(process.env.CLAUDE_PROJECT_DIR || process.cwd());
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(path.join(root, 'roles.config.json'), 'utf8')); } catch { /* defaults */ }
const pm = cfg.pm || {};
const cursorFile = path.join(root, pm.cursor || 'docs/pm/state.json');
const argv = process.argv.slice(2);
const has = (f) => argv.includes(f);
const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };

function gh(args) { return execFileSync('gh', args, { cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }); }
function readCursor() {
  try { return JSON.parse(fs.readFileSync(cursorFile, 'utf8')).cursor || null; } catch { return null; }
}

if (has('--ack')) {
  const at = val('--at') || new Date().toISOString().replace(/\.\d+Z$/, 'Z');
  if (Number.isNaN(Date.parse(at))) { console.error(`--at needs an ISO time, got: ${at}`); process.exit(2); }
  fs.mkdirSync(path.dirname(cursorFile), { recursive: true });
  fs.writeFileSync(cursorFile, JSON.stringify({ cursor: at }, null, 2) + '\n');
  console.log(`CURSOR: ${at} -> ACKED (${path.relative(root, cursorFile)})`);
  process.exit(0);
}

let repo = pm.repo;
if (!repo) {
  try { repo = gh(['repo', 'view', '--json', 'nameWithOwner', '-q', '.nameWithOwner']).trim(); }
  catch { console.error('pm-delta: no "pm.repo" in roles.config.json and `gh repo view` failed'); process.exit(1); }
}
const cursor = readCursor();
const since = cursor || new Date(Date.now() - 14 * 864e5).toISOString().replace(/\.\d+Z$/, 'Z');
let issues;
try {
  issues = JSON.parse(gh(['api', '--paginate', `repos/${repo}/issues?state=all&sort=updated&direction=desc&per_page=100&since=${since}`]));
} catch (e) { console.error(`pm-delta: gh api failed: ${String(e.message).split('\n')[0]}`); process.exit(1); }
const rows = issues.filter((i) => !i.pull_request).map((i) => ({
  number: i.number, title: i.title, state: i.state, updated_at: i.updated_at, comments: i.comments,
  labels: (i.labels || []).map((l) => (typeof l === 'string' ? l : l.name)),
}));
fs.mkdirSync(path.join(root, 'tmp', 'pm'), { recursive: true });
fs.writeFileSync(path.join(root, 'tmp', 'pm', 'delta.json'), JSON.stringify({ repo, since, rows }, null, 2) + '\n');
if (has('--json')) { console.log(JSON.stringify({ repo, since, rows })); process.exit(0); }
console.log(`board delta for ${repo} since ${since}${cursor ? '' : ' (no cursor yet: first run, last 14 days)'}: ${rows.length} issue(s)`);
for (const r of rows) console.log(`  #${r.number} [${r.state}] ${r.title}  (${r.labels.join(', ') || 'no labels'}; ${r.comments} comments; updated ${r.updated_at})`);
if (!rows.length) console.log('  (nothing changed: skip to chains)');
console.log('details: tmp/pm/delta.json   when the board writes have landed: node pm-delta.mjs --ack');
