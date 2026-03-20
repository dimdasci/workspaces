#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Local operations first (no network, guaranteed to succeed)
# =============================================================================

# ─── Fix Docker socket permissions (host GID may differ from container) ──────
echo "==> Fixing Docker socket permissions"
if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    sudo groupmod -g "$DOCKER_GID" docker 2>/dev/null || true
    sudo usermod -aG docker "$(whoami)" 2>/dev/null || true
fi

# ─── Ensure /workspace is writable (EFS root may be owned by root) ───────────
echo "==> Checking /workspace permissions"
if [ ! -w /workspace ]; then
    sudo chown -R "$(id -u):$(id -g)" /workspace
fi

# ─── Persist config on /workspace (survives rebuilds) ────────────────────────
echo "==> Setting up persistent config symlinks"
for dir in gh opencode; do
    mkdir -p "/workspace/.config/${dir}"
    rm -rf "${HOME}/.config/${dir}"
    ln -sf "/workspace/.config/${dir}" "${HOME}/.config/${dir}"
done

# Git config — always symlink so git config --global writes to /workspace
touch /workspace/.gitconfig
ln -sf /workspace/.gitconfig "${HOME}/.gitconfig"
if ! git config --global user.name &>/dev/null; then
    echo "NOTE: git user not configured. Run: git config --global user.name 'Your Name' && git config --global user.email 'you@example.com'"
fi

# ─── Chromium no-sandbox wrapper (required in containers) ────────────────────
echo "==> Configuring Chromium for container use"
sudo mkdir -p /etc/chromium
echo '{"CommandLineFlagSecurityWarningsEnabled": false}' | sudo tee /etc/chromium/policies/managed/container.json >/dev/null 2>&1 || true
# Set default flags for Chromium launched from desktop
sudo sed -i 's|^Exec=chromium|Exec=chromium --no-sandbox|' /usr/share/applications/chromium.desktop 2>/dev/null || true

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
cp "$(dirname "$0")/xstartup.sh" ~/.vnc/xstartup
chmod +x ~/.vnc/xstartup
echo -e "vscode\nvscode\n" | kasmvncpasswd -u vscode -w
touch ~/.vnc/.de-was-selected
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout ~/.vnc/self.key -out ~/.vnc/self.crt \
    -subj "/CN=localhost" 2>/dev/null

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
