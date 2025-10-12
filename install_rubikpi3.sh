#!/bin/bash -v
# Verbose and exit on errors
set -ex

cd /tmp/build
echo '=== Current directory: \$(pwd) ==='
echo '=== Files in current directory: ==='
ls -la

ln -sf libOpenCL.so.1 /usr/lib/aarch64-linux-gnu/libOpenCL.so # Fix for snpe-tools
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

# This needs to run before install.sh to fix some weird dependency issues
apt-get -y --allow-downgrades install libsqlite3-0=3.45.1-1ubuntu2

# Add the GPG key for the RUBIK Pi PPA
wget -qO - https://thundercomm.s3.dualstack.ap-northeast-1.amazonaws.com/uploads/web/rubik-pi-3/tools/key.asc | tee /etc/apt/trusted.gpg.d/rubikpi3.asc

# Run normal photon installer
chmod +x ./install.sh
./install.sh --install-nm=yes --arch=aarch64

# Install packages from the RUBIK Pi PPA, we skip calling apt-get update here because install.sh already does that
apt-get -y install libqnn1 libsnpe1 qcom-adreno1 device-tree-compiler

# Enable ssh
systemctl enable ssh


# Remove extra packages too
echo "Purging extra things"

# get rid of snaps
echo "Purging snaps"
rm -rf /var/lib/snapd/seed/snaps/*
rm -f /var/lib/snapd/seed/seed.yaml
apt-get purge --yes lxd-installer lxd-agent-loader snapd gdb gcc g++ linux-headers* libgcc*-dev perl-modules* git vim-runtime
apt-get autoremove -y

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