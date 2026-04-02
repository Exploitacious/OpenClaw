# OpenClaw Helper Scripts

Automates the setup of OpenClaw on Proxmox LXC containers or any existing Linux machine.

## What It Does

One command gives you a fully configured OpenClaw environment with:

- Ubuntu 24.04 LTS base (Node.js 22.x via NodeSource, build-essential)
- Dedicated `claw` user with systemd lingering
- OpenClaw installed with gateway service
- Hardened `openclaw.json` with sane defaults (coordinator/worker model pattern, fallback chains, concurrency caps, context pruning, compaction)
- Memory plugin (memory-lancedb-hybrid) for persistent semantic + keyword memory
- Tailscale installed (ready for `tailscale up`)
- Prompt injection defense baked into AGENTS.md
- Security hardening (loopback gateway, log redaction, file permissions, tool policies)
- Git-tracked config directory for rollback
- Automated daily backups with 7-day retention
- 30-day memory file cleanup cron

## Usage

### New Proxmox LXC (creates a container and installs everything)

Run on your Proxmox host:

```bash
bash -c "$(curl -fsSL pveClaw.ivantsov.tech)"
```

The script presents a dialog-based TUI with Simple (recommended) and Advanced modes, creates an LXC container, then runs the install script inside it.

### Existing Linux Machine (installs on what you've already got)

Run directly on any Debian/Ubuntu machine (including an existing LXC container):

```bash
bash -c "$(curl -fsSL setupClaw.ivantsov.tech)"
```

This runs the install script in standalone mode. Templates are fetched from GitHub automatically. Must be run as root.

### Local Clone

If you prefer to clone first or want to customize templates before running:

```bash
git clone https://github.com/Exploitacious/OpenClaw.git
cd OpenClaw
bash openclaw.sh          # Proxmox host — creates LXC + installs
# -- or --
bash openclaw-install.sh  # Inside a machine — installs directly
```

## File Structure

```
openclaw-helper/
├── openclaw.sh              # Proxmox host script (creates LXC + runs install)
├── openclaw-install.sh      # Install script (works standalone or via PVE host)
├── templates/
│   ├── openclaw.json.tpl    # Config template with security defaults
│   ├── soul.md.tpl          # Agent personality scaffold
│   └── agents.md.tpl        # Agent instructions + prompt injection defense
└── README.md
```

## After Installation

1. SSH into the container: `ssh claw@<container-ip>` (password: `openclaw`)
2. **Change the default password immediately**
3. Run `openclaw configure` to set your model providers and API keys
4. Edit `~/.openclaw/openclaw.json` and replace `__TELEGRAM_BOT_TOKEN__` with your bot token
5. Edit `~/.openclaw/workspace/SOUL.md` to define your agent's personality
6. Start Tailscale: `sudo tailscale up && sudo tailscale serve --bg 18789`
7. Pair your Telegram bot and verify with `openclaw doctor --fix`

## Customizing Templates

Edit the files in `templates/` before running the script to customize what ships with every container.

### openclaw.json.tpl

The config template uses placeholder tokens:
- `__GATEWAY_TOKEN__` -- auto-generated during install (random hex)
- `__TELEGRAM_BOT_TOKEN__` -- must be set manually after install

Default model config follows the coordinator/worker pattern from the digitalknk runbook:
cheap primary (Sonnet), explicit fallback chain, concurrency caps, context pruning with 6hr TTL, compaction flush at 40k tokens.

### soul.md.tpl

Agent personality and safety guardrails. Edit this to define who each agent is.

### agents.md.tpl

Behavioral rules and prompt injection defense. Ships with detection patterns for common attacks.

## NemoClaw (Future)

The script architecture supports a future `--nemoclaw` flag that would switch from LXC creation to VM creation and wrap the install with NVIDIA's NemoClaw security stack. Not implemented yet (NemoClaw is still alpha as of March 2026).

## Requirements

**Proxmox mode** (`pveClaw.ivantsov.tech`):
- Proxmox VE 7.x or 8.x
- Root access on the Proxmox host
- Internet access from the container (for package downloads)
- Ubuntu 24.04 LTS template (auto-downloaded if missing)

**Standalone mode** (`setupClaw.ivantsov.tech`):
- Debian/Ubuntu-based Linux (tested on Ubuntu 24.04)
- Root access
- Internet access (for package downloads and template fetch)
