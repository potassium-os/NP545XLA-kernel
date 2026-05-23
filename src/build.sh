#!/bin/bash
# Build the NP545XLA kernel inside the Docker container
#
# Usage: docker run --rm -v "$PWD":/work np545xla-kernel-build [target]
#   target: kernel (default), dtbs, modules, iso, all
#
# Output goes to /work/output/

set -euo pipefail

WORK="/work"
OUTPUT="$WORK/output"
SRC="$WORK/linux"
DEFCONFIG="np545xla_defconfig"
TARGET="${1:-kernel}"

JOBS=$(nproc)

mkdir -p "$OUTPUT"

if [ ! -d "$SRC" ]; then
    echo "ERROR: Kernel source not found at $SRC"
    echo "Run: git clone --depth 1 --branch v7.0 https://github.com/torvalds/linux.git $SRC"
    exit 1
fi

cd "$SRC"

# Apply defconfig
if [ ! -f ".config" ] || [ "$WORK/configs/$DEFCONFIG" -nt ".config" ]; then
    echo "========================================="
    echo " Applying defconfig: $DEFCONFIG"
    echo "========================================="
    cp "$WORK/configs/$DEFCONFIG" .config
    make olddefconfig
fi

build_dtbs() {
    make -j$JOBS dtbs
    mkdir -p "$OUTPUT/dtbs/qcom"
    # Copy from kernel tree if our DTS is included
    cp arch/arm64/boot/dts/qcom/sc8180xp-samsung-np545xla.dtb "$OUTPUT/dtbs/qcom/" 2>/dev/null || true
    # Fallback: build our custom DTS directly
    if [ ! -f "$OUTPUT/dtbs/qcom/sc8180xp-samsung-np545xla.dtb" ] && [ -f "$WORK/dts/sc8180xp-samsung-np545xla.dts" ]; then
        echo "  Building custom DTB from dts/..."
        cpp -nostdinc -I "$WORK/linux/include" \
            -I "$WORK/linux/arch/arm64/boot/dts" \
            -I "$WORK/linux/arch/arm64/boot/dts/qcom" \
            -undef -x assembler-with-cpp \
            "$WORK/dts/sc8180xp-samsung-np545xla.dts" \
            > /tmp/np545xla.dts.prep && \
        dtc -I dts -O dtb -o "$OUTPUT/dtbs/qcom/sc8180xp-samsung-np545xla.dtb" /tmp/np545xla.dts.prep 2>&1 || \
        echo "  WARNING: DTB build failed"
    fi
}

case "$TARGET" in
    kernel)
        echo "========================================="
        echo " Building kernel image"
        echo "========================================="
        make -j$JOBS Image.gz
        cp arch/arm64/boot/Image.gz "$OUTPUT/vmlinuz-np545xla"
        echo "  → $OUTPUT/vmlinuz-np545xla"
        ;;
    dtbs)
        echo "========================================="
        echo " Building DTBs"
        echo "========================================="
        build_dtbs
        echo "  → $OUTPUT/dtbs/"
        ;;
    modules)
        echo "========================================="
        echo " Building modules"
        echo "========================================="
        make -j$JOBS modules
        make INSTALL_MOD_PATH="$OUTPUT/modules" modules_install
        echo "  → $OUTPUT/modules/"
        ;;
    iso)
        echo "========================================="
        echo " Building boot ISO"
        echo "========================================="
        /work/src/build-iso.sh
        ;;
    all)
        echo "========================================="
        echo " Building kernel + DTBs + modules + ISO"
        echo "========================================="
        make -j$JOBS Image.gz modules

        cp arch/arm64/boot/Image.gz "$OUTPUT/vmlinuz-np545xla"
        echo "  → $OUTPUT/vmlinuz-np545xla"

        build_dtbs
        echo "  → $OUTPUT/dtbs/"

        make INSTALL_MOD_PATH="$OUTPUT/modules" modules_install
        echo "  → $OUTPUT/modules/"

        # Build the ISO with our custom kernel
        /work/src/build-iso.sh
        ;;
    debs)
        echo "========================================="
        echo " Building Debian packages"
        echo "========================================="
        make -j$JOBS bindeb-pkg LOCALVERSION=-np545xla KDEB_CHANGELOG_DIST="$(lsb_release -sc 2>/dev/null || echo stable)"
        # Move debs to output/
        mv ../linux-*.deb "$OUTPUT/" 2>/dev/null || true
        echo "  → $OUTPUT/linux-*.deb"
        ;;
    clean)
        echo "Cleaning..."
        make clean
        rm -rf "$OUTPUT"/* "$WORK/build"/*
        ;;
    *)
        echo "Unknown target: $TARGET"
        echo "Usage: $0 [kernel|dtbs|modules|debs|iso|all|clean]"
        exit 1
        ;;
esac

echo ""
echo "========================================="
echo " Build complete!"
echo "========================================="
