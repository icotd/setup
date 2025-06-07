#!/bin/bash

set -euo pipefail

PHOTON_HOME="$HOME/photon"
PHOTON_JAR="$PHOTON_HOME/photon.jar"
PHOTON_LOG="$PHOTON_HOME/photon.log"

# Default values
DB_TYPE=""
COUNTRY_CODE=""
PHOTON_PORT=""
LOG_CHOICE=""
STOP_PHOTON=false
UNINSTALL_PHOTON=false

# Parse CLI arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --db=*) DB_TYPE="${1#*=}";;
    --country=*) COUNTRY_CODE="${1#*=}";;
    --port=*) PHOTON_PORT="${1#*=}";;
    --log=*) LOG_CHOICE="${1#*=}";;
    --stop) STOP_PHOTON=true;;
    --uninstall) UNINSTALL_PHOTON=true;;
  esac
  shift
done

# --- STOP logic ---
if $STOP_PHOTON; then
  echo "Stopping Photon server..."
  pkill -f "photon.jar" && echo "Photon stopped." || echo "Photon is not running."
  exit 0
fi

# --- UNINSTALL logic ---
if $UNINSTALL_PHOTON; then
  echo "Stopping Photon server and removing $PHOTON_HOME..."
  pkill -f "photon.jar" || true
  rm -rf "$PHOTON_HOME"
  echo "Photon uninstalled."
  exit 0
fi

# --- INSTALL/START logic ---
echo "Detecting OS and installing dependencies..."

install_dependencies() {
  command_exists() { command -v "$1" &>/dev/null; }

  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Detected macOS"
    if ! command_exists brew; then
      echo "Homebrew not found. Install it? (y/n)"
      read -r answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      else
        echo "Homebrew required. Aborting."
        exit 1
      fi
    fi
    for pkg in openjdk pbzip2 wget; do
      brew list --versions "$pkg" >/dev/null || brew install "$pkg"
    done
    export PATH="$(brew --prefix)/opt/openjdk/bin:$PATH"

  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [[ -f /etc/os-release ]]; then . /etc/os-release; DISTRO="$ID"; else
      echo "Cannot detect Linux distro"; exit 1
    fi
    echo "Detected Linux: $DISTRO"
    case "$DISTRO" in
      ubuntu|debian) sudo apt update && sudo apt install -y default-jdk pbzip2 wget curl ;;
      fedora) sudo dnf install -y java-11-openjdk pbzip2 wget curl ;;
      centos|rhel) sudo yum install -y java-11-openjdk pbzip2 wget curl ;;
      alpine) sudo apk add --no-cache openjdk11 pbzip2 wget curl ;;
      *) echo "Unsupported distro: $DISTRO"; exit 1 ;;
    esac
  else
    echo "Unsupported OS: $OSTYPE"; exit 1
  fi
}

install_dependencies

mkdir -p "$PHOTON_HOME"
cd "$PHOTON_HOME"

# Prompt for DB type if not passed
if [[ -z "$DB_TYPE" ]]; then
  echo "What type of database? (global/country)"
  read -r DB_TYPE
fi
DB_TYPE="$(echo "$DB_TYPE" | tr '[:upper:]' '[:lower:]')"

# Prompt for country code if needed
if [[ "$DB_TYPE" == "country" && -z "$COUNTRY_CODE" ]]; then
  echo "Enter 2-letter country code (e.g. et):"
  read -r COUNTRY_CODE
fi

if [[ "$DB_TYPE" != "global" && "$DB_TYPE" != "country" ]]; then
  echo "Invalid DB type: $DB_TYPE"
  exit 1
fi

# Prompt for logging if not passed
if [[ -z "$LOG_CHOICE" ]]; then
  echo "Enable logging? (y/n) [default: n]"
  read -r LOG_CHOICE
fi
LOG_CHOICE="$(echo "${LOG_CHOICE:-n}" | tr '[:upper:]' '[:lower:]')"

# Prompt for port if not passed
if [[ -z "$PHOTON_PORT" ]]; then
  echo "Port to use? [default: 2322]"
  read -r PHOTON_PORT
fi
PHOTON_PORT="${PHOTON_PORT:-2322}"

# Get Photon release
REPO="komoot/photon"
LATEST_RELEASE="$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep 'tag_name' | sed -E 's/.*"v?([^"]+)".*/\1/')"
PHOTON_JAR_URL="https://github.com/$REPO/releases/download/$LATEST_RELEASE/photon-$LATEST_RELEASE.jar"

if [[ ! -f "$PHOTON_JAR" ]]; then
  echo "Downloading Photon $LATEST_RELEASE..."
  wget -O "$PHOTON_JAR" "$PHOTON_JAR_URL"
else
  echo "Photon jar exists. Skipping download."
fi

# Download DB
GLOBAL_DB="https://download1.graphhopper.com/public/photon-db-latest.tar.bz2"
COUNTRY_DB="https://download1.graphhopper.com/public/extracts/by-country-code/${COUNTRY_CODE}/photon-db-${COUNTRY_CODE}-latest.tar.bz2"

if [[ "$DB_TYPE" == "country" ]]; then
  echo "Downloading country DB ($COUNTRY_CODE)..."
  wget -O - "$COUNTRY_DB" | pbzip2 -cd | tar x
else
  echo "Downloading global DB..."
  wget -O - "$GLOBAL_DB" | pbzip2 -cd | tar x
fi

# Start Photon
echo "Starting Photon on port $PHOTON_PORT..."

if [[ "$LOG_CHOICE" == "y" ]]; then
  nohup java --enable-native-access=ALL-UNNAMED -Xmx4g -jar "$PHOTON_JAR" \
    -data-dir ./ \
    -listen-port "$PHOTON_PORT" \
    -default-language en \
    -languages en \
    -cors-any > "$PHOTON_LOG" 2>&1 &
  echo "Photon started. Log: $PHOTON_LOG"
else
  nohup java --enable-native-access=ALL-UNNAMED -Xmx4g -jar "$PHOTON_JAR" \
    -data-dir ./ \
    -listen-port "$PHOTON_PORT" \
    -default-language en \
    -languages en \
    -cors-any > /dev/null 2>&1 &
  echo "Photon started silently."
fi

# start.sh
cat << EOF > "$PHOTON_HOME/start.sh"
#!/bin/bash
cd "\$(dirname "\$0")"
nohup java --enable-native-access=ALL-UNNAMED -Xmx4g -jar photon.jar \\
  -data-dir ./ \\
  -listen-port $PHOTON_PORT \\
  -default-language en \\
  -languages en \\
  -cors-any > photon.log 2>&1 &
EOF
chmod +x "$PHOTON_HOME/start.sh"

# stop.sh
cat << 'EOF' > "$PHOTON_HOME/stop.sh"
#!/bin/bash
echo "Stopping Photon..."
pkill -f "photon.jar" && echo "Photon stopped." || echo "Photon not running."
EOF
chmod +x "$PHOTON_HOME/stop.sh"

# uninstall.sh
cat << EOF > "$PHOTON_HOME/uninstall.sh"
#!/bin/bash
echo "Uninstalling Photon..."
pkill -f "photon.jar" || true
rm -rf "$PHOTON_HOME"
echo "Photon removed."
EOF
chmod +x "$PHOTON_HOME/uninstall.sh"

echo
echo "Photon running at: http://localhost:$PHOTON_PORT"
echo "Start again: $PHOTON_HOME/start.sh"
echo "Stop server: $PHOTON_HOME/stop.sh"
echo "Uninstall:   $PHOTON_HOME/uninstall.sh"

# Self-delete if this script is ~/photon/install.sh
if [[ "$(basename "$0")" == "install.sh" ]]; then
  echo "Cleaning up install script..."
  rm -- "$0"
fi
