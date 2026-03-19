#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Local operations first (no network, guaranteed to succeed)
# =============================================================================

# ─── SSH authorized keys ──────────────────────────────────────────────────────
echo "==> Setting up SSH authorized keys"
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if [ -f /tmp/host_authorized_keys ]; then
    cp /tmp/host_authorized_keys ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
fi

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

# =============================================================================
# Network-dependent installs (each wrapped so one failure doesn't kill the rest)
# =============================================================================

install_or_warn() {
    local name="$1"; shift
    echo "==> Installing $name"
    if ! "$@"; then
        echo "WARN: $name installation failed (non-fatal)"
    fi
}

# ─── TypeScript language server ──────────────────────────────────────────────
install_or_warn "TypeScript language server" npm install -g typescript typescript-language-server

# ─── Terraform ───────────────────────────────────────────────────────────────
install_terraform() {
    local arch tf_version tf_url
    arch="$(dpkg --print-architecture)"
    tf_version="$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r '.current_version')"
    tf_url="https://releases.hashicorp.com/terraform/${tf_version}/terraform_${tf_version}_linux_${arch}.zip"
    curl -fsSL "$tf_url" -o /tmp/terraform.zip
    unzip -o /tmp/terraform.zip -d /tmp/terraform-bin
    sudo mv /tmp/terraform-bin/terraform /usr/local/bin/terraform
    sudo chmod +x /usr/local/bin/terraform
    rm -rf /tmp/terraform.zip /tmp/terraform-bin
}
install_or_warn "Terraform" install_terraform

# ─── AWS Session Manager plugin ──────────────────────────────────────────────
install_ssm() {
    local arch ssm_url
    arch="$(dpkg --print-architecture)"
    if [ "$arch" = "arm64" ]; then
        ssm_url="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_arm64/session-manager-plugin.deb"
    else
        ssm_url="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
    fi
    curl -fsSL "$ssm_url" -o /tmp/session-manager-plugin.deb
    sudo dpkg -i /tmp/session-manager-plugin.deb
    rm /tmp/session-manager-plugin.deb
}
install_or_warn "AWS Session Manager plugin" install_ssm

# ─── opencode ────────────────────────────────────────────────────────────────
install_or_warn "opencode" go install github.com/opencode-ai/opencode@latest

echo "==> postCreate.sh complete"
