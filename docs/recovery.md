# imx6ull\_port 产物还原报告

依据 `out/` 里的构建产物，反推出板级适配源码，套到官方发布版本上编译验证，并归档到 Beelink。

## 结论



| 项目         | 结果                                                                                                           |
| ---------- | ------------------------------------------------------------------------------------------------------------ |
| U-Boot     | 官方 v2026.10 + 还原补丁，编出 400,384 字节 `u-boot-dtb.imx`（与原件同尺寸），QEMU 跑到 `=>`                                       |
| 内核         | 官方 7.3.5 + 还原 `.config`/DTS，`dtb` 34,692 字节且 sha256 与原件**完全一致**；`zImage` 10,093,384 字节（原件 10,093,392，差 8 字节） |
| QEMU 启动    | 新编 zImage + dtb + initramfs 引导到 `imx6ull-mini: rootfs ready` 并出现 shell 提示符                                   |
| Beelink 归档 | `/vol1/1000/DATA/Study/IMX6`，373 MB，sha256/gzip 校验通过                                                         |

## 还原方法与依据



1. **内核配置**：`zImage` 内嵌 IKCFG 段（`IKCFG_ST`…`IKCFG_ED`），解出原构建真正使用的 `.config`（7593 行有效配置）。

2. **内核设备树**：`imx6ull-alientek-mini-4.3.dtb` 用 `dtc` 反编译成 1567 行 dts，model 为 `Alientek i.MX6ULL Mini (ATK-4.3RGBLCD 800x480)`。

3. **U-Boot 设备树**：`u-boot.imx` 偏移 365904 处取内嵌 FDT（total 31744），反编译 1408 行 dts，model `Alientek i.MX6ULL Mini`，compatible `fsl,imx6ull-alientek-mini`。

4. **U-Boot 代码差异**：把 `src/u-boot-2026.10` 残缺树与官方 clone 逐文件比对，只有 `arch/arm/mach-imx/mx6/soc.c` 被改（QEMU 兼容：ANA bandgap 等待改有界重试；屏蔽 `is_mx6ul()` 的 SNVS GPBIT/PMIC\_STBY\_REQ pad 配置），另新增 defconfig 与 dts。

## 编译中踩到的两个坑



* U-Boot 的 dts 必须放在 `arch/arm/dts/imx6ull-alientek-mini.dts`。该工程没启用 OF\_UPSTREAM，只放 `dts/upstream/src/arm/nxp/imx/` 会报 `No rule to make target`。

* 内核 DTS 注册行不能插在 `imx6ull-14x14-evk.dtb \` 这种续行后面自成一行，否则 `arch/arm/boot/dts/nxp/imx/Makefile` 报 `recipe commences before first target`。要写成同一列表的续行（`\timx6ull-alientek-mini-4.3.dtb \`）。

## 归档位置



* Beelink：`/vol1/1000/DATA/Study/IMX6/`（用户可直接读写，无需 sudo）


  * `u-boot-2026.10-nxp-mini.tar.gz`（45 MB，源码）

  * `patches/u-boot-2026.10-nxp-mini.bundle`（55 MB，含 v2026.10 全历史 + 还原提交，可独立 clone）

  * `patches/0001-mx6ull-alientek-mini-port.patch`（2962 行，全部改动）

  * `linux-7.3.5-nxp-mini.tar.gz`（263 MB，官方源码 + `.config` + DTS + Makefile 注册）

  * `out/`（重编的 zImage /dtb/u-boot-dtb.imx）

  * `recovered/`（反编译的 dts、抽出的内核 config）

  * `README.md`（编译步骤与校验结果）

* 本地同步留档：`01_Projects/imx6ull_port/{patches,recovered,out/rebuilt}`。

## 哈希



```
# 与原件一致
imx6ull-alientek-mini-4.3.dtb  1a41ee5697a87bddcbfd90f806ce98af43159c21411da362521abeb6bdf95f9a

# 重编产物
u-boot-dtb.imx  98601152aafd5684e648207a84b40466e612dc26b1cfabb15145a482c8444736
zImage          4fd1561cb9cfd4066543c8340472bb24964ad73bf13fc4576a24d3ead5afaa58

# 原件
u-boot.imx      d48b70a675b08eff651c6f03bf8f6cabb5232a65dcc88288771d8d55df44aa0d
zImage          d169d72e40b6bad9ca7e34b06fc9a960706f6b61d176c0d5fe7d53b8b8208e7a
```