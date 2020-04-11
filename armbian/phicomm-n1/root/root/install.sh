#!/bin/sh

emmc=$(lsblk | grep -oE 'mmcblk[0-9]' | uniq)
sd=$(lsblk | grep -oE 'sd[a-z]' | uniq)

[ $emmc ] || (echo "no emmc found!" && exit)
if [ $sd ]; then
    blkid -L 'BOOT' || (echo "no usb bootable device found!" && exit)
else
    echo "no usb bootable device found!" && exit
fi

dev_emmc="/dev/$emmc"
dev_sd="/dev/$sd"

echo "emmc: $dev_emmc"
echo "usb: $dev_sd"

if (blkid -L "BOOT_EMMC" && blkid -L "ROOT_EMMC"); then
    installed=true
fi

if (grep -q $dev_emmc /proc/mounts); then
    echo "umout emmc"
    umount -f ${dev_emmc}p* >/dev/null 2>&1
fi

part_boot="${dev_emmc}p1"
part_root="${dev_emmc}p2"

if ! [ $installed ]; then
    echo "backup u-boot"
    dd if=$dev_emmc of=u-boot-default-aml.img bs=1M count=4

    echo "create mbr and partition"
    parted -s $dev_emmc mklabel msdos
    parted -s $dev_emmc mkpart primary fat32 700M 1212M
    parted -s $dev_emmc mkpart primary ext4 1213M 100%

    echo "restore u-boot"
    dd if=u-boot-default-aml.img of=$dev_emmc conv=fsync bs=1 count=442
    dd if=u-boot-default-aml.img of=$dev_emmc conv=fsync bs=512 skip=1 seek=1

    sync

    echo "format boot partiton"
    mkfs.fat -F 32 -n "BOOT_EMMC" $part_boot

    echo "format rootfs partiton"
    mke2fs -t ext4 -F -q -L 'ROOT_EMMC' -m 0 $part_root
    e2fsck -n $part_root
fi

ins_boot="/install/boot"
ins_root="/install/root"

mkdir -p -m 777 $ins_boot $ins_root

echo "mount boot partition"
mount -t vfat $part_boot $ins_boot
rm -rf $ins_boot/*

echo "copy bootable file"
grep -q 'boot' /proc/mounts || mount -t vfat ${dev_sd}1 /boot
cp -r /boot/* $ins_boot
sync

sed -i 's/ROOTFS/ROOT_EMMC/' $ins_boot/uEnv.txt

rm $ins_boot/s9*
rm $ins_boot/aml*
rm $ins_boot/boot.ini
mv -f $ins_boot/boot-emmc.scr $ins_boot/boot.scr

if [ -f /boot/u-boot.ext ]; then
    mv -f $ins_boot/u-boot.sd $ins_boot/u-boot.emmc
    mv -f $ins_boot/boot-emmc.ini $ins_boot/boot.ini
    sync
fi

echo "umount boot partition"
umount -f $part_boot

echo "mount root partition"
mount -t ext4 $part_root $ins_root
rm -rf $ins_root/*

echo "copy rootfs"

cd /
echo "copy bin"
tar -cf - bin | (cd $ins_root && tar -xpf -)
echo "copy etc"
tar -cf - etc | (cd $ins_root && tar -xpf -)
echo "copy lib"
tar -cf - lib | (cd $ins_root && tar -xpf -)
echo "copy root"
tar -cf - root | (cd $ins_root && tar -xpf -)
echo "copy sbin"
tar -cf - sbin | (cd $ins_root && tar -xpf -)
echo "copy usr"
tar -cf - usr | (cd $ins_root && tar -xpf -)
echo "copy www"
tar -cf - www | (cd $ins_root && tar -xpf -)

[ -f init ] && cp -a init $ins_root

cd $ins_root
echo "create boot"
mkdir -p boot
echo "create dev"
mkdir -p dev
echo "create mnt"
mkdir -p mnt
echo "create overlay"
mkdir -p overlay
echo "create proc"
mkdir -p proc
echo "create rom"
mkdir -p rom
echo "create run"
mkdir -p run
echo "create sys"
mkdir -p sys
echo "create tmp"
mkdir -p tmp

echo "link lib64"
ln -sf lib lib64
echo "link var"
ln -sf tmp var

echo "copy fstab"
cp -a /root/fstab etc

sed -i 's/ROOTFS/ROOT_EMMC/' etc/config/fstab
sed -i 's/BOOT/BOOT_EMMC/' etc/config/fstab

rm root/install.sh
rm root/fstab

cd /
sync

echo "umount root partition"
umount -f $part_root

rm -rf install

echo "all done, now you can boot without usb disk!"
