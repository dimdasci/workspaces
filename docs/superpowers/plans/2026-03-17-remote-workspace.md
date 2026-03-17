# Remote Workspace Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a devcontainer-based remote workspace deployable on any Linux machine via DevPod, with terminal (SSH+tmux), graphical desktop (XFCE+KasmVNC), and full dev tooling.

**Architecture:** Devcontainer-first approach. Dockerfile installs apt packages (XFCE, KasmVNC, media tools). Devcontainer features provide runtimes (Node, Go, Claude Code). postCreate.sh handles tool installation and service startup. host-setup.sh bootstraps the remote host. All secrets managed externally by chezmoi+age.

**Tech Stack:** Docker, devcontainer spec, DevPod, XFCE4, KasmVNC, tmux, Node.js/pnpm, Go, Terraform, AWS CLI, Claude Code

**Spec:** `docs/superpowers/specs/2026-03-17-remote-workspace-design.md`

---

## File Structure

| File | Responsibility |
|---|---|
| `.devcontainer/Dockerfile` | Base image, apt packages (XFCE, KasmVNC, Chromium deps, media tools, docker.io, tmux, mosh) |
| `.devcontainer/devcontainer.json` | Features, mounts, ports, env vars, postCreate hook |
| `.devcontainer/postCreate.sh` | Tool installation (TS LSP, Terraform, ECS exec, opencode, age), SSH key setup, KasmVNC config, tmux config |
| `.devcontainer/kasmvnc.yaml` | KasmVNC server configuration (resolution, clipboard, network) |
| `.devcontainer/xstartup.sh` | KasmVNC session startup script (launches XFCE) |
| `host-setup.sh` | Host preparation (Docker install, persistent storage, firewall, chezmoi+age) |
| `.gitignore` | Excludes decrypted secrets, .clipboard/, etc. |
| `docs/manual.md` | Usage manual (updated for remote workflow) |
| `CLAUDE.md` | Project instructions (updated) |

---

## Chunk 1: Core container (Dockerfile + devcontainer.json)

### Task 1: Create .gitignore

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Write .gitignore**

```gitignore
# Decrypted secrets
*.dec
*.decrypted
.env
.env.local

# Clipboard transfer directory
.clipboard/

# OS files
.DS_Store
Thumbs.db

# Editor state
*.swp
*.swo
*~
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "Add .gitignore"
```

### Task 2: Create Dockerfile

**Files:**
- Create: `.devcontainer/Dockerfile`

**Reference:** Spec sections "Dockerfile apt packages", current Dockerfile at `/Users/dim/contexts/personal/.devcontainer/Dockerfile`

- [ ] **Step 1: Write Dockerfile with base image, locale, and user setup**

```dockerfile
FROM mcr.microsoft.com/devcontainers/base:bookworm

# Chromium/Playwright dependencies
RUN apt-get update && apt-get install -y \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpango-1.0-0 \
    libcairo2 \
    libatspi2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI (for socket passthrough to host daemon)
RUN apt-get update && apt-get install -y \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

RUN usermod -aG docker vscode

# Media processing tools
RUN apt-get update && apt-get install -y \
    ffmpeg \
    imagemagick \
    exiftool \
    webp \
    poppler-utils \
    ghostscript \
    qpdf \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Terminal tools
RUN apt-get update && apt-get install -y \
    tmux \
    mosh \
    && rm -rf /var/lib/apt/lists/*

# XFCE desktop environment
RUN apt-get update && apt-get install -y \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    && rm -rf /var/lib/apt/lists/*

# KasmVNC — download pinned .deb from GitHub releases
# Check https://github.com/kasmtech/KasmVNC/releases for latest version
ARG KASMVNC_VERSION=1.3.3
RUN ARCH=$(dpkg --print-architecture) && \
    apt-get update && apt-get install -y wget && \
    wget -q "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_bookworm_${KASMVNC_VERSION}_${ARCH}.deb" \
         -O /tmp/kasmvnc.deb && \
    apt-get install -y /tmp/kasmvnc.deb && \
    rm /tmp/kasmvnc.deb && \
    rm -rf /var/lib/apt/lists/*

# Locale
RUN sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8

# Silence login banner
RUN touch /home/vscode/.hushlogin
```

Note: The KasmVNC version and .deb filename pattern must be verified against the actual GitHub releases page during implementation. The naming convention may differ (e.g., `kasmvncserver_bookworm_` vs `kasmvncserver_debian_bookworm_`). Check and adjust.

- [ ] **Step 2: Verify Dockerfile syntax**

```bash
cd /Users/dim/contexts/personal/projects/workspace
docker build -f .devcontainer/Dockerfile --check .
```

If `--check` is not available, just verify it parses without error by running a dry build or reviewing syntax manually.

- [ ] **Step 3: Commit**

```bash
git add .devcontainer/Dockerfile
git commit -m "Add Dockerfile with XFCE, KasmVNC, Chromium deps, media tools"
```

### Task 3: Create devcontainer.json

**Files:**
- Create: `.devcontainer/devcontainer.json`

**Reference:** Spec sections "Devcontainer features", "Persistent storage", "Connection architecture". Current devcontainer.json at `/Users/dim/contexts/personal/.devcontainer/devcontainer.json`

- [ ] **Step 1: Write devcontainer.json**

```jsonc
{
  "name": "workspace",
  "build": {
    "dockerfile": "Dockerfile"
  },

  "runArgs": [
    "--shm-size=2g"
  ],

  "features": {
    "ghcr.io/devcontainers/features/node:1": { "pnpmVersion": "latest" },
    "ghcr.io/devcontainers/features/go:1": { "version": "latest" },
    "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {},
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/aws-cli:1": {},
    "ghcr.io/devcontainers/features/sshd:1": {}
  },

  "forwardPorts": [2222, 8443],

  "mounts": [
    // Persistent storage (host path set by host-setup.sh)
    "source=/workspace,target=/workspace,type=bind",

    // Host Docker socket for sibling containers
    "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind",

    // SSH public key for container login
    "source=${localEnv:HOME}/.ssh/authorized_keys,target=/tmp/host_authorized_keys,type=bind,readonly"
  ],

  "containerEnv": {
    "CLAUDE_CONFIG_DIR": "/workspace/.claude"
  },

  "remoteUser": "vscode",
  "updateRemoteUserUID": true,

  "postCreateCommand": "bash -l .devcontainer/postCreate.sh"
}
```

Notes for implementation:
- The `source=/workspace` host path assumes `host-setup.sh` has created `/workspace` on the host. On AWS this is the EFS mount point; on VPS it is a regular directory.
- The SSH authorized_keys mount assumes the host has the deployer's public key in the standard location. Adjust if DevPod handles SSH differently.
- `containerEnv` points Claude config to persistent storage. Chezmoi on the host populates env vars (CLAUDE_CODE_OAUTH_TOKEN, GH_TOKEN) which DevPod passes into the container. The exact mechanism for env var passthrough from host to container via DevPod needs verification during implementation.

- [ ] **Step 2: Commit**

```bash
git add .devcontainer/devcontainer.json
git commit -m "Add devcontainer.json with features, mounts, and port config"
```

---

## Chunk 2: KasmVNC + XFCE desktop setup

### Task 4: Create KasmVNC configuration

**Files:**
- Create: `.devcontainer/kasmvnc.yaml`
- Create: `.devcontainer/xstartup.sh`

- [ ] **Step 1: Write KasmVNC config**

```yaml
desktop:
  resolution:
    width: 1920
    height: 1080
  clipboard:
    allow_clipboard_down: true
    allow_clipboard_up: true

network:
  protocol: http
  websocket_port: 8443
  ssl:
    require_ssl: false

logging:
  level: 30
```

Note: `require_ssl: false` because we access via SSH tunnel (localhost), which provides the secure context needed for the Clipboard API. In production behind a reverse proxy, set to true with real certs.

- [ ] **Step 2: Write XFCE startup script**

```bash
#!/usr/bin/env bash
# KasmVNC xstartup — launches XFCE desktop session
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
dbus-launch --exit-with-session startxfce4
```

- [ ] **Step 3: Make startup script executable**

```bash
chmod +x .devcontainer/xstartup.sh
```

- [ ] **Step 4: Commit**

```bash
git add .devcontainer/kasmvnc.yaml .devcontainer/xstartup.sh
git commit -m "Add KasmVNC config and XFCE startup script"
```

### Task 5: Create postCreate.sh

**Files:**
- Create: `.devcontainer/postCreate.sh`

**Reference:** Spec section "postCreate.sh installs"

- [ ] **Step 1: Write postCreate.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing TypeScript language server..."
npm install -g typescript typescript-language-server

echo "==> Installing Terraform..."
TERRAFORM_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r '.current_version')
curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_$(dpkg --print-architecture).zip" -o /tmp/terraform.zip
sudo unzip -o /tmp/terraform.zip -d /usr/local/bin/
rm /tmp/terraform.zip

echo "==> Installing AWS Session Manager plugin..."
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "amd64" ]; then
    SSM_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
elif [ "$ARCH" = "arm64" ]; then
    SSM_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_arm64/session-manager-plugin.deb"
fi
curl -fsSL "$SSM_URL" -o /tmp/ssm-plugin.deb
sudo dpkg -i /tmp/ssm-plugin.deb
rm /tmp/ssm-plugin.deb

echo "==> Installing opencode..."
curl -fsSL https://opencode.ai/install | bash

echo "==> Installing age..."
sudo apt-get update && sudo apt-get install -y age && sudo rm -rf /var/lib/apt/lists/*

echo "==> Configuring SSH authorized keys..."
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if [ -f /tmp/host_authorized_keys ]; then
    cat /tmp/host_authorized_keys >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
fi

echo "==> Setting up Claude Code shell integration..."
claude install 2>/dev/null || true

echo "==> Configuring KasmVNC..."
mkdir -p ~/.vnc
cp /workspace/.devcontainer/kasmvnc.yaml ~/.vnc/kasmvnc.yaml 2>/dev/null || \
    cp "$(dirname "$0")/kasmvnc.yaml" ~/.vnc/kasmvnc.yaml
cp /workspace/.devcontainer/xstartup.sh ~/.vnc/xstartup.sh 2>/dev/null || \
    cp "$(dirname "$0")/xstartup.sh" ~/.vnc/xstartup.sh
chmod +x ~/.vnc/xstartup.sh
# Set VNC password (default; change via chezmoi or manually)
echo -e "vscode\nvscode\n" | kasmvncpasswd -u vscode -w

echo "==> Configuring tmux..."
cat > ~/.tmux.conf << 'TMUX'
# OSC-52 clipboard support
set -g set-clipboard on

# Modern terminal
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"

# Increase scrollback
set -g history-limit 50000

# Start window numbering at 1
set -g base-index 1
setw -g pane-base-index 1

# Reduce escape time (important for vim over SSH)
set -sg escape-time 10

# Mouse support
set -g mouse on
TMUX

echo "==> Starting KasmVNC..."
kasmvncserver :1 -geometry 1920x1080 -depth 24 -websocketPort 8443 || true

echo "==> postCreate done."
```

Notes for implementation:
- The opencode install URL needs verification. Check the actual installation method.
- The `kasmvncpasswd` syntax needs verification against the actual KasmVNC version.
- KasmVNC may need to be started as a background service rather than in postCreate (which runs once). Consider adding a startup script that runs on container start, not just create. Check if `postStartCommand` in devcontainer.json is more appropriate for KasmVNC.
- The tmux config uses default keybindings (Ctrl+B) per Mischa's recommendation.

- [ ] **Step 2: Make postCreate.sh executable**

```bash
chmod +x .devcontainer/postCreate.sh
```

- [ ] **Step 3: Commit**

```bash
git add .devcontainer/postCreate.sh
git commit -m "Add postCreate.sh with tool installation and KasmVNC setup"
```

---

## Chunk 3: Host setup script

### Task 6: Create host-setup.sh

**Files:**
- Create: `host-setup.sh`

**Reference:** Spec sections "host-setup.sh", "Security", "Persistent storage"

- [ ] **Step 1: Write host-setup.sh**

```bash
#!/usr/bin/env bash
#
# host-setup.sh — One-time host preparation for remote workspace
#
# Run on a fresh Ubuntu 22.04+ machine:
#   curl -sSL https://raw.githubusercontent.com/<repo>/main/host-setup.sh | bash
#
# What it does:
#   1. Installs Docker
#   2. Creates persistent storage directory (or mounts EFS)
#   3. Installs chezmoi + age
#   4. Configures firewall and SSH hardening
#
set -euo pipefail

echo "==> Installing Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    echo "    Docker installed. You may need to log out and back in for group changes."
else
    echo "    Docker already installed."
fi

echo "==> Setting up persistent storage..."
WORKSPACE_DIR="/workspace"
if [ ! -d "$WORKSPACE_DIR" ]; then
    # Check if EFS mount is configured (AWS)
    if grep -q "$WORKSPACE_DIR" /etc/fstab 2>/dev/null; then
        sudo mount "$WORKSPACE_DIR"
        echo "    EFS mounted at $WORKSPACE_DIR"
    else
        sudo mkdir -p "$WORKSPACE_DIR"
        sudo chown "$(id -u):$(id -g)" "$WORKSPACE_DIR"
        echo "    Created $WORKSPACE_DIR (local storage)"
    fi
else
    echo "    $WORKSPACE_DIR already exists."
fi

# Ensure correct ownership for devcontainer user (UID 1000)
sudo chown -R 1000:1000 "$WORKSPACE_DIR"

echo "==> Installing chezmoi..."
if ! command -v chezmoi &>/dev/null; then
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin
    echo "    chezmoi installed."
else
    echo "    chezmoi already installed."
fi

echo "==> Installing age..."
if ! command -v age &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y age
    echo "    age installed."
else
    echo "    age already installed."
fi

echo "==> Configuring firewall..."
if command -v ufw &>/dev/null; then
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow 22/tcp    # Host SSH
    sudo ufw allow 2222/tcp  # Container SSH (devcontainer sshd)
    # KasmVNC (8443) intentionally NOT opened — access via SSH tunnel only
    sudo ufw --force enable
    echo "    Firewall configured: ports 22, 2222 open."
else
    sudo apt-get update && sudo apt-get install -y ufw
    # Re-run firewall setup
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow 22/tcp
    sudo ufw allow 2222/tcp
    sudo ufw --force enable
    echo "    ufw installed and configured."
fi

echo "==> Installing fail2ban..."
if ! command -v fail2ban-client &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y fail2ban
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban
    echo "    fail2ban installed and started."
else
    echo "    fail2ban already installed."
fi

echo "==> Hardening SSH..."
SSHD_CONFIG="/etc/ssh/sshd_config"
# Disable root login
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
# Disable password auth
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
sudo systemctl restart sshd
echo "    SSH hardened: no root login, key-only auth."

echo ""
echo "==> Host setup complete."
echo ""
echo "Next steps:"
echo "  1. Copy your age key:  scp ~/.age/key.txt $(whoami)@$(hostname):~/.config/chezmoi/key.txt"
echo "  2. Bootstrap chezmoi:  chezmoi init --apply <your-github-username>"
echo "  3. Deploy workspace:   devpod up ./workspace --provider ssh --option HOST=$(hostname)"
```

- [ ] **Step 2: Make host-setup.sh executable**

```bash
chmod +x host-setup.sh
```

- [ ] **Step 3: Commit**

```bash
git add host-setup.sh
git commit -m "Add host-setup.sh for one-time remote host preparation"
```

---

## Chunk 4: Documentation and manual

### Task 7: Update docs/manual.md

**Files:**
- Modify: `docs/manual.md`

The existing manual.md describes the local devcontainer setup. Replace it with documentation for the remote workspace. Structure:

- [ ] **Step 1: Write the new manual**

The manual should cover:
1. Prerequisites (Mac: DevPod, pngpaste, SSH key. Remote: Ubuntu 22.04+)
2. First-time host setup (running host-setup.sh, copying age key, chezmoi bootstrap)
3. Creating a workspace (devpod up)
4. Connecting (SSH terminal, KasmVNC browser)
5. Daily workflow (tmux basics, clipboard, image transfer)
6. Mac shell aliases (ws1, ws1-vnc, ws1-img)
7. Managing multiple workspaces
8. Destroying and recreating workspaces
9. AWS-specific: EFS setup, IAM instance profiles
10. Troubleshooting (SSH host key changes, UID mismatches, KasmVNC not starting)

Write the full manual based on the spec and the decisions made during brainstorming. Keep the same information-dense style as the existing manual.md. This is a full rewrite — the current manual.md documents the local devcontainer setup which is being replaced.

- [ ] **Step 2: Commit**

```bash
git add docs/manual.md
git commit -m "Rewrite manual for remote workspace workflow"
```

### Task 8: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add project-specific instructions**

Add workspace-specific context to CLAUDE.md: what the project is, key file purposes, and the currentDate line should remain.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Update CLAUDE.md with workspace project context"
```

---

## Chunk 5: Validation

### Task 9: Local build test

This task validates the Dockerfile builds successfully. It does not require a remote machine.

- [ ] **Step 1: Build the Docker image locally**

```bash
cd /Users/dim/contexts/personal/projects/workspace
docker build -f .devcontainer/Dockerfile -t workspace-test .
```

Expected: successful build. If KasmVNC .deb URL is wrong, fix the version/filename in the Dockerfile.

- [ ] **Step 2: Verify key packages are installed**

```bash
docker run --rm workspace-test bash -c "
    echo '--- XFCE ---' && which startxfce4 &&
    echo '--- KasmVNC ---' && which kasmvncserver &&
    echo '--- tmux ---' && which tmux &&
    echo '--- mosh ---' && which mosh-server &&
    echo '--- Docker CLI ---' && which docker &&
    echo '--- ffmpeg ---' && which ffmpeg &&
    echo '--- ImageMagick ---' && which convert &&
    echo '--- jq ---' && which jq &&
    echo 'All packages OK'
"
```

Expected: all paths printed, "All packages OK" at the end.

- [ ] **Step 3: Clean up test image**

```bash
docker rmi workspace-test
```

- [ ] **Step 4: Commit any fixes**

If any Dockerfile changes were needed, commit them:

```bash
git add .devcontainer/Dockerfile
git commit -m "Fix Dockerfile issues found during build validation"
```

### Task 10: Documentation review

- [ ] **Step 1: Read through manual.md end-to-end**

Verify all commands are copy-pasteable, all paths are consistent with the spec, and no steps are missing.

- [ ] **Step 2: Verify repo structure matches spec**

```bash
find . -not -path './.git/*' -not -path './.git' -not -path './docs/superpowers/*' | sort
```

Expected output should match the spec's repository structure section.

- [ ] **Step 3: Final commit if needed**

```bash
git add -A
git status
# Only commit if there are changes
git commit -m "Final polish: documentation and structure cleanup"
```
