#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# host-setup.sh — one-time remote host preparation
# Ubuntu 22.04+ | run as regular user with sudo
#
# Usage:
#   bash host-setup.sh                          # VPS (local disk)
#   bash host-setup.sh --efs fs-xxx us-east-1   # AWS EC2 (EFS)
# =============================================================================

BANNER="==================================================================="

# Parse arguments
EFS_ID=""
AWS_REGION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --efs)
            EFS_ID="$2"
            AWS_REGION="${3:?'AWS region required after EFS ID, e.g.: --efs fs-xxx us-east-1'}"
            shift 3
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# -----------------------------------------------------------------------------
# 1. Docker
# -----------------------------------------------------------------------------
echo "$BANNER"
echo ">>> [1/8] Docker"
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
echo ">>> [2/8] Persistent storage (/workspace)"
echo "$BANNER"

if [ -d /workspace ]; then
    echo "  /workspace already exists, skipping mkdir"
else
    echo "  creating /workspace ..."
    sudo mkdir -p /workspace
fi

if [ -n "$EFS_ID" ]; then
    # Install EFS utils if needed
    if ! command -v mount.efs &>/dev/null; then
        echo "  installing amazon-efs-utils from source ..."
        sudo apt-get update
        sudo apt-get install -y git binutils rustc cargo pkg-config libssl-dev cmake golang-go
        rm -rf /tmp/efs-utils
        git clone https://github.com/aws/efs-utils /tmp/efs-utils
        cd /tmp/efs-utils
        ./build-deb.sh
        sudo apt-get install -y ./build/amazon-efs-utils*deb
        cd -
        rm -rf /tmp/efs-utils
    fi

    FSTAB_ENTRY="${EFS_ID}.efs.${AWS_REGION}.amazonaws.com:/ /workspace efs _netdev,tls 0 0"
    if grep -qsE '\s/workspace\s' /etc/fstab; then
        echo "  /workspace already in /etc/fstab, updating ..."
        sudo sed -i '\| /workspace |d' /etc/fstab
    fi
    echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab >/dev/null
    echo "  added fstab entry: $FSTAB_ENTRY"
fi

if grep -qsE '\s/workspace\s' /etc/fstab; then
    echo "  mounting /workspace from fstab ..."
    sudo mount /workspace || echo "  mount returned non-zero (may already be mounted)"
else
    echo "  no fstab entry for /workspace, using local disk"
fi

echo "  setting ownership of /workspace to UID 1000 ..."
sudo chown -R 1000:1000 /workspace

# -----------------------------------------------------------------------------
# 3. chezmoi
# -----------------------------------------------------------------------------
echo "$BANNER"
echo ">>> [3/8] chezmoi"
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
echo ">>> [4/8] age"
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
echo ">>> [5/8] Firewall (ufw)"
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
echo ">>> [6/8] fail2ban"
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
echo ">>> [7/8] SSH hardening"
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

echo "  restarting ssh ..."
# Ubuntu 24.04+ uses ssh.service; older versions use sshd.service
sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd

# -----------------------------------------------------------------------------
# 8. Elastic IP reminder (AWS only)
# -----------------------------------------------------------------------------
echo "$BANNER"
echo ">>> [8/8] Elastic IP check"
echo "$BANNER"

if [ -n "$EFS_ID" ]; then
    echo "  AWS detected (EFS configured)."
    echo "  Ensure an Elastic IP is associated with this instance"
    echo "  to keep a stable address across stop/start cycles."
else
    echo "  Non-AWS setup, skipping Elastic IP check."
fi

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
echo "  3. Deploy workspace:   devpod up github.com/<user>/workspaces --provider <ws-name> --id <ws-name> --ide none"
echo ""
