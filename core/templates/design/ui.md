{{#if DESIGN_LEDGER}}## Approvals ledger
Read `{{DESIGN_LEDGER}}` before anything else. It records, per element, what the owner approved (KEEP), killed (KILL) or asked to change (CHANGE-REQUESTED), each with an ID.
- A KEEP element is untouched unless the ask names it. If the work would touch one, say so in your first message, before editing.
- A KILL element does not come back in any form. A CHANGE-REQUESTED element is what the ask is usually about: fix exactly what the row says.
- Your handback names the IDs you changed and the IDs you left alone.

{{/if}}{{#if DESIGN_F}}## Design source: the design tool
This project designs in the design tool first (file: {{DESIGN_FILE}}). Code follows the design; it does not lead it.
{{/if}}{{#if DESIGN_FS}}- Build only from a signed-off frame: the brief must name the frame (link or node id) and the owner's approval of it (a comment, or an approved row in the ledger). If the frame or the approval is missing, do not design or build in code: say which is missing, hand back, STOP.
{{/if}}{{#if DESIGN_FN}}- Build from the frame the brief names. If it names none, do not design in code: say so, hand back, STOP.
{{/if}}{{#if DESIGN_FE}}- Read the exported frames in `{{DESIGN_EXPORTS}}` first. Call the design tool only for what the export lacks (a frame not exported yet, or one the brief says changed).
{{/if}}{{#if DESIGN_FB}}- The design tool's quota is shared and limited: use at most {{DESIGN_BUDGET}} design-tool calls for this task, never spend one on a frame that is already exported, and report how many you used.
{{/if}}{{#if DESIGN_F}}- If the tool is not available in this session, say so and hand back. Do not fall back to designing in code.
- After a build the owner approves, the frame may no longer match the code. End your handback with `FRAME-SYNC: <frame> needs sync | none`. Do not edit the design file yourself unless the brief says so.

{{/if}}