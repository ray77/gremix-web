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
# -sFULL_ES2=1 is what makes it draw at all: Allegro's GL path uses client-side
# arrays, which real WebGL does not have, so without the emulation the build
# runs happily at 60 fps and paints nothing - no error anywhere.
# Do NOT add -sMAX_WEBGL_VERSION=2. It forces a WebGL2 context with different
# draw paths and was measured to run WORSE on real machines; the player-facing
# regression of 2026-07-29 was exactly this flag. FULL_ES2 alone reproduces the
# original loader to within a few hundred bytes (GLctx count 234).
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
    -sFULL_ES2=1 \
    -O2 --preload-file "$DATA"@data --lz4 --use-preload-cache \
    -o "$OUT/gremix.js"

echo "== link (JSPI)"
# Same game, second engine: with JSPI the JS engine suspends the blocking loop
# itself, without the ASYNCIFY instrumentation that made up a third of the
# binary and taxed every function. Not universal yet, so the page feature-
# detects (WebAssembly.Suspending) and falls back to the ASYNCIFY build.
emcc "$OUT/game.o" "$OUT/stubs.o" "${LIB[@]}" \
    -sUSE_SDL=2 -sJSPI -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=1048576 -sLZ4=1 \
    -sFULL_ES2=1 \
    -O2 --preload-file "$DATA"@data --lz4 --use-preload-cache \
    -o "$OUT/gremix_jspi.js"
# Both engines read the one gremix.data; the JSPI loader is retargeted and its
# duplicate package dropped.
# The cache key is a sha256 of the package content, so both engines land on the
# same IndexedDB entry by themselves - only the filename needs retargeting.
python3 - "$OUT" <<'PYEOF'
import sys
out = sys.argv[1]
p = out + '/gremix_jspi.js'
s = open(p, encoding='utf-8', errors='surrogateescape').read()
open(p, 'w', encoding='utf-8', errors='surrogateescape').write(s.replace('gremix_jspi.data', 'gremix.data'))
PYEOF
rm -f "$OUT/gremix_jspi.data"

echo "== done"
ls -la "$OUT"/gremix.js "$OUT"/gremix.wasm "$OUT"/gremix_jspi.js "$OUT"/gremix_jspi.wasm "$OUT"/gremix.data | awk '{printf "  %10d  %s\n", $5, $9}'
