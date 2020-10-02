# 自动构建斐讯 N1、微加云( Vplus ) OpenWrt 固件脚本
# Automatically Build OpenWrt Firmware for PHICOMM N1, VPLUS and so on

**制作脚本已部署到 Github Action，真正实现一栈式全自动构建，每周六早上六点准时为你构建，无须自行制作，下载即可用**

[![OpenWrt-CI](https://github.com/tuanqing/mknop/workflows/OpenWrt-CI/badge.svg?branch=master)](https://github.com/tuanqing/mknop/actions)  
 👆👆👆&nbsp; &nbsp; 戳上面查看构建状态

## 使用方法

1. Linux环境，推荐使用 Ubuntu 18.04 LTS
2. 编译好待构建的 OpenWrt 固件，不会的自行科普 [Lean's OpenWrt source](https://github.com/coolsnowwolf/lede "Lean's OpenWrt source")  
   编译N1固件的配置如下：
   ``` 
   Target System (QEMU ARM Virtual Machine)  --->
   Subtarget (ARMv8 multiplatform)  --->
   Target Profile (Default)  --->
   ```

   **注意：  
   一键安装到 emmc 脚本( phicomm n1 )已迁移至 openwrt package。使用方法如下，悉知！！**

   **用法**：  
   1、`git clone https://github.com/tuanqing/install-program package/install-program`  
   2、执行 `make menuconfig` ，选中 Utilities 下的 install-program
      ``` 
      Utilities  --->  
         <*> install-program
      ```
   3、编译完成之后使用本源码制作镜像写入U盘启动，之后执行 `n1-install` 即可安装到 emmc  
   4、将固件上传到 `/tmp/upgrade`( xxx.img )，之后执行 `n1-update` 即可从该固件升级

3. 克隆仓库到本地  
   `git clone https://github.com/tuanqing/mknop` 
4. 将你编译好的固件拷贝到 openwrt 目录( 可复制多个 )
5. 使用 sudo 执行脚本  
   `sudo ./gen_openwrt` 
6. 按照提示操作，如，选择设备、固件、内核版本、设置 ROOTFS 分区大小等  
   如果你不了解这些设置项，请按回车保持默认，或者直接执行  
   `sudo ./gen_openwrt -d` 
7. 等待构建完成，默认输出文件夹为 out
8. 写盘启动，写盘工具推荐 [Etcher](https://www.balena.io/etcher/)

**注意**：  
1、待构建的固件格式只支持 rootfs.tar[.gz]、 ext4-factory.img[.gz]、root.ext4[.gz] 6种，推荐使用 rootfs.tar.gz 格式 

## 特别说明

* 目录说明
```
   ├── common                                公共文件夹
   │   ├── firmware-common.tar.gz            armbian 固件
   │   └── kernel                            内核文件夹，在它下面添加你的自定义内核
   │       └── 5.4.68                        kernel 5.4.68-flippy-45+o @flippy
   ├── device                                设备文件夹
   │   ├── phicomm-n1                        phicomm n1 设备文件夹
   │   │   ├── boot-phicomm-n1.tar.gz        phicomm n1 启动文件
   │   │   └── root                          phicomm n1 rootfs 文件夹
   │   └── vplus                             vplus 设备文件夹
   │       ├── boot-vplus.tar.gz             vplus 启动文件
   │       └── root                          vplus rootfs 文件夹
   ├── gen_openwrt                           构建脚本
   ├── LICENSE                               license
   ├── openwrt                               固件文件夹(to build)
   ├── out                                   固件文件夹(build ok)
   ├── tmp                                   临时文件夹
   └── README.md                             readme

```

* 使用参数
   * `-c, --clean` ，清理临时文件和输出目录
   * `-d, --default` ，使用默认配置来构建固件( 构建所有设备、openwrt 下的第一个固件、构建所有内核、ROOTFS 分区大小为自定义最小 )
   * `-e` ，从 openwrt 目录中提取内核，仅支持 img 格式和 xz 压缩的 img 格式
   * `-k=VERSION` ，设置内核版本，设置为 `all` 将会构架所有内核版本固件，设置为 `latest` 将构建最新内核版本固件
   * `-m=MACHINE` ，设置设备，设置为 `all` 将会构架所有设备的固件
   * `--mount` ，挂载 openwrt 目录下的固件，仅支持 img 格式和 xz 压缩的 img 格式
   * `-s, --size=SIZE` ，设置 ROOTFS 分区大小，不要小于自定义最小
   * `-h, --help` ，显示帮助信息
   * examples：  
      `sudo ./gen_openwrt -c` ，清理文件  
      `sudo ./gen_openwrt -d` ，使用默认配置  
      `sudo ./gen_openwrt -k latest` ，使用最新内核  
      `sudo ./gen_openwrt -m vplus`，构建 vplus 固件  
      `sudo ./gen_openwrt -s 512` ，将 ROOTFS 分区大小设置为 512M  
      `sudo ./gen_openwrt -d -k 5.4.68 -m vplus` ，使用默认，构建 vplus 固件，并将内核版本设置为 5.4.68  
      `sudo ./gen_openwrt -e` ，从 openwrt 目录中提取内核  
      `sudo ./gen_openwrt --mount` ，挂载 openwrt 目录中固件 

* 自定义
   * 使用自定义内核  
     使用 `sudo ./gen_openwrt -e`，从 openwrt 目录中提取内核
   
   * 添加自定义设备

   * 添加自定义文件  
      向 device/${device}/root 目录添加你的文件

      **注意**：添加的文件应保持与 ROOTFS 分区目录结构一致

## Thanks

* flippy provides the kernel
