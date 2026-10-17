#!/usr/bin/env bash
#
# Fetch the artifacts of a specific GitHub Actions run, by exact name.
#
# Requirements this satisfies:
#   * list the run's artifacts BEFORE downloading anything,
#   * download firmware / kmods / rescue by their exact names,
#   * extract each into its own directory,
#   * never silently download nothing.
#
# Two download paths are attempted, because cross-run artifact reads depend on
# token scope that must be proven rather than assumed:
#   1. `gh run download` (preinstalled on GitHub-hosted runners)
#   2. the REST API zip endpoint via curl with the same token
# If both fail, the script fails loudly with the real error.
#
# Usage: fetch-run-artifacts.sh <owner/repo> <run_id> <dest-dir>
set -eu

REPO="${1:?usage: fetch-run-artifacts.sh <owner/repo> <run_id> <dest-dir>}"
RUN_ID="${2:?usage: fetch-run-artifacts.sh <owner/repo> <run_id> <dest-dir>}"
DEST="${3:?usage: fetch-run-artifacts.sh <owner/repo> <run_id> <dest-dir>}"
API="https://api.github.com"

if ! printf '%s' "$RUN_ID" | grep -Eq '^[0-9]+$'; then
  echo "::error::run id must be numeric, got '$RUN_ID'"
  exit 1
fi
if [ -z "${GH_TOKEN:-}" ]; then
  echo "::error::GH_TOKEN is not set; cannot read artifacts of run $RUN_ID."
  echo "::error::Refusing to continue: downloading nothing must not look like success."
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"

api() {   # api <path> [jq-filter] -- JSON to stdout, retried
  local path="$1" i
  for i in 1 2 3 4 5; do
    if out=$(curl -sS --max-time 60 \
               -H "Authorization: Bearer $GH_TOKEN" \
               -H "Accept: application/vnd.github+json" \
               -H "X-GitHub-Api-Version: 2022-11-28" \
               "$API/$path" 2>/dev/null) && [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
    sleep $((i * 3))
  done
  return 1
}

# ------------------------------------------------------------------ #
# 1. Confirm the source run exists and really succeeded.
# ------------------------------------------------------------------ #
echo "===== source run $RUN_ID ====="
RUN_JSON=$(api "repos/$REPO/actions/runs/$RUN_ID") || {
  echo "::error::cannot read run $RUN_ID in $REPO"
  exit 1
}
python3 - "$RUN_JSON" > "$DEST/.source-run.txt" <<'PYEOF'
import json, sys
d = json.loads(sys.argv[1])
print(f"  name     = {d['name']}")
print(f"  status   = {d['status']} / {d['conclusion']}")
print(f"  branch   = {d['head_branch']}")
print(f"  head_sha = {d['head_sha']}")
print(f"  created  = {d['created_at']}")
print(f"  url      = {d['html_url']}")
PYEOF
cat "$DEST/.source-run.txt"

STATUS=$(python3 -c "import json,sys;d=json.loads(sys.argv[1]);print(d['status'])" "$RUN_JSON")
CONC=$(python3 -c "import json,sys;d=json.loads(sys.argv[1]);print(d['conclusion'])" "$RUN_JSON")
if [ "$STATUS" != "completed" ] || [ "$CONC" != "success" ]; then
  echo "::error::run $RUN_ID is $STATUS/$CONC; refusing to treat it as a good build"
  exit 1
fi

# ------------------------------------------------------------------ #
# 2. List artifacts BEFORE downloading (explicit requirement).
# ------------------------------------------------------------------ #
echo
echo "===== artifacts available on run $RUN_ID ====="
ART_JSON=$(api "repos/$REPO/actions/runs/$RUN_ID/artifacts") || {
  echo "::error::cannot list artifacts for run $RUN_ID"
  exit 1
}
python3 - "$ART_JSON" > "$DEST/.artifact-list.tsv" <<'PYEOF'
import json, sys
d = json.loads(sys.argv[1])
for a in d.get("artifacts", []):
    print(f"{a['name']}\t{a['id']}\t{a['size_in_bytes']}\t{a['expired']}")
PYEOF

if [ ! -s "$DEST/.artifact-list.tsv" ]; then
  echo "::error::run $RUN_ID has no artifacts; nothing to verify"
  exit 1
fi

python3 - "$DEST/.artifact-list.tsv" <<'PYEOF'
import sys
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
print(f"  {'artifact name':52} {'size':>10}  expired")
print("  " + "-" * 74)
total = 0
for name, aid, size, expired in rows:
    print(f"  {name:52} {int(size)/1048576:>8.1f}M  {expired}")
    total += int(size)
print("  " + "-" * 74)
print(f"  total: {total/1048576:.1f} MiB across {len(rows)} artifact(s)")
PYEOF

# ------------------------------------------------------------------ #
# 3. Select by exact name.
#
# The NEW layout uploads one `raw` artifact. The LEGACY layout -- including
# the successful run this task reuses -- uploads three separately named
# artifacts. Both are accepted; the selection is driven only by names that
# are actually present, never by assuming a `raw` artifact exists.
# ------------------------------------------------------------------ #
echo
echo "===== selecting artifacts ====="
WANT="$DEST/.want.tsv"
: > "$WANT"
while IFS=$'\t' read -r name aid size expired; do
  [ -n "$name" ] || continue
  case "$name" in
    *-raw-*)       kind=raw      ;;
    *-firmware-*)  kind=firmware ;;
    *-kmods-*)     kind=kmods    ;;
    *-rescue-*)    kind=rescue   ;;
    *)             echo "  (ignoring unrecognised artifact: $name)"; continue ;;
  esac
  echo "  $kind  <- $name"
  printf '%s\t%s\t%s\n' "$name" "$aid" "$kind" >> "$WANT"
done < "$DEST/.artifact-list.tsv"

N_WANT=$(wc -l < "$WANT")
if [ "$N_WANT" -le 0 ]; then
  echo "::error::none of run $RUN_ID's artifacts match a known FUR-602 layout"
  exit 1
fi
if ! awk -F'\t' '$3=="firmware" || $3=="raw"' "$WANT" | grep -q .; then
  echo "::error::run $RUN_ID has no firmware (or raw) artifact"
  exit 1
fi

# ------------------------------------------------------------------ #
# 4. Download each into its OWN directory.
# ------------------------------------------------------------------ #
echo
echo "===== downloading ====="
while IFS=$'\t' read -r name aid kind; do
  [ -n "$name" ] || continue
  dir="$DEST/$name"
  mkdir -p "$dir"
  echo "  [$kind] $name (id=$aid)"

  ok=0
  # Path 1: gh CLI.
  if command -v gh >/dev/null 2>&1; then
    for i in 1 2; do
      if gh run download "$RUN_ID" --repo "$REPO" -n "$name" -D "$dir" >/dev/null 2>&1; then
        echo "       downloaded via gh"
        ok=1; break
      fi
      sleep $((i * 5))
    done
    [ "$ok" = "1" ] || echo "       gh download failed; falling back to the REST API"
  fi

  # Path 2: REST API zip endpoint.
  if [ "$ok" != "1" ]; then
    zip="$DEST/.$name.zip"
    code=$(curl -sS -L --max-time 900 \
             -H "Authorization: Bearer $GH_TOKEN" \
             -H "Accept: application/vnd.github+json" \
             -o "$zip" -w '%{http_code}' \
             "$API/repos/$REPO/actions/artifacts/$aid/zip" 2>/dev/null || echo 000)
    if [ "$code" = "200" ] && [ -s "$zip" ] && ! head -c 1 "$zip" | grep -q '{'; then
      if unzip -q -o "$zip" -d "$dir"; then
        echo "       downloaded via REST API"
        ok=1
      else
        echo "::error::artifact '$name' zip is unreadable"
      fi
    else
      echo "::error::REST download of '$name' returned HTTP $code"
      head -c 300 "$zip" 2>/dev/null | sed 's/^/       /' || true
    fi
    rm -f "$zip"
  fi

  if [ "$ok" != "1" ]; then
    echo "::error::could not download artifact '$name' from run $RUN_ID"
    exit 1
  fi
  echo "       $(find "$dir" -type f | wc -l) file(s), $(du -sh "$dir" | cut -f1)"
done < "$WANT"

echo
echo "===== downloaded tree ====="
find "$DEST" -mindepth 1 -maxdepth 1 -type d -printf '  %f\n' | sort
echo
echo "fetch OK: $N_WANT artifact(s) from run $RUN_ID into $DEST"
