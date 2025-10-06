#!/bin/bash -v

# Verbose and exit on errors
set -ex

sudo apt upgrade -y

# First update the APT
sudo -E apt-get update

sudo apt update -y 2>&1 | tee -a $LOG_FILE
sudo apt upgrade -y 2>&1 | tee -a $LOG_FILE
echo "APT Update and Upgraded" 2>&1 | tee -a $LOG_FILE

echo "Installing General APT packages..."
for pkg in "${APT_PACKAGES[@]}"; do
  if is_installed "apt-$pkg"; then
    echo "APT $pkg already installed."
    continue
  fi

  if sudo -E apt-get install -y "$pkg"; then
    echo "APT $pkg installed."
    mark_status "apt-$pkg" "success"
    echo "APT apt-$pkg Installed" >> $LOG_FILE
  else
    echo "APT $pkg failed."
    mark_status "apt-$pkg" "fail"
    echo "APT apt-$pkg Failed" >> $LOG_FILE
  fi
done


git clone -b ubuntu_setup --single-branch https://github.com/rubikpi-ai/rubikpi-script.git 
cd rubikpi-script  
./install_ppa_pkgs.sh 


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
