# HONOR FUR-602/603 — ImmortalWrt 25.12.2 migration

This directory holds the **ImmortalWrt 25.12.2 (kernel 6.12)** build of the
HONOR FUR-602 / FUR-603 device support. It is additive: the existing 24.10
build (`build-fur602.yml` and its files at the repository root) is untouched and
remains the rollback path.

## What is here

| File | Purpose |
|------|---------|
| `locks/immortalwrt-25.12.2.lock` | Pins the main source to the real v25.12.2 release commit, with the evidence chain. |
| `locks/feeds-25.12.2.lock` | Pins all 5 package feeds to exact commits, plus the reproducibility boundary. |
| `mt7981b-honor-fur-602-2512.dts` | Device tree for kernel 6.12 (`mt7981b.dtsi` + `mt65xx.h` + `memory@40000000`). |
| `filogic.mk.25.12.append` | Device registration block for `target/linux/mediatek/image/filogic.mk`. |
| `filogic.config.25.12.append` | Kernel config fragment (intentionally empty — see inside). |
| `02_network.25.12.diff` | Illustrative diff for the LAN/WAN mapping. `diy-part2-25.12.sh` applies this programmatically. |
| `.config.25.12` | Build seed: target, device, and `CONFIG_ALL_KMODS=y`. |
| `diy-part2-25.12.sh` | Injection script. Strict: aborts if kernel ≠ 6.12, if NMBM is gone, or if the upgrade path changed. |
| `.github/workflows/build-fur602-25.12.yml` | The cloud build. Enforces the locks and verifies the artifacts. |
| `MIGRATION-REPORT.md` | Full report: what changed, what is verified, what is not. |

## Running it

1. Copy these files into the repository root, preserving paths (so
   `locks/`, `.github/workflows/`, and the dotfiles land where they belong).
2. Push to `main`, or run **Build HONOR FUR-602/603 (ImmortalWrt 25.12.2)**
   from the Actions tab.

The job refuses to build if the checked-out commit is not
`4fc16f2985a358bd43bb522e43f05395fcbd6ed5` or if any feed drifts off its pinned
SHA. Passing `source_sha` on a manual run overrides the pin, but the build is
then labelled EXPERIMENTAL and **fails at the end** so an unverified image can
never be mistaken for a release-baseline one.

## Artifacts

Three separate uploads, all named with the run id and the source SHA:

- `fur602-25.12.2-firmware-<run>-<sha>` — `factory.bin` (first flash, via U-Boot
  web recovery), `sysupgrade.bin` (later upgrades), manifest, `profiles.json`,
  `build-info.txt`, `SHA256SUMS.txt`.
- `fur602-25.12.2-kmods-<run>-<sha>` — the complete ABI-matched kmod `.ipk` set
  plus `Packages` index, for `opkg install` on the device.
- `fur602-25.12.2-rescue-<run>-<sha>` — initramfs rescue image, if the build
  produced one.

Bootloader images (`bl2`, `fip`, `preloader`, `bl31`) are explicitly rejected
from the firmware artifact, so an image for a different MediaTek SoC can never
be flashed by mistake.

## Flashing

Unchanged from the 24.10 procedure, and the preconditions are the same:

1. The board must already run the `hanwckf/bl-mt798x` `mt7981_honor_fur-602`
   U-Boot. The stock HONOR U-Boot is signature-locked and cannot boot this.
2. The mtd layout must be **`expand(114m)`**. `factory.bin` is sized for the
   116736k UBI volume in that layout.
3. Hold reset while powering on to reach the U-Boot web recovery page
   (default `192.168.1.1`), then upload `factory.bin`. Use `sysupgrade.bin`
   thereafter.

This repository does not flash anything and does not change wireless
configuration.

## Wireless

Native open-source `mac80211` + `mt76`. `DEVICE_PACKAGES` is
`kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware`, which is the canonical
MT7981 triple used by every comparable device in the 25.12.2 tree. No
out-of-tree or closed-source driver is used.

Nothing in this directory asserts that STA-relay + AP concurrency, 2.4 GHz
monitor mode, or long-run stability are fixed — those need real hardware
testing. See the "must still be verified on hardware" section of
`MIGRATION-REPORT.md`.
