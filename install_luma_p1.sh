#!/bin/bash -v

# Verbose and exit on errors
set -ex

cd /tmp/build

# Run the pi install script
chmod +x ./install_pi.sh
./install_pi.sh

# Install our new config.txt with OV9281 overlay
install -m 644 luma_p1/config.txt /boot/

# Add the database file for the p1 hardware config and default pipeline
mkdir -p /opt/photonvision/photonvision_config
install -v -m 644 luma_p1/photon.sqlite /opt/photonvision/photonvision_config/photon.sqlite
