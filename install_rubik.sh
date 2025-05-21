#!/bin/bash -v

apt remove gnome
apt autoremove
apt remove cups firefox-esr gstreamer1.0-plugins-base xwayland xorg
apt autoremove
apt remove pipewire pulseaudio
apt autoremove

apt remove wpasupplicant

rm -r /usr/share/gstreamer-1.0 
rm -r /usr/lib/firmware/qcacld/
rm -r /usr/lib/modules/6.6.38/kernel/drivers/net/wireless

# rm -r /var/cache/apt
