# verify-only 复用实测记录（25.12.2）

本文记录一次**真实运行**的结果，而不是代码检查结论。二者的区别在最后单独说明。

- 验证分支：`ci/split-build-verify-25.12`
- 验证提交：`db98cca5c335d86dc086bec1906ded9ee7cd07e6`
- verify-only 运行：**run `38208789499`**（run number 1）
  <https://github.com/schema12/honor-fur_602/actions/runs/38208789499>
- 被复用的源运行：**run `38134666544`**（run number 2，`success`，`migration/immortalwrt-25.12.2` @ `f2f6fbc`）
  <https://github.com/schema12/honor-fur_602/actions/runs/38134666544>

## 1. 这次运行有没有编译？

没有。可核验的事实：

- 该运行**只有一个作业** `verify`，不存在 `build` 作业，连被跳过的 `Build firmware` 都不存在。
- 该作业共 14 个步骤（12 个业务步骤 + `Post Checkout` + `Complete job`）**全部 `success`**，
  **整个作业 22 秒**（`2026-10-12T05:38:07Z` → `05:38:29Z`）。
  一次真实的 25.12.2 全量编译约需 **213 分钟**；22 秒在物理上不可能是编译。
- 步骤 3「Announce verify-only mode」在运行期执行 `ci/assert-verify-only.py`，
  该脚本在**运行期**（不是只在合并前）断言作业集合恰为 `['verify']`，且全文不含
  `make defconfig` / `make download` / `make -j` / `make world` / `feeds update` /
  `feeds install` / `scripts/feeds` / `toolchain` 等任何编译类命令。任一命中即硬失败。
- 步骤 4「Guard -- no build tree present」断言工作区里不存在源码/构建/暂存目录，
  因此即便有人偷偷加了编译命令，也没有可编译的源码树。
- 本次运行**没有**创建任何新的编译运行：仓库运行总数 5 → 5，只多出这 1 次 verify-only 运行。
- `build_all_kmods` 保持 `true`；没有用 `build_all_kmods=false` 之类的开关来「避免编译」。

## 2. 三个产物是不是真的被复用了？

是，而且是**逐字节**复用。判断依据不是产物名，而是把源运行的产物和重新发布的产物
**全部解压后逐文件比对 SHA256**：

| 源产物（run 38134666544） | 重新发布产物（run 38208789499） | 逐字节相同 |
| --- | --- | --- |
| `fur602-25.12.2-firmware-38134666544-4fc16f2` | `fur602-25.12.2-verified-firmware-from-38134666544-by-38208789499` | 8 / 8 个载荷相同 |
| `fur602-25.12.2-kmods-38134666544-4fc16f2` | `fur602-25.12.2-verified-kmods-from-38134666544-by-38208789499` | 1121 / 1121 个载荷相同 |
| `fur602-25.12.2-rescue-38134666544-4fc16f2` | `fur602-25.12.2-verified-rescue-from-38134666544-by-38208789499` | 1 / 1 个载荷相同 |

**合计 1130 个文件逐字节相同，0 个不同。**

差异只有三类，且都是校验器的**预期行为**，不是内容变化：

- `SHA256SUMS.txt`：校验器重新生成自己的清单（2 个集合各 1 个）。
- 新增 `VERIFICATION.md`、`original-sums/`：记录来源并**原样保留**源运行的校验和文件。
- 被策展剔除：`immortalwrt-...-initramfs-kernel.bin`（已移入 rescue 集合）、
  OpenWrt 自带的小写 `sha256sums`（被重新生成的清单取代）、rescue 里重复的 `build-info.txt`。

关键载荷的 SHA256（源运行 == 重新发布，完全一致）：

```
2e21f9cf68db96a7d6e60dd85cd393554f2cab6adb79e08124398d5f0da845a3  ...-squashfs-factory.bin
12f74ab7e15bf3f01447bec8eee49441d203ab398c9a9314858890cf00ee8979  ...-squashfs-sysupgrade.bin
c8ea5e7d9463ad833b45dafafdbb7544853983061201ee4f77bf16abb2bd5f21  ...honor_fur-602.manifest
b3a16c68a7235050ea5ccd69e80de16fe97a2ee12c639488fa383c7ff4c585a6  build-info.txt
9ae1b6789d940f29...                                              kmod-mt76-core-6.12.103.2026.03.19~39c960c3-r2.apk
88e4ab741a079c88...                                              packages.adb
16ec0237af2bde9d751aa48c464af56f5fbe1202c5e429e57e22f22bc98e65d1  ...-initramfs-kernel.bin
```

## 3. 输入 / 输出产物清单

### 输入（run 38134666544，全部 `expired=false`）

| 产物 | 字节 | 大小 | artifact id | zip SHA256 |
| --- | ---: | ---: | ---: | --- |
| `fur602-25.12.2-firmware-38134666544-4fc16f2` | 37,043,978 | 35.3 MiB | 11705940071 | `8150f4016fc47ae1b0d249911ba71ebf3ee2a526102ea18aaba44ab953408f09` |
| `fur602-25.12.2-kmods-38134666544-4fc16f2` | 47,451,819 | 45.3 MiB | 11705575595 | `f7ca9e12e384a21c217fec10360c81c7b008f57277c14b52cf5b239f9340d7d3` |
| `fur602-25.12.2-rescue-38134666544-4fc16f2` | 12,001,163 | 11.4 MiB | 11704699788 | `f7244bfe25b84e23033a719be4505b827f52265a440c00f04aaecc577e341c0d` |

### 输出（run 38208789499，全部 `expired=false`，2026-11-11 到期）

| 产物 | 字节 | 大小 | artifact id | zip SHA256 |
| --- | ---: | ---: | ---: | --- |
| `fur602-25.12.2-verified-firmware-from-38134666544-by-38208789499` | 25,095,557 | 23.9 MiB | 11728825300 | `3f6b146da843950db12a9deda13b07bdb8a4b5857dc492cda9760349b72d30e8` |
| `fur602-25.12.2-verified-kmods-from-38134666544-by-38208789499` | 47,452,528 | 45.3 MiB | 11728361186 | `76a1e292be728090ea9153bb10c2c280e0bd8f160e2da0aed885a3f2ace56e78` |
| `fur602-25.12.2-verified-rescue-from-38134666544-by-38208789499` | 11,999,189 | 11.4 MiB | 11728670552 | `f7a706e85db4ce58d9025aca78258798c8ec4c6e383ee63bc837a4fdc6a740ea` |

上表的 zip SHA256 是用 GitHub API 的 `digest` 字段与实际下载到的字节**双向核对**过的，全部 MATCH。

### 校验和是否真的算过

算过，而且是在下载后的真实字节上重算的：

- 重新发布集合自带 `SHA256SUMS.txt`，**1129 / 1129 项全部通过，0 项不符**。
- 源运行自带的 `SHA256SUMS.txt` 也**独立复算**过：firmware 10/10、kmods 1120/1120、rescue 2/2，
  0 缺失、0 不符 —— 说明用来做比对基准的源产物本身是自洽可信的。
- `original-sums/` 里保留的三份源校验和文件与源运行原件**逐字节相同**。

### 内容结构（独立复算，不是照抄工作流结论）

- **firmware**：`squashfs-factory.bin`（14,024,704 B）、`squashfs-sysupgrade.bin`（12,534,064 B）、
  `.manifest`、`profiles.json`、`build-info.txt`、`config/feeds/version.buildinfo`。
- **sysupgrade 结构**：顶层目录恰为 `sysupgrade-honor_fur-602/`，内含 `CONTROL`、`kernel`、`root`。
  板名与 `DEVICE=honor_fur-602` 一致。
- **kmods**：1118 个 `.apk`、0 个 `.ipk`，索引 `packages.adb`（155,468 B），无残留 opkg `Packages`。
  25.12 默认 `CONFIG_USE_APK=y`，所以 `.apk` 才是正确的格式。
- **rescue**：`initramfs-kernel.bin`，首 4 字节 `d00dfeed`，是 **FIT** 容器（符合 `KERNEL_IN_UBI` 方案）。
- **BL2 / preloader / FIP 泄漏检查**：firmware 与 rescue 两个可刷写集合里
  **没有任何** BL2 / preloader / BL31 / FIP 文件，也没有 mt7986/mt7987/mt7988/mt7622 等其他芯片的
  BL2。源构建目录里的 `mt7981-ram-ddr3-bl2.bin` 等文件**没有**被带进产物。
- kmods 集合里确实存在 `kmod-mt7622-firmware`、`kmod-mt7986-firmware` 等其他 SoC 的**内核模块包**。
  这是 `CONFIG_ALL_KMODS=y` 生效的**证据**，不是污染：该集合是软件包仓库而非刷机镜像。

### 溯源一致性（全部对上）

| 项 | 值 |
| --- | --- |
| github run id | 38134666544 |
| config repo commit | `f2f6fbcac4c18c3ba7e7667e608e3e4583c13299` |
| immortalwrt commit | `4fc16f2985a358bd43bb522e43f05395fcbd6ed5` |
| immortalwrt ref | `refs/tags/v25.12.2` |
| immortalwrt url | `https://github.com/immortalwrt/immortalwrt` |
| kernel version | 6.12.103 |
| version code | `r38135-0c4cd0f9920a` |
| target / device | `mediatek/filogic` / `honor_fur-602` |
| build_all_kmods | true |

`feeds.buildinfo` 中 5 个 feed 的 SHA 与锁文件完全一致（packages `84bd8638…`、luci `d6167ea0…`、
routing `e49d7603…`、telephony `2618106d…`、video `094bf58d…`）。
`version.buildinfo` = `r38135-0c4cd0f9920a`。manifest 里含 `kmod-mt76-core`、`kmod-mt7915e`、
`kmod-mt7981-firmware`，即**原生开源 mt76** 驱动，与既定要求一致。

**没有发现任何过期/串味文件，也没有编造任何版本信息。**

## 4. 源运行没有被干扰

- run `38134666544` 仍然是 `completed / success`，`head_sha` 仍是 `f2f6fbc`，3 个产物仍然存在且未过期。
- 本次 verify-only 运行**只读**该运行的产物，没有重新上传、没有覆盖、没有删除。
- `concurrency` 组是 `${{ github.workflow }}-${{ github.ref }}`，按 ref 隔离，
  因此既不会取消别的分支的构建，也不会被别的分支的构建取消。
- 24.10 回滚工作流 `.github/workflows/build-fur602.yml` 与 `origin/main` **逐字节相同**
  （blob `8f4e5acd784dd984b8f7c6a0af6570489e791054`），整个重构区间内从未被改动。

## 5. 「代码检查通过」与「工作流真实跑通」的区别

必须分开说清楚：

- **代码/结构检查通过**：`ci/assert-verify-only.py`、`check_verify_only_workflow.py`、
  `check_workflow.py`（7/7 个 run 块 `bash -n` 通过）、`check_split_workflow.py`、
  `test_split_contract.py`、`test_job_gating.py`、本地脚本测试 10/10。
  这些只证明**工作流在设计上不可能编译**，不证明它跑起来是对的。
- **真实运行成功**：run `38208789499` 确实跑了，`success`，22 秒，12 步全绿，
  并且真的下载了 `38134666544` 的三个产物、真的重新发布了 1130 个逐字节相同的文件。
  这才是本节标题所说的「跑通」。

两者都成立，但结论只能由后者给出。

### 仍未验证 / 无法在此验证的部分

- 步骤摘要（run summary）里的 SHA256 文本**匿名访问读不到**（相关端点返回 404/401），
  因此本记录里的校验和是从**实际下载的产物**里读取并重算的，不是从摘要页面抄的。
- 硬件层面仍未验证（与本次 CI 无关，且**未做任何刷机、未改 U-Boot、未写 flash**）：
  5 GHz 同时中继 + 本地 AP、2.4 GHz monitor 模式、中继时客户端连本地 5 GHz AP、长期稳定性、
  WiFi EEPROM（DTS 中仍标注 `TODO(verify-on-hardware)`）、expand(114m) 布局与 NMBM 映射。
- 可复现性边界：源码与 feed 已精确锁定，但 `make download` 的 tarball 与 `ubuntu-22.04`
  运行器镜像**未锁定**，因此**不主张**逐比特可复现。
- `build-fur602-25.12.yml` 上的 `reuse_run_id` 输入在手动触发场景下尚不可用，
  因为 `workflow_dispatch` 只对存在于**默认分支**的工作流生效，而 `main` 上目前只有 24.10 工作流。
  这正是本次另建独立 verify-only 工作流的原因。

## 6. 能否安全合并

`ci/split-build-verify-25.12` 相对 `master` 的提交（全部已推送，工作区干净）：

```
db98cca  Pin LF for *.py and mark the ci/ scripts executable
76b315a  Add verify-only workflow: reuse existing artifacts, never compile
8b30f7f  Publish per-file SHA256 in the run summary (no auth needed to read it)
7d94272  Pin .gitattributes itself to LF
ae52943  Pin LF for *.md/*.txt so docs are not line-ending rewritten
873744e  Document the build/verify CI refactor and why it was needed
bb369d6  Split build and verify into separate jobs; preserve raw build output
```

判断：**verify-only 路径已经真实跑通，具备合并条件。** 理由：

1. 复用路径真实执行过，且是逐字节复用（1130 文件），不是「看起来像复用」。
2. 编译被**结构性地**排除：工作流里没有 build 作业，且有运行期断言 + 无源码树守卫。
3. 源运行与 24.10 回滚工作流都未被改动。
4. 合并后 `workflow_dispatch` 会首次出现在默认分支上，
   `build-fur602-25.12.yml` 的 `reuse_run_id` 输入才真正可用——这也是这次重构的最终目的。

合并前建议再确认一次：`main` 上的 24.10 工作流仍为 blob `8f4e5acd…`，
且合并后不要删除任何既有工作流。
