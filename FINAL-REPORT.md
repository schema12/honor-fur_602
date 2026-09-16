# HONOR FUR-602/603 → ImmortalWrt 24.10 设备移植实施报告

> 目标：把 HONOR FUR-602/603（荣耀 XU50/XT50/XC50，MT7981B）移植为 **ImmortalWrt 24.10
> （`openwrt-24.10` 分支，kernel 6.6）** 中一个结构正确、可重复 GitHub Actions 编译、
> 无线优先稳定、支持 monitor mode、内核能力完整而用户态精简的**正式设备支持**。
>
> 本报告全部结论均来自**源码级证据**，每条结论附来源文件与行号。凡证据不足者均显式标注
> "需实机确认"，不做臆测填充。

---

## 0. 证据基线（Evidence Base）

| 来源 | 版本 | 用途 |
|------|------|------|
| `immortalwrt/immortalwrt` | `openwrt-24.10` @ `aa5e28abcccf388ff1b717d5d30b1657c7b2d835` | **目标源码基线**（kernel 6.6.xx） |
| `hanwckf/bl-mt798x` | tag **`20241115`** @ `15ad0ed949043bcbbcb5ef501ba156b1f25e676f` | **设备当前实际 U-Boot 依据** |
| `hanwckf/immortalwrt-mt798x` | `openwrt-21.02` | FUR-602 量产版参考实现（独立第三方交叉验证） |
| `schema12/honor-fur_602` | — | 用户提供的原始移植仓库（LEDE 方案，已在本方案中全面升级） |

**关键说明**：`bl-mt798x` 的 `20241115` tag 中，`build.sh` 默认
`UBOOT_DIR=uboot-mtk-20230718-09eda825`（build.sh:5）、`ATF_DIR=atf-20231013-0ea67d76a`（build.sh:7）。
即 20241115 发布版**就是用 `uboot-mtk-20230718-09eda825` 这棵源码树构建的**，因此
`uboot-mtk-20230718-09eda825/arch/arm/dts/mt7981-honor_fur-602.dts` 与
`uboot-mtk-20230718-09eda825/configs/mt7981_honor_fur-602_defconfig` **就是**设备当前 U-Boot 的真实定义。
（已确认 `uboot-mtk-20250711` 中已不含 FUR-602，故不采用。）

---

## 1. 硬件事实（全部源码确认，无猜测）

| 项目 | 结论 | 证据 |
|------|------|------|
| SoC | MediaTek **MT7981B** (Filogic 820)，双核 Cortex-A53 | U-Boot DTS `compatible`、24.10 `mt7981.dtsi` |
| 内存 | **256 MiB** DDR3（`reg = <0 0x40000000 0 0x10000000>`） | `mt7981b-honor-fur-602.dts` |
| 闪存 | **128 MiB SPI-NAND，启用 NMBM** | U-Boot `CONFIG_ENABLE_NAND_NMBM=y`、`CONFIG_CMD_NMBM=y` |
| 无线 | 2.4G 2×2（MT7981 内置）+ 5G 2×2（MT7976CN）= **AX3000** | `&wifi` + mt76 驱动模型 |
| 网口 | **4×1G**：1 WAN + 3 LAN，全部挂 **MT7531** 交换机，单 `gmac0` 上联 | U-Boot DTS `mediatek,switch = "mt7531"` |
| gmac0 上行 | **`phy-mode = "2500base-x"`，fixed-link 2500Mbps** | U-Boot DTS `&eth`；**已确认，非 SGMII** |
| 交换机 reset | **GPIO 39，`GPIO_ACTIVE_HIGH`** | U-Boot DTS `reset-gpios = <&gpio 39 GPIO_ACTIVE_HIGH>` |
| 交换机中断 | **GPIO 38，`IRQ_TYPE_LEVEL_HIGH`** | U-Boot DTS `interrupts` |
| Reset 键 | **GPIO1**，低有效 | U-Boot DTS `gpio-keys` |
| Mesh 键 | **GPIO0**，低有效（`BTN_9` / `EV_SW`） | U-Boot DTS `gpio-keys` + 21.02 参考 |
| LED 绿（状态） | **GPIO8** | U-Boot DTS `green:system` |
| LED 红（状态） | **GPIO13** | U-Boot DTS `red:system` |
| MAC（WAN） | `factory@0x24`（6 字节） | U-Boot DTS + 21.02 参考 |
| MAC（LAN/gmac0） | `factory@0x2a`（6 字节） | 同上 |
| WiFi EEPROM | `factory@0x0` | U-Boot DTS + 21.02 参考 |
| USB / PCIe | **无引出** | U-Boot DTS 中无对应节点 |
| Watchdog | U-Boot 侧 `disabled`；Linux 侧启用 | U-Boot DTS `watchdog { status = "disabled"; }` |
| HNAT | **不支持**（24.10 filogic 无 hnat 补丁） | 24.10 源码无 `kmod-mtkhnat` |

---

## 2. Flash / 分区布局（★ 高风险项，必须实机确认）

### 2.1 U-Boot 内置**两套**布局

来自 `uboot-mtk-20230718-09eda825/arch/arm/dts/mt7981-honor_fur-602.dts` 的
`/mtd-layout` 节点（`mtd_layout.c` 的 `get_mtd_layout_label()` 读取）：

**`layout@0` — label `"default"`（U-Boot defeconfig 默认）**

```
nmbm0: 1024k(bl2), 512k(u-boot-env), 1920k(factory), 128k(Trace),
       2048k(fip), 65536k(ubi), 128k(Tracebak), 51200k(foxfs)
```

即 **ubi = 64 MiB**，另有 `Tracebak`(128K) 与 `foxfs`(51200K) 两个原厂遗留分区。

**`layout@1` — label `"expand(114m)"`（我们的镜像所针对的布局）**

```
nmbm0: 1024k(bl2), 512k(u-boot-env), 1920k(factory), 128k(Trace),
       2048k(fip), 116736k(ubi)
```

即 **ubi = 116736 KiB = 114 MiB**，**吞掉了原厂的 `Tracebak` 与 `foxfs`**。

### 2.2 布局选择机制（★ 关键）

`board/mediatek/common/mtd_layout.c`：

```c
const char *get_mtd_layout_label(void) {
    return env_get("mtd_layout_label");   /* 缺省值 "default" */
}
```

`board_mtdparts_default()` 依据该 label 从 `/mtd-layout` 匹配 `layout@N`，
并用其中的 `mtdids` / `mtdparts` / `boot_part` / `factory_part` 执行 `env_set()`
（包括 `bootargs`、`ubi_boot_part`）。

**⇒ 结论：**

- 若 env 中**没有** `mtd_layout_label`，U-Boot 使用 `"default"`（64 MiB ubi）；
- 我们的 `IMAGE_SIZE := 116736k` **只适配** `expand(114m)`；
- 因此设备上**必须**已执行 `setenv mtd_layout_label "expand(114m)"; saveenv`
  （或刷入 `mt7981_honor_fur-602_multi_layout_defconfig` 构建的
  **multi-layout 版 U-Boot**，开机时可交互选择布局）。

`configs/mt7981_honor_fur-602_defconfig` 的
`CONFIG_MTDPARTS_DEFAULT="...65536k(ubi),128k(Tracebak),51200k(foxfs)"`
即为 `default` 布局；`mt7981_honor_fur-602_multi_layout_defconfig` 额外启用
`CONFIG_MEDIATEK_MULTI_MTD_LAYOUT=y`。

> ⚠️ **若 env 未切换布局，刷入本固件会导致 UBI 分区溢出/无法启动。**
> 这是本方案**唯一的硬性前置条件**，详见 §7 风险。

### 2.3 Linux 侧 DTS 分区（与 expand(114m) 一一对应）

```
partition@0        bl2        0x100000  (1 MiB)   ro
partition@100000   u-boot-env 0x80000   (512 KiB)
partition@180000   factory    0x1e0000  (1920 KiB) ro
partition@360000   trace      0x20000   (128 KiB)  ro
partition@380000   fip        0x200000  (2 MiB)    ro
partition@580000   ubi        0x7200000 (114 MiB)
```

`0x580000 + 0x7200000 = 0x7780000 = 125,304,832 B ≈ 119.5 MiB` < 128 MiB ✔（含 NMBM 坏块预留）

---

## 3. U-Boot 启动逻辑（★ factory.bin 为何能被识别的根本原因）

### 3.1 卷名常量（`mtd_helper.c:30-35`）

```c
#define PART_UBI_NAME          "ubi"
#define PART_FIRMWARE_NAME     "firmware"
#define PART_FIT_NAME          "fit"
#define PART_KERNEL_NAME       "kernel"
#define PART_ROOTFS_NAME       "rootfs"
#define PART_ROOTFS_DATA_NAME  "rootfs_data"
```

### 3.2 `mtd_boot_image()` 启动路径（`mtd_helper.c:1175`）

```
mtd_boot_image()
  ├─ 查找名为 "kernel" 的 MTD 分区
  │    ├─ 存在 且 与 ubi 同 parent → boot_from_mtd(mtd_kernel, 0)   ← 传统 NAND 布局
  │    └─ 不存在                    → boot_from_ubi(mtd)            ← ★ 我们走这条
  └─ …
```

**我们的分区表里没有名为 `kernel` 的 MTD 分区**（只有 `ubi`）⇒ 必然进入 `boot_from_ubi()`。

### 3.3 `boot_from_ubi()`（`mtd_helper.c:1038`）

```c
mount_ubi(...)
  → read_ubi_volume("kernel")          /* PART_KERNEL_NAME */
       ├─ 成功 → boot_from_mem()
       └─ ENODEV → read_ubi_volume("fit")   /* 回退到 FIT 路线 */
                      → boot_from_mem()
```

### 3.4 与 ImmortalWrt 24.10 image pipeline 的对应关系（★ 核心论证）

`KERNEL_IN_UBI := 1` 使 `include/image.mk` 走 `append-ubi` 路径，
`scripts/ubinize-image.sh` 生成 **UBI 卷 `kernel` + `rootfs` + `rootfs_data`**。

由于 `IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)` 产出的是
**裸 UBI 镜像**（含 UBI EC header），且卷名恰为 `kernel` / `rootfs` / `rootfs_data`：

| U-Boot 期望 | ImmortalWrt 24.10 产出 | 匹配 |
|-------------|------------------------|------|
| MTD 分区 `ubi` | DTS `partition@580000 ubi` | ✅ |
| UBI 卷 `kernel` | `KERNEL_IN_UBI=1` → ubinize 卷 `kernel` | ✅ |
| UBI 卷 `rootfs` | 同上 → 卷 `rootfs` | ✅ |
| UBI 卷 `rootfs_data` | 同上 → 卷 `rootfs_data` | ✅ |
| 无 `kernel` MTD 分区 | Linux DTS 无 `kernel` 分区 | ✅ |

**独立第三方确证**：`hanwckf/immortalwrt-mt798x` 的
`target/linux/mediatek/image/mt7981.mk:661` `define Device/honor_fur-602`
与本方案定义**逐字同构**（`IMAGE_SIZE := 116736k`、`KERNEL_IN_UBI := 1`、
`IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)`、
`IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata`、
`UBINIZE_OPTS := -E 5`、`BLOCKSIZE := 128k`、`PAGESIZE := 2048`）。

> **⇒ 为什么 factory.bin 能被 20241115 U-Boot 正确识别和启动：**
> 因为分区表中不存在 `kernel` MTD 分区，U-Boot 的 `mtd_boot_image()` 必然走
> `boot_from_ubi()` 分支，去 UBI 分区里读取名为 `kernel` 的 UBI 卷。
> 而 `KERNEL_IN_UBI=1` + `append-ubi` 产出的裸 UBI 镜像，其卷名正是 `kernel`/`rootfs`/`rootfs_data`，
> 且 `IMAGE_SIZE=116736k` 与 `expand(114m)` 布局的 ubi 分区大小完全一致。
> 卷名、分区名、偏移、大小四者全部对齐，因此 U-Boot 可以直接挂载并启动。

### 3.5 `write_ubi2_tar_image()` — sysupgrade 能安全升级的原因（`mtd_helper.c:765`）

```
write_ubi2_tar_image()
  → parse_tar_image()
      → update_ubi_volume("kernel")        /* 原地更新 kernel 卷 */
      → update_ubi_volume("rootfs")        /* 原地更新 rootfs 卷 */
      → remove_ubi_volume("rootfs_data")   /* 先删 */
      → create_ubi_volume("rootfs_data")   /* 再重建（清空配置） */
```

非 DUAL_BOOT 时 `kernel_part = PART_KERNEL_NAME`、`rootfs_part = PART_ROOTFS_NAME`。
已确认 FUR-602 的 U-Boot defconfig **未启用 `CONFIG_MTK_DUAL_BOOT`**
（grep 无该符号）⇒ 走普通（非 A/B slot）路径。

**⇒ 为什么 sysupgrade.bin 可以安全升级：**
`sysupgrade.bin` 是 **tar 包**（`sysupgrade-tar | append-metadata`），内部结构由
`scripts/sysupgrade-tar.sh` 生成：

```
sysupgrade-honor_fur_602/
  ├── CONTROL
  ├── kernel
  └── root
```

`DEVICE_NAME` 由 `BOARD_NAME`（默认为空）回退得到，即 `honor_fur-602` 中的 `,`→`_`
= **`honor_fur_602`**；运行时 `board_name` 来自 DTS `compatible = "honor,fur-602"`
（同样 `,`→`_`）⇒ **两者一致**。

刷机时链路上有两级校验：

1. `package/base-files/files/lib/upgrade/nand.sh:476` `nand_do_platform_check()`
   —— 用 `sysupgrade-<board>/CONTROL` 探测 tar 是否为本设备包；
2. 同文件 `:377` `nand_verify_tar_file()` —— 执行 `tar xOf - >/dev/null` 验证 tar 完整性。

> 注：`target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh` 中
> **没有** literal `ustar` 判断，走默认 `*)` 分支调用 `nand_do_upgrade "$1"`，
> 真正的校验发生在 `nand.sh`（见上）。这点与一些旧资料的说法不同，已按源码纠正。

---

## 4. ImmortalWrt 24.10 结构适配（与旧 LEDE 方案的差异）

| 项目 | 旧 LEDE / 21.02 写法 | **本方案（24.10 原生）** |
|------|---------------------|--------------------------|
| 交换机 | swconfig / `&switch` 旧式 | **DSA**：`&mdio_bus { switch: switch@1f { compatible = "mediatek,mt7531"; } }` |
| 接口映射 | 需 `02_network` 打补丁 | **不需要**（DSA 自动生成，`02_network` 不出现 `honor,fur-602`） |
| LED | `label = "..."` | `function` + `color`（`LED_FUNCTION_STATUS` / `LED_COLOR_ID_GREEN`） |
| MAC 绑定 | 手写 `mac-address` / `local-mac-address` | `nvmem-cells` + `label-mac-device` |
| NMBM | 独立 `nmbm` 节点 / 外置 patch | `spi_nand@0` 内联 `mediatek,nmbm` / `bmt-max-ratio` / `bmt-max-reserved-blocks` |
| SPI 校准 | 无 | `spi-cal-enable` + `spi-cal-mode = "read-data"` + `spi-cal-data = <'SPINAND'>` |
| 根文件系统 | `rootfs` 直挂 | 见下 |
| **FIT / fitblk** | — | **刻意不用**（NMBM 变体 DTS 会 `delete` `bootargs-append` / `rootdisk` / `volumes`） |
| HNAT | 21.02 有 `&hnat` | **24.10 无**，DTS 中不出现 `&hnat` |

### 4.1 为什么不用 FIT/fitblk 路线

24.10 多数 filogic 设备走 `chosen { bootargs-append = " root=/dev/fit0 rootwait";
rootdisk = <&ubi_rootdisk>; }` + `volname = "fit"` + `ubi` 分区 `compatible = "linux,ubi"`
+ `volumes`。**FUR-602 不适用**，因为：

- U-Boot 的 `boot_from_ubi()` 优先读卷 **`kernel`**，没有 `kernel` 卷才回退 `fit`；
- 24.10 官方 NMBM 变体 `mt7981b-h3c-magic-nx30-pro-nmbm.dts` 正是通过
  `delete` 掉 `bootargs-append` / `rootdisk` / `volumes` 来切换到 TAR 路线；
- 我们采用同一手法，保持与上游 NMBM 变体、与 hanwckf 官方实现三方一致。

---

## 5. 无线（最高优先级）

### 5.1 驱动栈

完全使用 **24.10 原生 mac80211 + mt76**，**不引入任何无线驱动魔改**。

| 软件包 | 来源 | 说明 |
|--------|------|------|
| `kmod-mt7915e` | `package/kernel/mt76/Makefile:234` | 含 `MODPARAMS.mt7915e:=wed_enable=Y`（mediatek_filogic） |
| `kmod-mt7981-firmware` | 同上 `:251` | MT7981 固件 |
| `mt7981-wo-firmware` | `package/firmware/linux-firmware/mediatek.mk` | 无线 offload 固件 |

`DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware`

### 5.2 能力覆盖

- 2.4G AP / STA，5G AP / STA（中继优先）
- WPA / WPA2 / WPA3、WMM、11n / 11ac / 11ax
- 80 MHz 带宽、rate control
- `hostapd` / `wpa_supplicant`（由 `wpad-openssl` 提供，见 `filogic/target.mk`）

### 5.3 针对"5GHz 中继 351Mbps ↔ 6Mbps 跳变"的处理

**策略：不加任何驱动魔改，依赖 24.10 原生 mt76。**

- 不注入 vendor 补丁、不改 `MODPARAMS`、不额外开启 WED 自定义参数；
- `kmod-mt7915e` 在 mediatek_filogic 下自带 `wed_enable=Y`（上游默认值，非我们改动）；
- 跳变问题的正确排查方向是**信道/DFS/扫描 roam 参数**，而非驱动裁剪——
  因此本方案保证驱动与内核能力**完整**，把调优留给运行时配置（见 §9 待实测项）。

### 5.4 EEPROM / calibration

`&wifi { status = "okay"; mediatek,mtd-eeprom = <&factory 0x0>; }`
—— 与 U-Boot DTS 和 21.02 参考实现一致。

---

## 6. 内核能力 vs. 固件精简（★ 核心设计原则）

### 6.1 原则

> **内核能力完整（kmod 集合齐全、ABI 匹配、可随时 opkg 安装），
> 但已安装进镜像的用户态包保持精简。**

### 6.2 源码级机制（为什么必须用 `CONFIG_ALL_KMODS=y`）

这是本方案最容易被忽略、但后果最严重的一点。完整链路如下：

1. **kmod 默认不编译**
   `config/Config-build.in` 中 `config ALL_KMODS` 是 `bool`，**没有 `default y`**
   ⇒ 默认 `n`。

2. **kmod 包的三态语义**
   `include/package-dumpinfo.mk:44` 使 ipkg 包默认 `Type: ipkg`，
   `scripts/metadata.pm:291` 遇 ipkg 置 `$pkg->{tristate}=1`，`:308` 输出 tristate。
   ⇒ kmod 是 **tristate**。

3. **默认值生成**
   `scripts/package-metadata.pl:316`：kmod 包会 `push @def, "ALL_KMODS"`
   ⇒ 生成的 Kconfig 为 `default m if ALL || ALL_NONSHARED || ALL_KMODS`；
   同文件 `:309`：`default y if DEFAULT_<name>`。

4. **可用性门（关键）**
   `include/kernel.mk:245`：

   ```make
   ifneq ($(if $(filter-out %=y %=n %=m,$(KCONFIG)),
                $(filter m y,$(foreach c,...,$($(c)))),.),)
   ```

   仅当 KCONFIG 中**每个**符号为 `m` 或 `y` 时才真正编译打包，
   否则输出 `"not available in the kernel config - generating empty package"`。

5. **谁把符号变成 `m`**
   `include/kernel-defaults.mk:121`：
   `package-metadata.pl kconfig ... > $(LINUX_DIR)/.config.override`
   → `:122`：`kconfig.pl 'm+' '+' .config.target /dev/null .config.override > .config.set`
   → `scripts/package-metadata.pl:53` `gen_kconfig_overrides()`：
   对**已选中**的 `CONFIG_PACKAGE_<kmod>`（`=y` 或 `=m`），把其 KCONFIG 符号置 `m`。
   → `scripts/kconfig.pl` 的 `set_config()` + `config_add(...,$mod_plus)`：
      `mod_plus` 时跳过 `y` 与 `#undef`，**`#undef` 可被覆盖**。

   ⇒ 这正是 `generic/config-6.6` 中 `# CONFIG_NET_SCH_HTB is not set` 这类写法的价值：
   **它是可被 override 的前提**。

6. **结论**

   | 场景 | netfilter/QoS 等 kmod 的 .ko / .ipk | 是否进镜像 |
   |------|-------------------------------------|-----------|
   | 默认（`ALL_KMODS=n`，无包依赖） | **不编译、不发布** | 否 |
   | `CONFIG_ALL_KMODS=y` | **编译并发布 .ipk（=m）** | **否**（除非进了 `DEFAULT_PACKAGES`） |
   | 显式 `CONFIG_PACKAGE_kmod-X=y` | 编译并发布 | **是** |

   ⇒ `CONFIG_ALL_KMODS=y` **同时满足**"kmod 齐全可 opkg"与"镜像不膨胀"两个目标。

### 6.3 反面证据：连参考实现都不足以支持事后装 SQM

`hanwckf/immortalwrt-mt798x` 的 `defconfig/mt7981-ax3000.config`（同一文件里
有 `CONFIG_TARGET_DEVICE_mediatek_mt7981_DEVICE_honor_fur-602=y`）**只**设置了：

```
CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-ifb=y
```

**没有** `kmod-sched` / `kmod-sched-cake` / `kmod-sched-prio` / `kmod-sched-fq-pie` / `kmod-sched-ctinfo`。
⇒ 用那份配置构建的固件，事后 `opkg install sqm-scripts` 会因**缺 CAKE 模块**而无法工作。
本方案通过 `ALL_KMODS=y` 避开此问题。

### 6.4 覆盖的能力清单

| 领域 | 代表 kmod（均存在且会被 `ALL_KMODS=y` 编译发布） |
|------|--------------------------------------------------|
| Netfilter | `kmod-nf-*`、`kmod-nft-*`（`nftables` + `firewall4` 在 DEFAULT_PACKAGES） |
| conntrack | `kmod-nf-conntrack*`、`kmod-nf-nathelper`(-extra) |
| Bridge / VLAN | `kmod-bridge`、`kmod-vlan-8021q`、`kmod-br-netfilter` |
| PPPoE | `ppp` + `ppp-mod-pppoe`（DEFAULT_PACKAGES.router） |
| Routing | `kmod-ip-*`、`kmod-nf-*`；policy routing 由 `iproute2` 用户态承载 |
| **SQM/QoS** | `kmod-sched-core`(netsupport.mk:716)、`kmod-sched`(:1032)、`kmod-sched-cake`(:828)、`kmod-sched-prio`(:975)、`kmod-sched-fq-pie`(:898)、`kmod-sched-ctinfo`(:855)、`kmod-sched-act-vlan`(:797)、`kmod-ifb`(netdevices.mk:1411)、`kmod-sched-act-mirred`、`kmod-cls-*` |
| 无线 | `kmod-mac80211`、`kmod-cfg80211`、`kmod-mt7915e`（作为 DEVICE_PACKAGES 进镜像） |
| **monitor mode** | 由 `mac80211`/`mt76` 提供，**驱动与内核已具备能力**；`iw`/`nl80211` 用户态按需安装 |
| USB | `kmod-usb-core`、`kmod-usb2/3`、`kmod-usb-storage`、`kmod-usb-net` 等（**kmod 提供**；硬件无 USB 引出，仅供未来/外设扩展） |
| 文件系统 | `kmod-fs-ext4`、`kmod-fs-f2fs`、`kmod-fs-vfat`、`kmod-nls-*` |
| overlay/rootfs | `squashfs`（内核内建）、`kmod-fs-overlay`、`proot`/`uloop` 无关（用户态） |

> **重要**：这些**全部以 kmod 形式提供**，不 `=y` 塞进内核。
> 依据：`generic/config-6.6` 中相关符号均为 `# ... is not set`；
> `filogic/config-6.6`（507 行）中**根本不存在**任何
> `NET_SCH_*` / `NET_CLS_*` / `NET_ACT_*` / `IFB` / `MAC80211` / `CFG80211` 符号
> —— 它们全由 `package/kernel/linux/modules/*.mk` 的 `KernelPackage` 机制按需开启。

### 6.5 随镜像安装的包（保持精简）

仅两类：

1. `include/target.mk` 的 `DEFAULT_PACKAGES` + `DEFAULT_PACKAGES.router`
   （`DEVICE_TYPE?=router`）：`dnsmasq-full`、`firewall4`、`nftables`、`kmod-nft-offload`、
   `odhcp6c`、`odhcpd-ipv6only`、`ppp`、`ppp-mod-pppoe`；
2. `filogic/target.mk` 追加：
   `fitblk`、`kmod-phy-aquantia`、`kmod-crypto-hw-safexcel`、`wpad-openssl`、
   `uboot-envtools`、`bridger`；
3. ImmortalWrt `DEFAULT_PACKAGES.tweak`：`luci-light`、`default-settings-chn`、
   `kmod-nf-nathelper`(-extra)；
4. 本设备 `DEVICE_PACKAGES`：`kmod-mt7915e`、`kmod-mt7981-firmware`、`mt7981-wo-firmware`。

**未预装**：AdGuard、MosDNS、Docker、Samba、各类下载工具、各类代理插件。

---

## 7. Device / Image 定义

`target/linux/mediatek/image/filogic.mk` 追加：

```make
define Device/honor_fur-602
  DEVICE_VENDOR := HONOR
  DEVICE_MODEL := FUR-602
  DEVICE_ALT0_VENDOR := HONOR
  DEVICE_ALT0_MODEL := FUR-603
  DEVICE_DTS := mt7981b-honor-fur-602
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += honor,fur-602 honor,fur-603
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 116736k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += honor_fur-602
```

- **刻意不声明** `KERNEL` / `KERNEL_INITRAMFS`：继承 `Device/Default` 的
  `KERNEL = kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb`
  （`target/linux/mediatek/image/Makefile`）。
- 字段结构逐项对齐上游 `h3c_magic-nx30-pro-nmbm`（`filogic.mk:1158`）。

**产物命名**：`DEVICE_IMG_PREFIX = immortalwrt-<ver>-mediatek-filogic-honor_fur-602`
⇒ `...-honor_fur-602-factory.bin` / `...-honor_fur-602-sysupgrade.bin`
DTB：`image-mt7981b-honor-fur-602.dtb`（`KERNELNAME := Image dtbs`）

**config 归属**（源码确认）：`target/linux/mediatek/config-6.6` **不存在**
⇒ `include/target.mk:188-203` 置 `USE_SUBTARGET_CONFIG=1`
⇒ 目标 config 为 **`target/linux/mediatek/filogic/config-6.6`**（最高优先级，
在 `generic/config-6.6` 之后应用并可覆盖）。

**kernel config fragment（`filogic.config.append`）**：
**故意为空**。理由见 §6.4——所有目标能力均由 kmod 提供；
若在此处 `=y` 会把功能塞进内核、违背设计原则，且与上游/参考实现零符号的做法冲突。

---

## 8. GitHub Actions 云编译

工作流：`.github/workflows/build-fur602.yml`（**16 步**，YAML 与全部 shell 块已校验通过）

| # | 步骤 | 要点 |
|---|------|------|
| 1 | Checkout | 拉取本仓库 |
| 2 | Free disk space | 释放 Runner 空间 |
| 3 | Install apt deps | 构建依赖 |
| 4 | Clone source | 默认 `immortalwrt/immortalwrt` @ `openwrt-24.10`；写入 `IMM_COMMIT` / `IMM_COMMIT_SHORT` |
| 5 | **Verify source tree matches assumptions** | ★ 前置断言（见下） |
| 6 | Inject | 拷 `.config`、运行 `diy-part2.sh`；`build_all_kmods=false` 时 `sed` 删除 `CONFIG_ALL_KMODS=y` |
| 7 | feeds update/install | |
| 8 | Re-assert DTS exists | 二次确认 DTS 落地 |
| 9 | `make defconfig` | |
| 10 | **Pre-build check** | ★ 断言设备与 kmod（见下） |
| 11 | `make download -j8` | |
| 12 | `make -j$(nproc) \|\| make -j1 V=s` | 失败自动降级重试 |
| 13 | **Verify images and kmod packages** | ★ 见下 |
| 14 | **Build summary** | 写入 `$GITHUB_STEP_SUMMARY` |
| 15 | Collect artifacts | 镜像 + kernel + dtb + `*.ipk` / `Packages*` |
| 16 | Upload artifact | `honor-fur602-firmware-<commit>`，`if-no-files-found: error` |

**步骤 5 断言**（失败立即 fail，避免"编译几小时才发现设备没进 image"）：

- `KERNEL_PATCHVER` 必须为 `6.6`；
- `filogic.mk`、`image/Makefile`、`dts/` 目录、`filogic/config-6.6` 必须存在；
- `image/Makefile` 必须含 `fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb`；
- `platform.sh` 必须含 `nand_do_upgrade "$1"`，且**不得**含 `honor,fur-602` 特例；
- `target/linux/mediatek/config-6.6` 必须**不存在**（否则 config 归属判断失效）。

**步骤 10 断言**：

- `CONFIG_TARGET_mediatek_filogic_DEVICE_honor_fur-602=y`
- `CONFIG_ALL_KMODS=y`
- `CONFIG_PACKAGE_kmod-mt7915e / kmod-mt7981-firmware / mt7981-wo-firmware = y`
- 6 个 `KernelPackage` 定义存在于 `netsupport.mk` / `netdevices.mk`

**步骤 13 验证**：

- 存在 `factory.bin` / `sysupgrade.bin`；
- `tar tf sysupgrade.bin` 校验含 `sysupgrade-honor_fur_602/` 且内含 `/kernel`、`/root`；
- 列出 manifest / `profiles.json` / DTB；
- 在 `bin/.../packages` 检查 kmod 是否发布：
  `kmod-sched-core`、`kmod-sched`、`kmod-sched-cake`、`kmod-ifb`、
  `kmod-mac80211`、`kmod-cfg80211`、`kmod-mt7915e`、`kmod-nft-core`、`kmod-pppoe`。

**步骤 14 Build summary 输出**：source / branch / commit / kernel 6.6 / target / subtarget /
device / DTS / images / U-Boot 版本，并从 `build_dir/**/linux*/.config` grep 关键 kernel config。

**验证状态**：YAML `safe_load` 通过；13 个 `run` 块全部 `bash -n` 通过；
`diy-part2.sh` 在真实 sparse 树副本上端到端运行成功且**幂等**（跑两次仅 1 处设备定义）。

---

## 9. 风险与刷机步骤（★ 必读）

### 9.1 硬性前置条件

> **⚠️ 设备 env 必须为 `mtd_layout_label = "expand(114m)"`。**

- U-Boot **默认**布局是 `layout@0 "default"`（**64 MiB ubi**）；
- 本固件 `IMAGE_SIZE = 116736k`（**114 MiB**）**只适配** `expand(114m)`；
- 若未切换布局就刷入 ⇒ UBI 溢出 / 无法启动。

**操作**（二选一）：

1. 已有 U-Boot 中执行：`setenv mtd_layout_label "expand(114m)"; saveenv`，重启再生效；
2. 刷入 `mt7981_honor_fur-602_multi_layout_defconfig` 构建的 **multi-layout 版 U-Boot**
   （`MULTI_LAYOUT=1 ./build.sh`），开机能交互选择布局。

`bl-mt798x/README.md` 明确说明：**不同布局的 U-Boot 与不同 firmware 之间互不兼容。**

### 9.2 原厂 U-Boot 不可用

FUR-602 是运营商定制机，原厂 U-Boot **校验并锁定镜像签名**，**无法直接刷写**本固件。
必须先通过 TTL 串口（或对应免拆流程）刷入 hanwckf 定制 U-Boot。

### 9.3 其余风险

| 风险 | 说明 | 缓解 |
|------|------|------|
| 5 GHz 中继跳变 | 此前观测到 351Mbps ↔ 6Mbps 反复 | 本方案不引入驱动魔改；留待实机调信道/DFS/roam 参数 |
| WiFi EEPROM 内容 | `factory@0x0` 的实际内容未逐字节验证 | 需实机 `hexdump` 核对；若异常需修正偏移 |
| Mesh 键行为 | `BTN_9` + `EV_SW` 的实际触发语义未实测 | 需实机 `evtest` 验证 |
| 交换机中断/PHY | GPIO38/39 极性已按 U-Boot DTS，但未在 Linux 侧实测 | 需实机确认 ethtool / dmesg |
| NMBM 坏块表 | `bmt-max-ratio=1` / `bmt-max-reserved-blocks=64` 为上游默认 | 与 U-Boot 的 NMBM 需实机共存验证 |
| 硬件功能未验证 | 4×1G 速率、2500base-x 上联实测吞吐 | 需刷机后实测 |
| USB 能力 | 芯片/固件层面 kmod 齐全，但**硬件无 USB 引出** | 仅供未来扩展，非缺陷 |
| `ALL_KMODS=y` 构建时长 | 编译时间与 artifact 体积显著增加 | 可用 `build_all_kmods=false` 关闭（会失去事后 opkg 装 kmod 的能力） |

### 9.4 刷机步骤

1. **切换布局**：确认 U-Boot env `mtd_layout_label` = `expand(114m)`（见 §9.1）。
2. **首次刷写**：按住 Reset 上电进入 U-Boot Web 恢复页（默认 `192.168.1.1`，自动 DHCP），
   上传 `immortalwrt-<ver>-mediatek-filogic-honor_fur-602-factory.bin`（**裸 UBI**）。
3. **后续升级**：在已运行的 ImmortalWrt 中，用
   `immortalwrt-<ver>-mediatek-filogic-honor_fur-602-sysupgrade.bin` 通过 LuCI 或
   `sysupgrade` 正常升级（**tar 包**，会保留配置；`rootfs_data` 会被重建）。
4. 首次登录 `192.168.1.1`（无密码）。LAN 口取 `factory@0x2a`，WAN 口取 `factory@0x24`。

### 9.5 factory.bin 与 sysupgrade.bin 的机制总结（回应核心提问）

| 镜像 | 格式 | 为什么可用 |
|------|------|-----------|
| `factory.bin` | **裸 UBI**（`append-ubi`，含 EC header） | 分区表无 `kernel` MTD 分区 ⇒ U-Boot `mtd_boot_image()` 走 `boot_from_ubi()` ⇒ 读 UBI 卷 `kernel`（回退 `fit`）。`KERNEL_IN_UBI=1` 产出的卷名恰为 `kernel`/`rootfs`/`rootfs_data`，与 U-Boot `PART_KERNEL_NAME`/`PART_ROOTFS_NAME`/`PART_ROOTFS_DATA_NAME` 完全一致；`IMAGE_SIZE=116736k` 与 `expand(114m)` 的 ubi 分区大小一致。 |
| `sysupgrade.bin` | **tar**（`sysupgrade-tar`，含 `CONTROL`/`kernel`/`root`） | `write_ubi2_tar_image()` 用 `parse_tar_image()` **原地更新**卷 `kernel`/`rootfs`，再 **remove + create** `rootfs_data`；非 DUAL_BOOT 路径（FUR-602 defconfig 未启 `CONFIG_MTK_DUAL_BOOT`）。刷机前由 `nand_do_platform_check()`（`nand.sh:476`）用 `sysupgrade-honor_fur_602/CONTROL` 探测，再由 `nand_verify_tar_file()`（`:377`）`tar xOf` 校验完整性；`board_name`（`honor,fur-602`→`honor_fur_602`）与 tar 内目录名一致。 |

---

## 10. 交付文件清单

| 文件 | 作用 |
|------|------|
| `mt7981b-honor-fur-602.dts` | 设备树（24.10 原生 DSA + NMBM + TAR 路线） |
| `filogic.mk.append` | Device/Image 定义追加块 |
| `filogic.config.append` | kernel config fragment（**故意为空** + 完整论证） |
| `.config` | 构建种子（`honor_fur-602` + `PER_DEVICE_ROOTFS` + `ALL_KMODS`） |
| `diy-part2.sh` | 构建时注入脚本（含多重前置断言，幂等） |
| `.github/workflows/build-fur602.yml` | 云编译工作流（16 步，含前/后置校验与 Build summary） |
| `FINAL-REPORT.md` | 本报告 |
| `README.md` | 面向使用者的简明说明 |

---

## 11. 待实机验证清单（TODO）

- [ ] `mtd_layout_label` 实际值确认（**最高优先级**）
- [ ] `factory@0x0` WiFi EEPROM 内容与偏移核对
- [ ] MT7531 交换机在 Linux 侧的识别与 4 口速率协商
- [ ] `gmac0` 2500base-x 上联实链速率
- [ ] 2.4G / 5G AP + STA（中继）稳定性，重点复测 5G 吞吐跳变
- [ ] monitor mode：`iw dev wlanX interface add mon0 type monitor` + 管理帧抓取 + radiotap
- [ ] `mesh` 键（`BTN_9`/`EV_SW`）触发行为
- [ ] `u-boot-envtools` 读写 env 的权限与偏移
- [ ] sysupgrade 保留配置升级实测
