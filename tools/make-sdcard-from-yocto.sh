#!/usr/bin/env bash
# 从 Yocto 的产物生成可直接烧 SD 卡的整盘镜像（U-Boot + ext4 rootfs 一体）。
#   bash tools/make-sdcard-from-yocto.sh
#
# 与手写路线 tools/make-sdcard-image.sh 的区别：rootfs 不再来自 busybox 安装树，
# 直接拿 Yocto 生成的 ext4 镜像（里面已经含 /boot/zImage、dtb、lvgl_demo、busybox，
# 因为 linux-imx6ull-mini / lvgl-demo / busybox-imx6ull-mini 都进了 IMAGE_INSTALL）。
#
# 环境变量：
#   YOCTO_DEPLOY=<dir>   Yocto deploy 目录，默认 <repo>/../yocto/tmp/deploy/images/imx6ull-mini
#   IM6_IMG=<file>       输出镜像，默认 <repo>/out/imx6ull-mini-yocto-sdcard.img
#   IM6_IMG_MB=256       最少 4+rootfs 大小，不足会自动放大
#
# 布局（与 U-Boot CONFIG_BOOTCOMMAND 对齐，和手写路线一致）：
#   扇区 0        MBR（分区 1 = Linux/ext4，起始 4 MiB）
#   偏移 1024     u-boot-dtb.imx（i.MX6ULL Boot ROM 的 IVT 位置）
#   偏移 4 MiB    ext4 根分区
# 依赖：dd truncate sfdisk mke2fs（e2fsprogs）debugfs
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEPLOY=${YOCTO_DEPLOY:-$ROOT/../yocto/tmp/deploy/images/imx6ull-mini}
OUT=${IM6_OUT:-$ROOT/out}
IMG=${IM6_IMG:-$OUT/imx6ull-mini-yocto-sdcard.img}
MIN_MB=${IM6_IMG_MB:-256}
START_MB=4

UBOOT=${IM6_UBOOT:-$DEPLOY/u-boot-dtb.imx}
ROOTFS_EXT4=${IM6_ROOTFS_EXT4:-$(ls -1 "$DEPLOY"/imx6ull-mini-image-imx6ull-mini*.ext4 2>/dev/null | head -1)}

for tool in dd truncate sfdisk mke2fs debugfs; do
  command -v "$tool" >/dev/null || { echo "缺少工具：$tool（apt install e2fsprogs fdisk util-linux）" >&2; exit 1; }
done
[ -f "$UBOOT" ] || { echo "缺少 $UBOOT，先跑 tools/yocto-build.sh" >&2; exit 1; }
[ -f "$ROOTFS_EXT4" ] || { echo "缺少 Yocto ext4 rootfs（$DEPLOY/*.ext4），先跑 tools/yocto-build.sh" >&2; exit 1; }

mkdir -p "$OUT"
ROOTFS_MB=$(( ($(stat -c %s "$ROOTFS_EXT4") + 1024*1024 - 1) / (1024*1024) ))
SIZE_MB=$(( START_MB + ROOTFS_MB + 8 ))
[ "$SIZE_MB" -lt "$MIN_MB" ] && SIZE_MB=$MIN_MB

echo "rootfs: $(basename "$ROOTFS_EXT4") = ${ROOTFS_MB} MiB → 整盘 ${SIZE_MB} MiB"

rm -f "$IMG"
truncate -s "${SIZE_MB}M" "$IMG"
PART_SEC=$(( (SIZE_MB - START_MB) * 1024 * 1024 / 512 ))
sfdisk --quiet "$IMG" >/dev/null <<EOF
label: dos
label-id: 0x1a6b0001
start=8192, size=$PART_SEC, type=83, bootable
EOF

# U-Boot 落在 1024 字节（i.MX IVT 固定位置），不覆盖 MBR
dd if="$UBOOT" of="$IMG" bs=1024 seek=1 conv=notrunc status=none
echo "   U-Boot 写入偏移 1024（$(stat -c %s "$UBOOT") 字节）"

# rootfs 直接拷贝 Yocto 的 ext4 镜像到 4 MiB 处
dd if="$ROOTFS_EXT4" of="$IMG" bs=1M seek="$START_MB" conv=notrunc status=none

# 自检
echo
echo "== 镜像自检 =="
sfdisk -l "$IMG" 2>/dev/null | sed -n '1,10p'
MAGIC=$(dd if="$IMG" bs=1 count=4 skip=1024 status=none | od -An -tx1 | tr -d ' \n')
echo "offset 1024 magic: $MAGIC  (i.MX6 IVT 期望 d1002040)"
[ "$MAGIC" = "d1002040" ] || { echo "!! U-Boot 头部不对" >&2; exit 1; }
PART=$(( START_MB * 1024 * 1024 ))
dd if="$IMG" of=/tmp/part1-check.ext4 bs=1M skip=$START_MB count=$ROOTFS_MB status=none
echo "分区内顶层："
debugfs -R 'ls -l /' /tmp/part1-check.ext4 2>/dev/null | sed 's/^/  /'
echo "分区内 /boot："
debugfs -R 'ls -l /boot' /tmp/part1-check.ext4 2>/dev/null | sed 's/^/  /'
rm -f /tmp/part1-check.ext4
echo
ls -l "$IMG"
sha256sum "$IMG"
