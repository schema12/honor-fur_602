# CI 重构说明：build / verify 拆分（25.12.2）

## 为什么要改

第一次 25.12.2 云编译（run `38121105627`）的**编译本身成功了**（步骤 17「Build firmware」，约 3 小时），
但随后**我写的校验步骤**失败了。GitHub 的注解原文（已通过 API 实测取得）是：

```
[failure] only 0 kmod .ipk files published -- CONFIG_ALL_KMODS did not take effect
```

根因：ImmortalWrt 25.12 的 `config USE_APK` 默认值为 `y`，因此软件包是 `.apk` +
`packages.adb` 索引，而我的校验脚本只统计 `kmod-*.ipk`，得到 0，于是硬失败。

后果链是这次重构要解决的核心问题：

1. 步骤 18 失败 →
2. 步骤 21–26（收集 / 上传）**没有** `if: always()`，被默认 `success()` 门禁跳过 →
3. 什么都没上传 →
4. `ubuntu-22.04` 托管运行器磁盘在作业结束时销毁 →
5. **约 3 小时编译成果全部无法恢复**

实测核查（不是推测）：该仓库**全部运行**的 Artifacts 总数为 **0**（含已过期），
GitHub Actions 缓存也是 **0**。连此前两次「成功」的 24.10 运行同样没有任何产物——
因为它们的上传步骤也在 `success()` 门禁之下，一旦某步失败就什么都不会留下。

结论：**校验步骤可能会写错，但它绝不能有能力销毁编译产物。**

## 改成了什么

拆成两个独立作业：

### `build`（昂贵，数小时）
编译完成后**立即**上传原始构建产物，用 `if: always()`，因此即使编译失败或后续步骤出错也照样上传。

产物名 `fur602-25.12.2-raw-<run_id>`，**只依赖 run id**，所以仅凭一个 run id 就能重建这个名字。

包含内容：
- `bin/targets/mediatek/filogic/` 整个目录：factory.bin、sysupgrade.bin、
  `packages/` 完整 kmod 集合 + 软件包索引、manifest、profiles.json、kernel、dtb
- `provenance/`：build-info.md / build-info.txt / env.txt

### `verify`（廉价，数秒）
下载上述产物后做校验、打包、发布。**内部不含任何编译命令**（有自动化检查强制这一点），
因此它不可能重新编译。

## 如何在不重新编译的情况下只重跑校验

两种方式：

1. **`reuse_run_id`**（推荐，可跨运行）
   手动触发 workflow，把 `reuse_run_id` 填成已产出 raw 产物的 run id。
   `build` 作业的 `if` 会使其跳过，`verify` 作业下载那个 run 的产物。
   需要 `permissions: actions: read` + 下载时带 `github-token`，两者都已加上。

2. **GitHub 原生「Re-run failed jobs」**
   因为校验已在独立作业中，重新运行只会重跑 `verify`，不会重跑 `build`。

## 关键设计点

| 点 | 做法 | 原因 |
|---|---|---|
| 产物保留 | 上传步骤 `if: always()` | 校验失败也不丢编译成果 |
| 产物命名 | `fur602-25.12.2-raw-<run_id>` | 仅凭 run id 可重建 |
| 重跑 | 所有上传加 `overwrite: true` | 重跑时 `github.run_id` 不变，否则报「artifact already exists」而丢失产物 |
| 并发 | `group: workflow-ref` | 按分支隔离，A 分支的推送不会取消 B 分支的构建 |
| 触发 | 重构分支**不在** `push.branches` 内 | 推送重构不会启动数小时的编译 |
| 来源 | 从产物内 `env.txt` 恢复环境 | 复用旧产物时，按它**当时**的构建参数判断，而非当次触发参数 |
| kmod | `CONFIG_ALL_KMODS=y` 默认保持开启 | 完整 kmod 是本次构建的目的之一 |
| 可追溯 | 固件内写入 `VERIFICATION.md` | 记录「哪个 run 编译、哪个 run 校验」 |

`verify` 作业会从产物里的 `provenance/env.txt` 恢复源码 SHA、各 feed SHA、
`EXPERIMENTAL`、`BUILD_ALL_KMODS`，所以复用几个月前的产物时，
判断依据是它真实的构建参数，而不是后来那次触发所填的参数。

## 本地已执行的验证

全部为真实执行，不是「看代码觉得没问题」：

| # | 检查 | 结果 |
|---|---|---|
| 1 | YAML 解析 + 全部 24 个 `run:` 块 `bash -n` | 通过 |
| 2 | 结构不变量（作业拓扑、`if: always()`、命名、verify 内无编译、`overwrite`、按 ref 隔离并发） | 通过 |
| 3 | build/verify 契约（多个 run id 的产物名重建、`GITHUB_ENV` heredoc 往返、路径布局） | 通过 |
| 4 | 作业门禁 4 种场景（成功 / 跳过复用 / 普通推送 / 编译失败） | 通过 |
| 5 | 用**真实** verify 作业 shell 代码跑合成 apk 产物 | 0 失败 |
| 6 | 同上，ipk 布局（向后兼容 24.10） | 0 失败 |
| 7 | 负向测试：健康树被接受，8 种具体破坏各自被正确拒绝 | 9/9 通过 |
| 8 | `build-fur602.yml`（24.10 回退路径）blob 未变 | 已核实 |

负向测试覆盖的破坏类型：缺 factory.bin、缺 sysupgrade.bin、sysupgrade.bin 不是 tar、
tar 内目录名不对、kmod 数量不足、缺必需 kmod、缺软件包索引、缺 `packages/` 目录。
**一个不会失败的校验等于没有校验**，所以这些必须能真的失败。

## 尚未验证（诚实说明）

- **本重构从未在 GitHub Actions 上真实运行过。** apk/ipk 处理是在合成目录上验证的，不是真实构建产物。
- 真实产物需等 `build` 作业产出后才能确认其命名、大小与 SHA256。

## 与 24.10 的关系

`build-fur602.yml`（24.10）**完全未改动**，仍是回退路径。
重构分支在合并前不会覆盖它，也不会合并任何未经验证的改动。
