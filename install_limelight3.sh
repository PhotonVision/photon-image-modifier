#!/bin/bash

# Exit on errors, print commands, ignore unset variables
set -ex +u

# Run the pi install script
chmod +x ./install_pi.sh
./install_pi.sh "$1" "limelight3/config.txt"

# mount partition 1 as /boot/firmware
mkdir --parent /boot/firmware
mount "${loopdev}p1" /boot/firmware
ls -la /boot/firmware

# link old config.txt location for diozero compatibility
# TODO(thatcomputerguy0101): Remove this when diozero checks the new location
ln -sf /boot/firmware/config.txt /boot/config.txt

umount /boot/firmware
