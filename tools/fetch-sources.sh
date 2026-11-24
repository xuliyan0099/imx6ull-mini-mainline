#!/usr/bin/env bash
# 依次拉取四个组件仓库的上游源码（版本均钉死），源码统一放在 <repo>/src 里复用。
#   bash tools/fetch-sources.sh
# 环境变量（透传给各组件脚本）：
#   IM6_SRC=<dir>   源码根目录，默认 <repo>/src
#   IM6_UB_URL / IM6_LX_URL / IM6_BB_URL / IM6_LV_URL   镜像地址
#   IM6_LX_FILE / IM6_BB_FILE   本地 tar 包，离线构建用
#   IM6_FORCE=1     强制重拉
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
C=${IM6_COMPONENTS:-$ROOT/components}
export IM6_SRC=${IM6_SRC:-$ROOT/src}
mkdir -p "$IM6_SRC"

for comp in u-boot linux busybox-rootfs lvgl; do
  echo "######## $comp ########"
  bash "$C/$comp/tools/fetch.sh"
done

echo
echo "源码就绪：$IM6_SRC"
ls -d "$IM6_SRC"/*/
