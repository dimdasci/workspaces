#!/usr/bin/env bash
set -euo pipefail

# ─── TypeScript language server ──────────────────────────────────────────────
echo "==> Installing TypeScript language server"
npm install -g typescript typescript-language-server

# ─── Terraform ───────────────────────────────────────────────────────────────
echo "==> Installing Terraform"
ARCH="$(dpkg --print-architecture)"
TF_VERSION="$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | python3 -c 'import sys,json; print(json.load(sys.stdin)["current_version"])')"
TF_URL="https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${ARCH}.zip"
curl -fsSL "$TF_URL" -o /tmp/terraform.zip
unzip -o /tmp/terraform.zip -d /tmp/terraform-bin
sudo mv /tmp/terraform-bin/terraform /usr/local/bin/terraform
sudo chmod +x /usr/local/bin/terraform
rm -rf /tmp/terraform.zip /tmp/terraform-bin

# ─── AWS Session Manager plugin ──────────────────────────────────────────────
echo "==> Installing AWS Session Manager plugin"
ARCH="$(dpkg --print-architecture)"
if [ "$ARCH" = "arm64" ]; then
    SSM_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_arm64/session-manager-plugin.deb"
else
    SSM_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
fi
curl -fsSL "$SSM_URL" -o /tmp/session-manager-plugin.deb
sudo dpkg -i /tmp/session-manager-plugin.deb
rm /tmp/session-manager-plugin.deb

# ─── opencode ────────────────────────────────────────────────────────────────
echo "==> Installing opencode"
go install github.com/opencode-ai/opencode@latest

# ─── age ─────────────────────────────────────────────────────────────────────
echo "==> Installing age"
sudo apt-get update
sudo apt-get install -y age
sudo rm -rf /var/lib/apt/lists/*

# ─── SSH authorized keys ──────────────────────────────────────────────────────
echo "==> Setting up SSH authorized keys"
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if [ -f /tmp/host_authorized_keys ]; then
    cat /tmp/host_authorized_keys >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
fi

# ─── Claude Code shell integration ───────────────────────────────────────────
echo "==> Installing Claude Code shell integration"
claude install 2>/dev/null || true

# ─── KasmVNC setup ───────────────────────────────────────────────────────────
echo "==> Setting up KasmVNC"
mkdir -p ~/.vnc
cp "$(dirname "$0")/kasmvnc.yaml" ~/.vnc/kasmvnc.yaml
cp "$(dirname "$0")/xstartup.sh" ~/.vnc/xstartup.sh
chmod +x ~/.vnc/xstartup.sh
echo -e "vscode\nvscode\n" | kasmvncpasswd -u vscode -w

# ─── tmux config ─────────────────────────────────────────────────────────────
echo "==> Writing tmux config"
cat > ~/.tmux.conf <<'EOF'
# OSC-52 clipboard passthrough
set -g set-clipboard on

# 256-color terminal support
set -g default-terminal "screen-256color"
set -ga terminal-overrides ",xterm-256color:Tc"

# Large scrollback buffer
set -g history-limit 50000

# Window numbering from 1
set -g base-index 1
setw -g pane-base-index 1

# Reduce escape time for vim over SSH
set -sg escape-time 10

# Mouse support
set -g mouse on
EOF

echo "==> postCreate.sh complete"
