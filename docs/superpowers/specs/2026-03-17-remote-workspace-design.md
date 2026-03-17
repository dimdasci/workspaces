# Remote Workspace Design

Standardized, reproducible dev environment deployable on any remote Linux machine (VPS, AWS EC2) in minutes. Terminal-first workflow with Claude Code, graphical browser access when needed.

## Architecture overview

```
Mac (any terminal)                      Mac (browser)
  │                                       │
  └── SSH ──► devcontainer:2222           └── SSH tunnel -L 8443:localhost:8443
                │                                │
                └── tmux session                 └── KasmVNC ► XFCE ► Chromium
                      ├── Claude Code
                      ├── bash
                      └── ...

Remote host
  ├── Docker engine
  ├── EFS mount (AWS) or local disk (VPS)  ← persistent storage
  └── devcontainer
        ├── project files (from persistent storage)
        ├── .claude/ (memory, settings, sessions)
        ├── tools (node, go, terraform, etc.)
        ├── XFCE + KasmVNC (graphical desktop)
        └── Docker socket (sibling containers)
```

## Repository structure

```
workspace/
├── .devcontainer/
│   ├── devcontainer.json       # container spec, DevPod consumes this
│   ├── Dockerfile              # base image + apt packages
│   └── postCreate.sh           # runs inside container after build
├── host-setup.sh               # one-time host preparation
├── .gitignore                  # excludes decrypted secrets, .clipboard/, etc.
├── docs/
│   └── manual.md               # usage manual
└── CLAUDE.md
```

### What goes where

- **Dockerfile**: apt packages only. No npm/node/go — those come from devcontainer features. Includes: docker.io, XFCE4, KasmVNC, Chromium deps, media tools, tmux, mosh.
- **devcontainer.json**: features (node, go, claude-code, github-cli, aws-cli, sshd), mounts (Docker socket, persistent storage), env vars from decrypted secrets. No desktop-lite feature.
- **postCreate.sh**: TypeScript LSP, Terraform, ECS exec plugin, opencode, SSH authorized keys, tmux config, KasmVNC startup.
- **host-setup.sh**: installs Docker, mounts EFS (AWS) or sets up persistent directory (VPS), installs chezmoi+age, configures firewall. Run once per new machine.

All secrets (CLAUDE_CODE_OAUTH_TOKEN, GH_TOKEN, AWS creds, SSH keys) are managed exclusively by chezmoi+age in a separate private dotfiles repo. No secrets in this workspace repo.

## Connection architecture

### Terminal (primary work)

SSH into the devcontainer, tmux inside. Session persistence — SSH drops, reconnect, `tmux attach`, everything intact.

```
ssh -p 2222 user@remote-host
# tmux attaches automatically
```

### Graphical desktop (browser debugging, watching dev-browser)

SSH tunnel to KasmVNC, access via Mac browser. KasmVNC port 8443 is mapped from the container to the host via Docker port mapping in devcontainer.json (`forwardPorts` or `appPort`), then tunneled to the Mac.

```
ssh -L 8443:localhost:8443 remote-host
# Open https://localhost:8443 in Mac browser
```

XFCE desktop with proper app launcher, window management, taskbar. Chromium launchable from the menu.

### Mac shell aliases

Convenience aliases on the Mac for common operations:

```bash
# Connect to workspace terminal
alias ws1='ssh -p 2222 user@host1'

# Open browser tunnel
alias ws1-vnc='ssh -L 8443:localhost:8443 user@host1'

# Send clipboard image to remote (for Claude Code)
alias ws1-img='f=$(date +%Y%m%d-%H%M%S).png; pngpaste /tmp/$f && scp -P 2222 /tmp/$f user@host1:/workspace/.clipboard/$f && echo "/workspace/.clipboard/$f"'
```

## Clipboard synchronization

Two separate paths depending on where you're working:

### Terminal clipboard (SSH + tmux)

| Direction | Mechanism | Setup |
|---|---|---|
| Remote → Mac | OSC-52 escape sequence | `set -g set-clipboard on` in tmux.conf. Mac terminal must support OSC-52 (iTerm2, Ghostty, Alacritty). |
| Mac → Remote | Cmd+V sends text as keyboard input | Works by default over SSH. |
| Images Mac → Remote | pngpaste + scp alias | See Mac shell aliases above. |

### Desktop clipboard (KasmVNC + XFCE)

| Direction | Mechanism | Setup |
|---|---|---|
| Remote → Mac | KasmVNC Clipboard API (text + images) | Requires HTTPS or localhost (SSH tunnel provides this). |
| Mac → Remote | KasmVNC Clipboard API (text + images) | Same — automatic when browser tab has focus. |

KasmVNC uses the browser's Async Clipboard API. Bidirectional, supports text and PNG images. No manual clipboard panel clicking.

## Secrets and configuration

### Chezmoi + age

A private git repo managed by chezmoi stores all dotfiles and encrypted secrets:

- **Dotfiles**: `.bashrc`, `.gitconfig`, `.ssh/config`, tmux.conf — templated per machine via Go templates
- **Encrypted secrets**: SSH keys, tokens — encrypted with age, committed safely to git
- **Per-machine config**: `chezmoi.toml` (not committed) holds machine-specific data (context name, region, etc.)
- **Interactive bootstrap**: `.chezmoi.toml.tmpl` prompts for machine-specific values on first `chezmoi init`

### Secret flow on a new machine

1. `host-setup.sh` installs chezmoi + age
2. SCP the age identity key once (the only manual secret transfer)
3. `chezmoi init --apply <private-repo>` pulls dotfiles, decrypts secrets, configures everything
4. DevPod deploys the devcontainer, secrets available as env vars

### AWS-specific

IAM instance profiles provide AWS credentials on EC2 — no tokens needed. Only non-AWS secrets (Claude token, GH token) go through chezmoi+age.

## Security

`host-setup.sh` configures host-level security:

- **Firewall (ufw)**: only ports 22 (host SSH) and 2222 (container SSH) open. KasmVNC port 8443 bound to 127.0.0.1 only — accessible exclusively via SSH tunnel.
- **fail2ban**: protects SSH against brute force.
- **No root SSH**: `PermitRootLogin no` in sshd_config.
- **Key-only auth**: `PasswordAuthentication no` for both host and container SSH.

## Persistent storage

| Environment | Storage | Lifecycle |
|---|---|---|
| AWS EC2 | EFS mounted on host, bind-mounted into container | Survives instance termination |
| VPS | Local disk | VPS is long-lived |

### What persists (on persistent storage)

- Project files and git repos
- `.claude/` — memory, settings, session history
- `.claude.json` — MCP server config
Chezmoi state does not need explicit persistence — `chezmoi apply` is idempotent and re-runs on container rebuild.

### What's ephemeral (rebuilt from spec)

- The container itself
- Installed tools and runtimes
- Build caches

### Mount point

Persistent storage mounts at `/workspace` inside the container. All project work happens under this path.

### Container user

The devcontainer runs as user `vscode` (UID 1000) from the base image. On remote Linux hosts, the host user that owns the persistent storage must also be UID 1000, or `updateRemoteUserUID` in devcontainer.json must be set to remap. This avoids permission errors on bind mounts (unlike Docker Desktop on macOS, Linux does not transparently handle UID mismatches).

### Backups

Git is the backup for code. Claude state (`.claude/`) is useful but expendable — it can be rebuilt. EFS provides durability (replicated across AZs) but not protection against accidental deletion. VPS local disk has no redundancy. Backup strategy for persistent storage is out of scope for this project.

## Tech stack

### Devcontainer features

| Feature | Purpose |
|---|---|
| node (+ pnpm) | JavaScript/TypeScript runtime |
| go | Go runtime |
| claude-code | Claude Code CLI |
| github-cli | `gh` for GitHub operations |
| aws-cli | AWS CLI v2 |
| sshd | SSH access into container |

### Dockerfile apt packages

| Package | Purpose |
|---|---|
| docker.io | Docker socket passthrough for sibling containers |
| xfce4, dbus-x11 | Desktop environment |
| KasmVNC (.deb from GitHub releases, pinned version) | VNC server with web client and clipboard sync |
| libnss3, libgbm1, etc. | Chromium/Playwright dependencies |
| ffmpeg, imagemagick, exiftool, webp, poppler-utils, ghostscript, qpdf | Media processing tools |
| tmux | Terminal session management |
| mosh | Roaming SSH alternative (for unreliable connections — survives IP changes, sleep/wake) |

### postCreate.sh installs

| Tool | Purpose |
|---|---|
| typescript, typescript-language-server | TypeScript LSP for editors |
| terraform | AWS infrastructure provisioning |
| session-manager-plugin | AWS ECS exec |
| opencode | AI coding tool |
| age | Secret decryption (used by chezmoi) |

## DevPod workflow

### First-time setup

```bash
# Install DevPod on Mac
brew install devpod

# Add SSH provider
devpod provider add ssh

# Prepare remote host (run once per new machine)
ssh user@my-ec2 'curl -sSL https://raw.githubusercontent.com/<repo>/main/host-setup.sh | bash'

# Copy age key to remote host
scp ~/.age/key.txt user@my-ec2:~/.config/sops/age/keys.txt

# Bootstrap chezmoi on remote host
ssh user@my-ec2 'sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply <github-username>'
```

### Create workspace

```bash
devpod up ./workspace --provider ssh --option HOST=my-ec2.example.com
```

### Connect

```bash
devpod ssh my-workspace
# Inside: tmux session with Claude Code ready
```

### Multiple workspaces

```bash
devpod up ./workspace --provider ssh --option HOST=vps1.example.com --id work-1
devpod up ./workspace --provider ssh --option HOST=vps2.example.com --id work-2

# Switch between them
devpod ssh work-1
devpod ssh work-2
```

### Destroy and recreate

```bash
devpod delete work-1
# Persistent storage (EFS/disk) untouched
# Recreate on same or different machine:
devpod up ./workspace --provider ssh --option HOST=new-host.example.com --id work-1
```

## Docker (sibling containers)

The devcontainer mounts `/var/run/docker.sock` from the host. Claude and the developer can run Docker commands that create sibling containers (Postgres, Redis, app containers) on the host.

Each workspace uses a separate remote machine to avoid port conflicts. Docker Compose project names provide additional namespacing.

## Decisions log

| Topic | Decision | Reasoning |
|---|---|---|
| Deployment model | DevPod with SSH provider | Consumes devcontainer.json natively, manages lifecycle, works with any SSH-accessible machine |
| Machine provisioning | Manual (out of scope) | Can be added later with Terraform. Focus is on the environment, not infrastructure. |
| Secrets + dotfiles | Chezmoi with age encryption | No vendor lock-in, works everywhere, manages both dotfiles and secrets |
| Terminal | SSH + tmux inside container | Session persistence, pane management, works from any terminal |
| Desktop | XFCE + KasmVNC | Real desktop environment, bidirectional clipboard sync (text + images), browser-based access |
| Desktop access | SSH tunnel | Secure, no exposed ports, provides HTTPS context for Clipboard API |
| Terminal clipboard | OSC-52 (remote→local), Cmd+V (local→remote) | Works in iTerm2/Ghostty/Alacritty, configured in tmux |
| Image transfer | pngpaste + scp alias | Same proven pattern as current local setup |
| Persistent storage | EFS (AWS), local disk (VPS) | Survives instance termination, separates state from compute |
| Container runtime isolation | One workspace per machine | Avoids port conflicts, clean resource separation |
| Tech stack | Node/pnpm, Go, TS LSP, AWS CLI, GitHub CLI, Terraform, ECS exec, Chromium, media tools, opencode | Matches current workflow + additions |
