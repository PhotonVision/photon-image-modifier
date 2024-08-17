# Run normal photon installer
chmod +x ./install.sh
./install.sh -q

# edit boot partition
install -m 644 limelight/config.txt /boot/
install -m 644 userconf.txt /boot/

# install LL DTS
dtc -O dtb limelight/gloworm-dt.dts -o /boot/dt-blob.bin

# Kill wifi and other networking things
install -v -m 644 files/wait.conf /etc/systemd/system/dhcpcd.service.d/
install -v files/rpi-blacklist.conf /etc/modprobe.d/blacklist.conf

# Update pigipio service file to listen locally
install -v -m 644 files/pigpiod.service /lib/systemd/system/pigpiod.service
systemctl daemon-reload

# Enable ssh/pigpiod
systemctl enable ssh
systemctl enable pigpiod

# Remove extra packages too
echo "Purging extra things"
apt-get purge -y python3 gdb gcc g++ linux-headers* libgcc*-dev libqt* wpasupplicant wireless-tools firmware-atheros firmware-brcm80211 firmware-libertas firmware-misc-nonfree firmware-realtek raspberrypi-net-mods device-tree-compiler
apt-get autoremove -y

echo "Installing additional things"
sudo apt-get update
apt-get install -y pigpiod pigpio device-tree-compiler libraspberrypi-bin
apt-get install -y network-manager net-tools
# libcamera-driver stuff
apt-get install -y libegl1 libopengl0 libopencv-core406 libgl1-mesa-dri libcamera0.1 libgbm1


rm -rf /var/lib/apt/lists/*
apt-get clean

rm -rf /usr/share/doc
rm -rf /usr/share/locale/
