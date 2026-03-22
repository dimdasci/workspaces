# README clarity improvements

**Date:** 2026-03-22
**Goal:** Fix four documentation gaps that caused friction during new instance setup.

## Problem

Setting up a new EC2 instance with fresh EFS required ~15 manual steps and troubleshooting because the README didn't prevent common detours or document recovery paths. The setup flow itself works — the docs just have gaps.

## Pain points

1. User manually installed `amazon-efs-utils` and edited `/etc/fstab` before realizing `host-setup.sh --efs` does it all
2. `postCreate.sh` silently fails chezmoi init on fresh EFS (no `gh auth` yet), no guidance on what to do next
3. DevPod crash during `devpod up` skipped SSH config creation, no documented recovery
4. DevPod git credential tunnel crash looked fatal but wasn't — no docs explaining this

## Changes

### Change 1: Prerequisites — warning not to manually configure

**Location:** After the "AWS EC2 example" paragraph in Prerequisites

Add:

> **`host-setup.sh` handles all host configuration** — Docker, EFS mount, firewall, memory limits. Do not manually install `amazon-efs-utils`, edit `/etc/fstab`, or create `/workspace`. Just run the script in step 2.

**Why:** The README lists EFS/SG prerequisites, then jumps to step 1 (SSH). A user reading sequentially may start configuring EFS manually instead of waiting for the script.

### Change 2: Extend existing step 7 — fresh EFS chezmoi recovery

**Location:** Append to existing step 7 ("First-time setup inside the container"), after the `gh auth login` block.

Add:

> **Fresh EFS (no existing dotfiles):** `postCreate.sh` tried to clone your chezmoi dotfiles during `devpod up` but failed because `gh auth` wasn't set up yet. After `gh auth login` above, re-run it:
> ```bash
> /workspaces/<ws-name>/.devcontainer/postCreate.sh
> ```
> Reconnect to pick up `.bash_aliases`.

**Why:** On fresh EFS, chezmoi can't clone a private repo without gh auth. The silent failure leaves the user with a half-configured workspace and no indication of what to do. Merging into step 7 avoids duplication (step 7 already covers `gh auth`) and contradiction with step 3's "skip chezmoi for initial testing."

### Change 3: Troubleshooting — SSH config missing after DevPod crash

**Location:** Troubleshooting section

Add:

> **`ssh <ws-name>.devpod` — "Could not resolve hostname":**
>
> DevPod creates SSH config entries during `devpod up`. If it crashed or was interrupted, the entry may be missing. Re-run `devpod up <ws-name>` to recreate it. If that doesn't help, verify with `grep <ws-name> ~/.ssh/config` and add manually:
> ```
> # DevPod Start <ws-name>.devpod
> Host <ws-name>.devpod
>   ForwardAgent yes
>   LogLevel error
>   StrictHostKeyChecking no
>   UserKnownHostsFile /dev/null
>   HostKeyAlgorithms rsa-sha2-256,rsa-sha2-512,ssh-rsa
>   ProxyCommand "$(which devpod)" ssh --stdio --context default --user vscode <ws-name>
>   User vscode
> # DevPod End <ws-name>.devpod
> ```
> Replace `$(which devpod)` with the actual path (e.g. `/opt/homebrew/bin/devpod` on macOS ARM).

**Why:** DevPod crash left no SSH config entry. The user couldn't connect via the standard `ssh <ws>.devpod` alias and had no way to know what was missing.

### Change 4: Troubleshooting — DevPod git credential crash

**Location:** Troubleshooting section

Add:

> **DevPod `devpod up` crashes with "tunnelServer.GitCredentials" stack trace:**
>
> This is a DevPod bug in git credential forwarding — usually non-fatal. The container is likely running. Verify: `devpod ssh <ws-name> -- echo ok`. If it connects, the workspace is fine. Check that the SSH config entry was created (see above).

**Why:** The stack trace looks like a fatal error but the container is actually running. Without this note, the user may think setup failed entirely.

## Out of scope

- No changes to `host-setup.sh` or `postCreate.sh`
- No changes to `devcontainer.json` or `Dockerfile`
- Blog post content (separate effort, tracked in memory)
