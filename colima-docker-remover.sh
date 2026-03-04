#!/usr/bin/env bash
set -euo pipefail

echo "Stopping Colima (if running)..."
if command -v colima >/dev/null 2>&1; then
  colima stop || true
  colima delete || true
fi

echo "Uninstalling Docker/Colima related brew packages..."
brew uninstall --ignore-dependencies colima docker docker-compose lima 2>/dev/null || true

echo "Removing unused dependencies..."
brew autoremove

echo "Removing leftover runtime directories..."
rm -rf ~/.colima
rm -rf ~/.docker
rm -rf ~/.lima

echo "Cleaning Homebrew cache..."
brew cleanup

echo "Verifying removal..."
brew list | grep -E "docker|colima|lima" || echo "No docker/colima/lima brew packages remain."

ps aux | grep -E "docker|colima|lima" | grep -v grep || echo "No related processes running."

echo "Done."
