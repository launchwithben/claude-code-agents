# claude-code-agents

**Turn one Claude Code chat into a team of specialists.**

> **Status: Active.** Maintained by [Launch With Ben](https://launchwithben.com). See [MAINTENANCE.md](MAINTENANCE.md) for what that means, how to hear about updates, and what happens if it is ever sunset. Changes are in [CHANGELOG.md](CHANGELOG.md). Current version: **0.5.0**.

A lead, a project manager, a developer, a UI builder and a concept designer (plus, for projects that design in Figma, a designer that owns the design file), each with its own scope, its own rules and (for the roles that edit code) its own copy of the repo. You talk to the lead. It scopes the work, files one issue per unit, sends every job to the right specialist in parallel, reads the diff that comes back and merges it. A role cannot hand back without showing its check result, or the reason it had none.

No extra windows and no extra subscriptions: the roles are subagents of the Claude Code you already run.

```
you ──► lead (the main chat) ──► dev      (scripts, data, config)       ──┐
        keeps an in-flight   ├─► ui       (components, styles)            ├─► lead reviews the diff ──► merge
        ledger, never types  ├─► concept  ("show me 3 ways")              │
                             └─► pm       (board delta -> ready chains) ──┘
```

**One master copy.** This repo is the kit; your project keeps only a small *overlay* (`roles.config.json`, optionally a territory file and a skills file). An improvement lands here once, and every project gets it with `git pull` and a re-install.

Written up in full at **launchwithben.com/notes/claude-code-agents** (the post explains why each part exists and what it cost to run for real).

## What's in the box

| Part | What it does |
|---|---|
| `core/templates/agents/` | The roles: `lead` (the main-session seat), `pm`, `dev`, `ui`, `concept`, `design` (opt-in; needs `design.source: "figma"`), plus any extra roles your overlay declares. Rendered with your prefix, gate and hook paths. |
| `core/hooks/role-handback-check` | Blocks a role from finishing until its report has the evidence its contract names (`GATE: ... -> PASS`, `SCREENSHOTS:`, `CURSOR:` ...) or an explicit `GATE-SKIPPED: <reason>`. Contracts per role come from the overlay. It checks what the role REPORTS, not that the command ran. |
| `core/hooks/role-territory-guard` | A file maps paths to the role that owns them; checked on every tool call. Judges writes **per target**, so running a script or copying a file out is not an edit of it. |
| `core/hooks/role-routing-guard` | The fallback for repos with no territory file: stops the lead sending an edit to a generic worker. Also refuses to dispatch the lead seat as a subagent. |
| `core/hooks/role-picker` | Typing a bare `@agent-<prefix>` shows the role menu; for the lead it prints how to start it as a chat. |
| `core/hooks/lead-inflight-record`, `lead-heartbeat-check`, `core/bin/inflight.mjs` | The lead's **in-flight ledger**: a hook records every dispatch and every handback; the reader says what is running, stalled, or finished-but-not-landed; a Stop hook nudges once when nothing is running and work can move. |
| `core/bin/build_skills.sh` | Generates a role's rules skill FROM your docs, so it cannot drift. `--check` fails when a committed skill is stale. |
| `core/bin/ask.sh` | Headless dispatch: `claude -p --agent`, a cost log, and it recovers a handback buried under later chatter. |
| `core/bin/pm-delta.mjs` | What changed on the GitHub board since the PM's last run (cursor file, REST only). |
| `core/bin/roles-pulse.mjs` | Reads Claude Code's own transcripts: are the roles used, do they hand back evidence, what do they cost? |
| `install.sh`, `kit-check` | Install into a project (merging, never overwriting, `settings.json`), `--check` for drift, and run every fixture. |

**Installing with an agent?** Point it at this repo and tell it to follow `AGENTS.md`.

## Install

Requirements: Claude Code, `bash`, `python3` (hooks and installer, stdlib only), `git`, `node` 18+ (the lead's ledger, the PM delta and the pulse script). The kit makes no network call and installs no package.

```bash
# 1. get the kit at a tag, next to your project (not inside it)
git clone --branch v0.5.0 https://github.com/launchwithben/claude-code-agents ../claude-code-agents

# 2. from your project root: write a starter overlay, then edit it
bash ../claude-code-agents/install.sh --init
$EDITOR roles.config.json            # at least "prefix" and "gate"

# 3. install
bash ../claude-code-agents/install.sh
```

The installer copies the core into `scripts/roles-kit/`, renders the agents into `.claude/agents/<prefix>-*.md`, writes the rules skills, builds your generated skills, **merges** the kit's hooks into `.claude/settings.json` (your own entries stay, in order; re-running replaces the kit's entries and never duplicates them) and records the version. It then prints what only you can do:

1. Fill in the starter `<prefix>-build-rules` / `<prefix>-design-rules` skills with your real rules, or generate them from your docs (see the skills file below). The starters are written once and never overwritten.
2. Restart Claude Code if `.claude/agents/` did not exist when the session started (`/clear` is not enough), and accept the workspace trust prompt (hooks in agent files only run in a trusted folder).
3. If `.claude/` is gitignored, `git add -f .claude/ scripts/roles-kit roles.config.json`, or a fresh worktree will not have the roles. Add `tmp/` to `.gitignore`: hooks keep ledgers there.
4. Add these to your project's gate, so the kit cannot rot silently:
   ```bash
   bash scripts/roles-kit/bin/kit-check
   bash scripts/roles-kit/bin/build_skills.sh --check     # only if you use generated skills
   ```

`"scope": "user"` installs into `~/.claude/` instead (agents, kit, settings) for every project on the machine; each project still carries its own overlay.

## Update

```bash
cd ../claude-code-agents && git fetch --tags && git checkout v0.5.0     # whichever tag you chose
cd - && bash ../claude-code-agents/install.sh --check                   # what would change
bash ../claude-code-agents/install.sh                                   # apply it
```

`install.sh --check` renders everything again in memory and compares it with what is on disk. It exits 1 and lists `MISSING`, `DRIFT` (a core file or rendered agent differs from the kit, including a local edit) or `STALE` (a file the new kit no longer ships), plus any generated skill that no longer matches its doc and any kit hook missing from `settings.json`. Pin the version in the overlay (`"kit": "0.5.0"`) and the installer refuses a checkout of a different version.

**Never edit installed core files in place** (`scripts/roles-kit/`, `.claude/agents/<prefix>-*.md`): the next install overwrites them. Change the overlay, or change the kit (see [MAINTENANCE.md](MAINTENANCE.md) for how a fix found in a project flows back here).

## The overlay: `roles.config.json`

Everything project-specific lives here. A full example is `examples/roles.config.json`.

| Key | Meaning |
|---|---|
| `prefix` | **Required.** Role prefix: agents are `<prefix>-lead`, `<prefix>-dev`... |
| `kit` | Pin: the install refuses another kit version. |
| `scope` | `project` (default) or `user`. |
| `roles` | Built-in roles to install; default all of `lead, pm, dev, ui, concept`; `design` is opt-in and refused unless `design.source` is `"figma"`. Either a list, or an object of per-role options: `{"pm": {"bodyFile": "docs/pm-procedure.md", "bodyMode": "append" or "replace"}}`. `append` (default) puts your text after the kit's body; `replace` keeps the frontmatter and swaps the body. An `extraRoles` entry named like a built-in is refused. |
| `extraRoles` | `[{name, description, model, color, worktree, skills, contract, body or bodyFile, routes}]`: extra roles rendered from a generic template. |
| `gate`, `extraGates` | THE check command (printed into every agent's contract) and any further ones. |
| `handback` | Evidence each role must report: `{"dev": ["gate"], "ui": ["gate","screenshots"], ...}`. Kinds: `gate`, `screenshots`, `concept-note`, `cursor`, `commit`, `line:NAME` (a `NAME: <value>` line) and `line:NAME~REGEX` (the text after `NAME:` must match the regex, e.g. `line:CURSOR~\\S+ -> ACKED` blocks a PM run that did not ack its cursor; a regex that does not compile is ignored). Keyed by suffix or full role name. |
| `territory` | Path of the territory file. **No key = the territory guard is off** and the regex routing guard is used. |
| `skills` | Path of the skills file for `build_skills.sh` (default `roles/skills.txt`). |
| `genericAgents` | Agent types the routing guard polices (default: `bulk-worker, general-purpose, full-stack-developer, haiku-worker, claude`). |
| `mainSessionRoles` | Roles that are chats, never subagents (default `["lead"]`). |
| `mainBranch`, `chains` | "Landed" means an ancestor of this branch; the file the PM writes ready chains to (default `docs/pm/chains.md`). |
| `lead` | `{focusCommand, shipStep, promoteRule, reportRule, routing, appRoute, hookScope, extraRulesFile}`: text and commands the lead's loop uses. `appRoute` (e.g. `/lead-agent`) is how the desktop app starts the lead, used verbatim by the picker, the roles menu and the routing guard. `hookScope` is `agent` (default: the heartbeat lives on the lead agent file, so it fires only in a `--agent <prefix>-lead` chat) or `project` (the recorder AND the heartbeat are registered in `settings.json` for every session, for desktop-app users who become the lead by invoking a command in a plain chat; safe, because both are keyed by `session_id` and a session that never dispatched is never nudged). `extraRulesFile` is appended to the lead rules as "Project rules". `reportRule` (one line) replaces the default owner report, an Executive brief. |
| `design` | `{source, file, signoff, exportsDir, callBudget, ledger, pageNaming}`: how the `ui` and `concept` roles design. `source` is `code` (default, no change) or `figma` (any design tool): then `file` is required, `concept` renders in the design file, `ui` builds only from a frame the owner signed off (`signoff`, default `true`; `false` = build from the frame the brief names), both read exported frames from `exportsDir` before spending design-tool quota, stay within `callBudget` design-tool calls and report the count, keep **one page per design round** in the design file (named by `pageNaming`, default `{surface} v{n}`, e.g. "Checkout v2": a new round duplicates the last approved page, a page holds only that version's frames, the review link is the page link, older versions are archived only with the owner's sign-off, never deleted), and `ui` ends with `FRAME-SYNC: <frame> needs sync \| none`. `ledger` is the path of an approvals ledger (template: [examples/design-ledger.md](examples/design-ledger.md)) with `KEEP` / `KILL` / `CHANGE-REQUESTED` rows and an ID per element; the roles read it first and hand back `LEDGER: changed <ids> \| kept <ids>` (add `line:FRAME-SYNC` or `line:LEDGER` to `handback` to have the Stop hook require them). With the opt-in `design` role installed (`"roles": [..., "design"]`, requires `source: "figma"`), `ui` routes `FRAME-SYNC` to it and the lead routes design-first work and `FRAME-SYNC` handbacks to it: see *The design role* below. Independent of all this, `ui` and `concept` always follow *Edit, do not redesign*: change only what the ask names, call out approved elements before touching them, return a before/after of the same page and a changed/kept list. |
| `pm` | `{repo, cursor, readyLabel, readFirst, rules, deltaCommand, ackCommand, paths}`: board specifics. Point `deltaCommand` at your own script if you need status fields. |

**Territory file** (`roles/territory.txt`): `<role> <edit|all> <path>`, first match wins. `edit` = anyone may read, only the owner may change; `all` = only the owner may even read, search or be briefed about it; role `-` = owned by nobody (the lead keeps it); `re:<regex>` for patterns. What counts as a write is judged **per target**: a redirect target, a `tee`/`cp`/`mv`/`ln` destination, `rm`/`touch`/`mkdir` arguments, a `sed -i` file, a path an interpreter opens for writing. A brief to an agent is denied only when none of the territories it names belongs to the dispatched agent. Override when you ask for hands-on work: `touch tmp/role-override` (30 minutes).

**Skills file** (`roles/skills.txt`), one line per skill: `name | description | path/to/doc.md#Heading prefix ; other.md#Heading [| key: value ; key: value]`. The optional 4th column declares more frontmatter, written after `description:` (for example `user-invocable: true`). `build_skills.sh` writes `.claude/skills/<name>/SKILL.md` from those `## ` sections; `--check` fails on drift. A skill over about 900 words prints a `WARNING` (it is preloaded on every dispatch; `ROLE_KIT_SKILL_MAX_WORDS` changes the threshold; never an error). A generated skill replaces the starter of the same name.

## The design role

For projects whose design lives in a design tool (`design.source: "figma"`), add `design` to `roles`. The design file is the source of truth for design: a change is cheap there and expensive in code, so design changes happen in the file first, then development builds from them. The role installs as `<prefix>-design` (sonnet, own worktree for exported PNGs) and is refused with a clear message if `design.source` is not `"figma"`.

| It does | How |
|---|---|
| Keeps the design file current | the design system (variables, text styles, components) and the section, page and component frames; every value bound to a token; a new component only when a pattern is used 2 or more times |
| Designs first | one new page per round, named by `design.pageNaming`, before anything is built |
| Scales the owner's involvement with weight | **light** (a small clear-scope change, or one requested by another agent): does it, hands back, notifies the requester. **heavy** (a new pattern or page, an element the ledger marks KEEP, a brand or look change, anything the owner has not seen): prepares the frame and waits for sign-off, relayed by the lead (`design.signoff` as before) |
| Closes the loop | on `FRAME-SYNC: <frame> needs sync` from `ui` or dev it updates the file to match what shipped, exports the PNG to `design.exportsDir` and replies done |
| Respects the shared quota | reads exports first, one screenshot per deliverable, stays within `design.callBudget`, reports calls used |
| Never | writes product code (the builder never edits the design file unless the brief says so) |

Handback (default contract, enforced by the Stop hook): `FRAMES:`, `EXPORTS:`, `CALLS:`, `REQUESTER: <role or agent> notified | none`, `OWNER-SIGNOFF: needed | not needed (<why>)`, plus `LEDGER: changed <ids> | kept <ids>` when `design.ledger` is set (add `line:LEDGER` to `handback.design` to have the hook require it). Without the role installed, `ui` and the lead render exactly as before.

## Use it

Talk to the lead. Start it as the main chat: `claude --agent <prefix>-lead` (CLI), or in the desktop app open a chat and run `/<prefix>-lead-rules` (or your `lead.appRoute`). The lead is a seat you sit in, never a subagent: the picker and the routing guard both say so. The full loop, modes and costs are in [docs/lead.md](docs/lead.md).

Without the lead, from any chat:

```
/roles                                   # menu
@agent-<prefix>-ui add a monthly/yearly toggle to the pricing table
Have <prefix>-dev fix the failing date test and add a regression case.
bash scripts/roles-kit/bin/ask.sh dev "fix #12; commit, report, STOP"     # headless
```

A follow-up on the same work goes to the **same** agent (SendMessage) so it keeps its context. A role does one or two tasks, then a fresh one starts: context grows the bill faster than linearly.

## Check it's working

```bash
bash kit-check                               # in the kit: every fixture, hooks + installer
node scripts/roles-kit/bin/roles-pulse.mjs   # last 7 days, this project: use, evidence, cost per run
node scripts/roles-kit/bin/inflight.mjs      # the lead's ledger
```

Cost in the pulse is a floor: transcripts under-count output tokens.

## Known limits

- A brand-new `.claude/agents/` folder needs a session restart before its roles exist.
- **The two-block limit is shared, not per agent.** The handback hook keys its counter on `agent_id`, falling back to `session_id`. Treat it as two blocks per role per session.
- **Headless runs skip hooks defined in agent files.** Under `claude -p` the handback and heartbeat hooks did not fire in our tests. Hooks in `settings.json` (territory guard, routing guard, in-flight recorder) still run; `ask.sh` sets `ROLE_KIT_ROLE` so the territory guard knows who is calling. Check the handback lines yourself.
- **A hook with a bash syntax error fails CLOSED** (bash exits 2 = block). Every hook is a tiny bash wrapper around a python file, and every fixture file starts by parsing both. A crash or syntax error in the python exits 0.
- The handback check reads what the role reports. A role could write `GATE: ... -> PASS` without running anything; the lead still reviews the diff.
- The territory guard reads shell commands with `shlex`, not a full shell parser. It handles redirects, pipes, `&&`/`;` chains, `cd`, heredocs and inline interpreter code; an unbalanced quote or an exotic construct is allowed (fail open), not guessed.
- The routing guard fallback is a regex on the prompt. It can miss an oddly worded edit. Saying "read-only, do not edit" lets analysis through on purpose.
- The rules skills are only as true as their source: generate them from your docs (`build_skills.sh`) instead of copying.
- The concept role has no worktree on purpose: it works on throwaway routes or a preview branch.

## Support and updates

- **Updates:** Watch → Custom → Releases, or the free [AI Boss newsletter](https://launchwithben.com/newsletter).
- **Problems:** open an issue. **Using it:** open a "Report a result" issue. The kit has no telemetry, so that is how I learn it is being used.
- **Security:** read the scripts before you install them, and report vulnerabilities privately (see [SECURITY.md](SECURITY.md)).
- **If it is ever sunset,** the top of this README will say so, the repo will be archived, and a final release will say what to use instead.

## License

MIT
