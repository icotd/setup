#!/bin/bash

# Set the SDK installation path
destination="$HOME/android"

# Check if sdkmanager is available
if ! command -v sdkmanager &> /dev/null; then
    echo "sdkmanager could not be found. Please install the Android SDK."
    exit 1
fi

# Create necessary directories if they don't exist
mkdir -p "$destination"

# Update SDK Manager and install the latest tools and platforms
echo "Updating SDK Manager..."
sdkmanager --sdk_root="$destination/" --update

# Install the latest platform tools, build tools, emulator, and system images
echo "Installing latest platform tools..."
sdkmanager --sdk_root="$destination/" "platform-tools"

echo "Installing latest build tools..."
sdkmanager --sdk_root="$destination/" "build-tools;latest"

echo "Installing latest emulator..."
sdkmanager --sdk_root="$destination/" "emulator"

# Install the latest SDK platform and sources
echo "Installing latest SDK Platform..."
sdkmanager --sdk_root="$destination/" "platforms;android-34"  # Change "34" to the latest API level if necessary

echo "Installing latest sources..."
sdkmanager --sdk_root="$destination/" "sources;android-34"  # Change "34" to the latest API level if necessary

# Update .zshrc for PATH if necessary
if ! grep -q "$destination/cmdline-tools/latest/bin" ~/.zshrc; then
    echo "export PATH=\$HOME/$destination/cmdline-tools/latest/bin:\$PATH" >> ~/.zshrc
fi

if ! grep -q "$destination/tools/bin" ~/.zshrc; then
    echo "export PATH=\$HOME/$destination/tools/bin:\$PATH" >> ~/.zshrc
fi

if ! grep -q "$destination/platform-tools" ~/.zshrc; then
    echo "export PATH=\$HOME/$destination/platform-tools:\$PATH" >> ~/.zshrc
fi

# Uncomment if you want to install the latest system images for Google APIs
# echo "Installing latest system images for Google APIs..."
# sdkmanager --sdk_root="$destination/" "system-images;android-34;google_apis;x86"  # Change "34" to the latest API level if necessary

# Uncomment if you want to install the latest SDK patcher
# echo "Installing latest SDK patcher..."
# sdkmanager --sdk_root="$destination/" "patcher;v4"

echo "Sourcing ~/.zshrc to apply changes..."
source ~/.zshrc  # Apply changes to PATH

echo "Android SDK setup is complete!"
