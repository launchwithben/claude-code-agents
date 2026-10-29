{{#if DESIGN_LEDGER}}## Approvals ledger
Read `{{DESIGN_LEDGER}}` before anything else. It records, per element, what the owner approved (KEEP), killed (KILL) or asked to change (CHANGE-REQUESTED), each with an ID.
- Every concept keeps the KEEP elements unless the direction question is about them; say which ones each concept touches.
- A KILL element does not come back in any concept. A CHANGE-REQUESTED row is a constraint every concept must answer.
- Your note names the ledger IDs each concept keeps, changes and answers.

{{/if}}{{#if DESIGN_F}}## Design source: the design tool
This project designs in the design tool first (file: {{DESIGN_FILE}}). Render the concepts in the design file, on their own page or section named for the question, not on throwaway code routes. Light, dark and phone frames are frames in that file.
{{/if}}{{#if DESIGN_FE}}- Read the exported frames in `{{DESIGN_EXPORTS}}` first, for the current page and the approved frames. Call the design tool only for what the export lacks.
{{/if}}{{#if DESIGN_FB}}- The design tool's quota is shared and limited: use at most {{DESIGN_BUDGET}} design-tool calls for this task, never spend one on a frame that is already exported, and report how many you used.
{{/if}}{{#if DESIGN_F}}- If the tool is not available in this session, say so and hand back. Do not fall back to code routes.
{{/if}}{{#if DESIGN_FS}}- Nothing you render is built until the owner signs a frame off. Your note links each concept's frame; {{PREFIX}}-ui builds the pick only from the signed-off frame.
{{/if}}{{#if DESIGN_F}}
{{/if}}