#!/bin/bash

# Exit on errors, print commands, ignore unset variables
set -ex +u

# Run the pi install script
chmod +x ./install_pi.sh
./install_pi.sh "$1"

# Add the one extra file for the snakeyes hardware config
mkdir -p /opt/photonvision/photonvision_config
install -v -m 644 files/snakeyes/photon.sqlite /opt/photonvision/photonvision_config/photon.sqlite
