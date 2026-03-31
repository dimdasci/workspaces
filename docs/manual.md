## Overview

Standardized remote workspace running as a devcontainer on a remote Linux machine (EC2, VPS, or any Ubuntu/Debian host). Provides both a terminal environment and a graphical XFCE desktop with Chromium. Managed via DevPod from your Mac: one command provisions the container, SSH gives you a proper terminal, and KasmVNC over an SSH tunnel gives you the desktop. All project files live on the remote host at `/workspace`; the container is stateless and can be destroyed and recreated without data loss.

---

## Prerequisites

**Mac (local):**
- DevPod: `brew install devpod`
- pngpaste (clipboard image transfer): `brew install pngpaste`
- SSH key at `~/.ssh/id_ed25519` — generate if missing: `ssh-keygen -t ed25519`

**Remote machine:**
- Ubuntu 22.04+ or Debian Bookworm
- SSH access with sudo privileges
- Minimum: 4 GB RAM, 2 vCPU
- Recommended: 8 GB+ RAM for headed Chromium

---

## First-time host setup

Run once per remote machine before creating any workspace.

```bash
# Install Docker, configure sshd, create /workspace
ssh user@my-ec2 'curl -sSL https://raw.githubusercontent.com/dimdasci/workspaces/main/host-setup.sh | bash'

# Copy age key for chezmoi secret decryption
scp ~/.age/key.txt user@my-ec2:~/.config/chezmoi/key.txt

# Bootstrap chezmoi (dotfiles: shell config, tmux, etc.)
ssh user@my-ec2 'chezmoi init --apply <github-username>'
```

---

## Creating a workspace

```bash
devpod provider add ssh        # once per Mac, skip if already added
devpod up ./workspace --provider ssh --option HOST=my-ec2.example.com
```

DevPod clones this repo into the remote host and starts the devcontainer. On first run this takes a few minutes for the image build.

---

## Connecting

### Terminal (primary)

```bash
ssh <ws-name>.devpod
```

tmux attaches automatically on login. Pane splitting and session persistence work out of the box — disconnect and reconnect without losing your session.

### Graphical desktop

```bash
ssh -L <local-port>:localhost:8443 <ws-name>.devpod
```

Pick any free local port (e.g. 9443). Open `https://localhost:<local-port>` in your browser. Password: `vscode`. XFCE desktop with Chromium in the app menu.

KasmVNC requires HTTPS or localhost — the SSH tunnel provides this.

---

## Clipboard

### Terminal (SSH + tmux)

- **Remote → Mac**: OSC-52 protocol, automatic in iTerm2, Ghostty, and Alacritty. Configured in `tmux.conf` — copy in tmux sends to your local clipboard.
- **Mac → Remote**: Cmd+V works by default via the terminal emulator.

### Desktop (KasmVNC)

Bidirectional text and image clipboard via the browser Clipboard API. Requires HTTPS or localhost — satisfied by the SSH tunnel.

### Images Mac → Remote (for Claude Code)

Ctrl+V image paste does not work over SSH. Use `pngpaste` to save the clipboard image and `scp` it into the container:

```bash
# Add to ~/.zshrc on Mac:
alias ws1-img='f=$(date +%Y%m%d-%H%M%S).png; pngpaste /tmp/$f && scp /tmp/$f <ws-name>.devpod:/workspace/.clipboard/$f && echo "/workspace/.clipboard/$f"'
```

Copy image to clipboard, run `ws1-img` in any Mac terminal. The path printed is valid inside the container. Pass it to Claude. Uses DevPod's SSH tunnel — no port configuration needed.

---

## Mac shell aliases

Add to `~/.zshrc`:

```bash
alias ws1='ssh ec2-ws.devpod'
alias ws1-vnc='ssh -L 9443:localhost:8443 ec2-ws.devpod'
alias ws1-img='f=$(date +%Y%m%d-%H%M%S).png; pngpaste /tmp/$f && scp /tmp/$f ec2-ws.devpod:/workspace/.clipboard/$f && echo "/workspace/.clipboard/$f"'
```

Replace `ec2-ws` with your workspace name. Pick any free local port for VNC. For a second workspace, duplicate with `ws2`, `ws2-vnc`, `ws2-img`.

---

## Container resources

Container memory and shared memory are configurable via environment variables on the remote host:

| Variable | Default | Purpose |
|---|---|---|
| `WORKSPACE_MEMORY` | `12g` | Container memory limit |
| `WORKSPACE_SHM` | `2g` | Shared memory size |

---

## Multiple workspaces

Each workspace is an independent DevPod environment, optionally on different hosts:

```bash
devpod up ./workspace --provider ssh --option HOST=vps1 --id work-1
devpod up ./workspace --provider ssh --option HOST=vps2 --id work-2

devpod ssh work-1
devpod ssh work-2
```

No port conflicts — container ports are not published to the host. DevPod tunnels all traffic through the host's SSH port (22).

---

## Parallel agent sessions

Run 2-4 Claude Code agents in parallel on the same repo, each with isolated filesystem and Docker services. See `docs/multi-agent-sessions.md` for the full design.

### Setup for a new project

**Step 1: Clone the project as a reference repo**

```bash
git clone https://github.com/org/myproject.git /workspace/repos/myproject
cd /workspace/repos/myproject && git config gc.auto 0
```

`gc.auto=0` prevents garbage collection from removing objects that session clones share via alternates.

**Step 2: Inspect the project's Docker setup**

Find the compose file and note:
- Service names and their `container_name:` values
- Network name and whether it's `external: true`
- Volumes with explicit `name:` fields
- Which `.env` files reference services by container name

```bash
cat docker-compose.yml
cat backend/.env.example   # or wherever the env template is
```

**Step 3: Write `.ws-sessions.yml`**

Create this file in the project repo root. It maps the project's Docker services to session-aware names.

```yaml
compose_file: docker-compose.yml

services:
  postgres:
    container_name: myapp-postgres
  meilisearch:
    container_name: myapp-meilisearch
  minio:
    container_name: myapp-minio
  mailpit:
    container_name: myapp-mailpit

network:
  name: myapp-network
  external: true

volumes:
  pgdata:
    name: myapp-pgdata       # only if the compose file uses explicit name:

env_files:
  - path: backend/.env
    template: backend/.env.example
    vars:
      DATABASE_URL: "postgresql://user:pass@{postgres}:5432/mydb"
      MEILISEARCH_URL: "http://{meilisearch}:7700"
      DOCUMENTS_S3_ENDPOINT: "http://{minio}:9000"
      SMTP_URL: "smtp://{mailpit}:1025"
      PORT: "{backend_port}"

processes:
  backend:
    port_env: PORT
    default_port: 3000
  frontend:
    port_env: VITE_PORT
    default_port: 5173

bootstrap:
  pre: "pnpm install"
  post: "pnpm db:migrate && pnpm db:seed"
  skip_scripts: ["scripts/dev.sh"]
```

Commit this file to the project repo (or keep it in your reference clone if you don't control the repo).

**Step 4: Create sessions**

```bash
# Planner — repo clone only, no services
ws-session create planner --project /workspace/repos/myproject --no-services

# Developer — full stack
ws-session create dev --project /workspace/repos/myproject

# QA — services + backend, no frontend dev servers
ws-session create qa --project /workspace/repos/myproject
```

Each session gets:
- Independent git clone at `/workspace/sessions/<id>/`
- Docker services with prefixed container names on a dedicated network
- Generated `.env` files with correct service hostnames
- CLAUDE.md with session context injected

**Step 5 (optional): Enable peer-to-peer messaging**

If you want agents to send messages to each other (e.g., developer tells QA "feature ready, check table X"), enable claude-peers-mcp:

```bash
export WS_PEERS=1
```

Prerequisites (one-time, in devcontainer image or postCreate.sh):
- Bun: `curl -fsSL https://bun.sh/install | bash`
- claude-peers-mcp: `git clone https://github.com/louislva/claude-peers-mcp /workspace/.tools/claude-peers-mcp && cd /workspace/.tools/claude-peers-mcp && bun install`
- Register MCP server: `claude mcp add --scope user --transport stdio claude-peers -- bun /workspace/.tools/claude-peers-mcp/server.ts`

When `WS_PEERS=1`, the orchestrator auto-starts the broker on first session creation. When unset, everything works normally without messaging.

**Step 6: Launch agents**

```bash
# In tmux, create panes for each agent
cd /workspace/sessions/planner && claude
cd /workspace/sessions/dev && claude
cd /workspace/sessions/qa && claude

# With peer messaging, add the channel flag:
cd /workspace/sessions/dev && claude --dangerously-load-development-channels server:claude-peers
```

Agents must start from their session directory so Claude Code reads the session-aware CLAUDE.md.

**Step 7: Verify**

```bash
ws-session list
# SESSION   STATUS    SERVICES  PORTS
# planner   ready     -         -
# dev       running   4/4       backend:3000 frontend:5173
# qa        running   4/4       backend:3100

# Check services are up
ws-session status dev

# QA can inspect developer's database
ws-session exec qa -- psql "postgresql://user:pass@dev-myapp-postgres:5432/mydb"
```

### Day-to-day operations

```bash
# Switch branch in a session
cd /workspace/sessions/dev && git checkout feature-branch
ws-session refresh dev          # regenerate override if compose file changed

# Restart services after a crash
ws-session services dev restart

# Tear down a session
ws-session destroy qa

# Run a command in session context (sources .session.env automatically)
ws-session exec dev pnpm test
```

### What to put in `.ws-sessions.yml` (cheat sheet)

| Look at | Write in config |
|---|---|
| `container_name:` in docker-compose.yml | `services.<svc>.container_name` |
| `networks:` with `name:` or `external: true` | `network.name`, `network.external` |
| `volumes:` with explicit `name:` field | `volumes.<vol>.name` |
| `.env` files that reference service hostnames | `env_files[].vars` with `{service}` placeholders |
| Dev server commands and their port env vars | `processes` |
| Setup scripts that hardcode container names | `bootstrap.skip_scripts` |

If the project's compose file uses default names (no explicit `container_name:`, no explicit volume `name:`, no `external: true` network), the config is minimal — just the env file mappings.

---

## Destroying and recreating

```bash
devpod delete work-1

# Recreate on the same or a different host
devpod up ./workspace --provider ssh --option HOST=new-host --id work-1
```

The container is stateless. `/workspace` on the host is not touched by `devpod delete`. All project files, `.claude/`, and git repos survive the rebuild.

---

## Persistent storage

| Layer | What persists |
|---|---|
| `/workspace` on host | project files, `.claude/`, git repos, `.clipboard/` |
| Container | nothing — ephemeral, rebuilt on `devpod up` |
| Tool caches | lost on rebuild (npm, pip, go module caches) |

**AWS EC2**: attach EFS and mount at `/workspace` before running `host-setup.sh`. Add to `/etc/fstab`:

```
fs-xxx.efs.region.amazonaws.com:/ /workspace efs _netdev,tls 0 0
```

Install the utils first: `sudo apt-get install -y amazon-efs-utils`

**VPS**: local disk at `/workspace` — persists across rebuilds, lost if you wipe the VPS.

---

## AWS-specific setup

### EFS

Create the filesystem in the same VPC and availability zone as your EC2 instance. Add the mount entry to `/etc/fstab` (see above) before running `host-setup.sh` so `/workspace` is mounted when the container starts.

### IAM instance profile

Attach an IAM role to the EC2 instance with required permissions. The AWS CLI inside the container picks up credentials from the instance metadata service automatically — no static keys or token files needed.

---

## Security

- **Firewall**: port 22 (SSH) only — container ports are not published, accessed via DevPod tunnel.
- **SSH**: key-only auth, no password login, no root login, fail2ban active after `host-setup.sh`.
- **Secrets**: managed via chezmoi + age encryption. No secrets committed to this repo.

---

## Troubleshooting

### SSH host key changed after rebuild

```bash
ssh-keygen -R "<host>"
```

Then reconnect — accept the new key.

### UID mismatch on bind mounts

The container runs as `vscode` (UID 1000). If `/workspace` is owned by a different UID, files will be unreadable or unwritable inside the container. Fix on the host:

```bash
sudo chown -R 1000:1000 /workspace
```

The host user created by `host-setup.sh` is UID 1000 by default. If your host user has a different UID, either re-create the user at UID 1000 or update the container's `remoteUser` UID to match.

### KasmVNC not starting

```bash
cat ~/.vnc/*.log
kasmvncserver -kill :1
kasmvncserver :1 -select-de xfce -depth 24 -geometry 1920x1080
```

### Clipboard not syncing in KasmVNC

The browser Clipboard API requires HTTPS or `localhost`. Verify:
1. SSH tunnel is active (`ssh -L 8443:localhost:8443 my-ec2`)
2. You're accessing `http://localhost:8443` via SSH tunnel (not the remote IP directly)
3. Browser has granted clipboard permissions to the page
