#!/usr/bin/env bash
#
# Normalize FUR-602 build artifacts into a single canonical layout.
#
# Two artifact layouts exist in this repository's history, and the verify path
# must not assume either one:
#
#   NEW (commit bb369d6 onwards)
#     one artifact:  fur602-25.12.2-raw-<run_id>
#     contents:      bin/targets/<target>/<subtarget>/... and provenance/...
#
#   LEGACY (commit f2f6fbc, and the successful run 38134666544)
#     three artifacts, each holding loose files:
#       fur602-25.12.2-firmware-<run_id>-<shortsha>
#       fur602-25.12.2-kmods-<run_id>-<shortsha>
#       fur602-25.12.2-rescue-<run_id>-<shortsha>
#
# Rather than guess from the artifact NAME, this script copies every file by
# what it IS. That way a mix of layouts, or a future rename, still works.
#
# Produces:
#   <out>/bin/targets/<target>/<subtarget>/           firmware + metadata
#   <out>/bin/targets/<target>/<subtarget>/packages/  kmod packages + index
#   <out>/rescue/                                     rescue images
#   <out>/provenance/                                 build-info.*
#   <out>/provenance/original-sums/                   each input SHA256SUMS.txt
#
# Usage: normalize-artifacts.sh <download-dir> <out-dir>
set -eu

DL="${1:?usage: normalize-artifacts.sh <download-dir> <out-dir>}"
OUT="${2:?usage: normalize-artifacts.sh <download-dir> <out-dir>}"
TARGET="${TARGET:-mediatek}"
SUBTARGET="${SUBTARGET:-filogic}"

BIN="$OUT/bin/targets/$TARGET/$SUBTARGET"
PKGS="$BIN/packages"

rm -rf "$OUT"
mkdir -p "$BIN" "$PKGS" "$OUT/rescue" "$OUT/provenance/original-sums"

echo "=== normalizing artifacts from: $DL ==="
if [ ! -d "$DL" ]; then
  echo "::error::$DL does not exist -- nothing was downloaded"
  exit 1
fi

echo "--- downloaded artifact directories ---"
find "$DL" -mindepth 1 -maxdepth 1 -type d | sort || true
echo "--- downloaded top-level files (if merge-multiple was used) ---"
find "$DL" -mindepth 1 -maxdepth 1 -type f | sort | head -20 || true

# ------------------------------------------------------------------ #
# Copy helpers. Both tolerate "no match" without failing under set -e.
# ------------------------------------------------------------------ #
copy_matching() {   # copy_matching <srcdir> <destdir> <name-glob>
  local src="$1" dst="$2" pat="$3" hit=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    cp -f "$f" "$dst/" && hit=1
  done < <(find "$src" -maxdepth 1 -type f -name "$pat" 2>/dev/null || true)
  [ "$hit" -eq 1 ]
}

copy_tree() {       # copy_tree <srcdir> <destdir>
  local src="$1" dst="$2"
  mkdir -p "$dst"
  cp -a "$src/." "$dst/" 2>/dev/null || true
}

N_SRC=0

process_raw() {     # process_raw <dir>  -- NEW layout
  local d="$1"
  echo "  [raw/new layout] $(basename "$d")"
  [ -d "$d/bin/targets" ] && copy_tree "$d/bin/targets" "$OUT/bin/targets"
  [ -d "$d/provenance" ] && copy_tree "$d/provenance" "$OUT/provenance"
  N_SRC=$((N_SRC + 1))
}

process_loose() {   # process_loose <dir> -- LEGACY layout
  local d="$1" name
  name=$(basename "$d")
  echo "  [loose/legacy layout] $name"

  # Firmware images and their metadata.
  copy_matching "$d" "$BIN"  '*factory*.bin'    || true
  copy_matching "$d" "$BIN"  '*sysupgrade*.bin' || true
  copy_matching "$d" "$BIN"  '*.manifest'       || true
  copy_matching "$d" "$BIN"  'profiles.json'    || true
  copy_matching "$d" "$BIN"  'sha256sums'       || true
  copy_matching "$d" "$BIN"  '*.buildinfo'      || true
  copy_matching "$d" "$BIN"  'kernel'           || true
  copy_matching "$d" "$BIN"  '*.dtb'            || true

  # Kernel modules and the package index.
  copy_matching "$d" "$PKGS" 'kmod-*.apk'       || true
  copy_matching "$d" "$PKGS" 'kmod-*.ipk'       || true
  copy_matching "$d" "$PKGS" 'packages.adb'     || true
  copy_matching "$d" "$PKGS" 'Packages'         || true
  copy_matching "$d" "$PKGS" 'Packages.*'       || true

  # Rescue / diagnostic images.
  copy_matching "$d" "$OUT/rescue" '*initramfs*.bin' || true

  # Provenance.
  copy_matching "$d" "$OUT/provenance" 'build-info.*' || true

  # Keep each input's own checksum list for traceability.
  if [ -f "$d/SHA256SUMS.txt" ]; then
    cp -f "$d/SHA256SUMS.txt" "$OUT/provenance/original-sums/$name.SHA256SUMS.txt"
  fi
  N_SRC=$((N_SRC + 1))
}

# ------------------------------------------------------------------ #
# Walk every downloaded directory (merge-multiple:false gives one per
# artifact). Also handle the merged case where files sit directly in $DL.
# ------------------------------------------------------------------ #
for d in "$DL"/*/; do
  [ -d "$d" ] || continue
  if [ -d "$d/bin/targets" ]; then
    process_raw "$d"
  else
    process_loose "$d"
  fi
done

if [ "$N_SRC" -eq 0 ]; then
  echo "  no artifact subdirectories; treating $DL as a merged tree"
  if [ -d "$DL/bin/targets" ]; then
    process_raw "$DL"
  else
    process_loose "$DL"
  fi
fi

# ------------------------------------------------------------------ #
# Report what we ended up with.
# ------------------------------------------------------------------ #
echo
echo "=== normalized layout ==="
echo "  firmware dir : $BIN"
find "$BIN" -maxdepth 1 -type f -printf '    %f\n' 2>/dev/null | sort || true
echo "  packages dir : $PKGS"
echo "    package files: $(find "$PKGS" -maxdepth 1 -type f 2>/dev/null | wc -l)"
echo "    kmod-* files : $(find "$PKGS" -maxdepth 1 -type f -name 'kmod-*' 2>/dev/null | wc -l)"
echo "  rescue dir   : $OUT/rescue"
find "$OUT/rescue" -maxdepth 1 -type f -printf '    %f\n' 2>/dev/null | sort || true
echo "  provenance   : $OUT/provenance"
find "$OUT/provenance" -maxdepth 1 -type f -printf '    %f\n' 2>/dev/null | sort || true

# The single thing we cannot proceed without.
if ! find "$BIN" -maxdepth 1 -type f -name '*.bin' | grep -q .; then
  echo "::error::normalization produced no firmware .bin in $BIN"
  echo "::error::Input artifacts were not what this repository produces."
  exit 1
fi

echo
echo "normalization OK: $N_SRC input artifact(s) processed"
