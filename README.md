# NP545XLA Kernel

> ⚠️ **Work in progress.** This kernel does not yet produce a fully booting system. We're actively working through the SC8180XP driver bring-up. If you have the same hardware or want to help, please [open an issue](https://github.com/potassium-os/NP545XLA-kernel/issues) — we'd love to hear from you.

Custom Linux kernel + boot ISO for the Samsung Galaxy Book Go 5G (SC8180XP).

The stock Ubuntu kernel doesn't include sc8180x-specific drivers (GCC, interconnect, SMMU power domains) — they're either missing entirely or loaded as modules that can't probe because their dependencies form a circular chain. This kernel builds everything critical as built-in (`=y`) so the hardware actually initializes.

## Quick Start

```bash
# Clone this repo
git clone https://github.com/potassium-os/NP545XLA-kernel.git
cd NP545XLA-kernel

# Shallow clone the kernel source (v7.0)
git clone --depth 1 --branch v7.0 https://github.com/torvalds/linux.git linux

# Build the Docker image (x86 host, cross-compiles arm64)
docker build --platform linux/arm64 -t np545xla-kernel-build .

# Build everything: kernel + DTBs + modules + boot ISO
docker run --platform linux/arm64 --rm -v "$PWD":/work np545xla-kernel-build /work/src/build.sh all

# Or build individual components:
docker run --platform linux/arm64 --rm -v "$PWD":/work np545xla-kernel-build /work/src/build.sh kernel
docker run --platform linux/arm64 --rm -v "$PWD":/work np545xla-kernel-build /work/src/build.sh dtbs
docker run --platform linux/arm64 --rm -v "$PWD":/work np545xla-kernel-build /work/src/build.sh modules
```

### Build the boot ISO

The ISO bundles the kernel, DTB, and GRUB into a Samsung-UEFI-compatible El Torito boot image:

```bash
# Requires --privileged and /dev access for loop devices
docker run --platform linux/arm64 --rm --privileged -v "$PWD":/work -v /dev:/dev np545xla-kernel-build /work/src/build.sh iso

# With Ubuntu initrd fallback (if no custom initrd):
docker run --platform linux/arm64 --rm --privileged -v "$PWD":/work -v /dev:/dev np545xla-kernel-build /work/src/build-iso.sh /work/src/ubuntu-26.04-desktop-arm64.iso
```

### Flash to USB and boot

```bash
dd if=build/np545xla-boot.iso of=/dev/sdX bs=4M status=progress
```

## Build Targets

| Target | What it builds |
|--------|---------------|
| `kernel` | `Image.gz` → `output/vmlinuz-np545xla` |
| `dtbs` | Device tree blobs → `output/dtbs/` |
| `modules` | Loadable modules → `output/modules/` |
| `iso` | Boot ISO → `build/np545xla-boot.iso` |
| `all` | Everything above |
| `clean` | Clean build artifacts |

## Configuration

`configs/np545xla_defconfig` — everything critical for SC8180X boot is built-in:

- **Clocks:** `gcc-sc8180x`, `gpucc-sc8180x`, `dispcc-sc8180x`
- **Interconnect:** `qnoc-sc8180x`
- **Power domains:** `rpmhpd`, `rpmh-regulator`
- **IOMMU:** `arm-smmu`, `arm-smmu-qcom`
- **UFS:** `ufs-qcom`
- **USB:** `dwc3-qcom`, `xhci-hcd`
- **Serial:** `qcom_geni_serial`, `serial_msm`
- **Pinctrl:** `pinctrl-sc8180x`
- **PHY:** `phy-qcom-qmp-ufs`, `phy-qcom-qmp-usb`

WiFi (ath11k) and remoteproc are modules — they need firmware that's loaded after rootfs mounts.

## Device Tree

`dts/sc8180xp-samsung-np545xla.dts` — board-specific DTS for the NP545XLA. Includes:
- UART12 (QUP1 SE10) debug console at 0xA90000
- UFS storage, USB (primary + secondary)
- PMIC regulators, GPIO keys
- Reserved memory regions

The DTS is built as part of `dtbs` target or can be built standalone via the Makefile in `dts/`.

## GRUB Config

`src/grub.cfg` — 13 boot entries covering:
- Standard DT boot (fbcon only)
- Serial console variants (ttyMSM0/ttyS0/ttyAMA0)
- Initrd debug shells (`break=top`, `break=premount`)
- nomodeset entries (keeps efifb, prevents DRM blanking)
- IOMMU bypass (`iommu=off`) for testing
- ACPI fallback

## GitHub Actions

Pushes to `main` automatically build the kernel. Artifacts are uploaded:
- `vmlinuz-np545xla` — the kernel image
- `dtbs-np545xla` — device tree blobs
- `modules-np545xla` — loadable kernel modules

You can also trigger a manual build via workflow dispatch, optionally specifying a kernel tag.

## Repository Layout

```
├── Dockerfile               ← Cross-compilation + ISO builder container
├── configs/
│   └── np545xla_defconfig   ← Kernel configuration
├── dts/
│   ├── sc8180xp-samsung-np545xla.dts  ← Board device tree
│   ├── Makefile                         ← Standalone DTB build
│   └── QUESTIONS.md                     ← Open design questions
├── src/
│   ├── build.sh             ← Kernel build script (runs in Docker)
│   ├── build-iso.sh         ← ISO builder (runs in Docker)
│   └── grub.cfg             ← GRUB boot menu
├── .github/
│   └── workflows/
│       └── build.yml        ← CI: build on push, upload artifacts
├── linux/                   ← Kernel source (shallow clone, gitignored)
└── output/                  ← Build output (gitignored)
    ├── vmlinuz-np545xla
    ├── dtbs/
    └── modules/
```

## License

GPL-2.0 — same as the Linux kernel
