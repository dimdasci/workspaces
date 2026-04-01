#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# postAuth.sh — run once after 'gh auth login' on a new container
#
# Initializes chezmoi from a private repo and sets up symlinks for
# chezmoi-managed dotfiles. On subsequent rebuilds, postCreate.sh
# handles this automatically (chezmoi source persists on /workspace).
# =============================================================================

export PATH="${HOME}/.local/bin:${PATH}"

# ── Preflight checks ────────────────────────────────────────────────────────

if ! gh auth status &>/dev/null; then
    echo "ERROR: gh is not authenticated. Run 'gh auth login' first." >&2
    exit 1
fi

if ! command -v chezmoi &>/dev/null; then
    echo "ERROR: chezmoi not found. Was postCreate.sh run?" >&2
    exit 1
fi

if [ ! -f /workspace/.age/key.txt ]; then
    echo "ERROR: age key not found at /workspace/.age/key.txt" >&2
    exit 1
fi

# ── chezmoi init ─────────────────────────────────────────────────────────────

if [ -d /workspace/.chezmoi-source/.git ]; then
    echo "==> Chezmoi source exists, updating and applying"
    chezmoi update --source /workspace/.chezmoi-source
else
    echo "==> Initializing chezmoi from repo"
    rm -rf /workspace/.chezmoi-source
    chezmoi init dimdasci/stuff --source /workspace/.chezmoi-source --apply
fi

# ── Symlinks for chezmoi-managed files ───────────────────────────────────────

echo "==> Setting up dotfile symlinks"

[ -f /workspace/.bash_aliases ] && ln -sf /workspace/.bash_aliases "${HOME}/.bash_aliases"
[ -f /workspace/.tmux.conf ] && ln -sf /workspace/.tmux.conf "${HOME}/.tmux.conf"
[ -d /workspace/.aws ] && { rm -rf "${HOME}/.aws"; ln -sf /workspace/.aws "${HOME}/.aws"; }

echo "==> Done. Restart your shell or run: source ~/.bash_aliases"
