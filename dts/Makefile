# Build DTB for Samsung Galaxy Book Go 5G (NP545XLA)
#
# Uses the kernel tree's dtc for proper preprocessing and validation.
# Run `make dtc` first if the kernel dtc hasn't been built yet.
#
# Usage:
#   make            # build DTB
#   make dtc        # build kernel dtc (first time only)
#   make clean

KERNEL_DIR ?= $(shell pwd)/../submodules/linux
DTC = $(KERNEL_DIR)/scripts/dtc/dtc
CC ?= gcc

DTS = sc8180xp-samsung-np545xla.dts
DTB = sc8180xp-samsung-np545xla.dtb

CPP_FLAGS = \
	-nostdinc \
	-I$(KERNEL_DIR)/arch/arm64/boot/dts \
	-I$(KERNEL_DIR)/arch/arm64/boot/dts/qcom \
	-I$(KERNEL_DIR)/include \
	-I$(KERNEL_DIR)/include/dt-bindings \
	-undef -D__DTS__

DTC_FLAGS = -@ -W no-unit_address_vs_reg

all: $(DTB)

$(DTC):
	$(MAKE) -C $(KERNEL_DIR) ARCH=arm64 scripts_dtc

%.dtb: %.dts $(DTC)
	$(CC) -E -P -x assembler-with-cpp $(CPP_FLAGS) -I$(shell pwd) -o $*.dts.pre $<
	$(DTC) $(DTC_FLAGS) -o $@ $*.dts.pre
	@rm -f $*.dts.pre

clean:
	rm -f *.dtb *.dts.pre

.PHONY: all clean
