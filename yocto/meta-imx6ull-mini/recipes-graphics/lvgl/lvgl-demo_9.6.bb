SUMMARY = "LVGL 9.6 仪表盘（imx6ull-mini 静态/动态演示程序）"
SECTION = "graphics"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit externalsrc

PV = "9.6"
EXTERNALSRC = "${IM6_REPO}/components/lvgl"
EXTERNALSRC_BUILD = "${WORKDIR}/build"

do_compile() {
    install -d ${B}
    cp -a ${S}/. ${B}/
    oe_runmake -C ${B} clean
    # LDFLAGS 必须带上 Yocto 的默认值，否则缺 --hash-style=gnu 会触发 ldflags QA 报错
    oe_runmake -C ${B} CC="${CC}" STRIP="${STRIP}" \
        LVGL_DIR="${IM6_SRC}/lvgl" \
        LDFLAGS="${LDFLAGS} -Wl,--gc-sections -lm -lpthread"
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/lvgl_demo ${D}${bindir}/lvgl_demo
}

FILES:${PN} = "${bindir}/lvgl_demo"
