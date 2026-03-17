# workspaces

Standardized remote dev environment for VPS/EC2. Devcontainer deployed via DevPod on remote Ubuntu machines. Terminal-first with Claude Code; graphical desktop via XFCE + KasmVNC when needed. Compute is ephemeral, state lives on persistent storage.

## What's inside

- **Runtimes:** Node.js/pnpm, Go
- **AI/Dev tools:** Claude Code, opencode
- **Cloud/Infra:** GitHub CLI, AWS CLI, Terraform, AWS Session Manager plugin
- **Desktop:** XFCE + KasmVNC (bidirectional clipboard, text + images)
- **Shell:** tmux (session persistence, OSC-52 clipboard), mosh
- **Media:** ffmpeg, imagemagick, exiftool, poppler-utils, ghostscript, qpdf

## Prerequisites

**Mac:**
```bash
brew install devpod pngpaste
ssh-keygen -t ed25519  # if you don't have a key
```

**Remote machine:** Ubuntu 22.04+ with SSH access and sudo. Minimum 4 GB RAM / 2 vCPU. 8 GB+ recommended for headed Chromium.

**AWS EC2 example:** Ubuntu 24.04 AMI, t4g.xlarge (arm64, 4 vCPU, 16 GB), 32 GB gp3 EBS, security group allowing SSH (port 22) only.

## Setup

### 1. Prepare SSH access

If using a .pem key (AWS):

```bash
# Fix permissions (required)
chmod 600 ~/.ssh/<key-name>.pem

# Add to ~/.ssh/config for convenience
cat >> ~/.ssh/config << 'EOF'
Host ws-ec2
    HostName <public-ip>
    User ubuntu
    IdentityFile ~/.ssh/<key-name>.pem
EOF

# Test
ssh ws-ec2
```

### 2. Run host setup

On the remote machine (installs Docker, firewall, fail2ban, chezmoi, age):

```bash
ssh ws-ec2 'curl -sSL https://raw.githubusercontent.com/dimdasci/workspaces/main/host-setup.sh | bash'
```

The script is idempotent — safe to re-run. It configures:
- Docker engine + adds your user to docker group
- `/workspace` directory (persistent storage mount point)
- ufw firewall: ports 22, 2222 open; everything else blocked
- fail2ban for SSH brute force protection
- SSH hardening: key-only auth, no root login
- chezmoi + age (for dotfiles and secret management)

### 3. Set up chezmoi (optional, skip for initial testing)

```bash
# Copy your age encryption key to the remote host
scp ~/.age/key.txt ws-ec2:~/.config/chezmoi/key.txt

# Bootstrap dotfiles
ssh ws-ec2 'chezmoi init --apply <your-github-username>'
```

### 4. Add DevPod SSH provider

```bash
devpod provider add ssh \
  --option HOST=ubuntu@<public-ip> \
  --option EXTRA_FLAGS="-i ~/.ssh/<key-name>.pem"
```

### 5. Deploy the workspace

```bash
devpod up github.com/dimdasci/workspaces --provider ssh --ide none
```

First build takes several minutes (downloads base image, installs XFCE, KasmVNC, all tools). Subsequent rebuilds use Docker cache.

### 6. Connect

**Terminal (primary):**
```bash
devpod ssh workspaces
```

tmux starts automatically. `Ctrl+B %` splits vertically, `Ctrl+B "` splits horizontally, `Ctrl+B <arrow>` switches panes. If SSH drops, reconnect and `tmux attach` — session is preserved.

**Graphical desktop (separate Mac terminal):**
```bash
ssh -L 8443:localhost:8443 ws-ec2
```
Then open `http://localhost:8443` in your browser. Password: `vscode`. XFCE desktop with Chromium in the app menu.

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
alias ws1-img='f=$(date +%Y%m%d-%H%M%S).png; pngpaste /tmp/$f && scp -P 2222 /tmp/$f vscode@ws-ec2:/workspace/.clipboard/$f && echo "/workspace/.clipboard/$f"'
```
Copy image to clipboard, run `ws1-img`, pass the printed path to Claude.

## Mac shell aliases

```bash
# Add to ~/.zshrc
alias ws1='devpod ssh workspaces'
alias ws1-vnc='ssh -L 8443:localhost:8443 ws-ec2'
alias ws1-img='f=$(date +%Y%m%d-%H%M%S).png; pngpaste /tmp/$f && scp -P 2222 /tmp/$f vscode@ws-ec2:/workspace/.clipboard/$f && echo "/workspace/.clipboard/$f"'
```

## Multiple workspaces

```bash
devpod up github.com/dimdasci/workspaces --provider ssh --id work-2
# (configure provider with different HOST for a different machine)

devpod ssh workspaces   # first workspace
devpod ssh work-2       # second workspace
```

## Destroy and recreate

```bash
devpod delete workspaces
# /workspace on the host is NOT deleted — all project files survive
devpod up github.com/dimdasci/workspaces --provider ssh --ide none
```

## Persistent storage

| What | Where | Lifecycle |
|---|---|---|
| Project files, git repos, .claude/ | `/workspace` on host | Survives container rebuild |
| Container, tools, caches | Inside container | Rebuilt from Dockerfile |

**AWS EFS** (optional, for data that survives instance termination):
```bash
sudo apt-get install -y amazon-efs-utils
# Add to /etc/fstab before running host-setup.sh:
# fs-xxx.efs.region.amazonaws.com:/ /workspace efs _netdev,tls 0 0
```

**VPS:** local disk at `/workspace`, persistent as long as the VPS exists.

## Security

- Firewall: ports 22 + 2222 open, KasmVNC (8443) via SSH tunnel only
- SSH: key-only, no root, fail2ban
- Secrets: chezmoi + age in a separate private repo, never in this repo

## Troubleshooting

**SSH host key changed after rebuild:**
```bash
ssh-keygen -R "[host]:2222"
```

**UID mismatch on bind mounts:**
```bash
sudo chown -R 1000:1000 /workspace
```

**KasmVNC not starting:**
```bash
cat ~/.vnc/*.log
kasmvncserver -kill :1
kasmvncserver :1 -geometry 1920x1080 -depth 24 -websocketPort 8443
```

**Clipboard not syncing:** verify SSH tunnel is active and you're accessing `http://localhost:8443` (not the remote IP).

**GitHub raw CDN caching stale files:** append a cache-buster: `curl -sSL "https://...host-setup.sh?$(date +%s)" | bash`

## Full documentation

See [`docs/manual.md`](docs/manual.md) for detailed configuration, AWS IAM setup, and architecture decisions.
