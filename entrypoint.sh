#!/bin/sh
set -e

# Pre-accept the workspace trust dialog so Claude doesn't hang waiting for input
CLAUDE_JSON="${HOME}/.claude.json"
[ -d "$CLAUDE_JSON" ] && rm -rf "$CLAUDE_JSON"
[ -f "$CLAUDE_JSON" ] || echo '{}' > "$CLAUDE_JSON"
node -e "
  const fs = require('fs'), f = process.env.HOME + '/.claude.json';
  const d = JSON.parse(fs.readFileSync(f, 'utf8'));
  d.projects = d.projects || {};
  d.projects['/home/clovis/workspace'] = d.projects['/home/clovis/workspace'] || {};
  d.projects['/home/clovis/workspace'].hasTrustDialogAccepted = true;
  fs.writeFileSync(f, JSON.stringify(d));
"

if [ -n "${GITHUB_TOKEN:-}" ]; then
  git config --global credential.helper \
    '!f() { echo "username=x-token"; echo "password='"$GITHUB_TOKEN"'"; }; f'
  export GH_TOKEN="$GITHUB_TOKEN"
fi

# Start code-server in background if a password is configured
if [ -n "${PASSWORD:-}" ]; then
  code-server --bind-addr 0.0.0.0:8080 --auth password "${HOME}/workspace" &
  echo "entrypoint: code-server started on :8080"
fi

# Telegram plugin — install once, skip forever after
# Sentinel lives inside the channels dir so wiping channels/ triggers a clean reinstall.
_TELEGRAM_SENTINEL="${HOME}/.claude/channels/telegram/.installed"
_TELEGRAM_PLUGIN_DIR="${HOME}/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/telegram"

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
  if [ ! -f "$_TELEGRAM_SENTINEL" ] || [ ! -d "$_TELEGRAM_PLUGIN_DIR" ]; then
    echo "entrypoint: first run — installing Telegram plugin"
    claude plugins install telegram@claude-plugins-official || true
    mkdir -p "${HOME}/.claude/channels/telegram"
    touch "$_TELEGRAM_SENTINEL"
    echo "entrypoint: Telegram plugin installed"
  else
    echo "entrypoint: Telegram plugin already installed, skipping"
  fi
  exec claude --channels plugin:telegram@claude-plugins-official
else
  exec claude
fi
