#!/bin/bash
 
set -x
 
#
#
apt-get install libssl0.9.8

mount -o ro /dev/mmcblk0p3 /mnt
cp /mnt/usr/bin/vbutil_* /usr/bin
mkdir -p /usr/share/vboot
rsync -avz /mnt/usr/share/vboot/ /usr/share/vboot
cp /mnt/usr/bin/dump_kernel_config /usr/bin
umount /mnt
 

vbutil_kernel --verify /dev/mmcblk1p1
 
#
# Fetch ChromeOS kernel sources from the Git repo.
#
apt-get install git-core
cd /usr/src
git clone  https://git.chromium.org/git/chromiumos/third_party/kernel.git
cd kernel
git checkout origin/chromeos-3.4





#
# Configure the kernel
#
# First we patch ``base.config`` to set ``CONFIG_SECURITY_CHROMIUMOS``
# to ``n`` ...
cp ./chromeos/config/base.config ./chromeos/config/base.config.orig
sed -e \
  's/CONFIG_SECURITY_CHROMIUMOS=y/CONFIG_SECURITY_CHROMIUMOS=n/' \
  ./chromeos/config/base.config.orig > ./chromeos/config/base.config2

sed -e \
  's/CONFIG_WIRELESS_EXT=n/CONFIG_WIRELESS_EXT=y/' \
  ./chromeos/config/base.config2 > ./chromeos/config/base.config


./chromeos/scripts/prepareconfig chromeos-exynos5


#
# ... and then we proceed as per Olaf's instructions
#
yes "" | make oldconfig
 
#
# Build the Ubuntu kernel packages
#
apt-get install kernel-package u-boot-tools

#Run the make tools
make kpkg kernel_image kernel_headers dtbs
cp arch/arm/boot/dts/*.dtb /boot




mkimage -f kernel.its kernel.itb



 
#
# Backup current kernel and kernel modules
#
tstamp=$(date +%Y-%m-%d-%H%M)
dd if=/dev/mmcblk1p1 of=/kernel-backup-$tstamp
cp -Rp /lib/modules/3.4.0 /lib/modules/3.4.0-backup-$tstamp
 

 
#
# Extract old kernel config
#
vbutil_kernel --verify /dev/mmcblk1p1 --verbose | tail -1 > /config-$tstamp-orig.txt
#
# Add ``disablevmx=off`` to the command line, so that VMX is enabled (for VirtualBox & Co)
#
echo "console=tty1 debug root=/dev/mmcblk1p3 rw rootwait" > config.txt

 
#
# Wrap the new kernel with the verified block and with the new config.
#
vbutil_kernel --pack /tmp/newkernel \
  --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
  --version 1 \
  --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
  --config=config.txt \
  --vmlinuz kernel.itb \
  --arch arm
 
#
# Make sure the new kernel verifies OK.
#
vbutil_kernel --verify /newkernel
 
#
# Copy the new kernel to the KERN-C partition.
#
dd if=/newkernel of=/dev/mmcblk1p2


#For partition index 2 (mmcblk1p2), set priority to 15,
#successful to 0 and tries to 1. Since the first partition has priority
#10, it means this will be tried first, as long as the tries counter is >0.

cgpt add -i 2 -P 15 -S 0 -T 1 /dev/mmcblk1
