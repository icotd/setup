#!/bin/bash
set -euo pipefail

PHOTON_HOME="$HOME/photon"
PHOTON_JAR="$PHOTON_HOME/photon.jar"
PHOTON_LOG="$PHOTON_HOME/photon.log"
PHOTON_SCRIPT="$PHOTON_HOME/photon.sh"

# --- Default values ---
DB_TYPE=""
COUNTRY_CODE=""
PHOTON_PORT=""
LOG_CHOICE=""
STOP_PHOTON=false
UNINSTALL_PHOTON=false

# --- Parse CLI arguments ---
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --db=*) DB_TYPE="${1#*=}";;
    --country=*) COUNTRY_CODE="${1#*=}";;
    --port=*) PHOTON_PORT="${1#*=}";;
    --log=*) LOG_CHOICE="${1#*=}";;
    --stop) STOP_PHOTON=true;;
    --uninstall) UNINSTALL_PHOTON=true;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# --- Validate or prompt for DB_TYPE ---
if [[ -z "$DB_TYPE" ]]; then
  echo "What type of database do you want to use? (global/country)"
  read -r DB_TYPE
  DB_TYPE="$(echo "$DB_TYPE" | tr '[:upper:]' '[:lower:]')"
fi

if [[ "$DB_TYPE" != "global" && "$DB_TYPE" != "country" ]]; then
  echo "❌ Invalid DB type: $DB_TYPE"
  exit 1
fi

# --- Stop ---
if $STOP_PHOTON; then
  echo "Stopping Photon server..."
  pkill -f "photon.jar" && echo "Photon stopped." || echo "Photon is not running."
  exit 0
fi

# --- Uninstall ---
if $UNINSTALL_PHOTON; then
  echo "Stopping Photon server and removing $PHOTON_HOME..."
  pkill -f "photon.jar" || true
  rm -rf "$PHOTON_HOME"
  echo "Photon uninstalled."
  exit 0
fi

# --- Prompt for log ---
if [[ -z "$LOG_CHOICE" ]]; then
  echo "Enable logging? (y/n) [default: n]"
  read -r LOG_CHOICE
fi
LOG_CHOICE="${LOG_CHOICE:-n}"
LOG_CHOICE="$(echo "$LOG_CHOICE" | tr '[:upper:]' '[:lower:]')"

# --- Prompt for port ---
if [[ -z "$PHOTON_PORT" ]]; then
  echo "Port to use? [default: 2322]"
  read -r PHOTON_PORT
fi
PHOTON_PORT="${PHOTON_PORT:-2322}"

# --- Install dependencies ---
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
      ubuntu|debian) sudo apt update && sudo apt install -y default-jdk pbzip2 wget curl xargs ;;
      fedora) sudo dnf install -y java-11-openjdk pbzip2 wget curl findutils ;;
      centos|rhel) sudo yum install -y java-11-openjdk pbzip2 wget curl findutils ;;
      alpine) sudo apk add --no-cache openjdk11 pbzip2 wget curl findutils ;;
      *) echo "Unsupported distro: $DISTRO"; exit 1 ;;
    esac
  else
    echo "Unsupported OS: $OSTYPE"; exit 1
  fi
}
install_dependencies

# --- Download Photon JAR ---
REPO="komoot/photon"
LATEST_RELEASE="$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep 'tag_name' | sed -E 's/.*"v?([^"]+)".*/\1/')"
PHOTON_JAR_URL="https://github.com/$REPO/releases/download/$LATEST_RELEASE/photon-$LATEST_RELEASE.jar"

mkdir -p "$PHOTON_HOME"
cd "$PHOTON_HOME"

if [[ ! -f "$PHOTON_JAR" ]]; then
  echo "Downloading Photon $LATEST_RELEASE..."
  wget -O "$PHOTON_JAR" "$PHOTON_JAR_URL"
else
  echo "Photon jar already exists. Skipping."
fi

# --- Download database ---
ALL_COUNTRIES=(
  "mc" "gi" "bm" "sm" "gg" "je" "li" "mh" "ck" "kn" "ky" "mv" "mt" "gd" "vc" "bb" "sc" "ad" "lc" "fm" "sg" "to" "dm" "bh" "tc" "st" "fo" "km" "mu" "lu" "ws" "cv" "tt" "bn" "ps" "cy" "lb" "xk" "jm" "gm" "qa" "fk" "vu" "me" "bs" "tl" "sz" "kw" "fj" "si" "sv" "il" "bz" "dj" "mk" "rw" "ht" "bi" "gq" "al" "sb" "am" "ls" "be" "md" "gw" "tw" "bt" "ch" "nl" "dk" "ee" "do" "sk" "cr" "ba" "hr" "tg" "lv" "lt" "lk" "ge" "ie" "sl" "pa" "rs" "cz" "at" "az" "jo" "pt" "hu" "kr" "is" "gt" "cu" "bg" "lr" "hn" "bj" "er" "mw" "kp" "ni" "gr" "tj" "np" "bd" "tn" "sr" "uy" "kh" "sy" "kg" "sn" "by" "gy" "la" "ro" "gh" "ug" "gb" "gn" "ga" "nz" "bf" "ec" "ph" "it" "om" "pl" "ci" "my" "vn" "fi" "cg" "de" "jp" "no" "zw" "py" "uz" "iq" "ma" "se" "pg" "tm" "cm" "es" "th" "ye" "bw" "ke" "mg" "ua" "ss" "cf" "so" "fr" "mm" "cl" "zm" "tr" "mz" "na" "pk" "ve" "ng" "tz" "eg" "mr" "bo" "et" "co" "za" "ml" "ao" "ne" "td" "pe" "mn" "ir" "ly" "sd" "id" "mx" "sa" "cd" "dz" "au" "us" "ca"
)


if [[ "$DB_TYPE" == "country" ]]; then
  if [[ -z "$COUNTRY_CODE" ]]; then
    echo "Please specify a country code with --country=XX"
    exit 1
  fi
  COUNTRY_DB="https://download1.graphhopper.com/public/extracts/by-country-code/${COUNTRY_CODE}/photon-db-${COUNTRY_CODE}-latest.tar.bz2"
  echo "Downloading country DB ($COUNTRY_CODE)..."
  wget -O - "$COUNTRY_DB" | pbzip2 -cd | tar x
else
  echo "Downloading all country DBs (global alternative) in parallel..."

  download_country_db() {
    country="$1"
    COUNTRY_DB="https://download1.graphhopper.com/public/extracts/by-country-code/${country}/photon-db-${country}-latest.tar.bz2"
    echo "➡ $country"
    wget -q -O - "$COUNTRY_DB" | pbzip2 -cd | tar x 2>/dev/null && echo "✅ $country done" || echo "⚠️ Failed $country"
  }

  export -f download_country_db

  printf "%s\n" "${ALL_COUNTRIES[@]}" | xargs -n 1 -P 8 -I {} bash -c 'download_country_db "$@"' _ {}
fi

# --- Start server ---
echo "Starting Photon on port $PHOTON_PORT..."

if [[ "$LOG_CHOICE" == "y" ]]; then
  nohup java --enable-native-access=ALL-UNNAMED -Xmx4g -jar "$PHOTON_JAR" \
    -data-dir ./ -listen-port "$PHOTON_PORT" \
    -default-language en -languages en -cors-any > "$PHOTON_LOG" 2>&1 &
  echo "Photon started with log: $PHOTON_LOG"
else
  nohup java --enable-native-access=ALL-UNNAMED -Xmx4g -jar "$PHOTON_JAR" \
    -data-dir ./ -listen-port "$PHOTON_PORT" \
    -default-language en -languages en -cors-any > /dev/null 2>&1 &
  echo "Photon started silently."
fi

# --- start.sh ---
cat << EOF > "$PHOTON_HOME/start.sh"
#!/bin/bash
cd "\$(dirname "\$0")"
nohup java --enable-native-access=ALL-UNNAMED -Xmx4g -jar photon.jar \\
  -data-dir ./ -listen-port $PHOTON_PORT \\
  -default-language en -languages en -cors-any > photon.log 2>&1 &
EOF
chmod +x "$PHOTON_HOME/start.sh"

# --- stop.sh ---
cat << 'EOF' > "$PHOTON_HOME/stop.sh"
#!/bin/bash
echo "Stopping Photon..."
pkill -f "photon.jar" && echo "Photon stopped." || echo "Photon not running."
EOF
chmod +x "$PHOTON_HOME/stop.sh"

# --- uninstall.sh ---
cat << EOF > "$PHOTON_HOME/uninstall.sh"
#!/bin/bash
echo "Uninstalling Photon..."
pkill -f "photon.jar" || true
rm -rf "$PHOTON_HOME"
echo "Photon removed."
EOF
chmod +x "$PHOTON_HOME/uninstall.sh"

# --- Output ---
echo
echo "🌍 Photon is running at: http://localhost:$PHOTON_PORT"
echo "▶ Start again: $PHOTON_HOME/start.sh"
echo "⏹ Stop:        $PHOTON_HOME/stop.sh"
echo "🗑 Uninstall:   $PHOTON_HOME/uninstall.sh"
