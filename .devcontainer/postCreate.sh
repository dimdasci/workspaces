#!/usr/bin/env bash
set -euo pipefail

# Ensure ~/.local/bin is in PATH (claude, chezmoi, opencode install here)
export PATH="${HOME}/.local/bin:${PATH}"
for rc in "${HOME}/.profile" "${HOME}/.bashrc"; do
    if ! grep -q '\.local/bin' "$rc" 2>/dev/null; then
        echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> "$rc"
    fi
done

# ─── Pull latest source (DevPod caches the repo clone, doesn't update) ───────
# Bash reads scripts by byte offset, not line number. git pull can replace this
# file mid-execution, causing bash to read corrupted content at the old offset
# in the new file. Fix: pull first, then re-exec so bash reads the updated file
# from the start.
if [ "${_POSTCREATE_UPDATED:-0}" = "0" ]; then
    echo "==> Pulling latest source"
    # DevPod may clone via SSH but container has no SSH keys — switch to HTTPS
    if git remote get-url origin 2>/dev/null | grep -q 'git@github.com:'; then
        HTTPS_URL=$(git remote get-url origin | sed 's|git@github.com:|https://github.com/|')
        git remote set-url origin "$HTTPS_URL"
    fi
    git pull --ff-only 2>/dev/null || echo "WARN: git pull failed (non-fatal)"
    echo "==> Re-executing updated postCreate.sh"
    exec env _POSTCREATE_UPDATED=1 bash -l "$0"
fi

# =============================================================================
# Local operations first (no network, guaranteed to succeed)
# =============================================================================

# ─── Fix Docker socket permissions (host GID may differ from container) ──────
echo "==> Fixing Docker socket permissions"
if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    CURRENT_DOCKER_GID=$(getent group docker | cut -d: -f3)
    if [ "$DOCKER_GID" != "$CURRENT_DOCKER_GID" ]; then
        # If another group already has the socket's GID, move it out of the way
        BLOCKING_GROUP=$(getent group "$DOCKER_GID" | cut -d: -f1)
        if [ -n "$BLOCKING_GROUP" ] && [ "$BLOCKING_GROUP" != "docker" ]; then
            FREE_GID=990
            while getent group "$FREE_GID" >/dev/null 2>&1; do FREE_GID=$((FREE_GID - 1)); done
            sudo groupmod -g "$FREE_GID" "$BLOCKING_GROUP"
        fi
        sudo groupmod -g "$DOCKER_GID" docker
    fi
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

# Bash aliases — persistent on /workspace, sourced by default .bashrc
if [ -f /workspace/.bash_aliases ]; then
    ln -sf /workspace/.bash_aliases "${HOME}/.bash_aliases"
fi
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

# ─── Terminal info (alacritty, ghostty not in base image) ────────────────────
echo "==> Installing terminfo entries"
if ! infocmp alacritty &>/dev/null; then
    curl -fsSL "https://raw.githubusercontent.com/alacritty/alacritty/master/extra/alacritty.info" | tic -x - 2>/dev/null || true
fi
if ! infocmp xterm-ghostty &>/dev/null; then
    tic -x "$(dirname "$0")/ghostty.terminfo" 2>/dev/null || true
fi

# ─── tmux config (managed by chezmoi, symlinked here) ───────────────────────
if [ -f /workspace/.tmux.conf ]; then
    ln -sf /workspace/.tmux.conf "${HOME}/.tmux.conf"
fi

# ─── Session orchestrator ────────────────────────────────────────────────────
echo "==> Setting up session orchestrator"
mkdir -p /workspace/sessions /workspace/repos "${HOME}/.local/bin"
ln -sf "$(pwd)/scripts/ws-session" "${HOME}/.local/bin/ws-session"

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

# ─── Docker Compose plugin (Debian's docker.io lacks it; install from Docker's official repo) ─
install_docker_compose() {
    # Skip if already installed (fresh build has it from Dockerfile)
    if docker compose version &>/dev/null; then return 0; fi
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    printf 'Types: deb\nURIs: https://download.docker.com/linux/debian\nSuites: bookworm\nComponents: stable\nSigned-By: /etc/apt/keyrings/docker.asc\n' \
        | sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null
    sudo apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/docker.sources -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
    sudo apt-get install -y --no-install-recommends docker-compose-plugin
}
install_or_warn "Docker Compose plugin" install_docker_compose

# ─── TypeScript language server ──────────────────────────────────────────────
install_or_warn "TypeScript language server" npm install -g typescript typescript-language-server

# ─── dev-browser (Playwright-based browser for AI agents) ───────────────────
install_or_warn "dev-browser" npm install -g dev-browser

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

# ─── chezmoi ────────────────────────────────────────────────────────────────
install_or_warn "chezmoi" sh -c "$(curl -fsSL get.chezmoi.io)" -- -b ~/.local/bin

# Configure chezmoi to use /workspace as target
if [ -x "${HOME}/.local/bin/chezmoi" ]; then
    echo "==> Configuring chezmoi"
    mkdir -p ~/.config/chezmoi
    cat > ~/.config/chezmoi/chezmoi.toml <<'CHEZEOF'
sourceDir = "/workspace/.chezmoi-source"
destDir = "/workspace"
encryption = "age"
[age]
    identity = "/workspace/.age/key.txt"
    recipient = "age1fxdg538s8gg9dfr59p5a4clek2r8x09xv2df3n97jnpj9387ud0q2zpq0z"
CHEZEOF

    # Apply chezmoi if source exists (from a previous init). First-time init
    # requires gh auth and must be done manually after container creation.
    if [ -d /workspace/.chezmoi-source/.git ]; then
        echo "==> Applying chezmoi (existing source)"
        ~/.local/bin/chezmoi apply 2>/dev/null || echo "WARN: chezmoi apply failed (non-fatal)"
    else
        echo "==> Chezmoi source not found. After 'gh auth login', run:"
        echo "     chezmoi init dimdasci/stuff --source /workspace/.chezmoi-source --apply"
    fi

    # Symlinks for chezmoi-managed dirs (must run after chezmoi apply)
    if [ -d /workspace/.aws ]; then
        rm -rf "${HOME}/.aws"
        ln -sf /workspace/.aws "${HOME}/.aws"
    fi
fi

# ─── Claude Code ─────────────────────────────────────────────────────────────
install_or_warn "Claude Code" bash -c "$(curl -fsSL https://claude.ai/install.sh)"

# ─── opencode ────────────────────────────────────────────────────────────────
install_or_warn "opencode" bash -c "$(curl -fsSL https://opencode.ai/install)"

echo "==> postCreate.sh complete"
