# OpenClaw Post-Install Audit

You are running on a freshly installed OpenClaw container. The install script handled system packages, user creation, Node.js, OpenClaw install, config templates, memory plugin, Tailscale, backups, and basic hardening.

Your job: audit the environment, fix everything that's broken, and produce a detailed report of what you found and what you did.

## Audit Checklist

Run through each of these. For every item, report: PASS, FAIL (with what's wrong), or FIXED (with what you did).

### 1. Environment & PATH
- Is `openclaw` in PATH for the `claw` user when logged in via SSH?
- Is `node` in PATH? What version?
- Is `npm` in PATH?
- Does `which openclaw` resolve? Where does it point?
- Check both `~/.bashrc` and `~/.profile` for PATH exports
- Check if `/etc/profile.d/` has anything relevant
- If openclaw is NOT in PATH, find where it was installed (`find / -name openclaw -type f 2>/dev/null`) and fix the PATH

### 2. OpenClaw Core
- Does `openclaw --version` work?
- Does `openclaw doctor --fix` pass? Capture full output.
- Does `openclaw gateway status` show the gateway running?
- Is the gateway systemd user service enabled? (`systemctl --user status openclaw-gateway.service`)
- Does `openclaw security audit --deep` pass? Capture output.

### 3. Config Integrity
- Does `~/.openclaw/openclaw.json` exist and parse as valid JSON?
- Does it have a `meta` section? (If not, `openclaw doctor` hasn't been run yet)
- Is the gateway token populated (not `__GATEWAY_TOKEN__`)?
- Is the Telegram bot token still a placeholder (`__TELEGRAM_BOT_TOKEN__`)? That's expected — just confirm.
- File permissions: is `openclaw.json` mode 600? Is `~/.openclaw/` mode 700?

### 4. Memory Plugin
- Does `~/.openclaw/workspace/skills/memory-lancedb-hybrid/` exist?
- Does it have a `node_modules/` directory?
- Does `openclaw skills list` show it?
- Is `OPENAI_API_KEY` needed for embeddings? Is there an `.env` file or guidance for where to put it?

### 5. Workspace Files
- Do these exist: `~/.openclaw/workspace/SOUL.md`, `AGENTS.md`, `USER.md`?
- Are they owned by the `claw` user?

### 6. Networking & Gateway
- Is the gateway bound to loopback only? (`ss -tlnp | grep 18789`)
- Is Tailscale installed? (`tailscale --version`)
- Is tailscaled running? (`systemctl status tailscaled`)
- Can the gateway reach external APIs? (`curl -sS -o /dev/null -w '%{http_code}' https://api.anthropic.com`)

### 7. Systemd & Services
- Is user lingering enabled for `claw`? (`ls /var/lib/systemd/linger/`)
- Does `XDG_RUNTIME_DIR` exist for the claw user? (`ls -la /run/user/$(id -u claw)`)
- Can the claw user run `systemctl --user` commands?

### 8. Git Tracking
- Is `~/.openclaw/` a git repo?
- Does `git log` show the initial commit from the install script?
- Is the `.gitignore` properly excluding sessions and logs?

### 9. Cron Jobs
- Does `crontab -l` (as claw user) show the backup and cleanup crons?
- Does the backup script exist at `~/bin/backup-openclaw.sh` and is it executable?

### 10. SSH & Access
- Can you confirm SSH is listening?
- Is password auth enabled in sshd_config?

## Output Format

When you're done, create a file at `~/audit-report.txt` with:

```
# OpenClaw Post-Install Audit Report
Date: [date]
Hostname: [hostname]

## Summary
PASS: [count]
FAIL: [count]
FIXED: [count]

## Details
[Each item with PASS/FAIL/FIXED and details]

## Changes Made
[Every file you modified, every command you ran that changed state]
[Include diffs where relevant]

## Recommendations for Install Script
[Things the install script should be doing but isn't]
[Exact commands or code that should be added]
```

Be thorough. Don't skip anything. If you fix something, explain exactly what was wrong and what you did so we can add it to the install script.
