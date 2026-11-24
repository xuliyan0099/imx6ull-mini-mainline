# imx6ull_port —— 正点原子 i.MX6ULL Mini 主线移植（5 仓库结构）

把 **Alientek i.MX6ULL Mini**（Cortex-A7 / 512 MiB DDR / ATK-4.3 RGBLCD 800×480 / GT911）的四层
软件栈全部换成上游最新版本，并把每层拆成独立仓库：**总仓库负责编排、文档和 QEMU 验证，
组件仓库各自能单独 clone、单独编译。**

| 组件 | 版本 | 仓库 | 产物 |
| --- | --- | --- | --- |
| U-Boot | v2026.10 | [imx6ull-mini-uboot](https://github.com/xuliyan0099/imx6ull-mini-uboot) | `u-boot-dtb.imx` 400,384 B |
| Linux | 7.3.6 | [imx6ull-mini-linux](https://github.com/xuliyan0099/imx6ull-mini-linux) | `zImage` 10,103,928 B + dtb 34,692 B |
| BusyBox + rootfs | 1.38.0 | [imx6ull-mini-busybox-rootfs](https://github.com/xuliyan0099/imx6ull-mini-busybox-rootfs) | `rootfs-mini.uimg` 1.6 MB |
| LVGL 仪表盘 | 9.6.0 | [imx6ull-mini-lvgl](https://github.com/xuliyan0099/imx6ull-mini-lvgl) | `lvgl_demo` 849 KB |
| 总仓库（本仓库） | — | imx6ull-mini-mainline | 编排 + 文档 + 统一 QEMU 验证 |

上游源码一律不进库：每个组件仓库的 `tools/fetch.sh` 按**钉死版本**拉取，`src/` 被 gitignore。

## 目录

```
imx6ull_port/                    # 本仓库
├── components/                  # 四个 submodule，各自独立仓库
│   ├── u-boot/                  # board/ 补丁+defconfig，tools/fetch.sh + build.sh
│   ├── linux/                   # board/ kernel.config + dts，tools/fetch.sh + build.sh
│   ├── busybox-rootfs/          # busybox.config + rootfs 骨架，tools/build.sh 打 initramfs
│   └── lvgl/                    # 800×480 仪表盘应用 + lv_conf.h
├── tools/
│   ├── fetch-sources.sh         # 依次调用四个组件的 fetch.sh（共用 src/）
│   ├── build-all.sh             # 依次构建四个组件，产物汇总到 out/
│   ├── install-to-qemu.sh       # 按统一命名装进 qemu/images
│   ├── verify-qemu.sh           # 统一 QEMU 冷启动 + 抓屏
│   └── ppm2png.py
├── docs/                        # porting.md / pitfalls.md（12 条）/ recovery.md / 抓屏证据
├── recovered/                   # 反编译得到的 dts 与抽出的内核 config（溯源用）
├── patches/                     # 离线 git bundle（不入库）
├── reference/                   # 旧 7.3.5 固件原件（仅本地对照，不入库）
└── src/  out/                   # 上游源码与产物（gitignore）
```

## 快速开始

依赖（Debian/Ubuntu）：

```bash
sudo apt install build-essential bison flex bc libssl-dev cpio gzip u-boot-tools \
                 gcc-arm-linux-gnueabihf device-tree-compiler
```

```bash
git clone --recursive https://github.com/xuliyan0099/imx6ull-mini-mainline.git imx6ull_port
cd imx6ull_port
bash tools/fetch-sources.sh      # 拉四份上游源码到 src/，套用各组件 board/ 配置
bash tools/build-all.sh          # 编四个组件，产物汇总到 out/
```

只想要某一层，直接进 `components/<组件>` 里 `bash tools/build.sh`，它会自动 fetch 自己的上游源码，
不依赖总仓库（`src/` 默认落在该组件目录下）。

源码放 Windows 挂载的 9p 盘上编译会慢一个量级，建议 `IM6_SRC=/tmp/im6-src` 指到本地 ext4。
网络受限时：`IM6_UB_URL / IM6_LX_URL / IM6_BB_URL / IM6_LV_URL` 换镜像，
`IM6_LX_FILE / IM6_BB_FILE` 指本地 tar 包（`busybox.net` 在部分网络下 TLS 会被重置，脚本已带
Buildroot / Alpine 镜像回退）。

## 接入统一 QEMU

```bash
IM6_QEMU=<qemu 工程目录> bash tools/install-to-qemu.sh
IM6_QEMU=<qemu 工程目录> bash tools/verify-qemu.sh
```

`install-to-qemu.sh` 把 `out/` 三个产物按网页虚拟开发板认的名字落到 `qemu/images/`
（`zImage-mini-upstream` / `imx6ull-alientek-mini-4.3.dtb` / `rootfs-mini.uimg`，覆盖前留 `.previous`）。
之后打开 `qemu/scripts/run-virtual-board.cmd`，配置选 **「Linux / imx6ull_port（LVGL 9.6）」**，服务会自动执行：

```text
mmc dev 0
fatload mmc 0:1 0x80800000 zImage
fatload mmc 0:1 0x83000000 mini.dtb
fatload mmc 0:1 0x84000000 initrd.uim
setenv bootargs console=ttymxc0,115200 root=/dev/ram0 rw
bootz 0x80800000 0x84000000 0x83000000
```

`IM6_QEMU` 不指定时按 `../../04_Linux_and_QEMU/02_QEMU_Workspace/qemu → ../qemu → ./qemu` 自动探测，
找不到就报错退出，不写死任何本机路径。

## 烧到真板

| 产物 | 烧写位置 |
| --- | --- |
| `out/u-boot-dtb.imx` | SD/eMMC 偏移 `0x400`（`dd bs=512 seek=2` 或 MfgTool） |
| `out/zImage`、`out/imx6ull-alientek-mini-4.3.dtb` | 第一分区 `/boot/`（U-Boot `ext4load ... /boot/zImage`） |
| `out/rootfs-mini.uimg` | initramfs 方式：`fatload` 到 0x84000000；常驻系统可解包成 ext4 根分区 |

## 验证结果（2026-11-25，QEMU 11.1.0 / `mcimx6ull-alientek`）

- U-Boot：`U-Boot 2026.10`、`Model: Alientek i.MX6ULL Mini`、`DRAM: 512 MiB`、`FSL_SDHC: 0, 1` → `=>`。
- 内核：`Linux version 7.3.6`，`imx6ull-mini: rootfs ready`，`ttymxc0` 出 shell。
- LVGL：800×480 全屏仪表盘（CPU/内存/进程三卡、60 秒曲线、uptime），触摸识别 `Goodix Capacitive TouchScreen`。
- DTB 与旧固件逐字节一致（sha256 `1a41ee56…f95f9a`）。

![QEMU 启动画面](docs/qemu-boot.png)

## 维护 submodule

```bash
git submodule update --init --recursive     # 拉齐四个组件
git submodule update --remote --merge       # 跟随各组件 main 最新
cd components/lvgl && git checkout -b feat/xxx && ... && git push    # 组件里单独开发
```

## 已知限制

- QEMU 不实现 `imx_thermal` 校准数据与 `pwm-backlight`，日志两条 probe 失败，不影响显示。
- QEMU 的 GT911 模型只报单点，`TOUCH` 恒显示 `0,0`；真板才有真实坐标。
- 未提供 eMMC 整盘烧写镜像，`uboot-emmc.img` 仍是既有基座。
- `lvgl_demo` 为静态 glibc 链接；要塞进厂商动态 rootfs 需换 SDK 编译（见 `docs/porting.md`）。

许可：本仓库脚本与文档 MIT；四个组件仓库各自注明，上游源码遵循其原许可（GPL-2.0 / GPL-2.0+ / MIT）。
