#!/bin/sh

process() {
    echo -e "\033[1;32m $1 \033[0m"
}

error() {
    echo -e "\033[1;31m Error:\033[0m $1"
}

emmc=$(lsblk | grep -oE 'mmcblk[0-9]' | sort | uniq)
sd=$(lsblk | grep -oE 'sd[a-z]' | sort | uniq)
[ $emmc ] || {
    error "no emmc found!" && exit 1
}
[ $sd ] || {
    error "no usb device found!" && exit 1
}

sd=$(lsblk | grep -w '/' | grep -oE 'sd[a-z]')
[ $sd ] || sd=$(lsblk | grep -w '/overlay' | grep -oE 'sd[a-z]')
[ $sd ] || {
    error "you are running in emmc mode, please boot system with usb!" && exit 1
}

dev_emmc="/dev/$emmc"
dev_sd="/dev/$sd"

echo " emmc: $dev_emmc"
echo " usb:  $dev_sd"

process "dependency check..."
# opkg install ipk/*.ipk --force-depends
if ! (lsblk --help >/dev/null 2>&1); then
    opkg install ipk/lsblk*.ipk --force-depends
fi
if ! (blkid --help >/dev/null 2>&1); then
    opkg install ipk/*blkid*.ipk --force-depends
fi
if ! (parted --help >/dev/null 2>&1); then
    opkg install ipk/parted*.ipk --force-depends
fi
if ! (mkfs.fat --help >/dev/null 2>&1); then
    opkg install ipk/dosfstools*.ipk --force-depends
fi
if ! (mke2fs -V >/dev/null 2>&1); then
    opkg install ipk/e2fsprogs*.ipk --force-depends
fi

if (blkid -L "BOOT_EMMC" && blkid -L "ROOT_EMMC") >/dev/null 2>&1; then
    installed=true
fi

if (grep -q $dev_emmc /proc/mounts); then
    process "umount emmc..."
    umount -f ${dev_emmc}p* >/dev/null 2>&1
fi

part_boot="${dev_emmc}p1"
part_root="${dev_emmc}p2"

if [ ! $installed ]; then
    process "backup u-boot..."
    dd if=$dev_emmc of=u-boot.img bs=1M count=4

    process "create mbr and partition..."
    parted -s $dev_emmc mklabel msdos
    parted -s $dev_emmc mkpart primary fat32 700M 1212M
    parted -s $dev_emmc mkpart primary ext4 1213M 100%

    process "restore u-boot..."
    dd if=u-boot.img of=$dev_emmc conv=fsync bs=1 count=442
    dd if=u-boot.img of=$dev_emmc conv=fsync bs=512 skip=1 seek=1

    sync

    process "format boot partiton..."
    mkfs.fat -F 32 -n "BOOT_EMMC" $part_boot

    process "format root partiton..."
    mke2fs -t ext4 -F -q -L 'ROOT_EMMC' -m 0 $part_root
    e2fsck -n $part_root
fi

ins_boot="/install/boot"
ins_root="/install/root"

mkdir -p -m 777 $ins_boot $ins_root

process "mount bootfs..."
mount -t vfat $part_boot $ins_boot
rm -rf $ins_boot/*

process "copy bootable file..."
grep -q 'BOOT' /proc/mounts || mount -t vfat ${dev_sd}1 /boot
cp -r /boot/* $ins_boot
sync

sed -i 's/ROOTFS/ROOT_EMMC/' $ins_boot/uEnv.txt

rm -f $ins_boot/s9*
rm -f $ins_boot/aml*
rm -f $ins_boot/boot.ini
mv -f $ins_boot/boot-emmc.scr $ins_boot/boot.scr

if [ -f /boot/u-boot.ext ]; then
    mv -f $ins_boot/u-boot.sd $ins_boot/u-boot.emmc
    mv -f $ins_boot/boot-emmc.ini $ins_boot/boot.ini
    sync
fi

process "umount bootfs..."
umount -f $part_boot

process "mount rootfs..."
mount -t ext4 $part_root $ins_root
rm -rf $ins_root/*

process "copy rootfs..."

cd /
echo "  - copy bin..."
tar -cf - bin | (cd $ins_root && tar -xpf -)
echo "  - copy etc..."
tar -cf - etc | (cd $ins_root && tar -xpf -)
echo "  - copy lib..."
tar -cf - lib | (cd $ins_root && tar -xpf -)
echo "  - copy root..."
tar -cf - root | (cd $ins_root && tar -xpf -)
echo "  - copy sbin..."
tar -cf - sbin | (cd $ins_root && tar -xpf -)
echo "  - copy usr..."
tar -cf - usr | (cd $ins_root && tar -xpf -)
echo "  - copy www..."
tar -cf - www | (cd $ins_root && tar -xpf -)

[ -f init ] && cp -a init $ins_root

cd $ins_root
echo "  - create boot dev mnt opt overlay proc rom run sys tmp..."
mkdir boot dev mnt opt overlay proc rom run sys tmp

echo "  - link lib64..."
ln -sf lib lib64
echo "  - link var..."
ln -sf tmp var

echo "  - copy fstab..."
cp -a /root/fstab ./etc

sed -i 's/ROOTFS/ROOT_EMMC/' etc/config/fstab
sed -i 's/BOOT/BOOT_EMMC/' etc/config/fstab

rm -rf ipk
rm -f root/fstab
rm -f root/install.sh

cd /
sync

process "umount rootfs..."
umount -f $part_root

rm -rf install

process "all done, now you can boot without usb disk!"
