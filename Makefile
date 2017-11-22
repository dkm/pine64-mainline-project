export CROSS_COMPILE	:= aarch64-linux-gnu-
export ARCH		:= arm64

TARGETS		:= output/rootfs output/busybox

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
components/linux/.config: config/kernel.config
	cp $< $@
	cd components/linux && make olddefconfig

components/linux/arch/arm64/boot/Image: components/linux/.config
	cd components/linux && make -j5 bindeb-pkg KBUILD_IMAGE=arch/arm64/boot/Image

# Rootfs
output/rootfs: output/pine64.img output/u-boot-sunxi-image.spl
	mkdir -p output/rootfs
	$(eval LOOPD := $(shell sudo losetup -f -P --show $<))
	sudo mkfs.ext2 $(LOOPD)p1
	sudo mkfs.ext4 $(LOOPD)p2
	sudo mount $(LOOPD)p2 $@
	sudo qemu-debootstrap --arch=arm64 --variant=minbase stretch $@ "http://ftp.debian.org/debian" --include="iproute2,systemd-sysv,ntp,udev,vim,sudo,openssh-server,ifupdown,isc-dhcp-client,kmod,apt-transport-https,ca-certificates"
	sudo mount $(LOOPD)p1 $@/boot
	sudo cp -rvp overlay/* $@/
	sudo rm $@/etc/machine-id
	sudo rm $@/etc/ssh/ssh_host_*
	sudo mkdir -p $@/boot/extlinux
	sudo chroot $@ apt-get update
	sudo chroot $@ useradd -s /bin/bash -m pine
	sudo chroot $@ usermod -aG sudo pine
	echo "pine:julien1234" | sudo chroot $@ /usr/sbin/chpasswd
	sync
	sudo umount $@/boot $@/
	sudo losetup -d $(LOOPD)
	dd conv=notrunc if=output/u-boot-sunxi-image.spl of=$< bs=8k seek=1

# Image
output/pine64.img: config/partitions
	dd if=/dev/zero of=$@ bs=1G count=4
	/sbin/sfdisk $@ < config/partitions
