#!/bin/bash

# Exit on errors, print commands, ignore unset variables
set -ex +u

# mount partition 1 as /CIDATA
mkdir --parent /CIDATA
mount "${loopdev}p1" /CIDATA
ls -la /CIDATA

# Create pi/raspberry login
if id "pi" >/dev/null 2>&1; then
    echo 'user found'
else
    echo "creating pi user"
    useradd pi -m -b /home -s /bin/bash
    usermod -a -G sudo pi
    echo 'pi ALL=(ALL) NOPASSWD: ALL' | tee -a /etc/sudoers.d/010_pi-nopasswd >/dev/null
    chmod 0440 /etc/sudoers.d/010_pi-nopasswd
fi
echo "pi:raspberry" | chpasswd

# silence log spam from dpkg
cat > /etc/apt/apt.conf.d/99dpkg.conf << EOF
Dpkg::Progress-Fancy "0";
APT::Color "0";
Dpkg::Use-Pty "0";
EOF

apt-get -q update

before=$(df --output=used / | tail -n1)
# clean up stuff

# get rid of snaps
echo "Purging snaps"
rm -rf /var/lib/snapd/seed/snaps/*
rm -f /var/lib/snapd/seed/seed.yaml
apt-get --yes -q purge lxd-installer lxd-agent-loader
apt-get --yes -q purge snapd

# remove bluetooth daemon
apt-get --yes -q purge bluez

apt-get --yes -q autoremove

# remove firmware that (probably) isn't needed
rm -rf /usr/lib/firmware/mrvl
rm -rf /usr/lib/firmware/mellanox
rm -rf /usr/lib/firmware/qcom
rm -rf /usr/lib/firmware/nvidia
rm -rf /usr/lib/firmware/intel
rm -rf /usr/lib/firmware/amdgpu

after=$(df --output=used / | tail -n1)
freed=$(( before - after ))
echo "Freed up $freed KiB"

# run Photonvision install script
chmod +x ./install.sh
./install.sh --install-nm=yes --arch=aarch64 --version="$1"

echo "Installing additional things"
apt-get --yes -qq install libc6 libstdc++6

# let netplan create the config during cloud-init
rm -f /etc/netplan/00-default-nm-renderer.yaml

# set NetworkManager as the renderer in cloud-init
cp -f ./OPi5_CIDATA/network-config /CIDATA/network-config
# add customized user-data file for cloud-init
cp -f ./OPi5_CIDATA/user-data /CIDATA/user-data

# modify photonvision.service to enable big cores
sed -i 's/# AllowedCPUs=4-7/AllowedCPUs=4-7/g' /lib/systemd/system/photonvision.service
cp -f /lib/systemd/system/photonvision.service /etc/systemd/system/photonvision.service
chmod 644 /etc/systemd/system/photonvision.service
cat /etc/systemd/system/photonvision.service

# networkd isn't being used, this causes an unnecessary delay
systemctl disable systemd-networkd-wait-online.service

# PhotonVision server is managing the network, so it doesn't need to wait for online
systemctl disable NetworkManager-wait-online.service

# the bluetooth service isn't needed and causes problems with cloud-init
# the chip has different names on different boards. Examples are:
#   OrangePi5: ap6275p-bluetooth.service
#   OrangePi5pro: ap6256s-bluetooth.service
#   OrangePi5b: ap6275p-bluetooth.service
#   OrangePi5max: ap6611s-bluetooth.service
# instead of keeping a catalog of these services, find them based on a pattern and mask them
btservices=$(systemctl list-unit-files *bluetooth.service | tail -n +2 | head -n -1 | awk '{print $1}')
for btservice in $btservices; do
    echo "Masking: $btservice"
    systemctl mask "$btservice"
done

rm -rf /var/lib/apt/lists/*
apt-get --yes -qq clean

rm -rf /usr/share/doc
rm -rf /usr/share/locale/

umount /CIDATA
