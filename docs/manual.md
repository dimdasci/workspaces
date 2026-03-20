## Overview

Standardized remote workspace running as a devcontainer on a remote Linux machine (EC2, VPS, or any Ubuntu/Debian host). Provides both a terminal environment and a graphical XFCE desktop with Chromium. Managed via DevPod from your Mac: one command provisions the container, SSH gives you a proper terminal, and KasmVNC over an SSH tunnel gives you the desktop. All project files live on the remote host at `/workspace`; the container is stateless and can be destroyed and recreated without data loss.

---

## Prerequisites

**Mac (local):**
- DevPod: `brew install devpod`
- pngpaste (clipboard image transfer): `brew install pngpaste`
- SSH key at `~/.ssh/id_ed25519` — generate if missing: `ssh-keygen -t ed25519`

**Remote machine:**
- Ubuntu 22.04+ or Debian Bookworm
- SSH access with sudo privileges
- Minimum: 4 GB RAM, 2 vCPU
- Recommended: 8 GB+ RAM for headed Chromium

---

## First-time host setup

Run once per remote machine before creating any workspace.

```bash
# Install Docker, configure sshd, create /workspace
ssh user@my-ec2 'curl -sSL https://raw.githubusercontent.com/dimdasci/workspaces/main/host-setup.sh | bash'

# Copy age key for chezmoi secret decryption
scp ~/.age/key.txt user@my-ec2:~/.config/chezmoi/key.txt

# Bootstrap chezmoi (dotfiles: shell config, tmux, etc.)
ssh user@my-ec2 'chezmoi init --apply <github-username>'
```

---

## Creating a workspace

```bash
devpod provider add ssh        # once per Mac, skip if already added
devpod up ./workspace --provider ssh --option HOST=my-ec2.example.com
```

DevPod clones this repo into the remote host and starts the devcontainer. On first run this takes a few minutes for the image build.

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

Container memory and shared memory are configurable via environment variables on the remote host:

| Variable | Default | Purpose |
|---|---|---|
| `WORKSPACE_MEMORY` | `12g` | Container memory limit |
| `WORKSPACE_SHM` | `2g` | Shared memory size |

---

## Multiple workspaces

Each workspace is an independent DevPod environment, optionally on different hosts:

```bash
devpod up ./workspace --provider ssh --option HOST=vps1 --id work-1
devpod up ./workspace --provider ssh --option HOST=vps2 --id work-2

devpod ssh work-1
devpod ssh work-2
```

No port conflicts — container ports are not published to the host. DevPod tunnels all traffic through the host's SSH port (22).

---

## Destroying and recreating

```bash
devpod delete work-1

# Recreate on the same or a different host
devpod up ./workspace --provider ssh --option HOST=new-host --id work-1
```

The container is stateless. `/workspace` on the host is not touched by `devpod delete`. All project files, `.claude/`, and git repos survive the rebuild.

---

## Persistent storage

| Layer | What persists |
|---|---|
| `/workspace` on host | project files, `.claude/`, git repos, `.clipboard/` |
| Container | nothing — ephemeral, rebuilt on `devpod up` |
| Tool caches | lost on rebuild (npm, pip, go module caches) |

**AWS EC2**: attach EFS and mount at `/workspace` before running `host-setup.sh`. Add to `/etc/fstab`:

```
fs-xxx.efs.region.amazonaws.com:/ /workspace efs _netdev,tls 0 0
```

Install the utils first: `sudo apt-get install -y amazon-efs-utils`

**VPS**: local disk at `/workspace` — persists across rebuilds, lost if you wipe the VPS.

---

## AWS-specific setup

### EFS

Create the filesystem in the same VPC and availability zone as your EC2 instance. Add the mount entry to `/etc/fstab` (see above) before running `host-setup.sh` so `/workspace` is mounted when the container starts.

### IAM instance profile

Attach an IAM role to the EC2 instance with required permissions. The AWS CLI inside the container picks up credentials from the instance metadata service automatically — no static keys or token files needed.

---

## Security

- **Firewall**: port 22 (SSH) only — container ports are not published, accessed via DevPod tunnel.
- **SSH**: key-only auth, no password login, no root login, fail2ban active after `host-setup.sh`.
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
