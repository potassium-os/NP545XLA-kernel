#!/bin/bash
# Build a bootable ISO for NP545XLA DT boot
#
# Runs INSIDE the Docker container. Don't run this directly on the host.
# Use: docker run --platform linux/arm64 --rm --privileged -v "$PWD":/work -v /dev:/dev np545xla-kernel-build /work/src/build-iso.sh [ubuntu-arm64.iso]
#
# Produces a bootable ISO9660 image (El Torito EFI boot) that Samsung UEFI
# can actually detect. Samsung firmware only boots ISOs and needs a real
# FAT ESP partition embedded in the GPT, not just a file in the ISO filesystem.
#
# Flash with: dd if=build/np545xla-boot.iso of=/dev/sdX bs=4M status=progress

set -euo pipefail

WORK="/work"
GRUB_CFG="$WORK/src/grub.cfg"
BUILD_DIR="$WORK/build"
ISO_OUT="$BUILD_DIR/np545xla-boot.iso"
UBUNTU_ISO="${1:-$WORK/src/ubuntu-26.04-desktop-arm64.iso}"
UBUNTU_ISO_URL="https://cdimage.ubuntu.com/cdimage/releases/26.04/release/ubuntu-26.04-desktop-arm64.iso"

mkdir -p "$BUILD_DIR"

echo "========================================="
echo " NP545XLA ISO Builder"
echo "========================================="

# --- Locate kernel, initrd, DTB ---

VMLINUZ=""
INITRD=""
DTB_FINAL=""

# Custom kernel from output/
if [ -f "$WORK/output/vmlinuz-np545xla" ]; then
    VMLINUZ="$WORK/output/vmlinuz-np545xla"
    echo "Kernel: custom (output/vmlinuz-np545xla)"
fi

# Custom DTB from output/ (preferred) or build from dts/
if [ -f "$WORK/output/dtbs/qcom/sc8180xp-samsung-np545xla.dtb" ]; then
    DTB_FINAL="$WORK/output/dtbs/qcom/sc8180xp-samsung-np545xla.dtb"
    echo "DTB: custom (output/dtbs/qcom/sc8180xp-samsung-np545xla.dtb)"
elif [ -f "$WORK/dts/sc8180xp-samsung-np545xla.dts" ]; then
    echo "Building DTB from dts/..."
    cpp -nostdinc -I "$WORK/linux/include" \
        -I "$WORK/linux/arch/arm64/boot/dts" \
        -I "$WORK/linux/arch/arm64/boot/dts/qcom" \
        -undef -x assembler-with-cpp \
        "$WORK/dts/sc8180xp-samsung-np545xla.dts" \
        > /tmp/np545xla.dts.prep && \
    dtc -I dts -O dtb -o "$BUILD_DIR/sc8180xp-samsung-np545xla.dtb" /tmp/np545xla.dts.prep 2>&1 || \
    echo "  WARNING: DTB build failed"
    DTB_FINAL="$BUILD_DIR/sc8180xp-samsung-np545xla.dtb"
    echo "DTB: built from dts/"
fi

# Initrd: prefer custom, fall back to Ubuntu ISO
if [ -f "$WORK/output/initrd.img" ]; then
    INITRD="$WORK/output/initrd.img"
    echo "Initrd: custom (output/initrd.img)"
elif [ -z "$INITRD" ]; then
    # Download Ubuntu ISO if not present
    if [ ! -f "$UBUNTU_ISO" ]; then
        echo "Ubuntu ISO not found at $UBUNTU_ISO"
        echo "Downloading from $UBUNTU_ISO_URL ..."
        mkdir -p "$(dirname "$UBUNTU_ISO")"
        curl -fSL -o "$UBUNTU_ISO" "$UBUNTU_ISO_URL"
    fi

    if [ -f "$UBUNTU_ISO" ]; then
        echo "Extracting initrd from Ubuntu ISO..."
        ISO_MNT=$(mktemp -d)
        mount -o ro,loop "$UBUNTU_ISO" "$ISO_MNT"

        # Also grab kernel from ISO if we don't have a custom one
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

        for initrd in initrd initrd.gz; do
            if [ -f "$ISO_MNT/casper/$initrd" ]; then
                cp "$ISO_MNT/casper/$initrd" "$BUILD_DIR/initrd.img"
                INITRD="$BUILD_DIR/initrd.img"
                echo "Initrd: Ubuntu ($initrd)"
                break
            fi
        done

        umount "$ISO_MNT"
        rmdir "$ISO_MNT"
    fi
fi

if [ -z "$VMLINUZ" ]; then
    echo "ERROR: No kernel image found. Run 'build.sh kernel' first."
    exit 1
fi

if [ -z "$DTB_FINAL" ]; then
    echo "ERROR: No DTB found. Run 'build.sh dtbs' first."
    exit 1
fi

if [ -z "$INITRD" ]; then
    echo "WARNING: No initrd. System may not boot to a shell."
fi

# --- Step 1: Prepare ISO filesystem tree ---
ISO_ROOT="$BUILD_DIR/iso-staging"
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/boot/grub"
mkdir -p "$ISO_ROOT/boot/dtb/qcom"
mkdir -p "$ISO_ROOT/EFI/BOOT"

echo ""
echo "[1/5] Staging files..."
cp "$DTB_FINAL" "$ISO_ROOT/boot/dtb/qcom/"
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
ESP_SIZE_MB=256

dd if=/dev/zero of="$ESP_IMG" bs=1M count="$ESP_SIZE_MB" status=none
mkfs.vfat -F 32 -n EFI "$ESP_IMG"

MNT=$(mktemp -d)
mount "$ESP_IMG" "$MNT"
mkdir -p "$MNT/EFI/BOOT"
mkdir -p "$MNT/boot/grub"
mkdir -p "$MNT/boot/dtb/qcom"
cp "$BUILD_DIR/bootaa64.efi" "$MNT/EFI/BOOT/BOOTAA64.EFI"
cp "$GRUB_CFG" "$MNT/boot/grub/grub.cfg"
cp "$DTB_FINAL" "$MNT/boot/dtb/qcom/"
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
