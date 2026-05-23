#!/bin/bash
# Build a bootable ISO for NP545XLA DT boot
#
# Runs INSIDE the Docker container. Don't run this directly on the host.
# Use: docker run --platform linux/arm64 --rm --privileged -v "$PWD":/work -v /dev:/dev np545xla-build /work/src/build-iso.sh
#
# Expects kernel build output at:
#   output/vmlinuz-np545xla
#   output/dtbs/qcom/sc8180xp-samsung-np545xla.dtb
#   output/modules/ (for initrd generation)
#
# If output/ is empty, tries to extract from Ubuntu ISO as fallback.

set -euo pipefail

WORK="/work"
BUILD_DIR="$WORK/build"
OUTPUT="$WORK/output"
ISO_OUT="$BUILD_DIR/np545xla-boot.iso"
UBUNTU_ISO="${1:-$WORK/src/ubuntu-26.04-desktop-arm64.iso}"

mkdir -p "$BUILD_DIR"

echo "========================================="
echo " NP545XLA ISO Builder"
echo "========================================="

# --- Locate kernel, initrd, DTB ---

VMLINUZ=""
INITRD=""
DTB=""

# Custom kernel from output/
if [ -f "$OUTPUT/vmlinuz-np545xla" ]; then
    VMLINUZ="$OUTPUT/vmlinuz-np545xla"
    echo "Kernel: custom (output/vmlinuz-np545xla)"
fi

if [ -f "$OUTPUT/dtbs/qcom/sc8180xp-samsung-np545xla.dtb" ]; then
    DTB="$OUTPUT/dtbs/qcom/sc8180xp-samsung-np545xla.dtb"
    echo "DTB: custom (output/dtbs/qcom/sc8180xp-samsung-np545xla.dtb)"
fi

# Fallback: extract from Ubuntu ISO
if [ -z "$VMLINUZ" ] || [ -z "$DTB" ]; then
    if [ -f "$UBUNTU_ISO" ]; then
        echo "Falling back to Ubuntu ISO for missing components..."
        ISO_MNT=$(mktemp -d)
        mount -o ro,loop "$UBUNTU_ISO" "$ISO_MNT"

        if [ -z "$VMLINUZ" ]; then
            for vmlinuz in vmlinuz vmlinuz.efi; do
                if [ -f "$ISO_MNT/casper/$vmlinuz" ]; then
                    cp "$ISO_MNT/casper/$vmlinuz" "$BUILD_DIR/vmlinuz"
                    VMLINUZ="$BUILD_DIR/vmlinuz"
                    echo "Kernel: Ubuntu fallback ($vmlinuz)"
                    break
                fi
            done
        fi

        if [ -z "$INITRD" ]; then
            for initrd in initrd initrd.gz; do
                if [ -f "$ISO_MNT/casper/$initrd" ]; then
                    cp "$ISO_MNT/casper/$initrd" "$BUILD_DIR/initrd.img"
                    INITRD="$BUILD_DIR/initrd.img"
                    echo "Initrd: Ubuntu fallback ($initrd)"
                    break
                fi
            done
        fi

        umount "$ISO_MNT"
        rmdir "$ISO_MNT"
    else
        echo "WARNING: No Ubuntu ISO at $UBUNTU_ISO"
    fi
fi

# Fallback: build DTB from dts/
if [ -z "$DTB" ] && [ -f "$WORK/dts/sc8180xp-samsung-np545xla.dts" ]; then
    echo "Building DTB from dts/..."
    if command -v dtc &>/dev/null; then
        dtc -I dts -O dtb -o "$BUILD_DIR/sc8180xp-samsung-np545xla.dtb" "$WORK/dts/sc8180xp-samsung-np545xla.dts"
        DTB="$BUILD_DIR/sc8180xp-samsung-np545xla.dtb"
        echo "DTB: built from dts/"
    fi
fi

if [ -z "$VMLINUZ" ]; then
    echo "ERROR: No kernel image found. Run 'build.sh kernel' first."
    exit 1
fi

if [ -z "$DTB" ]; then
    echo "ERROR: No DTB found. Run 'build.sh dtbs' first."
    exit 1
fi

if [ -z "$INITRD" ]; then
    echo "WARNING: No initrd. System may not boot to a shell."
    echo "  Provide one via Ubuntu ISO or build a custom initrd."
fi

GRUB_CFG="$WORK/src/grub.cfg"

# --- Step 1: Prepare ISO filesystem tree ---
ISO_ROOT="$BUILD_DIR/iso-staging"
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/boot/grub"
mkdir -p "$ISO_ROOT/boot/dtb/qcom"
mkdir -p "$ISO_ROOT/EFI/BOOT"

echo ""
echo "[1/5] Staging files..."
cp "$DTB" "$ISO_ROOT/boot/dtb/qcom/"
cp "$GRUB_CFG" "$ISO_ROOT/boot/grub/grub.cfg"
cp "$VMLINUZ" "$ISO_ROOT/boot/vmlinuz"
[ -n "$INITRD" ] && cp "$INITRD" "$ISO_ROOT/boot/initrd.img"

# --- Step 2: Build GRUB EFI binary ---
echo "[2/5] Building GRUB EFI image..."

GRUB_MODULES="
    boot
    chain
    configfile
    echo
    efi_gop
    efitextmode
    ext2
    fat
    font
    gfxmenu
    gfxterm
    gzio
    linux
    loadenv
    normal
    part_gpt
    part_msdos
    search
    search_fs_uuid
    search_fs_file
    serial
    terminal
    terminfo
    true
    video
    video_fb
    videoinfo
"

grub-mkimage \
    -O arm64-efi \
    -o "$BUILD_DIR/bootaa64.efi" \
    -p /boot/grub \
    $GRUB_MODULES

echo "  EFI binary: $(du -h "$BUILD_DIR/bootaa64.efi" | cut -f1)"

# Copy into ISO9660 tree (xorriso -e needs it there)
cp "$BUILD_DIR/bootaa64.efi" "$ISO_ROOT/EFI/BOOT/BOOTAA64.EFI"

# --- Step 3: Build FAT ESP partition image ---
echo "[3/5] Building ESP partition image..."

ESP_IMG="$BUILD_DIR/esp.img"
ESP_SIZE_MB=64

dd if=/dev/zero of="$ESP_IMG" bs=1M count="$ESP_SIZE_MB" status=none
mkfs.vfat -F 32 -n EFI "$ESP_IMG"

MNT=$(mktemp -d)
mount "$ESP_IMG" "$MNT"
mkdir -p "$MNT/EFI/BOOT"
mkdir -p "$MNT/boot/grub"
mkdir -p "$MNT/boot/dtb/qcom"
cp "$BUILD_DIR/bootaa64.efi" "$MNT/EFI/BOOT/BOOTAA64.EFI"
cp "$GRUB_CFG" "$MNT/boot/grub/grub.cfg"
cp "$DTB" "$MNT/boot/dtb/qcom/"
cp "$VMLINUZ" "$MNT/boot/vmlinuz"
[ -n "$INITRD" ] && cp "$INITRD" "$MNT/boot/initrd.img"
umount "$MNT"
rmdir "$MNT"

echo "  ESP image: $(du -h "$ESP_IMG" | cut -f1)"

# --- Step 4: Generate ISO ---
echo "[4/5] Generating ISO..."

xorriso -as mkisofs \
    -r -J \
    -V "NP545XLA Boot" \
    -o "$ISO_OUT" \
    --protective-msdos-label \
    -c /boot/boot.cat \
    -e /EFI/BOOT/BOOTAA64.EFI \
    -no-emul-boot \
    -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b "$ESP_IMG" \
    -appended_part_as_gpt \
    --mbr-force-bootable \
    "$ISO_ROOT"

# --- Step 5: Cleanup ---
echo "[5/5] Cleaning up..."
rm -rf "$ISO_ROOT" "$ESP_IMG" "$BUILD_DIR/bootaa64.efi"

ISO_SIZE=$(du -h "$ISO_OUT" | cut -f1)
echo ""
echo "========================================="
echo " ISO ready!"
echo "========================================="
echo "  $ISO_OUT ($ISO_SIZE)"
echo ""
echo "Flash to USB stick:"
echo "  dd if=build/np545xla-boot.iso of=/dev/sdX bs=4M status=progress"
echo "========================================="
