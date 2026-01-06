#!/bin/bash

# Exit on errors, print commands, ignore unset variables
set -ex +u

# mount partition 1 as /boot/firmware
mkdir --parent /boot/firmware
mount "${loopdev}p1" /boot/firmware
ls -la /boot/firmware

# silence log spam from dpkg
cat > /etc/apt/apt.conf.d/99dpkg.conf << EOF
Dpkg::Progress-Fancy "0";
APT::Color "0";
Dpkg::Use-Pty "0";
EOF

# Run normal photon installer
chmod +x ./install.sh
./install.sh --install-nm=yes --arch=aarch64 --version="$1"

# edit boot partition
install -m 644 limelight/config.txt /boot/firmware/
install -m 644 userconf.txt /boot/firmware/

# install LL DTS
dtc -O dtb limelight/gloworm-dt.dts -o /boot/firmware/dt-blob.bin

# Kill wifi and other networking things
install -v -m 644 -D -t /etc/systemd/system/dhcpcd.service.d/ files/wait.conf
install -v files/rpi-blacklist.conf /etc/modprobe.d/blacklist.conf

# Enable ssh
systemctl enable ssh

# Remove extra packages too
echo "Purging extra things"
apt-get purge -y gdb gcc g++ linux-headers* libgcc*-dev libqt* wpasupplicant wireless-tools firmware-atheros firmware-brcm80211 firmware-libertas firmware-misc-nonfree firmware-realtek raspberrypi-net-mods
apt-get autoremove -y

echo "Installing additional things"
sudo apt-get update
apt-get install -y device-tree-compiler
apt-get install -y network-manager net-tools
# libcamera-driver stuff
apt-get install -y libegl1 libopengl0 libgl1-mesa-dri libcamera-dev libgbm1

rm -rf /var/lib/apt/lists/*
apt-get clean

rm -rf /usr/share/doc
rm -rf /usr/share/locale/

umount /boot/firmware
