# Honor FUR-602 (荣耀 XU50/XT50/XC50) OpenWrt 云编译方案

本目录提供 **荣耀 FUR-602（联通定制版 XU50，与 XT50/XC50 同板型）** 的开源驱动固件
编译所需的一切：设备树（DTS）、设备注册、网络接口映射、以及 GitHub Actions 云编译工作流。

> ⚠️ **重要前提**：FUR-602 是运营商定制机，原厂 U-Boot 校验并锁定镜像，**无法直接刷写**。
> 必须先刷入 [hanwckf/bl-mt798x](https://github.com/hanwckf/bl-mt798x) 提供的
> `mt7981_honor_fur-602` 定制 U-Boot（含 NMBM、web 恢复、DHCP 自动下发），
> 并选择 **expand(114m)** 分区布局。本文的 DTS 与镜像就是按该 U-Boot + expand(114m) 布局写的。
> 刷 U-Boot 需要拆机 + TTL 串口（或对应免拆机流程），不属于本仓库范围，请先参考恩山论坛教程。

## 1. 硬件参数（据 hanwckf bl-mt798x / immortalwrt-mt798x）

| 项目 | 规格 |
|------|------|
| SoC  | MediaTek **MT7981B** (Filogic 820) |
| 内存 | 256 MiB DDR3 |
| 闪存 | 128 MiB SPI-NAND（**NMBM**） |
| 无线 | 2.4G 2x2（MT7981 内置）+ 5G 2x2（MT7976CN）= **AX3000** |
| 网口 | **4×1G**：1 WAN + 3 LAN，全部挂在 MT7531 交换机（gmac0）上 |
| 按键 | Reset（GPIO1，低有效）、Mesh（GPIO0，低有效） |
| LED  | 绿色状态（GPIO8，低有效）、红色状态（GPIO13，低有效） |

分区布局（expand/114m，`factory.bin` 按此打包）：

```
bl2(1M) | u-boot-env(512K) | factory(1920K) | trace(128K) | fip(2M) | ubi(114M)
```

MAC 地址：LAN 取 `factory@0x2a`，WAN 取 `factory@0x24`（已在 DTS 中用 nvmem 配置）。

## 2. 本目录文件说明

| 文件 | 作用 | 在仓库中的位置 |
|------|------|----------------|
| `mt7981b-honor-fur-602.dts` | 设备树（DSA 结构，适配 lede / OpenWrt 23.05+） | 仓库根目录（构建时自动拷入 `target/linux/mediatek/dts/`） |
| `filogic.mk.append` | 设备注册块（参考，`diy-part2.sh` 会自动追加） | 参考用 |
| `02_network.diff` | 网络接口映射补丁（参考） | 参考用 |
| `.config` | 构建种子配置（选择 `honor_fur602` 目标） | 仓库根目录 |
| `diy-part2.sh` | 构建时注入脚本（拷 DTS + 注册设备 + 改 02_network） | 仓库根目录 |
| `.github/workflows/build-fur602.yml` | 云编译工作流 | `.github/workflows/` |

## 3. 方式 A（推荐）：直接在 GitHub 云编译（无需 fork lede）

1. 新建一个 GitHub 仓库，把本目录内容原样推上去（`.config`、`diy-part2.sh`、
   `mt7981b-honor-fur-602.dts`、`.github/workflows/` 都放仓库根目录）。
2. 打开仓库 **Actions** 页 → 允许运行工作流。
3. 点击 **Build Honor FUR-602 OpenWrt firmware** → **Run workflow**。
   - 默认从 `coolsnowwolf/lede` 的 `master` 分支拉取源码并自动注入设备支持。
   - 想用官方源，可把 `repo_url` 填 `https://github.com/openwrt/openwrt`、`repo_branch` 填
     `openwrt-24.10`（或 `main`）。注意官方源与 lede 的 02_network/filogic.mk 路径一致，
     DTS 通用；若锚点不匹配，`diy-part2.sh` 会报错提示手工改。
4. 构建完成后在 **Summary → Artifacts** 下载 `honor-fur602-firmware`。
   - `factory.bin`：用 U-Boot web 恢复页面（或 mtkupgrade）首刷的裸 UBI 镜像。
   - `sysupgrade.bin`：以后在 OpenWrt 里升级用。

## 4. 方式 B：fork lede 并直接加入设备（更规范、可长期维护）

如果你想让设备支持长期固化在源码里（可提交 PR），在 **你的 lede fork** 中做三处改动：

1. 拷贝 DTS：
   ```
   target/linux/mediatek/dts/mt7981b-honor-fur-602.dts
   ```
2. 在 `target/linux/mediatek/image/filogic.mk` 末尾追加 `filogic.mk.append` 的内容
   （`define Device/honor_fur602 ... endef` + `TARGET_DEVICES += honor_fur602`）。
3. 应用 `02_network.diff`，把 `honor,fur-602` 加入
   `target/linux/mediatek/filogic/base-files/etc/board.d/02_network` 的三 LAN 分组。

然后把工作流里的 `repo_url` 改成你的 fork 地址即可（`diy-part2.sh` 的注入都有
幂等保护，不会重复添加）。

## 5. 关键实现说明

- **DTS 采用 DSA 结构**（`mediatek,mt7531` 交换机 + `&switch { ports }`），与 lede 当前
  `mt7981.dtsi` 及上游 OpenWrt 23.05+ 一致，不使用老 swconfig 写法。
- **单 gmac0**：WAN/LAN 都在 MT7531 上，WAN=port0，LAN=port1/2/3（对应 lan3/lan2/lan1），
  CPU=port6（2500base-x）。与 immortalwrt-mt798x 的 `1:lan:3 2:lan:2 3:lan:1 0:wan` 一致。
- **NMBM**：`spi_nand@0` 上开了 `mediatek,nmbm`，与 bl-mt798x U-Boot 的 NMBM 匹配。
- **MAC**：`factory` 分区 nvmem 提供 `0x24`(WAN)/`0x2a`(LAN)；`gmac0` 用 0x2a，`port@0`(wan) 用 0x24。
- **无线**：`&wifi` 走开源 mt76 驱动，eeprom 取 `factory@0x0`；固件包由
  `kmod-mt7981-firmware` + `mt7981-wo-firmware` 提供。

## 6. 刷机提示

1. 确认已刷入 hanwckf bl-mt798x 的 `mt7981_honor_fur-602` U-Boot，且布局为 **expand(114m)**。
2. 按住 reset 上电进入 U-Boot web 恢复（默认 `192.168.1.1`，自动 DHCP），上传 `factory.bin`。
3. 刷完等重启，首次登录 `192.168.1.1`（OpenWrt/LEDE 默认），LAN 口取 `factory@0x2a` 的 MAC。

## 7. 参考

- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) — OpenWrt 云编译模板
- [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) — LEDE 源码（MT7981 已支持）
- [openwrt/openwrt](https://github.com/openwrt/openwrt) — 官方源码（MT7981 已支持）
- [hanwckf/bl-mt798x](https://github.com/hanwckf/bl-mt798x) — FUR-602 定制 U-Boot（含 defconfig 与布局）
- [hanwckf/immortalwrt-mt798x](https://github.com/hanwckf/immortalwrt-mt798x) — FUR-602 老式 swconfig 参考实现
- 恩山论坛 XU50 刷机帖（设备拆机/TTL/U-Boot 流程）
