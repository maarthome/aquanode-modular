#!/usr/bin/env bash
# Build a stripped LV2 plugin from one patch: the engine plus only the modules that patch
# uses, starting with the patch loaded. Proof of concept.
#
# Put the patch (Export Patch in the app) in the folder patches_2_build/, then give its
# name. The plugin gets the name of the patch:
#
#   ./build_stripped.sh MyBass            patches_2_build/MyBass.aqua  ->  MyBass.lv2
#   ./build_stripped.sh MyEcho --fx       an effect (audio in -> audio out): MyEcho.lv2
#   ./build_stripped.sh                   lists the patches in patches_2_build/
#
#   --fx            build an effect instead of an instrument
#   --no-window     leave out the editor window too: smallest plugin, but then it can only
#                   be controlled through the 24 "DAW Mod" host parameters
#   --install       copy the result to ~/.lv2 as well
#   --jobs N        parallel compile jobs (default 2)
#   --init          no patch: build the app's Init patch as "Aqua Init" (a quick test)
#
# The full build must exist (./build_aquanode.sh): the stripped plugin takes its module
# code from that build's library. Nothing of the full build is changed, recompiled or
# removed: stripped plugins have their own build folder, build-stripped-<arch>/, and
# each result is added to ./dist-linux-<arch>/ next to what is already there.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="$ROOT/patches_2_build"

NAME=""
INIT=false
FX=false
WINDOW=true
INSTALL=false
JOBS=2

while [ $# -gt 0 ]; do
    case "$1" in
        --fx)       FX=true ;;
        --no-window) WINDOW=false ;;
        --install)  INSTALL=true ;;
        --init)     INIT=true ;;
        --jobs)     shift; JOBS="${1:?--jobs needs a number}" ;;
        -h|--help)  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)         echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
        *)          [ -z "$NAME" ] || { echo "Give one patch name (put names with spaces in quotes)" >&2; exit 2; }
                    NAME="${1%.aqua}" ;;
    esac
    shift
done

PATCH=""
if $INIT; then
    NAME="Aqua Init"
elif [ -z "$NAME" ]; then
    echo "Usage: ./build_stripped.sh <patch name> [--fx] [--install]   (--help for more)"
    echo
    echo "Patches in $PATCH_DIR:"
    found=false
    for f in "$PATCH_DIR"/*.aqua; do
        [ -f "$f" ] || continue
        found=true
        echo "  $(basename "$f" .aqua)"
    done
    $found || echo "  (none yet: export a patch from the app and copy the .aqua file there)"
    exit 2
else
    PATCH="$PATCH_DIR/$NAME.aqua"
    [ -f "$PATCH" ] || { echo "Patch not found: $PATCH" >&2; exit 1; }
fi

ARCH="$(uname -m)"
FULL_BUILD_DIR="$ROOT/build-linux-$ARCH"
BUILD_DIR="$ROOT/build-stripped-$ARCH"
SPECS_DIR="$BUILD_DIR/specs"
DIST_DIR="$ROOT/dist-linux-$ARCH"

# The full build's library is only read, never rebuilt.
FULL_LIB=""
if [ -d "$FULL_BUILD_DIR" ]; then
    FULL_LIB="$(find "$FULL_BUILD_DIR" -path '*AquanodeModular_artefacts*' -name '*SharedCode.a' 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$FULL_LIB" ]; then
    echo "The full build's library was not found under $FULL_BUILD_DIR." >&2
    echo "Run ./build_aquanode.sh first." >&2
    exit 1
fi

GEN_ARGS=(--out "$SPECS_DIR" --name "$NAME")
[ -z "$PATCH" ] || GEN_ARGS+=(--patch "$PATCH")
$FX && GEN_ARGS+=(--fx)
$WINDOW && GEN_ARGS+=(--window)
mkdir -p "$SPECS_DIR"
python3 "$ROOT/tools/make_stripped.py" "${GEN_ARGS[@]}"

SLUG="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')"
SPEC="$SPECS_DIR/$SLUG"
[ -f "$SPEC/stripped.cmake" ] || { echo "Generated files missing in $SPEC" >&2; exit 1; }

cmake -S "$ROOT/stripped" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DAQ_SPECS_DIR="$SPECS_DIR" \
    -DAQ_FULL_LIBRARY="$FULL_LIB" > "$BUILD_DIR/configure.log" 2>&1 \
    || { cat "$BUILD_DIR/configure.log"; exit 1; }

cmake --build "$BUILD_DIR" --target "$(cat "$SPEC/target.txt")" --parallel "$JOBS"

BUNDLE="$(cat "$SPEC/artefacts.txt")/$NAME.lv2"
[ -d "$BUNDLE" ] || { echo "Build finished but $BUNDLE is missing" >&2; exit 1; }

# Add the result to the dist folder; only a previous build of this same plugin is replaced.
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
