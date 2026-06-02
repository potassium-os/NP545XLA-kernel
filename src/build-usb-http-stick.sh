#!/bin/bash
# src/build-usb-http-stick.sh — Create a USB-HTTP boot stick as an El Torito ISO
#
# Usage: bash src/build-usb-http-stick.sh
#
# Produces: pxe/usb-http-stick.iso (El Torito EFI boot ISO)
#
# The Samsung UEFI only boots ISOs with El Torito EFI boot entries — it ignores
# raw GPT ESP partitions on USB drives. So we produce a minimal ISO instead of
# a raw .img, using the same xorriso + appended ESP technique as build-iso.sh.
#
# The ISO only contains GRUB + a grub.cfg that redirects to the HTTP server.
# All kernel/initrd/DTB files come over HTTP from tsbootkit.
# One-time flash, never re-burn.
#
# Flash to USB on macOS:  dd if=pxe/usb-http-stick.iso of=/dev/diskN bs=4M
# Or use Balena Etcher:   open pxe/usb-http-stick.iso

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/usb-http-stick"
ISO_OUT="$REPO_ROOT/pxe/usb-http-stick.iso"
SERVER_IP="192.168.202.5"
HTTP_PORT="8080"

# Build GRUB with HTTP support if not already built
if [ ! -f "$REPO_ROOT/pxe/tftp/BOOTAA64.EFI" ]; then
    echo "Building GRUB netboot binary first..."
    bash "$REPO_ROOT/src/build-grub-netboot.sh"
fi

echo "Building USB-HTTP boot ISO..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# --- Step 1: Prepare ISO filesystem tree ---
ISO_ROOT="$BUILD_DIR/iso-staging"
mkdir -p "$ISO_ROOT/EFI/BOOT"

# Copy the GRUB binary (already has net/tftp/http/efinet modules)
cp "$REPO_ROOT/pxe/tftp/BOOTAA64.EFI" "$ISO_ROOT/EFI/BOOT/BOOTAA64.EFI"

# Write grub.cfg that redirects to HTTP server
cat > "$ISO_ROOT/EFI/BOOT/grub.cfg" << GRUBEOF
# USB-HTTP hybrid grub.cfg
# All paths load from the tsbootkit HTTP server.
# To update kernel/DTB: just replace files on the server and reboot.

set server=${SERVER_IP}:${HTTP_PORT}
set prefix=(http)/boot/grub

# Load the full menu from the server
configfile (http)/boot/grub/grub.cfg
GRUBEOF

# Also put grub.cfg at /boot/grub/ for GRUB's default prefix fallback
mkdir -p "$ISO_ROOT/boot/grub"
cp "$ISO_ROOT/EFI/BOOT/grub.cfg" "$ISO_ROOT/boot/grub/grub.cfg"

# --- Step 2: Build FAT ESP partition image ---
# The Samsung UEFI needs an appended GPT ESP partition to find the EFI binary.
# The El Torito entry points to the same binary inside the ISO9660 filesystem.
echo "Building ESP partition image..."

ESP_IMG="$BUILD_DIR/esp.img"
ESP_SIZE_MB=8

dd if=/dev/zero of="$ESP_IMG" bs=1M count="$ESP_SIZE_MB" status=none
mkfs.vfat -F 32 -n EFI "$ESP_IMG"

MNT=$(mktemp -d)
mount "$ESP_IMG" "$MNT"
mkdir -p "$MNT/EFI/BOOT"
cp "$REPO_ROOT/pxe/tftp/BOOTAA64.EFI" "$MNT/EFI/BOOT/BOOTAA64.EFI"
umount "$MNT"
rmdir "$MNT"

# --- Step 3: Generate El Torito EFI boot ISO ---
echo "Generating ISO..."

xorriso -as mkisofs \
    -r -J \
    -V "PXE-HTTP" \
    -o "$ISO_OUT" \
    --protective-msdos-label \
    -c /boot/boot.cat \
    -e /EFI/BOOT/BOOTAA64.EFI \
    -no-emul-boot \
    -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b "$ESP_IMG" \
    -appended_part_as_gpt \
    --mbr-force-bootable \
    "$ISO_ROOT"

# --- Step 4: Cleanup ---
rm -rf "$BUILD_DIR"

ISO_SIZE=$(du -h "$ISO_OUT" | cut -f1)
echo ""
echo "Done: $ISO_OUT ($ISO_SIZE)"
echo ""
echo "Flash to USB on macOS:"
echo "  diskutil list                         # find the USB disk (e.g. /dev/disk4)"
echo "  diskutil unmountDisk /dev/diskN       # unmount it"
echo "  sudo dd if=$ISO_OUT of=/dev/diskN bs=4M"
echo ""
echo "Or use Balena Etcher — just open the .iso file."
echo ""
echo "Then start tsbootkit and boot the Samsung from the USB stick."
