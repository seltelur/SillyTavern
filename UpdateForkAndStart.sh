#!/usr/bin/env bash
# File: UpdateForkAndStart.sh
set -euo pipefail

# Update fork from upstream and start SillyTavern in Codespaces or any Linux box.
# Usage:
#   ./UpdateForkAndStart.sh [release|staging|main] [--stash|--no-stash] [--no-start]
# Default branch: release
# Default behavior: stash local changes, then fast-forward or merge if needed.

BRANCH="${1:-release}"
STASH="yes"
START="yes"

for arg in "$@"; do
  case "$arg" in
    --stash) STASH="yes" ;;
    --no-stash) STASH="no" ;;
    --no-start) START="no" ;;
    release|staging|main) BRANCH="$arg" ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing $1. Install it first."; exit 1; }; }
need git
need node
need npm

# Move to repo root
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${ROOT}" ]]; then
  echo "Not inside a Git repo. Open your SillyTavern folder first."
  exit 1
fi
cd "$ROOT"

# Ensure upstream remote exists
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream https://github.com/SillyTavern/SillyTavern.git
fi

echo "Fetching upstream..."
git fetch upstream

# Optional auto switch like the .bat sometimes provided
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
AUTO_SWITCH="$(git config --local --get script.autoSwitch || true)"  # "s" for staging, "r" for release

if [[ -n "$AUTO_SWITCH" ]]; then
  if [[ "$AUTO_SWITCH" == "s" ]]; then BRANCH="staging"; fi
  if [[ "$AUTO_SWITCH" == "r" ]]; then BRANCH="release"; fi
fi

echo "Target branch: $BRANCH (current: $CURRENT_BRANCH)"

# Switch branch if needed
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
  git checkout "$BRANCH" || git checkout -b "$BRANCH" --track "upstream/$BRANCH"
fi

# Handle local changes
if ! git diff --quiet || ! git diff --cached --quiet; then
  if [[ "$STASH" == "yes" ]]; then
    echo "Stashing local changes..."
    git stash push -u -m "auto-stash before update $(date -Iseconds)" >/dev/null || true
  else
    echo "Local changes present and --no-stash set. Update may fail."
  fi
fi

# Try fast-forward first, then merge if needed
set +e
git merge --ff-only "upstream/$BRANCH"
FF_RC=$?
set -e
if [[ $FF_RC -ne 0 ]]; then
  echo "Fast-forward not possible, merging upstream/$BRANCH..."
  git merge --no-edit "upstream/$BRANCH"
fi

# Install deps
export NODE_ENV=production
if [[ -f package-lock.json ]]; then
  npm ci || npm install
else
  npm install --no-audit --no-fund --loglevel=error --no-progress --omit=dev
fi

if [[ "$START" != "yes" ]]; then
  echo "Update complete. Skipping server start."
  exit 0
fi

# Start SillyTavern
PORT="${PORT:-8000}"
echo "Starting SillyTavern on port $PORT"
SILLYTAVERN_LISTEN=true \
SILLYTAVERN_WHITELISTMODE=false \
SILLYTAVERN_BASICAUTHMODE="${SILLYTAVERN_BASICAUTHMODE:-true}" \
SILLYTAVERN_BASICAUTHUSER_USERNAME="${SILLYTAVERN_BASICAUTHUSER_USERNAME:-user}" \
SILLYTAVERN_BASICAUTHUSER_PASSWORD="${SILLYTAVERN_BASICAUTHUSER_PASSWORD:-password}" \
node server.js --port "$PORT"
