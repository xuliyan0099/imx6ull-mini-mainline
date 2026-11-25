SUMMARY = "BusyBox + 最小 rootfs 骨架（i.MX6ULL Mini）"
SECTION = "base"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit externalsrc

PV = "1.38.0"
EXTERNALSRC = "${IM6_SRC}/busybox"
EXTERNALSRC_BUILD = "${WORKDIR}/build"
DEPENDS += "virtual/libc"

BUSYBOX_CONFIG = "${IM6_REPO}/components/busybox-rootfs/busybox/busybox.config"
ROOTFS_SKEL = "${IM6_REPO}/components/busybox-rootfs/rootfs"

# BusyBox 的 out-of-tree 构建会去源码树找 scripts/kconfig 生成的 zconf.tab.c，
# mrproper 之后必然报 "No such file or directory"，所以这里就按源码树原地构建。
do_configure() {
    oe_runmake -C ${S} mrproper || true
    install -m 0644 ${BUSYBOX_CONFIG} ${S}/.config
    # 原配置是静态链接的；Yocto 的 rootfs 自带 glibc，改动态链接省体积、省 libc.a 依赖
    sed -i -e 's/^CONFIG_STATIC=y/# CONFIG_STATIC is not set/' \
           -e 's/^CONFIG_STATIC_LIBGCC=y/# CONFIG_STATIC_LIBGCC is not set/' ${S}/.config
    yes '' | oe_runmake -C ${S} ARCH=arm CROSS_COMPILE=${TARGET_PREFIX} oldconfig
}

do_compile() {
    # CC 必须用 Yocto 的包装器（带 --sysroot），否则 gcc 找不到目标 libc 头文件
    # SKIP_STRIP=y：安装时不 strip，交给 do_package 用 Yocto 的 strip 处理（否则 already-stripped QA 报错）
    oe_runmake -C ${S} ARCH=arm CROSS_COMPILE=${TARGET_PREFIX} CC="${CC}" HOSTCC=gcc SKIP_STRIP=y ${PARALLEL_MAKE}
}

do_install() {
    oe_runmake -C ${S} ARCH=arm CROSS_COMPILE=${TARGET_PREFIX} CC="${CC}" HOSTCC=gcc SKIP_STRIP=y CONFIG_PREFIX=${D} install
    install -d ${D}/dev ${D}/proc ${D}/sys ${D}/tmp ${D}/run ${D}/var/log ${D}/root \
               ${D}/etc/init.d ${D}/usr/bin
    chmod 1777 ${D}/tmp
    # /etc/fstab、/etc/profile 由 base-files 提供，这里只放 rootfs 骨架里独有的三个文件
    install -m 0755 ${ROOTFS_SKEL}/init ${D}/init
    install -m 0755 ${ROOTFS_SKEL}/etc/init.d/rcS ${D}/etc/init.d/rcS
    install -m 0644 ${ROOTFS_SKEL}/etc/inittab ${D}/etc/inittab
}

FILES:${PN} = "/bin /sbin /usr /etc /init /linuxrc /dev /proc /sys /tmp /run /var /root"

# BusyBox 的 install 目标自己会调用 strip（部分版本不认 SKIP_STRIP），
# 产物已 stripped 属正常，跳过这条 QA
INSANE_SKIP:${PN} += "already-stripped empty-dirs"
