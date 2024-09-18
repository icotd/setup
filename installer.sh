#!/bin/bash

# Variables
ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/alpine-standard-3.20.3-x86_64.iso"
ISO_PATH="$HOME/Downloads/alpine-standard-3.20.3-x86_64.iso"
ISO_ASC_URL="${ISO_URL}.asc"
KEY_URL="https://alpinelinux.org/keys/ncopa.asc"
TARGET_DEVICE="/dev/sdd"  # Change this to your target device (e.g., /dev/sdd)

# Step 1: Download Alpine ISO and signature
echo "Downloading Alpine Linux ISO..."
curl -o "$ISO_PATH" "$ISO_URL"

echo "Downloading ISO signature..."
curl -o "${ISO_PATH}.asc" "$ISO_ASC_URL"

# Step 2: Import GPG keys for verification
echo "Importing GPG key..."
curl -s "$KEY_URL" | gpg --import

# Step 3: Verify the downloaded ISO against the signature
echo "Verifying the ISO..."
gpg --verify "${ISO_PATH}.asc" "$ISO_PATH"
if [ $? -ne 0 ]; then
  echo "ISO verification failed!"
  exit 1
else
  echo "ISO verified successfully!"
fi

# Step 4: Write the ISO to the USB drive (ensure the correct device is selected)
echo "Writing the ISO to the USB drive..."
sudo dd if="$ISO_PATH" of="$TARGET_DEVICE" bs=4M status=progress && sync

# Step 5: Compare the ISO and USB drive to ensure they are identical
echo "Verifying that the ISO was written correctly..."
cmp "$ISO_PATH" "$TARGET_DEVICE"
if [ $? -ne 0 ]; then
  echo "Comparison failed! The ISO was not written correctly."
  exit 1
else
  echo "ISO written successfully to $TARGET_DEVICE!"
fi

# Optional: Eject the USB drive
echo "Ejecting the USB drive..."
sudo eject "$TARGET_DEVICE"

echo "Alpine Linux ISO has been successfully written to the USB drive."
