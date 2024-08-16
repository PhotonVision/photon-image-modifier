
# Create pi/raspberry login
if id "$1" >/dev/null 2>&1; then
    echo 'user found'
else
    echo "creating pi user"
    useradd pi -m -b /home -s /bin/bash
    usermod -a -G sudo pi
    echo 'pi ALL=(ALL) NOPASSWD: ALL' | tee -a /etc/sudoers.d/010_pi-nopasswd >/dev/null
    chmod 0440 /etc/sudoers.d/010_pi-nopasswd
fi
echo "pi:raspberry" | chpasswd

apt-get update --quiet

before=$(df --output=used / | tail -n1)
# clean up stuff
echo 'Purging snaps'
# get rid of snaps
rm -rf /var/lib/snapd/seed/snaps/*
rm -f /var/lib/snapd/seed/seed.yaml
apt-get purge --yes --quiet lxd-installer lxd-agent-loader
apt-get purge --yes --quiet snapd

# remove bluetooth daemon
apt-get purge --yes --quiet bluez

apt-get --yes --quiet autoremove

after=$(df --output=used / | tail -n1)
freed=$(( before - after ))

echo "Freed up $freed KiB"

# run Photonvision install script
wget https://git.io/JJrEP -O install.sh
chmod +x install.sh

sed -i 's/# AllowedCPUs=4-7/AllowedCPUs=0-7/g' install.sh

./install.sh -m -q
rm install.sh

echo "Installing additional things"

apt-get install --yes --quiet network-manager net-tools libatomic1

# let netplan create the config during cloud-init
rm -f /etc/netplan/00-default-nm-renderer.yaml

# set NetworkManager as the renderer in cloud-init
cp -f ./OPi5_CIDATA/network-config /boot/network-config

# add customized user-data file for cloud-init
cp -f ./OPi5_CIDATA/user-data /boot/user-data

# tell NetworkManager not to wait for the carrier on ethernet, which can delay boot
# when the coprocessor isn't connected to the ethernet
# cat > /etc/NetworkManager/conf.d/50-ignore-carrier.conf <<EOF
# [main]
# ignore-carrier=*
# EOF

# modify photonvision.service to wait for the network before starting
# this helps ensure that photonvision detects the network the first time it starts
# but it may cause a startup delay if the coprocessor isn't connected to a network
sed -i '/Description/aAfter=network-online.target' /etc/systemd/system/photonvision.service
cat /etc/systemd/system/photonvision.service

# networkd isn't being used, this causes an unnecessary delay
systemctl disable systemd-networkd-wait-online.service

# the bluetooth service isn't needed and causes a delay at boot
systemctl disable ap6275p-bluetooth.service

apt-get install --yes --quiet libc6 libstdc++6

if [ $(cat /etc/lsb-release | grep -c "24.04") -gt 0 ]; then
    # add jammy to apt sources 
    echo "Adding jammy to list of apt sources"
    add-apt-repository -y -S 'deb http://ports.ubuntu.com/ubuntu-ports jammy main universe'
fi

apt-get --quiet update

# mrcal stuff
apt-get install --yes --quiet libcholmod3 liblapack3 libsuitesparseconfig5


rm -rf /var/lib/apt/lists/*
apt-get --yes --quiet clean

rm -rf /usr/share/doc
rm -rf /usr/share/locale/
