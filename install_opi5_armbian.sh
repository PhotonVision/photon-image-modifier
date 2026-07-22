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

# copy configuration directives for first boot
cp -f ./armbian/.not_logged_in_yet /root/

# modify photonvision.service to enable big cores
sed -i 's/# AllowedCPUs=4-7/AllowedCPUs=4-7/g' /lib/systemd/system/photonvision.service
cp -f /lib/systemd/system/photonvision.service /etc/systemd/system/photonvision.service
chmod 644 /etc/systemd/system/photonvision.service
cat /etc/systemd/system/photonvision.service

# diagnose slow boot on Armbian images
sed -i s/verbosity=1/verbosity=7/g /boot/armbianEnv.txt
sed -i 's/extraargs=/&initcall_debug ignore_loglevel cryptomgr.notests=1 nokprobes initcall_blacklist=init_kprobe_trace,crypto_kdf108_init,init_blk_tracer trace_buf_size=1 /' /boot/armbianEnv.txt

# networkd isn't being used, this causes an unnecessary delay
# systemctl disable systemd-networkd-wait-online.service

# PhotonVision server is managing the network, so it doesn't need to wait for online
systemctl disable NetworkManager-wait-online.service

# the bluetooth service isn't needed and causes problems with cloud-init
# the chip has different names on different boards. Examples are:
#   OrangePi5: ap6275p-bluetooth.service
#   OrangePi5pro: ap6256s-bluetooth.service
#   OrangePi5b: ap6275p-bluetooth.service
#   OrangePi5max: ap6611s-bluetooth.service
# instead of keeping a catalog of these services, find them based on a pattern and mask them
btservices=$(systemctl list-unit-files *bluetooth.service | tail -n +2 | head -n -1 | awk '{print $1}')
for btservice in $btservices; do
    echo "Masking: $btservice"
    systemctl mask "$btservice"
done

# disable radios on first boot
cat > /root/provisioning.sh << EOF
#!/bin/bash
hostnamectl set-hostname photonvision
# disable radios on first boot
echo "Running provisioning script" >> /root/provisioning.log
nmcli radio all off
EOF
chmod +x /root/provisioning.sh

# set the hostname
echo "photonvision" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1    photonvision/g" /etc/hosts

rm -rf /var/lib/apt/lists/*
apt-get --yes -qq clean

# rm -rf /usr/share/doc
rm -rf /usr/share/locale/

rm -rf /usr/lib/firmware/qcom
