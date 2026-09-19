#!/bin/bash
NETPLAN_DIR="/etc/netplan"
NETPLAN_FILE="${NETPLAN_DIR}/00-custom-macs.yaml"
NM_CONF_DIR="/etc/NetworkManager/conf.d"
NM_CONF_FILE="${NM_CONF_DIR}/10-mac-spoof.conf"

# Check if we already created the Netplan layout to prevent duplicate execution
if [ -f "$NETPLAN_FILE" ]; then
    exit 0
fi

# 1. Extract the unique hardware serial number
CPU_SERIAL=$(grep -i "serial" /proc/cpuinfo | awk '{print $3}')
if [ -z "$CPU_SERIAL" ]; then
    CPU_SERIAL=$(cat /proc/sys/kernel/random/uuid)
fi

# 2. Slice the hash correctly for a standard 6-byte MAC address
HASH_BASE=$(echo -n "$CPU_SERIAL" | md5sum | cut -c1-6 | sed 's/../&:/g')

BYTE5_DEC=$(( 16#$(echo -n "$CPU_SERIAL" | md5sum | cut -c7-8) ))
BYTE6_DEC=$(( 16#$(echo -n "$CPU_SERIAL" | md5sum | cut -c9-10) ))

P1_B5=$(printf "%02X" $BYTE5_DEC)
P1_B6=$(printf "%02X" $BYTE6_DEC)

P2_B5=$(printf "%02X" $BYTE5_DEC)
P2_B6=$(printf "%02X" $(( (BYTE6_DEC + 1) % 256 )))

MAC1="02:${HASH_BASE}${P1_B5}:${P1_B6}"
MAC2="02:${HASH_BASE}${P2_B5}:${P2_B6}"

# 3. Dynamic Hardware Discovery (Scans physical wired interfaces)
ETHERNET_INTERFACES=($(ls /sys/class/net | grep -E '^(eth|end)[0-9]' | sort))

# 4. REMOVE ARMBIAN DEFAULTS (Crucial step to prevent rule overrides)
# Wipes out '10-dhcp-all-interfaces.yaml' or similar default templates in the directory
rm -f ${NETPLAN_DIR}/10-dhcp-all-interfaces.yaml
# rm -f ${NETPLAN_DIR}/01-*.yaml # Wipe fallback profiles if present

# 5. Generate the Netplan YAML Structure and add a NetworkManager rule to
# honor the macaddr for new connections
if [ ${#ETHERNET_INTERFACES[@]} -gt 0 ]; then
    PORT1="${ETHERNET_INTERFACES}"

    cat << EOF > "$NETPLAN_FILE"
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ${PORT1}:
      match:
        name: "${PORT1}"
      macaddress: "${MAC1}"
      dhcp4: true
      dhcp6: true
EOF

    mkdir -p "$NM_CONF_DIR"
    cat << EOF > "$NM_CONF_FILE"
[connection-${PORT1}]
    match-device=interface-name:${PORT1}
    ethernet.cloned-mac-address=${MAC1}
EOF

    # If the board is an Orange Pi 5 Plus, append the secondary interface layout
    if [ ${#ETHERNET_INTERFACES[@]} -gt 1 ]; then
        PORT2="${ETHERNET_INTERFACES}"
        cat << EOF >> "$NETPLAN_FILE"
    ${PORT2}:
      match:
        name: "${PORT2}"
      macaddress: "${MAC2}"
      dhcp4: true
      dhcp6: true
EOF

        cat << EOF >> "$NM_CONF_FILE"
[connection-${PORT2}]
    match-device=interface-name:${PORT2}
    ethernet.cloned-mac-address=${MAC2}
EOF

    fi
fi

# Ensure correct file permissions for Netplan configurations
chmod 600 "$NETPLAN_FILE"

# Apply Netplan changes instantly
if command -v netplan &> /dev/null; then
    netplan apply
fi
