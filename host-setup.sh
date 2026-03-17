#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# host-setup.sh — one-time remote host preparation
# Ubuntu 22.04+ | run as regular user with sudo
# =============================================================================

BANNER="==================================================================="

# -----------------------------------------------------------------------------
# 1. Docker
# -----------------------------------------------------------------------------
echo "$BANNER"
echo ">>> [1/7] Docker"
echo "$BANNER"

if command -v docker &>/dev/null; then
    echo "  docker already installed, skipping"
else
    echo "  installing docker via get.docker.com ..."
    curl -fsSL https://get.docker.com | sh
fi

CURRENT_USER="${SUDO_USER:-$USER}"
if groups "$CURRENT_USER" | grep -qw docker; then
    echo "  user '$CURRENT_USER' already in docker group, skipping"
else
    echo "  adding '$CURRENT_USER' to docker group ..."
    sudo usermod -aG docker "$CURRENT_USER"
    echo "  NOTE: log out and back in (or run 'newgrp docker') for group change to take effect"
fi

# -----------------------------------------------------------------------------
# 2. Persistent storage
# -----------------------------------------------------------------------------
echo "$BANNER"
echo ">>> [2/7] Persistent storage (/workspace)"
echo "$BANNER"

if [ -d /workspace ]; then
    echo "  /workspace already exists, skipping mkdir"
else
    echo "  creating /workspace ..."
    sudo mkdir -p /workspace
fi

if grep -qsE '\s/workspace\s' /etc/fstab; then
    echo "  /workspace found in /etc/fstab (EFS), mounting ..."
    sudo mount /workspace || echo "  mount returned non-zero (may already be mounted)"
else
    echo "  /workspace not in /etc/fstab, skipping mount"
fi

echo "  setting ownership of /workspace to UID 1000 ..."
sudo chown -R 1000:1000 /workspace

# -----------------------------------------------------------------------------
# 3. chezmoi
# -----------------------------------------------------------------------------
echo "$BANNER"
echo ">>> [3/7] chezmoi"
echo "$BANNER"

if [ -x /usr/local/bin/chezmoi ]; then
    echo "  chezmoi already installed at /usr/local/bin/chezmoi, skipping"
else
    echo "  installing chezmoi to /usr/local/bin ..."
    sudo sh -c "$(curl -fsSL https://get.chezmoi.io)" -- -b /usr/local/bin
fi

# -----------------------------------------------------------------------------
# 4. age
# -----------------------------------------------------------------------------
echo "$BANNER"
echo ">>> [4/7] age"
echo "$BANNER"

if command -v age &>/dev/null; then
    echo "  age already installed, skipping"
else
    echo "  installing age ..."
    sudo apt-get install -y age
fi

# -----------------------------------------------------------------------------
# 5. Firewall (ufw)
# -----------------------------------------------------------------------------
echo "$BANNER"
echo ">>> [5/7] Firewall (ufw)"
echo "$BANNER"

if ! command -v ufw &>/dev/null; then
    echo "  ufw not found, installing ..."
    sudo apt-get install -y ufw
fi

echo "  configuring ufw rules ..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp   comment 'host SSH'
sudo ufw allow 2222/tcp comment 'container SSH'
# port 8443 (KasmVNC) intentionally NOT opened — SSH tunnel only

echo "  enabling ufw (force) ..."
sudo ufw --force enable

echo "  ufw status:"
sudo ufw status verbose

# -----------------------------------------------------------------------------
# 6. fail2ban
# -----------------------------------------------------------------------------
echo "$BANNER"
echo ">>> [6/7] fail2ban"
echo "$BANNER"

if command -v fail2ban-server &>/dev/null; then
    echo "  fail2ban already installed, skipping apt install"
else
    echo "  installing fail2ban ..."
    sudo apt-get install -y fail2ban
fi

echo "  enabling and starting fail2ban ..."
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# -----------------------------------------------------------------------------
# 7. SSH hardening
# -----------------------------------------------------------------------------
echo "$BANNER"
echo ">>> [7/7] SSH hardening"
echo "$BANNER"

SSHD_CONF=/etc/ssh/sshd_config

apply_sshd_setting() {
    local key="$1"
    local value="$2"
    if grep -qE "^\s*${key}\s+" "$SSHD_CONF"; then
        sudo sed -i "s|^\s*${key}\s.*|${key} ${value}|" "$SSHD_CONF"
        echo "  updated: ${key} ${value}"
    elif grep -qE "^\s*#\s*${key}\s+" "$SSHD_CONF"; then
        sudo sed -i "s|^\s*#\s*${key}\s.*|${key} ${value}|" "$SSHD_CONF"
        echo "  uncommented and set: ${key} ${value}"
    else
        echo "${key} ${value}" | sudo tee -a "$SSHD_CONF" >/dev/null
        echo "  appended: ${key} ${value}"
    fi
}

apply_sshd_setting PermitRootLogin no
apply_sshd_setting PasswordAuthentication no

echo "  restarting sshd ..."
sudo systemctl restart sshd

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo "$BANNER"
echo ">>> host-setup complete"
echo "$BANNER"
echo ""
echo "Next steps:"
echo "  1. Copy your age key:  scp ~/.age/key.txt user@host:~/.config/chezmoi/key.txt"
echo "  2. Bootstrap chezmoi:  chezmoi init --apply <your-github-username>"
echo "  3. Deploy workspace:   devpod up ./workspace --provider ssh --option HOST=<this-host>"
echo ""
