#!/usr/bin/env bash

# =============================================================================
# OpenClaw Post-Install Wizard
#
# Run after openclaw-install.sh to complete setup interactively or via flags.
# Handles: AI providers, embeddings key, Telegram bot, Tailscale, onboarding.
#
# Usage:
#   Interactive:  bash openclaw-postinstall.sh
#   Scripted:     bash openclaw-postinstall.sh \
#                   --provider anthropic-api-key --provider-key sk-ant-... \
#                   --provider gemini-api-key --provider-key AIza... \
#                   --primary-model anthropic/claude-sonnet-4-5 \
#                   --openai-key sk-... \
#                   --telegram-token 123456:ABC... \
#                   --telegram-user-id 5361915599 \
#                   --tailscale-auth-key tskey-auth-...
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
# Append NVM node if available
NVM_NODE_DIR="${HOME}/.nvm/versions/node"
if [[ -d "$NVM_NODE_DIR" ]]; then
  NVM_LATEST=$(ls "$NVM_NODE_DIR" 2>/dev/null | sort -V | tail -1)
  [[ -n "$NVM_LATEST" ]] && export PATH="${NVM_NODE_DIR}/${NVM_LATEST}/bin:${PATH}"
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

OC_DIR="${HOME}/.openclaw"
OC_CONFIG="${OC_DIR}/openclaw.json"
OC_ENV="${OC_DIR}/.env"
AUTH_PROFILES="${OC_DIR}/agents/main/agent/auth-profiles.json"

# -- Provider registry ---------------------------------------------------------
# Maps menu labels to openclaw onboard --auth-choice values, key flags, and
# example model strings. Order matters (it's the menu order).
#
# Format: "label|auth-choice|key-flag|example-models"
PROVIDER_REGISTRY=(
  "Anthropic (Claude)|anthropic-api-key|--anthropic-api-key|anthropic/claude-sonnet-4-5, anthropic/claude-opus-4-5"
  "Google Gemini|gemini-api-key|--gemini-api-key|gemini/gemini-2.5-flash, gemini/gemini-2.5-pro"
  "OpenAI (GPT)|openai-api-key|--openai-api-key|openai/gpt-5, openai/gpt-5-mini"
  "OpenRouter|openrouter-api-key|--openrouter-api-key|openrouter/google/gemini-3-flash-preview"
  "Ollama (local)|ollama||ollama/llama4, ollama/qwen3"
  "DeepSeek|deepseek-api-key|--deepseek-api-key|deepseek/deepseek-chat, deepseek/deepseek-reasoner"
  "xAI (Grok)|xai-api-key|--xai-api-key|xai/grok-3, xai/grok-3-mini"
  "Mistral|mistral-api-key|--mistral-api-key|mistral/mistral-large, mistral/codestral"
  "Together AI|together-api-key|--together-api-key|together/meta-llama/Llama-4-Maverick-17Bx128E"
  "LiteLLM proxy|litellm-api-key|--litellm-api-key|litellm/your-model-id"
  "Custom (OpenAI-compat)|custom-api-key|--custom-api-key|custom/your-model-id"
)

# -- Parse flags ---------------------------------------------------------------
# Provider flags are paired: --provider <choice> --provider-key <key>
# Can be repeated for multiple providers.
declare -a CLI_PROVIDERS=()    # auth-choice values
declare -a CLI_PROVIDER_KEYS=() # corresponding keys
PRIMARY_MODEL=""
FALLBACK_MODELS=""
HEARTBEAT_MODEL=""
OPENAI_KEY=""
TELEGRAM_TOKEN=""
TELEGRAM_USER_ID=""
TAILSCALE_AUTH_KEY=""
SKIP_TAILSCALE=false
SKIP_SOUL=false
SKIP_PROVIDERS=false
NON_INTERACTIVE=false
OLLAMA_BASE_URL=""
CUSTOM_BASE_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      CLI_PROVIDERS+=("$2"); shift 2 ;;
    --provider-key)
      CLI_PROVIDER_KEYS+=("$2"); shift 2 ;;
    --primary-model)      PRIMARY_MODEL="$2"; shift 2 ;;
    --fallback-models)    FALLBACK_MODELS="$2"; shift 2 ;;
    --heartbeat-model)    HEARTBEAT_MODEL="$2"; shift 2 ;;
    --openai-key)         OPENAI_KEY="$2"; shift 2 ;;
    --telegram-token)     TELEGRAM_TOKEN="$2"; shift 2 ;;
    --telegram-user-id)   TELEGRAM_USER_ID="$2"; shift 2 ;;
    --tailscale-auth-key) TAILSCALE_AUTH_KEY="$2"; shift 2 ;;
    --ollama-url)         OLLAMA_BASE_URL="$2"; shift 2 ;;
    --custom-base-url)    CUSTOM_BASE_URL="$2"; shift 2 ;;
    --skip-tailscale)     SKIP_TAILSCALE=true; shift ;;
    --skip-soul)          SKIP_SOUL=true; shift ;;
    --skip-providers)     SKIP_PROVIDERS=true; shift ;;
    --non-interactive)    NON_INTERACTIVE=true; shift ;;
    -h|--help)
      cat <<'USAGE'
Usage: openclaw-postinstall.sh [OPTIONS]

AI Providers (repeatable):
  --provider <choice>       Provider auth-choice (e.g. anthropic-api-key, ollama)
  --provider-key <key>      API key for the preceding --provider
  --primary-model <model>   Primary model (e.g. anthropic/claude-sonnet-4-5)
  --fallback-models <csv>   Comma-separated fallback models
  --heartbeat-model <model> Heartbeat/lightweight model
  --ollama-url <url>        Ollama base URL (default: http://localhost:11434)
  --custom-base-url <url>   Custom provider base URL

Embeddings:
  --openai-key <key>        OpenAI key (for memory embeddings only)

Telegram:
  --telegram-token <token>  Bot token from @BotFather
  --telegram-user-id <id>   Your numeric Telegram user ID

Tailscale:
  --tailscale-auth-key <key>  Auth key for non-interactive setup

Skips:
  --skip-providers          Skip AI provider setup
  --skip-tailscale          Skip Tailscale setup
  --skip-soul               Skip SOUL.md editor prompt
  --non-interactive         No prompts (use flags for all values)
USAGE
      exit 0 ;;
    *) msg_error "Unknown flag: $1"; exit 1 ;;
  esac
done

# -- Helpers -------------------------------------------------------------------
prompt_value() {
  local VARNAME="$1"
  local PROMPT_TEXT="$2"
  local DEFAULT="${3:-}"
  local SENSITIVE="${4:-false}"

  local CURRENT="${!VARNAME:-}"
  if [[ -n "$CURRENT" ]]; then return 0; fi

  if $NON_INTERACTIVE; then
    [[ -n "$DEFAULT" ]] && eval "$VARNAME='$DEFAULT'"
    return 0
  fi

  local DISPLAY_DEFAULT=""
  [[ -n "$DEFAULT" ]] && DISPLAY_DEFAULT=" [${DEFAULT}]"

  if [[ "$SENSITIVE" == "true" ]]; then
    printf "   ${BL}%s${CL}%s: " "$PROMPT_TEXT" "$DISPLAY_DEFAULT"
    read -rs REPLY; echo ""
  else
    printf "   ${BL}%s${CL}%s: " "$PROMPT_TEXT" "$DISPLAY_DEFAULT"
    read -r REPLY
  fi

  if [[ -n "$REPLY" ]]; then
    eval "$VARNAME='$REPLY'"
  elif [[ -n "$DEFAULT" ]]; then
    eval "$VARNAME='$DEFAULT'"
  fi
}

prompt_yesno() {
  local PROMPT_TEXT="$1"
  local DEFAULT="${2:-y}"
  if $NON_INTERACTIVE; then [[ "$DEFAULT" == "y" ]]; return; fi

  local HINT="[Y/n]"; [[ "$DEFAULT" == "n" ]] && HINT="[y/N]"
  printf "   ${BL}%s${CL} %s: " "$PROMPT_TEXT" "$HINT"
  read -r REPLY
  REPLY="${REPLY:-$DEFAULT}"
  [[ "${REPLY,,}" == "y" || "${REPLY,,}" == "yes" ]]
}

# Register a single provider with openclaw onboard
register_provider() {
  local AUTH_CHOICE="$1"
  local API_KEY="${2:-}"
  local EXTRA_FLAGS="${3:-}"

  local CMD=(openclaw onboard --non-interactive --accept-risk --auth-choice "$AUTH_CHOICE" --skip-channels --skip-health --skip-skills --skip-ui)

  # Find the key flag for this auth-choice
  for entry in "${PROVIDER_REGISTRY[@]}"; do
    IFS='|' read -r _label _choice _keyflag _models <<< "$entry"
    if [[ "$_choice" == "$AUTH_CHOICE" && -n "$_keyflag" && -n "$API_KEY" ]]; then
      CMD+=($_keyflag "$API_KEY")
      break
    fi
  done

  # Append any extra flags (e.g., --custom-base-url)
  if [[ -n "$EXTRA_FLAGS" ]]; then
    # shellcheck disable=SC2206
    CMD+=($EXTRA_FLAGS)
  fi

  "${CMD[@]}" 2>&1 | tail -3 || true
}

# =============================================================================
# Preflight
# =============================================================================
echo ""
echo -e "${GN}============================================${CL}"
echo -e "${GN}  OpenClaw Post-Install Wizard${CL}"
echo -e "${GN}============================================${CL}"
echo ""

if ! command -v openclaw &>/dev/null; then
  msg_error "openclaw not found in PATH. Is OpenClaw installed?"
  msg_info "Expected at: ~/.npm-global/bin/openclaw"
  exit 1
fi
msg_ok "OpenClaw $(openclaw --version 2>&1 | head -1) detected"

if [[ ! -f "$OC_CONFIG" ]]; then
  msg_error "Config not found at $OC_CONFIG"
  msg_info "Run the install script first: bash openclaw-install.sh"
  exit 1
fi
msg_ok "Config file found"

# =============================================================================
# Step 1: AI Providers
# =============================================================================
step_ai_providers() {
  msg_step "Step 1/6: AI Model Providers"

  if $SKIP_PROVIDERS; then
    msg_warn "Skipped (--skip-providers)"
    return 0
  fi

  # Show currently registered providers
  local REGISTERED=()
  if [[ -f "$AUTH_PROFILES" ]]; then
    while IFS= read -r p; do
      REGISTERED+=("$p")
    done < <(jq -r '.profiles | keys[]' "$AUTH_PROFILES" 2>/dev/null)
  fi

  if [[ ${#REGISTERED[@]} -gt 0 ]]; then
    msg_info "Currently registered providers:"
    for p in "${REGISTERED[@]}"; do
      msg_dim "  - $p"
    done
    echo ""
  fi

  # --- CLI flag mode: register providers passed via --provider / --provider-key
  if [[ ${#CLI_PROVIDERS[@]} -gt 0 ]]; then
    for i in "${!CLI_PROVIDERS[@]}"; do
      local choice="${CLI_PROVIDERS[$i]}"
      local key="${CLI_PROVIDER_KEYS[$i]:-}"
      local extra=""
      [[ "$choice" == "ollama" && -n "$OLLAMA_BASE_URL" ]] && extra="--custom-base-url $OLLAMA_BASE_URL"
      [[ "$choice" == "custom-api-key" && -n "$CUSTOM_BASE_URL" ]] && extra="--custom-base-url $CUSTOM_BASE_URL"

      msg_info "Registering provider: ${choice}..."
      register_provider "$choice" "$key" "$extra"
      msg_ok "Registered: ${choice}"
    done
    return 0
  fi

  # --- Interactive mode: show menu
  if $NON_INTERACTIVE; then
    msg_warn "Non-interactive mode: use --provider/--provider-key flags to add providers"
    return 0
  fi

  echo ""
  msg_info "Select AI providers to configure (you can add multiple):"
  echo ""

  local DONE=false
  while ! $DONE; do
    # Print numbered menu
    for i in "${!PROVIDER_REGISTRY[@]}"; do
      IFS='|' read -r label _choice _keyflag models <<< "${PROVIDER_REGISTRY[$i]}"
      local NUM=$((i + 1))
      # Check if already registered
      local STATUS=" "
      for p in "${REGISTERED[@]}"; do
        if [[ "$p" == *"${_choice%%%-*}"* ]]; then
          STATUS="${GN}\xE2\x9C\x94${CL}"
          break
        fi
      done
      printf "   ${BL}%2d${CL}) %b %s  ${DM}%s${CL}\n" "$NUM" "$STATUS" "$label" "$models"
    done
    echo ""
    printf "   ${BL}Pick a number (or 'd' when done, 's' to skip)${CL}: "
    read -r CHOICE

    case "${CHOICE,,}" in
      d|done) DONE=true; continue ;;
      s|skip) msg_warn "Provider setup skipped"; return 0 ;;
      ''    ) continue ;;
    esac

    # Validate number
    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [[ "$CHOICE" -lt 1 || "$CHOICE" -gt ${#PROVIDER_REGISTRY[@]} ]]; then
      msg_warn "Invalid selection"
      continue
    fi

    local IDX=$((CHOICE - 1))
    IFS='|' read -r LABEL AUTH_CHOICE KEY_FLAG EXAMPLE_MODELS <<< "${PROVIDER_REGISTRY[$IDX]}"

    echo ""
    msg_info "Setting up: ${LABEL}"
    msg_dim "Example models: ${EXAMPLE_MODELS}"

    local PROVIDER_KEY=""
    local EXTRA_FLAGS=""

    if [[ "$AUTH_CHOICE" == "ollama" ]]; then
      # Ollama: no API key, just base URL
      local OLLAMA_URL="http://localhost:11434"
      prompt_value OLLAMA_URL "Ollama base URL" "http://localhost:11434"
      if [[ "$OLLAMA_URL" != "http://localhost:11434" ]]; then
        EXTRA_FLAGS="--custom-base-url $OLLAMA_URL"
      fi
    elif [[ "$AUTH_CHOICE" == "custom-api-key" ]]; then
      # Custom: need base URL + optional key
      local CUST_URL=""
      prompt_value CUST_URL "Base URL (OpenAI-compatible endpoint)"
      prompt_value PROVIDER_KEY "API key (leave blank if none)" "" "true"
      [[ -n "$CUST_URL" ]] && EXTRA_FLAGS="--custom-base-url $CUST_URL --custom-compatibility openai"
    else
      # Standard provider: need API key
      prompt_value PROVIDER_KEY "API key" "" "true"
      if [[ -z "$PROVIDER_KEY" ]]; then
        msg_warn "No key provided, skipping ${LABEL}"
        echo ""
        continue
      fi
    fi

    msg_info "Registering ${LABEL}..."
    register_provider "$AUTH_CHOICE" "$PROVIDER_KEY" "$EXTRA_FLAGS"
    msg_ok "Registered: ${LABEL}"

    # Track it as registered for the checkmark display
    REGISTERED+=("${AUTH_CHOICE}:default")

    # Also write key to .env for providers that benefit from env-level access
    if [[ -n "$PROVIDER_KEY" ]]; then
      local ENV_VAR_NAME=""
      case "$AUTH_CHOICE" in
        anthropic-api-key)   ENV_VAR_NAME="ANTHROPIC_API_KEY" ;;
        openai-api-key)      ENV_VAR_NAME="OPENAI_API_KEY" ;;
        openrouter-api-key)  ENV_VAR_NAME="OPENROUTER_API_KEY" ;;
        gemini-api-key)      ENV_VAR_NAME="GEMINI_API_KEY" ;;
        deepseek-api-key)    ENV_VAR_NAME="DEEPSEEK_API_KEY" ;;
        xai-api-key)         ENV_VAR_NAME="XAI_API_KEY" ;;
        mistral-api-key)     ENV_VAR_NAME="MISTRAL_API_KEY" ;;
        together-api-key)    ENV_VAR_NAME="TOGETHER_API_KEY" ;;
      esac
      if [[ -n "$ENV_VAR_NAME" ]]; then
        # Append/replace in .env
        touch "$OC_ENV"
        if grep -q "^${ENV_VAR_NAME}=" "$OC_ENV" 2>/dev/null; then
          sed -i "s|^${ENV_VAR_NAME}=.*|${ENV_VAR_NAME}=${PROVIDER_KEY}|" "$OC_ENV"
        else
          echo "${ENV_VAR_NAME}=${PROVIDER_KEY}" >> "$OC_ENV"
        fi
        chmod 600 "$OC_ENV"
      fi
    fi

    echo ""
  done
}

# =============================================================================
# Step 2: Model Assignment
# =============================================================================
step_model_config() {
  msg_step "Step 2/6: Model Assignment"

  # Show current config
  local CURRENT_PRIMARY CURRENT_FALLBACKS CURRENT_HEARTBEAT
  CURRENT_PRIMARY=$(jq -r '.agents.defaults.model.primary // .agents.defaults.model // "not set"' "$OC_CONFIG" 2>/dev/null)
  CURRENT_FALLBACKS=$(jq -r '(.agents.defaults.model.fallbacks // []) | join(", ")' "$OC_CONFIG" 2>/dev/null)
  CURRENT_HEARTBEAT=$(jq -r '.agents.defaults.heartbeat.model // "not set"' "$OC_CONFIG" 2>/dev/null)

  msg_info "Current model config:"
  msg_dim "  Primary:   ${CURRENT_PRIMARY}"
  msg_dim "  Fallbacks: ${CURRENT_FALLBACKS:-none}"
  msg_dim "  Heartbeat: ${CURRENT_HEARTBEAT}"
  echo ""

  if $NON_INTERACTIVE && [[ -z "$PRIMARY_MODEL" && -z "$FALLBACK_MODELS" && -z "$HEARTBEAT_MODEL" ]]; then
    msg_info "No model overrides provided. Keeping current config."
    return 0
  fi

  # Primary model
  if [[ -z "$PRIMARY_MODEL" ]] && ! $NON_INTERACTIVE; then
    msg_info "Set primary model (provider/model format)."
    msg_dim "Examples: anthropic/claude-sonnet-4-5, gemini/gemini-2.5-flash, ollama/llama4"
    prompt_value PRIMARY_MODEL "Primary model" "$CURRENT_PRIMARY"
  fi

  if [[ -n "$PRIMARY_MODEL" && "$PRIMARY_MODEL" != "$CURRENT_PRIMARY" ]]; then
    openclaw config set agents.defaults.model.primary "$PRIMARY_MODEL" >/dev/null 2>&1
    msg_ok "Primary model set: ${PRIMARY_MODEL}"
  else
    msg_ok "Primary model unchanged: ${CURRENT_PRIMARY}"
  fi

  # Fallback models
  if [[ -z "$FALLBACK_MODELS" ]] && ! $NON_INTERACTIVE; then
    msg_info "Set fallback models (comma-separated, or blank to keep current)."
    msg_dim "Example: openai/gpt-5-mini, openrouter/google/gemini-3-flash-preview"
    prompt_value FALLBACK_MODELS "Fallback models" ""
  fi

  if [[ -n "$FALLBACK_MODELS" ]]; then
    # Convert CSV to JSON array
    local FB_JSON
    FB_JSON=$(echo "$FALLBACK_MODELS" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | jq -R . | jq -s .)
    jq --argjson fb "$FB_JSON" '.agents.defaults.model.fallbacks = $fb' "$OC_CONFIG" > "${OC_CONFIG}.tmp"
    mv "${OC_CONFIG}.tmp" "$OC_CONFIG"
    chmod 600 "$OC_CONFIG"
    msg_ok "Fallback models set: ${FALLBACK_MODELS}"
  fi

  # Heartbeat model (cheap/fast model for periodic pings)
  if [[ -z "$HEARTBEAT_MODEL" ]] && ! $NON_INTERACTIVE; then
    msg_info "Heartbeat model (cheap/fast model for background tasks)."
    msg_dim "Example: openai/gpt-5-nano, gemini/gemini-2.5-flash, ollama/llama4-scout"
    prompt_value HEARTBEAT_MODEL "Heartbeat model" "$CURRENT_HEARTBEAT"
  fi

  if [[ -n "$HEARTBEAT_MODEL" && "$HEARTBEAT_MODEL" != "$CURRENT_HEARTBEAT" ]]; then
    openclaw config set agents.defaults.heartbeat.model "$HEARTBEAT_MODEL" >/dev/null 2>&1
    msg_ok "Heartbeat model set: ${HEARTBEAT_MODEL}"
  else
    msg_ok "Heartbeat model unchanged: ${CURRENT_HEARTBEAT}"
  fi
}

# =============================================================================
# Step 3: Embeddings Key (OpenAI for memory)
# =============================================================================
step_embeddings() {
  msg_step "Step 3/6: Memory Embeddings (OpenAI)"

  msg_dim "OpenClaw uses OpenAI's text-embedding-3-small for semantic memory search."
  msg_dim "This is separate from your AI model providers."

  local EXISTING_OPENAI=""
  if [[ -f "$OC_ENV" ]]; then
    EXISTING_OPENAI=$(grep -oP '^OPENAI_API_KEY=\K.*' "$OC_ENV" 2>/dev/null || true)
  fi
  [[ -z "$EXISTING_OPENAI" ]] && EXISTING_OPENAI="${OPENAI_API_KEY:-}"

  if [[ -n "$EXISTING_OPENAI" && -z "$OPENAI_KEY" ]]; then
    msg_ok "OpenAI API key already set in .env (memory search active)"
    return 0
  fi

  prompt_value OPENAI_KEY "OpenAI API key for embeddings" "" "true"

  if [[ -n "$OPENAI_KEY" ]]; then
    touch "$OC_ENV"
    if grep -q "^OPENAI_API_KEY=" "$OC_ENV" 2>/dev/null; then
      sed -i "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=${OPENAI_KEY}|" "$OC_ENV"
    else
      echo "OPENAI_API_KEY=${OPENAI_KEY}" >> "$OC_ENV"
    fi
    chmod 600 "$OC_ENV"
    msg_ok "OpenAI key written to .env (memory search enabled)"
  else
    msg_warn "No key provided. Semantic memory search will be disabled."
    msg_info "Set later: echo 'OPENAI_API_KEY=sk-...' >> ~/.openclaw/.env"
  fi
}

# =============================================================================
# Step 4: Telegram Bot
# =============================================================================
step_telegram() {
  msg_step "Step 4/6: Telegram Bot"

  local CURRENT_TOKEN
  CURRENT_TOKEN=$(jq -r '.channels.telegram.botToken // ""' "$OC_CONFIG" 2>/dev/null)

  if [[ "$CURRENT_TOKEN" == "__TELEGRAM_BOT_TOKEN__" || -z "$CURRENT_TOKEN" ]]; then
    msg_warn "Telegram bot token is not configured"

    if [[ -z "$TELEGRAM_TOKEN" ]] && ! $NON_INTERACTIVE; then
      echo ""
      msg_info "To get a bot token:"
      msg_info "  1. Open Telegram and message @BotFather"
      msg_info "  2. Send /newbot and follow the prompts"
      msg_info "  3. Copy the token (format: 123456789:ABCdef...)"
      echo ""
      prompt_value TELEGRAM_TOKEN "Telegram bot token" "" "true"
    fi

    if [[ -n "$TELEGRAM_TOKEN" ]]; then
      openclaw config set channels.telegram.botToken "$TELEGRAM_TOKEN" >/dev/null 2>&1
      msg_ok "Telegram bot token configured"
    else
      msg_warn "No token provided. Telegram will not work."
      msg_info "  Set later: openclaw config set channels.telegram.botToken YOUR_TOKEN"
    fi
  else
    msg_ok "Telegram bot token already configured"
  fi

  # Telegram user ID (DM allowlist)
  local CURRENT_ALLOW
  CURRENT_ALLOW=$(jq -r '.channels.telegram.allowFrom // [] | length' "$OC_CONFIG" 2>/dev/null)

  if [[ "$CURRENT_ALLOW" -eq 0 ]]; then
    msg_warn "No Telegram users in allowFrom (nobody can DM the bot)"

    if [[ -z "$TELEGRAM_USER_ID" ]] && ! $NON_INTERACTIVE; then
      echo ""
      msg_info "To find your Telegram user ID:"
      msg_info "  1. Message @userinfobot on Telegram"
      msg_info "  2. It will reply with your numeric ID"
      echo ""
      prompt_value TELEGRAM_USER_ID "Your Telegram user ID (numeric)"
    fi

    if [[ -n "$TELEGRAM_USER_ID" ]]; then
      local TMP_CONFIG
      TMP_CONFIG=$(jq --arg uid "$TELEGRAM_USER_ID" \
        '.channels.telegram.allowFrom = (.channels.telegram.allowFrom // []) + [$uid] | .channels.telegram.allowFrom |= unique' \
        "$OC_CONFIG")
      echo "$TMP_CONFIG" > "$OC_CONFIG"
      chmod 600 "$OC_CONFIG"
      msg_ok "Telegram user ${TELEGRAM_USER_ID} added to allowFrom"
    else
      msg_warn "No user ID provided. Configure DM access later."
    fi
  else
    msg_ok "Telegram allowFrom has ${CURRENT_ALLOW} user(s)"
  fi
}

# =============================================================================
# Step 5: Tailscale
# =============================================================================
step_tailscale() {
  msg_step "Step 5/6: Tailscale"

  if $SKIP_TAILSCALE; then
    msg_warn "Skipped (--skip-tailscale)"
    return 0
  fi

  if ! command -v tailscale &>/dev/null; then
    msg_warn "Tailscale not installed. Skipping."
    return 0
  fi

  local TS_STATUS
  TS_STATUS=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "Unknown"' 2>/dev/null || echo "Unknown")

  if [[ "$TS_STATUS" == "Running" ]]; then
    local TS_IP
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
    msg_ok "Tailscale connected (${TS_IP})"
  else
    msg_warn "Tailscale not connected (state: ${TS_STATUS})"

    if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
      msg_info "Authenticating with provided auth key..."
      sudo tailscale up --auth-key="$TAILSCALE_AUTH_KEY" 2>&1 || {
        msg_error "Tailscale auth failed. Try: sudo tailscale up"
        return 0
      }
      msg_ok "Tailscale authenticated"
    elif ! $NON_INTERACTIVE; then
      if prompt_yesno "Start Tailscale authentication now?"; then
        msg_info "Follow the URL to authenticate in your browser."
        echo ""
        sudo tailscale up 2>&1 || {
          msg_error "Tailscale auth failed. Try later: sudo tailscale up"
          return 0
        }
        msg_ok "Tailscale authenticated"
      else
        msg_warn "Skipped. Run later: sudo tailscale up"
        return 0
      fi
    else
      msg_warn "Non-interactive: provide --tailscale-auth-key to authenticate"
      return 0
    fi
  fi

  # Tailscale Serve
  local TS_SERVE_STATUS
  TS_SERVE_STATUS=$(sudo tailscale serve status 2>&1 || true)

  if echo "$TS_SERVE_STATUS" | grep -q "18789"; then
    msg_ok "Tailscale Serve already forwarding port 18789"
  else
    msg_info "Enabling Tailscale Serve for gateway (port 18789)..."
    sudo tailscale serve --bg 18789 2>&1 || {
      msg_warn "Failed. Run manually: sudo tailscale serve --bg 18789"
      return 0
    }
    msg_ok "Tailscale Serve enabled"
  fi
}

# =============================================================================
# Step 6: Finalize
# =============================================================================
step_finalize() {
  msg_step "Step 6/6: Finalize"

  # Offer SOUL.md edit
  if ! $SKIP_SOUL; then
    local SOUL_FILE="${OC_DIR}/workspace/SOUL.md"
    if [[ -f "$SOUL_FILE" ]]; then
      if grep -q "Your name and personality should be configured" "$SOUL_FILE" 2>/dev/null || \
         grep -q "your-agent-name" "$SOUL_FILE" 2>/dev/null; then
        msg_warn "SOUL.md still has default content"
        if ! $NON_INTERACTIVE; then
          if prompt_yesno "Open SOUL.md in an editor now?" "n"; then
            ${EDITOR:-nano} "$SOUL_FILE"
            msg_ok "SOUL.md edited"
          else
            msg_info "Edit later: nano ~/.openclaw/workspace/SOUL.md"
          fi
        fi
      else
        msg_ok "SOUL.md customized"
      fi
    fi
  fi

  # Restart gateway
  msg_info "Restarting gateway..."
  systemctl --user restart openclaw-gateway.service 2>/dev/null || {
    msg_warn "Gateway restart failed. Try: systemctl --user restart openclaw-gateway.service"
  }
  sleep 2

  local GW_STATUS
  GW_STATUS=$(systemctl --user is-active openclaw-gateway.service 2>/dev/null || echo "unknown")
  if [[ "$GW_STATUS" == "active" ]]; then
    msg_ok "Gateway running"
  else
    msg_warn "Gateway status: ${GW_STATUS}"
  fi

  # Doctor
  msg_info "Running openclaw doctor --fix..."
  openclaw doctor --fix 2>&1 | tail -5 || true
  msg_ok "Doctor completed"

  # Git commit
  if [[ -d "${OC_DIR}/.git" ]]; then
    cd "$OC_DIR"
    git add -A 2>/dev/null || true
    git commit -q -m "config: post-install wizard $(date +%Y-%m-%d)" 2>/dev/null || true
    msg_ok "Config committed to git"
  fi
}

# =============================================================================
# Summary
# =============================================================================
print_summary() {
  echo ""
  echo -e "${GN}============================================${CL}"
  echo -e "${GN}  Post-Install Complete${CL}"
  echo -e "${GN}============================================${CL}"
  echo ""

  local ISSUES=()

  # Providers
  local PROVIDER_COUNT=0
  if [[ -f "$AUTH_PROFILES" ]]; then
    PROVIDER_COUNT=$(jq '.profiles | length' "$AUTH_PROFILES" 2>/dev/null || echo 0)
  fi
  if [[ "$PROVIDER_COUNT" -gt 0 ]]; then
    msg_ok "${PROVIDER_COUNT} AI provider(s) registered"
  else
    ISSUES+=("Add an AI provider: re-run this wizard or openclaw configure --section model")
  fi

  # Model config
  local PM
  PM=$(jq -r '.agents.defaults.model.primary // .agents.defaults.model // "not set"' "$OC_CONFIG" 2>/dev/null)
  msg_ok "Primary model: ${PM}"

  # Embeddings
  if [[ -f "$OC_ENV" ]] && grep -q "^OPENAI_API_KEY=" "$OC_ENV" 2>/dev/null; then
    msg_ok "Memory embeddings: configured"
  else
    ISSUES+=("Set OPENAI_API_KEY in ~/.openclaw/.env (for memory/embeddings)")
  fi

  # Telegram
  local TG_TOKEN
  TG_TOKEN=$(jq -r '.channels.telegram.botToken // ""' "$OC_CONFIG" 2>/dev/null)
  if [[ -n "$TG_TOKEN" && "$TG_TOKEN" != "__TELEGRAM_BOT_TOKEN__" ]]; then
    msg_ok "Telegram: configured"
  else
    ISSUES+=("Configure Telegram: openclaw config set channels.telegram.botToken TOKEN")
  fi

  # Tailscale
  if tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null 2>&1; then
    msg_ok "Tailscale: connected ($(tailscale ip -4 2>/dev/null))"
  else
    ISSUES+=("Connect Tailscale: sudo tailscale up")
  fi

  # Gateway
  if systemctl --user is-active openclaw-gateway.service >/dev/null 2>&1; then
    msg_ok "Gateway: running"
  else
    ISSUES+=("Start gateway: openclaw gateway start")
  fi

  if [[ ${#ISSUES[@]} -gt 0 ]]; then
    echo ""
    msg_warn "Still needs attention:"
    for issue in "${ISSUES[@]}"; do
      echo -e "   ${YW}\xe2\x80\xa2${CL} ${issue}"
    done
  fi

  echo ""
  echo -e "  ${BL}openclaw doctor --fix${CL}       Health check"
  echo -e "  ${BL}openclaw gateway status${CL}     Gateway info"
  echo -e "  ${BL}openclaw logs --follow${CL}      Live logs"
  echo -e "  ${BL}openclaw tui${CL}                Terminal UI"
  echo ""
}

# =============================================================================
# Main
# =============================================================================
main() {
  step_ai_providers
  step_model_config
  step_embeddings
  step_telegram
  step_tailscale
  step_finalize
  print_summary
}

main "$@"
