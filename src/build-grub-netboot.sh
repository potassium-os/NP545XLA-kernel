#!/bin/bash
# src/build-grub-netboot.sh — Build GRUB arm64-efi binary with network modules
#
# Run inside the NP545XLA-kernel Docker container:
#   docker run --platform linux/arm64 --rm -v "$PWD":/work np545xla-kernel-build \
#       /work/src/build-grub-netboot.sh
#
# Or on any system with grub-efi-arm64-bin installed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/pxe/tftp"

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
    net
    tftp
    http
    efinet
"

echo "Building GRUB arm64-efi netboot binary..."

grub-mkimage \
    -O arm64-efi \
    -o "$OUTPUT_DIR/BOOTAA64.EFI" \
    -p /boot/grub \
    $GRUB_MODULES

echo "Done: $OUTPUT_DIR/BOOTAA64.EFI ($(du -h "$OUTPUT_DIR/BOOTAA64.EFI" | cut -f1))"
