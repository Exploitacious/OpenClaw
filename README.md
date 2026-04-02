# OpenClaw

Automates the deployment and configuration of [OpenClaw](https://openclaw.ai) on Proxmox LXC containers or any Debian/Ubuntu machine.

## What You Get

One command creates a ready-to-use OpenClaw environment:

- Ubuntu 24.04 LTS base with Node.js 22.x and build-essential
- Dedicated `claw` user with passwordless sudo and systemd lingering
- OpenClaw installed with the gateway running as a systemd user service
- Hardened config template (loopback gateway, log redaction, file permissions 600/700, tool policies)
- Memory plugin ([memory-lancedb-hybrid](https://github.com/CortexReach/memory-lancedb-pro)) for persistent semantic + keyword memory
- Tailscale installed and ready for authentication
- Prompt injection defense baked into AGENTS.md
- Git-tracked `~/.openclaw/` config directory for rollback
- Automated daily backups (3 AM, 7-day retention) and 30-day memory cleanup cron
- System-wide PATH via `/etc/profile.d/openclaw.sh` (survives dotfile replacement)
- Node compile cache and `OPENCLAW_NO_RESPAWN` for faster CLI starts on LXC/VM hosts

After install, a post-install wizard handles everything that needs human input: AI providers, model selection, API keys, Telegram bot, and Tailscale auth.

## Quick Start

### Proxmox Host (creates LXC + installs)

```bash
bash -c "$(curl -fsSL pveClaw.ivantsov.tech)"
```

Dialog-based TUI with Simple (recommended) and Advanced modes. Creates an unprivileged LXC with nesting, injects `/dev/net/tun` for Tailscale, then runs the install script inside.

### Existing Linux Machine (installs directly)

```bash
bash -c "$(curl -fsSL setupClaw.ivantsov.tech)"
```

Standalone mode on any Debian/Ubuntu machine. Templates are fetched from GitHub. Must be run as root.

### Local Clone

```bash
git clone https://github.com/Exploitacious/OpenClaw.git
cd OpenClaw
bash openclaw.sh          # On Proxmox host — creates LXC + installs
# or
sudo bash openclaw-install.sh  # On any machine — installs directly
```

## After Installation

1. **Reboot** the container to load PATH and services: `reboot`
2. **SSH in**: `ssh claw@<container-ip>` (password: `openclaw`)
3. **Change the default password**: `passwd`
4. **Run the post-install wizard**:

```bash
bash ~/OpenClaw/openclaw-postinstall.sh
```

The wizard walks through six steps interactively:

| Step | What it does |
|------|-------------|
| AI Providers | Menu to add Anthropic, Gemini, OpenAI, Ollama, DeepSeek, xAI, Mistral, OpenRouter, Together, LiteLLM, or any custom OpenAI-compatible endpoint |
| Model Assignment | Set primary model, fallback chain, and heartbeat (cheap/fast) model |
| Embeddings | OpenAI API key for memory search (text-embedding-3-small) — separate from model providers |
| Telegram | Bot token from @BotFather + your Telegram user ID for DM access |
| Tailscale | Authentication + Tailscale Serve on port 18789 |
| Finalize | SOUL.md editor prompt, gateway restart, `openclaw doctor --fix`, git commit |

All steps detect existing config and skip what's already done. Re-run safely at any time.

### Scripted / Non-Interactive Mode

For automation or repeatable deployments, pass everything as flags:

```bash
bash ~/OpenClaw/openclaw-postinstall.sh \
  --provider anthropic-api-key --provider-key sk-ant-... \
  --provider gemini-api-key --provider-key AIza... \
  --provider ollama \
  --primary-model anthropic/claude-sonnet-4-5 \
  --fallback-models "gemini/gemini-2.5-flash, ollama/llama4" \
  --heartbeat-model openai/gpt-5-nano \
  --openai-key sk-... \
  --telegram-token 123456:ABCdef... \
  --telegram-user-id 5361915599 \
  --tailscale-auth-key tskey-auth-... \
  --non-interactive
```

Use `--provider` / `--provider-key` pairs — repeat for each provider. Ollama and custom endpoints need no key. Run `bash openclaw-postinstall.sh --help` for all flags.

## File Structure

```
OpenClaw/
├── openclaw.sh              # Proxmox host script (creates LXC + runs install)
├── openclaw-install.sh      # Install script (standalone or via Proxmox host)
├── openclaw-postinstall.sh  # Post-install wizard (AI providers, Telegram, Tailscale)
├── templates/
│   ├── openclaw.json.tpl    # Config template (gateway token auto-generated)
│   ├── soul.md.tpl          # Agent personality scaffold
│   └── agents.md.tpl        # Behavioral rules + prompt injection defense
└── README.md
```

## What Gets Installed Where

| Path | Purpose |
|------|---------|
| `~/.openclaw/openclaw.json` | Main config (mode 600) |
| `~/.openclaw/.env` | API keys for providers and embeddings (mode 600) |
| `~/.openclaw/agents/main/agent/auth-profiles.json` | Registered provider credentials |
| `~/.openclaw/workspace/SOUL.md` | Agent personality |
| `~/.openclaw/workspace/AGENTS.md` | Behavioral rules and security instructions |
| `~/.openclaw/workspace/USER.md` | User context for personalization |
| `~/.openclaw/workspace/skills/memory-lancedb-hybrid/` | Memory plugin |
| `~/.config/systemd/user/openclaw-gateway.service` | Gateway systemd service |
| `/etc/profile.d/openclaw.sh` | System-wide PATH for `openclaw` CLI |
| `~/bin/backup-openclaw.sh` | Daily backup script |
| `~/backups/` | Backup tarballs (7-day retention) |

## Customizing Templates

Edit files in `templates/` before running the install script to change what ships with every new container.

### openclaw.json.tpl

Config template with placeholder tokens:
- `__GATEWAY_TOKEN__` — auto-replaced with random hex during install
- `__TELEGRAM_BOT_TOKEN__` — set by the post-install wizard or manually

Default model config: cheap primary (Sonnet 4.5), explicit fallback chain, 4 concurrent agents, 8 concurrent subagents, context pruning with 6h TTL, compaction flush at 40k tokens.

### soul.md.tpl

Agent personality scaffold. Define who the agent is, its communication style, and safety guardrails.

### agents.md.tpl

Behavioral rules and prompt injection defense. Ships with detection patterns for common attacks (instruction override, encoded payloads, typoglycemia, social engineering).

## Useful Commands

```bash
openclaw doctor --fix       # Health check and auto-fix
openclaw gateway status     # Gateway service info
openclaw logs --follow      # Real-time logs
openclaw tui                # Terminal UI
openclaw configure          # Interactive config wizard
openclaw skills list        # Available skills
openclaw security audit     # Security posture check
```

Shell aliases (added by install):
```bash
openclaw-update   # Update OpenClaw + restart gateway
openclaw-logs     # Shortcut for openclaw logs --follow
openclaw-status   # Shortcut for openclaw gateway status
openclaw-backup   # Run backup now
```

## Requirements

**Proxmox mode** (`openclaw.sh`):
- Proxmox VE 7.x or 8.x
- Root access on the Proxmox host
- Internet access from the host and container
- Ubuntu 24.04 LTS template (auto-downloaded if missing)

**Standalone mode** (`openclaw-install.sh`):
- Debian/Ubuntu-based Linux (tested on Ubuntu 24.04)
- Root access
- Internet access

**Post-install wizard** (`openclaw-postinstall.sh`):
- Run as the `claw` user (not root)
- OpenClaw must be installed and in PATH
