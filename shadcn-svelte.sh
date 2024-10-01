#!/bin/bash

# Create "shadcn-svelte" directory if it doesn't exist
PARENT_DIR="shadcn-svelte"
if [ ! -d "$PARENT_DIR" ]; then
    mkdir -p "$PARENT_DIR"
    echo "Created directory: $PARENT_DIR"
else
    echo "Directory already exists: $PARENT_DIR"
fi

# Directories where you want to clone the specific folders
EXAMPLES_DIR="$PARENT_DIR/examples"
LIB_DIR="$PARENT_DIR/lib/ui"

# GitHub repository URL
REPO_URL="https://github.com/icotd/shadcn-svelte.git"

# Branch you want to pull from
BRANCH="next"

# Base directories for sparse checkout
SPARSE_LIB_DIR="sites/docs/src/lib/registry/new-york/ui"
SPARSE_EXAMPLES_DIR="sites/docs/src/routes/(app)/examples"

# Prompt user for the component directory
read -p "Enter the component directory (e.g., authentication/(components)): " COMPONENT_DIR

# Check if the component directory is not empty
if [ -z "$COMPONENT_DIR" ]; then
    echo "Component directory cannot be empty. Exiting..."
    exit 1
fi

# Combine the examples directory with the user-provided component directory
SPARSE_EXAMPLES="$SPARSE_EXAMPLES_DIR/$COMPONENT_DIR"

# Create and navigate to the target directories
mkdir -p "$EXAMPLES_DIR" "$LIB_DIR"

# Function to clone a directory
clone_repo() {
    local TARGET_DIR=$1
    local SPARSE_DIR=$2

    # Navigate to the target directory
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

    echo "Successfully cloned the directory: $SPARSE_DIR into $TARGET_DIR"
}

# Clone the examples directory
clone_repo "$EXAMPLES_DIR" "$SPARSE_EXAMPLES"

# Clone the lib/ui directory
clone_repo "$LIB_DIR" "$SPARSE_LIB_DIR"
