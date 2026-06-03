#!/bin/bash
# src/build-usb-http-stick.sh — Create a USB-HTTP boot stick as an El Torito ISO
#
# Usage: bash src/build-usb-http-stick.sh
#
# Produces: pxe/usb-http-stick.iso (El Torito EFI boot ISO)
#
# Boot chain: UEFI Shell → loads ASIX driver via startup.nsh → chainloads GRUB → HTTP boot
#
# The Samsung UEFI only boots ISOs with El Torito EFI boot entries — it ignores
# raw GPT ESP partitions on USB drives. So we produce a minimal ISO instead of
# a raw .img, using the same xorriso + appended ESP technique as build-iso.sh.
#
# The Tianocore UEFI Shell is the primary boot entry. Its startup.nsh loads the
# ASIX AX88179 UEFI driver (which registers the NIC with UEFI's SNP), then
# chainloads GRUB. GRUB's efinet can then see the NIC, DHCP, and fetch
# kernel/initrd over HTTP from tsbootkit.
#
# rEFInd was tried first but hard-crashes on Samsung's GOP — black screen, no input.
#
# Runs INSIDE the Docker container. Don't run this directly on the host.
# Use: docker run --platform linux/arm64 --rm --privileged -v "$PWD":/work np545xla-kernel-build /work/src/build-usb-http-stick.sh
#
# Flash to USB on macOS:  dd if=pxe/usb-http-stick.iso of=/dev/diskN bs=4M
# Or use Balena Etcher:   open pxe/usb-http-stick.iso

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/usb-http-stick"
ISO_OUT="$REPO_ROOT/pxe/usb-http-stick.iso"

# --- EFI binary paths ---
SHELL_EFI="$REPO_ROOT/pxe/efi/Shell.efi"
ASIX_EFI="$REPO_ROOT/pxe/efi/Ax88179Aa64.efi"
GRUB_EFI="$REPO_ROOT/pxe/tftp/BOOTAA64.EFI"
STARTUP_NSH="$REPO_ROOT/src/startup.nsh"

# Verify all required files exist
for f in "$SHELL_EFI" "$ASIX_EFI" "$GRUB_EFI" "$STARTUP_NSH"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Missing file: $f"
        echo ""
        echo "Download missing EFI binaries:"
        echo "  Shell:   apt-get download efi-shell-aa64 (Ubuntu) or build from edk2 ShellPkg"
        echo "  ASIX:    https://www.asix.com.tw/en/support/download/step2/11/2/3 → UEFI ARM/AARCH64"
        echo "  GRUB:    bash src/build-grub-netboot.sh"
        exit 1
    fi
done

echo "Building USB-HTTP boot ISO..."
echo ""
echo "  Shell:    $(basename "$SHELL_EFI") ($(du -h "$SHELL_EFI" | cut -f1))"
echo "  ASIX:     $(basename "$ASIX_EFI") ($(du -h "$ASIX_EFI" | cut -f1))"
echo "  GRUB:     $(basename "$GRUB_EFI") ($(du -h "$GRUB_EFI" | cut -f1))"
echo "  startup:  startup.nsh"
echo ""

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# --- Step 1: Prepare ISO filesystem tree ---
ISO_ROOT="$BUILD_DIR/iso-staging"
mkdir -p "$ISO_ROOT/EFI/BOOT"
mkdir -p "$ISO_ROOT/EFI/drivers"
mkdir -p "$ISO_ROOT/EFI/grub"
mkdir -p "$ISO_ROOT/boot/grub"

# UEFI Shell is the primary boot entry (Samsung UEFI finds BOOTAA64.EFI on ESP)
cp "$SHELL_EFI" "$ISO_ROOT/EFI/BOOT/BOOTAA64.EFI"

# ASIX UEFI driver — loaded by startup.nsh before GRUB
cp "$ASIX_EFI" "$ISO_ROOT/EFI/drivers/Ax88179Aa64.efi"

# GRUB binary — chainloaded by startup.nsh after the ASIX driver is loaded
cp "$GRUB_EFI" "$ISO_ROOT/EFI/grub/BOOTAA64.EFI"

# startup.nsh — auto-executed by the UEFI Shell
cp "$STARTUP_NSH" "$ISO_ROOT/startup.nsh"

# GRUB stub config — net_bootp should work now that ASIX driver registered the NIC
cat > "$ISO_ROOT/boot/grub/grub.cfg" << GRUBEOF
# USB-HTTP grub.cfg — loaded by GRUB after startup.nsh loads the ASIX driver
# The ASIX driver should have registered the NIC with UEFI's SNP,
# so efinet should now see it.

net_bootp

set server=192.168.202.5:8080
set prefix=(http,\${server})/boot/grub
configfile (http,\${server})/boot/grub/grub.cfg
GRUBEOF

# --- Step 2: Build FAT ESP partition image ---
# The Samsung UEFI needs an appended GPT ESP partition to find the EFI binary.
# The El Torito entry points to the same binary inside the ISO9660 filesystem.
echo "Building ESP partition image..."

ESP_IMG="$BUILD_DIR/esp.img"
ESP_SIZE_MB=64

dd if=/dev/zero of="$ESP_IMG" bs=1M count="$ESP_SIZE_MB" status=none
mkfs.vfat -F 32 -n EFI "$ESP_IMG"

MNT=$(mktemp -d)
mount "$ESP_IMG" "$MNT"

# Mirror the same layout onto the ESP
mkdir -p "$MNT/EFI/BOOT"
mkdir -p "$MNT/EFI/drivers"
mkdir -p "$MNT/EFI/grub"
mkdir -p "$MNT/boot/grub"

cp "$SHELL_EFI" "$MNT/EFI/BOOT/BOOTAA64.EFI"
cp "$ASIX_EFI" "$MNT/EFI/drivers/Ax88179Aa64.efi"
cp "$GRUB_EFI" "$MNT/EFI/grub/BOOTAA64.EFI"
cp "$STARTUP_NSH" "$MNT/startup.nsh"
cp "$ISO_ROOT/boot/grub/grub.cfg" "$MNT/boot/grub/grub.cfg"

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
echo "Boot chain: UEFI Shell → startup.nsh → ASIX driver → GRUB → HTTP (tsbootkit)"
echo ""
echo "Flash to USB on macOS:"
echo "  diskutil list                         # find the USB disk (e.g. /dev/disk4)"
echo "  diskutil unmountDisk /dev/diskN       # unmount it"
echo "  sudo dd if=$ISO_OUT of=/dev/diskN bs=4M"
echo ""
echo "Or use Balena Etcher — just open the .iso file."
echo ""
echo "Then start tsbootkit and boot the Samsung from the USB stick."
echo ""
echo "If the Shell appears but GRUB fails, check from the Shell prompt:"
echo "  Shell> load fs0:\EFI\drivers\Ax88179Aa64.efi"
echo "  Shell> dh -p UsbIo"
echo "  Shell> dh -p SimpleNetwork"
