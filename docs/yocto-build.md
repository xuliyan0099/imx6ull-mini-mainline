# Yocto（poky scarthgap 5.0）路线

这条路线把原来手写的四层（U-Boot / Linux / BusyBox rootfs / LVGL 9.6 仪表盘）
搬进 Yocto，用 `bitbake` 统一编排，产出可直接烧 SD 卡的整盘镜像。
手写路线仍然保留（`tools/build-all.sh`），两条路线共用同一批源码（`components/`），产物可对照。

## 1. 组成

| 部分 | 位置 | 说明 |
|---|---|---|
| 构建容器 | `yocto/Dockerfile` | `ubuntu:24.04` + Yocto 宿主依赖（bison/flex/bc/chrpath/socat/... 全套），构建用户 uid 1000 |
| 构建配置 | `yocto/local.conf` | MACHINE/DISTRO/镜像特性/依赖过滤 class |
| BSP 层 | `yocto/meta-imx6ull-mini/` | 机器定义 + 四个 recipe + 2 个辅助 class + 拦截钩子覆盖 |
| 初始化脚本 | `tools/yocto-build.sh` | 生成 `bblayers.conf`、铺 `local.conf`、`bitbake imx6ull-mini-image` |
| SD 镜像脚本 | `tools/make-sdcard-from-yocto.sh` | 把 Yocto 的 ext4 + U-Boot 拼成 256 MiB 整盘镜像 |

poky 用官方发布包 `poky-fb91a49387cfb0c8d48303bb3354325ba2a05587.tar.bz2`（`DISTRO_VERSION=5.0`，`LAYERSERIES_COMPAT=scarthgap`），
解压后顶层目录即 `poky/`。源码拉取全部走官方镜像 `https://downloads.yoctoproject.org/mirror/sources/`
（`INHERIT += "own-mirrors"` + `SOURCE_MIRROR_URL`），因为构建机上 GitHub / git.yoctoproject.org 的 git 协议不可用。

## 2. 机器定义

`meta-imx6ull-mini/conf/machine/imx6ull-mini.conf`：

```text
DEFAULTTUNE            = "cortexa7thf-neon"
KERNEL_IMAGETYPE       = "zImage"
PREFERRED_PROVIDER_virtual/kernel           = "linux-imx6ull-mini"
PREFERRED_PROVIDER_u-boot                   = "u-boot-imx6ull-mini"
PREFERRED_PROVIDER_virtual/bootloader       = "u-boot-imx6ull-mini"
UBOOT_MACHINE          = "mx6ull_alientek_mini_defconfig"
UBOOT_ENTRYPOINT / UBOOT_LOADADDRESS        = "0x80008000"
SERIAL_CONSOLES        = "115200;ttymxc0"
MACHINE_FEATURES       = "usbhost usbgadget alsa touchscreen screen"
IMAGE_FSTYPES ?=       "tar.bz2 ext4"
```

## 3. 四个 recipe 都是 `externalsrc`

不重新下载、不打包源码，直接指向组件仓库里的原件，保证 Yocto 产物和手写路线同源：

| recipe | EXTERNALSRC | 关键点 |
|---|---|---|
| `u-boot-imx6ull-mini_2026.10.bb` | `components/u-boot` | 装板级 defconfig → 源码树 `mrproper` → `O=build` 配置；`EXTRA_OEMAKE` 显式给 `HOSTCC=gcc`（任务 PATH 里只有 `gcc` 没有 `cc`） |
| `linux-imx6ull-mini_7.3.6.bb` | `components/linux` | 装 `kernel.config` → `olddefconfig` → `zImage dtbs`；`DEPENDS += bison-native flex-native bc-native` |
| `busybox-imx6ull-mini_1.38.0.bb` | `components/busybox` | 源码树**原地构建**（out-of-tree 会去源码树找 `scripts/kconfig/zconf.tab.c`）；`CC="${CC}"` 走 Yocto 包装器带 `--sysroot`；rootfs 骨架三件套（`/init`、`rcS`、`inittab`）来自 `components/busybox-rootfs/rootfs` |
| `lvgl-demo_9.6.bb` | `components/lvgl` | 拷到 `${B}` 后复用自带 Makefile，`LVGL_DIR` 指 `components/lvgl`，`LDFLAGS` 必须带 `${LDFLAGS}`（否则 `GNU_HASH` 缺失被 QA 拦） |

相对手写路线的两处改动：BusyBox 与 LVGL 都改成**动态链接**（`CONFIG_STATIC` 被 sed 关掉），libc 由 Yocto 的 glibc 包提供。

## 4. 镜像

`imx6ull-mini-image.bb`：`inherit image`（不用 `core-image`，避开 `meta-environment-extsdk` 那条链），
`IMAGE_INSTALL = "base-files base-passwd busybox-imx6ull-mini lvgl-demo linux-imx6ull-mini"`，
rootfs 收尾时补 `fstab`（sysfs/devtmpfs/tmpfs）、`hostname`、最小 `passwd/group`、空的 `/etc/man_db.conf`。

最终 manifest 只有 9 个包：

```text
base-files  base-passwd  busybox-imx6ull-mini  ldconfig  libc6
linux-imx6ull-mini  lvgl-demo  update-rc.d  util-linux-fcntl-lock
```

## 5. 怎么跑

```bash
# 1) 构建容器（约 580 MB）
docker build -t im6-yocto:ubuntu24 yocto/

# 2) 拉 poky 发布包并解压到 yocto/poky
curl -LO https://downloads.yoctoproject.org/releases/yocto/yocto-5.0/poky-fb91a49387cfb0c8d48303bb3354325ba2a05587.tar.bz2
tar -xjf poky-fb91a49387cfb0c8d48303bb3354325ba2a05587.tar.bz2 -C yocto/

# 3) 在容器里跑：生成 build-imx6ull/conf 并 bitbake 整个镜像
docker run --rm -v $PWD/..:/work -w /work/repo -u 1000:1000 im6-yocto:ubuntu24 \
  bash -lc 'bash tools/yocto-build.sh'

# 4) 拼 SD 整盘镜像（需要 mke2fs/sfdisk/debugfs，宿主机或 im6-build 容器里都行）
bash tools/make-sdcard-from-yocto.sh
```

`tools/yocto-build.sh` 生成 `bblayers.conf`（`meta`、`meta-poky`、本层）并铺 `local.conf`，
`conf/` 里两个文件的其它变量全部来自 `yocto/local.conf`。

## 6. 产物

| 文件 | 大小 | SHA256 |
|---|---|---|
| `u-boot-dtb.imx` | 400,384 B | `4b42f66f2e6b2000abc98895687b8207ca787e1e0690705be194a5960c7d98b3` |
| `zImage` | 10,105,192 B | `3bee0111dabb3e02ee1cd49621cbcf2c3b323c47b79dccad4007e63f2ca8c4d6` |
| `imx6ull-alientek-mini-4.3.dtb` | 34,692 B | `1a41ee5697a87bddcbfd90f806ce98af43159c21411da362521abeb6bdf95f9a` |
| `rootfs.ext4` | 62,914,560 B | `26a23668dc6aad5cd35ed22db8d7a7945e4c9d8f458fff090ff834456fd71770` |
| `rootfs.tar.bz2` | 12,381,400 B | `388301eaeb5bba569bd02b4814284ef307479020280799c4df11096b4b5b29ae` |
| `imx6ull-mini-yocto-sdcard.img` | 268,435,456 B | `b247c30ee7bbe912daa8bd7b41ddb9b81efe907e2e284deb8143e215d3a25946` |

U-Boot 与 dtb 和手写路线**字节一致**；zImage 差 576 B（Yocto 的内核编译选项与手写脚本不完全相同，功能等价）。

SD 整盘镜像布局（与 U-Boot `CONFIG_BOOTCOMMAND` 对齐）：

```text
扇区 0        MBR（分区 1 = Linux/ext4，起始 4 MiB，bootable）
偏移 1024     u-boot-dtb.imx（i.MX6ULL Boot ROM 的 IVT 位置，magic 0xd1002040 已校验）
偏移 4 MiB    ext4 根分区：/boot/zImage、/boot/*.dtb、BusyBox、/usr/bin/lvgl_demo、glibc
```

烧写：Windows 用 Win32DiskImager / Rufus / balenaEtcher 写整盘；Linux 用
`dd if=imx6ull-mini-yocto-sdcard.img of=/dev/sdX bs=4M conv=fsync`。

## 7. 踩坑清单（都是这条路线实际撞到的）

1. **tar 版本坑（最隐蔽）**：Ubuntu 24.04 的 `tar 1.35+dfsg-3ubuntu0.4` 改用 `openat2()`，与 poky 自带的 `pseudo 1.9.0` 不兼容，
   打包任务报 `got *at() syscall for unknown directory, fd 4` / `unknown base path for fd 4` / `mkdir: Bad address`。
   处理：容器里降级到 `tar_1.35+dfsg-3build1`（`dpkg -i --force-downgrade` + `apt-mark hold tar`）。
2. **依赖过滤 class 必须用事件处理器**：class 里的 `python () {}` 只对 base config 跑一次，对每个 recipe 无效；
   改成 `bb.event.RecipeParsed` 事件才生效。
3. **过滤范围要收窄**：曾遍历所有变量剔除 `kernel-module-`，把 `insane.bbclass` 里 QA 函数源码的换行压平，
   直接 `IndentationError`。最终只改 `RDEPENDS*/RRECOMMENDS*/RPROVIDES*/RSUGGESTS*` 且跳过含换行的值。
4. **`core-image` 会拖出 target gcc**：`core-image → meta-environment-extsdk → … → iptables` 引出一串 `kernel-module-*`；
   改 `inherit image` 后消失。
5. **poky 默认 `DISTRO_FEATURES` 带 `ptest`**：会把 `python3-ptest` 拉进 rootfs，它的 `RDEPENDS` 里有 `gcc`，
   于是整条 target gcc 链又开始编。`DISTRO_FEATURES:remove = "ptest"` 去掉。
6. **base-passwd 在本机打包必挂**：它的 `postinst-base-passwd` 落盘后丢可执行位（`chmod 0755` 之后仍是 0600），
   `do_package` 里执行它直接 `Permission denied`。`cleansstate`、`do_populate_sysroot:append` chmod 都无效，
   最终用本层精简 `base-passwd` 顶掉 poky 版本（只装 `/etc/passwd`、`/etc/group`）。
7. **postinst 拦截钩子连环失败**：rootfs 没有 man-db / desktop-file-utils / fontconfig / gdk-pixbuf，
   而 poky 的 `update_mandb`、`update_desktop_database` 等脚本照样跑，第一个 `sed /etc/man_db.conf` 就把 `do_rootfs` 打挂。
   处理：本层 `postinst-intercepts/` 放同名空脚本，`local.conf` 用 `POSTINST_INTERCEPTS_PATHS:prepend` 抢先命中。
8. **U-Boot `O=` 构建前的清理**：`make -C S O=B mrproper` 只清 build 目录，源码树里的手写中间物还在，
   必须先在源码树原地 `make -C S mrproper`，否则报 `source tree is not clean`。
9. **`bison` 不在任务 PATH**：任务环境只有 hosttools（有 `gcc/g++/cpp/make`，没有 `cc`、没有 `bison`），
   要 `DEPENDS += "bison-native flex-native"`，`EXTRA_OEMAKE` 里显式 `HOSTCC=gcc`。
10. **BusyBox 原地构建**：out-of-tree 会回源码树找 `scripts/kconfig/zconf.tab.c`；改原地构建后又撞
    `limits.h: No such file`（gcc 缺 `--sysroot`），`DEPENDS += "virtual/libc"` 并 `CC="${CC}"` 才通。
11. **QA 两道门**：BusyBox 的 `already-stripped`、`empty-dirs`（`/var/volatile`）用 `INSANE_SKIP` 放行；
    LVGL 的 `ldflags` 靠 `LDFLAGS="${LDFLAGS} …"` 真正修掉。
12. **不要把 `bitbake` 强杀**：会留下 stale server（`Reconnecting to bitbake server… No reply in 30s`）和半成品 `.o`，
   之后要 `bitbake -c cleansstate <recipe>` 才好。容器统一用 `--rm --init --name im6-yocto-build`，并且一份 TMPDIR 只能跑一个 bitbake。
13. **镜像脚本要用 `im6-build` 容器**：`im6-yocto` 里没有 `sfdisk`，拼 SD 镜像那步放 `im6-build:ubuntu24` 里跑。

## 8. 和手写路线的关系

两条路线共用 `components/` 的源码与板级配置，区别只在编排层：

- 手写：`tools/build-all.sh` 逐层调 `make`，rootfs 由 `components/busybox-rootfs/tools/build.sh` 组装，SD 镜像用 `tools/make-sdcard-image.sh`；
- Yocto：`bitbake` 负责依赖、打包、rootfs 组装，SD 镜像用 `tools/make-sdcard-from-yocto.sh`。

Yocto 路线多出来的是 **包管理、sstate 缓存、可复现的 manifest**（`rootfs.manifest` 能查到每个包的版本），
代价是第一次构建要编工具链（几千个 task，16 核约几十分钟），以及要处理上面那一串宿主/环境兼容问题。
