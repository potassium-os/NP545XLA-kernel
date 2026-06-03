# startup.nsh — NP545XLA USB-HTTP boot
# Auto-executed by the UEFI Shell when it starts.
# Loads the ASIX AX88179 UEFI driver, then chainloads GRUB.

# Try to load the ASIX driver from the ESP
# fs0 is usually the first FAT partition (our ESP)
load FS2:\EFI\drivers\Ax88179Aa64.efi

# Chainload GRUB — it should now see the NIC via efinet
FS2:\EFI\grub\BOOTAA64.EFI
