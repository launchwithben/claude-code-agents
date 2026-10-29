# Design approvals ledger

One row per element the owner has ruled on. The ui and concept roles read this FIRST (overlay `design.ledger` points here). The owner changes a row's status; roles never do, and never delete a row. When an element is approved, killed or sent back, the lead (or the owner) updates the row in the same commit as the work.

## Statuses

| Status | Meaning for a role |
|---|---|
| `KEEP` | Approved. Do not touch it unless the ask names it. If the work would touch it, say so before editing. |
| `KILL` | Rejected. It does not come back in any form, in any concept. |
| `CHANGE-REQUESTED` | The owner asked for a specific change. The ask is usually about these; do exactly what the row says, no more. |

## How to write a row

- `ID`: short, stable, never reused (`HERO-1`, `PRICING-3`). Roles quote it in their changed/kept list.
- `Where`: the page or component, precise enough to find it (route plus the element's visible label, or a frame link).
- `Element`: what it is, in a few words.
- `Note`: for `CHANGE-REQUESTED`, the exact change. For `KEEP`, what the owner liked, if they said. For `KILL`, why.
- `Ruled`: the date, and the evidence if any (a comment link, a message).

## Ledger

| ID | Where | Element | Status | Note | Ruled |
|---|---|---|---|---|---|
| HERO-1 | / (home) | Headline and subhead | KEEP | Owner: "the headline is right" | 2000-01-01 |
| HERO-2 | / (home) | Background illustration | KILL | Too busy behind the text | 2000-01-01 |
| NAV-1 | all pages | Header navigation | CHANGE-REQUESTED | Reduce to 5 links; keep order | 2000-01-01 |

## What roles hand back

A before/after of the same live page (same route, state and viewport), and one line:

```
LEDGER: changed NAV-1 | kept HERO-1
```

A KEEP element that is present before, gone after and not listed as changed is a defect. Add `line:LEDGER` to the role's `handback` list in the overlay to have the Stop hook require the line.
