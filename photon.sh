#!/bin/bash

set -euo pipefail

echo "Detecting OS and installing dependencies..."

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
                echo "Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            else
                echo "Homebrew is required to install dependencies. Aborting."
                exit 1
            fi
        fi

        # Install dependencies only if missing
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
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DISTRO="$ID"
        else
            echo "Cannot determine Linux distribution. Aborting."
            exit 1
        fi

        echo "Detected Linux distro: $DISTRO"

        case "$DISTRO" in
            ubuntu|debian)
                sudo apt update
                sudo apt install -y default-jdk pbzip2 wget curl
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
                echo "Unsupported Linux distribution: $DISTRO"
                exit 1
                ;;
        esac
    else
        echo "Unsupported OS: $OSTYPE"
        exit 1
    fi
}

install_dependencies

# Set up installation directory
PHOTON_HOME="$HOME/photon"
mkdir -p "$PHOTON_HOME"
cd "$PHOTON_HOME"

# Prompt for DB type
echo "What type of database do you want to use? (global/country)"
read -r DB_TYPE

COUNTRY_CODE=""
if [[ "$DB_TYPE" == "country" ]]; then
    echo "Provide the 2-letter country code (e.g., et for Ethiopia):"
    read -r COUNTRY_CODE
    COUNTRY_CODE="$(echo "$COUNTRY_CODE" | tr '[:upper:]' '[:lower:]')"
elif [[ "$DB_TYPE" != "global" ]]; then
    echo "Invalid selection. Please enter 'global' or 'country'."
    exit 1
fi

REPO="komoot/photon"
LATEST_RELEASE="$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep 'tag_name' | sed -E 's/.*"v?([^"]+)".*/\1/')"
PHOTON_JAR_DOWNLOAD_URL="https://github.com/$REPO/releases/download/$LATEST_RELEASE/photon-$LATEST_RELEASE.jar"

# Download Photon JAR if not already present
if [[ ! -f "photon.jar" ]]; then
    echo "Downloading photon-$LATEST_RELEASE.jar..."
    wget --tries=3 --retry-connrefused -O photon.jar "$PHOTON_JAR_DOWNLOAD_URL"
else
    echo "photon.jar already exists, skipping download."
fi

# DB download URLs
GLOBAL_DB_URL="https://download1.graphhopper.com/public/photon-db-latest.tar.bz2"
COUNTRY_DB_URL="https://download1.graphhopper.com/public/extracts/by-country-code/${COUNTRY_CODE}/photon-db-${COUNTRY_CODE}-latest.tar.bz2"

# Download DB
if [[ -n "$COUNTRY_CODE" ]]; then
    echo "Downloading Photon DB for country code: $COUNTRY_CODE"
    wget --tries=3 --retry-connrefused -O - "$COUNTRY_DB_URL" | pbzip2 -cd | tar x
else
    echo "Downloading global Photon DB..."
    wget --tries=3 --retry-connrefused -O - "$GLOBAL_DB_URL" | pbzip2 -cd | tar x
fi

# Logging choice
echo "Do you want to enable logging? (y/n) [default: n]"
read -r LOG_CHOICE
LOG_CHOICE="${LOG_CHOICE:-n}"

# Port prompt
echo "What port do you want to use for the Photon server? [default: 2322]"
read -r PHOTON_PORT
PHOTON_PORT="${PHOTON_PORT:-2322}"

echo "Starting Photon server on port $PHOTON_PORT..."

if [[ "$LOG_CHOICE" =~ ^[Yy]$ ]]; then
    java -Xmx4g -jar photon.jar \
      -data-dir ./ \
      -listen-port "$PHOTON_PORT" \
      -default-language en \
      -languages en \
      -cors-any > photon.log 2>&1 &
    echo "Photon server is running in the background with logging enabled."
    echo "Logs: $PHOTON_HOME/photon.log"
else
    java -Xmx4g -jar photon.jar \
      -data-dir ./ \
      -listen-port "$PHOTON_PORT" \
      -default-language en \
      -languages en \
      -cors-any
fi

# Create restart helper script
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

echo "Photon is now running at: http://localhost:$PHOTON_PORT"
echo "To restart later, run: $PHOTON_HOME/start.sh"
