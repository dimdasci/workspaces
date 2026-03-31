Standardized remote workspace for Claude, the AI assistant. 
The workspace is designed for VPS, AWS EC2, and similar environments. It must provide the full toolset for software development in pair with coding agents. 

# Rules
- no marketing fluff and corporate jargon
- information density is more important than readability and grammar
- no pre-existing error and "todos" are allowed in the codebase, production grade quality is required

# Project structure
- `.devcontainer/` — Dockerfile, devcontainer.json, postCreate.sh, KasmVNC config. Consumed by DevPod.
- `scripts/ws-session` — multi-agent session orchestrator (isolated clones, Docker services, port allocation)
- `host-setup.sh` — one-time remote host preparation (Docker, firewall, chezmoi)
- `docs/manual.md` — usage manual
- `docs/multi-agent-sessions.md` — design doc for parallel agent sessions

# Key decisions
- DevPod deploys devcontainer on remote machines via SSH provider
- XFCE + KasmVNC for graphical desktop (replaces desktop-lite + Fluxbox + noVNC)
- Chezmoi + age for secrets and dotfiles (separate private repo)
- Persistent storage at /workspace (EFS on AWS, local disk on VPS)
- SSH tunnel for KasmVNC access (port 8443 not exposed)
- Parallel agent sessions via ws-session: isolated git clones (--reference, no worktrees), per-session Docker Compose overrides, port allocation for app processes

# Container mount layout
- DevPod mounts repo source to `/workspaces/ec2-ws` (default, do NOT override with workspaceFolder or workspaceMount)
- EFS persistent storage at `/workspace` via explicit bind mount in devcontainer.json
- These are separate paths — do not conflate them
- `postCreateCommand` runs from the repo source dir (`/workspaces/ec2-ws`), uses relative paths
- Shell lands in `/workspace` via `cd /workspace` in `.bash_aliases`

# Chezmoi-managed files (on EFS at /workspace)
- `.bash_aliases` — shell aliases, env vars (COLORTERM), cd to /workspace
- `.tmux.conf` — tmux config
- `.gitconfig` — git identity
- `.claude/` — Claude Code settings
- postCreate.sh symlinks these from /workspace to ~ so the shell picks them up
- Config that modifies the container image goes in Dockerfile/postCreate.sh; user dotfiles go in chezmoi

# Applying changes
- Dockerfile/devcontainer.json changes: `devpod up <ws-name> --recreate` (pulls via postCreate.sh git pull)
- postCreate.sh changes: same — needs `--recreate`
- Chezmoi-managed files (.bash_aliases, .tmux.conf): edit on remote, `chezmoi add`, no rebuild needed
- Remote repo must be up to date before recreate: postCreate.sh does `git pull --ff-only` at start

# currentDate
Today's date is 2026-03-17.
