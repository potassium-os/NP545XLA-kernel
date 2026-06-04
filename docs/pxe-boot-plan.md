# PXE Boot Plan — Samsung Galaxy Book Go 5G (NP545XLA)

The Samsung laptop has no built-in Ethernet, but its UEFI will load a PXE option ROM from a USB Ethernet adapter. This means we can boot over the network from a dev machine — no more dd'ing ISOs to USB sticks for every kernel or DTB change.

We use [tsbootkit](https://github.com/thehonker/tsbootkit) — our own TypeScript PXE/TFTP toolkit with built-in DHCP, BOOTP, TFTP, and HTTP fallback. Cross-platform (macOS, Linux, Docker), no Python or dnsmasq required.

---

## Architecture

```
┌─────────────────────┐         USB-Ethernet          ┌────────────────────┐
│  Dev machine         │◄──────────────────────────►│  Samsung NP545XLA   │
│  tsbootkit-pxed      │     (direct cable or switch) │  UEFI PXE client   │
│  (DHCP+TFTP+HTTP)    │                              │  192.168.202.x     │
│  192.168.202.5        │                              │                    │
│  pxe/tftp/           │                              │                    │
│  ├─ BOOTAA64.EFI     │  ◄── TFTP: GRUB binary      │                    │
│  ├─ grub.cfg         │  ◄── TFTP: config            │                    │
│  ├─ vmlinuz          │  ◄── HTTP/TFTP: kernel       │                    │
│  ├─ initrd.img       │  ◄── HTTP/TFTP: initrd       │                    │
│  └─ *.dtb            │  ◄── HTTP/TFTP: device tree  │                    │
└─────────────────────┘                              └────────────────────┘
```

**Boot flow:** Samsung UEFI PXE client → DHCP discover → `tsbootkit-pxed` responds with IP + `BOOTAA64.EFI` path → GRUB loaded via TFTP → GRUB reads `grub.cfg` via TFTP → loads kernel + initrd + DTB via HTTP (faster) or TFTP → boots.

---

## PXE Server: tsbootkit

[tsbootkit](https://github.com/thehonker/tsbootkit) provides `tsbootkit-pxed` — a combined DHCP + TFTP + HTTP server in a single Node.js process. No config files needed for basic use (YAML config available for advanced setups).

### Install

```bash
npm install -g tsbootkit
```

Or via Docker:

```bash
docker pull ghcr.io/thehonker/tsbootkit:latest
```

### Run (one command)

```bash
# From the NP545XLA-kernel repo root:
sudo tsbootkit-pxed en0 pxe/tftp BOOTAA64.EFI --http-port 8080 -v
```

This:
1. Starts a DHCP server on `en0` (the USB ethernet interface)
2. Starts a TFTP server serving files from `pxe/tftp/`
3. Starts an HTTP server on port 8080 (same root, faster for large files)
4. Tells PXE clients to boot `BOOTAA64.EFI` from TFTP

**No dnsmasq. No Python. No config file.** One command, Ctrl+C to stop.

### Key options

| Flag | What it does |
|------|-------------|
| `-v` / `-vv` / `-vvv` | Verbose levels: info, debug, trace |
| `--mode bootp` | Use BOOTP instead of DHCP |
| `--answer-all` | Respond to non-PXE DHCP requests |
| `--http-port 8080` | Enable HTTP fallback (same root, 5-10x faster than TFTP) |
| `--wait` | Wait for interface to come up (USB-Ethernet hotplug) |
| `--wait-timeout 30` | Max seconds to wait for interface |
| `--config src/tsbootkit.yaml` | Load full config from YAML |
| `--gateway 192.168.202.5` | Set gateway IP advertised to clients |
| `--dns 8.8.8.8` | DNS server(s) advertised to clients |

For our use case:

```bash
sudo tsbootkit-pxed en0 pxe/tftp BOOTAA64.EFI --http-port 8080 -v
```

Verbose mode shows DHCP transactions and TFTP/HTTP transfers — essential during bring-up.

### Config file mode

For persistent setups, use a YAML config:

```yaml
# src/tsbootkit.yaml
interface: en0
bootFile: BOOTAA64.EFI
tftpRoot: pxe/tftp
mode: dhcp
httpPort: 8080
logging:
  level: info

bootFiles:
  efiARM64: BOOTAA64.EFI

reservations:
  - mac: XX:XX:XX:XX:XX:XX   # Samsung's USB-Ethernet MAC
    ip: 192.168.202.50
    bootFile: BOOTAA64.EFI
```

```bash
sudo tsbootkit-pxed --config src/tsbootkit.yaml
```

### Docker mode

```bash
# From the NP545XLA-kernel repo root:
docker run --net=host \
  -v ./pxe/tftp:/tftpboot \
  ghcr.io/thehonker/tsbootkit:latest \
  tsbootkit-pxed eth0 /tftpboot BOOTAA64.EFI --http-port 8080 -v
```

---

## Repository Structure

All PXE files live in the **NP545XLA-kernel repo** (`~/repos/potassium-os/NP545XLA-kernel`):

```
NP545XLA-kernel/
├── src/
│   ├── build.sh                  ← kernel/DTB/ISO build
│   ├── build-iso.sh              ← ISO builder
│   ├── build-grub-netboot.sh     ← build BOOTAA64.EFI with net modules
│   ├── build-usb-http-stick.sh   ← create USB stick for HTTP boot (Path B)
│   ├── pxe-serve.sh              ← one-shot PXE server + netconsole listener
│   ├── sync-pxe.sh               ← push build artifacts to PXE TFTP root
│   ├── grub.cfg                  ← ISO GRUB config
│   ├── grub-pxe.cfg              ← PXE-adapted GRUB config
│   └── tsbootkit.yaml            ← optional tsbootkit config (reservations, etc.)
└── pxe/
    └── tftp/
        ├── BOOTAA64.EFI          ← GRUB arm64-efi netboot binary
        └── boot/
            └── .gitkeep          ← actual kernel/initrd/DTB gitignored
```

The `pxe/tftp/boot/` directory is gitignored (files are large, built by `build.sh`). Contains:

```
pxe/tftp/boot/
├── vmlinuz                            ← from output/
├── initrd.img                         ← from output/ or Ubuntu ISO
├── dtb/
│   └── qcom/
│       └── sc8180xp-samsung-np545xla.dtb
└── grub/
    └── grub.cfg                       ← copy of src/grub-pxe.cfg
```

The `BOOTAA64.EFI` sits at `pxe/tftp/BOOTAA64.EFI` (TFTP root), since that's what `tsbootkit-pxed` references as the boot filename.

---

## 1. GRUB arm64-efi Netboot Binary (`BOOTAA64.EFI`)

This is NOT the same as the ISO's EFI binary. It needs network modules compiled in.

### Option A: Pre-built (quickest start)

Download Ubuntu's signed GRUB netboot binary:

```
http://archive.ubuntu.com/ubuntu/dists/noble/main/uefi/grub2-arm64/current/grubnetaa64.efi.signed
```

Rename to `BOOTAA64.EFI` and place in `pxe/tftp/`.

### Option B: Build our own (full control)

Build inside the NP545XLA-kernel Docker container (already has grub tools):

```bash
bash src/build-grub-netboot.sh
```

Or manually:

```bash
grub-mkimage -O arm64-efi -o BOOTAA64.EFI -p /boot/grub \
    boot chain configfile echo efi_gop efitextmode ext2 fat font \
    gfxmenu gfxterm gzio linux loadenv normal part_gpt part_msdos \
    search search_fs_uuid search_fs_file serial terminal terminfo \
    true video video_fb videoinfo \
    net tftp http efinet
```

Key additions vs the ISO build: **`net tftp http efinet`** — the network boot modules.

---

## 2. GRUB Config (TFTP/HTTP-adapted)

The PXE GRUB config lives at `src/grub-pxe.cfg` in the kernel repo. Same entries as the ISO `grub.cfg`, but all paths are relative to the TFTP root. With HTTP enabled, GRUB can fetch large files much faster. The kernel and initrd paths work over both TFTP and HTTP — GRUB prefers whichever protocol the `BOOTAA64.EFI` was loaded with, falling back to TFTP.

```cfg
# src/grub-pxe.cfg — PXE boot GRUB config for NP545XLA
#
# Paths are relative to the TFTP/HTTP root (pxe/tftp/ directory).
# To update kernel/DTB: just replace files in pxe/tftp/ and reboot.

set timeout=30
set default=0

# --- Standard boot entries ---

menuentry 'NP545XLA (DT)' {
    echo ">>> PXE Boot: DT, console=fbcon (tty0 only)"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused console=tty0 loglevel=8
    initrd /boot/initrd.img
}

menuentry 'NP545XLA (DT + serial ttyMSM0)' {
    echo ">>> PXE Boot: DT, console=serial(ttyMSM0)+fbcon, earlycon=qcom_geni"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused earlycon=qcom_geni,0xA90000 console=ttyMSM0,115200n8 console=tty0 loglevel=8
    initrd /boot/initrd.img
}

# --- Initrd debug shell entries ---

menuentry 'NP545XLA DT — break=top, ttyMSM0' {
    echo ">>> PXE Boot: DT, initrd shell before any scripts, serial(ttyMSM0)+fbcon"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused earlycon=qcom_geni,0xA90000 console=ttyMSM0,115200n8 console=tty0 loglevel=8 break=top
    initrd /boot/initrd.img
}

menuentry 'NP545XLA DT — break=premount, ttyMSM0' {
    echo ">>> PXE Boot: DT, initrd shell before mounting root, serial(ttyMSM0)+fbcon"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused earlycon=qcom_geni,0xA90000 console=ttyMSM0,115200n8 console=tty0 loglevel=8 break=premount
    initrd /boot/initrd.img
}

# --- nomodeset entries (keeps efifb, prevents DRM from blanking display) ---

menuentry 'NP545XLA DT — nomodeset, ttyMSM0' {
    echo ">>> PXE Boot: DT, nomodeset (efifb only), serial(ttyMSM0)+fbcon"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused earlycon=qcom_geni,0xA90000 console=ttyMSM0,115200n8 console=tty0 loglevel=8 nomodeset
    initrd /boot/initrd.img
}

menuentry 'NP545XLA DT — nomodeset + break=top, ttyMSM0' {
    echo ">>> PXE Boot: DT, nomodeset, initrd shell (break=top), serial(ttyMSM0)+fbcon"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused earlycon=qcom_geni,0xA90000 console=ttyMSM0,115200n8 console=tty0 loglevel=8 nomodeset break=top
    initrd /boot/initrd.img
}

# --- IOMMU diagnostic entries ---

menuentry 'NP545XLA DT — nomodeset + iommu=off, ttyMSM0' {
    echo ">>> PXE Boot: DT, nomodeset, IOMMU disabled, serial(ttyMSM0)+fbcon"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused earlycon=qcom_geni,0xA90000 console=ttyMSM0,115200n8 console=tty0 loglevel=8 nomodeset iommu=off
    initrd /boot/initrd.img
}

menuentry 'NP545XLA DT — nomodeset + iommu=off + break=top, ttyMSM0' {
    echo ">>> PXE Boot: DT, nomodeset, IOMMU disabled, initrd shell (break=top), serial(ttyMSM0)+fbcon"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused earlycon=qcom_geni,0xA90000 console=ttyMSM0,115200n8 console=tty0 loglevel=8 nomodeset iommu=off break=top
    initrd /boot/initrd.img
}

# --- netconsole entries (kernel log over UDP to 192.168.202.5:6666) ---
# On the dev machine: nc -u -l 6666
# NOTE: netconsole only works after the NIC driver loads. If the boot
# hangs before USB ethernet probes, you won't see those early messages.
# The 192.168.202.50 IP must match what tsbootkit assigns (check -v output).

menuentry 'NP545XLA DT — nomodeset + netconsole' {
    echo ">>> PXE Boot: DT, nomodeset, kernel log → UDP 192.168.202.5:6666"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused console=tty0 loglevel=8 nomodeset netconsole=6666@192.168.202.50/eth0,6666@192.168.202.5/
    initrd /boot/initrd.img
}

menuentry 'NP545XLA DT — nomodeset + break=top + netconsole' {
    echo ">>> PXE Boot: DT, nomodeset, initrd shell, kernel log → UDP 192.168.202.5:6666"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused console=tty0 loglevel=8 nomodeset break=top netconsole=6666@192.168.202.50/eth0,6666@192.168.202.5/
    initrd /boot/initrd.img
}

menuentry 'NP545XLA DT — nomodeset + iommu=off + netconsole' {
    echo ">>> PXE Boot: DT, nomodeset, IOMMU off, kernel log → UDP 192.168.202.5:6666"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused console=tty0 loglevel=8 nomodeset iommu=off netconsole=6666@192.168.202.50/eth0,6666@192.168.202.5/
    initrd /boot/initrd.img
}

# --- Squashfs over HTTP (full Ubuntu rootfs) ---
# Requires minimal.squashfs in pxe/tftp/boot/ (extract from Ubuntu ISO).
# The casper initrd fetches the squashfs over HTTP and uses it as rootfs.
# First boot fetches ~2GB over the network, takes ~30-60s.

menuentry 'NP545XLA DT — squashfs over HTTP' {
    echo ">>> PXE Boot: DT, nomodeset, full Ubuntu rootfs via HTTP"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused console=tty0 loglevel=8 nomodeset boot=casper netboot=url url=http://192.168.202.5:8080/boot/minimal.squashfs
    initrd /boot/initrd.img
}

menuentry 'NP545XLA DT — squashfs over HTTP + ttyMSM0' {
    echo ">>> PXE Boot: DT, nomodeset, full Ubuntu rootfs via HTTP, serial(ttyMSM0)"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused earlycon=qcom_geni,0xA90000 console=ttyMSM0,115200n8 console=tty0 loglevel=8 nomodeset boot=casper netboot=url url=http://192.168.202.5:8080/boot/minimal.squashfs
    initrd /boot/initrd.img
}

menuentry 'NP545XLA DT — squashfs over HTTP + netconsole' {
    echo ">>> PXE Boot: DT, nomodeset, full Ubuntu rootfs via HTTP, kernel log → UDP 192.168.202.5:6666"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused console=tty0 loglevel=8 nomodeset boot=casper netboot=url url=http://192.168.202.5:8080/boot/minimal.squashfs netconsole=6666@192.168.202.50/eth0,6666@192.168.202.5/
    initrd /boot/initrd.img
}

# --- ACPI fallback (no DT) ---

menuentry 'Ubuntu 26.04 (ACPI fallback)' {
    echo ">>> PXE Boot: ACPI (no DT), console=fbcon (tty0 only)"
    linux /boot/vmlinuz efi=novamap console=tty0 loglevel=8
    initrd /boot/initrd.img
}
```

---

## 3. Sync Script

```bash
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
```

---

## 4. Build GRUB Netboot Script

```bash
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
```

---

## 5. One-Shot PXE Server (`pxe-serve.sh`)

Instead of manually assigning an IP, starting a netconsole listener, and running tsbootkit in separate steps, use the wrapper script:

```bash
# From the NP545XLA-kernel repo root:
sudo bash src/pxe-serve.sh en0
```

This:
1. Assigns `192.168.202.5` to the USB ethernet interface
2. Starts a UDP listener on port 6666 for kernel netconsole output (requires `socat` or `nc`)
3. Saves netconsole output to `pxe/netconsole.log` **and** prints to stdout
4. Starts `tsbootkit-pxed` with HTTP enabled
5. Cleans up (kills listener, removes IP) on Ctrl+C

### Options

| Flag | What it does |
|------|-------------|
| `-p, --http-port PORT` | HTTP port (default: 8080) |
| `-n, --netconsole PORT` | Netconsole UDP listen port (default: 6666) |
| `--no-netconsole` | Skip the netconsole listener |
| `-v` / `-vv` / `-vvv` | Verbosity (passed to tsbootkit) |
| `--config FILE` | Use tsbootkit YAML config instead of CLI flags |

### Prerequisites

```bash
# tsbootkit (required)
npm install -g tsbootkit

# Netconsole listener (pick one):
brew install socat     # macOS — preferred, supports UDP broadcast
apt install socat      # Linux
# OR
brew install netcat    # macOS fallback
apt install netcat     # Linux fallback
```

### Quick start

```bash
# Full setup (interface auto-detected):
sudo bash src/pxe-serve.sh

# Specific interface + verbose:
sudo bash src/pxe-serve.sh en0 -vv

# No netconsole, just the PXE server:
sudo bash src/pxe-serve.sh en0 --no-netconsole

# Custom ports:
sudo bash src/pxe-serve.sh en0 --http-port 9090 --netconsole 7777
```

---

## Gotchas & Tips

### USB Ethernet Adapter Compatibility

The Samsung UEFI needs to recognize the adapter's PXE option ROM. Not all adapters expose one. Known good options for UEFI PXE on ARM:

| Adapter | Chipset | Notes |
|---------|---------|-------|
| Plugable USB-C to Gigabit Ethernet | RTL8153 | Widely supported, most UEFI firmware includes driver |
| Anker USB-C to Gigabit Ethernet | RTL8153 | Same chipset as Plugable |
| Cable Matters USB-C to Ethernet | AX88179 | ASIX chipset, less common in UEFI drivers |

**If the adapter doesn't have a UEFI driver, the PXE option won't appear in the boot menu.** Test this first — plug in the adapter, enter the Samsung boot menu (F2 or Esc at power-on), and look for a "PXE over IPv4" or "Network Boot" option.

### HTTP vs TFTP Performance

tsbootkit serves both TFTP (for the initial GRUB binary) and HTTP (for everything else) from the same root directory. Enable HTTP with `--http-port 8080`:

- **TFTP:** ~5-10 MB/s, required for the initial `BOOTAA64.EFI` load
- **HTTP:** 50-100 MB/s, used by GRUB's HTTP module for kernel, initrd, DTB

A 140MB initrd takes ~15-30s over TFTP vs ~2-3s over HTTP. **Always enable HTTP.**

GRUB's `http` module (included in our netboot build) automatically uses HTTP when the server supports it. No grub.cfg changes needed — GRUB tries the protocol it was loaded with first.

### Interface Wait (USB-Ethernet Hotplug)

USB-Ethernet adapters may not be present at daemon startup. Use `--wait` to have tsbootkit poll for the interface instead of exiting:

```bash
sudo tsbootkit-pxed en0 pxe/tftp BOOTAA64.EFI --http-port 8080 --wait --wait-timeout 30 -v
```

### Firewall

- **Linux:** `ufw` or `iptables` may block TFTP (UDP 69), DHCP (UDP 67/68), and HTTP (TCP 8080). Allow them.
- **macOS:** The built-in firewall may block these ports. Either disable it temporarily or add an exception for Node.js.

### Full Rootfs: Squashfs over HTTP

PXE boot with GRUB + TFTP/HTTP gets you the kernel and initrd — same as the ISO. The initrd still needs to mount a rootfs. For testing with `break=top`, this doesn't matter. For a full boot, use **squashfs over HTTP**: the Ubuntu casper initrd fetches a squashfs from the tsbootkit HTTP server and uses it as the root filesystem. No NFS needed.

#### Extract initrd + squashfs from the Ubuntu ISO

The Ubuntu desktop ISO has both files in `casper/`:

```bash
# macOS:
hdiutil attach src/ubuntu-26.04-desktop-arm64.iso -mountpoint /tmp/ubuntu-iso
cp /tmp/ubuntu-iso/casper/initrd output/initrd.img
cp /tmp/ubuntu-iso/casper/minimal.squashfs pxe/tftp/boot/
hdiutil detach /tmp/ubuntu-iso

# Linux:
sudo mount -o loop src/ubuntu-26.04-desktop-arm64.iso /tmp/ubuntu-iso
cp /tmp/ubuntu-iso/casper/initrd output/initrd.img
cp /tmp/ubuntu-iso/casper/minimal.squashfs pxe/tftp/boot/
sudo umount /tmp/ubuntu-iso
```

> **Note:** Don't use `7z` to extract from the ISO — it doesn't handle the
> ISO9660 rock ridge extensions properly and will find 0 files. Use `hdiutil`
> (macOS) or `mount -o loop` (Linux) instead.

Then `bash src/sync-pxe.sh` picks up the initrd and copies it into the TFTP root.

#### Add a squashfs GRUB entry

Add this to `src/grub-pxe.cfg` (or any custom config):

```cfg
menuentry 'NP545XLA DT — squashfs over HTTP' {
    echo ">>> PXE Boot: DT, nomodeset, full Ubuntu rootfs via HTTP"
    devicetree /boot/dtb/qcom/sc8180xp-samsung-np545xla.dtb
    linux /boot/vmlinuz efi=novamap clk_ignore_unused console=tty0 loglevel=8 nomodeset boot=casper netboot=url url=http://192.168.202.5:8080/boot/minimal.squashfs
    initrd /boot/initrd.img
}
```

The squashfs is ~2GB — the first HTTP fetch takes ~30-60s over USB ethernet, but only happens once per boot. After that, the full Ubuntu desktop environment is live.

#### Alternative: NFS root

If HTTP squashfs is too slow, NFS root avoids the large transfer:

```cfg
linux /boot/vmlinuz efi=novamap clk_ignore_unused console=tty0 loglevel=8 nomodeset root=/dev/nfs nfsroot=192.168.202.5:/srv/pxe/rootfs
```

Requires an NFS server and a rootfs extracted from the squashfs. More setup, faster per-boot after the initial extraction.

#### For iteration, just use break=top

For kernel/DTB development, the initrd shell is all you need. Full rootfs boot is for when you want to test userspace drivers or the desktop environment.

### DHCP Architecture Filtering

By default, `tsbootkit-pxed` only responds to PXE DHCP requests (clients that set the PXE vendor class). This is the right behavior — it won't interfere with other DHCP clients on the same network.

If you need it to answer all DHCP requests (e.g., the Samsung's PXE ROM doesn't set the PXE vendor class correctly), use `--answer-all`:

```bash
sudo tsbootkit-pxed en0 pxe/tftp BOOTAA64.EFI --answer-all -v
```

### Static Reservations

To always assign the same IP to the Samsung (useful for netconsole), add a reservation via config:

```bash
sudo tsbootkit-pxed en0 pxe/tftp BOOTAA64.EFI --http-port 8080 -v \
    --config src/tsbootkit.yaml
```

With `src/tsbootkit.yaml`:
```yaml
reservations:
  - mac: XX:XX:XX:XX:XX:XX
    ip: 192.168.202.50
```

---

## 6. USB-HTTP Hybrid Boot (Path B)

If you don't have the Samsung OEM adapter (AA-AM1N95W), native PXE won't work — the Samsung UEFI only includes UNDI drivers for that specific adapter's USB VID:PID. Generic RTL8153 dongles use Realtek's VID (0bda:8153), and the firmware has no matching driver, so no PXE boot option appears.

The workaround: **boot GRUB from a USB stick, but load everything else over HTTP.** The USB stick is a one-time setup — GRUB reads its config and fetches kernel/initrd/DTB over the network from tsbootkit. After that, every kernel/DTB change is just a file update on the server.

### How it works

```
┌─────────────────────┐     USB stick      ┌────────────────────┐
│  Dev machine         │    (GRUB only)     │  Samsung NP545XLA   │
│  tsbootkit-pxed      │                    │  UEFI boots USB     │
│  (HTTP only)         │◄── USB-Ethernet ──►│  GRUB loads via HTTP│
│  192.168.202.5:8080  │                    │  kernel/initrd/DTB  │
└─────────────────────┘                    └────────────────────┘
```

1. Samsung UEFI boots from USB stick → GRUB starts
2. GRUB loads `grub.cfg` over HTTP from `192.168.202.5:8080`
3. GRUB fetches kernel, initrd, and DTB over HTTP
4. Boots — same as PXE, but the bootloader came from USB instead of TFTP

### Build the USB-HTTP boot image

The script produces a `.img` file inside the Docker container. No USB device passthrough needed — just flash the image from macOS afterwards.

```bash
# Inside the Docker container (or any Linux box with grub-efi-arm64-bin):
bash src/build-usb-http-stick.sh
# → pxe/usb-http-stick.iso (El Torito EFI boot ISO)
```

Then on macOS, flash it to a USB stick:

```bash
diskutil list                         # find the USB disk (e.g. /dev/disk4)
diskutil unmountDisk /dev/disk4       # unmount it
sudo dd if=pxe/usb-http-stick.iso of=/dev/disk4 bs=4M
```

Or use **Balena Etcher** — just drag the `.iso` file in. No command line needed.

The ISO uses the same El Torito + appended ESP technique as the full boot ISO — the Samsung UEFI will see it. It contains only GRUB + a 3-line `grub.cfg` that redirects to the HTTP server. One-time flash, never re-burn.

### Server setup for Path B

Path B doesn't need DHCP or TFTP — only the HTTP server. Start tsbootkit with HTTP enabled:

```bash
# Assign IP on the dev machine
sudo ip addr add 192.168.202.5/24 dev en0

# Start tsbootkit (HTTP serves files, DHCP/TFTP aren't needed but don't hurt)
sudo tsbootkit-pxed en0 pxe/tftp BOOTAA64.EFI --http-port 8080 -v
```

Then boot the Samsung from the USB stick. GRUB will:
1. Read `grub.cfg` from the USB stick (which points to the HTTP server)
2. Load the full menu from `http://192.168.202.5:8080/boot/grub/grub.cfg`
3. Fetch kernel/initrd/DTB over HTTP

### Advantages over native PXE

- **Works with any RTL8153 adapter** — no Samsung OEM adapter needed
- **Same iteration speed** — kernel/DTB updates are server-side, no re-flashing
- **USB stick is one-time setup** — only contains GRUB + a 3-line config
- **No DHCP dependency** — the Samsung gets an IP from tsbootkit's DHCP after the kernel boots (for netconsole, SSH, etc.)

---

## Setup Checklist

### Path A: Native PXE (requires Samsung OEM adapter AA-AM1N95W)

- [ ] **Test USB ethernet adapter** — plug in, check Samsung boot menu for PXE option
- [ ] **Install tsbootkit** — `npm install -g tsbootkit`
- [ ] **Build or download BOOTAA64.EFI** — place in `pxe/tftp/`
- [ ] **Sync build artifacts to PXE root** — `bash src/sync-pxe.sh`
- [ ] **Identify USB ethernet interface** — `ip -br link` (Linux) or `ifconfig` (macOS)
- [ ] **Assign static IP** — `sudo ip addr add 192.168.202.5/24 dev en0` (Linux) or `sudo ifconfig en0 192.168.202.5 netmask 255.255.255.0 up` (macOS)
- [ ] **Run tsbootkit-pxed** — `sudo tsbootkit-pxed en0 pxe/tftp BOOTAA64.EFI --http-port 8080 -v`
- [ ] **Boot Samsung** — F2/Esc → PXE over IPv4
- [ ] **Celebrate** 🎉

### Path B: USB-HTTP hybrid (any RTL8153 adapter)

- [ ] **Install tsbootkit** — `npm install -g tsbootkit`
- [ ] **Build USB-HTTP boot image** — `bash src/build-usb-http-stick.sh` (in Docker)
- [ ] **Flash ISO to USB stick** — `dd if=pxe/usb-http-stick.iso of=/dev/diskN bs=4M` (on macOS)
- [ ] **Connect USB ethernet adapter** — any RTL8153 dongle (doesn't need PXE ROM support)
- [ ] **Start tsbootkit HTTP server** — `tsbootkit-pxed en0 pxe/tftp BOOTAA64.EFI --http-port 8080 -v`
- [ ] **Boot Samsung** — F2/Esc → USB drive → GRUB loads kernel/initrd/DTB over HTTP
- [ ] **Celebrate** 🎉

---

## Iteration Workflow

Once network boot is working (either path), the dev cycle becomes:

1. Edit kernel config / DTS / whatever in NP545XLA-kernel
2. `docker run ... build.sh all` (or just `kernel` / `dtbs`)
3. `bash src/sync-pxe.sh` — copies to TFTP/HTTP root
4. Reboot Samsung → network boot → new kernel loads automatically

No ISO rebuilding. Just update the files and reboot. 💅
