#!/usr/bin/env bash
# 一键构建 U-Boot / Linux / LVGL 仪表盘 / BusyBox rootfs，产物写到 out/。
#   bash tools/fetch-sources.sh     # 第一次：拉上游源码并套板级配置
#   bash tools/build-all.sh
# 可选环境变量：
#   IM6_SRC=<dir>      源码目录，默认 <repo>/src
#   IM6_JOBS=16        并行度
#   IM6_CROSS=arm-linux-gnueabihf-
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=${IM6_SRC:-$ROOT/src}
CROSS=${IM6_CROSS:-arm-linux-gnueabihf-}
JOBS=${IM6_JOBS:-$(nproc)}
OUT=$ROOT/out

for tool in make cpio gzip mkimage "${CROSS}gcc"; do
  command -v "$tool" >/dev/null || { echo "缺少工具：$tool（apt install build-essential cpio gzip u-boot-tools gcc-arm-linux-gnueabihf）" >&2; exit 1; }
done
[ -f "$SRC/linux/Makefile" ] || { echo "源码未就绪，先跑 bash tools/fetch-sources.sh" >&2; exit 1; }
mkdir -p "$OUT"

echo "== 1/4 U-Boot =="
make -C "$SRC/u-boot" mx6ull_alientek_mini_defconfig >/dev/null
make -C "$SRC/u-boot" CROSS_COMPILE="$CROSS" -j"$JOBS"
cp "$SRC/u-boot/u-boot-dtb.imx" "$OUT/u-boot-dtb.imx"

echo "== 2/4 Linux =="
make -C "$SRC/linux" ARCH=arm CROSS_COMPILE="$CROSS" olddefconfig
make -C "$SRC/linux" ARCH=arm CROSS_COMPILE="$CROSS" -j"$JOBS" zImage dtbs
cp "$SRC/linux/arch/arm/boot/zImage" "$OUT/zImage"
cp "$SRC/linux/arch/arm/boot/dts/nxp/imx/imx6ull-alientek-mini-4.3.dtb" "$OUT/"

echo "== 3/4 LVGL 仪表盘（静态）=="
make -C "$ROOT/app/lvgl" clean static CC="${CROSS}gcc" STRIP="${CROSS}strip" LVGL_DIR="$SRC/lvgl"
cp "$ROOT/app/lvgl/lvgl_demo" "$OUT/lvgl_demo"

echo "== 4/4 BusyBox + initramfs =="
make -C "$SRC/busybox" ARCH=arm CROSS_COMPILE="$CROSS" -j"$JOBS"
R=$(mktemp -d /tmp/im6-rootfs.XXXX)
make -C "$SRC/busybox" ARCH=arm CROSS_COMPILE="$CROSS" install CONFIG_PREFIX="$R" >/dev/null
mkdir -p "$R"/{dev,proc,sys,tmp,run,var/log,root,etc/init.d,usr/bin}
chmod 1777 "$R/tmp"
cp "$ROOT/rootfs/init" "$R/init"
cp "$ROOT/rootfs/etc/init.d/rcS" "$R/etc/init.d/rcS"
cp "$ROOT/rootfs/etc/inittab" "$ROOT/rootfs/etc/fstab" "$ROOT/rootfs/etc/profile" "$R/etc/"
chmod 755 "$R/init" "$R/etc/init.d/rcS"
cp "$OUT/lvgl_demo" "$R/usr/bin/lvgl_demo"

(cd "$R" && find . -print0 | cpio --null -o --format=newc --owner=0:0 2>/dev/null | gzip -9) > /tmp/rootfs-mini.cpio.gz
mkimage -A arm -O linux -T ramdisk -C gzip -n 'imx6ull mini initramfs' \
        -d /tmp/rootfs-mini.cpio.gz "$OUT/rootfs-mini.uimg" >/dev/null
rm -rf "$R"

echo
echo "== 完成，产物 =="
ls -l "$OUT"
sha256sum "$OUT"/*
