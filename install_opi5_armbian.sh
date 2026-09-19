#!/bin/bash

# Exit on errors, print commands, ignore unset variables
set -ex +u

# silence log spam from dpkg
cat > /etc/apt/apt.conf.d/99dpkg.conf << EOF
Dpkg::Progress-Fancy "0";
APT::Color "0";
Dpkg::Use-Pty "0";
EOF

# run Photonvision install script
chmod +x ./install.sh
./install.sh --control-networking=yes --arch=aarch64 --version="$1"

echo "Installing additional things"
apt-get --yes -qq install libc6 libstdc++6

# this adds `strings` so that users can check the version of U-Boot with `sudo strings /dev/mtd0 | grep "^U-Boot"``
apt-get --yes -qq install binutils

# this isn't required, but is useful for monitoring temperature from the command line
apt-get --yes -qq install  lm-sensors

# modify photonvision.service to enable big cores
sed -i 's/# AllowedCPUs=4-7/AllowedCPUs=4-7/g' /lib/systemd/system/photonvision.service
cp -f /lib/systemd/system/photonvision.service /etc/systemd/system/photonvision.service
chmod 644 /etc/systemd/system/photonvision.service
cat /etc/systemd/system/photonvision.service

# try to 'fix' slow boot on Armbian images
# sed -i s/verbosity=1/verbosity=7/g /boot/armbianEnv.txt
sed -i 's/extraargs=/&initcall_debug ignore_loglevel cryptomgr.notests=1 nokprobes initcall_blacklist=init_kprobe_trace,crypto_kdf108_init,init_blk_tracer trace_buf_size=1 /' /boot/armbianEnv.txt

# Vulkan for the Mali-G610, needed by PhotonVision's vkapriltag detector.
# Use ARM's libmali on the vendor kbase driver, not Mesa PanVK on panthor:
# on an Orange Pi 5 Plus, same binary and image, PanVK measured 141 ms/frame
# against libmali's 11 ms, with the CPU libapriltag detector at 43 ms - so
# PanVK would make the GPU detector slower than not using the GPU at all.
# Measurements and rationale:
# https://github.com/PhotonVision/photon-image-modifier/pull/161
#
# Three things here are easy to get wrong:
#  - do NOT enable the panthor-gpu overlay. It is mutually exclusive with
#    kbase, which this kernel already has builtin (CONFIG_MALI_MIDGARD=y),
#    and binding the GPU to panthor leaves no /dev/mali0 for libmali.
#  - g24p0, not g13p0: only g24p0 ships a Vulkan ICD. g13p0 is GLES/EGL/CL
#    only and silently leaves Vulkan with no driver at all.
#  - libvulkan1 is the Vulkan *loader*, separate from libmali's ICD, so it is
#    still required. mesa-vulkan-drivers is deliberately not installed - its
#    panfrost and lavapipe ICDs would enumerate alongside libmali's and can
#    be picked instead of it.
#
# curl is not in the Armbian minimal base image, and this runs before
# install_common.sh, so it cannot be assumed present.
apt-get --yes -qq install libvulkan1 curl

LIBMALI_DEB="libmali-valhall-g610-g24p0-gbm_1.9-1_arm64.deb"
LIBMALI_URL="https://github.com/tsukumijima/libmali-rockchip/releases/download/v1.9-1-20260312-bd33ee2/${LIBMALI_DEB}"
curl -fsSL -o "/tmp/${LIBMALI_DEB}" "${LIBMALI_URL}"
# via apt, not dpkg -i, so dependencies resolve; the package also drops
# /etc/ld.so.conf.d/00-aarch64-mali.conf, which is what puts
# libMaliVulkan.so.1 on the loader path.
apt-get --yes -qq install "/tmp/${LIBMALI_DEB}"
rm -f "/tmp/${LIBMALI_DEB}"

# Hold the GPU at its top OPP. The detector submits short bursts and then
# blocks on a fence, so simple_ondemand reads it as mostly idle and keeps it
# near the frequency floor; pinning is worth ~20% and removes most of the
# frame-time variance. Wildcard rather than the literal fb000000.gpu this was
# verified against, since this one script builds every RK3588 board in the
# matrix; the other devfreq devices are "dmc" and "<addr>.npu", so neither
# gets matched.
cat > /etc/udev/rules.d/99-mali-performance.rules <<'EOF'
SUBSYSTEM=="devfreq", KERNEL=="*.gpu", ATTR{governor}="performance"
EOF

# networkd isn't being used, this causes an unnecessary delay
# systemctl disable systemd-networkd-wait-online.service

# PhotonVision server is managing the network, so it doesn't need to wait for online
systemctl disable NetworkManager-wait-online.service

# disable wireless by blacklisting broadcom drivers
cat > /etc/modprobe.d/disable-wireless.conf << EOF
# Disable wireless drivers to prevent them from loading
blacklist brcmfmac
blacklist brcmutil
blacklist rtw88_core
blacklist rtw88_pci
blacklist rtw89_core
blacklist rtw89_pci
EOF

# mask the bluetooth and wpa services to preven them from being started
systemctl mask bluetooth.service
systemctl mask wpa_supplicant.service

# disable NetworkManager from managing wireless interfaces
mkdir -p /etc/NetworkManager/conf.d
echo -e "[keyfile]\nunmanaged-devices=interface-name:wlan*" > /etc/NetworkManager/conf.d/disable-wifi.conf


# set the hostname
echo "photonvision" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1    photonvision/g" /etc/hosts

# Prevent the firstlogin script from running when root logs in for the first time.
# The script changes settings and overrides the photon user password.
# Remove the sentinel file
rm -f /root/.not_logged_in_yet

# Erase the firstlogin script
sudo rm -f /usr/lib/armbian/armbian-firstlogin

# Create a blank, dummy script in its place to prevent "file not found" profile errors
printf '#!/bin/bash\necho "First login script disabled"\nexit 0\n' > /usr/lib/armbian/armbian-firstlogin
sudo chmod +x /usr/lib/armbian/armbian-firstlogin

# disable the Armbian motd sripts
chmod -x /etc/update-motd.d/*

# Clean up apt cache and remove unnecessary files to reduce image size
rm -rf /var/lib/apt/lists/*
apt-get --yes -qq clean

# rm -rf /usr/share/doc
rm -rf /usr/share/locale/

rm -rf /usr/lib/firmware/qcom
