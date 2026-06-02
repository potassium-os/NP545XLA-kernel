#!/bin/bash
# src/sync-pxe.sh — Copy latest build artifacts into the PXE TFTP root
#
# Usage: bash src/sync-pxe.sh
# Run from the NP545XLA-kernel repo root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/output"
TFTP_ROOT="$REPO_ROOT/pxe/tftp"

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "ERROR: No output/ directory. Run the kernel build first."
    exit 1
fi

echo "Syncing from output/ → pxe/tftp/"

# Kernel
if [ -f "$OUTPUT_DIR/vmlinuz-np545xla" ]; then
    cp "$OUTPUT_DIR/vmlinuz-np545xla" "$TFTP_ROOT/boot/vmlinuz"
    echo "  ✓ vmlinuz"
else
    echo "  ✗ vmlinuz not found"
fi

# DTB
if [ -f "$OUTPUT_DIR/dtbs/qcom/sc8180xp-samsung-np545xla.dtb" ]; then
    mkdir -p "$TFTP_ROOT/boot/dtb/qcom"
    cp "$OUTPUT_DIR/dtbs/qcom/sc8180xp-samsung-np545xla.dtb" \
       "$TFTP_ROOT/boot/dtb/qcom/"
    echo "  ✓ DTB"
else
    echo "  ✗ DTB not found"
fi

# Initrd (custom or Ubuntu fallback)
if [ -f "$OUTPUT_DIR/initrd.img" ]; then
    cp "$OUTPUT_DIR/initrd.img" "$TFTP_ROOT/boot/initrd.img"
    echo "  ✓ initrd (custom)"
elif [ -f "$REPO_ROOT/build/initrd.img" ]; then
    cp "$REPO_ROOT/build/initrd.img" "$TFTP_ROOT/boot/initrd.img"
    echo "  ✓ initrd (Ubuntu fallback from ISO)"
else
    echo "  ✗ initrd not found — boot may fail"
fi

# GRUB config
if [ -f "$REPO_ROOT/src/grub-pxe.cfg" ]; then
    mkdir -p "$TFTP_ROOT/boot/grub"
    cp "$REPO_ROOT/src/grub-pxe.cfg" "$TFTP_ROOT/boot/grub/grub.cfg"
    echo "  ✓ grub.cfg"
fi

echo ""
echo "Done. Reboot the Samsung to pick up changes."
echo "No need to restart tsbootkit — TFTP/HTTP serve files on demand."
