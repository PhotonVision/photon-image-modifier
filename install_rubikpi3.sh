#!/bin/bash -v
# Verbose and exit on errors
set -ex

REPO_ENTRY="deb http://apt.thundercomm.com/rubik-pi-3/noble ppa main"
HOST_ENTRY="151.106.120.85 apt.rubikpi.ai"	# TODO: Remove legacy

# First update the APT
sudo apt-get update -y


# TODO: Remove legacy
sudo sed -i "/$HOST_ENTRY/d" /etc/hosts || true
sudo sed -i '/apt.rubikpi.ai ppa main/d' /etc/apt/sources.list || true

if ! grep -q "^[^#]*$REPO_ENTRY" /etc/apt/sources.list; then
    echo "$REPO_ENTRY" | sudo tee -a /etc/apt/sources.list >/dev/null
fi

# Add the GPG key for the RUBIK Pi PPA
wget -qO - https://thundercomm.s3.dualstack.ap-northeast-1.amazonaws.com/uploads/web/rubik-pi-3/tools/key.asc | sudo tee /etc/apt/trusted.gpg.d/rubikpi3.asc

sudo apt update

sudo apt-get install libqnn1 libsnpe1 tensorflow-lite-qcom-apps qcom-adreno1

# Go back to parent directory to run photon installer
cd ..

# Run normal photon installer
chmod +x ./install.sh
./install.sh --install-nm=yes --arch=aarch64


# Enable ssh/pigpiod
systemctl enable ssh
systemctl enable pigpiod


# Remove extra packages too
echo "Purging extra things"
apt-get purge -y gdb gcc g++ linux-headers* libgcc*-dev
apt-get autoremove -y

echo "Installing additional things"
sudo apt-get update
apt-get install -y pigpiod pigpio device-tree-compiler
apt-get install -y network-manager net-tools
# libcamera-driver stuff
apt-get install -y libegl1 libopengl0 libgl1-mesa-dri libcamera-dev libgbm1

rm -rf /var/lib/apt/lists/*
apt-get clean

rm -rf /usr/share/doc
rm -rf /usr/share/locale/
