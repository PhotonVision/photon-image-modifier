#!/bin/bash

# Exit on errors, print commands, ignore unset variables
set -ex +u

# change hostname
sed -i 's/orangepi6plus/photonvision/g' /etc/hostname
sed -i 's/orangepi6plus/photonvision/g' /etc/hosts

# silence log spam from dpkg
cat > /etc/apt/apt.conf.d/99dpkg.conf << EOF
Dpkg::Progress-Fancy "0";
APT::Color "0";
Dpkg::Use-Pty "0";
EOF

apt-get -q update

before=$(df --output=used / | tail -n1)
# clean up stuff

# remove build-essential for minor space savings
apt-get --yes purge --allow-change-held-packages -q *-dev git
apt-get --yes autoremove --allow-change-held-packages --purge

after=$(df --output=used / | tail -n1)
freed=$(( before - after ))
echo "Freed up $freed KiB"

# run Photonvision install script
chmod +x ./install.sh
./install.sh --install-nm=yes --arch=aarch64 --version="$1"

echo "Installing additional things"
apt-get --yes -qq install libc6 libstdc++6

# modify photonvision.service to enable big cores
# For reasons beyond human comprehension, the little cores are on 2, 3, 4, and 5.
sed -i 's/# AllowedCPUs=4-7/AllowedCPUs=0,1,6-11/g' /lib/systemd/system/photonvision.service
cp -f /lib/systemd/system/photonvision.service /etc/systemd/system/photonvision.service
chmod 644 /etc/systemd/system/photonvision.service
cat /etc/systemd/system/photonvision.service

# networkd isn't being used, this causes an unnecessary delay
systemctl disable systemd-networkd-wait-online.service

# PhotonVision server is managing the network, so it doesn't need to wait for online
systemctl disable NetworkManager-wait-online.service

# there's no internal bluetooth or wifi on the opi6plus

# there's also no...preinstalled ssh keys.
ssh-keygen -A

rm -rf /var/lib/apt/lists/*
apt-get --yes -qq clean

rm -rf /usr/share/doc
rm -rf /usr/share/locale/
