export CROSS_COMPILE	:= aarch64-linux-gnu-
export ARCH		:= arm64

TARGETS		:= output/rootfs

.PHONY: all
all: $(TARGETS)

.PHONY: clean
clean:
	rm -rf output
	cd components/arm-trusted-firmware && make clean
	cd components/u-boot && make mrproper
	cd components/linux && make mrproper


# ATF
components/arm-trusted-firmware/build/sun50iw1p1/release/bl31.bin:
	cd components/arm-trusted-firmware && make -j4 PLAT=sun50iw1p1 DEBUG=0 bl31

# U-Boot
components/u-boot/spl/sunxi-spl.bin components/u-boot/u-boot.itb: components/arm-trusted-firmware/build/sun50iw1p1/release/bl31.bin components/u-boot/.config
	export BL31=$(PWD)/components/arm-trusted-firmware/build/sun50iw1p1/release/bl31.bin && cd components/u-boot && make -j4

output/u-boot-sunxi-image.spl: components/u-boot/spl/sunxi-spl.bin components/u-boot/u-boot.itb
	cat components/u-boot/spl/sunxi-spl.bin components/u-boot/u-boot.itb > $@

components/u-boot/.config: config/u-boot.config
	cp $< $@
	cd components/u-boot && make olddefconfig

# Kernel
components/linux/.config: config/kernel.config
	cp $< $@

components/linux/include/config/kernel.release: components/linux/.config
	cd components/linux && make olddefconfig

components/linux/arch/arm64/boot/Image: components/linux/include/config/kernel.release
	cd components/linux && make -j5 bindeb-pkg KBUILD_IMAGE=arch/arm64/boot/Image
	mv components/linux-*`cat $<`* output/

.PHONY: linux-image-pine64
linux-image-pine64: components/linux/include/config/kernel.release components/linux/arch/arm64/boot/Image
	cd linux-image-pine64 && ./update.sh `cat ../$<`
	mv linux-image-pine64_* output/

# Rootfs
output/rootfs: output/pine64.img output/u-boot-sunxi-image.spl linux-image-pine64
	mkdir -p output/rootfs
	$(eval LOOPD := $(shell sudo losetup -f -P --show $<))
	sudo mkfs.ext2 $(LOOPD)p1
	sudo mkfs.ext4 $(LOOPD)p2
	sudo mount $(LOOPD)p2 $@
	sudo qemu-debootstrap --arch=arm64 --merged-usr --variant=minbase stretch $@ "http://ftp.debian.org/debian" --include="iproute2,systemd-sysv,ntp,udev,vim,sudo,openssh-server,ifupdown,isc-dhcp-client,kmod,apt-transport-https,ca-certificates,locales,usbutils" --exclude="sysv-rc,initscripts,startpar,lsb-base,insserv"
	echo "en_US.UTF-8 UTF-8" >> ${ROOT}/etc/locale.gen
	sudo chroot $@ locale-gen
	sudo mount $(LOOPD)p1 $@/boot
	sudo cp -rvp overlay/* $@/
	sudo rm $@/etc/machine-id
	sudo rm $@/etc/ssh/ssh_host_*
	sudo mkdir -p $@/boot/extlinux
	sudo chroot $@ apt-get update
	sudo chroot $@ apt-get --assume-yes --no-install-recommends install dbus libpam-systemd
	sudo chroot $@ useradd -s /bin/bash -m pine
	sudo chroot $@ usermod -aG sudo pine
	echo "pine:julien1234" | sudo chroot $@ /usr/sbin/chpasswd
	sudo cp output/linux-image*.deb output/rootfs/tmp/
	sudo chroot $@ sh -c 'dpkg -i /tmp/linux-image*.deb' 
	sync
	sudo umount $@/boot $@/
	sudo losetup -d $(LOOPD)
	dd conv=notrunc if=output/u-boot-sunxi-image.spl of=$< bs=8k seek=1
	touch output/rootfs

# Image
output/pine64.img: config/partitions
	mkdir -p output
	dd if=/dev/zero of=$@ bs=1G count=4
	/sbin/sfdisk $@ < config/partitions

