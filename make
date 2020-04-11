#!/bin/bash

work_dir=$(pwd)
tmp_dir="$work_dir/tmp"
out_dir="$work_dir/out"
device="phicomm-n1"
image_name="$device-arm64-openwrt-firmware"

red="\033[31m"
green="\033[32m"
white="\033[0m"

info() {
    echo -e "$green i:$white $1"
}

error() {
    echo -e "$red e:$white $1"
}

tip() {
    echo -e "$green $1 $white"
}

mount_image() {
    local option=$1
    local part=$2
    local path=$3

    mkdir -p $path
    mount -o $option $part $path
}

umount_image() {
    umount -f $1
    rm -rf $1
}

cleanup() {
    [ -d $tmp_dir ] && {
        [ -d $tmp_dir/mount ] && {
            for x in $(lsblk | grep "$tmp_dir/mount*" | grep -oE "(loop[0-9]|loop[0-9][0-9])" | uniq); do
                umount -f /dev/${x}* >/dev/null 2>&1
                losetup -d "/dev/$x"
            done
        }
        rm -rf $tmp_dir
    }
}

extract_openwrt_file() {
    tip "extract openwrt files..."

    local path=$1
    local file_suffix="${path##*.}"
    mount_dir="$tmp_dir/mount"
    root_dir="$tmp_dir/root"

    mkdir -p $root_dir

    while true; do
        case "$file_suffix" in
        tar)
            tar -xf $path -C $root_dir
            break
            ;;
        gz)
            gzip -d $path
            path=${path%.*}
            file_suffix="${path##*.}"
            ;;
        img)
            loop=$(losetup -P -f --show $path)
            [ ! $loop ] && {
                error "you used a lower version linux, you may try 
                ${green} apt-get install util-linux=2.31.1-0.4ubuntu3.6 -y 
                ${red} to fix it, or you can upgrade your system version."
                exit
            }
            mount_image "rw" ${loop}p2 $mount_dir
            cp -r $mount_dir/* $root_dir && sync
            umount_image $mount_dir
            losetup -d $loop
            break
            ;;
        ext4)
            mount_image "rw,loop" $path $mount_dir
            cp -r $mount_dir/* $root_dir && sync
            umount_image $mount_dir
            break
            ;;
        *)
            error "unsupported firmware format, check your firmware in openwrt folder!\n
 this script only supported rootfs.tar.gz, ext4-factory.img[.gz], root.ext4[.gz] five format."
            exit
            ;;
        esac
    done

    rm -rf $root_dir/lib/modules/*/
}

extract_armbian_file() {
    tip "extract armbian files..."

    local path=$1
    boot_dir="$tmp_dir/boot"

    mkdir -p $boot_dir
    tar -xzf $path/boot.tar.gz -C $boot_dir
    tar -xzf $path/modules.tar.gz -C $root_dir
    tar -xzf $path/firmware.tar.gz -C $root_dir
    cp -r $work_dir/armbian/$device/root/* $root_dir
}

utils() {
    echo "pwm_meson" > $root_dir/etc/modules.d/pwm_meson
    sed -i '/kmodloader/i\\tulimit -n 51200\n' $root_dir/etc/init.d/boot
    sed -i 's/ttyAMA0/ttyAML0/' $root_dir/etc/inittab
    sed -i 's/ttyS0/tty0/' $root_dir/etc/inittab

    mkdir -p $root_dir/boot
    mkdir -p $root_dir/run
    chown -R 0:0 $root_dir
}

make_image() {
    tip "make openwrt image..."

    image="$out_dir/$(date "+%y.%m.%d-%H%M%S")-$image_name.img"

    [ -d $out_dir ] || mkdir $out_dir
    fallocate -l $((16 + 128 + root_size))M $image
}

format_image() {
    tip "format openwrt image..."

    parted -s $image mklabel msdos
    parted -s $image mkpart primary ext4 17M 151M
    parted -s $image mkpart primary ext4 151M 100%

    loop=$(losetup -P -f --show $image)
    [ ! $loop ] && {
        error "you used a lower version linux, you may try:\n
 ${green}apt-get install util-linux=2.31.1-0.4ubuntu3.6 -y\n
 ${white}to fix it, or you can upgrade your system version."
        exit
    }

    mkfs.vfat -n "BOOT" ${loop}p1 >/dev/null 2>&1
    mke2fs -F -q -t ext4 -L "ROOTFS" -m 0 ${loop}p2
}

copy2image() {
    tip "copy files to image..."

    local boot=$mount_dir/boot
    local root=$mount_dir/root

    mount_image "rw" ${loop}p1 $boot
    mount_image "rw" ${loop}p2 $root

    cp -r $boot_dir/* $boot
    cp -r $root_dir/* $root
    sync

    umount_image ${loop}p1 $boot
    umount_image ${loop}p2 $root
    losetup -d $loop
}

get_file_list() {
    files=("")
    i=0
    IFS=$(echo -en "\n\b")

    for x in $(ls $work_dir/openwrt); do
        files[i++]=$x
    done
}

choose_firmware() {
    opt=
    i=0

    info "firmware: "
    for x in ${files[@]}; do
        echo " $((i + 1)). $x"
        let i++
    done

    local len=${#files[@]}
    if (($len == 0)); then
        error "there is no file in openwrt folder!"
        exit
    elif (($len == 1)); then
        opt=0
    else
        i=0
        while true; do
            echo && read -p "$(info "select the firmware above, press enter to select the first one: ")" opt && echo
            [ $opt ] || opt=1

            if (($opt >= 1 && $opt <= $len)); then
                let opt--
                break
            else
                (($i >= 2)) && exit
                error "input is wrong, try again!"
                sleep 2s
                let i++
            fi
        done
    fi
}

link_modules() {
    tip "link modules..."

    local modules_dir="$work_dir/armbian/$device"
    local modules="$tmp_dir/lib/modules/*/"

    mkdir -p $tmp_dir
    tar -xzf $modules_dir/modules.tar.gz -C $tmp_dir

    if ! (ls $modules | grep ".ko" >/dev/null 2>&1); then
        cd $modules
        for x in $(find -name "*.ko"); do
            ln -s $x ./ >/dev/null 2>&1
        done
        cd $tmp_dir/
        tar -czf modules.tar.gz lib/
        cp -r modules.tar.gz $modules_dir
    else
        info "already initialized!\n you don't need to use the option -i next time.\n"
    fi

    rm -rf $tmp_dir/*
    cd $work_dir
}

set_rootsize() {
    local i=0
    root_size=

    while true; do
        echo && read -p "$(info "input the ROOTFS partition size, default 512m, do not less than 256m\n
 if you don't know what's the means, press enter to keep the default: ")" root_size && echo
        [ $root_size ] || root_size=512
        if [ $root_size -ge 256 ] >/dev/null 2>&1; then
            break
        else
            (($i >= 2)) && exit
            error "input is wrong, try again!"
            sleep 2s
            let i++
        fi
    done
}

##
if ! (($UID == 0)); then
    error "please use root to run this script"
    exit
fi

while [ $1 ]; do
    case "$1" in
    -h | --help)
        echo -e \
"Usage:
  make [option]

Options:
  -c, --clean\t\tcleanup the output directory
  -d, --default\t\tuse default configuration to make image, which where select the first one firmware in openwrt directory, and rootfs partition size set to 512m by default
  -l, --link\t\tif you replaced the modules, use this option to help you to link modules
  -s, --size=SIZE\tset the rootfs partition size, do not less than 256m
  -h, --help\t\tdisplay this help
"
        exit
        ;;
    -c | --clean)
        cleanup
        rm -rf $out_dir
        tip "finished clean up!"
        exit
        ;;
    -d | --default)
        info "use default configuration"
        is_default=true
        [ $root_size ] || root_size=512
        ;;
    -i | --init)
        link_modules
        ;;
    -s | --size)
        root_size=$2
        if ! [[ $root_size -ge 256 ]]; then
            root_size=512
            error "invalid size $2, use default size 512m"
        else
            info "rootfs size: ${2}m"
            shift
        fi
        ;;
    *)
        error "invalid option $1"
        ;;
    esac
    shift
done

cleanup
get_file_list

[ $is_default ] || choose_firmware
extract_openwrt_file $work_dir/openwrt/${files[opt]}

extract_armbian_file $work_dir/armbian/$device
utils

[ $root_size ] || set_rootsize
make_image $root_size

format_image
copy2image
cleanup

chmod 777 $out_dir

tip "all done, enjoy!"
