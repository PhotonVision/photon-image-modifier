#!/bin/bash -v

# Verbose and exit on errors
set -ex

# Run the pi install script
chmod +x ./install_pi.sh
./install_pi.sh

# Install our new config.txt with OV9281 overlay
install -m 644 luma_p1/config.txt /boot/
