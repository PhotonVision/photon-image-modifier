#!/bin/bash

# Exit on errors, print commands, ignore unset variables
set -ex +u

# silence log spam from dpkg
cat > /etc/apt/apt.conf.d/99dpkg.conf << EOF
Dpkg::Progress-Fancy "0";
APT::Color "0";
Dpkg::Use-Pty "0";
EOF

# Run normal photon installer
chmod +x ./install.sh
./install.sh -v "$1" --install-nm=yes --arch=x86_64 --version="$1"

# configure hostname
sudo hostnamectl set-hostname photonvision

# Enable ssh
systemctl enable ssh
