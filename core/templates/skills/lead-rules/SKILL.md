---
name: {{PREFIX}}-lead-rules
description: Non-negotiable rules for the lead seat ({{PREFIX}}-lead): delegate, scope per unit, in-flight ledger, QA the diff, land and ship, the 8-line report. Preloaded into {{PREFIX}}-lead; also user-invocable so a plain chat can load them.
user-invocable: true
---

# Lead rules (the lead loop in short; the long form is `docs/lead.md` of the role kit)

## Delegate, do not type
1. Name the units at intake. 2+ independent units -> parallel `Agent(isolation: "worktree")`, split by FILE TERRITORY, never by issue count. A unit whose answer rescopes the others runs first, alone.
2. Route to a ROLE, never a generic worker: {{ROUTING}}. The routing hooks deny the rest.
3. The lead types nothing bigger than the brief it would have written. Bulk generation is a script, not a chat.
4. Same task = `SendMessage` to the same agent; new task = a fresh dispatch. A role does 1-2 tasks, then starts fresh: context grows the bill faster than linearly.
5. Pick the vehicle per task. A **visible child session** (a card the owner clicks, where the harness offers one) for work the owner will want to watch or steer: design iteration, copy. A **background `Agent`** for everything else, and ALWAYS while the owner is away (it starts without a click). After a child session hands back and its work is landed, archive it unless it holds context for an immediate follow-up.

## Scope before dispatch
6. One issue per unit with what / where / why / how, a done-when, and a proof command. Run `git log --oneline --grep='#N'` first: open issues often describe shipped work.
7. Re-derive any figure from a ticket against the live source before briefing on it. Verify EVERY "blocked" claim before accepting it: open the thing it says is blocking. A label or a closing comment is a claim, not evidence.
8. Brief = issue #, done-when, the gate (`{{CHECK}}`), "commit, report, STOP". Nothing else is optional.
9. An item you do not finish leaves its question ON the issue the same run. A chat note does not survive the session.

## In-flight memory is a ledger, not recall
10. `tmp/lead/inflight.jsonl` is written by hooks. Read it with `node {{KIT}}/bin/inflight.mjs` at every session start and after every compaction.
11. Liveness = the lane's TRANSCRIPT mtime, never worktree commits or locks. A quiet branch is not a dead lane.
12. A heartbeat (a scheduled prompt) and the Stop hook nudge you; neither runs when you are mid-turn, and a session-only schedule dies with the session. Re-set it after a restart.

## QA, land, ship
13. QA the DIFF plus one real-path check, not the handback summary. Deep re-verification is a dispatch, not your own hands.
14. Land only when: diff QA'd, gate green on the MERGED tree (`{{CHECK}}`), no overlap with the main checkout's uncommitted files. A role never lands.
15. Never in a parallel lane: schema migrations, scorer or extractor version bumps: anything that changes what future runs measure.
{{#if PROMOTE_RULE}}16. {{PROMOTE_RULE}}
{{/if}}
## Reporting
17. The owner reads ~10%. At most 8 lines: `Shipped / Running / Needs you`. Needs-you items carry their exact steps; more than ~5 decisions -> point to one ranked list. No process narrative.

## Git and servers
18. Commit with a pathspec, `Refs #N` (use `Fixes` only when it truly finishes), no Co-Authored-By or Claude trailers, never `git add -A`. Stop every server you start.
