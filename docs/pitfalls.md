# 踩坑记录

按出现顺序记录，每条给出现象、原因、修法。

## 1. U-Boot 找不到自定义 dts（No rule to make target）

**现象**：dts 已放进 `dts/upstream/src/arm/nxp/imx/`，编译报
`No rule to make target 'arch/arm/dts/imx6ull-alientek-mini.dtb'`。

**原因**：该工程没有启用 `OF_UPSTREAM`（`CONFIG_OF_UPSTREAM` 未开），U-Boot 只在 `arch/arm/dts/` 下找 dtb 目标。

**修法**：把 dts 放到 `arch/arm/dts/imx6ull-alientek-mini.dts`，并在 `arch/arm/dts/Makefile` 的 `imx6ull-14x14-evk.dtb \` 后面追加 `imx6ull-alientek-mini.dtb \`。`dts/upstream/...` 那份只作副本保留。

## 2. 内核 dts 注册行插错 → recipe commences before first target

**现象**：`arch/arm/boot/dts/nxp/imx/Makefile:382: *** recipe commences before first target. Stop.`，但 `make` 只在日志里回显 `No change to .config`，真实错误被脚本吞掉。

**原因**：`imx6ull-14x14-evk.dtb \` 是**续行**（行尾反斜杠），在它后面另起一行写
`dtb-$(CONFIG_SOC_IMX6ULL) += imx6ull-alientek-mini-4.3.dtb` 会把列表打断，make 把下一行当成 recipe。

**修法**：写成同一列表的续行——`\timx6ull-alientek-mini-4.3.dtb \`，且注意 14x14-evk 那行本身以 `\` 结尾，追加后不能出现两个裸条目。另外注意 make 报错被 `make ... >/tmp/x.log 2>&1 || tail` 之类写法掩盖时，先看完整日志再改。

## 3. Windows 解包内核源码大量 `Can't create ... Invalid argument`

**现象**：`tar -xzf linux-x.tar.gz` 在 D 盘报几十个文件创建失败（`qcom,dispcc-sm8350.h`、`linux-event-codes.h` 等），Linux 树缺文件。

**原因**：这些条目是**符号链接**（`include/dt-bindings/clock/*.h` 大量软链到兄弟文件）。Windows 普通用户没有 `SeCreateSymbolicLinkPrivilege`，bsdtar 创建符号链接失败。

**修法**：打包时 `tar --dereference`，把软链换成正文件内容（git 在 Windows 上 `core.symlinks=false` 也是这么做的）。本次 `linux-7.3.6-src.tar.gz`、`lvgl-9.6.0-src.tar.gz` 都是这么打的。

## 4. BusyBox 编出 x86-64 二进制

**现象**：`make install CONFIG_PREFIX=rootfs` 之后 `file rootfs/bin/busybox` 显示 `ELF 64-bit LSB executable, x86-64`。

**原因**：`make` 与 `make install` 分两条命令，第二条没带 `ARCH`/`CROSS_COMPILE`，BusyBox 的 install 目标会隐式重新构建，用了宿主 gcc。

**修法**：两条命令都带同样的变量：

```bash
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc)
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- install CONFIG_PREFIX=rootfs
```

装完必须 `file` 验一遍。

## 5. host `strip` 把 ARM 程序删坏

**现象**：`strip: Unable to recognise the format of the input file 'rootfs/usr/bin/lvgl_demo'`，`set -e` 脚本在这里直接退出，后面的 init 脚本没生成。

**原因**：用了宿主 `strip`（x86 ELF）。

**修法**：`arm-linux-gnueabihf-strip`。同时脚本里 strip 失败不应中止整套流程，改成 `|| true` 或先 `file` 判架构。

## 6. rootfs 缺 `/init` → Kernel panic: VFS Unable to mount root fs

**现象**：`bootz` 后日志 `Trying to unpack rootfs image as initramfs...` 正常，随后
`No filesystem could mount root, tried: ext3 ext4 ext2 vfat` → `Kernel panic - not syncing: VFS: Unable to mount root fs on "/dev/ram0"`。

**原因**：上一轮脚本在 strip 处退出，`/init` 和 `/etc/init.d/rcS` 根本没写进 rootfs，cpio 里只有一个空壳；内核发现 initramfs 里没有 `/init`，回落去挂 `/dev/ram0`，自然没有文件系统。

**修法**：补齐 `/init` 后重打 cpio。检查手段：`cpio -t < rootfs.cpio.gz | head` 看有没有 `init`、`etc/init.d/rcS`；或启动日志里是否有 `Run /init as init process`。

## 7. `.cpio.gz` 直接 bootz → Wrong Ramdisk Image Format

**原因**：`bootz`（zImage 路径）要求 ramdisk 是 legacy uImage。

**修法**：`mkimage -A arm -O linux -T ramdisk -C gzip -n 'imx6ull mini initramfs' -d x.cpio.gz x.uimg`。

## 8. rcS 里 `/proc/sys/kernel/hotplug: nonexistent directory`

**原因**：新内核默认 `CONFIG_UEVENT_HELPER` 关闭，`/proc/sys/kernel/hotplug` 不存在。

**修法**：这行只是给 `mdev` 当 hotplug helper，`mdev -s` 仍能扫描 `/sys` 建节点；把 `echo` 加重定向容错或直接删掉即可，不影响启动。

## 9. QEMU 串口 socket 收不到任何输出

**现象**：`-serial unix:...,server=on,wait=off` 连上后 read 到空，QEMU 日志正常。

**原因**：`wait=off` 时 QEMU 不等客户端就连上，客户端连进来之前的早期输出（U-Boot 全部启动打印）已经丢了。

**修法**：用 `server=on,wait=on`，QEMU 阻塞到 socket 有客户端，之后从头收。

## 10. QEMU 上 U-Boot 卡死 / SNVS 复位

**原因**：i.MX6ULL 的 ANA bandgap 与 SNVS GPBIT 在 QEMU 模型里没实现：前者死等永远不置位，后者写 GPBIT 被当成复位。

**修法**：见 `docs/porting.md` 第 2 节的 `soc.c` 两处补丁（有界重试 + `#if 0` 屏蔽），真板不受影响。

## 11. 源码放在 Windows 挂载盘（9p）上编译慢到怀疑人生

**原因**：WSL 的 9p 文件共享，内核 8 万文件、U-Boot 3.8 万文件，每次 `make` 都在跨 VM 边界做 stat/read。

**修法**：`IM6_SRC=/tmp/im6-src bash tools/fetch-sources.sh`，把源码放到本地 ext4（`/tmp`、`~/`），编译完再 `tools/build-all.sh` 产物落回 `out/`。仅小改动用原地编译。

## 12. 重编 zImage 比原件小 8 字节

**现象**：同一份 `.config`/dts，重编 `zImage` 10,093,384 B，原件 10,093,392 B，`cmp` 有大量差异。

**原因**：内核版本串和构建时间戳进压缩流，压缩块边界随之变化；不是源码差异。判据是**同配置下 dtb 逐字节一致**（`1a41ee56…f95f9a`）。

**修法**：不比二进制哈希，比 `dtb` 哈希 + 启动日志里的版本串。要对齐时间戳可用 `KBUILD_BUILD_TIMESTAMP`。
