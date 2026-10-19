#!/usr/bin/env bash
#
# Verify a NORMALIZED FUR-602 artifact tree and emit a report.
#
# Input layout (produced by normalize-artifacts.sh):
#   <norm>/bin/targets/<target>/<subtarget>/           firmware + metadata
#   <norm>/bin/targets/<target>/<subtarget>/packages/  kmod packages + index
#   <norm>/rescue/                                     rescue images
#   <norm>/provenance/                                 build-info.*, env.txt (new layout only)
#
# Deliberately format-agnostic: 25.12 emits APK (.apk + packages.adb), 24.10
# emitted OPKG (.ipk + Packages). Detecting is correct; assuming is what broke
# the very first run.
#
# Usage: verify-normalized.sh <norm-dir> <out-dir>
# Exit 0 only if every required check passes.
set -eu

NORM="${1:?usage: verify-normalized.sh <norm-dir> <out-dir>}"
OUT="${2:?usage: verify-normalized.sh <norm-dir> <out-dir>}"
TARGET="${TARGET:-mediatek}"
SUBTARGET="${SUBTARGET:-filogic}"
DEVICE="${DEVICE:-honor_fur-602}"
BUILD_ALL_KMODS="${BUILD_ALL_KMODS:-true}"

BIN="$NORM/bin/targets/$TARGET/$SUBTARGET"
PKGS="$BIN/packages"
rm -rf "$OUT"
mkdir -p "$OUT"

FAILED=0
note() { echo "  $*"; }
fail() { echo "::error::$*"; FAILED=$((FAILED + 1)); }
pass() { echo "  OK   $*"; }

echo "=============================================================="
echo " verifying normalized artifacts"
echo "   target     = $TARGET/$SUBTARGET"
echo "   device     = $DEVICE"
echo "   all_kmods  = $BUILD_ALL_KMODS"
echo "=============================================================="

# ------------------------------------------------------------------ #
# 1. Firmware images
# ------------------------------------------------------------------ #
echo
echo "===== firmware images ====="
ls -la "$BIN"/*.bin 2>/dev/null || note "(no .bin files)"

FACTORY=$(ls "$BIN"/*"$DEVICE"*factory*.bin 2>/dev/null | head -1 || true)
SYSUP=$(ls "$BIN"/*"$DEVICE"*sysupgrade*.bin 2>/dev/null | head -1 || true)

if [ -n "$FACTORY" ]; then
  pass "factory.bin: $(basename "$FACTORY") ($(stat -c%s "$FACTORY") bytes)"
else
  fail "factory.bin not found for $DEVICE"
fi
if [ -n "$SYSUP" ]; then
  pass "sysupgrade.bin: $(basename "$SYSUP") ($(stat -c%s "$SYSUP") bytes)"
else
  fail "sysupgrade.bin not found for $DEVICE"
fi

# ------------------------------------------------------------------ #
# 2. sysupgrade payload structure
#
# Build/sysupgrade-tar produces a tar holding sysupgrade-<board>/CONTROL,
# /kernel, /root; append-metadata may prefix a metadata header, so search for
# the tar rather than assuming offset 0. bl-mt798x U-Boot's parse_tar_image()
# and OpenWrt's nand_do_platform_check() both require this shape.
# ------------------------------------------------------------------ #
echo
echo "===== sysupgrade.bin payload ====="
if [ -n "$SYSUP" ]; then
  if tar tf "$SYSUP" >/dev/null 2>&1; then
    tar tf "$SYSUP" | head -8 | sed 's/^/    /'
    if tar tf "$SYSUP" | grep -q "^sysupgrade-$DEVICE/"; then
      pass "tar contains sysupgrade-$DEVICE/"
    else
      fail "tar has no sysupgrade-$DEVICE/ directory"
    fi
    tar tf "$SYSUP" | grep -q "^sysupgrade-$DEVICE/kernel$" \
      && pass "kernel entry present" || note "warning: no kernel entry"
    tar tf "$SYSUP" | grep -q "^sysupgrade-$DEVICE/root$" \
      && pass "root entry present" || note "warning: no root entry"
  else
    fail "sysupgrade.bin is not a readable tar"
  fi
else
  note "(skipped: no sysupgrade.bin)"
fi

# ------------------------------------------------------------------ #
# 3. Manifest / profiles
# ------------------------------------------------------------------ #
echo
echo "===== manifest / profiles ====="
if ls "$BIN"/*.manifest >/dev/null 2>&1; then
  pass "manifest: $(ls "$BIN"/*.manifest | head -1 | xargs basename) ($(wc -l < "$(ls "$BIN"/*.manifest | head -1)") lines)"
else
  fail "no .manifest"
fi
if [ -f "$BIN/profiles.json" ]; then
  if grep -q 'honor,fur-602' "$BIN/profiles.json"; then
    pass "profiles.json declares honor,fur-602"
  else
    note "warning: honor,fur-602 not found in profiles.json"
  fi
else
  note "warning: no profiles.json"
fi

# ------------------------------------------------------------------ #
# 4. Package format detection + full kmod set
# ------------------------------------------------------------------ #
echo
echo "===== published packages ====="
if [ ! -d "$PKGS" ]; then
  fail "$PKGS missing -- no packages were published"
else
  N_APK=$(find "$PKGS" -maxdepth 1 -type f -name '*.apk' | wc -l)
  N_IPK=$(find "$PKGS" -maxdepth 1 -type f -name '*.ipk' | wc -l)
  note ".apk = $N_APK, .ipk = $N_IPK"

  if [ "$N_APK" -gt 0 ]; then
    PKGEXT="apk"
    KMOD_COUNT=$(find "$PKGS" -maxdepth 1 -type f -name 'kmod-*.apk' | wc -l)
  elif [ "$N_IPK" -gt 0 ]; then
    PKGEXT="ipk"
    KMOD_COUNT=$(find "$PKGS" -maxdepth 1 -type f -name 'kmod-*.ipk' | wc -l)
  else
    PKGEXT=""
    KMOD_COUNT=0
    fail "$PKGS holds neither .apk nor .ipk files"
  fi

  if [ -n "$PKGEXT" ]; then
    pass "package format = .$PKGEXT"
    note "kmod count = $KMOD_COUNT"

    if [ "$BUILD_ALL_KMODS" = "false" ]; then
      note "(build_all_kmods=false: full set not expected)"
    elif [ "$KMOD_COUNT" -lt 100 ]; then
      fail "only $KMOD_COUNT kmod .$PKGEXT -- CONFIG_ALL_KMODS did not take effect"
    else
      pass "full kmod set published ($KMOD_COUNT packages)"
    fi

    echo "  --- key packages (QoS/SQM, wifi, netfilter) ---"
    MISSING=0
    for p in kmod-sched-core kmod-sched kmod-sched-cake kmod-ifb \
             kmod-mac80211 kmod-cfg80211 kmod-mt7915e kmod-nft-core kmod-pppoe; do
      # Check each pattern separately: `ls pat1 pat2` returns non-zero when
      # EITHER operand is missing, which reports a false MISS.
      if find "$PKGS" -maxdepth 1 -type f \
           \( -name "${p}_*.$PKGEXT" -o -name "${p}-*.$PKGEXT" \) | grep -q .; then
        pass "$p"
      else
        fail "$p missing"
        MISSING=$((MISSING + 1))
      fi
    done

    # Index: apk uses packages.adb, opkg uses Packages.
    if [ "$PKGEXT" = "apk" ]; then
      if find "$PKGS" -maxdepth 1 -type f -name 'packages.adb' | grep -q .; then
        pass "packages.adb index present ($(stat -c%s "$PKGS/packages.adb") bytes)"
      else
        fail "no packages.adb index (apk)"
      fi
    else
      if find "$PKGS" -maxdepth 1 -type f -name 'Packages' | grep -q .; then
        pass "Packages index present"
      else
        fail "no Packages index (opkg)"
      fi
    fi
  fi
fi

# ------------------------------------------------------------------ #
# 5. Rescue images, and the bootloader-leak guard.
#
# A rescue/initramfs image is legitimate. A BL2 / FIP / preloader image is
# NOT flashable firmware and must never be presented as such, so its presence
# in the flashable set is a hard failure.
# ------------------------------------------------------------------ #
echo
echo "===== rescue images ====="
if [ -d "$NORM/rescue" ] && [ -n "$(ls -A "$NORM/rescue" 2>/dev/null)" ]; then
  for f in "$NORM"/rescue/*; do
    [ -f "$f" ] || continue
    pass "rescue: $(basename "$f") ($(stat -c%s "$f") bytes)"
  done
else
  note "no rescue image present (not an error)"
fi

echo
echo "===== bootloader-leak guard ====="
# Match the BASENAME, never the full path. Matching the path means a directory
# whose name merely contains "bl2" (e.g. a test fixture called ...-bl2-leak)
# makes every file inside it look like a bootloader image.
LEAK=0
for d in "$BIN" "$NORM/rescue"; do
  [ -d "$d" ] || continue
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    fail "bootloader image in flashable output: $f"
    LEAK=$((LEAK + 1))
  done < <(find "$d" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null \
             | grep -Ei '(^|[^a-z0-9])(bl2|preloader|bl31|fip)([^a-z0-9]|$)' || true)
done
[ "$LEAK" -eq 0 ] && pass "no BL2 / preloader / BL31 / FIP images present"

# ------------------------------------------------------------------ #
# 6. Emit the curated output set.
# ------------------------------------------------------------------ #
echo
echo "===== collecting curated output ====="
mkdir -p "$OUT/firmware" "$OUT/kmods" "$OUT/rescue"

if [ -n "$FACTORY" ]; then cp -f "$FACTORY" "$OUT/firmware/"; fi
if [ -n "$SYSUP" ]; then cp -f "$SYSUP" "$OUT/firmware/"; fi
for f in "$BIN"/*.manifest "$BIN"/profiles.json "$BIN"/*.buildinfo; do
  [ -f "$f" ] && cp -f "$f" "$OUT/firmware/" || true
done

if [ -n "${PKGEXT:-}" ]; then
  find "$PKGS" -maxdepth 1 -type f -name "kmod-*.$PKGEXT" -exec cp -f {} "$OUT/kmods/" \;
  if [ "$PKGEXT" = "apk" ]; then
    [ -f "$PKGS/packages.adb" ] && cp -f "$PKGS/packages.adb" "$OUT/kmods/"
  else
    find "$PKGS" -maxdepth 1 -type f -name 'Packages*' -exec cp -f {} "$OUT/kmods/" \;
  fi
fi

if [ -d "$NORM/rescue" ]; then
  find "$NORM/rescue" -maxdepth 1 -type f -exec cp -f {} "$OUT/rescue/" \;
fi

# Provenance: keep whatever the input gave us, verbatim.
if [ -f "$NORM/provenance/build-info.txt" ]; then
  cp -f "$NORM/provenance/build-info.txt" "$OUT/firmware/build-info.txt"
  cp -f "$NORM/provenance/build-info.txt" "$OUT/kmods/build-info.txt"
elif [ -f "$NORM/provenance/build-info.md" ]; then
  cp -f "$NORM/provenance/build-info.md" "$OUT/firmware/build-info.txt"
  cp -f "$NORM/provenance/build-info.md" "$OUT/kmods/build-info.txt"
fi
if [ -d "$NORM/provenance/original-sums" ]; then
  mkdir -p "$OUT/firmware/original-sums"
  cp -f "$NORM/provenance/original-sums/"* "$OUT/firmware/original-sums/" 2>/dev/null || true
fi

# ------------------------------------------------------------------ #
# 7. Checksums for everything we deliver.
# ------------------------------------------------------------------ #
echo
echo "===== checksums ====="
for d in firmware kmods rescue; do
  [ -d "$OUT/$d" ] || continue
  if [ -z "$(ls -A "$OUT/$d" 2>/dev/null)" ]; then
    rmdir "$OUT/$d" 2>/dev/null || true
    continue
  fi
  ( cd "$OUT/$d" && find . -maxdepth 1 -type f ! -name SHA256SUMS.txt -printf '%P\n' \
      | sort | xargs -r sha256sum > SHA256SUMS.txt )
  note "$d: $(find "$OUT/$d" -maxdepth 1 -type f | wc -l) file(s)"
done

echo
echo "===== curated output tree ====="
find "$OUT" -type f -printf '  %-72p %10s bytes\n' 2>/dev/null | sort || true

echo
echo "===== SHA256 of delivered files ====="
for d in firmware kmods rescue; do
  [ -f "$OUT/$d/SHA256SUMS.txt" ] || continue
  echo "  --- $d ---"
  sed 's/^/    /' "$OUT/$d/SHA256SUMS.txt"
done

echo
echo "=============================================================="
if [ "$FAILED" -gt 0 ]; then
  echo "VERIFY RESULT: FAILED ($FAILED problem(s))"
  exit 1
fi
echo "VERIFY RESULT: PASSED"
exit 0
