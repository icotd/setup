#!/bin/bash

set -euo pipefail

echo "Detecting OS and installing dependencies..."

# Default values
DB_TYPE=""
COUNTRY_CODE=""
PHOTON_PORT=""
LOG_CHOICE=""

# Parse CLI arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --db=*) DB_TYPE="${1#*=}";;
    --country=*) COUNTRY_CODE="${1#*=}";;
    --port=*) PHOTON_PORT="${1#*=}";;
    --log=*) LOG_CHOICE="${1#*=}";;
  esac
  shift
done

install_dependencies() {
  command_exists() {
    command -v "$1" >/dev/null 2>&1
  }

  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Detected macOS"
    if ! command_exists brew; then
      echo "Homebrew not found. Do you want to install it? (y/n)"
      read -r answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      else
        echo "Homebrew is required. Aborting."
        exit 1
      fi
    fi
    for pkg in openjdk pbzip2 wget; do
      if ! brew list --versions "$pkg" >/dev/null; then
        echo "Installing $pkg..."
        brew install "$pkg"
      else
        echo "$pkg already installed."
      fi
    done
    export PATH="$(brew --prefix)/opt/openjdk/bin:$PATH"

  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [[ -f /etc/os-release ]]; then . /etc/os-release; DISTRO="$ID"; else
      echo "Cannot determine Linux distribution."; exit 1
    fi
    echo "Detected Linux distro: $DISTRO"
    case "$DISTRO" in
      ubuntu|debian)
        sudo apt update && sudo apt install -y default-jdk pbzip2 wget curl
        ;;
      fedora)
        sudo dnf install -y java-11-openjdk pbzip2 wget curl
        ;;
      centos|rhel)
        sudo yum install -y java-11-openjdk pbzip2 wget curl
        ;;
      alpine)
        sudo apk add --no-cache openjdk11 pbzip2 wget curl
        ;;
      *)
        echo "Unsupported Linux distribution: $DISTRO"; exit 1
        ;;
    esac
  else
    echo "Unsupported OS: $OSTYPE"; exit 1
  fi
}

install_dependencies

PHOTON_HOME="$HOME/photon"
mkdir -p "$PHOTON_HOME"
cd "$PHOTON_HOME"

# Prompt for DB type if not passed
if [[ -z "$DB_TYPE" ]]; then
  echo "What type of database do you want to use? (global/country)"
  read -r DB_TYPE
fi

DB_TYPE="$(echo "$DB_TYPE" | tr '[:upper:]' '[:lower:]')"

# Prompt for country code if needed
if [[ "$DB_TYPE" == "country" && -z "$COUNTRY_CODE" ]]; then
  echo "Provide the 2-letter country code (e.g., et):"
  read -r COUNTRY_CODE
fi

if [[ "$DB_TYPE" != "global" && "$DB_TYPE" != "country" ]]; then
  echo "Invalid selection. Use 'global' or 'country'."
  exit 1
fi

REPO="komoot/photon"
LATEST_RELEASE="$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep 'tag_name' | sed -E 's/.*"v?([^"]+)".*/\1/')"
PHOTON_JAR_DOWNLOAD_URL="https://github.com/$REPO/releases/download/$LATEST_RELEASE/photon-$LATEST_RELEASE.jar"

# Download Photon jar if needed
if [[ ! -f "photon.jar" ]]; then
  echo "Downloading photon-$LATEST_RELEASE.jar..."
  wget --tries=3 --retry-connrefused -O photon.jar "$PHOTON_JAR_DOWNLOAD_URL"
else
  echo "photon.jar already exists. Skipping download."
fi

# DB URLs
GLOBAL_DB_URL="https://download1.graphhopper.com/public/photon-db-latest.tar.bz2"
COUNTRY_DB_URL="https://download1.graphhopper.com/public/extracts/by-country-code/${COUNTRY_CODE}/photon-db-${COUNTRY_CODE}-latest.tar.bz2"

# Download DB
if [[ "$DB_TYPE" == "country" ]]; then
  echo "Downloading Photon DB for country code: $COUNTRY_CODE"
  wget --tries=3 --retry-connrefused -O - "$COUNTRY_DB_URL" | pbzip2 -cd | tar x
else
  echo "Downloading global Photon DB..."
  wget --tries=3 --retry-connrefused -O - "$GLOBAL_DB_URL" | pbzip2 -cd | tar x
fi

# Prompt for logging if not set
if [[ -z "$LOG_CHOICE" ]]; then
  echo "Do you want to enable logging? (y/n) [default: n]"
  read -r LOG_CHOICE
fi
LOG_CHOICE="${LOG_CHOICE:-n}"

# Prompt for port if not set
if [[ -z "$PHOTON_PORT" ]]; then
  echo "What port do you want to use? [default: 2322]"
  read -r PHOTON_PORT
fi
PHOTON_PORT="${PHOTON_PORT:-2322}"

echo "Starting Photon server on port $PHOTON_PORT..."

if [[ "$LOG_CHOICE" =~ ^[Yy]$ ]]; then
  java -Xmx4g -jar photon.jar \
    -data-dir ./ \
    -listen-port "$PHOTON_PORT" \
    -default-language en \
    -languages en \
    -cors-any > photon.log 2>&1 &
  echo "Photon server is running in background. Logs at $PHOTON_HOME/photon.log"
else
  java -Xmx4g -jar photon.jar \
    -data-dir ./ \
    -listen-port "$PHOTON_PORT" \
    -default-language en \
    -languages en \
    -cors-any
fi

# Create restart script
cat << EOF > "$PHOTON_HOME/start.sh"
#!/bin/bash
cd "\$(dirname "\$0")"
java -Xmx4g -jar photon.jar \\
  -data-dir ./ \\
  -listen-port $PHOTON_PORT \\
  -default-language en \\
  -languages en \\
  -cors-any
EOF

chmod +x "$PHOTON_HOME/start.sh"

echo "Photon is running at: http://localhost:$PHOTON_PORT"
echo "To restart later, run: $PHOTON_HOME/start.sh"

# Delete the script if it's setup_photon.sh
SCRIPT_NAME="$(basename "$0")"
if [[ "$SCRIPT_NAME" == "setup_photon.sh" ]]; then
  echo "Cleaning up setup script..."
  rm -- "$0"
fi
