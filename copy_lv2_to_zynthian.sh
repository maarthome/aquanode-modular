#!/usr/bin/env bash
# Copy the built LV2 bundle(s) from ./dist-linux-<arch>/ to the Zynthian.
#
#   ./copy_lv2_to_zynthian.sh                      copies to root@zynthian:/usr/local/lib/lv2/
#   ./copy_lv2_to_zynthian.sh root@zynthian.local  other address
#
# Environment:
#   ZYNTHIAN_LV2_DIR=/usr/local/lib/lv2            folder on the Zynthian

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-root@zynthian}"
REMOTE_DIR="${ZYNTHIAN_LV2_DIR:-/usr/local/lib/lv2}"
DIST_DIR="$ROOT/dist-linux-$(uname -m)"

shopt -s nullglob
BUNDLES=("$DIST_DIR"/*.lv2)
if [ ${#BUNDLES[@]} -eq 0 ]; then
    echo "No .lv2 bundles in $DIST_DIR. Build first with ./build_aquanode.sh" >&2
    exit 1
fi

echo "== Copying to $TARGET:$REMOTE_DIR/"
for b in "${BUNDLES[@]}"; do echo "   $(basename "$b")"; done

scp -r "${BUNDLES[@]}" "$TARGET:$REMOTE_DIR/"

echo "== Done. On the Zynthian, rescan the LV2 plugins (webconf: Software > LV2-Plugins >"
echo "   Search for new Plugins & Presets) so the new plugin shows up."
