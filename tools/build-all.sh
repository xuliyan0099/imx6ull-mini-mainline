#!/usr/bin/env bash
# 一键构建四个组件，产物汇总到 <repo>/out：
#   bash tools/fetch-sources.sh     # 第一次：拉上游源码（已带者自动跳过）
#   bash tools/build-all.sh
# 可选环境变量：
#   IM6_SRC=<dir>    源码根目录，默认 <repo>/src
#   IM6_JOBS=16      并行度
#   IM6_CROSS=arm-linux-gnueabihf-
#   IM6_COMPONENTS=<dir>  组件仓库位置，默认 <repo>/components
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
C=${IM6_COMPONENTS:-$ROOT/components}
export IM6_SRC=${IM6_SRC:-$ROOT/src}
export IM6_CROSS=${IM6_CROSS:-arm-linux-gnueabihf-}
export IM6_JOBS=${IM6_JOBS:-$(nproc)}
OUT=$ROOT/out
mkdir -p "$OUT"

for tool in make cpio gzip mkimage "${IM6_CROSS}gcc"; do
  command -v "$tool" >/dev/null || { echo "缺少工具：$tool（apt install build-essential cpio gzip u-boot-tools gcc-arm-linux-gnueabihf）" >&2; exit 1; }
done
for comp in u-boot linux busybox-rootfs lvgl; do
  [ -d "$C/$comp" ] || { echo "缺少组件 $C/$comp，clone 时加 --recursive" >&2; exit 1; }
done

echo "== 1/4 U-Boot =="
bash "$C/u-boot/tools/build.sh"
cp "$C/u-boot/out/u-boot-dtb.imx" "$OUT/"

echo "== 2/4 Linux =="
bash "$C/linux/tools/build.sh"
cp "$C/linux/out/zImage" "$C/linux/out/imx6ull-alientek-mini-4.3.dtb" "$OUT/"

echo "== 3/4 LVGL 仪表盘 =="
bash "$C/lvgl/tools/build.sh"
cp "$C/lvgl/lvgl_demo" "$OUT/"

echo "== 4/4 BusyBox + initramfs =="
LVGL_DEMO="$OUT/lvgl_demo" bash "$C/busybox-rootfs/tools/build.sh"
cp "$C/busybox-rootfs/out/rootfs-mini.uimg" "$OUT/"

echo
echo "== 完成，产物 =="
ls -l "$OUT"
sha256sum "$OUT"/*
