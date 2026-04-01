## Overview

Standardized remote workspace running as a devcontainer on a remote Linux machine (EC2, VPS, or any Ubuntu/Debian host). Provides both a terminal environment and a graphical XFCE desktop with Chromium. Managed via DevPod from your Mac: one command provisions the container, SSH gives you a proper terminal, and KasmVNC over an SSH tunnel gives you the desktop. All project files live on the remote host at `/workspace`; the container is stateless and can be destroyed and recreated without data loss.

---

## Prerequisites

**Mac (local):**
- DevPod: `brew install devpod`
- pngpaste (clipboard image transfer): `brew install pngpaste`
- SSH key pair for the remote host (`.pem` from AWS or `id_ed25519`)
- age key at `~/.age/key.txt` for chezmoi secret decryption

**Remote machine:**
- Ubuntu 22.04 (22.04 only — 24.04 has known issues with this setup)
- SSH access with sudo privileges
- Minimum: 4 GB RAM, 2 vCPU
- Recommended: 8 GB+ RAM for headed Chromium

---

## First-time host setup

Run once per remote machine before creating any workspace.

```bash
# Install Docker, configure sshd, mount storage at /workspace
# VPS (local disk):
ssh user@my-ec2 'curl -sSL https://raw.githubusercontent.com/dimdasci/workspaces/main/host-setup.sh | bash'
# AWS EC2 with EBS (attach volume first, appears as /dev/nvme1n1 on Nitro):
ssh user@my-ec2 'curl -sSL https://raw.githubusercontent.com/dimdasci/workspaces/main/host-setup.sh | bash -s -- --ebs /dev/nvme1n1'

# Copy age key for chezmoi secret decryption (used inside the container)
ssh user@my-ec2 'mkdir -p /workspace/.age'
scp ~/.age/key.txt user@my-ec2:/workspace/.age/key.txt
```

---

## Creating a workspace

Each workspace needs a named SSH provider. Create one per remote host:

```bash
# Create a named provider (once per host)
devpod provider add ssh --name my-ws

# Configure it — HOST must include the username
devpod provider set-options my-ws \
  -o HOST=ubuntu@<elastic-ip> \
  -o EXTRA_FLAGS="-o IdentitiesOnly=yes -i ~/.ssh/<key>.pem" \
  -o AGENT_PATH="/tmp/$(whoami)/devpod/agent"

# Create the workspace
devpod up ./workspace --provider my-ws --id my-ws --ide none
```

`HOST` must include `ubuntu@` (or whatever the SSH user is). Without it, DevPod uses your local username which won't match the remote host.

On first run this takes a few minutes for the image build.

---

## First-time container setup

Run once after the first `devpod up`. SSH into the container, authenticate GitHub, then run the post-auth setup:

```bash
ssh my-ws.devpod

# Inside the container (working dir is /workspaces/<ws-name>):
gh auth login
bash .devcontainer/postAuth.sh
```

`postAuth.sh` initializes chezmoi (clones dotfiles from private repo) and sets up symlinks. On subsequent `devpod up --recreate`, `postCreate.sh` handles this automatically — chezmoi source and gh token persist on `/workspace`.

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

`host-setup.sh` auto-calculates memory limits based on the host's total RAM and writes them to `/etc/profile.d/workspace-resources.sh`. The devcontainer reads these on startup.

| Variable | How it's set | Purpose |
|---|---|---|
| `WORKSPACE_MEMORY` | 75% of (total - 2GB reserved) | Container memory limit |
| `WORKSPACE_SHM` | 25% of workspace memory, min 2GB | Shared memory size |

Override by editing `/etc/profile.d/workspace-resources.sh` on the host.

---

## Multiple workspaces

Each workspace is an independent DevPod environment with its own named provider, optionally on different hosts:

```bash
# Create a provider per host (see "Creating a workspace" for full setup)
devpod provider add ssh --name work-1
devpod provider set-options work-1 -o HOST=ubuntu@<host-1> -o EXTRA_FLAGS="..." -o AGENT_PATH="..."

devpod provider add ssh --name work-2
devpod provider set-options work-2 -o HOST=ubuntu@<host-2> -o EXTRA_FLAGS="..." -o AGENT_PATH="..."

devpod up ./workspace --provider work-1 --id work-1 --ide none
devpod up ./workspace --provider work-2 --id work-2 --ide none

ssh work-1.devpod
ssh work-2.devpod
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

# Recreate using the existing provider
devpod up ./workspace --provider work-1 --id work-1 --ide none
```

The container is stateless. `/workspace` on the host is not touched by `devpod delete`. All project files, `.claude/`, gh auth, chezmoi source, and git repos survive the rebuild. No need to re-run `gh auth login` or `postAuth.sh` after recreate.

---

## Persistent storage

| Layer | What persists |
|---|---|
| `/workspace` on host | project files, `.claude/`, git repos, `.clipboard/`, `.config/gh/`, `.chezmoi-source/`, `.age/` |
| Container | nothing — ephemeral, rebuilt on `devpod up` |
| Tool caches | lost on rebuild (npm, pip, go module caches) |

**AWS EC2 with EBS** (recommended): create a gp3 volume in the same AZ as the instance, attach it, then pass it to `host-setup.sh`:

```bash
# From your local machine (or AWS console):
# 1. Create volume in the same AZ as your instance
aws ec2 create-volume --availability-zone <az> --size 64 --volume-type gp3 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=<name>-data}]'

# 2. Attach to instance (appears as /dev/nvme1n1 on Nitro instances)
aws ec2 attach-volume --volume-id vol-xxx --instance-id i-xxx --device /dev/sdf

# 3. Run host-setup with --ebs flag (formats XFS with reflink support, adds to fstab)
bash host-setup.sh --ebs /dev/nvme1n1
```

XFS with `reflink=1` enables copy-on-write for `cp --reflink` and `git clone --reference`, keeping multi-agent session clones disk-efficient. The volume persists independently of the instance — set `DeleteOnTermination: false` to keep data across instance replacements.

**AWS EC2 with EFS**: for shared storage across multiple instances. Pass the filesystem ID to `host-setup.sh`:

```bash
bash host-setup.sh --efs fs-xxx us-east-1
```

This installs `amazon-efs-utils` from source and adds the NFS mount to `/etc/fstab`.

**VPS**: local disk at `/workspace` — persists across rebuilds, lost if you wipe the VPS. Run `host-setup.sh` without flags.

---

## AWS-specific setup

### EBS

Create a gp3 volume in the same AZ as your EC2 instance. Attach it before running `host-setup.sh --ebs <device>`. The script formats it as XFS with reflink support and mounts at `/workspace`.

To keep the volume across instance termination, set `DeleteOnTermination: false` on the attachment (the default when attaching via CLI). The launch template's root volume has `DeleteOnTermination: true` — this is intentional; the root disk is stateless.

### EFS

Create the filesystem in the same VPC and availability zone as your EC2 instance. Run `host-setup.sh --efs <fs-id> <region>` — it handles efs-utils installation, fstab entry, and mount.

### IAM instance profile

Attach an IAM role to the EC2 instance with required permissions. The AWS CLI inside the container picks up credentials from the instance metadata service automatically — no static keys or token files needed.

---

## Security

- **Firewall**: AWS security group or VPS provider firewall. No ufw on the host — it conflicts with Docker's iptables rules.
- **SSH**: key-only auth, no password login, no root login (enforced by `host-setup.sh`).
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
