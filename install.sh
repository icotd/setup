#!/bin/bash

# List of packages to install (excluding redundant versions)
declare -A packages=(
  ["openjdk"]=1
  ["go"]=1
  ["make"]=1
  ["oven-sh/bun/bun"]=1
  ["node"]=1
  ["pnpm"]=1
  ["yarn"]=1
  ["postgresql@16"]=1
  ["python@3.12"]=1
  ["redis"]=1
  ["--cask docker"]=1
  ["--cask bruno"]=1
)

# Function to install a package if not already installed
install_package() {
  local package=$1
  if ! brew ls --versions "$package" > /dev/null; then
    echo "Installing $package..."
    brew install "$package"
  else
    echo "$package is already installed."
  fi
}

# Update Homebrew
echo "Updating Homebrew..."
brew update

# Install each package
for package in "${!packages[@]}"; do
  install_package "$package"
done

echo "All specified packages have been checked/installed."
