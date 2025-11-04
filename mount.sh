base_image=$1
scriptOne=$2
scriptTwo=$3
set -exv

# Install required packages
sudo apt-get update
sudo apt-get install -y wget xz-utils
# If base_image ends with .yaml, treat it as a manifest and skip download
if [[ "$base_image" == *.yaml ]]; then
 
  # We're building a rubik image
  rubik=true
  # Download and process manifest
  wget -O manifest.yaml "${base_image}"

  echo "=== Manifest contents ==="
  cat manifest.yaml
  echo "========================="

  # Process each component using awk to extract URL and SHA256
  awk '/url:/ {
      sub(/.*url:[[:space:]]*/,"",$0);
      url=$0
       }
       /sha256sum:/ {
      sub(/.*sha256sum:[[:space:]]*/,"",$0);
      print url, $0
       }' manifest.yaml | while read -r url sha; do
    filename=$(basename "$url")
    echo "Downloading: $filename from $url"
    wget -nv -O "$filename" "$url"
    echo "$sha  $filename" | sha256sum -c -
  done

  echo "=== Downloaded files ==="
  ls -lh
  echo "========================"
elif [[ "$base_image" == *.tar.xz ]]; then
  # We're building a rubik image
  rubik=true
  # Directly download the tar.xz file
  wget -nv -O base_image.tar.xz "${base_image}"
  tar -I 'xz -T0' -xf base_image.tar.xz
elif [[ "$base_image" == *.img.xz ]]; then
  # We're building a standard image
  rubik=false
  wget -nv -O base_image.img.xz "${base_image}"
  xz -T0 -d base_image.img.xz
else
  echo "Error: base_image must be a .yaml manifest, .tar.xz, or .img.xz file"
  exit 1
fi
# Find the rootfs image - look for the largest .img.xz or .img file
ROOTFS_IMG=""

# If not found, use the largest .img.xz file
ROOTFS_IMG="${ROOTFS_IMG:-$(find . -type f \( -name '*.img.xz' -o -name '*.img' \) -exec ls -s {} + 2>/dev/null | sort -rn | head -n1 | awk '{print $2}')}"
[ -n "$ROOTFS_IMG" ] && echo "Using largest .img.xz or .img file as rootfs: $ROOTFS_IMG"

if [ -z "$ROOTFS_IMG" ] || [ ! -f "$ROOTFS_IMG" ]; then
  echo "Error: Could not find a suitable rootfs image file"
  echo "Available files:"
  ls -la
  exit 1
fi

# Only extract if ROOTFS_IMG is an .img.xz file
if [[ "$ROOTFS_IMG" == *.img.xz ]]; then
  ROOTFS_IMG_XZ="$ROOTFS_IMG"
  ROOTFS_IMG="${ROOTFS_IMG_XZ%.xz}"
  echo "Extracting rootfs image: $ROOTFS_IMG_XZ"
  xz -T0 -d "$ROOTFS_IMG_XZ"
fi

if [ ! -f "$ROOTFS_IMG" ]; then
  echo "Error: Root filesystem image not found: $ROOTFS_IMG"
  echo "Available files:"
  ls -la
  exit 1
fi

# Make mount point
mkdir -p ./rootfs

echo "Using rootfs image: $ROOTFS_IMG"
if [ "$rubik" == true ]; then
  echo "Building Rubik image"

  # This uses a fixed offset for Ubuntu preinstalled server images
  echo "=== Mounting rootfs with fixed offset (rpiimager method) ==="

  # Calculate offset: 4096 bytes/sector * 139008 sectors = 569,376,768 bytes
  OFFSET=$((4096*139008))
  echo "Using offset: $OFFSET bytes (sector 139008)"

  sudo mount -o rw,loop,offset=$OFFSET "$ROOTFS_IMG" ./rootfs

  if [ $? -ne 0 ]; then
    echo "Error: Failed to mount image with fixed offset"
    exit 1
  fi
else
  echo "Building Standard image"

  # Get partition info using parted
  PART_INFO=$(parted -s "$ROOTFS_IMG" unit B print)

  # Extract start byte of the root partition (assuming it's the second partition)
  START_BYTE=$(echo "$PART_INFO" | awk '/^ 2/ {gsub("B","",$2); print $2}')

  if [ -z "$START_BYTE" ]; then
    echo "Error: Could not determine start byte of root partition"
    exit 1
  fi

  OFFSET=$START_BYTE
  echo "Using offset: $OFFSET bytes"

  sudo mount -o rw,loop,offset=$OFFSET "$ROOTFS_IMG" ./rootfs

  if [ $? -ne 0 ]; then
    echo "Error: Failed to mount image with calculated offset"
    exit 1
  fi

fi 

echo "=== Mount successful ==="
ls -la ./rootfs | head -20

# Check if this is a Canonical or Modified image (from rpiimager logic)
if [ -f "rootfs/etc/ImgType" ]; then
  cp rootfs/etc/ImgType ImgType
else
  echo "Canonical" > ImgType
fi
read ImgType < ImgType
echo "Image type: $ImgType"

# Expand image if it's a Canonical image (first time modification)
if [ "$ImgType" == "Canonical" ]; then
  echo "=== Marking image as CustomIDE ==="
  sudo chroot rootfs /bin/bash -c "
    touch /etc/ImgType
    echo 'CustomIDE' > /etc/ImgType
  "

  echo "=== Unmounting for expansion ==="
  sudo umount ./rootfs

  if [ "$rubik" = true ]; then
    # Expand the image by 2GB (reduced from 10GB to fit GitHub Actions disk space)
    echo "=== Expanding image by 2GB ==="
    dd if=/dev/zero bs=1M count=2048 >> "$ROOTFS_IMG"
  else
    # Expand the image by 1GB
    echo "=== Expanding image by 1GB ==="
    dd if=/dev/zero bs=1M count=1024 >> "$ROOTFS_IMG"
  fi

  if [ "$rubik" != true ]; then
    loopdev=$(sudo losetup --find --show --partscan ${ROOTFS_IMG})
    echo "Created loopback device ${loopdev}"

    if ( (sudo parted --script $loopdev print || false) | grep "Partition Table: gpt" > /dev/null); then
      sudo sgdisk -e "${loopdev}"
    fi
    sudo parted --script "${loopdev}" resizepart 2 100%
    sudo e2fsck -p -f "${loopdev}p2"
    sudo resize2fs "${loopdev}p2"
    echo "Finished resizing disk image."
    # Detach loop device
    sudo losetup -d "${loopdev}"

  fi

  # Remount after expansion
  echo "=== Remounting after expansion ==="
  sudo mount -o rw,loop,offset=$OFFSET "$ROOTFS_IMG" ./rootfs

  if [ "$rubik" != true ]; then
    # Resize the filesystem to fill the partition
    echo "=== Resizing filesystem ==="
    sudo resize2fs "$(losetup -j "$ROOTFS_IMG" | cut -d: -f1 | head -n1)"
  fi
elif [ "$ImgType" == "CustomIDE" ]; then
  echo "Image already customized, no expansion needed"
fi

rm -f ImgType

echo "=== Filesystem ready ==="

# Setup chroot environment
sudo mount -t proc proc rootfs/proc
sudo mount -t sysfs sysfs rootfs/sys
sudo mount -t tmpfs tmpfs rootfs/run
sudo mount --bind /dev rootfs/dev

# Setup DNS resolution in chroot
echo "=== Setting up DNS in chroot ==="
sudo rm -f rootfs/etc/resolv.conf
sudo cp /etc/resolv.conf rootfs/etc/resolv.conf
sudo cp /etc/hosts rootfs/etc/hosts

# Mount and bind the current directory into /tmp/build in chroot
sudo mkdir -p rootfs/tmp/build/
sudo mount --bind "$(pwd)" rootfs/tmp/build/

echo "=== Checking for sudo in chroot and running script ==="
sudo chroot rootfs /bin/bash -c "
  set -exv
  export DEBIAN_FRONTEND=noninteractive
  if ! command -v sudo &> /dev/null; then
    echo 'sudo not found, installing...'
    apt-get update && apt-get install -y sudo
  else
    echo 'sudo is already installed'
  fi

  echo '=== Running installation scripts in chroot ==='

  echo '=== Making script executable ==='
  chmod +x /tmp/build/${scriptOne}
  echo '=== Running ${scriptOne} ==='
  ./tmp/build/${scriptOne}

  if [ -f "/tmp/build/${scriptTwo}" ]; then
    echo '=== Making second script executable ==='
    chmod +x /tmp/build/${scriptTwo}
    echo '=== Running ${scriptTwo} ==='
    ./tmp/build/${scriptTwo} $(printf '%q ' "${@:4}")
  else
    echo 'No second script provided, skipping.'
  fi
"

# Cleanup mounts
sudo umount rootfs/dev || true
sudo umount rootfs/run || true
sudo umount rootfs/sys || true
sudo umount rootfs/proc || true
sudo umount rootfs/tmp/build/ || true
sudo umount rootfs || true

# Find and detach any remaining loop devices pointing to our image
sudo losetup -j "$ROOTFS_IMG" | cut -d: -f1 | xargs -r sudo losetup -d

# Ensure all filesystem operations are complete
sync
sleep 3

if [ "$rubik" == true ]; then
  # Assembly process for remaining files
  mkdir -p photonvision_rubikpi3
  # Extract .tar.gz archive(s) directly into photonvision_rubikpi3 if they exist
  if ls *.tar.gz 1>/dev/null 2>&1; then
    tar -xzf *.tar.gz -C photonvision_rubikpi3
  fi
  # Move all files (rawprogram, dtb, img) into photonvision_rubikpi3
  mv rawprogram*.xml photonvision_rubikpi3/ 2>/dev/null || true
  mv dtb.bin photonvision_rubikpi3/ 2>/dev/null || true
  mv *.img photonvision_rubikpi3/ 2>/dev/null || true

  # Flatten directory structure - move all files from subdirectories to photonvision_rubikpi3 root
  find photonvision_rubikpi3 -mindepth 2 -type f -exec mv {} photonvision_rubikpi3/ \;
  # Remove empty subdirectories
  find photonvision_rubikpi3 -mindepth 1 -type d -empty -delete

  # Export the final directory as an environment variable for GitHub Actions
  FINAL_IMAGE="photonvision_rubikpi3"

else
  # Export the final image as an enivronment variable
  FINAL_IMAGE="$ROOTFS_IMG"
fi

if [ -n "$GITHUB_ENV" ]; then
  printf '%s\n' "FINAL_IMAGE=${FINAL_IMAGE}" >> "$GITHUB_ENV"
  echo "Wrote FINAL_IMAGE to GITHUB_ENV"
else
  export FINAL_IMAGE="$FINAL_IMAGE"
  echo "FINAL_IMAGE exported in current shell"
fi
