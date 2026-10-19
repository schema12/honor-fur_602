# FUR-602 → ImmortalWrt 25.12.2 — 实测验证报告

本文件记录**实际执行**的验证结果，替代此前的 `MIGRATION-REPORT.md`
（那份是在终端不可用时写的，其 §0/§11 关于"未执行"的说明已过时）。

生成时间：2026-10-11（本地）

---

## 一、终端故障是否恢复

**已完全恢复。** 上一次的 `3221225794` (`0xC0000142`, `STATUS_DLL_INIT_FAILED`)
不再出现。实测结果：

| 命令 | 结果 |
|------|------|
| `Write-Output "POWERSHELL_OK"` | ✅ 输出 `POWERSHELL_OK` |
| `cmd.exe /c "echo CMD_OK & ver"` | ✅ `CMD_OK` / `Microsoft Windows [Version 10.0.19045.4046]` |
| `git --version` | ✅ `git version 2.37.1.windows.1` |
| `python --version` | ✅ `Python 3.10.10` |
| `bash --version` | ✅ `GNU bash, version 4.4.23(1)-release (x86_64-pc-msys)` |
| 工作区读写 | ✅ 可读可写可创建目录 |

### 网络：需要显式代理（重要）

- DNS 正常，但 **TCP 443 直连被阻断**（`Test-NetConnection github.com:443` → False）。
- 系统 WinINET 代理为 `127.0.0.1:7897`（Clash Verge / verge-mihomo，PID 3124，确实在监听）。
- `git` 与 `curl` **不读取** WinINET 代理，因此最初 `git ls-remote` 超时。
- 解决方式：**按仓库本地**设置 `http.proxy`/`https.proxy`（未改动全局 git 配置），
  curl 用 `-x` 逐次传入。此后全部网络操作正常。

未修改任何 Windows 系统文件、全局安全策略，也未安装无关软件。

---

## 二、真实仓库与分支

| 项目 | 值 |
|------|-----|
| 本地工作区 | `F:\DeepSeek-Harness\DSH` |
| 仓库克隆 | `F:\DeepSeek-Harness\DSH\honor-fur602` |
| remote | `https://github.com/schema12/honor-fur_602.git` |
| 起始分支 | `wip/workbuddy-handoff`（HEAD `e917b8f`，落后于远端） |
| **迁移分支** | **`migration/immortalwrt-25.12.2`**，基于 `origin/main` (`6445674`) |
| 迁移提交 | `ca9678c066b670589634c8bff33ba56523d93659` |

注意：本地 `wip/workbuddy-handoff` 的 HEAD 停在旧提交 `e917b8f`，
真正的 24.10 移植在 `origin/main`（`6445674`）。迁移分支因此**基于 origin/main**，
而不是本地那个过期的分支头。

已推送：`* [new branch] migration/immortalwrt-25.12.2`。**未推送 main，未强制推送。**

---

## 三、新增与修改的文件

**全部为新增（12 个），零删除、零修改既有文件。**

```
A  .config.25.12
A  .gitattributes
A  .github/workflows/build-fur602-25.12.yml
A  02_network.25.12.diff
A  MIGRATION-REPORT.md
A  README-25.12.md
A  diy-part2-25.12.sh            (mode 100755)
A  filogic.config.25.12.append
A  filogic.mk.25.12.append
A  locks/feeds-25.12.2.lock
A  locks/immortalwrt-25.12.2.lock
A  mt7981b-honor-fur-602-2512.dts
```

`git diff --diff-filter=D --name-only origin/main HEAD` → 空（无删除）。

### 24.10 回退基线完好

24.10 工作流 blob 与 `origin/main` **逐字节相同**：

```
HEAD        .github/workflows/build-fur602.yml : 8f4e5acd784dd984b8f7c6a0af6570489e791054
origin/main .github/workflows/build-fur602.yml : 8f4e5acd784dd984b8f7c6a0af6570489e791054
```

两套工作流**不共用任何文件名**：

| 24.10（回退） | 25.12.2（新增） |
|---|---|
| `.config` | `.config.25.12` |
| `diy-part2.sh` | `diy-part2-25.12.sh` |
| `filogic.mk.append` | `filogic.mk.25.12.append` |
| `filogic.config.append` | `filogic.config.25.12.append` |
| `mt7981b-honor-fur-602.dts` | `mt7981b-honor-fur-602-2512.dts` |
| `build-fur602.yml` | `build-fur602-25.12.yml` |

另外历史记录确认：24.10 工作流在 `main` 上**最近一次运行是成功的**
（run `35108878566`，conclusion=`success`）。

---

## 四、固定的 ImmortalWrt 25.12.2 源码 SHA（已实际验证）

**`4fc16f2985a358bd43bb522e43f05395fcbd6ed5`**

用 `git ls-remote` 直接向上游查询（经代理）：

```
bfc8bae082b913eb60e3247bb3e3a9cb3a6fde55	refs/tags/v25.12.2
4fc16f2985a358bd43bb522e43f05395fcbd6ed5	refs/tags/v25.12.2^{}
```

- `v25.12.2` 是**附注标签**（annotated），标签对象 `bfc8bae0…`，
  `^{}` 剥离后指向 commit `4fc16f29…`。与锁定文件一致。
- 本地浅克隆该 SHA 成功，`git rev-parse HEAD` 输出完全一致。

### 版本元数据（本地读取锁定提交）

| 项目 | 值 |
|------|-----|
| `version` 文件 | `r38135-0c4cd0f9920a` |
| `include/version.mk` → `VERSION_NUMBER` 默认 | `25.12.2` |
| `include/version.mk` → `VERSION_CODE` 默认 | `r38135-0c4cd0f9920a` |
| `include/version.mk` → `VERSION_REPO` 默认 | `https://downloads.immortalwrt.org/releases/25.12.2` |
| `KERNEL_PATCHVER` (mediatek) | `6.12` |
| `target/linux/generic/kernel-6.12` | `LINUX_VERSION-6.12 = .103` |
| 内核源码哈希 | `f143aaade8877ba5616e788b4482576db28481bcf557ef537f4fcc3938fc3176` |

**内核版本：Linux 6.12.103。**

### 分支头 ≠ 发布版（关键）

`refs/heads/openwrt-25.12` = `ce35a9e4ef1b87fbbc2146036ce6693e4242861a`
（2026-10-09，"Merge Official Source"），**领先于发布标签**。
若按分支头构建，得到的是滚动的 25.12-SNAPSHOT，而非 25.12.2。
工作流因此固定到标签指向的 commit，并在检出后强校验。

---

## 五、全部 feeds 的实际提交 SHA（已实际验证）

锁定值取自**发布提交自身**写入的 `feeds.conf.default`（`^<sha>` 语法）：

```
src-git packages  https://github.com/immortalwrt/packages.git^84bd86384928955b568988ca0e09e2c78c75173d
src-git luci      https://github.com/immortalwrt/luci.git^d6167ea0645cbd1327708d85f94824f42d0eb872
src-git routing   https://github.com/openwrt/routing.git^e49d76035aafb85ddc993b59271d8c7ba56b5362
src-git telephony https://github.com/openwrt/telephony.git^2618106d5846a4a542fdf5809f0d3ed228ce439b
src-git video     https://github.com/openwrt/video.git^094bf58da6682f895255a35a84349a79dab4bf95
```

逐个向上游验证 **可获取性**（`git fetch --dry-run <url> <sha>`）：

| feed | 仓库 | 锁定 SHA | 上游可取 |
|------|------|----------|----------|
| packages | immortalwrt/packages | `84bd86384928955b568988ca0e09e2c78c75173d` | ✅ |
| luci | immortalwrt/luci | `d6167ea0645cbd1327708d85f94824f42d0eb872` | ✅ |
| routing | openwrt/routing | `e49d76035aafb85ddc993b59271d8c7ba56b5362` | ✅ |
| telephony | openwrt/telephony | `2618106d5846a4a542fdf5809f0d3ed228ce439b` | ✅ |
| video | openwrt/video | `094bf58da6682f895255a35a84349a79dab4bf95` | ✅ |

（GitHub 不在 `ls-remote` 中广告任意 SHA，故用 direct fetch 验证，5/5 全部成功。）

工作流中 feeds 校验分**两道**：
1. `feeds.conf.default` 必须仍把每个 feed 钉在上述 SHA，否则中止；
2. `scripts/feeds update -a` 之后，对 `feeds/<name>` 逐个 `git rev-parse HEAD`
   比对锁定值，任一不符即中止。

CI 中这两步**均已通过**（见第七节步骤 9 与 11）。

---

## 六、实际内核与 mt76 版本

| 项目 | 值 |
|------|-----|
| Linux 内核 | **6.12.103** |
| mt76 驱动来源 | `https://github.com/openwrt/mt76` |
| **mt76 提交** | **`39c960c3ada558b4c2e7915772483d3731573d09`** |
| mt76 源码日期 | `2026-03-19` |
| mt76 PKG_RELEASE | `2` |
| mt76 许可 | `BSD-3-Clause-Clear` |
| mt76 镜像哈希 | `7a9f8ea21eee5324e6638ace627dd305b3650ae6ca86109317d9ee83702140eb` |

无线固件包（均确认存在于主源码树，**不在** packages feed 中）：

- `kmod-mt7915e` — `package/kernel/mt76/Makefile:235`
- `kmod-mt7981-firmware` — `package/kernel/mt76/Makefile:252`
- `mt7981-wo-firmware` — `package/firmware/linux-firmware/mediatek.mk:81`

对照同类 MT7981 设备（`filogic.mk` 第 147/358/399/430 行）使用的正是同一三元组。

---

## 七、静态检查与 DTS 检查的真实结果

### 7.1 工具准备（本地原本缺失）

本地没有 `dtc`，也没有 `cpp`。为**真正执行** DTS 编译检查，我：

1. 从 MSYS2 取得预编译 `dtc` 1.7.2（用 Python `zstandard` 解包 `.zst`，
   因为 Windows 自带 `tar` 无法调用 `zstd`）；
2. 发现 `dtc.exe` 缺 `libyaml-0-2.dll`（`0xC0000135`），一并补齐；
3. 下载官方 **linux-6.12.103.tar.xz**（148 MB），只抽取 DTS 所需的内核头文件；
4. 自建 DTS 预处理器（Windows 无 `cpp`），并**发现并修复**它自身的两个真实缺陷：
   - 未剥离跨行 `/* */` 注释 → 注释尾部泄漏进 DTS；
   - 未做宏展开 → `MTK_DRIVE_8mA`/`GPIO_ACTIVE_LOW`/`KEY_RESTART` 等未替换。

### 7.2 检查结果

| # | 检查项 | 结果 |
|---|--------|------|
| 1 | YAML 语法（25.12 工作流） | ✅ 解析通过，1 个 job，26 个步骤 |
| 2 | YAML 语法（24.10 工作流） | ✅ 解析通过，13 个 run 块 |
| 3 | 25.12 工作流全部 `run:` shell 块 `bash -n` | ✅ 21/21 通过 |
| 4 | 24.10 工作流全部 `run:` shell 块 `bash -n` | ✅ 13/13 通过 |
| 5 | `diy-part2-25.12.sh` `bash -n` | ✅ 通过 |
| 6 | 脚本内嵌 Python 逻辑独立测试 | ✅ 对真实 `02_network` 插入成功、`bash -n` 仍通过、恰好 1 处、幂等 |
| 7 | 脚本**真实执行**（在真实 25.12 树上，跑 2 次） | ✅ 两次 exit 0，第二次正确跳过（幂等） |
| 8 | 设备注册重复检查 | ✅ `Device/honor_fur-602` 恰好 1 次，`TARGET_DEVICES` 恰好 1 次，`02_network` 中 `honor` 恰好 1 次 |
| 9 | **DTS 编译（dtc 1.7.2 + 真实 6.12.103 头文件）** | ✅ **exit 0，产出 17667 字节 DTB** |
| 10 | DTB 回解校验（`dtc -I dtb -O dts`） | ✅ 905 行，见下 |
| 11 | `CONFIG_ALL_KMODS=y` 生效 | ✅ 在 `.config.25.12` 中，且工作流断言其进入生效 `.config` |
| 12 | 工作流引用的每个路径存在 | ✅ 7/7 |
| 13 | 敏感凭据扫描 | ✅ 未发现 token/私钥/密码 |

### 7.3 DTS 编译中发现并修复的真实问题

**问题 A（脚本断言错误，已修复）**：脚本原本断言
`target/linux/mediatek/files-6.12/.../mt7981b.dtsi` 存在。实际运行时**失败**。
排查后确认：`mt7981b.dtsi` **不属于 OpenWrt 树**，它来自内核 tarball
（`arch/arm64/boot/dts/mediatek/mt7981b.dtsi`）。
已改为断言**约定**：树内有 84 个 DTS 使用 `"mt7981b.dtsi"`，且**无任何** DTS
使用旧的 `"mt7981.dtsi"`。工作流中的同类断言也已同步修正。

**问题 B（重大发现，影响 DTS 正确性）**：mainline 6.12.103 的
`mt7981b.dtsi` 只有 **248 行**，**不包含** `eth:` / `spi0:` / `wifi:` /
`mdio_bus:` 等标签 —— 首次 dtc 编译报 `Label or path eth not found`。
查明原因是 OpenWrt 自己的补丁
`target/linux/mediatek/patches-6.12/117-complete-mt7981b-dtsi.patch`
（19 KB）在构建时给该文件补上约 500 行。应用后 `mt7981b.dtsi` 变为 **790 行**，
标签齐全，编译随即通过。

> 这一点值得强调：它证明"只把 `mt7981.dtsi` 改成 `mt7981b.dtsi` 就够"
> 的说法**不完整** —— 真正让 DTS 成立的是 OpenWrt 的补丁 + 内核头文件的组合。
> 工作流因此断言该补丁所依赖的补丁目录存在，且校验标签来自 in-tree 同类 DTS。

**问题 C（换行符，已修复）**：`git add` 报出 CRLF 警告。若
`diy-part2-25.12.sh` 以 CRLF 检出，在 Linux 上会以
`/bin/bash^M: bad interpreter` 失败，heredoc 终止符也会失配。
已新增 `.gitattributes` 强制 `eol=lf`（含 `*.sh`、`*.yml`、`*.dts`、
`*.config*`、`*.append`、`*.lock`、`*.diff`），并 `--renormalize`；
索引中实测 **CR 字节 = 0**。脚本已标记 `100755`。

### 7.4 DTB 回解内容核对

| 项目 | 回解结果 |
|------|----------|
| model | `HONOR FUR-602/603` |
| compatible | `honor,fur-602`, `mediatek,mt7981` |
| NMBM | `mediatek,nmbm`、`bmt-max-ratio=1`、`bmt-max-reserved-blocks=64` |
| SPI 校准 | `spi-cal-enable` 存在 |
| 分区 | `bl2` / `u-boot-env` / `factory` / `trace` / `fip` / `ubi` |
| ubi 大小 | `0x580000 0x7200000`（= 116736 KiB，与 expand(114m) 一致） |
| DSA 端口 | `wan`(port0) / `lan3`(1) / `lan2`(2) / `lan1`(3) / `cpu`(6) |
| 交换机 | `mediatek,mt7531`，`phy-mode="2500base-x"` |
| MAC nvmem | `macaddr@24`、`macaddr@2a`；两个 `nvmem-cell-names="mac-address"` |
| 按键 | reset `linux,code=0x198`(KEY_RESTART)、mesh `0x109`(BTN_9) |
| LED | 两个 `function="status"`，`color=2`(绿)/`1`(红) |
| 内存 | `device_type="memory"` |
| WiFi EEPROM | `mediatek,mtd-eeprom` |

dtc 输出的 4 条 warning 全部位于**上游** `mt7981b.dtsi`（`ice_debug`、
`ap2woccif`、`efuse` 等），与我们的设备树无关。

### 7.5 未能在本地完成的部分

- **`make defconfig` / 完整本地编译**：未在本地执行（需要完整 Linux 工具链；
  本机为 Windows + git-bash，不具备条件）。该部分改由真实 GitHub Actions
  构建覆盖（见第八节）。
- **`dtc` 版本差异**：本地用 1.7.2，CI 用内核自带的 `scripts/dtc`。
  两者对本文 DTS 均应通过；已在 CI 中实际验证。

---

## 八、完整 kmod 云编译

| 项目 | 值 |
|------|-----|
| Workflow | `Build HONOR FUR-602/603 (ImmortalWrt 25.12.2)` |
| **Run ID** | **`38121105627`** |
| URL | https://github.com/schema12/honor-fur_602/actions/runs/38121105627 |
| 分支 | `migration/immortalwrt-25.12.2` |
| 触发时间 | `2026-10-11T07:21:44Z` |
| `build_all_kmods` | **true**（完整 kmod，未按此前建议关闭） |

### 已通过的步骤（真实 CI 结果）

```
[OK]  1. Set up job
[OK]  2. Checkout build config
[OK]  3. Load and validate version locks
[OK]  4. Free disk space
[OK]  5. Install build dependencies
[OK]  6. Clone ImmortalWrt at the locked commit
[OK]  7. Verify the locked source commit          <- SHA 强校验通过
[OK]  8. Verify source tree matches our assumptions
[OK]  9. Pin feeds to the locked commits
[OK] 10. Update and install feeds
[OK] 11. Verify feed commits                      <- feeds SHA 强校验通过
[OK] 12. Inject HONOR FUR-602/603 device support
[OK] 13. Re-assert DTS once feeds are installed
[OK] 14. Generate .config
[OK] 15. Pre-build check -- device, kmods and wireless present  <- CONFIG_ALL_KMODS 断言通过
[OK] 16. Download packages
[..] 17. Build firmware                           <- 进行中
```

**注意**：步骤 17 是完整 kmod 编译，耗时很长。截至本报告生成时仍在进行，
因此**不能宣称构建成功**。后续步骤（镜像校验、kmod 数量校验、产物收集与上传）
尚未执行。

### 构建日志的可访问性限制

`GET /actions/jobs/{id}/logs` 返回 **403 "Must have admin rights to
Repository"**。仓库为 public，但日志下载端点需要管理员权限。
我**没有**为此索取或使用任何访问令牌，因此**无法读取构建日志原文**；
目前依据的是公开可用的 step 级状态 API（`/actions/runs/{id}/jobs`），
它能给出每步的 pass/fail，但不含日志正文。

若步骤 17 失败，仅凭 step 状态无法定位首个实质错误。此时需要仓库管理员
在 Actions 页面查看日志，或提供日志访问方式。

---

## 九、最终产物

**尚未产生。** 构建仍在步骤 17。产物设计如下（将在构建完成后核实实际文件名、
大小与 SHA256）：

1. `fur602-25.12.2-firmware-<run_id>-<sha>` — factory.bin、sysupgrade.bin、
   manifest、profiles.json、build-info.txt、SHA256SUMS.txt
2. `fur602-25.12.2-kmods-<run_id>-<sha>` — 完整 kmod `.ipk` 集 + `Packages` 索引
3. `fur602-25.12.2-rescue-<run_id>-<sha>` — initramfs 救援镜像（若有）

产物筛选规则已设计为：
- 只按 `*honor_fur_602*` 匹配，**不使用**裸 `*.bin`；
- 收集后再检查是否混入 `bl2|preloader|bl31|fip`，有则**中止**；
- 每个产物附 `SHA256SUMS.txt`。

---

## 十、仍未解决的问题与需实机验证事项

### 环境/流程

1. 构建仍在进行，**成败未知**；本报告不把它写成成功。
2. 构建日志需管理员权限才能下载，失败时的日志定位手段受限。
3. `downloads.immortalwrt.org` 在本次环境中不可达，因此官方
   `version.buildinfo`/`feeds.buildinfo`/`config.buildinfo` **未被读取**。
   源码与 feeds 的锁定依据是签名标签 + 发布提交自身的内容，
   对**源码/feeds** 复现性充分，但未独立印证官方**二进制**产物。

### 必须实机验证（本次未做，也不应声称已解决）

1. **5 GHz 同时作 STA 中继 + 本地 AP** — 依赖 mt76 固件在 6.12 下对同 PHY
   并发 STA+AP 的支持，未测；可能受信道/DFS 限制。
2. **2.4 GHz monitor 模式** — 需实机确认 MT7981 固件允许 monitor 及并发；
   且需从 kmod 产物中 `opkg install` 相应模块。
3. **电脑连接本地 5 GHz AP（中继同时在线）** — 取决于第 1 项。
4. **长期连接稳定性** — 需实机长时间运行，软件检查无法替代。
5. **WiFi EEPROM 位于 `factory@0x0`** — DTS 中仍保留
   `TODO(verify-on-hardware)`，需 dump 实机 `factory` 分区确认。
6. **expand(114m) 布局与 NMBM 映射** — 需实机确认与 DTS 分区表一致。

本次**未**刷写任何设备、未修改 U-Boot、未写入闪存。
