#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
VERSION=4.1
SOURCE_SHA=537b2ade623cb94b6edddfa5c61bf0b0af21484aa8365ea2531b686ea573249a
SERVER_SHA=deacb991ed2509715160ffdc7907e47b4160eb30d1566217e9047fd5b8850cae
CACHE="$ROOT/.build/vendor"
NATIVE="$ROOT/.build/native"
mkdir -p "$CACHE" "$NATIVE"
for tool in meson ninja pkg-config python3; do
  command -v "$tool" >/dev/null || { echo "Missing build tool: $tool" >&2; exit 1; }
done
fetch_verified() {
  local url="$1" dest="$2" hash="$3"
  if [[ ! -f "$dest" ]]; then curl -fL --retry 2 "$url" -o "$dest"; fi
  if [[ "$(shasum -a 256 "$dest" | cut -d ' ' -f1)" != "$hash" ]]; then
    echo "Checksum mismatch: $dest" >&2; exit 1
  fi
}
fetch_verified "https://github.com/Genymobile/scrcpy/archive/refs/tags/v${VERSION}.tar.gz" "$CACHE/scrcpy-${VERSION}.tar.gz" "$SOURCE_SHA"
fetch_verified "https://github.com/Genymobile/scrcpy/releases/download/v${VERSION}/scrcpy-server-v${VERSION}" "$CACHE/scrcpy-server-v${VERSION}" "$SERVER_SHA"
tar -xzf "$CACHE/scrcpy-${VERSION}.tar.gz" -C "$NATIVE"
SRC="$NATIVE/scrcpy-${VERSION}"
cp "$ROOT/Native/launcher.c" "$SRC/app/src/launcher.c"
python3 - "$SRC" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
def patch(name, before, after):
    path = root / name
    text = path.read_text()
    if text.count(before) != 1:
        raise SystemExit(f'Unexpected upstream source: {name}')
    path.write_text(text.replace(before, after))
patch('app/meson.build', "'src/main.c',", "'src/launcher.c',")
patch('app/meson.build', "executable('scrcpy', src,", "shared_library('scrcpy-client', src,")
patch('app/src/scrcpy.c', '    atexit(SDL_Quit);', '    // SDL is released by the host after each session.')
patch('app/src/scrcpy.c', '    static struct scrcpy scrcpy;', '    static struct scrcpy scrcpy;\n    memset(&scrcpy, 0, sizeof(scrcpy));')
patch('app/src/sdl_hints.c', 'SDL_HINT_APP_NAME, "scrcpy"', 'SDL_HINT_APP_NAME, "Scrcpy Launcher"')
patch('app/src/events.h', '    SC_EVENT_DISCONNECTED_TIMEOUT,',
      '    SC_EVENT_DISCONNECTED_TIMEOUT,\n    SC_EVENT_LAUNCHER_POWER,')
patch('app/src/input_manager.c', '''        case SC_EVENT_DEVICE_DISCONNECTED:
            sc_input_manager_on_device_disconnected(im);''', '''        case SC_EVENT_LAUNCHER_POWER:
            if (im->controller && im->kp && !im->camera && !im->disconnected) {
                action_power(im, SC_ACTION_DOWN);
                action_power(im, SC_ACTION_UP);
            }
            break;
        case SC_EVENT_DEVICE_DISCONNECTED:
            sc_input_manager_on_device_disconnected(im);''')
# SDL's Cocoa backend replaces NSApp's icon here. Keep the bundle ICNS as
# the single source for the Dock icon before, during, and after mirroring.
patch('app/src/screen.c', '''        if (!SDL_SetWindowIcon(screen->window, icon)) {
            LOGW("Could not set window icon: %s", SDL_GetError());
        }''', '''#ifndef __APPLE__
        if (!SDL_SetWindowIcon(screen->window, icon)) {
            LOGW("Could not set window icon: %s", SDL_GetError());
        }
#endif''')
PY
ARGS=(--buildtype=release -Dcompile_server=false -Dusb=true -Db_lto=true)
if [[ -d "$NATIVE/meson/meson-private" ]]; then
  meson setup --reconfigure "$NATIVE/meson" "$SRC" "${ARGS[@]}"
else
  meson setup "$NATIVE/meson" "$SRC" "${ARGS[@]}"
fi
meson compile -C "$NATIVE/meson"
echo "Built embedded scrcpy ${VERSION} client"
