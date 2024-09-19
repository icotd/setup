#!/bin/bash

# Cleanup Homebrew installation
echo "Cleaning up outdated packages..."
brew cleanup

echo "Removing unused dependencies..."
brew autoremove

echo "Clearing Homebrew cache..."
rm -rf ~/Library/Caches/Homebrew

echo "Checking for issues with Homebrew..."
brew doctor

echo "Cleanup complete!"
