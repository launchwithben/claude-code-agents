---
name: {{PREFIX}}-{{NAME}}
description: >-
  {{DESCRIPTION}}
model: {{MODEL}}
{{#if WORKTREE}}isolation: worktree
{{/if}}color: {{COLOR}}
{{#if SKILLS}}skills:
{{SKILLS}}
{{/if}}hooks:
  Stop:
    - hooks:
        - type: command
          command: "bash \"{{HOOKS}}/role-handback-check.sh\" {{PREFIX}}-{{NAME}}"
          timeout: 10
---

{{BODY}}
