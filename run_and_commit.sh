#!/usr/bin/env bash
set -euo pipefail

# Run mimotion, persist tokens and auto-commit changes using a GitHub PAT.
# Required environment variables:
#   CONFIG  - JSON string for program config
#   AES_KEY - 16-byte AES key (optional)
#   GIT_PAT - GitHub personal access token with repo permissions

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# Create venv if missing
if [ ! -d "venv" ]; then
  python3 -m venv venv
  source venv/bin/activate
  pip install --upgrade pip
  if [ -f requirements.txt ]; then
    pip install -r requirements.txt
  fi
else
  source venv/bin/activate
fi

echo "Running main.py at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Ensure CONFIG is set
if [ -z "${CONFIG-}" ]; then
  echo "ERROR: CONFIG environment variable is not set. Exiting." >&2
  exit 1
fi

python main.py

# Commit changes if any
git add encrypted_tokens.data cron_change_time || true
if [ -n "$(git status --porcelain)" ]; then
  git commit -m "Auto update tokens/cron: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" || true

  if [ -z "${GIT_PAT-}" ]; then
    echo "GIT_PAT not set; skipping push. Configure GIT_PAT env var to enable push." >&2
    exit 0
  fi

  origin_url=$(git config --get remote.origin.url || true)
  if [ -z "$origin_url" ]; then
    echo "remote.origin.url not found; please configure repository remotes." >&2
    exit 1
  fi

  # derive repo path
  repo_path=""
  if [[ "$origin_url" == git@github.com:* ]]; then
    repo_path=${origin_url#git@github.com:}
  elif [[ "$origin_url" == https://github.com/* ]]; then
    repo_path=${origin_url#https://github.com/}
  else
    # fallback: try to extract trailing path
    repo_path=$(basename -s .git "$origin_url")
  fi

  # Ensure repo_path ends with .git
  if [[ "$repo_path" != *.git ]]; then
    repo_path="${repo_path}.git"
  fi

  push_url="https://${GIT_PAT}@github.com/${repo_path}"

  # push current branch
  branch=$(git rev-parse --abbrev-ref HEAD)
  echo "Pushing changes to ${push_url} (branch ${branch})"
  git push "$push_url" "HEAD:${branch}"
else
  echo "No changes to commit."
fi

echo "Done."
