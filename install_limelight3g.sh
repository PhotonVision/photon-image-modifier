# Run the pi install script
chmod +x ./install_pi.sh
./install_pi.sh

install -m 644 limelight3g/config.txt /boot/

# Add the one extra file for the LL3
wget https://datasheets.raspberrypi.org/cmio/dt-blob-cam1.bin -O /boot/dt-blob.bin