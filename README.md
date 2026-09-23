# HONOR FUR-602/603 → ImmortalWrt 24.10 设备移植

把 **荣耀 FUR-602 / FUR-603**（联通定制版 XU50，与 XT50/XC50 同板型，MT7981B）
移植到 **ImmortalWrt 24.10**（`openwrt-24.10` 分支，kernel **6.6**）的完整方案。

- 结构对齐 ImmortalWrt 上游（DSA + NMBM + UBI2/TAR 路线），无私有魔改
- GitHub Actions 云编译，含构建前/后置自动校验
- 无线优先（原生 mac80211 + mt76），支持 monitor mode
- **内核能力完整**（`CONFIG_ALL_KMODS=y`，全套 kmod 可 opkg 安装）而**用户态精简**

> 详细论证（源码级证据、行号、风险分析）见 **[FINAL-REPORT.md](FINAL-REPORT.md)**。

---

## ⚠️ 两个硬性前提（刷机前必读）

1. **必须已刷入 [hanwckf/bl-mt798x](https://github.com/hanwckf/bl-mt798x) 的定制 U-Boot**
   （`mt7981_honor_fur-602`）。原厂 U-Boot 校验并锁定镜像签名，**无法直接刷写**本固件。
   

2. **必须切换分区布局为 `expand(114m)`**。
   U-Boot 内置两套布局，**默认是 `default`（ubi 仅 64 MiB）**；
   本固件 `IMAGE_SIZE = 116736k`（**114 MiB**）**只适配 `expand(114m)`**。

   ```
   在 U-Boot 中执行：
     setenv mtd_layout_label "expand(114m)"
     saveenv
   ```
   或刷入 `MULTI_LAYOUT=1 ./build.sh` 构建的 multi-layout 版 U-Boot 并交互选择。

   > 不同布局的 U-Boot 与 firmware 之间**互不兼容**。未切换布局直接刷入会导致 UBI 溢出/无法启动。

---

## 1. 硬件参数

| 项目 | 规格 |
|------|------|
| SoC | MediaTek **MT7981B**（Filogic 820），双核 Cortex-A53 |
| 内存 | 256 MiB DDR3 |
| 闪存 | 128 MiB SPI-NAND（**NMBM**） |
| 无线 | 2.4G 2×2（MT7981 内置）+ 5G 2×2（MT7976CN）= **AX3000** |
| 网口 | **4×1G**：1 WAN + 3 LAN，全部挂 MT7531 交换机，单 `gmac0` 上联 |
| gmac0 上行 | **`2500base-x`**，fixed-link 2500 Mbps |
| 交换机 reset | GPIO 39（ACTIVE_HIGH）；中断 GPIO 38 |
| 按键 | Reset = **GPIO1**（低有效）、Mesh = **GPIO0**（低有效，`BTN_9`/`EV_SW`） |
| LED | 绿状态 = **GPIO8**、红状态 = **GPIO13**（均低有效） |
| MAC | WAN = `factory@0x24`，LAN/gmac0 = `factory@0x2a` |
| WiFi EEPROM | `factory@0x0` |
| USB / PCIe | 无引出 |

分区布局（`expand(114m)`，与 U-Boot 完全对应）：

```
bl2(1M) | u-boot-env(512K) | factory(1920K) | trace(128K) | fip(2M) | ubi(114M)
```

---

## 2. 文件说明

| 文件 | 作用 |
|------|------|
| `mt7981b-honor-fur-602.dts` | 设备树（24.10 原生 DSA + NMBM + SPI cal + TAR 路线） |
| `filogic.mk.append` | Device/Image 定义追加块（参考；`diy-part2.sh` 自动追加） |
| `filogic.config.append` | kernel config fragment——**故意为空**，附完整理由 |
| `.config` | 构建种子（`honor_fur-602` + `PER_DEVICE_ROOTFS` + `ALL_KMODS`） |
| `diy-part2.sh` | 构建时注入脚本（多重前置断言，幂等可重复运行） |
| `.github/workflows/build-fur602.yml` | 云编译工作流（16 步，含前/后置校验与 Build summary） |
| `FINAL-REPORT.md` | **完整实施报告**（源码级证据、镜像机制论证、风险清单） |

---

## 3. 云编译

1. 新建 GitHub 仓库，把本目录内容推上去。
2. **Actions** → 允许运行工作流 → **Build Honor FUR-602/603 ImmortalWrt firmware** → **Run workflow**。
   - 默认源：`immortalwrt/immortalwrt`，分支 `openwrt-24.10`。
   - `build_all_kmods`（默认 `true`）：保留 `CONFIG_ALL_KMODS=y`，
     生成全套 kmod `.ipk`（**推荐**，这样以后能直接 `opkg install` SQM/CAKE 等）。
3. 构建完成后在 **Summary → Artifacts** 下载 `honor-fur602-firmware-<commit>`，
   内含镜像、kernel、DTB，以及 `packages/*.ipk`。

**产物**（`bin/targets/mediatek/filogic/`）：

| 文件 | 用途 |
|------|------|
| `immortalwrt-*-mediatek-filogic-honor_fur-602-**factory.bin**` | 裸 UBI，U-Boot Web 恢复页**首次刷写** |
| `immortalwrt-*-mediatek-filogic-honor_fur-602-**sysupgrade.bin**` | tar，已在 ImmortalWrt 中**正常升级** |
| `image-mt7981b-honor-fur-602.dtb` | 设备树二进制 |

工作流会在编译**前**断言 DTS/设备定义/内核版本/kmod 包名，在编译**后**验证镜像文件名、
tar 内部结构与 kmod `.ipk` 是否发布，并输出 Build summary。任何一步失败立即终止。

---

## 4. 为什么 factory.bin 能被 U-Boot 识别

- 分区表中**没有**名为 `kernel` 的 MTD 分区 ⇒ U-Boot `mtd_boot_image()`
  （`mtd_helper.c:1175`）必然走 `boot_from_ubi()`（`:1038`）分支；
- 该分支读取 UBI 卷 **`kernel`**（`PART_KERNEL_NAME`，`ENODEV` 时回退 `fit`）；
- `KERNEL_IN_UBI=1` + `append-ubi` 产出的裸 UBI 镜像，卷名正是
  `kernel` / `rootfs` / `rootfs_data`，与 U-Boot 常量逐一对应；
- `IMAGE_SIZE = 116736k` 与 `expand(114m)` 的 ubi 分区大小一致。

**卷名、分区名、偏移、大小四者全部对齐**，故可直接挂载启动。

## 5. 为什么 sysupgrade.bin 能安全升级

- `sysupgrade.bin` 是 **tar**，内部为 `sysupgrade-honor_fur_602/{CONTROL,kernel,root}`；
- U-Boot `write_ubi2_tar_image()`（`mtd_helper.c:765`）用 `parse_tar_image()`
  **原地更新** UBI 卷 `kernel` / `rootfs`，并 **remove + create** `rootfs_data`（清空配置）；
- FUR-602 defconfig **未启用** `CONFIG_MTK_DUAL_BOOT` ⇒ 走普通路径，不涉及 A/B slot；
- 刷机前由 `nand_do_platform_check()`（`nand.sh:476`）用
  `sysupgrade-honor_fur_602/CONTROL` 探测设备匹配，
  再由 `nand_verify_tar_file()`（`:377`）执行 `tar xOf` 校验完整性；
- tar 内目录名 `honor_fur_602` 与运行时 `board_name`（DTS `honor,fur-602` → `,`→`_`）一致。

---

## 6. 刷机步骤

1. 确认 U-Boot env `mtd_layout_label` = **`expand(114m)`**（见开头"硬性前提"）。
2. 按住 **Reset** 上电，进入 U-Boot Web 恢复页（默认 `192.168.1.1`，自动 DHCP）。
3. 上传 `...-honor_fur-602-factory.bin`，等待重启。
4. 首次登录 `192.168.1.1`（password）。LAN 用 `factory@0x2a`，WAN 用 `factory@0x24`。
5. 后续升级用 `...-honor_fur-602-sysupgrade.bin`（LuCI 或 `sysupgrade`，保留配置）。

---

## 7. 内核能力与精简策略

**原则：kmod 集合完整（ABI 匹配、可随时 opkg 安装），但装进镜像的用户态包保持精简。**

关键点在 `CONFIG_ALL_KMODS=y`：

- kmod 包是 **tristate**（`metadata.pm:291`），且 `ALL_KMODS` **默认 `n`**
  （`config/Config-build.in` 无 `default y`）；
- 默认构建下，netfilter/QoS/IFB 等 kmod 若没有任何包依赖它们，
  **既不会编译也不会发布 `.ipk`** ⇒ 以后 `opkg install sqm-scripts` 会因缺 CAKE 而失败；
- `CONFIG_ALL_KMODS=y` 使每个 kmod 变为 `m`：**编译并发布 `.ipk`，但不装进镜像**。

因此镜像仍只包含 `DEFAULT_PACKAGES` / `DEFAULT_PACKAGES.router` / `filogic/target.mk`
追加项 / `DEVICE_PACKAGES`，而 SQM（`kmod-sched-cake`）、IFB（`kmod-ifb`）、
netfilter/nftables、bridge/VLAN、PPPoE、USB、ext4/f2fs 等能力全部**可事后安装**。

> 参考实现 `hanwckf/immortalwrt-mt798x` 只设了 `kmod-sched-core` + `kmod-ifb`，
> **缺 CAKE**，事后装 SQM 会失败——本方案通过 `ALL_KMODS=y` 规避。

**无线**：完全使用 24.10 原生 **mac80211 + mt76**，不引入任何驱动魔改。
`DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware`，
覆盖 2.4G/5G AP+STA、WPA/WPA2/WPA3、WMM、11n/ac/ax、80 MHz。
monitor mode 由 mac80211/mt76 提供能力（内核与驱动已具备），用户态工具按需安装。

---

## 8. 参考

- [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) — 目标源码（`openwrt-24.10`）
- [hanwckf/bl-mt798x](https://github.com/hanwckf/bl-mt798x) — FUR-602 定制 U-Boot（tag `20241115` 为设备当前版本）
- [hanwckf/immortalwrt-mt798x](https://github.com/hanwckf/immortalwrt-mt798x) — FUR-602 参考实现（独立交叉验证）
- [cmi.hanwckf.top — ImmortalWrt MT798x](https://cmi.hanwckf.top/p/immortalwrt-mt798x/)
