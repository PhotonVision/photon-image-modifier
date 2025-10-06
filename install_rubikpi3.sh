#!/bin/bash -v

# Verbose and exit on errors
set -ex

sudo add-apt-repository ppa:ubuntu-qcom-iot/qcom-noble-ppa
sudo apt-get install libqnn1

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
