#!/bin/bash
set -exuo pipefail

rootdir="./rootfs"
rootdir="$(realpath ${rootdir})"
echo "Root directory will be: ${rootdir}"

url=$1
install_script=$2
additional_mb=$3
rootpartition=$4

if [[ $# -ge 5 ]]; then
    bootpartition=$5
    if [[ "x$rootpartion" = "x$bootpartition" ]]; then
        echo "Boot partition cannot be equal to root partition"
        exit 1
    fi
else
    bootpartition=
fi

image="base_image.img"

####
# Download the image
####
wget -nv -O ${image}.xz "${url}"
xz -T0 -d ${image}.xz

####
# Prepare and mount the image
####

if [[ ${additional_mb} -gt 0 ]]; then
    dd if=/dev/zero bs=1M count=${additional_mb} >> ${image}
fi

export loopdev=$(losetup --find --show --partscan ${image})
# echo "loopdev=${loopdev}" >> $GITHUB_OUTPUT

part_type=$(blkid -o value -s PTTYPE "${loopdev}")
echo "Image is using ${part_type} partition table"

if [[ ${additional_mb} -gt 0 ]]; then
    if [[ "${part_type}" == "gpt" ]]; then
        sgdisk -e "${loopdev}"
    fi
    parted --script "${loopdev}" resizepart ${rootpartition} 100%
    e2fsck -p -f "${loopdev}p${rootpartition}"
    resize2fs "${loopdev}p${rootpartition}"
    echo "Finished resizing disk image."
fi

sync

echo "Partitions in the mounted image:"
lsblk "${loopdev}"

if [[ -n "$bootpartition" ]]; then
    bootdev="${loopdev}p${bootpartition}"
else
    bootdev=
fi
rootdev="${loopdev}p${rootpartition}"

mkdir --parents ${rootdir}
# echo "rootdir=${rootdir}" >> "$GITHUB_OUTPUT"
mount "${rootdev}" "${rootdir}"
if [[ -n "$bootdev" ]]; then
    mkdir --parents "${rootdir}/boot"
    mount "${bootdev}" "${rootdir}/boot"
fi

# Set up the environment
mount -t proc /proc "${rootdir}/proc"
mount -t sysfs /sys "${rootdir}/sys"
mount --rbind /dev "${rootdir}/dev"

# Temporarily replace resolv.conf for networking
mv -v "${rootdir}/etc/resolv.conf" "${rootdir}/etc/resolv.conf.bak"
cp -v /etc/resolv.conf "${rootdir}/etc/resolv.conf"

####
# Modify the image in chroot
####
chrootscriptdir=/tmp/build
scriptdir=${rootdir}${chrootscriptdir}
mkdir --parents "${scriptdir}"
mount --bind "$(pwd)" "${scriptdir}"

cat >> "${scriptdir}/commands.sh" << EOF
set -ex
export DEBIAN_FRONTEND=noninteractive
cd "${chrootscriptdir}"
echo "Running ${install_script}"
chmod +x "${install_script}"
"./${install_script}"
echo "Running install_common.sh"
chmod +x "./install_common.sh"
"./install_common.sh"
EOF

cat -n "${scriptdir}/commands.sh"
chmod +x "${scriptdir}/commands.sh"

sudo -E chroot "${rootdir}" /bin/bash -c "${chrootscriptdir}/commands.sh"

####
# Clean up and shrink image
####

if [[ -e "${rootdir}/etc/resolv.conf.bak" ]]; then
    mv "${rootdir}/etc/resolv.conf.bak" "${rootdir}/etc/resolv.conf"
fi

echo "Zero filling empty space"
if mountpoint "${rootdir}/boot"; then
    (cat /dev/zero > "${rootdir}/boot/zeros" 2>/dev/null || true); sync; rm "${rootdir}/boot/zeros";
fi

(cat /dev/zero > "${rootdir}/zeros" 2>/dev/null || true); sync; rm "${rootdir}/zeros";

umount --recursive "${rootdir}"

echo "Resizing root filesystem to minimal size."
e2fsck -v -f -p -E discard "${rootdev}"
resize2fs -M "${rootdev}"
rootfs_blocksize=$(tune2fs -l ${rootdev} | grep "^Block size" | awk '{print $NF}')
rootfs_blockcount=$(tune2fs -l ${rootdev} | grep "^Block count" | awk '{print $NF}')

echo "Resizing rootfs partition."
rootfs_partstart=$(parted -m --script "${loopdev}" unit B print | grep "^${rootpartition}:" | awk -F ":" '{print $2}' | tr -d 'B')
rootfs_partsize=$((${rootfs_blockcount} * ${rootfs_blocksize}))
rootfs_partend=$((${rootfs_partstart} + ${rootfs_partsize} - 1))
rootfs_partoldend=$(parted -m --script "${loopdev}" unit B print | grep "^${rootpartition}:" | awk -F ":" '{print $3}' | tr -d 'B')
if [ "$rootfs_partoldend" -gt "$rootfs_partend" ]; then
    echo y | parted ---pretend-input-tty "${loopdev}" unit B resizepart "${rootpartition}" "${rootfs_partend}"
else
    echo "Rootfs partition not resized as it was not shrunk"
fi

free_space=$(parted -m --script "${loopdev}" unit B print free | tail -1)
if [[ "${free_space}" =~ "free" ]]; then
    initial_image_size=$(stat -L --printf="%s" "${image}")
    image_size=$(echo "${free_space}" | awk -F ":" '{print $2}' | tr -d 'B')
    if [[ "${part_type}" == "gpt" ]]; then
        # for GPT partition table, leave space at the end for the secondary GPT
        # it requires 33 sectors, which is 16896 bytes
        image_size=$((image_size + 16896))
    fi
    echo "Shrinking image from ${initial_image_size} to ${image_size} bytes."
    truncate -s "${image_size}" "${image}"
    if [[ "${part_type}" == "gpt" ]]; then
        # use sgdisk to fix the secondary GPT after truncation
        sgdisk -e "${image}"
    fi
fi

losetup --detach "${loopdev}"

echo "image=${image}" >> "$GITHUB_OUTPUT"
