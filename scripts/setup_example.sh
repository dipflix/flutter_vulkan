#!/usr/bin/env bash
# Copies compiled SPIR-V shaders from the main project into the Flutter example.
# Run after `./scripts/build_native.sh`.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SRC="$ROOT/assets/shaders"
DST="$SCRIPT_DIR/../example/assets/shaders"

mkdir -p "$DST"

for spv in mesh3d.vert.spv mesh3d.frag.spv; do
    if [ ! -f "$SRC/$spv" ]; then
        echo "Missing shader: $SRC/$spv"
        echo "Build the native libraries first: ./scripts/build_native.sh"
        exit 1
    fi
    cp "$SRC/$spv" "$DST/"
    echo "  Copied $spv"
done

echo "Shaders ready in $DST"
