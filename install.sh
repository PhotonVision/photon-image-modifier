#!/bin/bash

# Exit on errors
set -e +u

needs_arg() {
    if [ -z "$OPTARG" ]; then
      die "Argument is required for --$OPT option" \
          "See './install.sh -h' for more information."
    fi;
}

die() {
  for arg in "$@"; do
    echo "$arg" 1>&2
  done
  exit 1
}

debug() {
  if [ -z "$QUIET" ] ; then
    for arg in "$@"; do
      echo "$TEST$arg"
    done
  fi
}

package_is_installed(){
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

install_if_missing() {
  if package_is_installed "$1" ; then
    debug "Found existing $1. Skipping..."
    # Always mark our upstream apt deps as held back, which will prevent the package
    # from being automatically installed, upgraded or removed
    if [[ -z $TEST ]]; then
      apt-mark manual "$1"
    fi
    return
  fi

  debug "Installing $1..."
  if [[ -z $TEST ]]; then
    apt-get --yes install "$1"
    # Always mark our upstream apt deps as held back, which will prevent the package
    # from being automatically installed, upgraded or removed
    apt-mark manual "$1"
  fi
  debug "$1 installation complete."
}

get_versions() {
  PHOTON_VISION_RELEASES="$(wget -qO- https://api.github.com/repos/photonvision/photonvision/releases?per_page=$1)"

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
  cat << EOF
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
  -m [option], --install-nm=[option]
      Controls NetworkManager installation (Ubuntu only).
      Options: "yes", "no", "ask".
      Default: "ask" (unless -q or --quiet is specified, then "no").
      "ask" prompts for installation. Ignored on other distros.
  -n, --no-networking
      Disable networking. This will also prevent installation of
      NetworkManager, overriding -m,--install-nm.
  -q, --quiet
      Silent install, automatically accepts all defaults. For
      non-interactive use. Makes -m,--install-nm default to "no".
  -t, --test
      Run in test mode. All actions that make chnages to the system
      are suppressed.

EOF
}

# Exit with message if attempting to run on SystemCore
if grep -iq "systemcore" /etc/os-release; then
  die "This install script does not work on Systemcore."
fi

INSTALL_NETWORK_MANAGER="ask"
DISABLE_NETWORKING="false"
VERSION="latest"

while getopts "hlva:mnqt-:" OPT; do
  if [ "$OPT" = "-" ]; then
    OPT="${OPTARG%%=*}"       # extract long option name
    OPTARG="${OPTARG#"$OPT"}" # extract long option argument (may be empty)
    OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
  else
    nextopt=${!OPTIND}        # check for an optional argument followinng a short option
    if [[ -n $nextopt && $nextopt != -* ]]; then
      OPTIND=$((OPTIND + 1))
      OPTARG=$nextopt
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
      VERSION=${OPTARG:-latest}
      ;;
    a | arch) needs_arg; ARCH=$OPTARG
      ;;
    m | install-nm)
      INSTALL_NETWORK_MANAGER="$(echo "${OPTARG:-yes}" | tr '[:upper:]' '[:lower:]')"
      case "$INSTALL_NETWORK_MANAGER" in
        yes)
          ;;
        no)
          ;;
        ask)
          ;;
        * )
          die "Valid options for -m, --install-nm are: 'yes', 'no', and 'ask'"
          ;;
      esac
      ;;
    n | no-networking) DISABLE_NETWORKING="true"
      ;;
    q | quiet) QUIET="true"
      ;;
    t | test) TEST="[TEST]:"
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

debug "This is the installation script for PhotonVision."

if [[ "$(id -u)" != "0" && -z $TEST ]]; then
   die "This script must be run as root"
fi

if is_chroot ; then
  debug "Running in chroot. Arch should be specified."
fi

if [[ -z "$ARCH" ]]; then
  debug "Arch was not specified. Inferring..."
  ARCH=$(uname -m)
  debug "Arch was inferred to be $ARCH"
fi

ARCH_NAME=""
if [ "$ARCH" = "aarch64" ]; then
  ARCH_NAME="linuxarm64"
elif [ "$ARCH" = "armv7l" ]; then
  die "ARM32 is not supported by PhotonVision. Exiting."
elif [ "$ARCH" = "x86_64" ]; then
  ARCH_NAME="linuxx64"
else
  die "Unsupported or unknown architecture: '$ARCH'." \
  "Please specify your architecture using: ./install.sh -a <arch> " \
  "Run './install.sh -h' for more information."
fi

debug "Installing for platform $ARCH"

# make sure that we are downloading a valid version
if [ "$VERSION" = "latest" ] ; then
  RELEASE_URL="https://api.github.com/repos/photonvision/photonvision/releases/latest"
else
  RELEASE_URL="https://api.github.com/repos/photonvision/photonvision/releases/tags/$VERSION"
fi

DOWNLOAD_URL=$(curl -sk "$RELEASE_URL" |
                  grep "browser_download_url.*$ARCH_NAME.jar" |
                  cut -d : -f 2,3 |
                  tr -d '"'
              )

if [[ -z $DOWNLOAD_URL ]] ; then
  die "PhotonVision '$VERSION' is not available for $ARCH_NAME!" \
      "See ./install --list-versions for a list of available versions."
fi

DISTRO=$(lsb_release -is)

# Only ask if it makes sense to do so.
# i.e. the distro is Ubuntu, you haven't requested disabling networking,
# and you have requested a quiet install.
if [[ "$INSTALL_NETWORK_MANAGER" == "ask" ]]; then
  if [[ "$DISTRO" != "Ubuntu" || "$DISABLE_NETWORKING" == "true" || -n "$QUIET" ]] ; then
    INSTALL_NETWORK_MANAGER="no"
  fi
fi

if [[ "$INSTALL_NETWORK_MANAGER" == "ask" ]]; then
  debug ""
  debug "Photonvision uses NetworkManager to control networking on your device."
  debug "This could possibly mess up the network configuration in Ubuntu."
  read -p "Do you want this script to install and configure NetworkManager? [y/N]: " response
  if [[ $response == [yY] || $response == [yY][eE][sS] ]]; then
    INSTALL_NETWORK_MANAGER="yes"
  fi
fi

debug "Updating package list..."
if [[ -z $TEST ]]; then
  apt-get -q update
fi
debug "Updated package list."

install_if_missing curl
install_if_missing avahi-daemon
install_if_missing cpufrequtils
install_if_missing libatomic1
install_if_missing v4l-utils
install_if_missing sqlite3
install_if_missing openjdk-17-jre-headless

debug "Setting cpufrequtils to performance mode"
if [[ -z $TEST ]]; then
  if [ -f /etc/default/cpufrequtils ]; then
      sed -i -e 's/^#\?GOVERNOR=.*$/GOVERNOR=performance/' /etc/default/cpufrequtils
  else
      echo 'GOVERNOR=performance' > /etc/default/cpufrequtils
  fi
fi

if [[ "$INSTALL_NETWORK_MANAGER" == "yes" ]]; then
  debug "NetworkManager installation requested. Installing components..."
  install_if_missing network-manager
  install_if_missing net-tools

  debug "Configuring..."
  if [[ -z $TEST ]]; then
    systemctl disable systemd-networkd-wait-online.service
    if [[ -d /etc/netplan/ ]]; then
      cat > /etc/netplan/00-default-nm-renderer.yaml <<EOF
network:
  renderer: NetworkManager
EOF
    fi
    debug "network-manager installation complete."
  fi
fi

debug ""
debug "Downloading PhotonVision '$VERSION'..."

if [[ -z $TEST ]]; then
  mkdir -p /opt/photonvision
  cd /opt/photonvision || die "Tried to enter /opt/photonvision, but it was not created."
  curl -sk "$RELEASE_URL" |
      grep "browser_download_url.*$ARCH_NAME.jar" |
      cut -d : -f 2,3 |
      tr -d '"' |
      wget -qi - -O photonvision.jar
fi
debug "Downloaded PhotonVision."

debug "Creating the PhotonVision systemd service..."

if [[ -z $TEST ]]; then
  # service --status-all doesn't list photonvision on OrangePi use systemctl instead:
  if [[ $(systemctl --quiet is-active photonvision) = "active" ]]; then
    debug "PhotonVision is already running. Stopping service."
    systemctl stop photonvision
    systemctl disable photonvision
    rm /lib/systemd/system/photonvision.service
    rm /etc/systemd/system/photonvision.service
    systemctl daemon-reload
    systemctl reset-failed
  fi

  cat > /lib/systemd/system/photonvision.service <<EOF
[Unit]
Description=Service that runs PhotonVision
# Uncomment the next line to have photonvision startup wait for NetworkManager startup
# After=network.target

[Service]
WorkingDirectory=/opt/photonvision
# Run photonvision at "nice" -10, which is higher priority than standard
Nice=-10
# for non-uniform CPUs, like big.LITTLE, you want to select the big cores
# look up the right values for your CPU
# AllowedCPUs=4-7

ExecStart=/usr/bin/java -Xmx512m -jar /opt/photonvision/photonvision.jar
ExecStop=/bin/systemctl kill photonvision
Type=simple
Restart=on-failure
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF

  if [[ "$DISABLE_NETWORKING" == "true" ]]; then
    debug "Adding -n switch to photonvision startup to disable network management"
    sed -i "s/photonvision.jar/photonvision.jar -n/" /lib/systemd/system/photonvision.service
  else
    debug "Setting photonvision.service to start after network.target is reached"
    sed -i "s/# After=network.target/After=network.target/g" /lib/systemd/system/photonvision.service
  fi

  if grep -q "RK3588" /proc/cpuinfo; then
    debug "This has a Rockchip RK3588, enabling big cores"
    sed -i 's/# AllowedCPUs=4-7/AllowedCPUs=4-7/g' /lib/systemd/system/photonvision.service
  fi

  cp /lib/systemd/system/photonvision.service /etc/systemd/system/photonvision.service
  chmod 644 /etc/systemd/system/photonvision.service
  systemctl daemon-reload
  systemctl enable photonvision.service
fi

debug "Created PhotonVision systemd service."

debug "PhotonVision installation successful."
