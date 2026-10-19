> ⚠️ 免责声明
> 本仓库全部内容由 AI 完成，未经人工逐项审核。
> 可能存在错误，请自行甄别、验证后再使用。

# HONOR FUR-602/603 → ImmortalWrt 设备移植

把 **荣耀 FUR-602 / FUR-603**（联通定制版 XU50，与 XT50/XC50 同板型，MT7981B / Filogic 820）
移植到 ImmortalWrt 的完整方案。

本仓库同时维护**两套**互不干扰的方案：

| | **主方案（当前）** | **回退方案（旧版）** |
|---|---|---|
| 发行版 | **ImmortalWrt 25.12.2** | ImmortalWrt 24.10 |
| 内核 | **6.12.103** | 6.6 |
| 构建工作流 | [`build-fur602-25.12.yml`](.github/workflows/build-fur602-25.12.yml) | [`build-fur602.yml`](.github/workflows/build-fur602.yml) |
| 状态 | 已实机刷入并运行 | 保留为可回退路径 |

两套方案**文件不重名、配置不混用**：25.12.2 的所有文件都带 `25.12` 后缀，24.10 的保持原样。
**不要把 25.12.2 的脚本或配置与 24.10 的混用**，两者内核与包格式都不同。

> 详细论证见：[25.12.2 迁移报告](MIGRATION-REPORT.md)、[CI 重构说明](CI-REFACTOR-25.12.md)、
> [校验实测记录](VERIFY-ONLY-RESULTS-25.12.md)、[24.10 实施报告](FINAL-REPORT.md)。

---

## ⚠️ 两个硬性前提（刷机前必读，两套方案都适用）

1. **必须已刷入 [hanwckf/bl-mt798x](https://github.com/hanwckf/bl-mt798x) 的定制 U-Boot**
   （`mt7981_honor_fur-602`）。原厂 HONOR U-Boot 校验并锁定镜像签名，**无法直接刷写**本固件。

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

## 已归档固件（推荐直接下载）

不需要自己编译。已构建并验证过的固件发布在 **GitHub Releases**：

> **[查看全部 Release](../../releases)**

| 版本 | 内核 | 标签 | 说明 |
|---|---|---|---|
| **ImmortalWrt 25.12.2**（主方案） | 6.12.103 | `fur602-immortalwrt-25.12.2-build-38134666544` | 当前主力版本，已实机验证可运行 |
| ImmortalWrt 24.10 | 6.6 | 见 Releases 列表 | 回退方案 |

Release 中的固件标签**指向实际参与编译的设备适配提交**，而不是之后的 CI 整合提交。

### 25.12.2 归档产物的来源

| 项目 | 值 |
|---|---|
| 构建运行 | `38134666544` |
| 设备适配提交 | `f2f6fbcac4c18c3ba7e7667e608e3e4583c13299` |
| ImmortalWrt 源码提交 | `4fc16f2985a358bd43bb522e43f05395fcbd6ed5`（`refs/tags/v25.12.2`） |
| 内核 | `6.12.103` |
| 产物校验运行 | `38208789499`（verify-only，未编译） |

### 各产物的实际用途

| 文件 | 用途 |
|---|---|
| `*-squashfs-factory.bin` | **首次刷写**。裸 UBI 镜像，通过 U-Boot Web 恢复页上传。 |
| `*-squashfs-sysupgrade.bin` | **后续升级**。tar 格式，在系统内用 LuCI / `sysupgrade` 刷入，可保留配置。 |
| `*-initramfs-kernel.bin` | **救援镜像**。只在内存中运行，不写 flash，用于救砖或临时排查。 |
| kmods 包集（`.apk`） | 完整、ABI 匹配的内核模块集合，**按需安装**，不在镜像内。 |

> **kmod 包集限制**：由 `CONFIG_ALL_KMODS=y` 生成，**只适用于内核 6.12.103**。
> 25.12.2 默认 `CONFIG_USE_APK=y`，因此是 `.apk` + `packages.adb` 索引，**不是** opkg 的 `.ipk`/`Packages`。
> 内核版本不匹配时不可安装，换固件后需取用对应包集。

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

## 2. 仓库结构

两套方案的文件并列在仓库根目录，靠**文件名后缀**区分，互不覆盖。

### 主方案：ImmortalWrt 25.12.2（kernel 6.12）

| 文件 | 作用 |
|------|------|
| `mt7981b-honor-fur-602-2512.dts` | 设备树（kernel 6.12 版本） |
| `filogic.mk.25.12.append` | Device/Image 定义追加块 |
| `filogic.config.25.12.append` | kernel config fragment（**故意为空**，理由见文件内注释） |
| `.config.25.12` | 构建种子（含 `CONFIG_ALL_KMODS=y`） |
| `diy-part2-25.12.sh` | 构建时注入脚本（前置断言，失败即中止） |
| `locks/immortalwrt-25.12.2.lock` | **主源码锁定**（含证据链） |
| `locks/feeds-25.12.2.lock` | **5 个 feed 锁定** |
| `02_network.25.12.diff` | LAN/WAN 映射的参考 diff（脚本会程序化应用） |
| `.github/workflows/build-fur602-25.12.yml` | **云编译**（build + verify 两个作业） |
| `.github/workflows/verify-fur602-25.12.yml` | **纯校验**（复用已有产物，永不编译） |
| `.github/workflows/release-fur602-25.12.yml` | **归档发布**（把已验证产物挂到 Release） |
| `ci/` | 上述两个工作流调用的校验脚本 |
| `README-25.12.md` | 25.12.2 的补充说明 |

### 回退方案：ImmortalWrt 24.10（kernel 6.6）

| 文件 | 作用 |
|------|------|
| `mt7981b-honor-fur-602.dts` | 设备树（24.10 版本） |
| `filogic.mk.append` | Device/Image 定义追加块 |
| `filogic.config.append` | kernel config fragment（故意为空） |
| `.config` | 构建种子 |
| `diy-part2.sh` | 构建时注入脚本 |
| `.github/workflows/build-fur602.yml` | 云编译（单作业） |

> 24.10 方案**完整保留**，未做任何删改，可随时回退。

---

## 3. 固定的源码版本

25.12.2 方案**不接受"当前分支最新提交"**，而是锁定到官方 `v25.12.2` 标签所指的提交：

| 项目 | 锁定值 |
|---|---|
| 仓库 | `https://github.com/immortalwrt/immortalwrt` |
| 引用 | `refs/tags/v25.12.2` |
| 标签对象 | `bfc8bae082b913eb60e3247bb3e3a9cb3a6fde55` |
| **源码提交** | **`4fc16f2985a358bd43bb522e43f05395fcbd6ed5`** |
| 内核 | `6.12.103`（`KERNEL_PATCHVER=6.12`） |

5 个 feed 也逐一锁定：

| feed | 提交 |
|---|---|
| packages | `84bd86384928955b568988ca0e09e2c78c75173d` |
| luci | `d6167ea0645cbd1327708d85f94824f42d0eb872` |
| routing | `e49d76035aafb85ddc993b59271d8c7ba56b5362` |
| telephony | `2618106d5846a4a542fdf5809f0d3ed228ce439b` |
| video | `094bf58da6682f895255a35a84349a79dab4bf95` |

**任何一项不匹配，构建立即中止**，不会静默退回浮动分支。
详见 [`locks/immortalwrt-25.12.2.lock`](locks/immortalwrt-25.12.2.lock) 与
[`locks/feeds-25.12.2.lock`](locks/feeds-25.12.2.lock)。

> **可复现性边界（诚实说明）**：源码与 feed 已精确锁定，但 `make download` 拉取的
> 上游 tarball 以及 GitHub 托管运行器镜像**未锁定**，因此**不主张**逐比特可复现。

---

## 4. 云编译（如果确实需要自己构建）

### 25.12.2

**`main` 分支上不会因推送自动编译**，因为一次完整编译约需 3.5 小时。要构建时显式触发：

> **Actions** → **Build HONOR FUR-602/603 (ImmortalWrt 25.12.2)** → **Run workflow**

| 输入 | 说明 |
|---|---|
| `source_sha` | 覆盖锁定的 ImmortalWrt 提交。**实验性**：这样构建出的镜像会被标记并最终**故意失败**，避免被误当成发布基线。 |
| `build_all_kmods` | 默认 `true`，保留 `CONFIG_ALL_KMODS=y`，生成全套 kmod（**推荐**）。 |
| `reuse_run_id` | **只做校验**：复用指定运行已上传的 raw 产物，**跳过编译**。 |

推送 `migration/immortalwrt-25.12.2` 仍会触发构建（供持续开发使用），
但推送 `main` 不会。

### 24.10

> **Actions** → **Build HONOR FUR-602/603 (ImmortalWrt 24.10)** → **Run workflow**

---

## 5. 工作流的校验机制

25.12.2 的构建拆成**两个独立作业**，这是刻意设计：

- **`build`**（昂贵，数小时）：编译完成后**立即**上传原始构建产物，使用 `if: always()`，
  因此**即使后续校验失败，编译成果也不会丢失**。
- **`verify`**（廉价，数秒）：下载 raw 产物后校验、打包、发布。**内部不含任何编译命令**
  （有自动检查强制这一点）。

> 这么设计的原因：第一次构建时，编译成功但**校验步骤有 bug**，而收集/上传步骤当时没有
> `if: always()`，于是被跳过、运行器磁盘销毁、约 3 小时成果全部丢失。详见
> [CI-REFACTOR-25.12.md](CI-REFACTOR-25.12.md)。

另有**纯校验工作流** `verify-fur602-25.12.yml`：它只有一个作业、没有任何 build 作业，
从结构上就不可能编译，专门用于在**不重新编译**的前提下复验并重新发布已有产物。

---

## 6. 刷机步骤

1. 确认 U-Boot env `mtd_layout_label` = **`expand(114m)`**（见开头"硬性前提"）。
2. 按住 **Reset** 上电，进入 U-Boot Web 恢复页（默认 `192.168.1.1`，自动 DHCP）。
3. 上传 `*-factory.bin`，等待重启。
4. 首次登录 `192.168.1.1`。LAN 用 `factory@0x2a`，WAN 用 `factory@0x24`。
5. 后续升级用 `*-sysupgrade.bin`（LuCI 或 `sysupgrade`，保留配置）。
6. 若刷坏，用 `*-initramfs-kernel.bin` 救援（仅内存运行，不写 flash）。

> 本仓库**不会**自动刷机、不改 U-Boot、不改分区表、不写 flash。

---

## 7. 内核能力与精简策略

**原则：kmod 集合完整（ABI 匹配、可随时安装），但装进镜像的用户态包保持精简。**

关键在 `CONFIG_ALL_KMODS=y`：

- kmod 包是 **tristate**，且 `ALL_KMODS` **默认 `n`**；
- 默认构建下，netfilter/QoS/IFB 等 kmod 若没有任何包依赖它们，
  **既不会编译也不会发布** ⇒ 以后装 SQM 会因缺 CAKE 而失败；
- `CONFIG_ALL_KMODS=y` 使每个 kmod 变为 `m`：**编译并发布，但不装进镜像**。

因此镜像仍只含 `DEFAULT_PACKAGES` / `DEVICE_PACKAGES`，而 SQM（`kmod-sched-cake`）、
IFB（`kmod-ifb`）、netfilter/nftables、PPPoE、USB 等能力全部**可事后安装**。

**无线**：两套方案都用**原生开源 `mac80211` + `mt76`**，不引入任何闭源或树外驱动。

---

## 8. 已验证 / 未验证

**已验证（真实运行，非静态推断）**

- ImmortalWrt 25.12.2 完整固件编译成功（运行 `38134666544`）。
- 全量 kmod 已生成并发布（1118 个 `.apk`）。
- 产物经独立校验运行 `38208789499` **逐文件复核**：1130 个文件 SHA256 全部一致。
- 25.12.2 固件已**刷入实体 FUR-602 并运行**。

**仍未经过完整实机验证**

- **5 GHz STA + AP 并发**（中继同时开本地 AP）的稳定性。
- **2.4 GHz monitor 模式**。
- **EEPROM / WiFi 校准数据**读取路径（DTS 中仍标注 `TODO(verify-on-hardware)`）。
- **NAND / NMBM** 长期读写稳定性与坏块处理。

**工作流层面仍未实测**

- 重构后 `build` 作业"编译完立即上传 raw 产物"这条路径，尚未经过一次**真实完整云编译**。
- 重构后的 `build → verify` **完整交接**同样未实测。

> 这两项只做过静态检查，**不等于**已经跑通。为避免为此再花数小时编译，本次未触发构建。

---

## 9. 参考

- [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) — 目标源码
- [hanwckf/bl-mt798x](https://github.com/hanwckf/bl-mt798x) — FUR-602 定制 U-Boot
- [hanwckf/immortalwrt-mt798x](https://github.com/hanwckf/immortalwrt-mt798x) — 参考实现
- [cmi.hanwckf.top — ImmortalWrt MT798x](https://cmi.hanwckf.top/p/immortalwrt-mt798x/)
