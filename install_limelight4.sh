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
install -m 644 limelight4/config.txt /boot/firmware

umount /boot/firmware
