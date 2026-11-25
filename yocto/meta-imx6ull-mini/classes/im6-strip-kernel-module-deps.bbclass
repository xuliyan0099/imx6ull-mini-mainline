# 去掉所有包上的 kernel-module-* 运行时依赖。
# 原因：本板内核把 netfilter/scsi 等编译成 built-in（不产出 kernel-module-* 包），
# 而 poky 的 iptables、iproute2、util-linux 等把这些模块包写进 RRECOMMENDS/RDEPENDS，
# 缺失时 bitbake 的依赖图会直接判定 "no buildable providers"（Nothing RPROVIDES ...）。
# rootfs 里本来也不安装这些包，因此统一摘除；内核真启用这些模块时删掉 inherit 即可。
#
# 注意：
# 1. class 里的 `python () {}` 匿名函数只对 base config 执行一次，必须用 RecipeParsed 事件；
# 2. 只能改 RDEPENDS/RRECOMMENDS/RPROVIDES 这三类变量，绝不能遍历所有变量——
#    否则会把 python 函数源码（insane.bbclass 里含 "kernel-module" 字样）的换行压平，
#    直接导致 IndentationError。

python im6_strip_kernel_module_deps() {
    d = e.data
    for var in list(d.keys()):
        if var.split(":")[0] not in ("RDEPENDS", "RRECOMMENDS", "RPROVIDES", "RSUGGESTS"):
            continue
        val = d.getVar(var, False)
        if not isinstance(val, str) or "kernel-module-" not in val or "\n" in val:
            continue
        newval = " ".join(t for t in val.split() if not t.startswith("kernel-module-"))
        if newval != val:
            d.setVar(var, newval)
}

addhandler im6_strip_kernel_module_deps
im6_strip_kernel_module_deps[eventmask] = "bb.event.RecipeParsed"
