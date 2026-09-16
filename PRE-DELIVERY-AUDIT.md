# 交付前最终检查（Pre-Delivery Audit）

审计时间：2026-09-16
审计对象：`honor-fur602-handoff` 全部交付物
审计原则：**只读验证，不扩大修改范围**；每条结论给出源码位置

---

## 1. 是否严格以 20241115 U-Boot 为启动依据 → **✅ 是**

### 1.1 版本锚定

| 证据 | 内容 |
|------|------|
| `bl-mt798x` HEAD | `git describe` → **`20241115`**；commit `15ad0ed949043bcbbcb5ef501ba156b1f25e676f` |
| `build.sh:5` | `UBOOT_DIR=uboot-mtk-20230718-09eda825`（**未被注释**，即生效值） |
| `build.sh:4,6` | `#UBOOT_DIR=uboot-mtk-20220606` / `#ATF_DIR=atf-20220606-637ba581b`（**已注释**，不生效） |
| `build.sh:7` | `ATF_DIR=atf-20231013-0ea67d76a` |

⇒ **20241115 发布版就是用 `uboot-mtk-20230718-09eda825` 这棵树构建的**。
因此本方案引用的 `uboot-mtk-20230718-09eda825/arch/arm/dts/mt7981-honor_fur-602.dts`
与 `configs/mt7981_honor_fur-602_defconfig` **就是设备当前 U-Boot 的真实定义**，不是 20220606 旧版。

**补充**：`find` 显示 FUR-602 的 DTS 只存在于 `uboot-mtk-20220606/` 与
`uboot-mtk-20230718-09eda825/` 两棵树；`uboot-mtk-20250711` **已不含该板**。
本项目**只**引用 `uboot-mtk-20230718-09eda825`（=20241115 实际使用的那棵）。

### 1.2 关键硬件事实与 U-Boot DTS 一致性

| 事实 | 本项目值 | U-Boot DTS 证据 |
|------|---------|----------------|
| gmac0 上行 | `2500base-x`，fixed-link 2500 | `&eth { phy-mode = "2500base-x"; fixed-link { speed=<2500>; } }` |
| 交换机 | `mediatek,mt7531`，reset GPIO39 ACTIVE_HIGH | `mediatek,switch = "mt7531"; reset-gpios = <&gpio 39 GPIO_ACTIVE_HIGH>` |
| 按键 | reset=GPIO1 / mesh=GPIO0 (`BTN_9`) | `gpio-keys { reset-button / mesh-button }` |
| LED | green=GPIO8 / red=GPIO13 | `green:system` / `red:system` |
| NMBM | 启用 | `CONFIG_ENABLE_NAND_NMBM=y`, `CONFIG_CMD_NMBM=y` |

### 1.3 启动路径与 U-Boot 源码一致（逐分支核对）

`mtd_boot_image()`（`mtd_helper.c:1175`）：

```c
mtd_kernel = get_mtd_device_nm(PART_KERNEL_NAME);   /* "kernel" MTD 分区 */
if (!ki && ...) mtd_kernel = NULL;

ubi_boot_part = PART_UBI_NAME;                       /* "ubi"，非 multi-layout 时固定 */
mtd = get_mtd_device_nm(ubi_boot_part);

if (mtd valid) {
    if (mtd_kernel && mtd_kernel->parent == mtd->parent) {
        if (!CONFIG_MTK_DUAL_BOOT) return boot_from_mtd(mtd_kernel, 0);
    } else {
        if (CONFIG_MTK_DUAL_BOOT) return ubi_dual_boot(mtd);
        return boot_from_ubi(mtd);                   /* ★ 我们走这里 */
    }
}
```

- 我们的分区表**无 `kernel` MTD 分区** ⇒ `mtd_kernel = NULL` ⇒ 条件 `mtd_kernel && ...` 为假
  ⇒ 进 `else` 分支；
- `CONFIG_MTK_DUAL_BOOT` **未启用**（defconfig grep 无该符号）⇒ `return boot_from_ubi(mtd)`。

`boot_from_ubi()`（`:1038`）：

```c
mount_ubi(mtd, false);
read_ubi_volume(PART_KERNEL_NAME /* "kernel" */, ...);   /* 优先 */
if (ret == ENODEV) read_ubi_volume(PART_FIT_NAME /* "fit" */, ...);  /* 回退 */
boot_from_mem(...);
```

⇒ 与 `KERNEL_IN_UBI=1` 产出的 UBI 卷 **`kernel`** 精确对应。

**结论：启动依据严格锚定在 20241115（=20230718 源码树）的 U-Boot 行为上，逐分支可验证。**

---

## 2. 既有 114M 分区布局是否被保持（未重新设计）→ **✅ 完全保持**

### 2.1 U-Boot 侧布局定义（权威）

`uboot-mtk-20230718-09eda825/arch/arm/dts/mt7981-honor_fur-602.dts:24-39`：

```
mtd-layout {
    layout@0 { label = "default";      /* stock 64m ubi */
               mtdparts = "nmbm0:1024k(bl2),512k(u-boot-env),1920k(factory),
                           128k(Trace),2048k(fip),
                           65536k(ubi),128k(Tracebak),51200k(foxfs)"; };

    layout@1 { label = "expand(114m)"; /* 114m ubi */
               mtdparts = "nmbm0:1024k(bl2),512k(u-boot-env),1920k(factory),
                           128k(Trace),2048k(fip),116736k(ubi)"; };
};
```

### 2.2 本项目 DTS 分区（逐项比对）

| 分区 | 本项目 DTS `reg` | U-Boot `expand(114m)` | 一致 |
|------|------------------|----------------------|------|
| bl2 | `0x0000000 0x100000` | `1024k` | ✅ |
| u-boot-env | `0x0100000 0x80000` | `512k` | ✅ |
| factory | `0x0180000 0x1e0000` | `1920k` | ✅ |
| trace | `0x0360000 0x20000` | `128k` | ✅ |
| fip | `0x0380000 0x200000` | `2048k` | ✅ |
| **ubi** | `0x0580000` `0x7200000` | **`116736k`** | ✅ |

**数值验证**：`0x7200000 / 1024 = 116736` KiB ✅ 与 U-Boot 声明的 `116736k` **完全相等**。
总占用 = `0x7780000` = 119.5 MiB < 128 MiB ✅。

### 2.3 Image 定义侧

`filogic.mk.append` 的 `IMAGE_SIZE := 116736k` —— 与上述 ubi 分区大小**同一数值**。

### 2.4 结论

- 未新增、未删除、未移动任何分区；
- 未改动 ubi offset/size；
- 未改动 `layout@0`/`layout@1` 的定义；
- 唯一动作是**在 Linux DTS 中复刻 `expand(114m)` 的既有布局**（这是 Linux 侧描述，非重新设计）。

**同时确认：为让 Action 出镜像而修改 U-Boot 预期分区结构的行为 = 零。**

---

## 3. `mtd_layout_label` 的实际要求 → **必须精确等于 `expand(114m)`**

### 3.1 源码语义

`board/mediatek/common/mtd_layout.c`：

```c
const char *get_mtd_layout_label(void)
{
    const char *layout_label = NULL;
    if (gd->flags & GD_FLG_ENV_READY)
        layout_label = env_get("mtd_layout_label");   /* 读 U-Boot env */
    if (!layout_label)
        layout_label = "default";                      /* ★ 缺省值 */
    return layout_label;
}

static ofnode ofnode_get_mtd_layout(const char *layout_label)
{
    ofnode_for_each_subnode(layout, ofnode_path("/mtd-layout")) {
        label = ofnode_read_string(layout, "label");
        if (!strcmp(layout_label, label))   /* ★ 精确字符串比较 */
            return layout;
    }
    return ofnode_null();
}
```

### 3.2 三条硬性结论

1. **变量名**必须是 `mtd_layout_label`（读的是 `env_get`，即 U-Boot 环境变量）；
2. **取值**必须是字符串 **`expand(114m)`** —— 注意：含**小写 `expand`、半角括号、`114m`**，
   `strcmp` 精确匹配，**多一个空格、改大小写、用全角括号都会失败**；
3. **不设 = 用 `default` = 64 MiB ubi** ⇒ 我们的 116736k 镜像放不下。

### 3.3 实际要求（两条路径，二选一）

| 路径 | 操作 | 说明 |
|------|------|------|
| **A. 使用现有 defconfig U-Boot** | 在 U-Boot 命令行执行 `setenv mtd_layout_label "expand(114m)"` + `saveenv` | 该 defconfig 的 `CONFIG_MTDPARTS_DEFAULT` 硬编码为 **64m（default 布局）**，因此必须靠 env 覆盖 |
| **B. 使用 multi-layout U-Boot** | 刷 `mt7981_honor_fur-602_multi_layout_defconfig` 构建的版本（`MULTI_LAYOUT=1 ./build.sh`），开机交互选择 | `diff` 显示它**删除了** `CONFIG_MTDPARTS_DEFAULT` 并加了 `CONFIG_MEDIATEK_MULTI_MTD_LAYOUT=y`，即布局完全由选择决定 |

> **补充（multi-layout 的副作用，需知晓）**：启用 `CONFIG_MEDIATEK_MULTI_MTD_LAYOUT` 后，
> `mtd_boot_image()` 会用 `env_get("ubi_boot_part")` 决定从哪个分区引导，
> `mtd_upgrade_image()` 若发现 env 中同时存在 `sysupgrade_kernel_ubipart` +
> `sysupgrade_rootfs_ubipart` 会改走 `write_ubi2_tar_image_separate()`（双分区路径）。
> 由于 FUR-602 的 **layout 节点未定义 `boot_part` / `factory_part` / `cmdline` /
> `sysupgrade_*_ubipart`**（已 grep 确认无这些属性），`env_set()` 会写入空值，
> 两者都回退到默认 `"ubi"` 与单分区路径 ⇒ **与路径 A 行为一致**。
>
> **建议**：**优先使用路径 A**（现有 defconfig U-Boot + `setenv`），路径最短、变量最少。

### 3.4 需上机确认

`printenv mtd_layout_label` 的**当前实际值**。若设备此前从未设置过，它就是空的
⇒ 当前 U-Boot 正以 64m `default` 布局运行 ⇒ **必须先切换再刷本固件**。

---

## 4. factory.bin / sysupgrade.bin 各自的使用场景

### 4.1 判定依据（U-Boot 侧如何区分两者）

`mtd_upgrade_image()`（`mtd_helper.c:1088`）用 `parse_image_ram()`
（`image_helper.c:288`）判型，顺序：

```
genimg_get_format() → LEGACY? / FIT?
   default:
      tar_header_checksum(data) 成功  → IMAGE_TAR      （= sysupgrade.bin）
      否则                            → parse_image_ubi2_ram() → IMAGE_UBI2  （= factory.bin）
```

非 multi-layout 时（我们的 defconfig）分支结果：

| 判型 | 走向 | 对应镜像 |
|------|------|---------|
| `IMAGE_UBI2` | `mtd_update_generic(mtd, data, size, true)` —— **整片 ubi 分区原始写入** | **`factory.bin`** |
| `IMAGE_TAR` | `write_ubi2_tar_image(data, size, mtd)` —— **按卷更新** | **`sysupgrade.bin`** |
| `HEADER_FIT` | `write_ubi_fit_image()` | （本项目不产出） |

### 4.2 使用场景

| | `factory.bin` | `sysupgrade.bin` |
|---|---|---|
| **格式** | 裸 UBI（`append-ubi`，含 UBI EC header） | tar（`sysupgrade-tar` + `append-metadata`） |
| **内部结构** | UBI 卷 `kernel` / `rootfs` / `rootfs_data` | `sysupgrade-honor_fur_602/{CONTROL,kernel,root}` |
| **写入方式** | 整片覆盖 ubi 分区（`mtd_update_generic`） | 按卷原地更新 `kernel`/`rootfs`，**remove+create** `rootfs_data` |
| **是否保留配置** | ❌ **全清**（连 `rootfs_data` 一起被覆盖） | ✅ **保留**（`rootfs_data` 重建但配置在 overlay 中……见下方注意） |
| **使用场景** | ① **首次**从 U-Boot Web 恢复页刷机<br>② 布局切换后重刷<br>③ 固件严重损坏、需要"回到出厂状态" | ① 已运行 ImmortalWrt 后**日常升级**<br>② LuCI "刷写固件" / `sysupgrade` 命令行 |
| **入口** | U-Boot Web failsafe（默认 `192.168.1.1`，自动 DHCP）<br>`bootmenu_mtd.c:286 write_firmware()` → `mtd_upgrade_image()` | 运行中的系统：`nand_do_upgrade()` → U-Boot 下次启动... **实际是** OpenWrt 的 `sysupgrade` 调用 U-Boot 的 `mtd_upgrade_image` 等价路径 |
| **前置条件** | `mtd_layout_label = expand(114m)`（同样必须） | 同上 |
| **风险** | 低（整片写入，目标分区固定）<br>但**必须**确认布局正确，否则溢出 | 中：`rootfs_data` 会被重建，**部分配置可能丢失**（见 §6 待实测项） |

> **关于 `sysupgrade` 保留配置的准确表述**：
> `write_ubi2_tar_image()` 会 `remove_ubi_volume("rootfs_data")` 后 `create_ubi_volume("rootfs_data")`，
> 即 **overlay 分区被重建**。OpenWrt 的 `sysupgrade` 默认会在升级前把 `/etc` 备份到
> **临时位置并在首次启动时恢复**（`/sysupgrade.tgz` 机制，落在新 `rootfs_data` 中），
> 因此"保留配置"这一用户感知是成立的，但**机制上不是原地保留**。
> **此项需实机验证**（见 §7）。

### 4.3 本项目两个镜像与 U-Boot 的对应（最终确认）

```
filogic.mk.append:
  IMAGE/factory.bin    := append-ubi | check-size $$$$(IMAGE_SIZE)   → 裸 UBI  → U-Boot: IMAGE_UBI2 → mtd_update_generic
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata           → tar     → U-Boot: IMAGE_TAR  → write_ubi2_tar_image
  IMAGE_SIZE           := 116736k  （= expand(114m) 的 ubi 大小）
  KERNEL_IN_UBI        := 1        （ubinize 产出卷 kernel/rootfs/rootfs_data）
```

**四个卷名常量交叉验证**（`mtd_helper.c:30-35`）：
`PART_KERNEL_NAME="kernel"` / `PART_ROOTFS_NAME="rootfs"` / `PART_ROOTFS_DATA_NAME="rootfs_data"`
—— 与 `KERNEL_IN_UBI=1` 的 ubinize 产物**逐字一致**。

**独立第三方确证**：`hanwckf/immortalwrt-mt798x` 的 `mt7981.mk:661` `Device/honor_fur-602`
与本项目定义逐字同构（同 `IMAGE_SIZE=116736k`、同 `KERNEL_IN_UBI=1`、同两个 IMAGE 行）。

---

## 5. GitHub Actions 最终会生成哪些镜像和 .ipk

### 5.1 镜像（`bin/targets/mediatek/filogic/`）

| 文件 | 说明 | Workflow 是否断言存在 |
|------|------|---------------------|
| `immortalwrt-<ver>-mediatek-filogic-honor_fur-602-**factory.bin**` | 裸 UBI，首刷 | ✅ `[ -n "$FACTORY" ]` 否则 fail |
| `immortalwrt-<ver>-mediatek-filogic-honor_fur-602-**sysupgrade.bin**` | tar，升级 | ✅ `[ -n "$SYSUP" ]` 否则 fail |
| `image-mt7981b-honor_fur-602.dtb` | 设备树二进制 | 收集（`'*.dtb'`） |
| `kernel` | FIT 内核（`Image + dtb`） | 收集 |
| `profiles.json` / `*.manifest` | 设备清单 | 收集；`profiles.json` 断言含 `honor,fur-602`（warning） |

### 5.2 `.ipk`（`bin/targets/mediatek/filogic/packages/`）

**路径已源码确认**：`rules.mk:180` `PACKAGE_DIR ?= $(BIN_DIR)/packages`，
`rules.mk:151` `BIN_DIR := $(OUTPUT_DIR)/targets/$(BOARD)/$(SUBTARGET)`
⇒ `bin/targets/mediatek/filogic/packages`。
**不存在 `kmods` 子目录**（已 grep 全库 `packages/kmods` 零命中）⇒ 所有 `.ipk` **平铺**在该目录。

`CONFIG_ALL_KMODS=y` 时，**每个 kmod 包**都会产出 `.ipk`。Workflow 显式检查 9 个关键包：

```
kmod-sched-core  kmod-sched  kmod-sched-cake  kmod-ifb
kmod-mac80211    kmod-cfg80211  kmod-mt7915e  kmod-nft-core  kmod-pppoe
```

命中输出 `OK`，未命中输出 `MISS`（**注意：当前是 echo，不是 fail** —— 见 §8 建议）。

**除 kmod 外**还会包含：普通 feed 包（`Packages`/`Packages.gz` 索引 +
所有在 `ALL`/`ALL_NONSHARED`/`ALL_KMODS` 下变 `m` 的包）
——这意味着 **产物体积会明显增大**（`ALL_KMODS=y` 的代价）。

### 5.3 镜像内**实际安装**的包（≠ 发布的 .ipk）

来自 `DEFAULT_PACKAGES` + `DEFAULT_PACKAGES.router` + `filogic/target.mk` + `DEVICE_PACKAGES`：

```
dnsmasq-full firewall4 nftables kmod-nft-offload odhcp6c odhcpd-ipv6only ppp ppp-mod-pppoe
fitblk kmod-phy-aquantia kmod-crypto-hw-safexcel wpad-openssl uboot-envtools bridger
luci-light default-settings-chn kmod-nf-nathelper kmod-nf-nathelper-extra
kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
```

**注意 `fitblk`**：`filogic/target.mk` 默认包含它，但本项目走 TAR 路线（不用 fitblk）。
这是**无害的**（`fitblk` 仅是一个小工具，未使用时不会被调用），
且**不应删除**（它是 subtarget 默认，删了会偏离上游）。
如追求极致精简可在 `DEVICE_PACKAGES` 无法移除（它是全局默认），**故保留**。

### 5.4 Artifact

`honor-fur602-firmware-<IMM_COMMIT_SHORT>`（`retention-days: 14`），
内容 = `out/`（镜像 + `PROFILES`/manifest + kernel + dtb + `out/packages/` 的 ipk 与索引），
`if-no-files-found: error`。

---

## 6. `CONFIG_ALL_KMODS=y` 是否满足"rootfs 精简 + kmod 尽可能完整" → **✅ 满足（源码可证）**

### 6.1 三个源码事实

**(a) kmod 是 tristate**

- `include/package-dumpinfo.mk:44`：ipkg 包默认 `Type: ... ipkg`
- `scripts/metadata.pm:289-291`：遇到 `Type: ... ipkg` ⇒ `$pkg->{tristate} = 1`
- `scripts/package-metadata.pl:308`：`print ($tristate ? 'tristate' : 'bool')`
  ⇒ **kmod 的 Kconfig 类型是 `tristate`** ⇒ `m` 合法。

**(b) `ALL_KMODS` 只影响"编译/发布"，不影响"安装"**

`scripts/package-metadata.pl:309-318`：

```perl
print "\t\tdefault y if DEFAULT_".$pkg->{name}."\n";    /* ← 决定是否装机 */
unless ($pkg->{hidden}) {
    my @def = ("ALL");
    push @def, "ALL_NONSHARED" unless exists $pkg->{repository};
    push @def, "ALL_KMODS" if $pkg->{name} =~ /^kmod-/;  /* ← 只对 kmod-* 加 */
    $pkg->{default} ||= "m if " . join("||", @def);      /* ← m，不是 y */
}
```

⇒ `CONFIG_ALL_KMODS=y` 使 `kmod-*` 的默认值变为 **`m`**（编译 + 发布 `.ipk`），
**只有** `DEFAULT_PACKAGES` / `DEVICE_PACKAGES` 被强制 `y`（装机）。

**(c) 真正决定"装不装进镜像"的是 `=y`**

`m` 与 `y` 的区别在 `include/package-pack.mk` / `package.mk` 的安装规则——
`m` 的包只产出 `.ipk` 到 `PACKAGE_DIR`，不进入 `TARGET_DIR`（rootfs）。

### 6.2 结论矩阵

| 目标 | 实现 | 结果 |
|------|------|------|
| rootfs 精简 | 只有 `DEFAULT_PACKAGES` + `DEVICE_PACKAGES` 为 `y` | ✅ 未变（与不加 `ALL_KMODS` 时**完全相同**） |
| kmod 尽可能完整 | 所有 `kmod-*` 变 `m` ⇒ 全部编译并发布 `.ipk` | ✅ 全套可用 |
| 未来 opkg 安装 | `.ipk` 已发布 + kernel ABI 由同一次构建产生 ⇒ 版本匹配 | ✅ 可装 |

### 6.3 与参考实现的对比（说明本方案更强）

`hanwckf/immortalwrt-mt798x` `defconfig/mt7981-ax3000.config`（同一文件选了 FUR-602）**只有**：

```
CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-ifb=y
```

**缺** `kmod-sched` / `kmod-sched-cake` / `kmod-sched-prio` / `kmod-sched-fq-pie` / `kmod-sched-ctinfo`
⇒ 那份固件**无法**支持事后 `opkg install sqm-scripts`（SQM 依赖 CAKE）。
本方案通过 `ALL_KMODS=y` **避免了这一缺陷**。

### 6.4 需注意的取舍（非缺陷）

- 构建**时间**显著增加（要编译全部 kmod）；
- `.ipk` 产物体积显著增加；
- 可通过 workflow input `build_all_kmods=false` 关闭，
  但**会失去**事后 `opkg install kmod-sched-cake` 的能力（回到参考实现的短板）。
  **建议保持 `true`。**

---

## 7. 目前还有哪些问题**必须上真机**才能确认

按优先级排序（**均无法通过源码静态分析解决**）：

### P0 —— 不确认就无法刷机

1. **`mtd_layout_label` 的当前值**
   `printenv mtd_layout_label`。若为 `default`（或未设置），**必须先 `setenv` 切换**
   到 `expand(114m)` 才能刷本固件（见 §3）。
2. **实际 Flash 容量与坏块状态**
   128 MiB 标称，但 NMBM 保留块数量会影响可用空间。
   `mtd list` / `nand info` 确认真实可用容量 ≥ 119.5 MiB。
3. **当前 U-Boot 是否为 20241115 构建**
   `version` 命令确认。若设备上是更早/更晚的 U-Boot，布局定义可能不同。

### P1 —— 刷机后立即验证

4. **Linux 能否正确识别分区表**
   `cat /proc/mtd`，比对 6 个分区名与 offset/size 是否与 §2.2 一致。
5. **NMBM 在 Linux 侧是否正常挂载**
   `dmesg | grep -i nmbm`、`ubiattach` 是否成功。
6. **MT7531 交换机识别与 4 口速率**
   `dmesg | grep mt7531`、`ip link`、每口 `ethtool` 速率协商。
7. **gmac0 2500base-x 上联实链速率**
   `ethtool eth0` / `dmesg`。若协商失败会导致 4 口全不通。
8. **WiFi EEPROM 内容**
   `hexdump -C /dev/mtdblock2 | head`（factory@0x0 处应有有效校准数据）。
   若为空/乱码 ⇒ WiFi 起不来或性能异常。
9. **2.4G / 5G 是否能起来并正常发射**
   `iw dev`、`wifi status`、`dmesg | grep mt7915`。

### P2 —— 稳定性与功能验证

10. **5 GHz 中继 351Mbps ↔ 6Mbps 跳变是否复现**
    （本项目最大历史遗留问题；**本方案未做驱动魔改，需实测确认原生 mt76 是否已修复**）
11. **monitor mode 能力**
    `iw phy phy0 info | grep -A3 monitor`、
    `iw dev wlan0 interface add mon0 type monitor`、`tcpdump -i mon0`。
12. **`mesh` 按键 `BTN_9` + `EV_SW` 的实际触发行为**
    `evtest`。若 `EV_SW` 语义不当，可能需要改为普通 `KEY_*`（**但这是实机才能定的事**）。
13. **`sysupgrade` 保留配置是否真的生效**
    改一个配置项 → `sysupgrade -k` / LuCI 升级 → 重启后确认配置还在
    （机制上 `rootfs_data` 会被重建，依赖 `/sysupgrade.tgz` 恢复，需实测）。
14. **`u-boot-envtools` 能否正常读写 env**
    `fw_printenv` / `fw_setenv`（注意 `CONFIG_ENV_OFFSET=0x0` 但 `CONFIG_ENV_MTD_NAME="u-boot-env"`，
    是以**分区名**定位，故 `/etc/fw_env.config` 应写 `/dev/mtd1` 而非裸 offset）。
15. **`factory.bin` 首刷后再刷 `sysupgrade.bin` 的完整往返**
    验证 §4.1 的判型分支在实机上确实各走对路径。
16. **LED 行为**
    开机/启动完成/失败时的绿红 LED 是否按 `led-boot`/`led-running`/`led-failsafe` 预期点亮。
17. **复位键（GPIO1）触发 failsafe / 恢复模式**
    长按是否能进入 U-Boot Web 恢复页或 OpenWrt failsafe。

> **以上 17 项均属"需实机证据"，本项目不做任何猜测性修改。**

---

## 8. 可选的两处小改进（**不扩大范围，仅登记**）

以下两点是审计中发现的**非阻塞**问题，**本轮不修改**，仅登记备查：

1. **Workflow 中 kmod `MISS` 只 warning/echo，不 fail。**
   若 `ALL_KMODS` 意外失效，构建仍会"成功"但缺 `.ipk`。
   建议将来把 `MISS` 改为 `exit 1`（或至少 `::warning::` 标注）。
   *位置：`build-fur602.yml` 步骤 "Verify images and kmod packages" 的 kmod 循环。*
2. **`sysupgrade.bin` 的 `ustar` 探测实际未参与判断。**
   代码里 `TAR="$SYSUP"` 两个分支都指向同一文件，`head -c 265 | tail -c 8 | grep ustar`
   的结果未被使用（真正的校验靠 `tar tf`）。**功能不受影响**（`tar tf` 才是有效检验），
   但这几行是死代码，可读性上可清理。
   *位置：同步骤中 `if head -c 265 ...` 段。*

---

# 刷机前检查清单（**只列必须确认项**）

> 本清单按执行顺序排列。**任何一项未通过，都不要开始刷写。**

## 阶段 1：U-Boot 环境（在 U-Boot 命令行执行）

- [ ] **1.1** 确认 U-Boot 版本为 `20241115` 构建
      → `version`
- [ ] **1.2** 确认分区布局变量已设为 `expand(114m)`
      → `printenv mtd_layout_label`
      → 若为空或为 `default`：`setenv mtd_layout_label "expand(114m)"` + `saveenv` + 重启
      → 重启后**再次** `printenv mtd_layout_label` 确认已保存
- [ ] **1.3** 确认分区表已按新布局生效，ubi 分区为 **116736k**
      → `mtd list`（应见 `ubi` = `0x7200000`，即 114 MiB）
- [ ] **1.4** 确认 U-Boot 能正常联网（Web 恢复页可访问）
      → 按住 Reset 上电，浏览器打开 `192.168.1.1`

## 阶段 2：镜像准备（在电脑上）

- [ ] **2.1** 下载的 `factory.bin` 文件名含 `honor_fur-602` 且非 0 字节
- [ ] **2.2** 文件大小合理（约 20–40 MB 量级，绝不能 > 119.5 MiB）
- [ ] **2.3** 已备份当前可用的原厂/旧固件（若条件允许）

## 阶段 3：首刷（U-Boot Web 恢复页）

- [ ] **3.1** 使用 **`factory.bin`**（不是 sysupgrade.bin）上传
- [ ] **3.2** 等待写入完成并自动重启（**不要中途断电**）
- [ ] **3.3** 确认系统能启动（LAN 口有响应，`192.168.1.1` 可访问）

## 阶段 4：首刷后立即核对（SSH / 串口）

- [ ] **4.1** `cat /proc/mtd` —— 6 个分区与预期一致（bl2/u-boot-env/factory/trace/fip/ubi）
- [ ] **4.2** `dmesg | grep -iE 'nmbm|ubi|mt7531'` —— 无致命错误，交换机识别正常
- [ ] **4.3** `ip link` —— `wan` + `lan1/2/3` 四口齐全
- [ ] **4.4** 2.4G 与 5G 均能起来（`iw dev` 见两个 phy）
- [ ] **4.5** `factory@0x0` 处 WiFi 校准数据非空（避免 WiFi 异常）

## 阶段 5：升级路径验证

- [ ] **5.1** 用 **`sysupgrade.bin`** 做一次升级，确认能正常重启回系统
- [ ] **5.2** 确认升级后配置（如修改过的 LAN IP）是否保留

---

## 附：本次审计的验证执行记录

| 验证项 | 方法 | 结果 |
|--------|------|------|
| U-Boot 版本锚定 | `git describe` / `git log -1` / `build.sh` | ✅ 20241115 @ `15ad0ed…`，UBOOT_DIR=20230718 |
| FUR-602 DTS 存在树 | `find` | ✅ 仅 20220606 / 20230718 两棵，`20250711` 无 |
| 布局 label 精确匹配 | `mtd_layout.c` `strcmp` | ✅ 必须精确 `expand(114m)` |
| 布局缺省值 | `get_mtd_layout_label()` | ✅ 缺省 `"default"`（64m） |
| 分区数值一致性 | `0x7200000/1024` vs `116736k` | ✅ 相等；总占用 119.5 MiB < 128 MiB |
| DUAL_BOOT | defconfig grep | ✅ 未启用 |
| multi-layout 差异 | `diff` 两个 defconfig | ✅ 仅多 `MULTI_MTD_LAYOUT=y`、删 `MTDPARTS_DEFAULT` |
| 启动分支 | `mtd_helper.c:1175/1038` | ✅ 无 kernel 分区 ⇒ `boot_from_ubi` ⇒ 卷 `kernel` |
| 升级判型 | `image_helper.c:288` `parse_image_ram` | ✅ UBI2 → `mtd_update_generic`；TAR → `write_ubi2_tar_image` |
| Web failsafe 入口 | `bootmenu_mtd.c:286` | ✅ `write_firmware` → `mtd_upgrade_image` |
| 签名校验 | defconfig grep `MTK_UPGRADE_IMAGE_VERIFY` | ✅ 未启用（无签名校验） |
| kmod 输出目录 | `rules.mk:151,180` | ✅ `bin/targets/mediatek/filogic/packages`（无 kmods 子目录） |
| kmod tristate | `metadata.pm:289-291`、`package-metadata.pl:308` | ✅ tristate |
| ALL_KMODS 语义 | `package-metadata.pl:316` `=~ /^kmod-/` | ✅ 仅 kmod 得 `m`；`y` 仅来自 `DEFAULT_*` |
| Workflow YAML | `yaml.safe_load` | ✅ 16 steps |
| Workflow shell | 13 个 `run` 块 `bash -n` | ✅ 全通过 |
| 注入脚本 e2e | 真实树副本运行 2 次 | ✅ exit 0，幂等（定义计数=1） |
| 注入脚本负路径 | 4 项构造失败 | ✅ 全部正确 exit 1 |
| 设备定义同构 | 对比 `mt7981.mk:661` | ✅ 逐字一致 |

**审计结论：当前方案在源码层面自洽、可交付。除 §7 的 17 项真机确认项外，无阻塞问题。**
