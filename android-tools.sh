#!/bin/bash

# Example Definitions, for Mac Setups
destination="$HOME/android/"
commandlinetoolsDownloadUrl=$(curl https://developer.android.com/studio | grep -o "https:\/\/dl.google.com\/android\/repository\/commandlinetools\-mac\-[0-9]*_latest\.zip")

toolsDownloadUrl=$(curl https://developer.android.com/studio | grep -o "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip")
 # toolsDownloadUrl=$(curl https://developer.android.com/studio | grep -o "https://dl.google.com/android/repository/platforms-latest-darwin.zip")

Download lastest Android platform tools

Mac https://dl.google.com/android/repository/platform-tools-latest-darwin.zip
Linux https://dl.google.com/android/repository/platform-tools-latest-linux.zip
Windows https://dl.google.com/android/repository/platform-tools-latest-windows.zip

# Download and extract the contents
curl --location -o android.zip $commandlinetoolsDownloadUrl
unzip -q android.zip -d ./android-temp

mkdir -p "$destination/cmdline-tools/latest"
mv ./android-temp/cmdline-tools/* "$destination/cmdline-tools/latest"
rm -rf ./android-temp
# rm android.zip
