#!/bin/bash

# Example Definitions, for Mac Setups
destination="$HOME/android/Android/Sdk/"
sdk_url_base="https://dl.google.com/android/repository/"

# Create necessary directories
mkdir -p "$destination/platforms/android-29"
mkdir -p "$destination/patcher/v4"
mkdir -p "$destination/build-tools/29.0.3"
mkdir -p "$destination/emulator"
mkdir -p "$destination/sources/android-29"
mkdir -p "$destination/platform-tools"

# Manual download links
declare -a sdk_urls=(
    "${sdk_url_base}platform-29_r04.zip"
    "${sdk_url_base}3534162-studio.sdk-patcher.zip"
    "${sdk_url_base}build-tools_r29.0.3-macos.zip" # Updated to macOS version
    "${sdk_url_base}emulator-macos-6306047.zip" # Updated to macOS version
    "${sdk_url_base}sources-29_r01.zip"
    "${sdk_url_base}platform-tools_r29.0.6-macos.zip" # Updated to macOS version
)

# Download and unpack SDK
for url in "${sdk_urls[@]}"; do
    echo "Downloading $url..."
    curl -O "$url"
    zip_file="${url##*/}" # Extract filename from URL
    echo "Unpacking $zip_file..."
    unzip "$zip_file" -d "$destination" # Unpack into the SDK destination
done

# Clean up zip files
rm *.zip

echo "Android SDK setup is complete!"
