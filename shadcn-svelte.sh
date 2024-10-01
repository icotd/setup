#!/bin/bash

# Create "shadcn-svelte" directory if it doesn't exist
PARENT_DIR="shadcn-svelte"
if [ ! -d "$PARENT_DIR" ]; then
    mkdir -p "$PARENT_DIR"
    echo "Created directory: $PARENT_DIR"
else
    echo "Directory already exists: $PARENT_DIR"
fi

# GitHub repository URL
REPO_URL="https://github.com/icotd/shadcn-svelte.git"

# Branch you want to pull from
BRANCH="next"

# Base directory for sparse checkout
BASE_DIR="sites/docs/src"
SPARSE_LIB_DIR="$BASE_DIR/lib/registry/new-york/ui"
SPARSE_EXAMPLES_DIR="$BASE_DIR/routes/(app)/examples"

# Prompt user for the component directory
read -p "Enter the component directory (e.g., authentication/(components)): " COMPONENT_DIR

# Check if the component directory is not empty
if [ -z "$COMPONENT_DIR" ]; then
    echo "Component directory cannot be empty. Exiting..."
    exit 1
fi

# Combine the examples directory with the user-provided component directory
SPARSE_EXAMPLES="$SPARSE_EXAMPLES_DIR/$COMPONENT_DIR"

# Create the necessary directories to match the structure
mkdir -p "$PARENT_DIR/$SPARSE_LIB_DIR"
mkdir -p "$PARENT_DIR/$SPARSE_EXAMPLES_DIR"

# Function to clone a directory
clone_repo() {
    local TARGET_DIR=$1
    local SPARSE_DIR=$2

    # Initialize a new Git repository if it doesn't exist
    if [ ! -d "$TARGET_DIR/.git" ]; then
        cd "$TARGET_DIR" || { echo "Failed to enter directory: $TARGET_DIR"; exit 1; }
        git init
        git remote add origin "$REPO_URL"
        git sparse-checkout init --cone
    else
        cd "$TARGET_DIR" || { echo "Failed to enter directory: $TARGET_DIR"; exit 1; }
    fi

    # Set the specific directory to checkout
    git sparse-checkout set "$SPARSE_DIR"

    # Pull the required branch
    git pull origin "$BRANCH"

    echo "Successfully cloned the directory: $SPARSE_DIR into $TARGET_DIR"
}

# Clone the lib/ui directory directly into its original path
clone_repo "$PARENT_DIR" "$SPARSE_LIB_DIR"

# Wait for a few seconds to allow the user to see the success message
echo "Waiting for 2 seconds before cloning the examples directory..."
sleep 2

# Clone the examples directory while preserving the original structure
clone_repo "$PARENT_DIR" "$SPARSE_EXAMPLES"
