# The lead

The lead is the one role that is not a subagent. It is the **main chat** you talk to: it scopes the work, files one issue per unit, dispatches the other roles in parallel worktrees, stays free to talk to you while they run, then QAs the diff, lands, gates the merged tree and ships. It never types bulk edits. Roles do the typing.

Why a seat and not a subagent: a subagent cannot spawn the other roles, and the point of the lead is that it holds the plan across many dispatches. So the lead is installed as an agent file (`<prefix>-lead.md`) that you *start a chat as*, and every dispatch hook knows not to dispatch it.

## Starting it

| Where | How |
|---|---|
| CLI | `claude --agent <prefix>-lead` |
| Desktop app | open a chat and run `/<prefix>-lead-rules` (the rules skill is user-invocable), or the command in the overlay's `lead.appRoute` if you have your own |
| Not possible | `Agent(subagent_type: "<prefix>-lead")`. The routing guard denies it and says how to start it properly. |

A brand-new agents folder needs a session restart before `--agent` can see it.

## The loop

1. **Session start.** Read the ledger (`node scripts/roles-kit/bin/inflight.mjs`), then the PM's ready chains (`chains` in the overlay). Land or chase what is finished-but-unlanded FIRST.
2. **Intake.** Name the units out loud. One issue per unit, scoped: what / where / why / how, a done-when, a proof command. `git log --oneline --grep='#N'` first: open issues often describe shipped work. Re-derive any figure quoted in a ticket against the live source.
3. **Dispatch** to a ROLE, never a generic worker, in ONE message when units are independent, split by **file territory**, never by issue count. A unit whose answer rescopes the others runs first, alone. The brief is the issue number, the done-when, the gate, and "commit, report, STOP".
4. **Stay free.** While roles run, answer the owner and scope the next unit. Do not poll; the harness notifies you.
5. **On handback:** QA the DIFF (not the summary) plus one real-path check. Land only when the diff is QA'd, the gate is green on the **merged** tree, and nothing overlaps the main checkout's uncommitted files. A role never lands. A role sent back counts as a rework round.
6. **Report in 8 lines or fewer:** Shipped / Running / Needs you.

Never in a parallel lane: schema migrations, scorer or extractor version bumps, anything that changes what future runs measure.

## The in-flight ledger

"What is running?" must not depend on the lead remembering, because compaction and `/clear` erase memory.

- A `PostToolUse` hook on `Agent|Task` appends a row to `tmp/lead/inflight.jsonl` for every dispatch (agent id, role, issue number from the prompt, session id). A `SubagentStop` hook appends a `done` row, with the `COMMIT:` sha from the handback, **only** for an agent id that was dispatched, so the hooks are harmless in sessions that never use a lead.
- `node scripts/roles-kit/bin/inflight.mjs` reads it: **running**, **stalled** (idle more than 20 minutes, `LEAD_STALE_MIN`), **finished, not landed**, **landed**.
- **Liveness is the subagent's transcript mtime**, not worktree commits or locks: a lane that is thinking or running a long gate has no new commit for an hour and is alive. If no transcript is found, the age of the dispatch is used.
- **Landed** means the handback sha is an ancestor of `mainBranch` (a real `git merge-base --is-ancestor`), not a label.
- `--session <id>` filters to one session; a row with no session id never matches.

## The heartbeat

A `Stop` hook, declared in the lead's own agent file so it applies to that chat only. When the lead is about to stop its turn and **nothing is running** but there is finished-unlanded work, or a launchable chain under `## Ready chains` in the chains file, it blocks **once** with "land X / dispatch Y". The same state (session plus ledger and chains signature) never blocks twice, so the lead can always answer "idle, nothing to do" next time. It is keyed by `session_id`: a session that never dispatched is never nudged. Because a desktop-app chat cannot be started *as* an agent, set `lead.hookScope: "project"` in the overlay and the installer registers the recorder and the heartbeat in `settings.json` for every session instead; the key makes that safe for sessions that are not the lead. If a scheduler is available (a recurring prompt), the lead sets an hourly check at session start; that is session-only and fires only while idle.

## Modes

| Choice | Use it when |
|---|---|
| **Chat** (owner present) vs **unattended** (owner away) | Present: ask the one question that unblocks, keep the report short. Away: only dispatch units that are decided, self-contained, verifiable and reversible (the PM marks them ready); leave every question ON the issue, because a chat note does not survive the session. |
| **Child session** vs **background agent** | A visible child session (a card the owner clicks, where the harness offers one) for work the owner will want to watch or steer: design iteration, copy. A background `Agent` for everything else, and always while the owner is away, because it starts without a click. |
| **Same agent** vs **fresh** | Same task: `SendMessage` to the same agent. New task: a fresh dispatch. **A role does one or two tasks, then starts fresh**: context grows the bill faster than linearly. |
| **Headless** | `bash scripts/roles-kit/bin/ask.sh <role> "<brief>"` runs `claude -p --agent` in a small fresh context, logs cost to `tmp/roles/roles.jsonl`, and recovers a handback that later chatter buried. |

## The PM feeds the lead

`<prefix>-pm` triages only what changed on the board since its last run (`pm-delta.mjs`, cursor in the overlay's `pm.cursor`), gives each changed issue one verdict (close with evidence, ready, decide, recon, no-op), and groups the ready ones into **chains** written to the chains file. The lead launches chains; the heartbeat reads that file. The PM advances its cursor only after its board writes landed, so a failed write is seen again next run.

## Territory

If the overlay has a `territory` file, the lead may read everything it does not mark `all`, but changes under a role's territory are refused with the role to hand them to. That is the "delegate, do not type" rule enforced rather than remembered. `touch tmp/role-override` lifts it for 30 minutes when you explicitly ask the lead to work hands-on.
