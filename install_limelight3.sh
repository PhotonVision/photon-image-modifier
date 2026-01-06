#!/bin/bash

# Exit on errors, print commands, ignore unset variables
set -ex +u

# mount partition 1 as /boot/firmware
mkdir --parent /boot/firmware
mount "${loopdev}p1" /boot/firmware
ls -la /boot/firmware

# Run the pi install script
chmod +x ./install_pi.sh
./install_pi.sh

# Add the one extra file for the LL3
wget https://datasheets.raspberrypi.org/cmio/dt-blob-cam1.bin -O /boot/firmware/dt-blob.bin

umount /boot/firmware
