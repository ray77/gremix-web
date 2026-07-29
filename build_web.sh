#!/usr/bin/env bash
# Build Ghouls'n Ghosts Remix for the browser.
#
# RECONSTRUCTED on 2026-07-29. The original command was never written down and
# the working directory that held it was cleaned up; this was derived from the
# surviving environment and verified by building - it compiles and links. What
# environment and verified by building AND by looking at the result.
#
# The game is one translation unit: game.cpp includes everything under class/.
# It runs on Allegro 4 through Allegro-Legacy, which itself sits on Allegro 5,
# so both are linked. midia5_web_stubs.c replaces Legacy's MIDI player with a
# TinySoundFont softsynth fed into an A5 audio stream.
#
# --lz4 packs the assets and -sLZ4=1 links the decompressor that reads them;
# one without the other silently does nothing. This is what makes the download
# bearable: the assets are uncompressed BMPs,
# 170 MB of them, and they pack down to about 26 MB. Without it the browser
# would fetch the lot raw.
#
# -sFULL_ES2=1 -sMAX_WEBGL_VERSION=2 are what make it draw at all. Without them
# the build runs perfectly happily at 60 fps with a WebGL context and paints
# nothing: too few GL entry points are linked, and no error is raised anywhere.
# A build that runs is not a build that works - check the picture.
#
# ASYNCIFY, because the game keeps a blocking Allegro 4 style loop.
# -sUSE_SDL=2 is not optional: the Allegro 5 in prefix/ was built against SDL,
# and without it the link fails on SDL_OpenAudioDevice and friends.
#
# Usage: ./build_web.sh [data-dir]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AW="${ALLEGRO_WEB:-$HOME/Developer/allegro-web}"
DATA="${1:-$HOME/Downloads/g_remix/data}"
OUT="$HERE/out"

if ! command -v emcc >/dev/null; then
    # shellcheck disable=SC1091
    source "${EMSDK:-$HOME/Developer/emsdk}/emsdk_env.sh" >/dev/null 2>&1 || {
        echo "emcc not found - source emsdk_env.sh or set EMSDK" >&2; exit 1; }
fi
for p in "$AW/Allegro-Legacy/build-web/lib/liballeg.a" "$AW/prefix/lib/liballegro-static.a" \
         "$AW/midia5_web_stubs.c" "$AW/tsf.h"; do
    [ -e "$p" ] || { echo "missing: $p" >&2; exit 1; }
done
[ -d "$DATA" ] || { echo "no data directory: $DATA" >&2; exit 1; }

INC=(-I"$AW/Allegro-Legacy/include" -I"$AW/Allegro-Legacy/build-web/include"
     -I"$AW/prefix/include" -I"$AW")
LIB=(-L"$AW/Allegro-Legacy/build-web/lib" -L"$AW/prefix/lib"
     -lalleg
     -lallegro_acodec-static -lallegro_audio-static -lallegro_image-static
     -lallegro_font-static -lallegro_primitives-static -lallegro_color-static
     -lallegro_memfile-static -lallegro_main-static -lallegro-static)

mkdir -p "$OUT"
echo "== stubs (C)"
emcc -c "$AW/midia5_web_stubs.c" -w -O2 "${INC[@]}" -o "$OUT/stubs.o"

echo "== game (C++98)"
emcc -c "$HERE/src/game.cpp" -std=gnu++98 -w -O2 "${INC[@]}" -o "$OUT/game.o"

echo "== link"
emcc "$OUT/game.o" "$OUT/stubs.o" "${LIB[@]}" \
    -sUSE_SDL=2 -sASYNCIFY -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=1048576 -sLZ4=1 \
    -sFULL_ES2=1 -sMAX_WEBGL_VERSION=2 \
    -O2 --preload-file "$DATA"@data --lz4 \
    -o "$OUT/gremix.js"

echo "== done"
ls -la "$OUT"/gremix.js "$OUT"/gremix.wasm "$OUT"/gremix.data | awk '{printf "  %10d  %s\n", $5, $9}'
