export CROSS_COMPILE	:= aarch64-linux-gnu-

TARGETS		:= output/u-boot-sunxi-image.spl output/busybox components/linux/arch/arm64/boot/Image

.PHONY: all
all: $(TARGETS)

# ATF
components/arm-trusted-firmware/build/sun50iw1p1/release/bl31.bin:
	cd components/arm-trusted-firmware && make -j4 PLAT=sun50iw1p1 DEBUG=0 bl31

# U-Boot
components/u-boot/spl/sunxi-spl.bin components/u-boot/u-boot.itb: components/arm-trusted-firmware/build/sun50iw1p1/release/bl31.bin components/u-boot/.config
	export BL31=components/arm-trusted-firmware/build/sun50iw1p1/release/bl31.bin && cd components/u-boot && make -j4

output/u-boot-sunxi-image.spl: components/u-boot/spl/sunxi-spl.bin components/u-boot/u-boot.itb
	cat components/u-boot/spl/sunxi-spl.bin components/u-boot/u-boot.itb > $@

components/u-boot/.config: config/uboot.config
	cp $< $@
	cd components/u-boot && make olddefconfig

# Busybox
output/busybox: components/busybox/busybox
	cp $< $@

components/busybox/busybox: components/busybox/.config
	cd components/busybox && make -j4

components/busybox/.config: config/busybox.config
	cp $< $@
	cd components/busybox && yes "" | make oldconfig

# Kernel
components/linux/.config: export ARCH=arm64
components/linux/.config: config/kernel.config
	cp $< $@
	cd components/linux && make olddefconfig

components/linux/arch/arm64/boot/Image: export ARCH=arm64
components/linux/arch/arm64/boot/Image: components/linux/.config
	cd components/linux && make -j5 bindeb-pkg KBUILD_IMAGE=arch/arm64/boot/Image
