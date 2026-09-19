#!/bin/bash

# Exit on errors, print commands, ignore unset variables
set -ex +u

echo "=== Pre-upgrade space ==="
df -h

# Free up space BEFORE upgrading, so the dist-upgrade has room to work
# get rid of snap seeds
rm -rf /var/lib/snapd/seed/snaps/* 2>/dev/null || true
rm -f /var/lib/snapd/seed/seed.yaml 2>/dev/null || true

# Remove packages that waste space and aren't needed in the final image
apt-get purge --yes lxd-installer lxd-agent-loader snapd gdb gcc g++ linux-headers* libgcc*-dev perl-modules* git vim-runtime python3-twisted bluez 2>/dev/null || true

# Remove filesystem/RAID/crypto tools not needed on the rubikpi3 (ext4 root).
# This also shrinks the 26.04 dracut/initramfs by skipping their hooks.
apt-get purge --yes btrfs-progs lvm2 cryptsetup cryptsetup-initramfs mdadm multipath-tools open-iscsi 2>/dev/null || true

# Remove misc services not needed on a headless vision appliance
apt-get purge --yes fwupd apport ubuntu-advantage-tools landscape-common motd-news-config friendly-recovery command-not-found plymouth bolt cups alsa-utils 2>/dev/null || true

# Remove packages that conflict with the 26.04 upgrade
apt-get remove --yes libgstreamer-qcom1.0-0 sosreport 2>/dev/null || true

apt-get autoremove --purge -y
rm -rf /var/lib/apt/lists/*
apt-get clean

rm -rf /usr/share/doc
rm -rf /usr/share/locale/

# Remove firmware for hardware that the rubikpi3 definitely doesn't have
rm -rf /usr/lib/firmware/mrvl
rm -rf /usr/lib/firmware/mellanox
rm -rf /usr/lib/firmware/nvidia
rm -rf /usr/lib/firmware/intel
rm -rf /usr/lib/firmware/amd
rm -rf /usr/lib/firmware/amdgpu
rm -rf /usr/lib/firmware/i915
rm -rf /usr/lib/firmware/radeon

echo "=== Space after pre-cleanup ==="
df -h

# START 26.04 UPGRADE HACK
# Pre-configure grub to avoid interactive prompts in chroot
debconf-set-selections <<< "grub-efi-arm64 grub-efi/install_devices multiselect"
debconf-set-selections <<< "grub-efi-arm64 grub-efi/install_devices_empty boolean true"

# Upgrade from 24.04 to 26.04 via direct dist-upgrade
# More space-efficient than do-release-upgrade (doesn't keep old packages)
sed -i 's/noble/resolute/g' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
sed -i 's/noble/resolute/g' /etc/apt/sources.list 2>/dev/null || true
DEBIAN_FRONTEND=noninteractive apt-get -y update
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-overwrite" -y upgrade || true
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-overwrite" -y dist-upgrade || true
# Remove dragonwing initramfs hook that fails in chroot
rm -f /usr/share/initramfs-tools/hooks/linux-firmware-dragonwing
# Fix dpkg state after upgrade (some pkg configs fail in chroot)
dpkg --configure -a 2>/dev/null || true
apt-get --fix-broken install -y 2>/dev/null || true
# Regenerate grub.cfg now that the kernel/initramfs are actually in place
# (the kernel postinst ran before the initramfs existed, so grub.cfg has no entries)
update-grub 2>/dev/null || true
apt autoremove --purge -y
# Remove old 24.04 kernels, keep the new 26.04 one(s)
dpkg -l | awk '/^ii.*linux-(image|headers|modules)/{print $2}' | sort -V | head -n -1 | xargs apt-get purge --yes 2>/dev/null || true
apt-get clean

# Ensure Hexagon DSP firmware is included and enabled, required for OD
cat > /etc/initramfs-tools/hooks/qcom-dsp-firmware << 'EOF_DSP_HOOK'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in prereqs) prereqs; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions
for fw in qcom/qcs6490/cdsp.mbn qcom/qcs6490/Thundercomm/RubikPi3/adsp.mbn; do
    add_firmware "$fw" || echo "W: qcom-dsp-firmware: $fw not found, DSPs will not boot" >&2
done
EOF_DSP_HOOK
chmod 755 /etc/initramfs-tools/hooks/qcom-dsp-firmware

update-initramfs -u -k all
for fw in qcom/qcs6490/cdsp.mbn qcom/qcs6490/Thundercomm/RubikPi3/adsp.mbn; do
    lsinitramfs /boot/initrd.img | grep -q "firmware/.*${fw}$" \
        || { echo "ERROR: ${fw} missing from initramfs" >&2; exit 1; }
done
# END 26.04 UPGRADE HACK

echo "=== Space after upgrade ==="
df -h

cd /tmp/build
echo '=== Current directory: $(pwd) ==='
echo '=== Files in current directory: ==='
ls -la

# This fixes log spam from iris_vpu AKA msm_vidc
# See: https://github.com/rubikpi-ai/linux-debian/blob/0f0155ba6d6057a6a86162597f48c24e1a54d1a1/ubuntu/qcom/video/vidc/inc/msm_vidc_debug.h#L101
# and https://github.com/rubikpi-ai/linux-debian/blob/0f0155ba6d6057a6a86162597f48c24e1a54d1a1/ubuntu/qcom/video/vidc/src/msm_vidc_debug.c#L25
echo "options iris_vpu msm_fw_debug=0x18" > /etc/modprobe.d/iris_vpu.conf

ln -sf libOpenCL.so.1 /usr/lib/aarch64-linux-gnu/libOpenCL.so # Fix for snpe-tools

# silence log spam from dpkg
cat > /etc/apt/apt.conf.d/99dpkg.conf << EOF_DPKG
Dpkg::Progress-Fancy "0";
APT::Color "0";
Dpkg::Use-Pty "0";
EOF_DPKG


# Make sure all the sources are available for apt
cat > /etc/apt/sources.list.d/ubuntu.sources << EOF_UBUNTU_SOURCES
Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports
Suites: resolute resolute-updates resolute-backports
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF_UBUNTU_SOURCES

# diff /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources

apt-get -q update

# Add the GPG key for the RUBIK Pi PPA
wget -qO - https://thundercomm.s3.dualstack.ap-northeast-1.amazonaws.com/uploads/web/rubik-pi-3/tools/key.asc | tee /etc/apt/trusted.gpg.d/rubikpi3.asc

# Remove extra packages to make space
echo "Space available before purging things"
df -h

apt-get autoremove --yes

rm -rf /var/lib/apt/lists/*
apt-get clean

rm -rf /usr/share/doc
rm -rf /usr/share/locale/

echo "Space available after purging things"
df -h

# Run normal photon installer
chmod +x ./install.sh
./install.sh --control-networking=yes --arch=aarch64 --version="$1"

# Install packages from the RUBIK Pi PPA, we skip calling apt-get update here because install.sh already does that
# libqnn1, libsnpe1, and qcom-adreno1 are for OD
apt-get -y install libqnn1 libsnpe1 qcom-adreno1 device-tree-compiler

# Download packages for installing NPU metrics daemon
mkdir metrics-daemon

DEBPOOL=https://deb.debian.org/debian/pool/contrib

curl --output-dir metrics-daemon -O "${DEBPOOL}/f/fastrpc/libfastrpc1_1.0.2-2_arm64.deb"
curl --output-dir metrics-daemon -O "${DEBPOOL}/libq/libqcnpuperf/libqcnpuperf1_1.0.0-1_arm64.deb"
curl -L --output-dir metrics-daemon -O "https://github.com/samfreund/qcnpuperfmon/releases/download/dev/qcnpuperfd_1.0.0-1_arm64.deb"

dpkg -i --force-overwrite metrics-daemon/*.deb
rm -rf metrics-daemon

# Enable ssh
systemctl enable ssh

# modify photonvision.service to run on A78 cores
sed -i 's/# AllowedCPUs=4-7/AllowedCPUs=4-7/g' /lib/systemd/system/photonvision.service
cp -f /lib/systemd/system/photonvision.service /etc/systemd/system/photonvision.service
chmod 644 /etc/systemd/system/photonvision.service
cat /etc/systemd/system/photonvision.service

# networkd isn't being used, this causes an unnecessary delay
systemctl disable systemd-networkd-wait-online.service

# set the hostname during cloud-init and disable cloud-init after first boot
cat >> /var/lib/cloud/seed/nocloud/user-data << EOFUSERDATA

hostname: photonvision

runcmd:
- nmcli radio all off
- touch /etc/cloud/cloud-init.disabled
EOFUSERDATA

# This udev rule is a workaround for a quirk in the Rubik Pi 3's USB controller that causes the camera to be assigned a different path on each boot, which breaks PhotonVision's ability to find it. This rule creates a consistent symlink for the camera and removes the old ones.
cat >> /etc/udev/rules.d/67-camera-path-fix.rules << 'EOFUDEV'
   SUBSYSTEM=="video4linux", ENV{ID_PATH}=="platform-xhci-hcd.0.auto-usb-0:1:1.0", \
  ENV{ID_PATH}="platform-xhci-hcd.1.auto-usb-0:1:1.0", \
  ENV{ID_PATH_TAG}="platform-xhci-hcd_1_auto-usb-0_1_1_0", \
  ENV{ID_PATH_WITH_USB_REVISION}="platform-xhci-hcd.1.auto-usbv2-0:1:1.0", \
  SYMLINK+="v4l/by-path/platform-xhci-hcd.1.auto-usb-0:1:1.0-video-index$attr{index}", \
  RUN+="/bin/rm -f /dev/v4l/by-path/platform-xhci-hcd.0.auto-usb-0:1:1.0-video-index$attr{index} /dev/v4l/by-path/platform-xhci-hcd.0.auto-usbv2-0:1:1.0-video-index$attr{index}"
EOFUDEV

# Override the automatic fan control and set it to run continuously at full speed
# Instructions provided by Rami

# 1. Disable the thermal service
systemctl disable oem-tangshan-rubikpi3-thermal.service

# 2. Create the fan helper script
cat > /usr/local/sbin/rubik-fan-max.sh << 'EOF_MAX_FAN'
#!/bin/sh
hwmon_dir=$(readlink -f /sys/devices/platform/pwm-fan/hwmon/hwmon*)
echo 0 > "$hwmon_dir/pwm1_enable"
echo 255 > "$hwmon_dir/pwm1"
EOF_MAX_FAN

chmod +x /usr/local/sbin/rubik-fan-max.sh

# 3. Add a oneshot systemd unit
cat > /etc/systemd/system/rubik-fan-max.service << EOF_FAN_SERVICE
[Unit]
Description=Force Rubik Pi fan to full speed
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/rubik-fan-max.sh

[Install]
WantedBy=multi-user.target
EOF_FAN_SERVICE

# 4. Enable the new service
systemctl enable rubik-fan-max.service

echo "Space available before final cleanup"
df -h

rm -rf /var/lib/apt/lists/*
apt-get clean
rm -rf /usr/share/doc
rm -rf /usr/share/locale/

# remove firmware that (probably) isn't needed
rm -rf /usr/lib/firmware/mrvl
rm -rf /usr/lib/firmware/mellanox
rm -rf /usr/lib/firmware/nvidia
rm -rf /usr/lib/firmware/intel

echo "Space available after final cleanup"
df -h
