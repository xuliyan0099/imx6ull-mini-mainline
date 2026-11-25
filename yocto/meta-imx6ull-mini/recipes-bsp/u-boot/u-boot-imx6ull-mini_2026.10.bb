SUMMARY = "U-Boot bootloader for ATK i.MX6ULL Mini"
HOMEPAGE = "https://www.denx.de/wiki/U-Boot"
SECTION = "bootloaders"
LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit externalsrc deploy

PV = "2026.10"
EXTERNALSRC = "${IM6_SRC}/u-boot"
EXTERNALSRC_BUILD = "${WORKDIR}/build"

PROVIDES = "u-boot virtual/bootloader"
UBOOT_MACHINE ??= "mx6ull_alientek_mini_defconfig"

DEFCONFIG_SRC = "${IM6_REPO}/components/u-boot/board/mx6ull_alientek_mini_defconfig"

DEPENDS += "swig-native dtc-native bc-native bison-native flex-native"
# 任务里 PATH 只剩 hosttools（有 gcc 没有 cc），显式指定宿主编译器
EXTRA_OEMAKE = 'CROSS_COMPILE=${TARGET_PREFIX} CC="${TARGET_PREFIX}gcc ${TOOLCHAIN_OPTIONS}" HOSTCC="gcc" V=1'

do_configure() {
    install -d ${S}/configs
    install -m 0644 ${DEFCONFIG_SRC} ${S}/configs/${UBOOT_MACHINE}
    # 源码树里可能有手写构建留下的中间物；O= 的 mrproper 只清 build 目录，
    # 必须先在源码树里原地 mrproper，否则 out-of-tree 构建报 "source tree is not clean"
    oe_runmake -C ${S} mrproper || true
    oe_runmake -C ${S} O=${B} mrproper || true
    oe_runmake -C ${S} O=${B} ${UBOOT_MACHINE}
}

do_compile() {
    oe_runmake -C ${S} O=${B} CROSS_COMPILE=${TARGET_PREFIX} ${PARALLEL_MAKE} all
}

do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 ${B}/u-boot-dtb.imx ${DEPLOYDIR}/u-boot-dtb-${MACHINE}-${PV}-${PR}.imx
    ln -sf u-boot-dtb-${MACHINE}-${PV}-${PR}.imx ${DEPLOYDIR}/u-boot-dtb.imx
}

addtask deploy after do_compile before do_build
