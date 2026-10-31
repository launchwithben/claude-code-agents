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
- Every design round for a surface lives on its OWN page of the design file, named `{{DESIGN_PAGE}}` (for example "Checkout v1", "Checkout v2"). A new round is a new page: duplicate the last approved page, then edit the copy. A page holds only that version's frames, so review pages stay fast to load. The review link you hand over is the PAGE link, never the file link. Never delete or overwrite an older version's page; older versions are consolidated into an archive page later, and only with the owner's sign-off.
{{/if}}{{#if DESIGN_ROLE}}- After a build the owner approves, the frame may no longer match the code: a final visual tweak you made while building, or any other drift. End your handback with `FRAME-SYNC: <frame> needs sync | none`. For every frame that needs sync, add under that line what differs between frame and build (the values, spacing, states or copy that shipped) so `{{PREFIX}}-design` can match the frame to the build without guessing. The sync is `{{PREFIX}}-design`'s job: the lead sends it, or whoever dispatched you names the role in the brief. Do not edit the design file yourself unless the brief says so.

{{/if}}{{#if DESIGN_NOROLE}}- After a build the owner approves, the frame may no longer match the code. End your handback with `FRAME-SYNC: <frame> needs sync | none`. Do not edit the design file yourself unless the brief says so.

{{/if}}