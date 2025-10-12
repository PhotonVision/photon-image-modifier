#!/bin/bash -v
# Verbose and exit on errors
set -ex

cd /tmp/build
echo '=== Current directory: \$(pwd) ==='
echo '=== Files in current directory: ==='
ls -la

# Create user pi:raspberry login
echo "creating pi user"
useradd pi -m -b /home -s /bin/bash
usermod -a -G sudo pi
echo 'pi ALL=(ALL) NOPASSWD: ALL' | tee -a /etc/sudoers.d/010_pi-nopasswd >/dev/null
chmod 0440 /etc/sudoers.d/010_pi-nopasswd

echo "pi:raspberry" | chpasswd

# Delete ubuntu user

if id "ubuntu" >/dev/null 2>&1; then
    echo 'removing ubuntu user'
    deluser --remove-home ubuntu
fi

REPO_ENTRY="deb http://apt.thundercomm.com/rubik-pi-3/noble ppa main"
HOST_ENTRY="151.106.120.85 apt.rubikpi.ai"	# TODO: Remove legacy

# First update the APT
apt-get update -y


# TODO: Remove legacy
sed -i "/$HOST_ENTRY/d" /etc/hosts || true
sed -i '/apt.rubikpi.ai ppa main/d' /etc/apt/sources.list || true

if ! grep -q "^[^#]*$REPO_ENTRY" /etc/apt/sources.list; then
    echo "$REPO_ENTRY" | tee -a /etc/apt/sources.list >/dev/null
fi

# Add the GPG key for the RUBIK Pi PPA
wget -qO - https://thundercomm.s3.dualstack.ap-northeast-1.amazonaws.com/uploads/web/rubik-pi-3/tools/key.asc | tee /etc/apt/trusted.gpg.d/rubikpi3.asc

apt update -y

apt-get -y --allow-downgrades install libsqlite3-0=3.45.1-1ubuntu2
apt-get -y install libqnn1 libsnpe1 tensorflow-lite-qcom-apps qcom-adreno1

ln -sf libOpenCL.so.1 /usr/lib/aarch64-linux-gnu/libOpenCL.so # Fix for snpe-tools

# Run normal photon installer
chmod +x ./install.sh
./install.sh --install-nm=yes --arch=aarch64

# Enable ssh
systemctl enable ssh


# Remove extra packages too
echo "Purging extra things"
apt-get purge -y gdb gcc g++ linux-headers* libgcc*-dev perl-modules* git vim-runtime tensorflow-lite-qcom-apps

# get rid of snaps
echo "Purging snaps"
rm -rf /var/lib/snapd/seed/snaps/*
rm -f /var/lib/snapd/seed/seed.yaml
apt-get purge --yes --quiet lxd-installer lxd-agent-loader
apt-get purge --yes --quiet snapd
apt-get autoremove -y

echo "Installing additional things"

apt-get update -y

apt-get install -y device-tree-compiler

rm -rf /var/lib/apt/lists/*
apt-get clean

rm -rf /usr/share/doc
rm -rf /usr/share/locale/

echo '=== Running install_common.sh ==='
chmod +x ./install_common.sh
./install_common.sh
echo '=== Creating version file ==='
mkdir -p /opt/photonvision/
echo '{$1};rubikpi3' > /opt/photonvision/image-version
echo '=== Installation complete ==='