# workspaces

Standardized remote dev environment for VPS/EC2.

## What this is

Devcontainer deployed via DevPod on remote Ubuntu machines. Terminal-first with Claude Code as the primary interface; graphical desktop via KasmVNC when needed. All state lives on persistent storage — compute is ephemeral and replaceable.

## Quick start

1. **Prerequisites:** DevPod installed on Mac, Ubuntu 22.04+ remote machine with SSH access
2. **Prepare host:** `ssh user@host 'curl -sSL https://raw.githubusercontent.com/dimdasci/workspaces/main/scripts/host-setup.sh | bash'`
3. **Deploy:** `devpod up . --provider ssh --option HOST=host`
4. **Connect:** `devpod ssh workspace`
5. **Browser desktop:** `ssh -L 8443:localhost:8443 host` then open `https://localhost:8443`

## What's inside

- **Runtimes:** Node.js/pnpm, Go
- **AI/Dev tools:** Claude Code, opencode
- **Cloud/Infra:** GitHub CLI, AWS CLI, Terraform
- **Desktop:** XFCE + KasmVNC
- **Shell:** tmux, standard Unix tooling
- **Media:** ffmpeg and related tools

## Documentation

See [`docs/manual.md`](docs/manual.md) for full setup guide, configuration, and troubleshooting.
