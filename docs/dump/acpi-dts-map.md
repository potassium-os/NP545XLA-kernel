# NP545XLA ACPI → DTS Mapping
# Extracted from Windows ACPI dump (DSDT)

## I2C Bus → DTS Node Mapping

| ACPI | Base Address | QUP Wrapper | SE# | dtsi node | Devices |
|------|-------------|-------------|-----|-----------|---------|
| I2C1 | 0x00880000 | QUP0 | SE0 | `i2c0` | TCPD (USB-C PD, addr 0x40) |
| I2C2 | 0x00884000 | QUP0 | SE1 | `i2c1` | ECTC (touchpad, addr 0x62) |
| I2C5 | 0x00890000 | QUP0 | SE4 | `i2c4` | (unknown) |
| I2C6 | 0x00894000 | QUP0 | SE5 | `i2c5` | SAR1 (proximity, addr 0x20) |
| I2C9 | 0x00A80000 | QUP1 | SE4 | `i2c9` | ECKB (keyboard, addr 0x05) |
| IC10 | 0x00A84000 | QUP1 | SE5 | `i2c10` | (unknown) |
| IC12 | 0x00A8C000 | QUP1 | SE6 | `i2c11` | (unknown) |
| IC15 | 0x00C90000 | QUP2 | SE3 | `i2c15` | (unknown) |
| IC18 | 0x00C80000 | QUP2 | SE0 | `i2c18` | SAR2 (proximity, addr 0x20) |
| IC19 | 0x00C84000 | QUP2 | SE1 | `i2c19` | (unknown) |
| IC20 | 0x00C88000 | QUP2 | SE2 | `i2c20` | (unknown) |

## I2C Devices (Samsung-Specific)

### Keyboard (ECKB)
- HID: SSEC0001 / CID: PNP0C50 (hid-over-i2c)
- Bus: I2C9 → &i2c9 (QUP1 SE4)
- Address: 0x05
- IRQ: ACPI gpio640 (controller=\_SB.GIO0) → **NEEDS VERIFICATION**
  - ACPI pin 640 is beyond TLMM range (0-191)
  - Possible DT mapping: gpio64 or gpio128 — verify at runtime
  - Lenovo Flex 5G uses gpio37 on i2c7

### Touchpad (ECTC)
- HID: SAM060B
- Bus: I2C2 → &i2c1 (QUP0 SE1)
- Address: 0x62
- IRQ: gpio118 (TLMM, valid)
- Subsystem ID: C1A1144D

### USB-C PD Controller (TCPD)
- HID: SSTP0001 / CID: PNP0C50
- Bus: I2C1 → &i2c0 (QUP0 SE0)
- Address: 0x40
- IRQ: ACPI gpio448 (controller=\_SB.GIO0) → **NEEDS VERIFICATION**

### SAR Proximity Sensor 1 (SAR1)
- HID: SAMM0209
- Bus: I2C6 → &i2c5 (QUP0 SE5)
- Address: 0x20
- IRQ: gpio93 (TLMM, valid)

### SAR Proximity Sensor 2 (SAR2)
- HID: SAMM0209
- Bus: IC18 → &i2c18 (QUP2 SE0)
- Address: 0x20
- IRQ: gpio87 (TLMM, valid)

## GPIO Pin Assignments (from DSDT)

| GPIO Pin | Function | Source |
|----------|----------|--------|
| 9 | SCM0 IRQ (GIO0) | GIO0 _CRS |
| 22 | MCTL sensor GPIO | MCTL _CRS |
| 25 | SSPN GPIO | SSPN _CRS |
| 33 | MCTL sensor GPIO | MCTL _CRS |
| 34 | MCTL sensor GPIO | MCTL _CRS |
| 50 | LID switch (read via LIDR field) | GIO0.GPOR |
| 83 | MCTL sensor GPIO | MCTL _CRS |
| 87 | SAR2 IRQ | SAR2 _CRS |
| 93 | SAR1 IRQ | SAR1 _CRS |
| 118 | Touchpad IRQ | ECTC _CRS |
| 120 | SSPN IRQ (active-both) | SSPN _CRS |
| 126 | MCTL sensor IRQ (active-both) | MCTL _CRS |
| 127 | MCTL sensor GPIO | MCTL _CRS |
| 129 | UR03 UART IRQ | UR03 _CRS |
| 130 | SSPN GPIO | SSPN _CRS |
| 131 | MCTL sensor GPIO | MCTL _CRS |
| 132 | MCTL sensor IRQ (active-both) | MCTL _CRS |
| 133 | MCTL sensor GPIO | MCTL _CRS |
| 166 (0xA6) | Camera enable (output, GIO0) | GIO0.GPO2 |
| 189 | GIO0 IRQ | GIO0 _CRS |
| PM01 gpio0 | Power key (BTNS) | BTNS _CRS |
| PM01 gpio677 | MCTL sensor GPIO | MCTL _CRS |
| PM01 gpio528 | MCTL sensor GPIO | MCTL _CRS |

## UARTs

| ACPI | Base | IRQ Pin | DTS Mapping |
|------|------|---------|-------------|
| UR03 | 0x00888000 | gpio129 | QUP0 SE? |
| UARD | 0x00A90000 | gpio86 | **UART12** (QUP1 SE10) ✅ CONFIRMED |
| UR18 | 0x00C8C000 | gpio46 | QUP2 SE3 |
| UR20 | 0x00C94000 | gpio30 | QUP2 SE4 |

## PCIe

| ACPI | Base | DTS Node | Function |
|------|------|----------|----------|
| PCI0 | 0x60200000 | &pcie0 | |
| PCI1 | 0x68200000 | &pcie1 | |
| PCI2 | 0x70200000 | &pcie2 | **WiFi** (PNID=2) |
| PCI3 | 0x40200000 | &pcie3 | |

PCIe GPIOs (QPPX):
- gpio35: PERST/config
- gpio175: PERST/config
- gpio102: PERST/config  
- gpio178: PERST (confirmed from Lenovo DTS)

PCIe2 wake: ACPI pin 576 (gpio576 - PMIC?)
PCIe2 IRQ: ACPI pin 448 (same as TCPD - likely PMIC)
PCIe3 IRQ: ACPI pin 512 (gpio512 - PMIC?)

## UFS / Storage

| ACPI | Base | Notes |
|------|------|-------|
| UFS0 | 0x01D84000 | Main UFS controller ✅ |
| UFS1.DEV0 | 0x01D64000 | UFS PHY wrapper |
| SDC2 | 0x08804000 | SD card slot (gpio192 RST, gpio96) |

## WiFi (QWLN)
- HID: QCOM041E
- Base: 0x18800000 (matches dtsi wifi@18800000)
- Memory: 0x0C250000 (config), 0x8BC00000 (wlan_mem)
- On PCIe2 (PNID=2)

## Remoteprocs
- ADSP: QCOM041D, base 0x17300000
- CDSP: QCOM0423
- MPSS/AMSS: QCOM041E (same HID as WiFi? No, different device)
  - SLM1: 0x171C0000, SLM2: 0x17240000 (subsys regs)

## GPU
- GPU0: QCOM043A
- AVS0: QCOM043A (Adaptive Voltage Scaling)
- Display clocks reference: disp_cc_mdss_edp_pixel_clk, link_clk, gtc_clk, aux_clk

## LID Switch
- ACPI: LID0, HID: PNP0C0D
- Read via GIO0.LIDR field on gpio50 (0x32)
- Our DTS has gpio50 ✅ CORRECT
- Lenovo uses gpio121 (DIFFERENT — Samsung-specific)

## Samsung Platform (SSPN)
- HID: SAM0101, SUB: C1A1144D
- Controls: CABL (panel backlight enable/disable)
- GPIOs: 25, 130, 120 (active-both IRQ)

## Embedded Controller (EMEC)
- Has CHGS (charge status), CHTY (charger type), CCST, CCS2, HPDS, PINA
- USB-C role switching likely controlled through this

## ACPI GPIO Numbering Mystery
- gpio640 (keyboard) and gpio448 (USB-C PD) are beyond TLMM's 192-pin range
- Both reference controller=\_SB.GIO0 (QCOM040D = TLMM)
- Hypothesis 1: Samsung ACPI uses tile-based offset (west=0, east=256, south=512)
  - 640 = south tile + 128 → out of range for a 64-pin tile
  - 448 = east tile + 192 → out of range for a 64-pin tile
- Hypothesis 2: 640 % 192 = 64, 448 % 192 = 64 → both map to TLMM gpio64
  - Unlikely that both devices share the same pin
- Hypothesis 3: These are PMIC GPIOs accessed through GIO0
  - pmc8180c GPIOs might start at 448, pmc8180 at 256
  - 640 - 448 = 192 → still out of PMIC range (typically 9-12 GPIOs)
- **NEEDS RUNTIME VERIFICATION**: boot with `gpiolib-acpi` debug and check pin mapping

## Reserved GPIO Ranges
- Our DTS: `<0 4>, <47 4>` (gpio0-3, gpio47-50)
- Lenovo DTS: `<0 4>, <47 4>, <126 4>` (gpio0-3, gpio47-50, gpio126-129)
- Samsung has gpio126 used by MCTL → NOT reserved on Samsung
- Samsung has gpio50 used by LID → NOT in reserved range (47-50 overlaps!)
- **FIX NEEDED**: Remove `<47 4>` from gpio-reserved-ranges since gpio50 is our LID pin
