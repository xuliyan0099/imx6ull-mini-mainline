#!/usr/bin/env bash
# 在 im6-yocto 容器里执行：初始化 build 目录并 bitbake imx6ull-mini-image
#   bash tools/yocto-build.sh            # 正常构建
#   bash tools/yocto-build.sh -c devtool # 只解析配置（bitbake -p）
set -euo pipefail

YOCTO=${YOCTO:-/work/yocto}
POKY=$YOCTO/poky
REPO=${IM6_REPO:-/work/repo}
BUILD=${BUILD:-$YOCTO/build-imx6ull}
IMAGE=${IMAGE:-imx6ull-mini-image}

mkdir -p "$BUILD/conf" "$YOCTO/downloads" "$YOCTO/sstate-cache"

cat > "$BUILD/conf/bblayers.conf" <<EOF
POKY_BBLAYERS_CONF_VERSION = "2"

BBPATH = "\${TOPDIR}"
BBFILES ?= ""

BBLAYERS ?= " \\
  $POKY/meta \\
  $POKY/meta-poky \\
  $REPO/yocto/meta-imx6ull-mini \\
"
EOF

cp "$REPO/yocto/local.conf" "$BUILD/conf/local.conf"

# shellcheck disable=SC1091
set +u
source "$POKY/oe-init-build-env" "$BUILD" >/dev/null
set -u

if [ "${1:-}" = "-c" ]; then
  shift
  exec bitbake "$@"
fi

exec bitbake "$IMAGE"
