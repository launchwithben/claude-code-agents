---
name: roles
description: Pick and start one of the project's role agents (role-dev, role-ui, role-concept) from a menu, so nobody has to remember their names. Use when the owner types /roles, asks "which roles do we have", or wants to start a role without naming it.
---

# /roles: the role menu

1. Get the live list. It is read from `.claude/agents/role-*.md`, so a new role appears here on its own:
   ```sh
   printf '%s' '{"prompt":"@agent-role"}' | bash "$CLAUDE_PROJECT_DIR/scripts/hooks/role-picker.sh"
   ```
2. Ask with AskUserQuestion, one option per role: label = role name, description = its line. If the owner already typed a task after `/roles`, put it in the question so they only pick.
3. Start the chosen role with the Agent tool (`subagent_type` = the role). Their task is the brief. If they gave none, ask for it in one line first: never start a role with an empty brief.
4. Relay the role's report in plain language. A follow-up on the same work goes to the SAME agent (SendMessage), not a new start.
