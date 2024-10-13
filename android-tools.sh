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

https://dl.google.com/android/repository/platform- .zip

# Download and extract the contents
curl --location -o android.zip $commandlinetoolsDownloadUrl
unzip -q android.zip -d ./android-temp

mkdir -p "$destination/cmdline-tools/latest"
mv ./android-temp/cmdline-tools/* "$destination/cmdline-tools/latest"
rm -rf ./android-temp
# rm android.zip

#!/bin/bash

# Example Definitions, for Mac Setups
destination="$HOME/android/"
OS=

manual download sdk:

https://dl.google.com/android/repository/platform-29_r04.zip
https://dl.google.com/android/repository/3534162-studio.sdk-patcher.zip
https://dl.google.com/android/repository/build-tools_r29.0.3-windows.zip
https://dl.google.com/android/repository/emulator-windows-6306047.zip
https://dl.google.com/android/repository/sources-29_r01.zip
https://dl.google.com/android/repository/platform-tools_r29.0.6-windows.zip

Unpack to
destination/Android\Sdk\platforms\android-2
destination/Android\Sdk\patcher\v4
destination/Android\Sdk\build-tools\29.0.3
destination/Android\Sdk\emulator
destination/Android\Sdk\sources\android-29
destination/Android\Sdk\platform-tools
