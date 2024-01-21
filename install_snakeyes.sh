# Run the pi install script
./install_pi.sh

# Add the one extra file for the snakeyes hardware config
install -v -m 644 files/snakeyes/photon.sqlite /opt/photonvision/photonvision_config/photon.sqlite
