#!/bin/bash

# Run standard photon installer
chmod +x ./install.sh
./install.sh --install-nm=yes --arch=aarch64

# Do additional tasks that are common across all images, 
# but not suitable for inclusion in install.sh

# Limit the maximum length of systemd-journald logs
cat > /etc/systemd/journald.conf.d/60-limit-log-size.conf <<EOF
# Added by Photonvision to keep the logs to a reasonable size
[Journal]
SystemMaxUse=100M
EOF

# Add a helpful message to the logon screen
cp -f ./files/issue /etc/issue
cp -f /etc/issue /etc/issue.net
sed -i 's/#Banner none/Banner \/etc\/issue.net/g' /etc/ssh/sshd_config
