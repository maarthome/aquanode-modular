#!/usr/bin/env bash
# Build a stripped LV2 plugin from one patch: the engine plus only the modules that patch
# uses, no editor window, starting with the patch loaded. Proof of concept.
#
#   ./build_stripped.sh --name "My Bass" --patch ~/patches/MyBass.aqua
#   ./build_stripped.sh --name "My Echo" --patch ~/patches/MyEcho.aqua --fx
#   ./build_stripped.sh --name "Aqua Init"          no patch: the app's Init patch
#
#   --name NAME     plugin name shown in the host (letters, digits, spaces, - and _)
#   --patch FILE    .aqua file made with Export Patch in the app
#   --fx            build an effect (audio in -> audio out) instead of an instrument
#   --install       copy the result to ~/.lv2 as well
#   --jobs N        parallel compile jobs (default 2)
#
# The full build must have been made first (./build_aquanode.sh): the stripped plugin
# takes its module code from that build. The result goes to ./dist-linux-<arch>/.

set -euo pipefail

NAME=""
PATCH=""
FX=false
INSTALL=false
JOBS=2

while [ $# -gt 0 ]; do
    case "$1" in
        --name)     shift; NAME="${1:?--name needs a value}" ;;
        --patch)    shift; PATCH="${1:?--patch needs a file}" ;;
        --fx)       FX=true ;;
        --install)  INSTALL=true ;;
        --jobs)     shift; JOBS="${1:?--jobs needs a number}" ;;
        -h|--help)  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$NAME" ] || { echo "--name is required (try --help)" >&2; exit 2; }
[ -z "$PATCH" ] || [ -f "$PATCH" ] || { echo "Patch file not found: $PATCH" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
BUILD_DIR="$ROOT/build-linux-$ARCH"
DIST_DIR="$ROOT/dist-linux-$ARCH"

if [ ! -f "$BUILD_DIR/build.ninja" ]; then
    echo "The full build is missing. Run ./build_aquanode.sh first." >&2
    exit 1
fi

SLUG="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')"
GEN_DIR="$BUILD_DIR/stripped/$SLUG"

GEN_ARGS=(--name "$NAME" --out "$GEN_DIR")
[ -z "$PATCH" ] || GEN_ARGS+=(--patch "$PATCH")
$FX && GEN_ARGS+=(--fx)
python3 "$ROOT/tools/make_stripped.py" "${GEN_ARGS[@]}"

cmake -S "$ROOT" -B "$BUILD_DIR" -DAQ_STRIPPED_DIR="$GEN_DIR" > "$BUILD_DIR/stripped-configure.log" 2>&1 \
    || { cat "$BUILD_DIR/stripped-configure.log"; exit 1; }
cmake --build "$BUILD_DIR" --target aq_stripped --parallel "$JOBS"

ART_DIR="$(cat "$BUILD_DIR/aq_stripped_artefacts.txt")"
BUNDLE="$ART_DIR/$NAME.lv2"
[ -d "$BUNDLE" ] || { echo "Build finished but $BUNDLE is missing" >&2; exit 1; }

mkdir -p "$DIST_DIR"
rm -rf "$DIST_DIR/$NAME.lv2"
cp -a "$BUNDLE" "$DIST_DIR/"
find "$DIST_DIR/$NAME.lv2" -name '*.so' -exec strip --strip-unneeded {} \;

if $INSTALL; then
    mkdir -p "$HOME/.lv2"
    rm -rf "$HOME/.lv2/$NAME.lv2"
    cp -a "$DIST_DIR/$NAME.lv2" "$HOME/.lv2/"
    echo "Installed $NAME.lv2 in ~/.lv2"
fi

echo
echo "== Done: $DIST_DIR/$NAME.lv2"
du -sh "$DIST_DIR/$NAME.lv2"
