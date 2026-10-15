#!/usr/bin/env node
/**
 * roles-pulse: is the role system being used, is it working, what does it cost?
 *
 *   node roles-pulse.mjs [--since YYYY-MM-DD] [--json] [--project <substring>]
 *
 * Reads Claude Code's own transcripts (read-only) and prints one row per role run:
 * model, tool calls, handback blocks, the GATE line it handed back, rounds per issue, cost.
 *
 * Sources
 *   subagent runs  ~/.claude/projects/<project>/<session>/subagents/agent-<id>.jsonl
 *                  + agent-<id>.meta.json {agentType, description}; kept if agentType starts ROLE_PREFIX
 *   headless runs  ~/.claude/projects/<project>/<uuid>.jsonl carrying "agentSetting":"<role>"
 *                  (claude -p --agent role-x). No handback tool there, so GATE comes from the final text.
 *
 * <project> defaults to this checkout: Claude names the folder after the path with "/" and "."
 * turned into "-", and worktree sessions get their own folders that start with the same prefix.
 *
 * Cost is a FLOOR: transcripts under-record output tokens (one run's own report said $11.52
 * where this computes $9.11), and every cache write is priced at the 5-minute rate.
 * Prices are USD per million tokens; update PRICES when they change.
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

// USD per MTok: [input, output, cache_read, cache_write_5m].
// A model missing here makes that run's cost null and lists it in unpriced_models, so a gap never hides.
const PRICES = {
  'claude-opus-5-5': [4.0, 20.0, 0.2, 5.0],
  'claude-opus-5': [5.0, 25.0, 0.5, 6.25],
  'claude-opus-4-8': [5.0, 25.0, 0.5, 6.25],
  'claude-sonnet-5': [2.0, 10.0, 0.2, 2.5],
  'claude-sonnet-5-5': [2.0, 10.0, 0.2, 2.5],
  'claude-fable-5': [10.0, 50.0, 1.0, 12.5],
  'claude-fable-5-1': [10.0, 50.0, 0.25, 12.5],
  'claude-haiku-4-5-20251001': [1.0, 5.0, 0.1, 1.25],
};

const DEFAULT_SINCE = new Date(Date.now() - 7 * 864e5).toISOString().slice(0, 10);
// Prefix: $ROLE_PREFIX, else "<prefix>-" from roles.config.json in $CLAUDE_PROJECT_DIR / the cwd, else "role-".
function configPrefix() {
  try {
    const c = JSON.parse(fs.readFileSync(path.join(process.env.CLAUDE_PROJECT_DIR || process.cwd(), 'roles.config.json'), 'utf8'));
    return typeof c.prefix === 'string' && c.prefix ? `${c.prefix}-` : null;
  } catch { return null; }
}
const ROLE_PREFIX = process.env.ROLE_PREFIX || configPrefix() || 'role-';
const projectKey = (dir) => dir.replace(/[/.]/g, '-');

export function parseArgs(argv) {
  const out = { since: DEFAULT_SINCE, json: false, project: projectKey(process.cwd()), root: path.join(os.homedir(), '.claude', 'projects') };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--json') out.json = true;
    else if (a === '--since') out.since = argv[++i];
    else if (a.startsWith('--since=')) out.since = a.slice(8);
    else if (a === '--root') out.root = argv[++i];
    else if (a === '--project') out.project = argv[++i];
    else if (a === '-h' || a === '--help') {
      console.log('usage: node roles-pulse.mjs [--since YYYY-MM-DD] [--json] [--project <substring>]   (ROLE_PREFIX env, else the prefix in roles.config.json, else role-)');
      process.exit(0);
    } else {
      console.error(`unknown argument: ${a}`);
      process.exit(2);
    }
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(out.since || '')) {
    console.error('--since needs YYYY-MM-DD');
    process.exit(2);
  }
  return out;
}

function readLines(file) {
  const rows = [];
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    if (!line) continue;
    try { rows.push(JSON.parse(line)); } catch { /* torn line: skip */ }
  }
  return rows;
}

function textOf(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.map((c) => (typeof c === 'string' ? c : c?.text || '')).join('\n');
}

// Issue number: description first, then "issue #N" in the opening prompt, then the
// most-mentioned #N in it (ties go to the first mentioned).
function pickIssue(description, prompt) {
  const d = (description || '').match(/#(\d{3,5})/);
  if (d) return Number(d[1]);
  const named = (prompt || '').match(/\bissues?\s+#(\d{3,5})/i);
  if (named) return Number(named[1]);
  const counts = new Map();
  for (const m of (prompt || '').matchAll(/#(\d{3,5})\b/g)) counts.set(m[1], (counts.get(m[1]) || 0) + 1);
  let best = null;
  for (const [k, v] of counts) if (best === null || v > counts.get(best)) best = k;
  return best === null ? null : Number(best);
}

function analyse(rows, { role, kind, id, description, file }) {
  const seen = new Set();
  const usage = { input: 0, output: 0, cache_read: 0, cache_write: 0 };
  const perModel = new Map();
  const toolIds = new Set();
  let handbackMsg = null;
  let lastText = '';
  let blocks = 0;
  let first = null;
  let last = null;
  let firstPrompt = '';

  for (const r of rows) {
    if (r.timestamp) {
      if (!first || r.timestamp < first) first = r.timestamp;
      if (!last || r.timestamp > last) last = r.timestamp;
    }
    if (!firstPrompt) {
      if (r.type === 'user' && !r.isMeta) firstPrompt = textOf(r.message?.content);
      else if (r.type === 'queue-operation' && r.operation === 'enqueue') firstPrompt = textOf(r.content);
    }
    if (r.type === 'user' && r.isMeta && textOf(r.message?.content).includes('HANDBACK BLOCKED')) blocks++;
    if (r.type !== 'assistant' || !r.message) continue;
    const m = r.message;
    const blocksArr = Array.isArray(m.content) ? m.content : [];
    for (const c of blocksArr) {
      if (c.type === 'tool_use') {
        toolIds.add(c.id);
        if (c.name === 'SubagentHandback' && typeof c.input?.message === 'string') handbackMsg = c.input.message;
      }
    }
    const t = blocksArr.filter((c) => c.type === 'text').map((c) => c.text).join('\n');
    if (t) lastText = t;
    // assistant lines repeat once per content block: sum usage once per message.id
    if (m.id && m.usage && !seen.has(m.id)) {
      seen.add(m.id);
      const u = m.usage;
      const row = {
        input: u.input_tokens || 0,
        output: u.output_tokens || 0,
        cache_read: u.cache_read_input_tokens || 0,
        cache_write: u.cache_creation_input_tokens || 0,
      };
      for (const k of Object.keys(row)) usage[k] += row[k];
      const mk = m.model || 'unknown';
      const pm = perModel.get(mk) || { input: 0, output: 0, cache_read: 0, cache_write: 0 };
      for (const k of Object.keys(row)) pm[k] += row[k];
      perModel.set(mk, pm);
    }
  }

  let cost = 0;
  let unpriced = [];
  for (const [mk, u] of perModel) {
    const p = PRICES[mk];
    if (!p) { unpriced.push(mk); continue; }
    cost += (u.input * p[0] + u.output * p[1] + u.cache_read * p[2] + u.cache_write * p[3]) / 1e6;
  }

  const hb = handbackMsg ?? lastText;
  const lines = hb.split('\n').map((s) => s.trim().replace(/^[`*\s]+/, ''));
  const gateLines = lines.filter((s) => /^GATE(-SKIPPED)?:/.test(s));
  const gateSkipped = gateLines.some((s) => s.startsWith('GATE-SKIPPED:'));
  const passLines = gateLines.filter((s) => s.startsWith('GATE:') && /->\s*PASS/.test(s));
  const gate = gateLines.length === 0 ? null : gateSkipped ? (passLines.length ? 'PASS+SKIP' : 'SKIPPED') : passLines.length === gateLines.length ? 'PASS' : 'FAIL?';
  const minutes = first && last ? Math.round((Date.parse(last) - Date.parse(first)) / 60000) : null;

  return {
    role,
    kind,
    id,
    issue: pickIssue(description, firstPrompt),
    description: description || firstPrompt.replace(/^TOOL_BOUND:\d+\s*/, '').split('\n').find(Boolean)?.slice(0, 70) || '',
    model: [...perModel.keys()].join(','),
    started: first,
    ended: last,
    minutes,
    tool_calls: toolIds.size,
    handback_blocks: blocks,
    gate,
    screenshots: /(^|\n)[`*\s]*SCREENSHOTS:/.test(hb),
    handback_via: handbackMsg !== null ? 'SubagentHandback' : 'final-text',
    messages: seen.size,
    tokens: usage,
    cost_usd_floor: unpriced.length ? null : Number(cost.toFixed(2)),
    unpriced_models: unpriced,
    file,
  };
}

export function collect(root, project) {
  const runs = [];
  if (!fs.existsSync(root)) return runs;
  for (const proj of fs.readdirSync(root).filter((d) => d.startsWith(project) || d.includes(project))) {
    const pdir = path.join(root, proj);
    for (const entry of fs.readdirSync(pdir)) {
      const full = path.join(pdir, entry);
      if (entry.endsWith('.jsonl')) {
        // headless role session (claude -p --agent role-x)
        const head = fs.readFileSync(full, 'utf8');
        const m = head.match(new RegExp(`"agentSetting":"(${ROLE_PREFIX}[a-z-]+)"`));
        if (!m) continue;
        runs.push(analyse(readLines(full), { role: m[1], kind: 'headless', id: entry.replace('.jsonl', '').slice(0, 8), description: '', file: full }));
      } else if (fs.statSync(full).isDirectory()) {
        const sub = path.join(full, 'subagents');
        if (!fs.existsSync(sub)) continue;
        for (const f of fs.readdirSync(sub).filter((x) => x.endsWith('.meta.json'))) {
          let meta;
          try { meta = JSON.parse(fs.readFileSync(path.join(sub, f), 'utf8')); } catch { continue; }
          if (!String(meta.agentType || '').startsWith(ROLE_PREFIX)) continue;
          const jf = path.join(sub, f.replace('.meta.json', '.jsonl'));
          if (!fs.existsSync(jf)) continue;
          runs.push(analyse(readLines(jf), { role: meta.agentType, kind: 'subagent', id: f.replace(/^agent-|\.meta\.json$/g, '').slice(0, 8), description: meta.description || '', file: jf }));
        }
      }
    }
  }
  return runs;
}

export function summarise(runs) {
  runs.sort((a, b) => String(a.started).localeCompare(String(b.started)));
  // rounds: runs of the same role on the same issue, numbered in start order
  const seen = new Map();
  const perIssueRole = new Map();
  for (const r of runs) {
    const k = `${r.issue}|${r.role}`;
    perIssueRole.set(k, (perIssueRole.get(k) || 0) + 1);
  }
  for (const r of runs) {
    const k = `${r.issue}|${r.role}`;
    seen.set(k, (seen.get(k) || 0) + 1);
    r.round = r.issue ? seen.get(k) : null;
    r.rounds_per_issue = r.issue ? perIssueRole.get(k) : null;
  }
  const roles = {};
  for (const r of runs) {
    const t = (roles[r.role] ||= { runs: 0, headless: 0, cost_usd_floor: 0, tool_calls: 0, handback_blocks: 0, minutes: 0, gate_skipped: 0 });
    t.runs++;
    if (r.kind === 'headless') t.headless++;
    t.cost_usd_floor = Number((t.cost_usd_floor + (r.cost_usd_floor || 0)).toFixed(2));
    t.tool_calls += r.tool_calls;
    t.handback_blocks += r.handback_blocks;
    t.minutes += r.minutes || 0;
    if (r.gate === 'SKIPPED' || r.gate === 'PASS+SKIP') t.gate_skipped++;
  }
  const issues = {};
  for (const r of runs) {
    if (!r.issue) continue;
    const t = (issues[r.issue] ||= { runs: 0, cost_usd_floor: 0, by_role: {} });
    t.runs++;
    t.cost_usd_floor = Number((t.cost_usd_floor + (r.cost_usd_floor || 0)).toFixed(2));
    t.by_role[r.role] = (t.by_role[r.role] || 0) + 1;
  }
  return { roles, issues };
}

function pad(s, n) { s = String(s ?? '-'); return s.length >= n ? s.slice(0, n) : s + ' '.repeat(n - s.length); }

function printTable(runs, sum, since) {
  console.log(`roles-pulse since ${since}: ${runs.length} runs. Cost is a FLOOR (transcripts under-record output; cache writes priced at 5m).`);
  console.log('');
  console.log(['role', 'kind', 'id', 'issue', 'rnd', 'model', 'start (UTC)', 'min', 'tools', 'blk', 'gate', 'shots', 'cost$'].map((h, i) => pad(h, [11, 9, 9, 6, 4, 16, 17, 5, 6, 4, 9, 6, 8][i])).join(' '));
  for (const r of runs) {
    console.log([
      r.role, r.kind, r.id, r.issue ? `#${r.issue}` : '-', r.round ? `${r.round}/${r.rounds_per_issue}` : '-',
      r.model.replace('claude-', ''), (r.started || '').slice(0, 16).replace('T', ' '), r.minutes, r.tool_calls,
      r.handback_blocks, r.gate, r.screenshots ? 'yes' : '-', r.cost_usd_floor === null ? 'n/a' : r.cost_usd_floor.toFixed(2),
    ].map((v, i) => pad(v, [11, 9, 9, 6, 4, 16, 17, 5, 6, 4, 9, 6, 8][i])).join(' '));
  }
  console.log('');
  console.log('per role');
  console.log(['role', 'runs', 'headless', 'cost$', 'tools', 'blocks', 'min', 'gate-skipped'].map((h, i) => pad(h, [11, 5, 9, 8, 7, 7, 6, 12][i])).join(' '));
  for (const [role, t] of Object.entries(sum.roles)) {
    console.log([role, t.runs, t.headless, t.cost_usd_floor.toFixed(2), t.tool_calls, t.handback_blocks, t.minutes, t.gate_skipped].map((v, i) => pad(v, [11, 5, 9, 8, 7, 7, 6, 12][i])).join(' '));
  }
  console.log('');
  console.log('per issue (role runs = rework rounds + 1)');
  for (const [n, t] of Object.entries(sum.issues).sort((a, b) => b[1].cost_usd_floor - a[1].cost_usd_floor)) {
    console.log(`  #${pad(n, 5)} ${pad(t.runs + ' runs', 8)} $${t.cost_usd_floor.toFixed(2).padStart(7)}  ${Object.entries(t.by_role).map(([k, v]) => `${k}x${v}`).join(' ')}`);
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const runs = collect(args.root, args.project).filter((r) => r.started && r.started.slice(0, 10) >= args.since);
  const sum = summarise(runs);
  if (args.json) {
    console.log(JSON.stringify({ since: args.since, cost_note: 'floor', runs: runs.map(({ file, ...r }) => r), roles: sum.roles, issues: sum.issues }, null, 2));
  } else printTable(runs, sum, args.since);
}

if (import.meta.url === `file://${process.argv[1]}`) main();
