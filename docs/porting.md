# 移植文档：官方最新内核/U-Boot 落到 Alientek i.MX6ULL Mini

目标：用上游最新版本（U-Boot v2026.10 / Linux 7.3.6 / BusyBox 1.38.0 / LVGL 9.6.0）在正点原子 i.MX6ULL Mini 上跑起来，不依赖厂商 BSP 树。

## 1. 板级事实

| 项 | 值 |
| --- | --- |
| SoC | Freescale i.MX6ULL（Cortex-A7 单核，528/792 MHz OPP） |
| DDR | 512 MiB，起始 0x80000000 |
| 屏幕 | ATK-4.3 RGBLCD，800×480，31.5 MHz 像素时钟，XRGB8888，背光 GPIO1_IO08 |
| 触摸 | Goodix GT911，I2C2，地址 0x14（INT 低电平锁存），中断 GPIO1_IO09 |
| 存储 | SD0（TF 卡）/ SD1（eMMC），U-Boot 环境区 eMMC 偏移 0xC0000 |
| 串口 | UART1 `ttymxc0`，115200 |

## 2. U-Boot v2026.10

U-Boot 部分在独立仓库 `components/u-boot`（[imx6ull-mini-uboot](https://github.com/xuliyan0099/imx6ull-mini-uboot)），改动集中在一个补丁（`components/u-boot/board/0001-mx6ull-alientek-mini-port.patch`）：

1. `configs/mx6ull_alientek_mini_defconfig`
   - 复用上游 `mx6ull_14x14_evk` 的 SoC 目标（`CONFIG_TARGET_MX6ULL_14X14_EVK=y`），只改板级差异。
   - `CONFIG_TEXT_BASE=0x87800000`、`CONFIG_ENV_IS_IN_MMC=y`、`CONFIG_ENV_OFFSET=0xC0000`、`CONFIG_ENV_MMC_DEVICE_INDEX=1`。
   - `CONFIG_DEFAULT_DEVICE_TREE="imx6ull-alientek-mini"`。
   - 双路 `BOOTCOMMAND`：先 `mmc dev 0`（TF）`ext4load ... /boot/zImage`，失败再 `mmc dev 1`（eMMC）；两路的 root 分别 `mmcblk0p1` / `mmcblk1p2`。
   - 以太网按 MINI 实际只引出的 ENET2 走 RMII + KSZ8XXX PHY（`CONFIG_PHY_MICREL_KSZ8XXX=y`）。
2. `arch/arm/dts/imx6ull-alientek-mini.dts`（必须放这里，工程没开 `OF_UPSTREAM`）
   - 以 EVK dts 为骨架，改 LCD 时序 800×480、触摸节点 `goodix_ts@14`、删掉板上没有的器件。
   - 同一份副本放 `dts/upstream/src/arm/nxp/imx/` 只为兼容将来开启 OF_UPSTREAM 的布局。
3. `arch/arm/mach-imx/mx6/soc.c`（QEMU 兼容，真板同样能跑）
   - ANA bandgap 等待改为**有界重试**：`val = 100000; while (!(readl(...) & 0x80) && --val);`。QEMU 的 `ANA_MISC0` 不实现该位，原代码死等会挂死。
   - `is_mx6ul()` 分支里的 SNVS `GPBIT` / `PMIC_STBY_REQ` pad 配置用 `#if 0 ... #endif` 屏蔽。QEMU 的 SNVS 把 GPBIT 写当复位，真板无影响（该分支只是把这两个 pad 设成 GPIO 输出）。

构建：

```bash
bash components/u-boot/tools/build.sh
# 内部仍是 make defconfig + make，源码在 src/u-boot
# 产物 components/u-boot/out/u-boot-dtb.imx，400,384 B（偏移 0x400 有 IVT，可写 eMMC/SD）
```

## 3. Linux 7.3.6

内核部分在独立仓库 `components/linux`（[imx6ull-mini-linux](https://github.com/xuliyan0099/imx6ull-mini-linux)），内核本身没有厂商改动，靠三样东西落到板上：

1. **`.config`**：来源是旧固件 `zImage` 里 IKCFG 段反推出的真实配置（`docs/recovery.md`），7.3.6 上跑 `olddefconfig` 后仅补齐新增符号。关键项：`CONFIG_SOC_IMX6UL=y`、`CONFIG_DRM_MXS=y` + `CONFIG_DRM_MXSFB=y` + `CONFIG_DRM_FBDEV_EMULATION=y`（mxsfb 走 DRM，靠 fbdev 仿真出 `/dev/fb0`）、`CONFIG_INPUT_EVDEV`、`CONFIG_TOUCHSCREEN_GOODIX`、`CONFIG_MMC_SDHCI_ESDHC_IMX`、`CONFIG_FEC`、`CONFIG_EXT4_FS`、`CONFIG_BLK_DEV_INITRD`、gzip 压缩内核。
2. **`arch/arm/boot/dts/nxp/imx/imx6ull-alientek-mini-4.3.dts`**：直接由旧固件 dtb 反编译（1567 行），`model` = `Alientek i.MX6ULL Mini (ATK-4.3RGBLCD 800x480)`，`compatible` 仍沿用 `fsl,imx6ull-14x14-evk`，所以复用 EVK 的机器描述。
   - 显示：`display-timings` 800×480@31.5 MHz，`mxcfb` 节点 32bpp，`pwm-backlight` 挂 GPIO1_IO08。
   - 触摸：`goodix_ts@14` 在 `i2c2`，`interrupt-parent` 走 GPIO1。
   - 网络：只使能 ENET2（`&fec2`），PHY 复位脚按 MINI 底板。
3. **`arch/arm/boot/dts/nxp/imx/Makefile` 注册行**：在 `imx6ull-14x14-evk.dtb \` 同一列表里追加 `imx6ull-alientek-mini-4.3.dtb \`（续行写法，见踩坑记录第 2 条）。

构建：

```bash
bash components/linux/tools/build.sh
# 内部：olddefconfig + make zImage dtbs，源码在 src/linux
```

结果：`zImage` 10,103,928 B，`imx6ull-alientek-mini-4.3.dtb` 34,692 B。DTB 与旧固件 sha256 完全一致（`1a41ee56…f95f9a`），说明设备树还原无误差。

## 4. BusyBox 1.38.0 + initramfs

- 配置：静态链接（`CONFIG_STATIC=y`）、`vi` 行编辑、完整 modutils，`CONFIG_PREFIX="./_install"`。
- rootfs 由 `make install CONFIG_PREFIX=<rootfs>` 生成，再补：
  - `/init`：PID 1，挂 proc/sys/devtmpfs/devpts 后 `exec /sbin/init`；
  - `/etc/init.d/rcS`：`mount -a`、`mdev -s`、`hostname imx6ull-mini`、关 `vtcon1`（防止 fbcon 画到 LVGL 上）、把 cpufreq 固定到 `performance`（`ondemand` 在无触摸时会掉到 198 MHz，正好卡 UI 重绘）、后台拉起 `/usr/bin/lvgl_demo`，最后打印 `imx6ull-mini: rootfs ready`；
  - `/etc/inittab`：`ttymxc0::askfirst:-/bin/sh`，串口保留控制台。
- 打包：`find . | cpio -o -H newc | gzip -9` → `mkimage -A arm -O linux -T ramdisk -C gzip`。**必须是 uImage 包装**，直接给 `.cpio.gz` 会被 `bootz` 判 `Wrong Ramdisk Image Format`。

## 5. LVGL 9.6.0 仪表盘

四个源文件（`components/lvgl/src`，仓库 [imx6ull-mini-lvgl](https://github.com/xuliyan0099/imx6ull-mini-lvgl)）：

| 文件 | 职责 |
| --- | --- |
| `main.c` | `lv_init()`、tick 线程、主循环 `lv_timer_handler()` |
| `display.c` | `mmap` `/dev/fb0`，`FBIOGET_VSCREENINFO` 读分辨率，40 行分块 flush，XRGB8888/BGRA 直拷、16bpp 转 RGB565 |
| `input.c` | 扫描 `/dev/input/event0..9`，取第一个带 `ABS_X/ABS_Y` 的设备，`EVIOCGABS` 原始范围映射，支持 `LVGL_TOUCH_SWAP/INVERT_X/INVERT_Y` |
| `ui.c` | 800×480 仪表盘：顶栏时间、CPU/内存/进程三卡、60 秒 CPU 曲线、uptime/loadavg/触摸信息 |

- `config/lv_conf.h`：4 MB 内存池、`LV_COLOR_DEPTH 32`、Montserrat 14/16/20/28。
- 交叉编译（静态，rootfs 里不需要额外库）：

```bash
bash components/lvgl/tools/build.sh       # 静态链接 + 交叉 strip
# 等价于 make -C components/lvgl static CC=arm-linux-gnueabihf-gcc LVGL_DIR=<src/lvgl>
```

## 6. 统一 QEMU 接入约定

QEMU 工程里的网页虚拟开发板只认三个固定文件名，`tools/install-to-qemu.sh` 就是做这件事：

| 产物 | 装到 `qemu/images/` 的文件名 |
| --- | --- |
| `out/zImage` | `zImage-mini-upstream` |
| `out/imx6ull-alientek-mini-4.3.dtb` | `imx6ull-alientek-mini-4.3.dtb` |
| `out/rootfs-mini.uimg` | `rootfs-mini.uimg` |

安装后网页选「Linux / imx6ull_port（LVGL 9.6）」，服务会自动把三个文件塞进 vvfat，再在 U-Boot 里发第 6 节的 `fatload` 命令块。命令行等价入口是 `tools/verify-qemu.sh`（同一二进制 `bin/qemu-system-arm-im6`、同一机型 `mcimx6ull-alientek`、同一 bootargs）。
