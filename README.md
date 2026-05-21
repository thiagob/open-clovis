# open-clovis

Clovis is a persistent AI agent built on [Claude Code](https://claude.ai/code), reachable via Telegram. It runs as a Docker container and operates on a dedicated git workspace.

![Clovis answering a question via Telegram](docs/telegram-demo.png)

## Motivation

This project started as an exploration of [openclaw.ai](https://openclaw.ai/) — a cloud-based AI assistant that connects to your email, calendar, todos, and messages. The idea was compelling, but the security implications were not: you are handing a third-party service full access to your Gmail, WhatsApp, and the rest of your personal data, with no real visibility into what it does with it.

The internet has also produced some memorable reminders of what happens when an agent has write access to everything and acts on ambiguous instructions — [like texting your ex](https://www.reddit.com/r/ChatGPT/comments/1sng426/my_openclaw_texted_my_ex/).

Clovis is the alternative: the same concept, but self-hosted, small, and built on Claude Code. You own the container, the credentials never leave your machine, and everything the agent does is visible in git history.

**What it is today:** a Docker wrapper around Claude Code that lets you run a persistent agent reachable via Telegram, using your existing Claude subscription — no API key, no extra cost on top of what you already pay.

**Where it's going:**

- **Easy, reproducible setup** — copy `docker-compose.yml`, fill in `.env`, and have a working agent in minutes ✓
- **MCP tool integrations** — Gmail, Todoist, WhatsApp, Google Calendar, and others will be added incrementally as MCP servers
- **Granular access control** — each MCP tool restricted to read-only by default, so the agent can read your emails without being able to send them, read your calendar without creating events. You decide what it can touch.

> **Compliance note:** Clovis is designed for personal use. If you are considering using it in a work context, your organization may have data governance policies, corporate IT requirements, or regulatory obligations (GDPR, HIPAA, SOC 2, etc.) that govern what tools can access company data. Evaluate accordingly — personal and professional contexts carry very different rules.
>
> **Anthropic Terms of Service:** `CLAUDE_CODE_OAUTH_TOKEN` is a personal OAuth token from your Claude subscription. open-clovis passes it directly to the official `claude` CLI — which is the intended use. The [Consumer Terms of Service](https://www.anthropic.com/legal/consumer-terms) (§2) prohibit sharing account credentials with anyone else, and (§3) prohibit accessing services through automated means except via an API key. open-clovis does neither: it runs the official `claude` binary and each user supplies their own token. What those clauses rule out is building tools that use someone else's subscription token to call Anthropic's API — open-clovis is not that. That said, before running it is worth reviewing your intended use case against the Consumer Terms — if your usage goes beyond personal, interactive use (e.g. fully automated pipelines, team-shared instances, or commercial workflows), switching to a proper Anthropic API key under the Commercial Terms is the safer path.

## Concept

An agent instance is made of two repos:

```
open-clovis         ← the shell: container, auth, Telegram, config
clovis-workspace    ← the workspace: git repo Clovis reads and writes
```

**`open-clovis`** (this repo) is the environment — it defines how the agent runs, how it authenticates, and how it connects to Telegram. You manage this from the host.

**`clovis-workspace`** is where Clovis does its work — a regular git repo mounted into the container at `/home/clovis`. Clovis can read files, write code, make commits, and push. You review what it did via git history.

This separation keeps infra concerns out of the workspace and gives Clovis a clean, auditable place to operate.

## How it works

At startup, the entrypoint registers the official plugin marketplace (`anthropics/claude-plugins-official`) and installs the Telegram plugin — both steps are idempotent and complete in under a second once the data volume is populated. [Bun](https://bun.sh) is required by the Telegram plugin's MCP server and is installed system-wide. [tini](https://github.com/krallin/tini) is used as PID 1 to reap zombie processes that Bun spawns.

n8n runs as a sidecar container and exposes third-party service integrations (Gmail, Google Calendar, Todoist, WhatsApp, and others) as MCP servers that Claude picks up automatically on start.

**code-server** runs inside the agent container as a background process, exposing a browser-based VS Code at `http://localhost:8080`. It shares the same environment, MCP configs, and workspace as the agent — the `claude` CLI is available directly from the integrated terminal.

n8n is a heavier container than the rest of the stack, but it earns its keep in two ways. First, it handles OAuth authentication with Google — connecting to Gmail or Google Calendar through n8n means you go through Google's official consent screen once, and n8n stores and refreshes the credentials for you, without needing to write any auth code. Second, it lets you define exactly which tools the agent can use per integration. You wire up only the nodes you want to expose, and the agent only sees those. This is the practical path to least-privilege access: Claude can read your inbox and create drafts, but if the "Send email" node is not in the workflow, it simply cannot send.

```
                      Telegram API
                           │
                           ▼
 ┌─────────────────────────────────────────────── clovis-net ───────────────────────────────────┐
 │                                                                                              │
 │  ┌──────────────────────────────────────────────────┐                                        │
 │  │                     agent                         │  MCP (HTTP)   ┌──────────────────────┐│
 │  │                                                   │ ────────────► │         n8n          ││
 │  │  Telegram MCP plugin  ◄──►  Claude Code           │               │  :5678               ││──► Google, Gmail
 │  │                                                   │ ◄──────────── │  workflow MCPs       ││    Todoist, ...
 │  │  workspace/  (clovis-workspace, mounted volume)   │               └──────────────────────┘│
 │  │                                                   │  HTTP API     ┌──────────────────────┐│
 │  └───────────────────────────────────────────────────┘ ────────────► │        waha          ││
 │                                                                      │  :3000               ││──► WhatsApp
 │                                                                      └──────────────────────┘│
 └──────────────────────────────────────────────────────────────────────────────────────────────┘
       │ ./data/                                            │ ./n8n-data/      │ ./waha-data/
       ▼ (workspace, .claude/ config)                       ▼ (workflows)      ▼ (WA sessions)
                                            host filesystem  (all gitignored)

  Host browser ─────────────────────────────────────────────► :5678 n8n UI  │  :3000 Waha UI  │  :8080 code-server
```
![n8n Gmail MCP workflow with limited tools — read, draft, no send](docs/n8n-gmail-mcp-workflow.png)

> **Note:** The Telegram plugin requires a compatible Claude plan (Pro, Max, Team, or Enterprise).

## Setup

### 1. Create a working directory

```bash
mkdir clovis && cd clovis
```

### 2. Get `docker-compose.yml`

Download it from this repo:

```bash
curl -fsSL https://raw.githubusercontent.com/open-clovis/open-clovis/main/docker-compose.yml -o docker-compose.yml
```

### 3. Create the data layout

```bash
mkdir -p data/workspace
sudo chown -R 1001:1001 data/
```

### 4. Set up the workspace

To start fresh:

```bash
git -C data/workspace init
```

Or if you have an existing repo, clone it instead:

```bash
git clone https://github.com/<your-username>/clovis-workspace.git data/workspace
```

### 5. Create `.env`

```env
BOT_NAME=clovis
CLAUDE_CODE_OAUTH_TOKEN="your-claude-oauth-token"
TELEGRAM_BOT_TOKEN="your-telegram-bot-token"
GITHUB_TOKEN=your-github-pat
GOG_KEYRING_PASSWORD=your-random-secret
```

Create a bot and get its token from [@BotFather](https://t.me/BotFather) on Telegram (`/newbot`).

`GITHUB_TOKEN` is optional — only needed for Clovis to push commits. Create a token with `repo` scope at [github.com/settings/tokens](https://github.com/settings/tokens).

To get a long-lived OAuth token, run on a machine where you are already logged into Claude Code:

```bash
claude setup-token
```

> Always wrap `CLAUDE_CODE_OAUTH_TOKEN` in double quotes — the token may contain a `#` which `.env` parsers treat as a comment delimiter, silently truncating the value.

### 6. First-time wizard

```bash
docker compose run --rm agent
```

On first start Claude Code will:
1. Ask you to select a login method — choose **Claude account with subscription**
2. Show a URL to complete OAuth in your browser
3. Show a theme/onboarding wizard — complete it fully before exiting

> If you set `TELEGRAM_BOT_TOKEN` in `.env`, the plugin picks it up automatically. If you skipped that env var, run `/telegram:configure <your-botfather-token>` before exiting.

Exit with Ctrl+C.

### 7. Pair your Telegram account and lock down access

Open Telegram and send any message to your bot. It will reply with a pairing code.

Attach to the running container and open a Claude Code session:

```bash
docker compose run --rm agent
```

Once inside the Claude Code prompt (not your bash shell), run:

```
/telegram:access pair <code>
/telegram:access policy allowlist
```

The allowlist is critical: without it, anyone who finds your bot's username can send it messages and interact with your agent. Once enabled, only paired accounts are allowed — everyone else is silently dropped.

See the [Claude Code documentation](https://code.claude.com/docs/en/overview) for full details on how the sender allowlist works.

Exit with Ctrl+C. All state is saved to `./data/` and persists across restarts.

### 8. Add integrations via n8n (optional)

n8n is available at **http://localhost:5678** once the stack is running.

To connect a service (Gmail, Google Calendar, Todoist, WhatsApp, etc.):

1. Open n8n, create a new workflow, add an **MCP Server Trigger** as the first node
2. Add the service nodes as tools under that trigger
3. Activate the workflow — n8n shows the MCP endpoint URL in the trigger node
4. Copy the URL, replace `localhost` with `n8n`: `http://n8n:5678/mcp/your-webhook-id`
5. Uncomment (or add) the matching line in `docker-compose.yml` under `agent.environment`:
   ```yaml
   N8N_MCP_GMAIL: http://n8n:5678/mcp/your-gmail-webhook-id
   N8N_MCP_GCAL: http://n8n:5678/mcp/your-gcal-webhook-id
   ```
6. Restart the agent: `docker compose restart agent`

Claude logs `entrypoint: registered MCP server 'n8n-gmail'` on startup when the var is active. MCP URLs go in `docker-compose.yml` directly — they contain no secrets and the `n8n` hostname only resolves inside the Docker network.

### 9. Access code-server (optional)

code-server starts automatically with the agent and provides a browser-based VS Code at:

**http://localhost:8080**

Log in with the `CODE_SERVER_PASSWORD` from your `.env`. The workspace opens at `/home/clovis/workspace` — the same repo Clovis operates on.

From the integrated terminal you can run `claude` directly, inspect MCP configs in `.mcp.json`, or edit files. All changes are immediately visible to the running agent.

### 10. Run in the background

```bash
docker compose up -d
```

Open Telegram and message your bot. Clovis will respond as if you were using Claude Code in a terminal, with full access to the workspace repo.

## Development

To modify the container itself, clone the repo and use `setup.sh` to automate steps 3 and 5 above. Since `docker-compose.yml` builds from the GitHub URL, override the build context locally with:

### 1. Clone this repo

```bash
git clone https://github.com/open-clovis/open-clovis.git
cd open-clovis
```

Override `docker-compose.yml` with a local `docker-compose.override.yml`:

```yaml
services:
  agent:
    build:
      context: .
```

### 2. Run setup

```bash
./setup.sh
```

The script prompts for credentials and scaffolds `.env`, auto-generating `N8N_ENCRYPTION_KEY`. Then continue from step 4 (set up the workspace) and fill in the remaining `.env` values.

## Configuration

| Variable | Required | Description |
|---|---|---|
| `BOT_NAME` | Yes | Agent name — sets the Docker container name to `open-clovis-<name>` |
| `CLAUDE_CODE_OAUTH_TOKEN` | Yes | Long-lived auth token from `claude setup-token` |
| `TELEGRAM_BOT_TOKEN` | Yes | Bot token from @BotFather |
| `GITHUB_TOKEN` | No | GitHub PAT ([create one](https://github.com/settings/tokens)) — enables `git push` from the workspace |
| `N8N_ENCRYPTION_KEY` | Yes | Encrypts n8n credentials at rest — auto-generated by `setup.sh` |
| `CODE_SERVER_PASSWORD` | Yes | Password for the code-server web UI at `http://localhost:8080` |
| `TZ` | No | Container timezone. Defaults to `America/Sao_Paulo` |

### Volumes

| Host path | Container path | Purpose |
|---|---|---|
| `./data` | `/home/clovis` | Home dir — holds `.claude/` config, `.claude.json`, and the workspace repo |
| `./n8n-data` | `/home/node/.n8n` | n8n workflows, credentials, and settings (n8n container) |

### Ports

| Port | Service | Purpose |
|---|---|---|
| `5678` | n8n | Workflow automation UI |
| `3000` | waha | WhatsApp API / Swagger UI |
| `8080` | agent (code-server) | Browser-based VS Code |

## Commands

```bash
docker compose run --rm agent     # interactive session (first-time wizard, pairing) — runs entrypoint.sh
docker compose up -d              # start in background
docker compose logs -f            # follow logs
docker compose down               # stop (state preserved in ./data/)
docker compose exec agent sh      # shell into the running container (entrypoint already ran — git credentials and gogcli are set up)
docker compose run --rm agent sh  # raw shell in a new container — bypasses entrypoint.sh (no git credentials, no gogcli setup)
```

