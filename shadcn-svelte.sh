#!/bin/bash

# Create "shadcn-svelte" directory if it doesn't exist
PARENT_DIR="shadcn-svelte"
if [ ! -d "$PARENT_DIR" ]; then
    mkdir -p "$PARENT_DIR"
    echo "Created directory: $PARENT_DIR"
else
    echo "Directory already exists: $PARENT_DIR"
fi

# Directory where you want to clone the specific folder
TARGET_DIR="$PARENT_DIR/components"

# GitHub repository URL
REPO_URL="https://github.com/icotd/shadcn-svelte.git"

# Branch you want to pull from
BRANCH="next"

# Base directory for sparse checkout
BASE_DIR="sites/docs/src/routes/(app)/examples"

# Prompt user for the component directory
read -p "Enter the component directory (e.g., authentication/(components)): " COMPONENT_DIR

# Combine the base directory with the user-provided component directory
SPARSE_DIR="$BASE_DIR/$COMPONENT_DIR"

# Check if the component directory is not empty
if [ -z "$COMPONENT_DIR" ]; then
    echo "Component directory cannot be empty. Exiting..."
    exit 1
fi

# Create and navigate to the target directory
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR" || { echo "Failed to enter directory: $TARGET_DIR"; exit 1; }

# Initialize a new Git repository
git init

# Add the remote repository
git remote add origin "$REPO_URL"

# Enable sparse checkout
git sparse-checkout init --cone

# Set the specific directory to checkout
git sparse-checkout set "$SPARSE_DIR"

# Pull the required branch
git pull origin "$BRANCH"

echo "Successfully cloned the directory: $SPARSE_DIR"
