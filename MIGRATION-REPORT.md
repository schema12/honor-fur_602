# FUR-602 → ImmortalWrt 25.12.2 migration report

Status: **migration authored and statically reasoned; NO build has been executed.**
Read §11 before treating anything here as proven.

---

## 0. Environment limitation (read this first)

The machine this migration was produced on had a **completely non-functional
shell**. Every `pwsh` invocation — including trivial builtins — returned exit
code `3221225794` (`0xC0000142`, `STATUS_DLL_INIT_FAILED`), with no stdout and
no stderr. A second agent independently reproduced this on all six of its probe
commands. Consequences:

- No `git`, no `python`, no `make`, no `bash` could run locally.
- I could **not** clone `schema12/honor-fur_602`, could not read its Git
  history locally, and could not `git commit`/`git push` anything.
- I could **not** execute the static checks in §11 locally.
- I could **not** trigger or observe a GitHub Actions run.

Everything below therefore comes from **reading upstream sources over HTTPS**
and from the repository contents fetched through the GitHub API. Where that
leaves a gap, §11 says so explicitly rather than implying verification.

Also note: the repository referenced in the task is
`https://github.com/schema12/honor-fur_602` (hyphen), not
`.../honor_fur_602`. The local workspace contained only an earlier, much smaller
draft; the real repository has evolved considerably. I reconstructed the current
files via the GitHub API into `repo-current/` and based this migration on those.

---

## 1. What is the real source baseline for ImmortalWrt 25.12.2?

**Commit `4fc16f2985a358bd43bb522e43f05395fcbd6ed5`**, reachable as git tag
`v25.12.2` in `immortalwrt/immortalwrt`.

Evidence read from upstream:

| Fact | Value |
|------|-------|
| Tag | `v25.12.2`, **annotated** (type `tag`, not `commit`) |
| Tag object SHA | `bfc8bae082b913eb60e3247bb3e3a9cb3a6fde55` |
| Tag message | `ImmortalWrt v25.12.2 Release` |
| Tagger | Tianling Shen `<cnsztl@immortalwrt.org>`, 2026-09-06T14:02:15Z |
| Signature | **PGP-signed, verified valid** |
| → points at commit | `4fc16f2985a358bd43bb522e43f05395fcbd6ed5` |
| Commit subject | `ImmortalWrt v25.12.2: adjust config defaults` |

Two facts made this non-obvious and are worth stating plainly:

1. **`GET /repos/immortalwrt/immortalwrt/releases` returns `[]`.** ImmortalWrt
   publishes no GitHub Releases. Judging existence of the release from that page
   would have been wrong.
2. **The `openwrt-25.12` branch head is NOT 25.12.2.** It is
   `ce35a9e4ef1b87fbbc2146036ce6693e4242861a` (2026-10-09, *"Merge Official
   Source"*) — **ahead** of the release tag. Building the branch head would
   yield a moving `25.12-SNAPSHOT`, not 25.12.2. This is exactly the drift the
   lock file exists to prevent.

Kernel: `KERNEL_PATCHVER:=6.12`, point release **6.12.103**
(`target/linux/generic/kernel-6.12` → `LINUX_VERSION-6.12 = .103`,
`LINUX_KERNEL_HASH-6.12.103 = f143aaad…c3176`).

## 2. How does that SHA correspond to the official 25.12.2 release baseline?

The commit *is* the release-engineering commit, and it performs precisely the
edits that define the release. Diffed against its parent `0c4cd0f9920a`:

- `include/version.mk` — `25.12-SNAPSHOT` → `25.12.2`;
  version code → `r38135-0c4cd0f9920a`;
  `VERSION_REPO` → `https://downloads.immortalwrt.org/releases/25.12.2`
- `feeds.conf.default` — all 5 feeds rewritten from branch refs
  (`;openwrt-25.12`) to **exact commit pins** (`^<sha>`)
- `package/base-files/image-config.in` — release repo default
- `version`, `version.date` — added

So the build reports `25.12.2` / `r38135-0c4cd0f9920a`, and the feed pins that
upstream ships for the release are committed *inside* this very commit.

**Not verified:** `downloads.immortalwrt.org` was unreachable from this machine,
so `version.buildinfo`, `feeds.buildinfo` and `config.buildinfo` from the
official download directory could not be read. The source-tree evidence is
strictly stronger for pinning *source and feeds*, but it does not independently
confirm the official **binary** artifacts. See §4.

## 3. Are the main source and all feeds locked?

**Yes — both, with real upstream SHAs, no placeholders.**

`locks/immortalwrt-25.12.2.lock`:

```
REPO_URL="https://github.com/immortalwrt/immortalwrt"
REPO_REF="refs/tags/v25.12.2"
REPO_SHA="4fc16f2985a358bd43bb522e43f05395fcbd6ed5"
KERNEL_PATCHVER="6.12"   KERNEL_VERSION="6.12.103"
VERSION_CODE="r38135-0c4cd0f9920a"
```

`locks/feeds-25.12.2.lock` — taken verbatim from `feeds.conf.default` at that
commit:

| feed | repo | pinned SHA |
|------|------|-----------|
| packages | immortalwrt/packages | `84bd86384928955b568988ca0e09e2c78c75173d` |
| luci | immortalwrt/luci | `d6167ea0645cbd1327708d85f94824f42d0eb872` |
| routing | openwrt/routing | `e49d76035aafb85ddc993b59271d8c7ba56b5362` |
| telephony | openwrt/telephony | `2618106d5846a4a542fdf5809f0d3ed228ce439b` |
| video | openwrt/video | `094bf58da6682f895255a35a84349a79dab4bf95` |

Enforcement in `build-fur602-25.12.yml`:

1. Lock SHA must match `^[0-9a-f]{40}$`, else abort.
2. Source is fetched **by SHA** (falling back to the tag), then
   `git rev-parse HEAD` must equal `REPO_SHA` **exactly** — else abort.
3. `feeds.conf.default` must still pin each feed to our SHA — else abort.
4. After `scripts/feeds update -a`, each `feeds/<name>` is `git rev-parse`d and
   compared to its lock — else abort.

There is no code path that falls back to a floating branch. A manual
`source_sha` override is allowed but forces `EXPERIMENTAL=true` and the job
**fails at the end** so an unverified image cannot be mistaken for a
release-baseline one.

## 4. What still cannot be precisely reconstructed?

Be precise about the boundaries:

1. **Official binary build metadata not read.**
   `downloads.immortalwrt.org/releases/25.12.2/.../version.buildinfo`,
   `feeds.buildinfo`, `config.buildinfo` were all unreachable (fetch failure, no
   shell to curl). The lock therefore rests on the signed tag + release commit,
   not on the published buildinfo. For *source and feed* pinning this is
   equivalent-or-better (the pins are in the commit); for *binary* provenance it
   is an unclosed gap.
2. **`make download` tarballs are not bit-pinned by us.** Individual package
   Makefiles carry `PKG_HASH`, so content is verified, but some packages track
   moving upstream tags and can legitimately fail later if a host deletes an old
   tarball. Inherent to OpenWrt; not fixable from this repository.
3. **Runner image is not pinned.** `ubuntu-22.04` contents drift.
4. **`x-device` `DEVICE_PACKAGES` for `xiaomi_mi-router-ax3000t`** could not be
   read (the 150 KB `filogic.mk` truncated before the alphabetically-later
   xiaomi section). Irrelevant to this device, but it is an unread line.

**Conclusion:** source + feeds are exactly reproducible. The full binary build
is reproducible *up to* upstream tarball availability and runner drift. I do
**not** claim bit-for-bit reproducible firmware.

## 5. What was added / changed?

All new files live under `honor-fur602-25.12/` and are drop-in for the
repository root. **No existing file is modified.**

| File | New? | Notes |
|------|------|-------|
| `locks/immortalwrt-25.12.2.lock` | new | real SHAs + evidence chain |
| `locks/feeds-25.12.2.lock` | new | 5 feed pins + reproducibility boundary |
| `mt7981b-honor-fur-602-2512.dts` | new | kernel-6.12 DTS (see below) |
| `filogic.mk.25.12.append` | new | device registration |
| `filogic.config.25.12.append` | new | kernel fragment (intentionally empty) |
| `02_network.25.12.diff` | new | illustrative diff |
| `.config.25.12` | new | build seed incl. `CONFIG_ALL_KMODS=y` |
| `diy-part2-25.12.sh` | new | strict injection script |
| `.github/workflows/build-fur602-25.12.yml` | new | the 25.12 build |
| `README-25.12.md`, `MIGRATION-REPORT.md` | new | docs |

### Device tree: exactly three changes, each forced by a verified upstream change

The 24.10 DTS design was preserved wherever it was already correct. Only these
three edits were made, and each is required or the DTB will not build:

1. **`#include "mt7981.dtsi"` → `#include "mt7981b.dtsi"`.**
   Kernel 6.12 ships `files-6.12/arch/arm64/boot/dts/mediatek/mt7981b.dtsi`;
   `mt7981.dtsi` no longer exists in that path. Confirmed: `mt7981b.dtsi`
   resolves (HTTP 200) while `mt7981.dtsi` at the same path returns 404. Every
   MT7981 board in the 25.12 tree (h3c-magic-nx30-pro, nokia-ea0326gmp,
   jcg-q30-pro, cmcc-rax3000m, mt7981-rfb) includes `mt7981b.dtsi`.
2. **Added `#include <dt-bindings/pinctrl/mt65xx.h>`.**
   `MTK_DRIVE_8mA` / `MTK_PUPD_SET_R1R0_11` are used by the SPI pinconf. The
   5.4-era `mt7981.dtsi` pulled this in transitively; mainline `mt7981b.dtsi`
   does not, so 25.12 device trees that use these macros include it themselves
   (cf. `mt7981b-h3c-magic-nx30-pro.dts`, which includes it).
3. **`memory { … }` → `memory@40000000 { device_type = "memory"; … }`.**
   Matches every MT7981 DTS in 25.12 and avoids a dtc unit-address warning.

**Deliberately NOT changed** (all verified still correct on 6.12):
partition layout, NMBM properties, SPI calibration data, `factory` offsets
(`0x24`/`0x2a`), DSA port mapping, GPIOs, LED bindings, `mediatek,mtd-eeprom`
for WiFi, `&mdio_bus`/`&pio` usage.

### Deliberately NOT adopting the new 25.12 UBI layout

25.12 device trees such as `mt7981b-h3c-magic-nx30-pro.dts` and
`mt7981b-jcg-q30-pro.dts` use:

```dts
chosen { bootargs-append = " root=/dev/fit0 rootwait"; rootdisk = <&ubi_rootdisk>; };
partition@580000 { compatible = "linux,ubi"; volumes { ubi_rootdisk: ubi-volume-fit { volname = "fit"; }; }; };
```

**I did not adopt this, on purpose.** It requires the bootloader to expose a
`fitblk` device (`/dev/fit0`) and to look for a UBI volume named `fit`. The
`bl-mt798x` U-Boot for this board instead looks for a UBI volume named
`kernel`. Adopting the new layout would produce an image that this board's
U-Boot cannot boot.

Corroborating evidence that the classic layout is still fully supported in
25.12: `platform_do_upgrade()`'s final arm is still `*) nand_do_upgrade "$1"`,
and `nand.sh` still defaults `CI_KERNPART=kernel` / `CI_ROOTPART=rootfs`. So an
unlisted board keeps the classic `kernel`/`rootfs` UBI volumes. The DTS also
still has **no MTD partition named `kernel`**, which is what forces the U-Boot
down its `boot_from_ubi()` path.

## 6. Is the 24.10 rollback workflow preserved?

**Yes — untouched.** `build-fur602.yml` and its inputs (`.config`,
`diy-part2.sh`, `filogic.mk.append`, `filogic.config.append`,
`mt7981b-honor-fur-602.dts`) are not modified by this migration. The new
workflow deliberately shares **no filenames** with it, so both can run
independently:

| 24.10 (rollback) | 25.12.2 (new) |
|---|---|
| `.config` | `.config.25.12` |
| `diy-part2.sh` | `diy-part2-25.12.sh` |
| `filogic.mk.append` | `filogic.mk.25.12.append` |
| `filogic.config.append` | `filogic.config.25.12.append` |
| `mt7981b-honor-fur-602.dts` | `mt7981b-honor-fur-602-2512.dts` |
| `build-fur602.yml` | `build-fur602-25.12.yml` |

⚠️ One caveat: if someone were to apply *both* `diy-part2.sh` and
`diy-part2-25.12.sh` to the same tree, both would append a `Device/honor_fur-602`
block to `filogic.mk` — a duplicate device definition. Each script is
individually idempotent and each workflow runs exactly one of them, so this
cannot happen in CI; it only matters if someone runs both by hand.

## 7. Did the full kmod build actually succeed?

**Unknown — no build has been run.** What *is* in place:

- `.config.25.12` sets `CONFIG_ALL_KMODS=y`.
- The workflow asserts `^CONFIG_ALL_KMODS=y` is present in the post-`defconfig`
  `.config`, and fails the job if it is not.
- The workflow then proves the *effect* rather than trusting the setting: it
  requires `bin/targets/mediatek/filogic/packages/` to exist, requires the
  `kmod-*.ipk` count to be **≥ 100**, requires a `Packages` index, and reports
  presence/absence for `kmod-sched-core`, `kmod-sched`, `kmod-sched-cake`,
  `kmod-ifb`, `kmod-mac80211`, `kmod-cfg80211`, `kmod-mt7915e`, `kmod-nft-core`,
  `kmod-pppoe`. The kmod artifact collection step re-asserts the ≥ 100 count.
- `CONFIG_ALL_KMODS` is a **tristate** knob: it flips kmods from default `n` to
  `m` (built + published as `.ipk`), and does **not** install them into the
  rootfs. Only `DEFAULT_PACKAGES` + `DEVICE_PACKAGES` are installed. It is
  deliberately **not** `CONFIG_ALL=y`.

So the mechanism is wired and will fail loudly if the full set is not produced —
but it has never executed.

## 8. Did the GitHub Actions cloud build actually succeed?

**No — it was never run.** I cannot push to the user's repository and had no
shell to trigger anything. Anyone reading this should treat the workflow as
**unexecuted**. §11 separates what was reasoned from what was proven.

## 9. What artifacts are produced, and what is each for?

Three uploads, each named `…-<run_id>-<short_sha>` so an older download cannot be
mistaken for a newer one:

**1. `fur602-25.12.2-firmware-<run>-<sha>`**
| file | purpose |
|---|---|
| `*honor_fur-602*factory*.bin` | first flash via U-Boot web recovery (UBI image, 116736k) |
| `*honor_fur-602*sysupgrade*.bin` | later upgrades (sysupgrade tar) |
| `*.manifest` | installed package list |
| `profiles.json` | device metadata |
| `build-info.txt` | full provenance block |
| `SHA256SUMS.txt` | sizes/checksums of everything above |

**2. `fur602-25.12.2-kmods-<run>-<sha>`** — complete `kmod-*.ipk` set +
`Packages*` index + `SHA256SUMS.txt`, for `opkg install` on the device.

**3. `fur602-25.12.2-rescue-<run>-<sha>`** — `initramfs-kernel.bin` /
device initramfs, if the build produced one. Skipped without error otherwise.

**BL2/FIP hygiene:** the firmware collector matches images **only** on
`*honor_fur-602*` plus `factory|sysupgrade|initramfs`, never a bare `*.bin`
glob, and then explicitly greps the collected set for
`bl2|preloader|bl31|fip` and **aborts** if any appears. So an image built for a
different MediaTek SoC cannot be shipped in the FUR-602 firmware artifact.

**Security:** no root password is hardcoded anywhere; no package-signature
verification is disabled; no credentials are written to logs or artifacts.

## 10. Do all artifacts correspond to this run and the locked source?

Intended yes, and enforced by construction:

- Artifact names embed `github.run_id` and the short source SHA.
- `build-info.txt` records run id, run number, run attempt, the config-repo
  commit (`github.sha`), the ImmortalWrt commit, the ref, the resolved feed
  SHAs, kernel version, version code, `build_all_kmods`, and a UTC timestamp.
- Every artifact carries a `SHA256SUMS.txt` computed at collection time.
- The workflow fails on: SHA mismatch, feed drift, missing DTS, missing
  `factory`/`sysupgrade`, unreadable sysupgrade tar, missing
  `sysupgrade-honor_fur_602/` directory, kmod count < 100, missing `Packages`,
  bootloader images in the firmware set, or an EXPERIMENTAL override.

Freshness is therefore decided by run id + commit + checksums, not by file
mtime.

## 11. What is statically checked vs actually build-verified?

### Verified by reading upstream at the locked SHA (high confidence)

- The `v25.12.2` annotated PGP-signed tag and its target commit.
- The branch head being *ahead* of the release tag.
- `KERNEL_PATCHVER:=6.12`; kernel 6.12.103 and its source hash.
- The 5 feed SHAs, as committed by the release commit itself.
- `target/linux/mediatek/config-6.12` does **not** exist;
  `target/linux/mediatek/filogic/config-6.12` **does** (so the fragment location
  is the highest-priority one).
- `mt7981b.dtsi` exists in `files-6.12/…`; `mt7981.dtsi` does not.
- **NMBM is still supported**: `target/linux/generic/files/drivers/mtd/nand/mtk_bmt.c`
  handles `mediatek,nmbm` → `mtk_bmt_nmbm_ops`, and `filogic/config-6.12` has
  `CONFIG_MTD_NAND_MTK_BMT=y`. The `-nmbm` **DTS variant** disappearing is a
  layout consolidation, **not** a driver removal — this was the single biggest
  migration risk and it is cleared.
- `Device/Default` still builds a FIT kernel
  (`fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb`).
- `platform.sh` final arm is still `*) nand_do_upgrade "$1"`; no `honor` special
  case. `nand.sh` still defaults `CI_KERNPART=kernel` / `CI_ROOTPART=rootfs`.
- `02_network`'s default arm is `"lan1 lan2 lan3 lan4" wan`, and `honor` appears
  nowhere — so the board genuinely needs its own 3-port arm.
- `kmod-mt7915e` and `kmod-mt7981-firmware` are defined in the main tree
  `package/kernel/mt76/Makefile`; `mt7981-wo-firmware` in
  `package/firmware/linux-firmware/mediatek.mk`. **They are not in the packages
  feed** — the pinned feed has no `kernel/mt76` and no `firmware/` directory.
  This matters: anyone looking for them in the feed would conclude wrongly that
  they vanished.

### Reasoned but NOT executed (medium confidence — logic reviewed by hand only)

- YAML validity and shell syntax of the workflow and script. **No parser or
  linter was run**, because there was no shell. This is the largest untested
  surface.
- The `02_network` Python insertion (finds exactly one `\t*)` arm, inserts
  before it). Logic reviewed by hand; never executed.
- The `git fetch --depth 1 origin <sha>` path (with tag fallback).
- Whether `make defconfig` keeps `CONFIG_ALL_KMODS=y` (expected: yes, it is a
  normal build knob).
- Exact artifact filenames produced by OpenWrt for this device. The globs are
  written against the `<vendor>_<model>-…-factory/sysupgrade.bin` convention
  used by the existing 24.10 workflow, but the literal names were not observed.

### Not verified at all

- **No firmware was built. No GitHub Actions run happened. No artifact exists.**
- No DTB was compiled, so `mt7981b.dtsi` compatibility is inferred from sibling
  device trees, not proven by dtc.
- No real-hardware test of any kind.

**Do not read "statically checked" as "build-verified".** The checks in §3/§7
are wired to fail loudly; they have not fired yet.

## 12. Wireless: what still requires real-hardware validation?

The build uses native `mac80211` + `mt76` with
`DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware` — the
canonical MT7981 triple, matching `cetron_ct3003`, `h3c_magic-nx30-pro`,
`cmcc_rax3000m`, `abt_asr3000`, `asus_rt-ax52` in the same tree. No closed-source
or out-of-tree driver is introduced, and nothing was removed to make the build
pass.

**Nothing here claims the following scenarios work.** They are the stated
research goals and each needs a real FUR-602:

1. **5 GHz simultaneously as STA relay and local AP.** Requires the mt76
   firmware and channel/DFS handling to support concurrent STA+AP on one PHY
   under 6.12. Untested. May require a specific channel, may hit DFS, and
   may not be supported by this firmware revision at all.
2. **2.4 GHz monitor mode.** `mt76` monitor support exists in principle; whether
   the MT7981 firmware build in this release allows monitor + concurrent
   operation is unverified. Monitor mode also needs the right kmods installed
   from the kmod artifact (see §7).
3. **Client connected to the local 5 GHz AP while the STA relay is up.**
   Depends entirely on (1).
4. **Long-run connection stability.** Cannot be assessed without days of uptime
   on real hardware; no software check substitutes for this.

Additional hardware-only unknowns carried over from the 24.10 port and still
open:

- WiFi EEPROM presence at `factory@0x0` (the DTS carries a
  `TODO(verify-on-hardware)` for this).
- Whether the `expand(114m)` layout and the NMBM mapping on the actual unit
  match the DTS partition table.
- Actual throughput/offload behaviour with `mt7981-wo-firmware`.

## Recommended next step

Run the workflow once with `build_all_kmods: false` to shake out YAML/shell
errors and confirm the device registers, then a full run. Report back the first
substantive error from the log and I will fix it. Until a green run exists, §11
"reasoned but NOT executed" is the honest status of this migration.
