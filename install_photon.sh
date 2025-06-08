#!/bin/bash
set -euo pipefail

PHOTON_HOME="$HOME/photon"
PHOTON_SCRIPT="$PHOTON_HOME/photon.sh"

# Create the directory if it doesn't exist
echo "Creating directory $PHOTON_HOME"
mkdir -p "$PHOTON_HOME"

# Download the setup script
echo "Downloading setup script"
wget -O "$PHOTON_SCRIPT" https://raw.githubusercontent.com/icotd/setup/main/photon.sh

# Make the script executable
echo "Making the script executable"
chmod +x "$PHOTON_SCRIPT"

# Change to the photon directory
echo "Changing to the photon directory"
cd "$PHOTON_HOME" || { echo "Failed to cd into $PHOTON_HOME"; exit 1; }

# Run the script from inside the directory
echo "Running the script"
./photon.sh

echo "Script completed"
