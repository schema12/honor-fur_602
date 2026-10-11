#!/bin/bash
#
# diy-part2-25.12.sh -- inject HONOR FUR-602/603 device support into an
# ImmortalWrt 25.12.2 source tree (kernel 6.12).
#
# Run from the root of the source tree (working-directory = openwrt), with the
# device files present one level up, i.e.:
#
#   <workspace>/openwrt/                              <- source tree (this script's CWD)
#   <workspace>/mt7981b-honor-fur-602-2512.dts        <- device tree
#   <workspace>/filogic.mk.25.12.append               <- device registration
#   <workspace>/filogic.config.25.12.append           <- kernel config fragment
#
# The script is idempotent: re-running it will not duplicate anything.
# Every step fails LOUDLY instead of silently producing a firmware that does
# not actually contain the device, or that would brick the board by using the
# wrong flash layout.
#
# It is deliberately strict about the 25.12 baseline: this device tree depends
# on mt7981b.dtsi (renamed from mt7981.dtsi), on NMBM still being supported, and
# on the generic nand_do_upgrade path still being the fallback. If any of those
# assumptions stop holding, we abort rather than guess.

set -eu

DTS_SRC="../mt7981b-honor-fur-602-2512.dts"
DTS_NAME="mt7981b-honor-fur-602-2512"
DTS_DST="target/linux/mediatek/dts/${DTS_NAME}.dts"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"
MEDIATEK_IMG_MK="target/linux/mediatek/image/Makefile"
FILOGIC_CFG="target/linux/mediatek/filogic/config-6.12"
NETWORK_FILE="target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
PLATFORM_SH="target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
NAND_SH="package/base-files/files/lib/upgrade/nand.sh"
BMT_C="target/linux/generic/files/drivers/mtd/nand/mtk_bmt.c"

fail() {
	echo "[diy] ERROR: $*" >&2
	exit 1
}
note() {
	echo "[diy] $*"
}

# ---------------------------------------------------------------------------
# 0. Sanity-check the source tree layout BEFORE touching anything
# ---------------------------------------------------------------------------
[ -f "$FILOGIC_MK" ] || fail "$FILOGIC_MK not found -- wrong source tree or branch?"
[ -f "$MEDIATEK_IMG_MK" ] || fail "$MEDIATEK_IMG_MK not found -- wrong source tree?"
[ -d "target/linux/mediatek/dts" ] || fail "target/linux/mediatek/dts not found"
[ -f "$FILOGIC_CFG" ] || fail "$FILOGIC_CFG not found -- filogic shared config changed?"
[ -f "$NETWORK_FILE" ] || fail "$NETWORK_FILE not found"
[ -f "$PLATFORM_SH" ] || fail "$PLATFORM_SH not found"

# 0a. Kernel must be 6.12. Everything in this port (mt7981b.dtsi, the
#     config-6.12 fragment path, the mtk_bmt NMBM driver) is verified for 6.12.
KV=$(sed -n 's/^KERNEL_PATCHVER:=//p' target/linux/mediatek/Makefile)
note "KERNEL_PATCHVER=$KV"
[ "$KV" = "6.12" ] || fail "expected kernel 6.12 for ImmortalWrt 25.12.2, got '$KV'.
This repository's 25.12 port is pinned to the 6.12 design. Refusing to build.
If upstream moved the target to a newer kernel, re-verify:
  - target/linux/mediatek/files-<ver>/.../mt7981b.dtsi exists
  - target/linux/mediatek/filogic/config-<ver> exists (and no target-level config-<ver>)
  - target/linux/generic/files/drivers/mtd/nand/mtk_bmt.c still handles mediatek,nmbm"

# 0b. mediatek has no per-target config, so filogic/config-6.12 is the
#     highest-priority kernel config kconfig.pl merges for this target.
#     That is why our kernel fragment belongs there and nowhere else.
if [ -f "target/linux/mediatek/config-6.12" ]; then
	fail "target/linux/mediatek/config-6.12 now exists; the config precedence changed -- re-check where the kernel fragment should go"
fi

# 0c. The SoC include our DTS uses is "mt7981b.dtsi", which upstream Linux
#     renamed from "mt7981.dtsi" when the SoC gained its "b" suffix. That file
#     is NOT part of the OpenWrt tree -- it is unpacked from the kernel tarball
#     at build time (arch/arm64/boot/dts/mediatek/mt7981b.dtsi). So we cannot
#     assert on the file itself before the kernel is downloaded.
#
#     Instead we assert the CONVENTION, using the in-tree sibling device trees
#     as the authority: if the other MT7981 boards in this tree include
#     "mt7981b.dtsi", then our include is correct for this kernel generation.
#     We also assert that nothing still uses the old 5.4-era "mt7981.dtsi",
#     because that spelling would not resolve on 6.12.
SIBLING_DTS="target/linux/mediatek/dts"
grep -rlq '#include "mt7981b.dtsi"' "$SIBLING_DTS" || fail \
"no in-tree DTS includes \"mt7981b.dtsi\" -- the MT7981 SoC include convention changed"
if grep -rlq '#include "mt7981\.dtsi"' "$SIBLING_DTS"; then
	fail "an in-tree DTS still includes the old \"mt7981.dtsi\"; \
this tree is not the 6.12 generation this port was verified against"
fi
N_SIBLINGS=$(grep -rl '#include "mt7981b.dtsi"' "$SIBLING_DTS" | wc -l)
note "SoC include convention: $N_SIBLINGS in-tree DTS use \"mt7981b.dtsi\", none use \"mt7981.dtsi\""

# The mt65xx.h pinctrl binding header is likewise provided by the kernel tree,
# not by OpenWrt. Assert that in-tree 6.12 device trees include it explicitly,
# which is what justifies our own explicit include.
grep -rlq '<dt-bindings/pinctrl/mt65xx.h>' "$SIBLING_DTS" || fail \
"no in-tree DTS includes <dt-bindings/pinctrl/mt65xx.h>; \
cannot confirm the pinctrl binding header is available"

# 0d. Device/Default must still synthesise the FIT kernel we rely on.
#     Doubled dollars on purpose: in a Makefile $$(x) is a literal $(x).
grep -q 'fit lzma \$\$(KDIR)/image-\$\$(firstword \$\$(DEVICE_DTS)).dtb' "$MEDIATEK_IMG_MK" \
	|| fail "Device/Default in $MEDIATEK_IMG_MK no longer builds a FIT kernel;
this device definition assumes it does"

# 0e. NMBM must still be supported. The FUR-602 U-Boot maps the whole chip
#     through its own bad-block table; without NMBM in the kernel the
#     partitions below would be interpreted with the wrong block mapping and
#     the image would not boot.
[ -f "$BMT_C" ] || fail "$BMT_C not found -- MediaTek BMT/NMBM driver disappeared"
grep -q 'mediatek,nmbm' "$BMT_C" || fail \
"$BMT_C no longer handles the \"mediatek,nmbm\" property -- NMBM support was removed.
This device REQUIRES NMBM; do not drop it from the DTS. Investigate upstream first."
grep -q '^CONFIG_MTD_NAND_MTK_BMT=y' "$FILOGIC_CFG" || fail \
"$FILOGIC_CFG does not enable CONFIG_MTD_NAND_MTK_BMT=y -- NMBM would not be built in"
note "NMBM: mtk_bmt.c handles mediatek,nmbm and CONFIG_MTD_NAND_MTK_BMT=y is set"

# 0f. The upgrade path must still be the generic nand_do_upgrade fallback.
#     Our sysupgrade.bin is a tar that the bl-mt798x U-Boot expects in the UBI
#     volumes "kernel"/"rootfs"; nand_do_platform_check() detects it via
#     sysupgrade-<board>/CONTROL and then untars it.
grep -q 'nand_do_upgrade "\$1"' "$PLATFORM_SH" || fail \
"$PLATFORM_SH no longer has a nand_do_upgrade branch"
# The very last case arm must still be the generic fallback. $'...' gives us a
# real tab without embedding one literally in this file.
grep -q $'^\t\\*)$' "$PLATFORM_SH" \
	|| fail "$PLATFORM_SH no longer has a generic *) fallback branch"
if grep -q 'honor,fur-602' "$PLATFORM_SH"; then
	fail "$PLATFORM_SH now special-cases honor,fur-602 -- re-verify the upgrade path"
fi
note "platform.sh: generic nand_do_upgrade fallback present, no FUR-602 override"

# 0g. nand.sh default UBI volume names must still be kernel/rootfs, because the
#     U-Boot looks for exactly those.
grep -q 'CI_KERNPART="\${CI_KERNPART:-kernel}"' "$NAND_SH" || fail \
"$NAND_SH CI_KERNPART default is no longer 'kernel' -- U-Boot volume names would mismatch"
grep -q 'CI_ROOTPART="\${CI_ROOTPART:-rootfs}"' "$NAND_SH" || fail \
"$NAND_SH CI_ROOTPART default is no longer 'rootfs' -- U-Boot volume names would mismatch"
note "nand.sh: CI_KERNPART=kernel / CI_ROOTPART=rootfs defaults intact"

# ---------------------------------------------------------------------------
# 1. Install the device tree
# ---------------------------------------------------------------------------
if [ -f "$DTS_SRC" ]; then
	cp -f "$DTS_SRC" "$DTS_DST"
	note "installed $DTS_DST"
else
	[ -f "$DTS_DST" ] || fail "neither $DTS_SRC nor $DTS_DST exists"
	note "$DTS_SRC not found, keeping existing $DTS_DST"
fi

# ---------------------------------------------------------------------------
# 2. Register the device in the image build (filogic.mk)
# ---------------------------------------------------------------------------
if grep -q 'define Device/honor_fur-602' "$FILOGIC_MK"; then
	note "$FILOGIC_MK already has honor_fur-602, skip"
else
	cat >> "$FILOGIC_MK" <<'EOF'

define Device/honor_fur-602
  DEVICE_VENDOR := HONOR
  DEVICE_MODEL := FUR-602
  DEVICE_ALT0_VENDOR := HONOR
  DEVICE_ALT0_MODEL := FUR-603
  DEVICE_DTS := mt7981b-honor-fur-602-2512
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
EOF
	note "appended honor_fur-602 to $FILOGIC_MK"
fi

# ---------------------------------------------------------------------------
# 3. Network interface mapping: 3 LAN + 1 WAN
# ---------------------------------------------------------------------------
# The 25.12 default arm is `ucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" wan`,
# which would reference a lan4 this board does not have. Join the existing
# 3-LAN group instead. MACs come from the DTS nvmem cells, so no board.d MAC
# change is needed.
if grep -q 'honor,fur-602' "$NETWORK_FILE"; then
	note "$NETWORK_FILE already has honor,fur-602, skip"
else
	# Pick whichever python is actually usable. CI (ubuntu-22.04) has
	# python3; a Windows dev box may only expose `python`. Prefer one that
	# really runs, not just one that exists on PATH -- on Windows, python3
	# is often a Microsoft Store stub that fails at runtime.
	PY=""
	for cand in python3 python; do
		if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'pass' >/dev/null 2>&1; then
			PY="$cand"
			break
		fi
	done
	[ -n "$PY" ] || fail "no working python interpreter found (tried python3, python)"
	note "using $PY for the 02_network patch"

	"$PY" - "$NETWORK_FILE" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as fh:
    lines = fh.readlines()

# Insert a dedicated case arm immediately before the final default arm of
# mediatek_setup_interfaces(). A dedicated arm is more robust than joining an
# existing vendor group, because group membership changes between releases.
# The device string is unique, so ordering relative to other arms is safe.
default_idxs = [i for i, ln in enumerate(lines) if ln.rstrip('\n') == '\t*)']
if len(default_idxs) != 1:
    raise SystemExit(
        '02_network: expected exactly one "\\t*)" default arm in '
        'mediatek_setup_interfaces, found %d -- patch it manually'
        % len(default_idxs))

idx = default_idxs[0]
arm = [
    '\thonor,fur-602)\n',
    '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan\n',
    '\t\t;;\n',
]
lines[idx:idx] = arm

with open(path, 'w', encoding='utf-8') as fh:
    fh.writelines(lines)
print('[diy] inserted a dedicated honor,fur-602 arm into 02_network')
PYEOF
fi

# Verify the patch actually landed and yields the mapping we want.
grep -q 'honor,fur-602' "$NETWORK_FILE" \
	|| fail "$NETWORK_FILE still does not mention honor,fur-602 after patching"
grep -q 'ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan' "$NETWORK_FILE" \
	|| fail "$NETWORK_FILE has no 3-LAN arm -- cannot confirm the LAN/WAN mapping"
# Guard against a double injection.
[ "$(grep -c 'honor,fur-602' "$NETWORK_FILE")" -eq 1 ] \
	|| fail "$NETWORK_FILE mentions honor,fur-602 more than once -- duplicate injection"
note "02_network: honor,fur-602 -> lan1 lan2 lan3 + wan"

# ---------------------------------------------------------------------------
# 4. Kernel configuration
# ---------------------------------------------------------------------------
# The kernel-config part of our fragment is DELIBERATELY EMPTY. Upstream keeps
# tc/qdisc/ifb, netfilter, mac80211/mt76 and USB out of the target kernel config
# on purpose and ships them as opt-in kmod packages; baking them in with =y
# would bloat the kernel and diverge from upstream. The kmods are supplied by
# the packages feed, and the workflow builds the full kmod set so they are
# installable later.
#
# We still assert the knobs that make those kmods exist, so a silent upstream
# change is caught here rather than at opkg-install time on the device.
grep -q 'define KernelPackage/mt7915e' package/kernel/mt76/Makefile \
	|| fail "package/kernel/mt76/Makefile has no KernelPackage/mt7915e"
grep -q 'define KernelPackage/mt7981-firmware' package/kernel/mt76/Makefile \
	|| fail "package/kernel/mt76/Makefile has no KernelPackage/mt7981-firmware"
grep -rq 'mt7981-wo-firmware' package/firmware/linux-firmware/ \
	|| fail "mt7981-wo-firmware is no longer defined under package/firmware/linux-firmware/"
note "kernel config: no in-kernel fragment required (kmod-provided); wireless packages present"

# CONFIG_ALL_KMODS=y makes *every* kmod package default to `m`, i.e. built and
# published into bin/targets/mediatek/filogic/packages/, while only the packages
# forced to `y` (DEFAULT_PACKAGES + DEVICE_PACKAGES) are installed into the
# image. That is what lets `opkg install kmod-sched-cake kmod-ifb ...` succeed
# on the device afterwards with a matching kernel ABI, without inflating the
# image. It is a tristate knob, so `m` is legal and does NOT mean "install this".
#
# The workflow applies and enforces this in .config; record the intent here so
# the requirement is not silently lost if the workflow is ever rewritten.
note "build config requirement: CONFIG_ALL_KMODS=y (publish full kmod set, keep image lean)"

note "HONOR FUR-602/603 device support ready (ImmortalWrt 25.12.2 / kernel 6.12)."
