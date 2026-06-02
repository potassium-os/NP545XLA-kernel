#!/bin/bash
# src/build-usb-http-stick.sh — Create a USB-HTTP boot stick disk image
#
# Usage: bash src/build-usb-http-stick.sh
#
# Produces: pxe/usb-http-stick.img (FAT32 ESP with GRUB + HTTP redirect config)
#
# Flash to USB on macOS:  dd if=pxe/usb-http-stick.img of=/dev/diskN bs=4M
# Or use Balena Etcher:   open pxe/usb-http-stick.img
#
# The stick only needs GRUB + grub.cfg. All kernel/initrd/DTB files
# come over HTTP from tsbootkit. One-time setup, never re-flash.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$REPO_ROOT/pxe/usb-http-stick.img"
SERVER_IP="192.168.202.5"
HTTP_PORT="8080"

# 64MB is plenty — just GRUB + a config file
IMG_SIZE_MB=64

# Build GRUB with HTTP support if not already built
if [ ! -f "$REPO_ROOT/pxe/tftp/BOOTAA64.EFI" ]; then
    echo "Building GRUB netboot binary first..."
    bash "$REPO_ROOT/src/build-grub-netboot.sh"
fi

echo "Creating ${IMG_SIZE_MB}MB disk image..."

# Create sparse image
dd if=/dev/zero of="$OUTPUT" bs=1M count=0 seek="$IMG_SIZE_MB" status=none

# Partition: single FAT32 ESP
sgdisk --zap-all "$OUTPUT"
sgdisk --new=1:0:0 --typecode=1:ef00 "$OUTPUT"

# Set up loop device
LOOP=$(losetup --show -fP "$OUTPUT")
PART="${LOOP}p1"
trap 'losetup -d "$LOOP" 2>/dev/null' EXIT

# Wait for partition device to appear
sleep 1
if [ ! -b "$PART" ]; then
    partprobe "$LOOP" 2>/dev/null || true
    sleep 1
fi

# Format FAT32
mkfs.vfat -F 32 "$PART"

# Mount and install
MOUNT=$(mktemp -d)
mount "$PART" "$MOUNT"
trap 'umount "$MOUNT" && rmdir "$MOUNT" && losetup -d "$LOOP" 2>/dev/null' EXIT

mkdir -p "$MOUNT/EFI/BOOT"
cp "$REPO_ROOT/pxe/tftp/BOOTAA64.EFI" "$MOUNT/EFI/BOOT/BOOTAA64.EFI"

# Write grub.cfg that redirects to HTTP server
cat > "$MOUNT/EFI/BOOT/grub.cfg" << GRUBEOF
# USB-HTTP hybrid grub.cfg
# All paths load from the tsbootkit HTTP server.
# To update kernel/DTB: just replace files on the server and reboot.

set server=${SERVER_IP}:${HTTP_PORT}
set prefix=(http)/boot/grub

# Load the full menu from the server
configfile (http)/boot/grub/grub.cfg
GRUBEOF

# Unmount (trap will clean up loop device)
umount "$MOUNT"
rmdir "$MOUNT"
trap 'losetup -d "$LOOP" 2>/dev/null' EXIT
losetup -d "$LOOP"
trap - EXIT

echo ""
echo "Done: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
echo ""
echo "Flash to USB on macOS:"
echo "  diskutil list                         # find the USB disk (e.g. /dev/disk4)"
echo "  diskutil unmountDisk /dev/diskN       # unmount it"
echo "  sudo dd if=$OUTPUT of=/dev/diskN bs=4M"
echo ""
echo "Or use Balena Etcher — just open the .img file."
echo ""
echo "Then start tsbootkit and boot the Samsung from the USB stick."
