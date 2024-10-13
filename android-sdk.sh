#!/bin/bash

# Example Definitions, for Mac Setups
destination="$HOME/android/"
toolsDownloadUrl=$(curl https://developer.android.com/studio | grep -o "https:\/\/dl.google.com\/android\/repository\/commandlinetools\-mac\-[0-9]*_latest\.zip")

# Download and extract the contents
curl --location -o android.zip $toolsDownloadUrl
unzip -q android.zip -d ./android-temp

mkdir -p "$destination/cmdline-tools/latest"
mv ./android-temp/tools/* "$destination/cmdline-tools/latest"
rm -rf ./android-temp
# rm android.zip
