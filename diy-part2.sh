#!/bin/bash
#
# diy-part2.sh — inject Honor FUR-602 device support into the OpenWrt/LEDE
# source tree. Run from the root of the source tree (working-directory = openwrt).
#
# Expected layout (see the workflow):
#   <workspace>/openwrt/                     <- source tree (this script's CWD)
#   <workspace>/mt7981b-honor-fur-602.dts    <- device tree, copied from repo
#
set -e

DTS_SRC="../mt7981b-honor-fur-602.dts"
DTS_DST="target/linux/mediatek/dts/mt7981b-honor-fur-602.dts"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"
NETWORK_FILE="target/linux/mediatek/filogic/base-files/etc/board.d/02_network"

# ---------------------------------------------------------------------------
# 1. Install the device tree
# ---------------------------------------------------------------------------
if [ -f "$DTS_SRC" ]; then
	cp -f "$DTS_SRC" "$DTS_DST"
	echo "[diy] installed $DTS_DST"
else
	echo "[diy] WARNING: $DTS_SRC not found, keeping existing $DTS_DST if any"
fi

# ---------------------------------------------------------------------------
# 2. Register the device in the image build (filogic.mk)
# ---------------------------------------------------------------------------
if grep -q 'define Device/honor_fur602' "$FILOGIC_MK"; then
	echo "[diy] filogic.mk already has honor_fur602, skip"
else
	cat >> "$FILOGIC_MK" <<'EOF'

define Device/honor_fur602
  DEVICE_VENDOR := Honor
  DEVICE_MODEL := FUR-602
  DEVICE_DTS := mt7981b-honor-fur-602
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7981-firmware mt7981-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 116736k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += honor_fur602
EOF
	echo "[diy] appended honor_fur602 to filogic.mk"
fi

# ---------------------------------------------------------------------------
# 3. Map network interfaces: 3 LAN + 1 WAN (all on the MT7531 switch / gmac0)
# ---------------------------------------------------------------------------
if grep -q 'honor,fur-602' "$NETWORK_FILE"; then
	echo "[diy] 02_network already has honor,fur-602, skip"
else
	python3 - "$NETWORK_FILE" <<'EOF'
import sys
p = sys.argv[1]
with open(p, encoding='utf-8') as f:
    s = f.read()
anchor = '\ttenbay,wr3000k)\n'
if anchor not in s:
    raise SystemExit('02_network: anchor not found; patch it manually')
s = s.replace(anchor, '\thonor,fur-602|\\\n' + anchor, 1)
with open(p, 'w', encoding='utf-8') as f:
    f.write(s)
print('[diy] patched 02_network')
EOF
fi

echo "[diy] Honor FUR-602 device support ready."
