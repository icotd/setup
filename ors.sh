#!/usr/bin/env bash
set -euo pipefail

######################## 1. Detect platform ########################
KERNEL=$(uname -s)
ARCH=$(uname -m)              # x86_64, aarch64/arm64, etc.
OS_FAMILY=""                  # debian | redhat | alpine | mac
PKG_MGR=""                    # apt | dnf | yum | apk | brew

if [[ "$KERNEL" == "Darwin" ]]; then
  OS_FAMILY="mac"
  PKG_MGR="brew"
elif [[ "$KERNEL" == "Linux" ]]; then
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    case "$ID" in
      debian|ubuntu|raspbian)                OS_FAMILY="debian"; PKG_MGR="apt" ;;
      centos|rhel|fedora|rocky|almalinux)    OS_FAMILY="redhat"; PKG_MGR="$(command -v dnf || echo yum)" ;;
      alpine)                                OS_FAMILY="alpine"; PKG_MGR="apk" ;;
      *)                                     echo "✖ Unsupported Linux distro: $ID"; exit 1 ;;
    esac
  else
    echo "✖ Cannot detect Linux distribution."; exit 1
  fi
else
  echo "✖ Unsupported operating system: $KERNEL"; exit 1
fi

echo "✔ Detected OS: $OS_FAMILY ($KERNEL), Arch: $ARCH"

######################## 2. Ensure privileges ########################
if [[ "$OS_FAMILY" != "mac" && "$EUID" -ne 0 ]]; then
  echo "✖ Please run this script as root (e.g. with sudo)."; exit 1
fi

######################## 3. Dependency check & install ##############
PKGS_apt="openjdk-17-jdk maven git curl unzip"
PKGS_dnf="java-17-openjdk-devel maven git curl unzip"
PKGS_yum="$PKGS_dnf"
PKGS_apk="openjdk17 maven git curl unzip"
PKGS_brew="openjdk@17 maven git curl unzip"

NEEDED_CMDS=(java mvn git curl unzip)
MISSING_CMDS=()
for c in "${NEEDED_CMDS[@]}"; do
  if ! command -v "$c" &>/dev/null; then MISSING_CMDS+=("$c"); fi
done

if (( ${#MISSING_CMDS[@]} )); then
  echo "➤ Missing commands: ${MISSING_CMDS[*]}"
  case "$PKG_MGR" in
    apt)
      apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y $PKGS_apt
      ;;
    dnf)
      dnf -y install $PKGS_dnf
      ;;
    yum)
      yum -y install $PKGS_yum
      ;;
    apk)
      apk add --no-cache $PKGS_apk
      ;;
    brew)
      if ! command -v brew &>/dev/null; then
        echo "✖ Homebrew not found. Install it from https://brew.sh/"; exit 1
      fi
      for p in $PKGS_brew; do
        if ! brew list --formula | grep -q "^$p\$"; then brew install "$p"; fi
      done
      # brew’s JDK isn’t on PATH by default:
      export PATH="$(brew --prefix)/opt/openjdk@17/bin:$PATH"
      ;;
  esac
else
  echo "✔ All dependencies already present."
fi

######################## 4. Prepare paths ###########################
CURRENT_USER="${SUDO_USER:-$(whoami)}"
HOME_DIR="$(eval echo "~$CURRENT_USER")"
INSTALL_DIR="$HOME_DIR/ors"
mkdir -p "$INSTALL_DIR"/{src,data,graphs}
# chown may fail on mac when not root; ignore errors
chown -R "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR" 2>/dev/null || true

######################## 5. Fetch & build ORS #######################
ORS_VERSION="v9.1.1"
echo "➤ Cloning ORS $ORS_VERSION …"
sudo -u "$CURRENT_USER" git clone --depth 1 --branch "$ORS_VERSION" \
      https://github.com/GIScience/openrouteservice.git "$INSTALL_DIR/src"

echo "➤ Building ORS (Maven) …"
(cd "$INSTALL_DIR/src" && sudo -u "$CURRENT_USER" ./mvnw -B clean package -DskipTests)
cp "$INSTALL_DIR/src/ors-api/target/ors.jar" "$INSTALL_DIR/ors.jar"

######################## 6. Download Ethiopia data ##################
OSM_PBF_URL="https://download.geofabrik.de/africa/ethiopia-latest.osm.pbf"
echo "➤ Downloading Ethiopia extract …"
curl -L "$OSM_PBF_URL" -o "$INSTALL_DIR/data/ethiopia-latest.osm.pbf"
chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/data/ethiopia-latest.osm.pbf" 2>/dev/null || true

######################## 7. Create minimal app-config ###############
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

######################## 8. Register service ########################
JVM_MIN="2G"; JVM_MAX="8G"
JAVA_BIN="$(command -v java)"
SERVICE_MSG=""

if command -v systemctl &>/dev/null; then                  # ─ Linux
  echo "➤ Creating systemd service …"
  cat > /etc/systemd/system/ors.service <<EOF
[Unit]
Description=OpenRouteService backend (Ethiopia, car only)
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$JAVA_BIN -Xms$JVM_MIN -Xmx$JVM_MAX \\
  -Dspring.config.location=$INSTALL_DIR/app-config.yml \\
  -jar $INSTALL_DIR/ors.jar
Restart=on-failure
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now ors
  SERVICE_MSG="systemd service 'ors' started"
elif [[ "$OS_FAMILY" == "mac" ]]; then                     # ─ macOS
  echo "➤ Creating LaunchAgent …"
  LAUNCH_PLIST="$HOME_DIR/Library/LaunchAgents/com.openrouteservice.backend.plist"
  cat > "$LAUNCH_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>               <string>com.openrouteservice.backend</string>
  <key>ProgramArguments</key>    <array>
      <string>$JAVA_BIN</string>
      <string>-Xms$JVM_MIN</string>
      <string>-Xmx$JVM_MAX</string>
      <string>-Dspring.config.location=$INSTALL_DIR/app-config.yml</string>
      <string>-jar</string>
      <string>$INSTALL_DIR/ors.jar</string>
  </array>
  <key>RunAtLoad</key>           <true/>
  <key>WorkingDirectory</key>    <string>$INSTALL_DIR</string>
  <key>StandardOutPath</key>     <string>$INSTALL_DIR/ors.stdout</string>
  <key>StandardErrorPath</key>   <string>$INSTALL_DIR/ors.stderr</string>
</dict>
</plist>
EOF
  launchctl unload "$LAUNCH_PLIST" &>/dev/null || true
  launchctl load   "$LAUNCH_PLIST"
  SERVICE_MSG="LaunchAgent loaded (com.openrouteservice.backend)"
else                                                        # ─ Fallback
  SERVICE_MSG="No init system found – run manually: $JAVA_BIN -jar $INSTALL_DIR/ors.jar"
fi

######################## 9. Finish ##################################
echo
echo "🎉 ORS installed successfully in $INSTALL_DIR"
echo "▶ Listening on http://localhost:8082   (first run builds graphs; be patient)"
echo "🛠  $SERVICE_MSG"
echo "🪵 Logs:"
if command -v journalctl &>/dev/null; then
  echo "    journalctl -fu ors"
else
  echo "    tail -f $INSTALL_DIR/ors.stdout"
fi
