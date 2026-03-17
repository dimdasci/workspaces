Standardized remote workspace for Claude, the AI assistant. 
The workspace is designed for VPS, AWS EC2, and similar environments. It must provide the full toolset for software development in pair with coding agents. 

# Rules
- no marketing fluff and corporate jargon
- information density is more important than readability and grammar
- no pre-existing error and "todos" are allowed in the codebase, production grade quality is required

# Project structure
- `.devcontainer/` — Dockerfile, devcontainer.json, postCreate.sh, KasmVNC config. Consumed by DevPod.
- `host-setup.sh` — one-time remote host preparation (Docker, firewall, chezmoi)
- `docs/manual.md` — usage manual

# Key decisions
- DevPod deploys devcontainer on remote machines via SSH provider
- XFCE + KasmVNC for graphical desktop (replaces desktop-lite + Fluxbox + noVNC)
- Chezmoi + age for secrets and dotfiles (separate private repo)
- Persistent storage at /workspace (EFS on AWS, local disk on VPS)
- SSH tunnel for KasmVNC access (port 8443 not exposed)

# currentDate
Today's date is 2026-03-17.
