#!/bin/bash -v

# Verbose and exit on errors
set -ex
# Run normal photon installer

cd /tmp/build

chmod +x ./install.sh
./install.sh --install-nm=yes

# and edit boot partition
install -m 644 config.txt /boot/
install -m 644 userconf.txt /boot/

# Kill wifi and other networking things
install -v -m 644 -D -t /etc/systemd/system/dhcpcd.service.d/ files/wait.conf
install -v files/rpi-blacklist.conf /etc/modprobe.d/blacklist.conf

# Update pigipio service file to listen locally
install -v -m 644 files/pigpiod.service /lib/systemd/system/pigpiod.service
systemctl daemon-reload

# Enable ssh/pigpiod
systemctl enable ssh
systemctl enable pigpiod


echo "Installing additional things"
sudo apt-get update
apt-get install -y pigpiod pigpio device-tree-compiler
apt-get install -y network-manager net-tools
# libcamera-driver stuff
apt-get install -y libegl1 libopengl0 libgl1-mesa-dri libgbm1 libegl1-mesa-dev libcamera-dev cmake build-essential libdrm-dev libgbm-dev default-jdk openjdk-17-jdk

# Remove extra packages too
# echo "Purging extra things"
# apt-get purge -y gdb gcc g++ linux-headers* libgcc*-dev
# apt-get autoremove -y

rm -rf /var/lib/apt/lists/*
apt-get clean

rm -rf /usr/share/doc
rm -rf /usr/share/locale/
