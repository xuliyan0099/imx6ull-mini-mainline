SUMMARY = "Linux 7.3.6 kernel for ATK i.MX6ULL Mini"
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit externalsrc deploy

PV = "7.3.6"
EXTERNALSRC = "${IM6_SRC}/linux"
EXTERNALSRC_BUILD = "${WORKDIR}/build"

PROVIDES = "virtual/kernel"
DEPENDS += "bison-native flex-native bc-native"
KCONFIG_SRC = "${IM6_REPO}/components/linux/board/kernel.config"
KERNEL_DTB = "imx6ull-alientek-mini-4.3.dtb"

do_configure() {
    # 手写构建曾在源码树里留过中间物，先 mrproper 保证 O= 构建可复现
    oe_runmake -C ${S} ARCH=arm mrproper || true
    install -m 0644 ${KCONFIG_SRC} ${B}/.config
    oe_runmake -C ${S} O=${B} ARCH=arm CROSS_COMPILE=${TARGET_PREFIX} olddefconfig
}

do_compile() {
    oe_runmake -C ${S} O=${B} ARCH=arm CROSS_COMPILE=${TARGET_PREFIX} ${PARALLEL_MAKE} zImage dtbs
}

do_install() {
    install -d ${D}/boot
    install -m 0644 ${B}/arch/arm/boot/zImage ${D}/boot/zImage
    install -m 0644 ${B}/arch/arm/boot/dts/nxp/imx/${KERNEL_DTB} ${D}/boot/${KERNEL_DTB}
}

do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 ${B}/arch/arm/boot/zImage ${DEPLOYDIR}/zImage
    install -m 0644 ${B}/arch/arm/boot/dts/nxp/imx/${KERNEL_DTB} ${DEPLOYDIR}/${KERNEL_DTB}
}

addtask deploy after do_compile before do_build

FILES:${PN} = "/boot"

# 本板内核把 SCSI_DEBUG/SD_MOD/LOOP/ALGIF_HASH 都设成 n（不产出模块包），
# 但 util-linux-ptest 的 RRECOMMENDS 引用了这些包名，依赖图会直接报错。
# 这里给四个空占位包，让 bitbake 的依赖解析通过；真启用模块时可删掉对应行。
PACKAGES += "kernel-module-scsi-debug kernel-module-sd-mod kernel-module-loop kernel-module-algif-hash"
ALLOW_EMPTY:kernel-module-scsi-debug = "1"
ALLOW_EMPTY:kernel-module-sd-mod = "1"
ALLOW_EMPTY:kernel-module-loop = "1"
ALLOW_EMPTY:kernel-module-algif-hash = "1"
