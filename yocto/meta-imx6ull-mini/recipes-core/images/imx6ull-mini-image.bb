SUMMARY = "i.MX6ULL Mini SD 卡镜像（U-Boot + Linux + BusyBox + LVGL）"
LICENSE = "MIT"

# 用基础 image 类而不是 core-image：core-image 会拉进 meta-environment-extsdk，
# 后者经 ncurses→bash→coreutils→util-linux→iproute2→iptables 引出一串
# kernel-module-* 依赖（本板这些子系统是 built-in，根本没有模块包），
# 我们只需要一个最小可启动 rootfs，不需要 eSDK 那套东西。
inherit image

IMAGE_INSTALL = "base-files base-passwd busybox-imx6ull-mini lvgl-demo linux-imx6ull-mini"
IMAGE_FSTYPES = "tar.bz2 ext4"
IMAGE_LINGUAS = ""
IMAGE_ROOTFS_SIZE ?= "61440"
IMAGE_OVERHEAD_FACTOR = "1.0"

imx6ull_fstab_fix() {
    # base-files 的 fstab 只有 proc/devpts，板子上需要 sysfs/devtmpfs/tmpfs
    grep -q '/sys ' ${IMAGE_ROOTFS}/etc/fstab 2>/dev/null || {
        echo "" >> ${IMAGE_ROOTFS}/etc/fstab
        echo "sysfs                /sys                 sysfs      defaults              0  0" >> ${IMAGE_ROOTFS}/etc/fstab
        echo "devtmpfs             /dev                 devtmpfs   mode=0755,nosuid    0  0" >> ${IMAGE_ROOTFS}/etc/fstab
        echo "tmpfs                /tmp                 tmpfs      mode=1777,nodev,nosuid 0  0" >> ${IMAGE_ROOTFS}/etc/fstab
    }
    echo "imx6ull-mini" > ${IMAGE_ROOTFS}/etc/hostname

    # rootfs 里没有 man-db，但某个 -doc 包的 postinst 会走 update_mandb 拦截脚本，
    # 它 sed /etc/man_db.conf 时文件不存在就直接让 do_rootfs 失败（exit 2）；
    # 这里先放一个空文件让它 sed 得动（板子上本来也不装 man）。
    touch ${IMAGE_ROOTFS}${sysconfdir}/man_db.conf

    # 镜像里没有 base-passwd（它的 pkg_postinst 在 sysroot 中丢了可执行位，打包直接失败），
    # 这里补一份最小账号库，够 login/ps/id 这些用
    if [ ! -s ${IMAGE_ROOTFS}/etc/passwd ]; then
        cat > ${IMAGE_ROOTFS}/etc/passwd << 'EOF'
root:x:0:0:root:/root:/bin/sh
daemon:x:1:1:daemon:/usr/sbin:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/bin/sh
EOF
    fi
    if [ ! -s ${IMAGE_ROOTFS}/etc/group ]; then
        cat > ${IMAGE_ROOTFS}/etc/group << 'EOF'
root:x:0:
daemon:x:1:
nobody:x:65534:
EOF
    fi
}

ROOTFS_POSTPROCESS_COMMAND += "imx6ull_fstab_fix; "
