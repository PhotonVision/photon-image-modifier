#!/bin/bash

# Exit on errors, print commands, ignore unset variables
set -ex +u

# Run the pi install script
chmod +x ./install_pi.sh
./install_pi.sh "$1"

# mount partition 1 as /boot/firmware
mkdir --parent /boot/firmware
mount "${loopdev}p1" /boot/firmware
ls -la /boot/firmware

# Install our new config.txt with OV9281 overlay
install -m 644 luma_p1/config.txt /boot/firmware

# Add the database file for the p1 hardware config and default pipeline
mkdir -p /opt/photonvision/photonvision_config
install -v -m 644 luma_p1/photon.sqlite /opt/photonvision/photonvision_config/photon.sqlite

umount /boot/firmware
