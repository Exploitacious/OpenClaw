#!/usr/bin/env bash

# =============================================================================
# OpenClaw Reset Script
#
# Wipes workspace (SOUL.md, AGENTS.md, USER.md), memory, and sessions while
# preserving all API keys, provider credentials, and config settings.
# Re-applies templates from the helper repo and launches onboard to re-hatch.
#
# Usage:
#   Interactive:  bash ~/OpenClaw/openclaw-reset.sh
#   Scripted:     bash ~/OpenClaw/openclaw-reset.sh --confirm --skip-hatch
# =============================================================================

set -euo pipefail

# -- Colors & Formatting -------------------------------------------------------
GN="\e[32m"; RD="\e[31m"; BL="\e[36m"; YW="\e[33m"; DM="\e[2m"; CL="\e[0m"
CM="${GN}\xE2\x9C\x94${CL}"; CROSS="${RD}\xE2\x9C\x98${CL}"

msg_ok()    { printf " ${CM} ${GN}%s${CL}\n" "$1"; }
msg_error() { printf " ${CROSS} ${RD}%s${CL}\n" "$1"; }
msg_info()  { printf "   ${BL}%s${CL}\n" "$1"; }
msg_warn()  { printf "   ${YW}%s${CL}\n" "$1"; }
msg_step()  { printf "\n ${GN}>>>${CL} %s\n" "$1"; }
msg_dim()   { printf "   ${DM}%s${CL}\n" "$1"; }

# -- Ensure PATH ---------------------------------------------------------------
export PATH="${HOME}/.npm-global/bin:${HOME}/.local/share/pnpm:${PATH}"
NVM_NODE_DIR="${HOME}/.nvm/versions/node"
if [[ -d "$NVM_NODE_DIR" ]]; then
  NVM_LATEST=$(ls "$NVM_NODE_DIR" 2>/dev/null | sort -V | tail -1)
  [[ -n "$NVM_LATEST" ]] && export PATH="${NVM_NODE_DIR}/${NVM_LATEST}/bin:${PATH}"
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# -- Config --------------------------------------------------------------------
OC_DIR="${HOME}/.openclaw"
OC_CONFIG="${OC_DIR}/openclaw.json"
OC_ENV="${OC_DIR}/.env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"
REPO_RAW="https://raw.githubusercontent.com/Exploitacious/OpenClaw/main"

# -- Parse flags ---------------------------------------------------------------
CONFIRMED=false
SKIP_HATCH=false
KEEP_SOUL=false
FULL_RESET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm)       CONFIRMED=true; shift ;;
    --skip-hatch)    SKIP_HATCH=true; shift ;;
    --keep-soul)     KEEP_SOUL=true; shift ;;
    --full)          FULL_RESET=true; shift ;;
    --help|-h)
      echo "Usage: bash openclaw-reset.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --confirm       Skip confirmation prompt"
      echo "  --skip-hatch    Don't launch onboard after reset"
      echo "  --keep-soul     Preserve SOUL.md (only reset memory/sessions)"
      echo "  --full          Also reset openclaw.json to template defaults"
      echo "                  (preserves API keys in .env and auth-profiles)"
      echo "  --help          Show this help"
      exit 0
      ;;
    *)
      msg_error "Unknown flag: $1"
      exit 1
      ;;
  esac
done

# -- Preflight checks ---------------------------------------------------------
if [[ "$(id -u)" == "0" ]]; then
  msg_error "Do not run this as root. Run as the claw user."
  exit 1
fi

if [[ ! -d "$OC_DIR" ]]; then
  msg_error "OpenClaw directory not found at ${OC_DIR}"
  exit 1
fi

if ! command -v openclaw &>/dev/null; then
  msg_error "openclaw command not found in PATH"
  exit 1
fi

# -- Resolve templates ---------------------------------------------------------
# Try local repo first, fall back to GitHub
resolve_template() {
  local NAME="$1"
  if [[ -f "${TEMPLATE_DIR}/${NAME}" ]]; then
    cat "${TEMPLATE_DIR}/${NAME}"
  elif curl -fsSL "${REPO_RAW}/templates/${NAME}" 2>/dev/null; then
    : # curl already output to stdout
  else
    msg_error "Cannot resolve template: ${NAME}"
    return 1
  fi
}

# -- Show what will be wiped ---------------------------------------------------
echo ""
echo -e "${YW}============================================${CL}"
echo -e "${YW}  OpenClaw Reset${CL}"
echo -e "${YW}============================================${CL}"
echo ""

msg_info "This will:"
if ! $KEEP_SOUL; then
  echo -e "   ${RD}\xe2\x80\xa2${CL} Replace SOUL.md, AGENTS.md, USER.md with templates"
fi
echo -e "   ${RD}\xe2\x80\xa2${CL} Wipe all memory (LanceDB vector store + markdown logs)"
echo -e "   ${RD}\xe2\x80\xa2${CL} Wipe all sessions (conversation history)"
echo -e "   ${RD}\xe2\x80\xa2${CL} Wipe workspace skills (memory-lancedb-hybrid plugin data)"
if $FULL_RESET; then
  echo -e "   ${RD}\xe2\x80\xa2${CL} Reset openclaw.json to template defaults"
fi
echo ""
msg_info "This will KEEP:"
echo -e "   ${GN}\xe2\x80\xa2${CL} API keys (.env)"
echo -e "   ${GN}\xe2\x80\xa2${CL} Provider credentials (auth-profiles.json)"
echo -e "   ${GN}\xe2\x80\xa2${CL} Gateway token and Telegram bot token"
if ! $FULL_RESET; then
  echo -e "   ${GN}\xe2\x80\xa2${CL} All openclaw.json settings (models, concurrency, hooks, etc.)"
fi
if $KEEP_SOUL; then
  echo -e "   ${GN}\xe2\x80\xa2${CL} SOUL.md (personality preserved)"
fi
echo ""

if ! $CONFIRMED; then
  printf "   ${RD}Are you sure? This cannot be undone. [y/N]${CL}: "
  read -r CONFIRM_INPUT
  if [[ "${CONFIRM_INPUT,,}" != "y" && "${CONFIRM_INPUT,,}" != "yes" ]]; then
    msg_info "Cancelled."
    exit 0
  fi
fi

# -- Create backup before reset ------------------------------------------------
msg_step "Step 1/5: Backup"
BACKUP_DIR="${HOME}/backups"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="${BACKUP_DIR}/openclaw-pre-reset-$(date +%Y%m%d-%H%M%S).tar.gz"

msg_info "Backing up current state..."
tar -czf "$BACKUP_FILE" \
  -C "$HOME" \
  .openclaw/openclaw.json \
  .openclaw/.env \
  .openclaw/workspace/ \
  .openclaw/agents/ \
  2>/dev/null || true

if [[ -f "$BACKUP_FILE" ]]; then
  msg_ok "Backup saved: ${BACKUP_FILE}"
else
  msg_warn "Backup may be incomplete"
fi

# -- Stop gateway --------------------------------------------------------------
msg_step "Step 2/5: Stop gateway"
systemctl --user stop openclaw-gateway.service 2>/dev/null || true
sleep 1
msg_ok "Gateway stopped"

# -- Wipe sessions and memory --------------------------------------------------
msg_step "Step 3/5: Wipe data"

# Sessions
if [[ -d "${OC_DIR}/sessions" ]]; then
  rm -rf "${OC_DIR}/sessions"
  msg_ok "Sessions wiped"
else
  msg_dim "No sessions directory found"
fi

# Memory (LanceDB + markdown)
if [[ -d "${OC_DIR}/memory" ]]; then
  rm -rf "${OC_DIR}/memory"
  msg_ok "Memory wiped"
else
  msg_dim "No memory directory found"
fi

# Agent session data
find "${OC_DIR}/agents" -type d -name "sessions" -exec rm -rf {} + 2>/dev/null || true
msg_ok "Agent session data wiped"

# Memory plugin data in workspace
if [[ -d "${OC_DIR}/workspace/skills/memory-lancedb-hybrid" ]]; then
  # Keep the plugin code, wipe the data
  find "${OC_DIR}/workspace/skills/memory-lancedb-hybrid" \
    -name "*.lance" -o -name "*.idx" -o -name "*.manifest" \
    -exec rm -f {} + 2>/dev/null || true
  msg_ok "Memory plugin data wiped"
fi

# -- Re-apply templates --------------------------------------------------------
msg_step "Step 4/5: Apply templates"

WORKSPACE_DIR="${OC_DIR}/workspace"
mkdir -p "$WORKSPACE_DIR"

# SOUL.md
if ! $KEEP_SOUL; then
  SOUL_CONTENT=$(resolve_template "soul.md.tpl" 2>/dev/null) || true
  if [[ -n "$SOUL_CONTENT" ]]; then
    echo "$SOUL_CONTENT" > "${WORKSPACE_DIR}/SOUL.md"
    msg_ok "SOUL.md reset to template"
  else
    msg_warn "Could not resolve soul.md.tpl — SOUL.md left unchanged"
  fi
fi

# AGENTS.md
AGENTS_CONTENT=$(resolve_template "agents.md.tpl" 2>/dev/null) || true
if [[ -n "$AGENTS_CONTENT" ]]; then
  echo "$AGENTS_CONTENT" > "${WORKSPACE_DIR}/AGENTS.md"
  msg_ok "AGENTS.md reset to template"
else
  msg_warn "Could not resolve agents.md.tpl — AGENTS.md left unchanged"
fi

# USER.md — create empty if it doesn't exist, or wipe to empty
echo "# User Context" > "${WORKSPACE_DIR}/USER.md"
echo "" >> "${WORKSPACE_DIR}/USER.md"
echo "Add personal context here. The agent reads this at session start." >> "${WORKSPACE_DIR}/USER.md"
msg_ok "USER.md reset to blank"

# Full config reset (optional)
if $FULL_RESET; then
  # Save values we want to preserve
  SAVED_GW_TOKEN=$(jq -r '.gateway.auth.token // ""' "$OC_CONFIG" 2>/dev/null)
  SAVED_TG_TOKEN=$(jq -r '.channels.telegram.botToken // ""' "$OC_CONFIG" 2>/dev/null)
  SAVED_TG_UID=$(jq -r '.channels.telegram.dmPolicy // ""' "$OC_CONFIG" 2>/dev/null)
  SAVED_TS_DNS=$(jq -r '.gateway.remote.url // ""' "$OC_CONFIG" 2>/dev/null)

  # Apply template
  CONFIG_CONTENT=$(resolve_template "openclaw.json.tpl" 2>/dev/null) || true
  if [[ -n "$CONFIG_CONTENT" ]]; then
    echo "$CONFIG_CONTENT" > "$OC_CONFIG"
    chmod 600 "$OC_CONFIG"

    # Restore preserved values
    [[ -n "$SAVED_GW_TOKEN" ]] && \
      jq --arg t "$SAVED_GW_TOKEN" '.gateway.auth.token = $t' "$OC_CONFIG" > "${OC_CONFIG}.tmp" && \
      mv "${OC_CONFIG}.tmp" "$OC_CONFIG"
    [[ -n "$SAVED_TG_TOKEN" && "$SAVED_TG_TOKEN" != "__TELEGRAM_BOT_TOKEN__" ]] && \
      jq --arg t "$SAVED_TG_TOKEN" '.channels.telegram.botToken = $t' "$OC_CONFIG" > "${OC_CONFIG}.tmp" && \
      mv "${OC_CONFIG}.tmp" "$OC_CONFIG"
    [[ -n "$SAVED_TS_DNS" ]] && \
      jq --arg u "$SAVED_TS_DNS" '.gateway.remote.url = $u' "$OC_CONFIG" > "${OC_CONFIG}.tmp" && \
      mv "${OC_CONFIG}.tmp" "$OC_CONFIG"

    chmod 600 "$OC_CONFIG"
    msg_ok "openclaw.json reset to template (tokens preserved)"
  else
    msg_warn "Could not resolve openclaw.json.tpl — config left unchanged"
  fi
fi

# -- Restart and hatch ---------------------------------------------------------
msg_step "Step 5/5: Restart"

# Run doctor to re-wire hooks
msg_info "Running openclaw doctor --fix..."
openclaw doctor --fix 2>&1 | tail -5 || true
msg_ok "Doctor completed"

# Git commit the reset
if [[ -d "${OC_DIR}/.git" ]]; then
  cd "$OC_DIR"
  git add -A 2>/dev/null || true
  git commit -q -m "reset: wiped memory/sessions, re-applied templates $(date +%Y-%m-%d)" 2>/dev/null || true
  msg_ok "Reset committed to git"
fi

# Start gateway
msg_info "Starting gateway..."
systemctl --user start openclaw-gateway.service 2>/dev/null || true
sleep 3

if systemctl --user is-active openclaw-gateway.service >/dev/null 2>&1; then
  msg_ok "Gateway running"
else
  msg_warn "Gateway may not have started. Check: systemctl --user status openclaw-gateway.service"
fi

echo ""
echo -e "${GN}============================================${CL}"
echo -e "${GN}  Reset Complete${CL}"
echo -e "${GN}============================================${CL}"
echo ""
msg_ok "Backup: ${BACKUP_FILE}"
msg_ok "Memory and sessions wiped"
msg_ok "Templates re-applied"
echo ""

if $SKIP_HATCH; then
  msg_info "Skipped hatching. When ready:"
  echo ""
  echo -e "  ${BL}openclaw onboard --skip-auth --skip-channels --skip-health --skip-skills${CL}"
  echo ""
  echo -e "  ${DM}Select all hooks, then choose 'TUI' to hatch.${CL}"
  echo ""
  exit 0
fi

msg_info "Launching onboard to re-hatch the bot..."
msg_dim "Select all hooks when prompted, then choose 'TUI' to hatch."
msg_dim ""
msg_warn "Do NOT message the bot on Telegram until the TUI session is connected."
echo ""

printf "   ${BL}Press Enter to launch onboard (or 's' to skip)${CL}: "
read -r HATCH_REPLY

if [[ "${HATCH_REPLY,,}" != "s" ]]; then
  echo ""
  exec openclaw onboard --skip-auth --skip-channels --skip-health --skip-skills
else
  echo ""
  msg_info "When ready:"
  echo -e "  ${BL}openclaw onboard --skip-auth --skip-channels --skip-health --skip-skills${CL}"
  echo ""
fi
