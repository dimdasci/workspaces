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

**AWS EC2 example:** Ubuntu 24.04 AMI, t4g.xlarge (arm64, 4 vCPU, 16 GB), 64 GB gp3 EBS, security group allowing SSH (port 22) only. Allocate an Elastic IP so the address survives stop/start. Create an EFS filesystem in the same VPC/AZ and assign the same security group as the EC2 instance (NFS port 2049 must be open within the SG).

> **`host-setup.sh` handles all host configuration** — Docker, EFS mount, firewall, memory limits. Do not manually install `amazon-efs-utils`, edit `/etc/fstab`, or create `/workspace`. Just run the script in step 2.

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

Chezmoi manages dotfiles and secrets across workspaces. It stores your config in a private git repo and applies it inside the container. Skip this step on first setup — come back after the workspace is running.

See [Chezmoi guide](#chezmoi-guide) below for the full walkthrough.

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
ssh -L <local-port>:localhost:8443 <ws-name>.devpod
```
Pick any free local port (e.g. 9443). Then open `https://localhost:<local-port>` in your browser (accept the self-signed cert warning). Password: `vscode`. XFCE desktop with Chromium in the app menu.

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

**Fresh EFS (no existing dotfiles):** `postCreate.sh` tried to clone your chezmoi dotfiles during `devpod up` but failed because `gh auth` wasn't set up yet. After `gh auth login` above, re-run it:
```bash
/workspaces/<ws-name>/.devcontainer/postCreate.sh
```
Reconnect to pick up `.bash_aliases`.

## tmux cheatsheet

All commands start with `Ctrl+b` (prefix), then a second key.

**Sessions:**
| Keys | Action |
|---|---|
| `tmux` | Start new session |
| `Ctrl+b d` | Detach (session keeps running) |
| `tmux attach` | Reattach to session |

**Panes (splits):**
| Keys | Action |
|---|---|
| `Ctrl+b "` | Split horizontal (top/bottom) |
| `Ctrl+b %` | Split vertical (left/right) |
| `Ctrl+b arrow` | Move between panes |
| `Ctrl+b x` | Close pane (confirm with `y`) |

**Windows (tabs):**
| Keys | Action |
|---|---|
| `Ctrl+b c` | New window |
| `Ctrl+b n` / `Ctrl+b p` | Next / previous window |
| `Ctrl+b 0-9` | Jump to window by number |

Detach/attach is the killer feature: your session survives SSH disconnects. Reconnect and `tmux attach` — everything is where you left it.

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
alias ws1-img='f=$(date +%Y%m%d-%H%M%S).png; pngpaste /tmp/$f && scp /tmp/$f ec2-ws.devpod:/workspace/.clipboard/$f && echo "/workspace/.clipboard/$f"'
```
Copy image to clipboard, run `ws1-img`, pass the printed path to Claude. Uses DevPod's SSH tunnel — no port configuration needed.

## Mac shell aliases

```bash
# Add to ~/.zshrc — one set per workspace
alias ws1='ssh ec2-ws.devpod'
alias ws1-vnc='ssh -L 9443:localhost:8443 ec2-ws.devpod'
alias ws1-img='f=$(date +%Y%m%d-%H%M%S).png; pngpaste /tmp/$f && scp /tmp/$f ec2-ws.devpod:/workspace/.clipboard/$f && echo "/workspace/.clipboard/$f"'
```
Replace `ec2-ws` with your workspace name. Pick any free local port for VNC (9443, 8444, etc.).

## Container shell aliases

Aliases inside the container live in `/workspace/.bash_aliases` (persistent, managed by chezmoi). The container's `.bashrc` sources this file automatically via a symlink set up by postCreate.sh.

```bash
# View all aliases
alias

# View a specific alias
alias cld

# Edit aliases
chezmoi edit /workspace/.bash_aliases
# or edit directly and sync:
vim /workspace/.bash_aliases
chezmoi add /workspace/.bash_aliases

# Reload after editing (or just reconnect)
source ~/.bash_aliases
```

Default aliases shipped via chezmoi:

| Alias | Command |
|---|---|
| `cld` | `claude --dangerously-skip-permissions --append-system-prompt-file /workspace/.claude/system-prompt.md` |

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

## Lifecycle

**Stop** (container stops, nothing is deleted):
```bash
devpod stop <ws-name>
```

**Start** (restarts a stopped container, no rebuild):
```bash
devpod up <ws-name>
```

If the remote VM was stopped and restarted, `devpod up <ws-name>` detects the existing container and starts it.

**Delete and recreate** (container is removed, `/workspace` files are untouched):
```bash
devpod delete <ws-name>
devpod up github.com/dimdasci/workspaces --provider <ws-name> --id <ws-name> --ide none
```

Delete + recreate is needed after Dockerfile changes.

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

- Firewall: port 22 (SSH) only — container ports are not published, accessed via DevPod tunnel
- SSH: key-only, no root, fail2ban
- Secrets: chezmoi + age in a separate private repo, never in this repo
- Docker memory limits auto-calculated from host RAM

## Chezmoi guide

Chezmoi keeps your dotfiles in a private git repo. On a fresh workspace, one command restores everything. Sensitive files (API keys, tokens) are encrypted with age.

### How it works

```
Private git repo (e.g. github.com/you/stuff)
  └── dot_gitconfig              ← plain file, becomes /workspace/.gitconfig
  └── encrypted_dot_env.age      ← encrypted, decrypted on apply
  └── dot_claude/settings.json   ← directory structure preserved

chezmoi apply  →  /workspace/.gitconfig
                   /workspace/.env
                   /workspace/.claude/settings.json
```

Chezmoi renames files: `dot_` prefix becomes `.`, `encrypted_` files are decrypted, directories map to paths. The source repo is safe to push to GitHub — encrypted files can't be read without your age key.

### First-time setup

**1. Create a private repo** (e.g. `github.com/<you>/stuff`) on GitHub.

**2. Inside the container**, install and init chezmoi:

```bash
# Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

# Init with your repo, store source in /workspace so it persists
chezmoi init <your-github-username>/stuff --source /workspace/.chezmoi-source

# Tell chezmoi to target /workspace instead of ~
mkdir -p ~/.config/chezmoi
cat > ~/.config/chezmoi/chezmoi.toml << 'EOF'
sourceDir = "/workspace/.chezmoi-source"
destDir = "/workspace"
EOF
```

**3. Add files** you want managed:

```bash
# Track a file — chezmoi copies it into the source repo
chezmoi add /workspace/.gitconfig
chezmoi add /workspace/.claude/settings.json

# See what chezmoi manages
chezmoi managed
```

**4. Edit managed files** — two ways:

```bash
# Option A: edit through chezmoi (source stays in sync automatically)
chezmoi edit /workspace/.gitconfig

# Option B: edit the file directly, then sync back to chezmoi
vim /workspace/.gitconfig
chezmoi add /workspace/.gitconfig   # re-sync after direct edit
```

**5. Push to your repo:**

```bash
cd /workspace/.chezmoi-source
git add -A && git commit -m "Add dotfiles" && git push
```

### On a fresh workspace

After `devpod up` creates a new container:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

mkdir -p ~/.config/chezmoi
cat > ~/.config/chezmoi/chezmoi.toml << 'EOF'
sourceDir = "/workspace/.chezmoi-source"
destDir = "/workspace"
EOF

chezmoi init --apply <your-github-username>/stuff --source /workspace/.chezmoi-source
```

All your dotfiles are restored. If `/workspace/.chezmoi-source` already exists from a previous container (persisted on EFS), chezmoi pulls the latest and applies.

### Encrypted files (secrets)

For API keys, tokens, and other secrets — encrypt with age:

```bash
# One-time: set up age encryption
mkdir -p /workspace/.age
age-keygen -o /workspace/.age/key.txt   # or copy from your Mac

# Tell chezmoi to use your age key
cat >> ~/.config/chezmoi/chezmoi.toml << 'EOF'

encryption = "age"
[age]
    identity = "/workspace/.age/key.txt"
    recipient = "age1..."  # your public key from key.txt
EOF

# Add a secret file — chezmoi encrypts it automatically
chezmoi add --encrypt /workspace/.env
```

The encrypted file appears as `encrypted_dot_env.age` in the source repo — safe to push.

### Chezmoi cheatsheet

| Command | Action |
|---|---|
| `chezmoi add <file>` | Start managing a file |
| `chezmoi add --encrypt <file>` | Manage with encryption |
| `chezmoi edit <file>` | Edit a managed file |
| `chezmoi apply` | Apply all managed files to target |
| `chezmoi diff` | Preview what `apply` would change |
| `chezmoi managed` | List all managed files |
| `chezmoi update` | Pull latest from repo + apply |
| `chezmoi cd` | cd into the source directory |

### What to manage with chezmoi

| File | Why |
|---|---|
| `/workspace/.gitconfig` | Git identity |
| `/workspace/.claude/settings.json` | Claude Code preferences |
| `/workspace/.config/gh/hosts.yml` | GitHub CLI auth (encrypt) |
| `/workspace/.env` | API keys, tokens (encrypt) |
| `/workspace/.tmux.conf` | tmux customization |

## Troubleshooting

**"Too many authentication failures" or agent injection timeout:**
DevPod bulk-loads all `~/.ssh/` keys into the SSH agent by default. Fix: `devpod context set-options -o SSH_ADD_PRIVATE_KEYS=false` and ensure your provider has `-o IdentitiesOnly=yes -i <key>` in EXTRA_FLAGS.

**EC2 IP changed after stop/start:**
Allocate an Elastic IP and associate it with the instance. Then update the provider: `devpod provider set-options <ws-name> -o HOST=ubuntu@<new-ip>`

**SSH host key changed after rebuild:**
```bash
ssh-keygen -R "<host>"
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

**"Error opening terminal: alacritty" (or similar):**
Your local `$TERM` is passed to the remote, but the terminfo entry may be missing. `postCreate.sh` installs alacritty terminfo via `tic`, but it can fail silently on transient network issues. Fix: `curl -fsSL "https://raw.githubusercontent.com/alacritty/alacritty/master/extra/alacritty.info" | tic -x -`

**"Duplicate mount point: /workspace":**
Do NOT set `workspaceFolder` or `workspaceMount` in devcontainer.json. DevPod mounts repo source to `/workspaces/<id>` by default. EFS is at `/workspace` via explicit bind mount in `mounts[]`. Setting `workspaceFolder: "/workspace"` makes DevPod try to mount source there too — conflict. Use `cd /workspace` in `.bash_aliases` to land in EFS instead.

**`postCreate.sh` changes not applied after `devpod up --recreate`:**
DevPod caches the repo clone and doesn't pull on recreate. `postCreate.sh` runs `git pull --ff-only` at start to self-update, but if the container fails before reaching that point (e.g. mount error), the old code runs. Fix: pull manually on the host first: `ssh -i <key> ubuntu@<ip> 'cd /home/ubuntu/.devpod/agent/contexts/default/workspaces/<id>/content && git pull'`

**Claude Code colors washed out / unreadable diffs in tmux:**
Claude Code v2.1.77+ hardcodes a 256-color downgrade when `$TMUX` is set, ignoring `COLORTERM=truecolor` and `FORCE_COLOR=3`. 24-bit diff highlight colors get approximated to the nearest 256-color match, making them oversaturated and unreadable. Tracked in [#36785](https://github.com/anthropics/claude-code/issues/36785). Workaround — launch Claude Code with `TMUX` cleared:
```bash
# In .bash_aliases
alias claude="TMUX= command claude"
```
Note: `env -u TMUX command claude` does NOT work — `env` can't call bash builtins like `command`. Use `TMUX= command claude` instead.

**chezmoi source repo permission denied after `docker exec` as root:**
Running `docker exec` without `-u vscode` creates files as root in `/workspace/.chezmoi-source/.git`, breaking git operations. Fix: `sudo chown -R vscode:vscode /workspace/.chezmoi-source/.git`. Avoid `docker exec` without `-u vscode` when touching `/workspace`.

**Docker build fails with "no space left on device":**
Docker images, layers, and build cache accumulate on the EBS root volume. Clean up: `docker system prune -a -f && docker builder prune -a -f`. If recurring, resize the EBS volume (can be done online without downtime): `aws ec2 modify-volume --volume-id <vol-id> --size 64`, then on the host: `sudo growpart /dev/nvme0n1 1 && sudo resize2fs /dev/nvme0n1p1`. 64GB is a safe size for dev workloads with multiple containers.

**KasmVNC doesn't load in Safari:**
Safari has issues with KasmVNC's WebSocket connection. Use Chrome or any Chromium-based browser instead.

**tmux not using true color despite Tc override:**
tmux matches terminal overrides against the outer `$TERM`. If SSH sets `TERM=dumb` or `xterm-256color` instead of `alacritty`, the `,alacritty:Tc` override won't match. Check with `tmux display-message -p '#{client_termname}'` and `tmux info | grep Tc` inside tmux. Ensure your local terminal sets `$TERM` correctly and SSH forwards it (`SendEnv TERM` in ssh_config, `AcceptEnv TERM` in sshd_config).

**`ssh <ws-name>.devpod` — "Could not resolve hostname":**
DevPod creates SSH config entries during `devpod up`. If it crashed or was interrupted, the entry may be missing. Re-run `devpod up <ws-name>` to recreate it. If that doesn't help, verify with `grep <ws-name> ~/.ssh/config` and add manually:
```
# DevPod Start <ws-name>.devpod
Host <ws-name>.devpod
  ForwardAgent yes
  LogLevel error
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  HostKeyAlgorithms rsa-sha2-256,rsa-sha2-512,ssh-rsa
  ProxyCommand "$(which devpod)" ssh --stdio --context default --user vscode <ws-name>
  User vscode
# DevPod End <ws-name>.devpod
```
Replace `$(which devpod)` with the actual path (e.g. `/opt/homebrew/bin/devpod` on macOS ARM).

## Full documentation

See [`docs/manual.md`](docs/manual.md) for detailed configuration, AWS IAM setup, and architecture decisions.
