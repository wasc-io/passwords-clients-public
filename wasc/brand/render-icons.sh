#!/usr/bin/env bash
# Renders the placeholder brand SVGs into the committed browser icons and the macOS .icns.
# Requires ImageMagick 7 (`magick`) and python3. Re-run after changing an SVG and commit the output.
#   browser/  -> copied over apps/browser/src/images by webpack.base.js (same file names)
#   desktop/icon.icns -> mac.icon / dmg.icon in wasc/desktop/electron-builder.json
set -euo pipefail
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

render() { # svg bg size out [crop]
  sed "s/#111111/$2/" "$1" >"$tmp/in.svg"
  if [ "${5:-}" = crop ]; then
    magick -background none -density 96 "$tmp/in.svg" -crop 824x824+100+100 +repage \
      -resize "$3x$3" -strip "$4"
  else
    magick -background none -density 96 "$tmp/in.svg" -resize "$3x$3" -strip "$4"
  fi
}

mkdir -p browser desktop
for s in 16 19 32 38; do
  render icon-rounded.svg '#111111' "$s" "browser/icon$s.png" crop
  render icon-rounded.svg '#8a8a8a' "$s" "browser/icon${s}_gray.png" crop
done
for s in 48 96 128; do
  render icon-rounded.svg '#111111' "$s" "browser/icon$s.png"
  render icon-rounded.svg '#8a8a8a' "$s" "browser/icon${s}_gray.png"
done
for s in 19 38; do
  cp "browser/icon${s}_gray.png" "browser/icon${s}_locked.png"
done

# macOS .icns: PNG-payload entries (ic11..ic14, ic07..ic10).
for s in 32 64 128 256 512 1024; do
  render icon-rounded.svg '#111111' "$s" "$tmp/mac$s.png"
done
python3 - "$tmp" desktop/icon.icns <<'PY'
import struct, sys
tmp, out = sys.argv[1], sys.argv[2]
entries = [("ic11", 32), ("ic12", 64), ("ic07", 128), ("ic13", 256), ("ic08", 256),
           ("ic14", 512), ("ic09", 512), ("ic10", 1024)]
body = b""
for kind, size in entries:
    data = open(f"{tmp}/mac{size}.png", "rb").read()
    body += kind.encode() + struct.pack(">I", len(data) + 8) + data
open(out, "wb").write(b"icns" + struct.pack(">I", len(body) + 8) + body)
PY
echo "rendered browser/*.png and desktop/icon.icns"
