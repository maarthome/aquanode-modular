#!/usr/bin/env bash
# Build Aquanode Modular on a Raspberry Pi 5 (Raspberry Pi OS / Debian trixie, aarch64).
#
#   ./build_pi.sh              standalone app + LV2 plugin of the synth
#   ./build_pi.sh --fx         also the effect version (LV2), roughly doubles the build time
#   ./build_pi.sh --vst3       also VST3 plugins
#   ./build_pi.sh --install    after building, copy the LV2 bundle(s) to ~/.lv2
#   ./build_pi.sh --jobs N     parallel compile jobs (default 2, safe for 4 GB of memory)
#   ./build_pi.sh --clean      delete the build folder first
#   ./build_pi.sh --no-apt     do not check or install system packages
#
# Results are collected in ./dist-linux-<arch>/

set -euo pipefail

JUCE_TAG="9.0.5"
JOBS=2
BUILD_FX=OFF
BUILD_VST3=OFF
INSTALL=false
CLEAN=false
USE_APT=true

while [ $# -gt 0 ]; do
    case "$1" in
        --fx)       BUILD_FX=ON ;;
        --vst3)     BUILD_VST3=ON ;;
        --install)  INSTALL=true ;;
        --clean)    CLEAN=true ;;
        --no-apt)   USE_APT=false ;;
        --jobs)     shift; JOBS="${1:?--jobs needs a number}" ;;
        -h|--help)  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
BUILD_DIR="$ROOT/build-linux-$ARCH"
DIST_DIR="$ROOT/dist-linux-$ARCH"
cd "$ROOT"

echo "== Aquanode Modular build: arch $ARCH, $JOBS jobs, FX $BUILD_FX, VST3 $BUILD_VST3 =="
[ "$ARCH" = "aarch64" ] || echo "Note: this is not aarch64; building for $ARCH instead."

# ── 1. System packages ───────────────────────────────────────────────────────────────────
PACKAGES=(
    build-essential cmake ninja-build pkg-config git ca-certificates
    libasound2-dev libjack-jackd2-dev
    libfreetype-dev libfontconfig1-dev
    libx11-dev libxext-dev libxrandr-dev libxinerama-dev libxcursor-dev
    libxcomposite-dev libxrender-dev
    libgl1-mesa-dev libegl1-mesa-dev
)
if $USE_APT; then
    MISSING=()
    for p in "${PACKAGES[@]}"; do
        dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || MISSING+=("$p")
    done
    if [ ${#MISSING[@]} -gt 0 ]; then
        echo "== Installing packages: ${MISSING[*]}"
        sudo apt-get update
        sudo apt-get install -y --no-install-recommends "${MISSING[@]}"
    fi
fi

# ── 2. JUCE (not part of the repository) ─────────────────────────────────────────────────
if [ ! -f "$ROOT/JUCE/CMakeLists.txt" ]; then
    echo "== Fetching JUCE $JUCE_TAG"
    rm -rf "$ROOT/JUCE.partial"
    git clone --depth 1 --branch "$JUCE_TAG" https://github.com/juce-framework/JUCE.git "$ROOT/JUCE.partial"
    mv "$ROOT/JUCE.partial" "$ROOT/JUCE"
fi

# ── 3. Memory check ──────────────────────────────────────────────────────────────────────
MEM_MB=$(awk '/MemTotal/ {m=$2} /SwapTotal/ {s=$2} END {print int((m+s)/1024)}' /proc/meminfo)
if [ "$MEM_MB" -lt $((JOBS * 2500)) ]; then
    echo "Warning: ${MEM_MB} MB of memory+swap for $JOBS jobs is tight. If the build gets killed,"
    echo "         run again with --jobs 1 (it continues where it stopped)."
fi

# ── 4. Configure and build ───────────────────────────────────────────────────────────────
$CLEAN && rm -rf "$BUILD_DIR"

cmake -S "$ROOT" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DAQ_BUILD_FX="$BUILD_FX" \
    -DAQ_BUILD_VST3="$BUILD_VST3"

cmake --build "$BUILD_DIR" --parallel "$JOBS"

# ── 5. Collect the results ───────────────────────────────────────────────────────────────
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
for target in AquanodeModular AquanodeModularFX; do
    art="$BUILD_DIR/${target}_artefacts/Release"
    [ -d "$art" ] || continue
    for kind in Standalone LV2 VST3; do
        [ -d "$art/$kind" ] && cp -a "$art/$kind/." "$DIST_DIR/"
    done
done

if $INSTALL; then
    mkdir -p "$HOME/.lv2"
    for bundle in "$DIST_DIR"/*.lv2; do
        [ -d "$bundle" ] || continue
        rm -rf "$HOME/.lv2/$(basename "$bundle")"
        cp -a "$bundle" "$HOME/.lv2/"
        echo "Installed $(basename "$bundle") in ~/.lv2"
    done
fi

echo
echo "== Done. Results in $DIST_DIR:"
ls -1 "$DIST_DIR"
