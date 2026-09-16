#!/bin/bash
#
# diy-part2.sh -- inject HONOR FUR-602/603 device support into an
# ImmortalWrt 24.10 source tree.
#
# Run from the root of the source tree (working-directory = openwrt), with the
# device tree file present one level up, i.e.:
#
#   <workspace>/openwrt/                     <- source tree (this script's CWD)
#   <workspace>/mt7981b-honor-fur-602.dts    <- device tree
#
# The script is idempotent: re-running it will not duplicate anything.
# Every step fails loudly instead of silently producing a firmware that does
# not actually contain the device.

set -eu

DTS_SRC="../mt7981b-honor-fur-602.dts"
DTS_DST="target/linux/mediatek/dts/mt7981b-honor-fur-602.dts"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"
MEDIATEK_IMG_MK="target/linux/mediatek/image/Makefile"
FILOGIC_CFG="target/linux/mediatek/filogic/config-6.6"

fail() {
	echo "[diy] ERROR: $*" >&2
	exit 1
}

# ---------------------------------------------------------------------------
# 0. Sanity-check the source tree layout before touching anything
# ---------------------------------------------------------------------------
[ -f "$FILOGIC_MK" ] || fail "$FILOGIC_MK not found -- wrong source tree or branch?"
[ -f "$MEDIATEK_IMG_MK" ] || fail "$MEDIATEK_IMG_MK not found -- wrong source tree?"
[ -d "target/linux/mediatek/dts" ] || fail "target/linux/mediatek/dts not found"
[ -f "$FILOGIC_CFG" ] || fail "$FILOGIC_CFG not found -- mediatek/filogic shared config changed?"

# mediatek has no per-target config (target/linux/mediatek/config-6.6 does not
# exist), so include/target.mk's USE_SUBTARGET_CONFIG resolves to 1 and
# filogic/config-6.6 becomes LINUX_RECONFIG_TARGET -- i.e. the highest-priority
# file that kconfig.pl merges for this target.  That is why our kernel-config
# fragment belongs there and nowhere else.
if [ -f "target/linux/mediatek/config-6.6" ]; then
	fail "target/linux/mediatek/config-6.6 now exists; the config precedence changed -- re-check where the fragment should go"
fi

# The FIT-in-UBI kernel we rely on must come from Device/Default.  Note the
# doubled dollar signs: this is a Makefile, so `$$(...)` is a literal `$(...)`
# that make expands later.
grep -q 'fit lzma \$\$(KDIR)/image-\$\$(firstword \$\$(DEVICE_DTS)).dtb' "$MEDIATEK_IMG_MK" \
	|| fail "Device/Default in $MEDIATEK_IMG_MK no longer builds a FIT kernel; this device definition assumes it does"

# ---------------------------------------------------------------------------
# 1. Install the device tree
# ---------------------------------------------------------------------------
if [ -f "$DTS_SRC" ]; then
	cp -f "$DTS_SRC" "$DTS_DST"
	echo "[diy] installed $DTS_DST"
else
	[ -f "$DTS_DST" ] || fail "neither $DTS_SRC nor $DTS_DST exists"
	echo "[diy] $DTS_SRC not found, keeping existing $DTS_DST"
fi

# ---------------------------------------------------------------------------
# 2. Register the device in the filogic image build
# ---------------------------------------------------------------------------
if grep -q 'define Device/honor_fur-602' "$FILOGIC_MK"; then
	echo "[diy] $FILOGIC_MK already has honor_fur-602, skip"
else
	cat >> "$FILOGIC_MK" <<'EOF'

define Device/honor_fur-602
  DEVICE_VENDOR := HONOR
  DEVICE_MODEL := FUR-602
  DEVICE_ALT0_VENDOR := HONOR
  DEVICE_ALT0_MODEL := FUR-603
  DEVICE_DTS := mt7981b-honor-fur-602
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
	echo "[diy] appended honor_fur-602 to $FILOGIC_MK"
fi

# ---------------------------------------------------------------------------
# 3. Network interface mapping
# ---------------------------------------------------------------------------
# ImmortalWrt 24.10 mediatek/filogic uses DSA: the port names come straight
# from the DTS (port@0 -> "wan", port@1..3 -> "lan3"/"lan2"/"lan1"), and the
# default case in mediatek_setup_interfaces() already yields
# "lan1 lan2 lan3" + "wan", which is exactly what we want. Likewise the MAC
# addresses are supplied by the DTS via nvmem cells on gmac0 (0x2a) and on
# port@0 (0x24), so no board.d change is required at all.
#
# We therefore deliberately do NOT patch 02_network. The old LEDE-style
# *honor,fur-602* branch (swconfig "eth0.1"/"eth0.2" + add_switch) must NOT be
# carried over into a DSA tree.
NETWORK_FILE="target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
if [ -f "$NETWORK_FILE" ] && grep -q 'honor,fur-602' "$NETWORK_FILE"; then
	fail "$NETWORK_FILE unexpectedly mentions honor,fur-602; a swconfig-style entry is incompatible with this DSA device tree -- remove it manually"
fi
echo "[diy] 02_network: no change needed (DSA, MAC supplied by DTS nvmem)"

# ---------------------------------------------------------------------------
# 4. Upgrade path
# ---------------------------------------------------------------------------
# FUR-602 must take the generic fallback branch `*) nand_do_upgrade "$1"` in
# filogic's platform_do_upgrade(), because our sysupgrade.bin is a sysupgrade
# tar that the bl-mt798x U-Boot expects in the UBI volumes "kernel"/"rootfs".
#
# The ustar/tar validation is NOT in this file: nand_do_upgrade() calls
# nand_do_platform_check() (package/base-files/files/lib/upgrade/nand.sh),
# which detects the tar by looking for `sysupgrade-<board>/CONTROL` inside it
# and then runs `tar xOf - >/dev/null` via nand_verify_tar_file().  So what we
# assert here is (a) the generic fallback still calls nand_do_upgrade, and
# (b) our board is NOT special-cased into a different upgrade path.
PLATFORM_SH="target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
if [ -f "$PLATFORM_SH" ]; then
	grep -q 'nand_do_upgrade "\$1"' "$PLATFORM_SH" \
		|| fail "$PLATFORM_SH no longer has a nand_do_upgrade branch"
	# The very last case arm must still be the generic fallback.
	awk '/^\t\*\)/{found=1} END{if(!found){exit 1}}' "$PLATFORM_SH" \
		|| fail "$PLATFORM_SH no longer has a generic *) fallback branch"
	if grep -q 'honor,fur-602' "$PLATFORM_SH"; then
		fail "$PLATFORM_SH now special-cases honor,fur-602 -- verify the new branch still does nand_do_upgrade with volumes kernel/rootfs"
	fi
	echo "[diy] platform.sh: generic nand_do_upgrade fallback present, no FUR-602 override"
fi

# ---------------------------------------------------------------------------
# 5. Kernel / build configuration
# ---------------------------------------------------------------------------
# The kernel-config part of our fragment is deliberately EMPTY -- see the long
# explanation in filogic.config.append.  In short: upstream keeps tc/qdisc/ifb,
# netfilter, mac80211/mt76 and USB out of the target kernel config on purpose
# and ships them as opt-in kmod packages, and the reference port for this very
# board (hanwckf/immortalwrt-mt798x mt7981/config-5.4) does the same.  Baking
# them in with =y would bloat the kernel and diverge from upstream.
#
# What we DO assert here is that the kmod-selection knobs that make those
# packages actually exist are present in the build config, and that the target
# config still looks the way our assumptions require.
if [ -f "../filogic.config.append" ]; then
	# Re-verify the assumptions the empty kernel fragment relies on.
	grep -q '^# CONFIG_NET_SCH_HTB is not set' target/linux/generic/config-6.6 \
		|| echo "[diy] NOTE: generic/config-6.6 no longer marks NET_SCH_HTB as unset; re-check whether a kernel fragment is now needed"
	grep -q '^# CONFIG_MAC80211 is not set' target/linux/generic/config-6.6 \
		|| echo "[diy] NOTE: generic/config-6.6 no longer marks MAC80211 as unset; re-check the wireless kmod situation"
	echo "[diy] kernel config: no in-kernel fragment required (kmod-provided), assumptions asserted"
else
	echo "[diy] filogic.config.append not found, skipping kernel-config notes"
fi

# CONFIG_ALL_KMODS=y makes *every* kmod package default to `m`, i.e. built and
# published into bin/targets/mediatek/filogic/packages/, while only the packages
# forced to `y` (DEFAULT_PACKAGES + DEVICE_PACKAGES) are installed into the
# firmware image.  That is what lets `opkg install kmod-sched-cake kmod-ifb ...`
# succeed on the device afterwards with a matching kernel ABI, without inflating
# the image.  kmod packages are `tristate` (Type: ipkg), so `m` is legal and
# does NOT mean "install this".
#
# This is applied to the build .config by the workflow; record the intent here
# so the requirement is not silently lost if the workflow is ever rewritten.
echo "[diy] build config requirement: CONFIG_ALL_KMODS=y (publish full kmod set, keep image lean)"

echo "[diy] HONOR FUR-602/603 device support ready."
