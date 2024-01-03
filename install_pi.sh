# Run normal photon installer

wget https://git.io/JJrEP -O install.sh
chmod +x install.sh
./install.sh
rm install.sh


# and edit boot partition
install -m 644 config.txt /boot/
install -m 644 userconf.txt /boot/

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
apt-get purge -y python3 gdb gcc g++ linux-headers* libgcc*-dev device-tree-compiler
apt-get autoremove -y

echo "Installing additional things"
sudo apt-get update
apt-get install -y pigpiod pigpio device-tree-compiler libraspberrypi-bin
apt-get install -y network-manager
apt-get install -y net-tools
# libcamera-driver stuff + libatomic1 for wpilib
apt-get install -y libegl1 libopengl0 libopencv-core406 libgl1-mesa-dri libcamera0.1 libgbm1 libatomic1
# mrcal stuff
apt-get install -y libcholmod3 liblapack3 libsuitesparseconfig5


rm -rf /var/lib/apt/lists/*
apt-get clean

rm -rf /usr/share/doc
rm -rf /usr/share/locale/
