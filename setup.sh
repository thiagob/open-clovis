#!/usr/bin/env bash
set -euo pipefail

if [ ! -f .env ]; then
  cp .env.example .env
fi

# Read raw value of KEY from .env (strips quotes, inline comments, whitespace)
get_env() {
  sed -n "s/^${1}=//p" .env | sed 's/[[:space:]]*#.*//' | tr -d '"' | xargs 2>/dev/null || true
}

# Write KEY=val to .env, overwriting existing line or appending
set_env() {
  local key=$1 val=$2
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${val}|" .env
  else
    printf '%s=%s\n' "$key" "$val" >> .env
  fi
}

# Prompt for KEY if current value is blank or still a placeholder
prompt_var() {
  local key=$1 label=$2 required=${3:-} current
  current=$(get_env "$key")
  if [ -z "$current" ] || [[ "$current" == your-* ]]; then
    read -rp "${label}: " val
    if [ -n "$val" ]; then
      set_env "$key" "$val"
    elif [ -n "$required" ]; then
      echo "Error: ${key} is required." >&2
      exit 1
    fi
  fi
}

# Auto-generate a random hex value if KEY is blank
generate_if_empty() {
  local key=$1 current
  current=$(get_env "$key")
  if [ -z "$current" ]; then
    set_env "$key" "$(openssl rand -hex 32)"
  fi
}

prompt_var BOT_NAME                "Bot name (e.g. jarbas)"                              required
prompt_var CLAUDE_CODE_OAUTH_TOKEN "Claude OAuth token (from claude.ai/settings)"        required
prompt_var TELEGRAM_BOT_TOKEN      "Telegram bot token (from @BotFather, blank to skip)"
prompt_var GITHUB_TOKEN            "GitHub token (blank to skip)"
prompt_var PASSWORD                "code-server password for VS Code on :8080 (blank to disable)"

prompt_var WAHA_API_KEY             "Waha API key (blank to disable auth)"
prompt_var WAHA_SESSION              "Waha session name"
prompt_var WAHA_DASHBOARD_USERNAME   "Waha dashboard username"
generate_if_empty WAHA_DASHBOARD_PASSWORD
generate_if_empty WHATSAPP_SWAGGER_PASSWORD

generate_if_empty N8N_ENCRYPTION_KEY

echo ""
echo "Done. Edit .env to adjust any remaining values, then:"
echo "  docker compose build"
echo "  docker compose run --rm agent"
