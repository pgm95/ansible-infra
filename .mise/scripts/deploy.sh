#!/usr/bin/env bash
set -euo pipefail

GROUP="${DEPLOY_GROUP:?DEPLOY_GROUP not set}"
PLAYBOOK="playbooks/${GROUP}.yml"
INTERACTIVE="${DEPLOY_INTERACTIVE:-true}"
CHECK_MODE="${DEPLOY_CHECK_MODE:-false}"

# --- Host discovery ---
HOSTS="${usage_hosts:-}"
if [ -z "$HOSTS" ] && [ "$INTERACTIVE" = "true" ] && [ -t 0 ]; then
  HOST_VARS_DIR="inventory/host_vars/${GROUP}"
  if [ -d "$HOST_VARS_DIR" ] && find "$HOST_VARS_DIR" -maxdepth 1 -name '*.yml' -print -quit | grep -q .; then
    AVAILABLE=$(find "$HOST_VARS_DIR" -maxdepth 1 -name '*.yml' -exec basename {} .yml \; | sort | tr '\n' ',' | sed 's/,$//')
  else
    AVAILABLE=$(ansible-inventory --graph "$GROUP" 2>/dev/null | grep '^[[:space:]]*|--' | sed 's/.*|--//' | tr '\n' ',' | sed 's/,$//')
  fi
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
if [ -n "$HOSTS" ]; then
  case "$GROUP" in
    lxc|vm) CMD+=(--limit "localhost,$HOSTS") ;;
    *)      CMD+=(--limit "$HOSTS") ;;
  esac
fi
[ -n "$TAGS" ] && CMD+=(--tags "$TAGS")
[ "$CHECK_MODE" = "true" ] && CMD+=(--check --diff)
"${CMD[@]}" "$@"
