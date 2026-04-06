#!/usr/bin/env bash
set -euo pipefail

GROUP="${DEPLOY_GROUP:?DEPLOY_GROUP not set}"
PLAYBOOK="playbooks/${GROUP}.yml"
INTERACTIVE="${DEPLOY_INTERACTIVE:-true}"
CHECK_MODE="${DEPLOY_CHECK_MODE:-false}"

# --- Host discovery ---
HOSTS="${usage_hosts:-}"
if [ -z "$HOSTS" ] && [ "$INTERACTIVE" = "true" ] && [ -t 0 ]; then
  AVAILABLE=$(ansible-inventory --graph "$GROUP" 2>/dev/null | grep '^[[:space:]]*|--' | sed 's/.*|--//' | tr '\n' ',' | sed 's/,$//')
  echo ""
  echo "Available Hosts for ${GROUP}: ${AVAILABLE:-none found}"
  read -rp " >> Comma-separated hosts (Press Enter to skip): " HOSTS
fi

# --- Tag discovery ---
TAGS="${usage_tags:-}"
if [ -z "$TAGS" ] && [ "$INTERACTIVE" = "true" ] && [ -t 0 ]; then
  AVAILABLE_TAGS=$(ansible-playbook "$PLAYBOOK" --list-tags 2>/dev/null | grep 'TASK TAGS' | sed 's/.*\[//;s/\].*//' | tr ',' '\n' | sed 's/^ //' | sort -u | tr '\n' ',' | sed 's/,$//')
  echo ""
  echo "Available Tags for ${GROUP}: ${AVAILABLE_TAGS:-none found}"
  read -rp " >> Comma-separated tags (Press Enter to skip): " TAGS
  echo ""
fi

# --- Build and execute ---
CMD=(ansible-playbook "$PLAYBOOK")
[ -n "$HOSTS" ] && CMD+=(--limit "$HOSTS")
[ -n "$TAGS" ] && CMD+=(--tags "$TAGS")
[ "$CHECK_MODE" = "true" ] && CMD+=(--check --diff)
"${CMD[@]}" "$@"
