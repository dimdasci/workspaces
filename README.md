# workspaces

Standardized remote dev environment for VPS/EC2. Devcontainer deployed via DevPod on remote Ubuntu machines. Terminal-first with Claude Code; graphical desktop via XFCE + KasmVNC when needed. Compute is ephemeral, state lives on persistent storage.

## What's inside

- **Runtimes:** Node.js/pnpm, Go
- **AI/Dev tools:** Claude Code, opencode
- **Cloud/Infra:** GitHub CLI, AWS CLI, Terraform, AWS Session Manager plugin
- **Desktop:** XFCE + KasmVNC + Chromium (bidirectional clipboard, text + images)
- **Shell:** tmux (session persistence, OSC-52 clipboard), mosh
- **Media:** ffmpeg, imagemagick, exiftool, poppler-utils, ghostscript, qpdf

## Prerequisites

**Mac:**
```bash
brew install devpod pngpaste age
ssh-keygen -t ed25519  # if you don't have a key
mkdir -p ~/.age && age-keygen -o ~/.age/key.txt  # encryption key for chezmoi secrets

# One-time: disable DevPod bulk-loading all SSH keys into agent
devpod context set-options -o SSH_ADD_PRIVATE_KEYS=false
devpod context set-options -o AGENT_INJECT_TIMEOUT=60
```

**Remote machine:** Ubuntu 22.04+ with SSH access and sudo. Minimum 4 GB RAM / 2 vCPU. 8 GB+ recommended for headed Chromium.

**AWS EC2 example:** Ubuntu 24.04 AMI, t4g.xlarge (arm64, 4 vCPU, 16 GB), 32 GB gp3 EBS, security group allowing SSH (port 22) only. Allocate an Elastic IP so the address survives stop/start. Create an EFS filesystem in the same VPC/AZ and assign the same security group as the EC2 instance (NFS port 2049 must be open within the SG).

## Setup

### 1. Prepare SSH access

If using a .pem key (AWS):

```bash
chmod 600 ~/.ssh/<key-name>.pem

# Test
ssh -o IdentitiesOnly=yes -i ~/.ssh/<key-name>.pem ubuntu@<elastic-ip> echo ok
```

### 2. Run host setup

On the remote machine (installs Docker, firewall, fail2ban, chezmoi, age, EFS, memory limits):

```bash
# VPS (local disk for /workspace)
ssh -o IdentitiesOnly=yes -i ~/.ssh/<key-name>.pem ubuntu@<elastic-ip> \
  'curl -sSL https://raw.githubusercontent.com/dimdasci/workspaces/main/host-setup.sh | bash'

# AWS EC2 (EFS for /workspace — survives instance termination)
ssh -o IdentitiesOnly=yes -i ~/.ssh/<key-name>.pem ubuntu@<elastic-ip> \
  'curl -sSL https://raw.githubusercontent.com/dimdasci/workspaces/main/host-setup.sh | bash -s -- --efs <fs-id> <region>'
```

The script is idempotent — safe to re-run. It configures:
- Docker engine + adds your user to docker group
- `/workspace` directory — EFS mount (AWS) or local disk (VPS)
- Docker memory limits auto-calculated from host RAM
- ufw firewall: port 22 open; everything else blocked
- fail2ban for SSH brute force protection
- SSH hardening: key-only auth, no root login
- chezmoi + age (for dotfiles and secret management)

### 3. Set up chezmoi (optional, skip for initial testing)

```bash
# Copy your age encryption key to the remote host
scp -o IdentitiesOnly=yes -i ~/.ssh/<key-name>.pem ~/.age/key.txt ubuntu@<elastic-ip>:~/.config/chezmoi/key.txt

# Bootstrap dotfiles
ssh -o IdentitiesOnly=yes -i ~/.ssh/<key-name>.pem ubuntu@<elastic-ip> 'chezmoi init --apply <your-github-username>'
```

### 4. Add DevPod SSH provider

One provider per remote machine. Name it to match the host:

```bash
devpod provider add ssh --name <ws-name> \
  -o HOST=ubuntu@<elastic-ip> \
  -o EXTRA_FLAGS="-o IdentitiesOnly=yes -i ~/.ssh/<key-name>.pem"
```

### 5. Deploy the workspace

Use `--id` matching the provider name so everything stays consistent:

```bash
devpod up github.com/dimdasci/workspaces --provider <ws-name> --id <ws-name> --ide none
```

First build takes ~30 minutes on ARM (downloads base image, installs XFCE, KasmVNC, Chromium, all tools). Subsequent rebuilds use Docker cache and are faster.

### 6. Connect

**Terminal (primary):**
```bash
ssh <ws-name>.devpod
```

**Graphical desktop (separate Mac terminal):**
```bash
ssh -L 8443:localhost:8443 <ws-name>.devpod
```
Then open `https://localhost:8443` in your browser (accept the self-signed cert warning). Password: `vscode`. XFCE desktop with Chromium in the app menu.

**Port forwarding for dev servers:**
```bash
# Forward any port from the container to your Mac
ssh -L <port>:localhost:<port> <ws-name>.devpod

# Multiple ports at once
ssh -L 3000:localhost:3000 -L 5173:localhost:5173 <ws-name>.devpod
```

### 7. First-time setup inside the container

```bash
# Set git identity (persisted on EFS)
git config --global user.name "Your Name"
git config --global user.email "you@example.com"

# Authenticate with GitHub (use device flow — paste code in Mac browser)
gh auth login
```

## Clipboard

**Terminal (SSH + tmux):**
- Remote → Mac: automatic via OSC-52 (works in iTerm2, Ghostty, Alacritty)
- Mac → Remote: Cmd+V works by default

**Desktop (KasmVNC):**
- Bidirectional text + image clipboard via browser Clipboard API
- Requires the SSH tunnel (localhost provides the secure context)

**Images Mac → Remote (for Claude Code):**
```bash
# Add to ~/.zshrc on Mac:
alias ws1-img='f=$(date +%Y%m%d-%H%M%S).png; pngpaste /tmp/$f && scp -P 2222 /tmp/$f vscode@localhost:/workspace/.clipboard/$f && echo "/workspace/.clipboard/$f"'
```
Copy image to clipboard, run `ws1-img`, pass the printed path to Claude. Requires an SSH tunnel with port 2222 forwarded.

## Mac shell aliases

```bash
# Add to ~/.zshrc — one set per workspace
alias ws1='ssh ec2-ws.devpod'
alias ws1-vnc='ssh -L 8443:localhost:8443 ec2-ws.devpod'
alias ws1-img='f=$(date +%Y%m%d-%H%M%S).png; pngpaste /tmp/$f && scp -P 2222 /tmp/$f vscode@localhost:/workspace/.clipboard/$f && echo "/workspace/.clipboard/$f"'
```

## Multiple workspaces

Each remote machine gets its own provider and workspace ID:

```bash
# Add second machine
devpod provider add ssh --name contabo-ws \
  -o HOST=ubuntu@<other-ip> \
  -o EXTRA_FLAGS="-o IdentitiesOnly=yes -i ~/.ssh/<other-key>.pem"

devpod up github.com/dimdasci/workspaces --provider contabo-ws --id contabo-ws --ide none

# Connect
ssh ec2-ws.devpod       # first workspace
ssh contabo-ws.devpod   # second workspace
```

## Destroy and recreate

```bash
devpod delete <ws-name>
# /workspace on the host is NOT deleted — all project files survive
devpod up github.com/dimdasci/workspaces --provider <ws-name> --id <ws-name> --ide none
```

## Persistent storage

| What | Where | Lifecycle |
|---|---|---|
| Project files, git repos | `/workspace` on EFS | Survives everything |
| Claude config | `/workspace/.claude` | Survives everything |
| gh auth, opencode config | `/workspace/.config/` | Survives everything |
| git config | `/workspace/.gitconfig` | Survives everything |
| Container, tools, caches | Inside container | Rebuilt from Dockerfile |

**AWS EC2:** EFS is required. Pass `--efs` to `host-setup.sh` (see step 2). Data survives instance termination.

**VPS:** local disk at `/workspace`, persistent as long as the VPS exists.

## Security

- Firewall: port 22 open, KasmVNC (8443) via SSH tunnel only
- SSH: key-only, no root, fail2ban
- Secrets: chezmoi + age in a separate private repo, never in this repo
- Docker memory limits auto-calculated from host RAM

## Troubleshooting

**"Too many authentication failures" or agent injection timeout:**
DevPod bulk-loads all `~/.ssh/` keys into the SSH agent by default. Fix: `devpod context set-options -o SSH_ADD_PRIVATE_KEYS=false` and ensure your provider has `-o IdentitiesOnly=yes -i <key>` in EXTRA_FLAGS.

**EC2 IP changed after stop/start:**
Allocate an Elastic IP and associate it with the instance. Then update the provider: `devpod provider set-options <ws-name> -o HOST=ubuntu@<new-ip>`

**SSH host key changed after rebuild:**
```bash
ssh-keygen -R "[host]:2222"
```

**KasmVNC not starting:**
```bash
cat /tmp/kasmvnc-start.log
cat ~/.vnc/*.log
kasmvncserver -kill :1
kasmvncserver :1 -geometry 1920x1080 -depth 24 -websocketPort 8443
```

**Docker permission denied inside container:**
Reconnect — the docker group fix applies on next login: `ssh <ws-name>.devpod`

**GitHub raw CDN caching stale files:** use commit SHA instead of `main`:
```bash
curl -sSL "https://raw.githubusercontent.com/dimdasci/workspaces/<commit-sha>/host-setup.sh" | bash
```

## Full documentation

See [`docs/manual.md`](docs/manual.md) for detailed configuration, AWS IAM setup, and architecture decisions.
