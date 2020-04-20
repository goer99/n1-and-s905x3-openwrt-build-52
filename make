#!/bin/bash

work_dir=$(pwd)
tmp_dir="$work_dir/tmp"
out_dir="$work_dir/out"
device="phicomm-n1"

red="\033[31m"
green="\033[32m"
white="\033[0m"

info() {
    echo -e "$green i:$white $1"
}

error() {
    echo -e "$red e:$white $1"
}

error_exit() {
    error $1
    exit
}

tip() {
    echo -e "$green $1 $white"
}

cleanup() {
    [ -d $tmp_dir ] && {
        [ -d "$tmp_dir/mount" ] && {
            local mounts=$(lsblk | grep -E "$tmp_dir/mount" | grep -oE "(loop[0-9]|loop[0-9][0-9])" | uniq)
            for x in ${mounts[*]}; do
                umount -f /dev/${x}* >/dev/null 2>&1
                losetup -d "/dev/$x" >/dev/null 2>&1
            done
        }
        rm -rf $tmp_dir
    }
}

extract_openwrt_file() {
    tip "extract openwrt files..."

    local file_path="$work_dir/openwrt/$1"
    local file_suff="${file_path##*.}"
    mount_dir="$tmp_dir/mount"
    root_dir="$tmp_dir/root"

    mkdir -p $mount_dir $root_dir

    while true; do
        case "$file_suff" in
        tar)
            tar -xf $file_path -C $root_dir
            break
            ;;
        gz)
            if (ls $file_path | grep -E ".tar.gz$") >/dev/null 2>&1; then
                tar -xf $file_path -C $root_dir
                break
            else
                gzip -d $file_path
                file_path=${file_path%.*}
                file_suff=${file_path##*.}
            fi
            ;;
        img)
            loop=$(losetup -P -f --show $file_path)
            [ ! $loop ] && error_exit "you used a lower version linux, you may try 
 apt-get install util-linux=2.31.1-0.4ubuntu3.6 -y 
 to fix it, or you can upgrade your system version."
            if !(mount -t ext4 -o rw ${loop}p2 $mount_dir); then
                error_exit "mount image faild!"
            fi
            cp -r $mount_dir/* $root_dir && sync
            umount -f $mount_dir
            losetup -d $loop
            break
            ;;
        ext4)
            if !(mount -t ext4 -o rw,loop $file_path $mount_dir); then
                error_exit "mount image faild!"
            fi
            cp -r $mount_dir/* $root_dir && sync
            umount -f $mount_dir
            break
            ;;
        *)
            error_exit "unsupported firmware format, check your firmware in openwrt folder! 
 this script only supported rootfs.tar.gz, ext4-factory.img[.gz], root.ext4[.gz] five format."
            ;;
        esac
    done

    rm -rf $root_dir/lib/modules/*/
}

extract_armbian_file() {
    tip "extract armbian files..."

    kernel_dir="$work_dir/armbian/$device/kernel/$kernel"
    boot_dir="$tmp_dir/boot"

    mkdir -p $boot_dir

    tar -xzf "$kernel_dir/../../boot-common.tar.gz" -C $boot_dir
    tar -xzf "$kernel_dir/../../firmware.tar.gz" -C $root_dir
    tar -xzf "$kernel_dir/kernel.tar.gz" -C $boot_dir
    tar -xzf "$kernel_dir/modules.tar.gz" -C $root_dir
    cp -r $work_dir/armbian/$device/root/* $root_dir
}

utils() {
    cd $root_dir

    echo "pwm_meson" >etc/modules.d/pwm-meson
    sed -i '/kmodloader/i\\tulimit -n 51200\n' etc/init.d/boot
    sed -i 's/ttyAMA0/ttyAML0/' etc/inittab
    sed -i 's/ttyS0/tty0/' etc/inittab

    mkdir -p boot run
    chown -R 0:0 ./

    cd $work_dir
}

make_image() {
    tip "make openwrt image..."

    image_name="$device-$kernel-openwrt-firmware"
    image="$out_dir/$kernel/$(date "+%y.%m.%d-%H%M")-$image_name.img"

    [ -d "$out_dir/$kernel" ] || mkdir -p "$out_dir/$kernel"
    fallocate -l $((16 + 128 + root_size))M $image
}

format_image() {
    tip "format openwrt image..."

    parted -s $image mklabel msdos
    parted -s $image mkpart primary ext4 17M 151M
    parted -s $image mkpart primary ext4 151M 100%

    loop=$(losetup -P -f --show $image)
    [ $loop ] || error_exit "you used a lower version linux, you may try: 
    apt-get install util-linux=2.31.1-0.4ubuntu3.6 -y 
    to fix it, or you can upgrade your system version."

    mkfs.vfat -n "BOOT" ${loop}p1 >/dev/null 2>&1
    mke2fs -F -q -t ext4 -L "ROOTFS" ${loop}p2 -m 0 >/dev/null 2>&1
}

copy2image() {
    tip "copy files to image..."

    local boot=$mount_dir/boot
    local root=$mount_dir/root

    mkdir -p $boot $root

    if !(mount -t vfat -o rw ${loop}p1 $boot); then
        error_exit "mount image faild!"
    fi
    if !(mount -t ext4 -o rw ${loop}p2 $root); then
        error_exit "mount image faild!"
    fi

    cp -r $boot_dir/* $boot
    cp -r $root_dir/* $root
    sync

    umount -f $boot $root
    losetup -d $loop
}

get_firmware_list() {
    firmwares=()
    i=0
    IFS=$'\n'

    [ -d "$work_dir/openwrt" ] && {
        for x in $(ls $work_dir/openwrt); do
            firmwares[i++]=$x
        done
    }
    if ((${#firmwares[*]} == 0)); then
        error_exit "no file in openwrt folder!"
    fi
}

get_kernel_list() {
    kernels=()
    i=0
    IFS=$'\n'

    local kernel_root="$work_dir/armbian/$device/kernel"
    [ -d $kernel_root ] && {
        cd $kernel_root
        for x in $(ls ./); do
            if [ -f "$x/kernel.tar.gz" ] && [ -f "$x/modules.tar.gz" ]; then
                kernels[i++]=$x
            fi
        done
        cd $work_dir
    }
    if ((${#kernels[*]} == 0)); then
        error_exit "no file in kernel folder!"
    fi
}

show_list() {
    i=0
    for x in $1; do
        echo " ($((i + 1))) ==> $x"
        let i++
    done
}

choose_firmware() {
    echo " firmware: "
    show_list "${firmwares[*]}"

    choose_files ${#firmwares[*]} "firmware"
    firmware=${firmwares[opt]}
    echo -e " ( $firmware )\n"
}

choose_kernel() {
    echo " kernel: "
    show_list "${kernels[*]}"

    choose_files ${#kernels[*]} "kernel"
    kernel=${kernels[opt]}
    echo -e " ( $kernel )\n"
}

choose_files() {
    local len=$1
    local type=$2
    opt=

    if (($len == 1)); then
        opt=0
    else
        i=0
        while true; do
            echo && read -p "$(info "select the $type above, press enter to choose the first one: ")" opt
            [ $opt ] || opt=1

            if (($opt >= 1 && $opt <= $len)) >/dev/null 2>&1; then
                let opt--
                break
            else
                (($i >= 2)) && exit
                error "input is wrong, try again!"
                sleep 1s
                let i++
            fi
        done
    fi
}

link_modules() {
    tip "link \"$kernel\" modules..."

    kernel_dir="$work_dir/armbian/$device/kernel/$1"
    
    mkdir -p $tmp_dir
    tar -xzf "$kernel_dir/modules.tar.gz" -C $tmp_dir

    local modules="$tmp_dir/lib/modules/*/"
    if !(ls $modules | grep ".ko") >/dev/null 2>&1; then
        cd $modules
        for x in $(find -name "*.ko"); do
            ln -s $x ./ >/dev/null 2>&1
        done
        cd $tmp_dir/
        tar -czf modules.tar.gz lib/
        cp -r modules.tar.gz "$kernel_dir"
        cd $work_dir
    else
        info "already initialized! don't need \"-l\" next time."
    fi

    rm -rf $tmp_dir

    echo && tip "link modules ok!"
}

set_rootsize() {
    i=0
    root_size=

    while true; do
        read -p "$(info "input the ROOTFS partition size, default 512m, do not less than 256m 
 if you don't know what's the means, press enter to keep the default: ")" root_size
        [ $root_size ] || root_size=512
        if (($root_size >= 256)) >/dev/null 2>&1; then
            echo -e " (${root_size}m) \n"
            break
        else
            (($i >= 2)) && exit
            error "input is wrong, try again!"
            sleep 1s
            let i++
        fi
    done
}

show_help() {
    echo -e \
        "
Usage:
  make [option]\n
Options:
  -c, --clean\t\tcleanup the output directory
  -d, --default\t\tuse default configuration to build image, which where use the first firmware, build all kernel version, and rootfs partition size set to 512m by default
  --firmware\t\tshow all firmware in \"openwrt\" directory
  --kernel\t\tshow all kernel in \"kernel\" directory
  -k=VERSION\t\tset the kernel version, which must be in kernel directory, or use \"all\" to build all kernel version
  -l, --link=[VERSION]\thelp you to link the kernel modules
  -s, --size=SIZE\tset the rootfs partition size, do not less than 256m
  -h, --help\t\tdisplay this help
"
}

##
if (($UID != 0)); then
    error_exit "please run this script as root!"
fi

cleanup
get_firmware_list
get_kernel_list

while [ "$1" ]; do
    case "$1" in
    -h | --help)
        show_help
        exit
        ;;
    -c | --clean)
        cleanup
        rm -rf $out_dir
        tip "cleanup ok!"
        exit
        ;;
    -d | --default)
        [ $root_size ] || root_size=512
        [ $firmware ] || firmware=${firmwares[0]}
        [ $kernel ] || kernel="all"
        is_default=true
        ;;
    --firmware)
        show_list "${firmwares[*]}"
        exit
        ;;
    -k)
        kernel=$2
        if ! [ $kernel ] || ! [ -d "$work_dir/armbian/$device/kernel/$kernel" ]; then
            [ $kernel = "all" ] && shift || error_exit "invalid kernel \"$2\""
        else
            shift
        fi
        ;;
    --kernel)
        show_list "${kernels[*]}"
        exit
        ;;
    -l | --link)
        kernel=$2
        if ! [ $kernel ] || ! [ -d "$work_dir/armbian/$device/kernel/$kernel" ]; then
            choose_kernel
        fi
        link_modules $kernel
        exit
        ;;
    -s | --size)
        root_size=$2
        if ! [ $root_size ] || (($root_size < 256)) >/dev/null 2>&1; then
            error_exit "invalid size \"$2\""
        else
            shift
        fi
        ;;
    *)
        error_exit "invalid option \"$1\""
        ;;
    esac
    shift
done

[ $firmware ] && echo " firmware     ==>  $firmware"
[ $kernel ] && echo " kernel       ==>  $kernel"
[ $root_size ] && echo -e " rootfs size  ==>  ${root_size}m\n"

[ $firmware ] || choose_firmware
[ $kernel ] || choose_kernel
[ $root_size ] || set_rootsize

[ $kernel = "all" ] || kernels=("$kernel")
for x in ${kernels[*]}; do
    kernel=$x
    echo " for \"$kernel\": "
    extract_openwrt_file $firmware
    extract_armbian_file $kernel
    utils
    make_image $root_size
    format_image
    copy2image
    cleanup
    sleep 1s
    echo
done

chmod -R 777 $out_dir

tip "all done, enjoy!"
