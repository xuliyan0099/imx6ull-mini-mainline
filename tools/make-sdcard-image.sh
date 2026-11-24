#!/usr/bin/env bash
# 生成可直接烧到 SD 卡的整盘镜像（U-Boot + ext4 rootfs 一体的 .img）。
#   bash tools/make-sdcard-image.sh
# 前置：先跑 bash tools/build-all.sh（需要 out/ 里的 u-boot-dtb.imx / zImage / dtb / lvgl_demo），
#       以及 components/busybox-rootfs/out/rootfs 安装树（build.sh 会生成）。
# 产物：out/imx6ull-mini-sdcard.img（默认 256 MB，MBR + 单 ext4 分区）
#
# 环境变量：
#   IM6_OUT=<dir>        产物目录，默认 <repo>/out
#   IM6_IMG=<file>       输出镜像路径
#   IM6_IMG_MB=256       镜像总大小（>=64）
#   IM6_ROOTFS_STAGE=<dir> rootfs 安装树，默认 components/busybox-rootfs/out/rootfs
#   IM6_UBOOT / IM6_ZIMAGE / IM6_DTB / IM6_LVGL_DEMO  覆盖默认输入文件
#
# 布局（与 U-Boot 的 CONFIG_BOOTCOMMAND 对齐）：
#   扇区 0            MBR（分区 1 = Linux/ext4，起始 4 MiB）
#   偏移 1024 字节    u-boot-dtb.imx（i.MX6ULL Boot ROM 的 IVT 位置）
#   偏移 4 MiB 起     ext4 分区：/boot/zImage、/boot/*.dtb、busybox rootfs、/usr/bin/lvgl_demo
# 依赖：dd、truncate、sfdisk（或 parted）、mke2fs（e2fsprogs）
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${IM6_OUT:-$ROOT/out}
IMG=${IM6_IMG:-$OUT/imx6ull-mini-sdcard.img}
SIZE_MB=${IM6_IMG_MB:-256}
STAGE=${IM6_ROOTFS_STAGE:-$ROOT/components/busybox-rootfs/out/rootfs}
UBOOT=${IM6_UBOOT:-$OUT/u-boot-dtb.imx}
ZIMAGE=${IM6_ZIMAGE:-$OUT/zImage}
DTB=${IM6_DTB:-$OUT/imx6ull-alientek-mini-4.3.dtb}
LVGL=${IM6_LVGL_DEMO:-$OUT/lvgl_demo}

START_MB=4

for tool in dd truncate mke2fs sfdisk; do
  command -v "$tool" >/dev/null || { echo "缺少工具：$tool（apt install e2fsprogs fdisk）" >&2; exit 1; }
done
for f in "$UBOOT" "$ZIMAGE" "$DTB"; do
  [ -f "$f" ] || { echo "缺少 $f，先跑 tools/build-all.sh" >&2; exit 1; }
done
[ -d "$STAGE" ] || { echo "缺少 rootfs 安装树 $STAGE，先跑 components/busybox-rootfs/tools/build.sh" >&2; exit 1; }
[ "$SIZE_MB" -ge 64 ] || { echo "IM6_IMG_MB 至少 64" >&2; exit 1; }

mkdir -p "$OUT"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/im6-sd.XXXX")
trap 'rm -rf "$WORK"' EXIT

# 1) 组装分区内容：rootfs 安装树 + /boot
cp -a "$STAGE" "$WORK/rootfs"
mkdir -p "$WORK/rootfs/boot" "$WORK/rootfs/usr/bin"
cp "$ZIMAGE" "$WORK/rootfs/boot/zImage"
cp "$DTB"    "$WORK/rootfs/boot/$(basename "$DTB")"
if [ -f "$LVGL" ]; then
  cp "$LVGL" "$WORK/rootfs/usr/bin/lvgl_demo"
else
  echo "!! 没有 $LVGL，镜像里不带 LVGL 仪表盘" >&2
fi

# 2) 整盘镜像骨架：MBR + 4 MiB 前的空隙留给 U-Boot / 环境变量
rm -f "$IMG"
truncate -s "${SIZE_MB}M" "$IMG"
PART_SEC=$(( (SIZE_MB - START_MB) * 1024 * 1024 / 512 ))
sfdisk --quiet "$IMG" >/dev/null <<EOF
label: dos
label-id: 0x1a6b0001
start=8192, size=$PART_SEC, type=83, bootable
EOF

# 3) U-Boot 落在 1024 字节（i.MX IVT 固定位置），不覆盖 MBR
dd if="$UBOOT" of="$IMG" bs=1024 seek=1 conv=notrunc status=none
echo "   U-Boot 写入偏移 1024（$(stat -c %s "$UBOOT") 字节）"

# 4) ext4 分区先在独立文件里格式化并灌入内容（不需要 mount / loop 权限）
PART="$WORK/part1.ext4"
truncate -s "$((PART_SEC * 512))" "$PART"
mke2fs -q -t ext4 -b 4096 -L imx6ull-mini -m 0 -E root_owner=0:0 \
       -d "$WORK/rootfs" "$PART"
dd if="$PART" of="$IMG" bs=1M seek="$START_MB" conv=notrunc status=none

# 5) 自检
echo
echo "== 镜像自检 =="
sfdisk -l "$IMG" 2>/dev/null | sed -n '1,12p'
MAGIC=$(dd if="$IMG" bs=1 count=4 skip=1024 status=none | od -An -tx1 | tr -d ' \n')
echo "offset 1024 magic: $MAGIC  (i.MX6 IVT 期望 d1002040)"
[ "$MAGIC" = "d1002040" ] || { echo "!! U-Boot 头部不对" >&2; exit 1; }
echo "分区内文件："
debugfs -R 'ls -l /' "$PART" 2>/dev/null | sed 's/^/  /'
debugfs -R 'ls -l /boot' "$PART" 2>/dev/null | sed 's/^/  /'
echo
ls -l "$IMG"
sha256sum "$IMG"
echo
echo "烧写：Linux  dd if=$(basename "$IMG") of=/dev/sdX bs=4M status=progress conv=fsync"
echo "      Windows  用 Win32DiskImager / Rufus / balenaEtcher 选整盘写入"
