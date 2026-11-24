#!/usr/bin/env bash
# 把 out/ 里的固件按统一 QEMU 命名装进 qemu/images，供网页虚拟开发板直接启动。
#   IM6_QEMU=<qemu 工程目录> bash tools/install-to-qemu.sh
# 不指定时自动在仓库上两级目录里找 04_Linux_and_QEMU/02_QEMU_Workspace/qemu。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
QEMU=${IM6_QEMU:-}
if [ -z "$QEMU" ]; then
  for c in "$ROOT/../../04_Linux_and_QEMU/02_QEMU_Workspace/qemu" "$ROOT/../qemu" "$ROOT/qemu"; do
    [ -d "$c/images" ] && QEMU=$(cd "$c" && pwd) && break
  done
fi
[ -n "$QEMU" ] && [ -d "$QEMU/images" ] || { echo "找不到 QEMU 工程，设置 IM6_QEMU 指向 qemu 目录（含 bin/ 与 images/）" >&2; exit 1; }

IMG=$QEMU/images
install_one() {
  local src=$1 dst=$IMG/$2
  [ -f "$src" ] || { echo "缺少产物：$src（先跑 tools/build-all.sh）" >&2; exit 1; }
  [ -f "$dst.previous" ] || cp -a "$dst" "$dst.previous" 2>/dev/null || true
  cp "$src" "$dst"
  printf '%-38s %10s B\n' "$2" "$(stat -c%s "$dst")"
}

install_one "$ROOT/out/zImage"                        zImage-mini-upstream
install_one "$ROOT/out/imx6ull-alientek-mini-4.3.dtb" imx6ull-alientek-mini-4.3.dtb
install_one "$ROOT/out/rootfs-mini.uimg"              rootfs-mini.uimg

echo
echo "网页入口：$QEMU/scripts/run-virtual-board.cmd → 配置「Linux / imx6ull_port（LVGL 9.6）」"
echo "命令行验证：bash tools/verify-qemu.sh"
