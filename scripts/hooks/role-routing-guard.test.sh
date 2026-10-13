#!/usr/bin/env bash
# Fixtures for role-routing-guard.sh.   bash scripts/hooks/role-routing-guard.test.sh
# A syntax error makes bash exit 2, which Claude Code reads as BLOCK: a fail-open hook would fail closed.
bash -n "$(dirname "$0")/role-routing-guard.sh" || { echo "FAIL role-routing-guard.sh has a bash syntax error"; exit 1; }
set -uo pipefail
cd "$(dirname "$0")"
# Denials are logged under $CLAUDE_PROJECT_DIR/tmp/role-routing; point it at a scratch dir so fixtures
# never write into the real log.
export CLAUDE_PROJECT_DIR="$(mktemp -d)"
trap 'rm -rf "$CLAUDE_PROJECT_DIR"' EXIT
G=./role-routing-guard.sh
fails=0
check() { # <want-exit> <label> <subagent_type> <prompt>
  local want="$1" label="$2" st="$3" prompt="$4" got
  python3 -c 'import json,sys;print(json.dumps({"tool_name":"Agent","tool_input":{"subagent_type":sys.argv[1],"prompt":sys.argv[2]}}))' "$st" "$prompt" | "$G" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then printf '  ok   %s\n' "$label"; else printf '  FAIL %s (want %s got %s)\n' "$label" "$want" "$got"; fails=$((fails+1)); fi
}
echo "-- must DENY (exit 2)"
check 2 "bulk-worker edits an astro component" bulk-worker "Edit src/components/Hero.astro to add a toggle above the picks"
check 2 "general-purpose restyles with CSS"    general-purpose "Restyle the pricing table: update the CSS in src/styles/global.css"
check 2 "full-stack-developer builds design"   full-stack-developer "Build a new design for the homepage hero section"
check 2 "haiku-worker implements astro page"   haiku-worker "Implement a new section in pricing.astro"
check 2 "plugin-prefixed generic worker"       daily-skills:bulk-worker "Fix the tailwind classes in the nav component and update the stylesheet"
check 2 "empty subagent_type (default)"        "" "Redesign the footer layout, edit footer.astro"
check 2 "bulk-worker restores content titles"  bulk-worker "Restore the translated page titles in src/content/posts and commit"
check 2 "generic worker edits a script"        general-purpose "Fix the off-by-one in scripts/build-feed.mjs and commit with Refs #1"
check 2 "generic worker updates a json file" bulk-worker "Update pricing.json so the pro plan says 29"
echo "-- must ALLOW (exit 0)"
check 0 "summary with no repo path"            bulk-worker "Query the database for signups and write a summary of conversion by channel"
check 0 "read-only audit naming paths"         bulk-worker "Audit scripts/gates/*.mjs for unwired gates. Read-only, report only."
check 0 "read-only call-site map"              bulk-worker "Map every call site of PricingCard in src/components. Read-only, do not edit anything."
check 0 "code-style word is not a UI task"    bulk-worker "Describe the code style and export style of this repo and write a summary"
check 0 "analysis with no UI words"            bulk-worker "Query the database for signups last 7 days and write a summary of conversion by channel"
check 0 "role-ui may edit UI"                   role-ui "Edit src/components/Hero.astro to add a toggle"
check 0 "role-dev non-UI script"                role-dev "Add a gate script under scripts/gates and wire it into npm run check"
check 0 "generic worker, UI noun but no verb"  general-purpose "List which .astro files import Icon.astro"
check 0 "role-concept direction question"       role-concept "Show 3 ways the pricing toggle could work in the design"
check 0 "malformed payload fails open"         x "ok"
echo "-- garbage stdin fails open"
printf 'not json' | "$G" >/dev/null 2>&1; [ $? = 0 ] && echo "  ok   garbage stdin" || { echo "  FAIL garbage stdin"; fails=$((fails+1)); }
[ "$fails" = 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
