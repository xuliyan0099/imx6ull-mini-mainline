# 用本层的精简 base-passwd 顶掉 poky 的实现（BBFILE_PRIORITY 更高，同名 recipe 本层优先）。
# 原因：poky 的 base-passwd 在 do_package 阶段要在 sysroot 里执行它自己生成的
# postinst-base-passwd 脚本，而本构建机（Beelink + pseudo）上这个脚本落盘后丢了可执行位，
# 直接导致打包任务 "Permission denied" 失败（试过 chmod、cleanstate 均无效）。
# 板子上只需要一份能用的 /etc/passwd、/etc/group，不需要 useradd 那套。

SUMMARY = "最小 passwd/group（替代 poky base-passwd）"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

do_install() {
    install -d ${D}${sysconfdir}
    cat > ${D}${sysconfdir}/passwd << 'EOF'
root:x:0:0:root:/root:/bin/sh
daemon:x:1:1:daemon:/usr/sbin:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/bin/sh
EOF
    cat > ${D}${sysconfdir}/group << 'EOF'
root:x:0:
daemon:x:1:
nobody:x:65534:
EOF
    chmod 0644 ${D}${sysconfdir}/passwd ${D}${sysconfdir}/group
}

FILES:${PN} = "${sysconfdir}/passwd ${sysconfdir}/group"

