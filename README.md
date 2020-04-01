# 构建斐讯N1 OpenWrt固件脚本
# Build OpenWrt Firmware for PHICOMM N1


## 使用方法

1. `Linux`环境，推荐使用`Ubuntu 18.04 LTS`
2. 编译好待构建的`OpenWrt`固件，不会的自行科普 [Lean's OpenWrt source](https://github.com/coolsnowwolf/lede "Lean's OpenWrt source")
3. 克隆仓库到本地<br>
`git clone https://github.com/tuanqing/mknop.git`
4. 将你编译好的OpenWrt固件拷贝到 `OpenWrt`目录（可以复制多个固件到此）
5. 使用`sudo`执行脚本<br>
`sudo ./make`
6. 按照提示操作，如：选择你要制作的固件、设置`ROOTFS`分区大小等
7. 等待构建完成，默认输出文件夹为`out`
8. 写盘启动，写盘工具推荐 [Etcher](https://github.com/balena-io/etcher/releases/download/v1.5.80/balenaEtcher-Portable-1.5.80.exe)

**注意**：待构建的固件格式只支持 `rootfs.tar.gz`、`ext4-factory.img[.gz]`、`root.ext4[.gz]` 5种


## 特别说明

* 目录说明
   * `armbian`，`armbian`相关文件
      * `phicomm-n1`，设备文件夹
         * `root`，自定义文件夹
         * `boot.tar.gz`，启动分区相关文件
         * `firmware.tar.gz`，设备驱动文件
         * `modules.tar.gz`，内核模块文件
   * `openwrt`，用于存放待构建的OpenWrt固件
   * `out`，输出文件夹，用于存放构建好的OpenWrt固件
   * `.tmp`，临时文件夹，用于脚本转储

* 使用参数
   * `-d, --default`，使用默认配置构建，使用此参数将以 "使用 `OpenWrt`目录的第一个固件、`ROOTFS`分区大小默认为`512M`" 方式构建 
   * `-i, --init`，替换内核之后使用此参数
   * `-c, --clean`，清理临时文件和输出目录

* 自定义
   * 使用自定义内核<br>
     你可以在`Armnbian`镜像中提取，并按照目录结构，将文件打包为 `boot.tar.gz`、`firmware.tar.gz`、`modules.tar.gz`，最后替换 `armbian/phicomm-n1`目录下的相关文件即可

     **注意**：<br>
     1、如果`Armnbian`镜像的`BOOT`分区下的`uEnv.txt`中的`FDT`参数不是`phicomm-n1`，则需要你手动更改，不更改则导致无法启动<br>
     2、替换内核后需要使用`-i`参数

   * 添加自定义文件<br>
      向`armbian/phicomm-n1/root`目录添加你想要的文件

      **注意**：添加的文件应保持与`ROOTFS`分区目录结构一致