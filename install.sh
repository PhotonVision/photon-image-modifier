#!/bin/bash

# Exit on errors
set -e +u

needs_arg() {
    if [ -z "$OPTARG" ]; then
      die "Argument is required for the '-$RAWOPT' option" \
          "See './install.sh -h' for more information."
    fi;
}

die() {
  for arg in "$@"; do
    echo "[FAILURE] $arg" 1>&2
  done
  exit 1
}

debug() {
  if [[ -z "$QUIET" || -n "$TEST" ]] ; then
    for arg in "$@"; do
      printf "%b\n" "$QUIET$TEST$arg"
    done
  fi
}

package_is_installed(){
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

install_required() {
  debug "Installing $* ... "
  apt-get $APT_OPT --yes install "$@"
  debug "Installation complete."
}

get_versions() {
  PHOTON_VISION_RELEASES="$(wget -q -O - https://api.github.com/repos/photonvision/photonvision/releases?per_page=$1)"

  PHOTON_VISION_VERSIONS=$(echo "$PHOTON_VISION_RELEASES" | \
    sed -En 's/\"tag_name\": \"(.+)\",/\1/p' | \
    sed 's/^[[:space:]]*//'
  )
  echo "$PHOTON_VISION_VERSIONS"
}

is_chroot() {
  if systemd-detect-virt -r; then
    return 0
  else
    return 1
  fi
}

help() {
  cat << HELPEOF
This script installs Photonvision.
It must be run as root.

Syntax: sudo ./install.sh [options]
  options:
  -h, --help
      Display this help message.
  -l [count], --list-versions=[count]
      Lists the most recent versions of PhotonVision.
      Count: Number of recent versions to show, max value is 100.
      Default: 30
  -v <version>, --version=<version>
      Specifies which version of PhotonVision to install.
      If not specified, the latest stable release is installed.
  -a <arch>, --arch=<arch>
      Install PhotonVision for the specified architecture.
      Supported values: aarch64, x86_64
  -c [option], --control-networking=[option]
      Configures PhotonVision to control networking and will install
      NetworkManager if needed. This will only work on Debian-based Linux systems.
      Options: "yes", "no".
      Default: "yes" (unless -q or --quiet is specified, then "no").
  -q, --quiet
      Silent install, automatically accepts all defaults. For
      non-interactive use. Makes -c, --control-networking default to "no".
  -t, --test
      Run in test mode. All actions that make chnages to the system
      are suppressed.
HELPEOF
}

debug "Running the installation script for PhotonVision."

# Exit with message if attempting to run on SystemCore
if grep -iq "systemcore" /etc/os-release; then
  die "This install script does not work on Systemcore."
fi

CONTROL_NETWORKING="ask"
PV_VERSION="latest"

# use GITHUB TOKEN when available to authenticate
AUTH_TOKEN=""
if [[ -n $GH_TOKEN ]]; then
  AUTH_TOKEN="Authorization: Bearer $GH_TOKEN"
fi

while getopts "hlva:cqt-:" OPT; do
  RAWOPT="$OPT"
  if [ "$OPT" = "-" ]; then
    RAWOPT="-$OPTARG"
    OPT="${OPTARG%%=*}"       # extract long option name
    OPTARG="${OPTARG#"$OPT"}" # extract long option argument (may be empty)
    OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
  else
    nextopt=${!OPTIND}        # check for an optional argument followinng a short option
    if [[ -n $nextopt && $nextopt != -* ]]; then
      OPTIND=$((OPTIND + 1))
      OPTARG=$nextopt
      RAWOPT="$OPT $OPTARG"
    fi
  fi

  case "$OPT" in
    h | help)
      help
      exit 0
      ;;
    l | list-versions)
      COUNT=${OPTARG:-30}
      get_versions "$COUNT"
      exit 0
      ;;
    v | version)
      # needs_arg
      PV_VERSION=${OPTARG:-latest}
      ;;
    a | arch) needs_arg;
      ARCH=$OPTARG
      ;;
    c | control-networking)
      if [[ "$CONTROL_NETWORKING" == "ask" ]] ; then
        CONTROL_NETWORKING="$(echo "${OPTARG:-yes}" | tr '[:upper:]' '[:lower:]')"
        case "$CONTROL_NETWORKING" in
          yes)
            debug "PhotonVisison will be configured to control networking and will install NetworkManager, if needed."
            ;;
          no)
            debug "PhotonVision will not control networking. Be sure to configure it correctly."
            ;;
          * )
            die "Valid options for -c, --control-networking are: 'yes', 'no'"
            ;;
        esac
      else
        die "--control-networking=$CONTROL_NETWORKING was already set. The option '-$RAWOPT' is redundant."
      fi
    ;;
    q | quiet)
      QUIET="QUIET-"
      ;;
    t | test)
      TEST="TEST>"
      ;;
    \?)  # Handle invalid short options
      die "Error: Invalid option -$OPTARG" \
          "See './install.sh -h' for more information."
      ;;
    * )  # Handle invalid long options
      die "Error: Invalid option --$OPT" \
          "See './install.sh -h' for more information."
      ;;
  esac
done

# if quiet and control_networking wasn't set, then assume "no"
if [[ -n $QUIET && "$CONTROL_NETWORKING" == "ask" ]]; then
  CONTROL_NETWORKING="no"
fi

APT_OPT=""

if [[ -n $TEST ]]; then
  debug "This script is running in test mode, no changes will be made to the system"
  APT_OPT="--dry-run"
fi

if [[ -n $QUIET ]]; then
  APT_OPT="$APT_OPT --quiet"
fi

if [[ "$(id -u)" != "0" && -z $TEST ]]; then
   die "This script must be run as root"
fi

# Print an error message if apt isn't available
command -v apt &> /dev/null || die "The 'apt' package manager is required for this installer, but was not founed on this system!"

# Determine the system platform
if [[ -z "$ARCH" ]]; then
  if is_chroot ; then
    die "Running in chroot. Arch must be specified!"
  fi
  debug "Arch was not specified. Inferring..."
  ARCH=$(uname -m)
  debug "Arch was inferred to be $ARCH"
fi

case "$ARCH" in
  aarch64)
    ARCH_NAME="linuxarm64"
    ;;
  x86_64)
    ARCH_NAME="linuxx64|linuxx86-64"
    ;;
  armv71)
    die "ARM32 is not supported by PhotonVision. Exiting."
    ;;
  *)
    die "Unsupported or unknown architecture: '$ARCH'." \
    "Please specify your architecture using: ./install.sh -a <arch> " \
    "Run './install.sh -h' for more information."
    ;;
esac

debug "Installing for platform $ARCH"

if [ -f /etc/os-release ]; then
    # Sourcing the file makes variables like $ID and $ID_LIKE available
    . /etc/os-release
    if [[ "$ID" == "debian" || "$ID_LIKE" == "debian" ]]; then
        DISTRO="$ID"
        debug "Running on $ID"
    fi
else
    echo "Could not determine distribution (/etc/os-release not found)."
fi

if [[ "$CONTROL_NETWORKING" == "ask" && -n "$DISTRO" ]]; then
  debug "" \
    "Photonvision uses NetworkManager to control networking on your device." \
    "This may alter the network configuration on your computer and override" \
    "any existing networking configuration."
  read -r -p "Do you want this script to install NetworkManager and allow PhotonVision to control networking? [y/N]: " response
  if [[ $response == [yY] || $response == [yY][eE][sS] ]]; then
    CONTROL_NETWORKING="yes"
  else
    CONTROL_NETWORKING="no"
  fi
fi

if [[ "$CONTROL_NETWORKING" == "yes" ]]; then
  debug "PhotonVision will install NetworkManager (if needed) and control networking on this device!"
else
  debug "PhotonVision will not control networking. You will have to configure the network manually."
  USER_CONTROL="yes"
fi

# select the right version of the PhotonVision release URL
if [ "$PV_VERSION" = "latest" ] ; then
  RELEASE_URL="https://api.github.com/repos/photonvision/photonvision/releases/latest"
else
  RELEASE_URL="https://api.github.com/repos/photonvision/photonvision/releases/tags/$PV_VERSION"
fi

DOWNLOAD_URL=$(wget -q --header="$AUTH_TOKEN" -O - "$RELEASE_URL" |
                  grep -oP -m 1 "browser_download_url.*\Khttp.*(${ARCH_NAME})\.jar"
              )

if [[ -z $DOWNLOAD_URL ]] ; then
  die "PhotonVision '$PV_VERSION' is not available for $ARCH_NAME!" \
      "Use ./install --list-versions to get a list of available versions."
fi

debug "Updating package list..."
if [[ -z $TEST ]]; then
  apt-get -q update
fi
debug "Updated package list."

install_required avahi-daemon libatomic1 v4l-utils sqlite3 openjdk-25-jre-headless usbtop

debug "" "Adding cpu governor service"
GOV_FILE="/etc/systemd/system/cpu_governor.service"
GOV_SERVICE=$(cat << GOVERNOREOF
[Unit]
Description=Service that sets the cpu frequency governor

[Service]
Type=oneshot
ExecStart=bash -c 'echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor'

[Install]
WantedBy=multi-user.target
GOVERNOREOF
)
debug "Writing:\n$GOV_SERVICE" "To: '$GOV_FILE'"
if [[ -z $TEST ]]; then
  printf "%s\n" "$GOV_SERVICE" > "$GOV_FILE"
  chmod 644 "$GOV_FILE"
  systemctl enable cpu_governor.service
fi

if [[ "$CONTROL_NETWORKING" == "yes" ]]; then
  NM_FILE="/etc/netplan/50-default-nm-renderer.yaml"
  NM_CONFIG=$'network:\n  renderer: NetworkManager'

  debug "NetworkManager installation requested. Installing components..."
  install_required network-manager net-tools

  debug "Configuring NetworkManager ..."
  if [[ -z $TEST ]]; then
    systemctl disable systemd-networkd-wait-online.service
  fi
  if [[ -d /etc/netplan/ ]]; then
    debug "Writing:\n$NM_CONFIG" "To: '$NM_FILE'"
    if [[ -z $TEST ]]; then
      printf "%s\n" "$NM_CONFIG" > "$NM_FILE"
      chmod 600 "$NM_FILE"
    fi
  fi
  debug "NetworkManager configuration complete."
fi

debug "" "Downloading PhotonVision '$PV_VERSION' from '$DOWNLOAD_URL'..."

if [[ -z $TEST ]]; then
  mkdir -p /opt/photonvision
  cd /opt/photonvision || die "Tried to enter /opt/photonvision, but it was not created."
  wget -q --header="$AUTH_TOKEN" -O photonvision.jar "$DOWNLOAD_URL"
fi
debug "Downloaded PhotonVision."

CPUs="# AllowedCPUs=4-7"
if grep -q "RK3588" /proc/cpuinfo; then
  debug "This has a Rockchip RK3588, enabling big cores"
  CPUs="AllowedCPUs=4-7"
fi

debug "Creating the PhotonVision systemd service ..."

PV_FILE="/lib/systemd/system/photonvision.service"
PV_SERVICE=$(cat << PVSERVICEEOF
[Unit]
Description=Service that runs PhotonVision
# Uncomment the next line to have photonvision startup wait for NetworkManager startup
${USER_CONTROL:+# }After=network.target

[Service]
WorkingDirectory=/opt/photonvision
# Run photonvision at "nice" -10, which is higher priority than standard
Nice=-10
# for non-uniform CPUs, like big.LITTLE, you want to select the big cores
# look up the right values for your CPU
$CPUs

ExecStart=/usr/bin/java -Xmx512m -jar /opt/photonvision/photonvision.jar ${USER_CONTROL:+-n}
ExecStop=/bin/systemctl kill photonvision
Type=simple
Restart=on-failure
RestartSec=1

[Install]
WantedBy=multi-user.target
PVSERVICEEOF
)

debug "Writing:\n$PV_SERVICE" "To: '$PV_FILE'"

if [[ -z $TEST ]]; then
  if [[ $(systemctl --quiet is-active photonvision) == "active" ]]; then
    debug "PhotonVision is already running. Stopping service."
    systemctl stop photonvision
    systemctl disable photonvision
    rm /lib/systemd/system/photonvision.service
    rm /etc/systemd/system/photonvision.service
    systemctl daemon-reload
    systemctl reset-failed
  fi

  printf "%s\n" "$PV_SERVICE" > "$PV_FILE"
  cp "$PV_FILE" /etc/systemd/system/photonvision.service
  chmod 644 /etc/systemd/system/photonvision.service
  systemctl daemon-reload
  systemctl enable photonvision.service
fi

debug "Created PhotonVision systemd service."

debug "PhotonVision installation complete."
