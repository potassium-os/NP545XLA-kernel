# NP545XLA DT — Open Questions

## ✅ UART12 Pin Mapping (RESOLVED)

**uart12** at `0xA90000` (QUP1 SE10) uses **gpio83 (TX) + gpio84 (RX)**, function `qup12`.

Verified from `drivers/pinctrl/qcom/pinctrl-sc8180x.c`:
```
qup12_groups = { "gpio83", "gpio84", "gpio85", "gpio86" }
```
2-wire UART: gpio83=TX, gpio84=RX. gpio85/86 are CTS/RTS (unused in 2-wire mode).

ACPI cross-check: UARD GpioInt pin 86 maps to physical TLMM gpio86 (SE10 lane 3 / RTS), which is consistent.

## Reserved Memory Regions

The reserved-memory block is copied from the Lenovo Flex 5G. Samsung's board may have different region sizes or addresses. If the bootloader provides its own reserved-memory (UEFI does via EFI memory map), the DT entries with `no-map` might conflict.

**For Phase 1:** Start with the Lenovo values. If the kernel complains about reserved-memory overlaps, adjust.

## SC8180XP vs SC8180X

We're using `compatible = "qcom,sc8180x"` in the board DTS. The 'P' variant difference is "no integrated modem." In the DT, the modem is the `remoteproc_mpss` node. For Phase 1, we're not enabling it, so this doesn't matter. When we add WiFi (which goes through the modem/WPSS on some configurations), we'll need to verify the modem path.

## I2C Bus Mapping (ACPI → DT)

From the ACPI dump:
| ACPI Device | _HID | I2C Bus (ACPI) | Addr | DT Node |
|-------------|------|----------------|------|---------|
| TCPD | SSTP0001 | I2C1 | 0x40 | &i2c1 |
| ECTC | SAM060B | I2C2 | 0x62 | &i2c2 |
| SAR1 | SAMM0209 | I2C6 | 0x20 | &i2c6 |
| ECKB | SSEC0001 | I2C9 | 0x05 | &i2c9 |
| SAR2 | SAMM0209 | IC18 | 0x20 | &i2c18 |

The ACPI I2C numbering may not match the dtsi I2C node numbering. The dtsi has i2c0 through i2c18 in QUP0/1/2. Need to cross-reference ACPI I2C controller base addresses with the dtsi QUP serial engine addresses.

**From the CRS dump:**
- UARD (debug UART): base 0xA90000 → uart12, QUP1 SE10 ✓
- Other UARTs at 0x888000, 0xC8C000, 0xC94000 → need mapping

## Firmware Paths

The Lenovo DTS references firmware files like `qcom/sc8180x/LENOVO/82AK/qcadsp8180.mbn`. Samsung's board will need different firmware paths. For Phase 1, we're not enabling remoteprocs, so this is deferred.

WiFi firmware (ath11k) is in `linux-firmware` and should work without board-specific paths.

## UFS Reset GPIO

The board DTS has `reset-gpios = <&tlmm 190 GPIO_ACTIVE_LOW>` for UFS, copied from the Lenovo Flex 5G. This pin may differ on the Samsung board. If UFS doesn't come up, this is a suspect.
