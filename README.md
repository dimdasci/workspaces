# workspaces

Open-source dev environment for running multi-agent Claude Code workflows in Docker. Inspired by [Conductor](https://conductor.build), but built to run on Linux as well as macOS, and kept open so anyone can reuse or fork. Configures dev containers, tmux session layout, and Bedrock-backed Claude Code with cross-region inference.

## What it does

- **Multi-agent orchestration** — `ws-session` creates isolated sessions (git clone, Docker services, port allocation) so 2–4 Claude Code agents work in parallel without stepping on each other
- **Devcontainer on any Linux host** — deployed via DevPod over SSH to EC2, VPS, or bare metal
- **Terminal-first** — tmux with session persistence; graphical desktop (XFCE + KasmVNC) available when needed
- **Persistent storage** — project files on EFS (AWS) or local disk survive container rebuilds
- **Dotfiles and secrets** — chezmoi + age, separate private repo

## Architecture

```
Mac (devpod up)
  └── SSH → Remote host (Ubuntu)
       └── Docker container (devcontainer)
            ├── Claude Code agent 1 → /workspace/sessions/dev-1/
            ├── Claude Code agent 2 → /workspace/sessions/qa-1/
            ├── Claude Code agent 3 → /workspace/sessions/plan-1/
            ├── Docker socket → host daemon
            │   ├── dev-1-postgres, dev-1-redis, ...
            │   └── qa-1-postgres, qa-1-redis, ...
            └── tmux (one pane per agent)
```

Each session gets: independent git clone (shared object store via `--reference`), Docker Compose override with prefixed container/network/volume names, generated `.env` files, allocated ports for app processes.

## What's inside the container

| Category | Tools |
|---|---|
| AI/Dev | Claude Code, opencode |
| Runtimes | Node.js/pnpm, Go, Bun |
| Cloud/Infra | AWS CLI, GitHub CLI, Terraform, SSM plugin |
| Desktop | XFCE + KasmVNC + Chromium |
| Shell | tmux, mosh, ripgrep, fzf |
| Media | ffmpeg, imagemagick, exiftool, poppler-utils |
| Data | PostgreSQL client, Docker Compose, yq, jq |

## Quick start

### Prerequisites

**Mac:**
```bash
brew install devpod pngpaste age
devpod context set-options -o SSH_ADD_PRIVATE_KEYS=false
devpod context set-options -o AGENT_INJECT_TIMEOUT=60
```

**Remote:** Ubuntu 22.04+, SSH access, sudo. Minimum 4 GB RAM / 2 vCPU.

### 1. Prepare the host

```bash
# VPS (local /workspace)
ssh ubuntu@<ip> 'curl -sSL https://raw.githubusercontent.com/dimdasci/workspaces/main/host-setup.sh | bash'

# AWS EC2 (EFS for /workspace)
ssh ubuntu@<ip> 'curl -sSL https://raw.githubusercontent.com/dimdasci/workspaces/main/host-setup.sh | bash -s -- --efs <fs-id> <region>'
```

Installs Docker, configures firewall (port 22 only), fail2ban, SSH hardening, mounts storage.

### 2. Deploy the workspace

```bash
devpod provider add ssh --name my-ws \
  -o HOST=ubuntu@<ip> \
  -o EXTRA_FLAGS="-o IdentitiesOnly=yes -i ~/.ssh/<key>.pem"

devpod up github.com/dimdasci/workspaces --provider my-ws --id my-ws --ide none
```

First build ~30 min (ARM). Subsequent rebuilds use Docker cache.

### 3. Connect and authenticate

```bash
ssh my-ws.devpod
gh auth login
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

### 4. Run multi-agent sessions

```bash
# Create isolated sessions for parallel agents
ws-session create dev-1 --project https://github.com/org/repo --ref main
ws-session create qa-1  --project https://github.com/org/repo --ref main

# Each agent runs in its session directory
cd /workspace/sessions/dev-1 && claude
cd /workspace/sessions/qa-1  && claude

# Manage sessions
ws-session list
ws-session status dev-1
ws-session destroy qa-1
```

Sessions read `.ws-sessions.yml` from the repo for Docker service isolation, env var mapping, and bootstrap commands. See [docs/multi-agent-sessions.md](docs/multi-agent-sessions.md).

## Session orchestrator (`ws-session`)

```
ws-session create <id> --project <url|path> [--no-services] [--ref <branch>]
ws-session destroy <id> [--keep-volumes]
ws-session list
ws-session status <id>
ws-session services <id> start|stop|restart
ws-session refresh <id>          # after branch switch
ws-session shell <id>            # cd + source env + rename tmux window
ws-session exec <id> <command>
ws-session env <id>
ws-session peers start|stop|status
```

What `create` does:
1. Clones repo to `/workspace/sessions/<id>/`
2. Reads `.ws-sessions.yml` — maps services, networks, volumes, env vars
3. Generates `docker-compose.override.yml` (prefixed container names, isolated network)
4. Allocates ports for app processes (stride of 100 per session index)
5. Generates `.session.env` and project `.env` files
6. Starts Docker services (`docker compose up -d --wait`)
7. Connects devcontainer to session network
8. Runs bootstrap commands
9. Injects `.claude/CLAUDE.md` with session context (git-excluded)

## Connecting

**Terminal:** `ssh my-ws.devpod`

**Graphical desktop:** `ssh -L 9443:localhost:8443 my-ws.devpod` → open `https://localhost:9443` (password: `vscode`)

**Port forwarding:** `ssh -L 3000:localhost:3000 my-ws.devpod`

**Image clipboard (Mac → remote for Claude):**
```bash
alias ws-img='f=$(date +%Y%m%d-%H%M%S).png; pngpaste /tmp/$f && scp /tmp/$f my-ws.devpod:/workspace/.clipboard/$f && echo "/workspace/.clipboard/$f"'
```

## Lifecycle

| Action | Command |
|---|---|
| Stop container | `devpod stop my-ws` |
| Restart stopped | `devpod up my-ws` |
| Rebuild (Dockerfile changes) | `devpod up my-ws --recreate` |
| Full reset | `devpod delete my-ws` then `devpod up ...` |

`/workspace` survives all of the above.

## Persistent storage layout

| What | Where |
|---|---|
| Project repos, session clones | `/workspace/sessions/`, `/workspace/repos/` |
| Claude config | `/workspace/.claude/` |
| Git config | `/workspace/.gitconfig` |
| gh/opencode config | `/workspace/.config/` |
| Chezmoi source | `/workspace/.chezmoi-source/` |
| Secrets (age key) | `/workspace/.age/` |

## Security

- Firewall: port 22 only — no container ports published
- SSH: key-only auth, no root, fail2ban
- KasmVNC: accessed via SSH tunnel (not exposed)
- Secrets: chezmoi + age, separate private repo
- Docker memory limits auto-calculated from host RAM

## Chezmoi (dotfiles + secrets)

Manages `.bash_aliases`, `.tmux.conf`, `.gitconfig`, Claude settings across workspaces. Encrypted files (API keys, tokens) use age.

```bash
# First time
chezmoi init <user>/stuff --source /workspace/.chezmoi-source --apply

# After editing a file
chezmoi add /workspace/.bash_aliases

# On fresh container (EFS has the source already)
chezmoi apply
```

See the [chezmoi guide in docs/manual.md](docs/manual.md) for full setup.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Too many auth failures" | `devpod context set-options -o SSH_ADD_PRIVATE_KEYS=false` |
| EC2 IP changed | Elastic IP, or `devpod provider set-options my-ws -o HOST=ubuntu@<new-ip>` |
| SSH host key changed | `ssh-keygen -R "<host>"` |
| Docker permission denied | Reconnect: `ssh my-ws.devpod` |
| KasmVNC won't start | `cat /tmp/kasmvnc-start.log`; restart with `kasmvncserver :1 ...` |
| "Error opening terminal: alacritty" | `curl -fsSL "https://raw.githubusercontent.com/alacritty/alacritty/master/extra/alacritty.info" \| tic -x -` |
| No space on device | `docker system prune -a -f && docker builder prune -a -f` |
| Claude colors in tmux | `alias claude="TMUX= command claude"` in `.bash_aliases` |
| postCreate.sh stale | `git pull` on host before `devpod up --recreate` |

## Documentation

- [docs/manual.md](docs/manual.md) — full configuration, AWS IAM, architecture
- [docs/multi-agent-sessions.md](docs/multi-agent-sessions.md) — session orchestrator design
