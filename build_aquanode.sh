#!/usr/bin/env bash
# Build Aquanode Modular on the Pi using every core, with a temporary 6 GB swap file so the
# build is not killed for lack of memory. The swap file is removed again when the build
# ends, also when it fails or is interrupted with Ctrl+C.
#
#   ./build_aquanode.sh              standalone app + LV2 plugin, all cores
#   ./build_aquanode.sh --install    any option of build_pi.sh can be added (--fx, --vst3, ...)
#
# Environment:
#   SWAP_GB=6                        size of the temporary swap file
#   SWAP_FILE=/swapfile-aquanode     where to put it (needs that much free disk space)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SWAP_GB="${SWAP_GB:-6}"
SWAP_FILE="${SWAP_FILE:-/swapfile-aquanode}"
SWAP_ON=false

cleanup() {
    if $SWAP_ON; then
        echo "== Removing temporary swap $SWAP_FILE"
        sudo swapoff "$SWAP_FILE" 2>/dev/null || true
        sudo rm -f "$SWAP_FILE"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# A previous run that was cut off (power loss) may have left the file behind.
if grep -q "^$SWAP_FILE " /proc/swaps; then
    sudo swapoff "$SWAP_FILE"
fi
sudo rm -f "$SWAP_FILE"

SWAP_DIR="$(dirname "$SWAP_FILE")"
FREE_MB=$(df -Pm "$SWAP_DIR" | awk 'NR==2 {print $4}')
NEED_MB=$((SWAP_GB * 1024 + 1024))
if [ "$FREE_MB" -lt "$NEED_MB" ]; then
    echo "Not enough free disk space in $SWAP_DIR for a ${SWAP_GB} GB swap file" >&2
    echo "(${FREE_MB} MB free, ${NEED_MB} MB needed). Set SWAP_GB or SWAP_FILE." >&2
    exit 1
fi

echo "== Creating temporary ${SWAP_GB} GB swap at $SWAP_FILE"
SWAP_ON=true
# dd instead of fallocate: swap files with holes are refused on some file systems.
sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$((SWAP_GB * 1024)) status=progress
sudo chmod 600 "$SWAP_FILE"
sudo mkswap "$SWAP_FILE" >/dev/null
sudo swapon "$SWAP_FILE"
free -h

"$ROOT/build_pi.sh" --jobs "$(nproc)" "$@"
