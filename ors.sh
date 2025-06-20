#!/usr/bin/env bash
set -euo pipefail

# ───────────────────────── helper ───────────────────────────
# run_as_target "<command>"
run_as_target() {
  if [[ "$(id -u)" -eq 0 && "$CURRENT_USER" != "root" ]]; then
    sudo -u "$CURRENT_USER" bash -c "$1"
  else
    bash -c "$1"
  fi
}

# ───────────────────────── 1. dependencies ─────────────────
install_dependencies() {
  command_exists() { command -v "$1" &>/dev/null; }

  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Detected macOS"
    if ! command_exists brew; then
      echo "Homebrew not found. Install it? (y/n)"
      read -r answer
      [[ "$answer" =~ ^[Yy]$ ]] || { echo "Homebrew required. Aborting."; exit 1; }
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
      eval "$(/usr/local/bin/brew shellenv)"    2>/dev/null || true
    fi
    for pkg in openjdk@17 maven git curl wget pbzip2 unzip; do
      brew list --versions "$pkg" &>/dev/null || brew install "$pkg"
    done
    export PATH="$(brew --prefix)/opt/openjdk@17/bin:$PATH"
    export JAVA_HOME=$(/usr/libexec/java_home -v 17)
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [[ -f /etc/os-release ]]; then . /etc/os-release; DISTRO="$ID"; else
      echo "Cannot detect Linux distro"; exit 1
    fi
    echo "Detected Linux: $DISTRO"
    case "$DISTRO" in
      ubuntu|debian|raspbian) apt-get update -qq && DEBIAN_FRONTEND=noninteractive \
        apt-get install -y openjdk-17-jdk maven git curl wget pbzip2 unzip ;;
      fedora)                dnf  -y install java-17-openjdk-devel maven git curl wget pbzip2 unzip ;;
      centos|rhel|rocky|almalinux)
                              yum -y install java-17-openjdk-devel maven git curl wget pbzip2 unzip ;;
      alpine)                apk  add --no-cache openjdk17 maven git curl wget pbzip2 unzip ;;
      *) echo "Unsupported distro: $DISTRO"; exit 1 ;;
    esac
  else
    echo "Unsupported OS: $OSTYPE"; exit 1
  fi
}
install_dependencies

# ───────────────────────── 2. paths ────────────────────────
CURRENT_USER="${SUDO_USER:-$(whoami)}"
HOME_DIR="$(eval echo "~$CURRENT_USER")"
INSTALL_DIR="$HOME_DIR/ors"
mkdir -p "$INSTALL_DIR"/{src,data,graphs}
chown -R "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR" 2>/dev/null || true

# ───────────────────────── 3. clone & build ────────────────
ORS_VERSION="v9.1.1"
echo "➤ Cloning ORS $ORS_VERSION …"
run_as_target "git clone --depth 1 --branch $ORS_VERSION https://github.com/GIScience/openrouteservice.git $INSTALL_DIR/src"

echo "➤ Building ORS (Maven) …"
run_as_target "chmod +x $INSTALL_DIR/src/mvnw"
run_as_target "cd $INSTALL_DIR/src && ./mvnw -B clean package -DskipTests"
cp "$INSTALL_DIR/src/ors-api/target/ors.jar" "$INSTALL_DIR/ors.jar"

# ───────────────────────── 4. Ethiopia extract ─────────────
curl -L "https://download.geofabrik.de/africa/ethiopia-latest.osm.pbf" \
     -o "$INSTALL_DIR/data/ethiopia-latest.osm.pbf"
chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/data/ethiopia-latest.osm.pbf" 2>/dev/null || true

# ───────────────────────── 5. config ───────────────────────
cat > "$INSTALL_DIR/app-config.yml" <<EOF
ors:
  engine:
    profiles:
      - profile: car
        params:
          maximum_speed: 130
  data_sources:
    default:
      source: pbf
      location: "$INSTALL_DIR/data/ethiopia-latest.osm.pbf"
  graphs:
    default:
      location: "$INSTALL_DIR/graphs"
server:
  port: 8082
logging:
  level:
    ROOT: INFO
EOF
chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/app-config.yml" 2>/dev/null || true

# ───────────────────────── 6. service ──────────────────────
JAVA_BIN="$(command -v java)"
JVM_MIN="2G"; JVM_MAX="8G"
SERVICE_MSG=""

if command -v systemctl &>/dev/null; then                            # Linux
  cat > /etc/systemd/system/ors.service <<EOF
[Unit]
Description=OpenRouteService (Ethiopia, car only)
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$JAVA_BIN -Xms$JVM_MIN -Xmx$JVM_MAX \
  -Dspring.config.location=$INSTALL_DIR/app-config.yml \
  -jar $INSTALL_DIR/ors.jar
Restart=on-failure
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now ors
  SERVICE_MSG="systemd service 'ors' started"
elif [[ "$OSTYPE" == "darwin"* ]]; then                             # macOS
  PLIST="$HOME_DIR/Library/LaunchAgents/com.openrouteservice.backend.plist"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>            <string>com.openrouteservice.backend</string>
  <key>ProgramArguments</key> <array>
    <string>$JAVA_BIN</string>
    <string>-Xms$JVM_MIN</string>
    <string>-Xmx$JVM_MAX</string>
    <string>-Dspring.config.location=$INSTALL_DIR/app-config.yml</string>
    <string>-jar</string>
    <string>$INSTALL_DIR/ors.jar</string>
  </array>
  <key>WorkingDirectory</key> <string>$INSTALL_DIR</string>
  <key>RunAtLoad</key>        <true/>
  <key>StandardOutPath</key>  <string>$INSTALL_DIR/ors.stdout</string>
  <key>StandardErrorPath</key><string>$INSTALL_DIR/ors.stderr</string>
</dict>
</plist>
EOF
  launchctl unload "$PLIST" &>/dev/null || true
  launchctl load  "$PLIST"
  SERVICE_MSG="LaunchAgent loaded (com.openrouteservice.backend)"
else
  SERVICE_MSG="No init system – run manually: $JAVA_BIN -jar $INSTALL_DIR/ors.jar"
fi

# ───────────────────────── 7. done ─────────────────────────
echo
echo "🎉 ORS installed in $INSTALL_DIR"
echo "▶ Listening at http://localhost:8082  (first start builds graphs)"
echo "🛠  $SERVICE_MSG"
echo "🪵 Logs:"
if command -v journalctl &>/dev/null; then
  echo "    journalctl -fu ors"
else
  echo "    tail -f $INSTALL_DIR/ors.stdout"
fi
