# README Clarity Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix four documentation gaps in README.md that caused friction during new instance setup.

**Architecture:** Four independent edits to README.md. No code changes. Each task is one edit + commit.

**Tech Stack:** Markdown

**Spec:** `docs/superpowers/specs/2026-03-22-readme-clarity-design.md`

---

### Task 1: Add prerequisites warning about host-setup.sh

**Files:**
- Modify: `README.md` — after the "AWS EC2 example" paragraph in Prerequisites section

- [ ] **Step 1: Add warning paragraph**

After the paragraph starting with `**AWS EC2 example:**` (ends with "NFS port 2049 must be open within the SG")."), add:

```markdown

> **`host-setup.sh` handles all host configuration** — Docker, EFS mount, firewall, memory limits. Do not manually install `amazon-efs-utils`, edit `/etc/fstab`, or create `/workspace`. Just run the script in step 2.
```

- [ ] **Step 2: Verify**

Read the Prerequisites section and confirm the warning appears directly after the AWS EC2 example paragraph, before "## Setup".

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add prerequisites warning: host-setup.sh handles all config"
```

---

### Task 2: Add fresh-EFS chezmoi recovery to step 7

**Files:**
- Modify: `README.md` — step 7 ("First-time setup inside the container")

- [ ] **Step 1: Append fresh-EFS paragraph**

After the existing `gh auth login` code block in step 7, before the next section (`## tmux cheatsheet`), add this text (note: NOT a blockquote, just a regular paragraph like the rest of step 7):

    **Fresh EFS (no existing dotfiles):** `postCreate.sh` tried to clone your chezmoi dotfiles during `devpod up` but failed because `gh auth` wasn't set up yet. After `gh auth login` above, re-run it:
    ```bash
    /workspaces/<ws-name>/.devcontainer/postCreate.sh
    ```
    Reconnect to pick up `.bash_aliases`.

- [ ] **Step 2: Verify**

Read step 7 and confirm the fresh-EFS note appears after `gh auth login`, before `## tmux cheatsheet`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add fresh-EFS chezmoi recovery to first-time setup step"
```

---

### Task 3: Add troubleshooting — DevPod SSH config missing

**Files:**
- Modify: `README.md` — Troubleshooting section

- [ ] **Step 1: Add troubleshooting entry**

Add to the Troubleshooting section (after the existing entries, before `## Full documentation`):

```markdown
**`ssh <ws-name>.devpod` — "Could not resolve hostname":**
DevPod creates SSH config entries during `devpod up`. If it crashed or was interrupted, the entry may be missing. Re-run `devpod up <ws-name>` to recreate it. If that doesn't help, verify with `grep <ws-name> ~/.ssh/config` and add manually:
\```
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
\```
Replace `$(which devpod)` with the actual path (e.g. `/opt/homebrew/bin/devpod` on macOS ARM).
```

- [ ] **Step 2: Verify**

Read the Troubleshooting section and confirm the entry appears correctly.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add troubleshooting: DevPod SSH config missing after crash"
```

---

### Task 4: Add troubleshooting — DevPod git credential crash (after Task 3)

**Files:**
- Modify: `README.md` — Troubleshooting section

- [ ] **Step 1: Add troubleshooting entry**

Add to the Troubleshooting section (after the SSH config entry from Task 3):

```markdown
**DevPod `devpod up` crashes with "tunnelServer.GitCredentials" stack trace:**
This is a DevPod bug in git credential forwarding — usually non-fatal. The container is likely running. Verify: `devpod ssh <ws-name> -- echo ok`. If it connects, the workspace is fine. Check that the SSH config entry was created (see above).
```

- [ ] **Step 2: Verify**

Read the Troubleshooting section and confirm both new entries appear.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add troubleshooting: DevPod git credential crash is non-fatal"
```
