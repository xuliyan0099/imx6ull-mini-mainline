#!/usr/bin/env bash
# 拉取四个上游源码（版本全部钉死），并把 board/ 里的板级配置套上去。
#   bash tools/fetch-sources.sh
# 可选环境变量（内网镜像/离线包时用）：
#   IM6_SRC=/path/to/src          源码放哪儿，默认 <repo>/src
#   IM6_UB_URL / IM6_LX_URL / IM6_BB_URL / IM6_LV_URL
#   IM6_FORCE=1                   已存在也重新拉取
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=${IM6_SRC:-$ROOT/src}
BOARD=$ROOT/board
mkdir -p "$SRC"

UB_TAG=v2026.10
LX_VER=7.3.6
LX_SHA=8183d475a76a0faffa92d6cd500af421f589dfd0300a0f1060bb875e11d45723
BB_VER=1.38.0
BB_SHA=34f9ea6ff8636f2c9241153b9114eefa9e65674a45318ae1ef95bb5f31c53bb2
LV_TAG=v9.6.0

UB_URL=${IM6_UB_URL:-https://github.com/u-boot/u-boot.git}
LX_URL=${IM6_LX_URL:-https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$LX_VER.tar.xz}
BB_URL=${IM6_BB_URL:-https://busybox.net/downloads/busybox-$BB_VER.tar.bz2}
LV_URL=${IM6_LV_URL:-https://github.com/lvgl/lvgl.git}

: "${IM6_FORCE:=0}"

echo "== U-Boot $UB_TAG =="
if [ ! -d "$SRC/u-boot/.git" ] || [ "$IM6_FORCE" = 1 ]; then
  rm -rf "$SRC/u-boot"
  git clone --depth 1 --branch "$UB_TAG" "$UB_URL" "$SRC/u-boot"
fi
cd "$SRC/u-boot"
if git apply --check "$BOARD/u-boot/0001-mx6ull-alientek-mini-port.patch" 2>/dev/null; then
  git apply "$BOARD/u-boot/0001-mx6ull-alientek-mini-port.patch"
  echo "   补丁已应用"
else
  echo "   补丁已应用过（跳过）"
fi

echo "== Linux $LX_VER =="
if [ ! -f "$SRC/linux/Makefile" ] || [ "$IM6_FORCE" = 1 ]; then
  rm -rf "$SRC/linux" "$SRC/linux-$LX_VER"
  TMP=$(mktemp -d)
  curl -fL --retry 3 -o "$TMP/linux.tar.xz" "$LX_URL"
  echo "$LX_SHA  $TMP/linux.tar.xz" | sha256sum -c -
  tar -xJf "$TMP/linux.tar.xz" -C "$SRC"
  mv "$SRC/linux-$LX_VER" "$SRC/linux"
  rm -rf "$TMP"
fi
cp "$BOARD/linux/kernel.config" "$SRC/linux/.config"
cp "$BOARD/linux/imx6ull-alientek-mini-4.3.dts" "$SRC/linux/arch/arm/boot/dts/nxp/imx/"
MK=$SRC/linux/arch/arm/boot/dts/nxp/imx/Makefile
if ! grep -q 'imx6ull-alientek-mini-4.3.dtb' "$MK"; then
  sed -i 's#^\timx6ull-14x14-evk.dtb \\#\timx6ull-14x14-evk.dtb \\\n\timx6ull-alientek-mini-4.3.dtb \\#' "$MK"
  echo "   设备树已注册"
fi

echo "== BusyBox $BB_VER =="
if [ ! -f "$SRC/busybox/Makefile" ] || [ "$IM6_FORCE" = 1 ]; then
  rm -rf "$SRC/busybox" "$SRC/busybox-$BB_VER"
  TMP=$(mktemp -d)
  curl -fL --retry 3 -o "$TMP/bb.tar.bz2" "$BB_URL"
  echo "$BB_SHA  $TMP/bb.tar.bz2" | sha256sum -c -
  tar -xjf "$TMP/bb.tar.bz2" -C "$SRC"
  mv "$SRC/busybox-$BB_VER" "$SRC/busybox"
  rm -rf "$TMP"
fi
cp "$BOARD/busybox/busybox.config" "$SRC/busybox/.config"

echo "== LVGL $LV_TAG =="
if [ ! -f "$SRC/lvgl/lv_version.h" ] || [ "$IM6_FORCE" = 1 ]; then
  rm -rf "$SRC/lvgl"
  git clone --depth 1 --branch "$LV_TAG" "$LV_URL" "$SRC/lvgl"
fi

echo
echo "源码就绪：$SRC"
ls -d "$SRC"/*/
