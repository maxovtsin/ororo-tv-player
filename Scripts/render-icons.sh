#!/usr/bin/env bash
# Renders every brand PNG (tvOS icon layers, App Store icon, Top Shelf, iOS icon, in-app
# Wordmark) from Branding/brand.html with headless Chrome, straight into the asset catalogs.
#
#   Scripts/render-icons.sh
#
# Idempotent: rerun after tweaking Branding/brand.html and commit the regenerated PNGs.
# Override the browser with CHROME=/path/to/chrome.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAGE="$ROOT/Branding/brand.html"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
TV="$ROOT/Apps/TV/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
IOS="$ROOT/Apps/iOS/Assets.xcassets/AppIcon.appiconset"
WORDMARK="$ROOT/Packages/OroroUI/Sources/OroroFeatures/Resources/Brand.xcassets/Wordmark.imageset"

if [[ ! -x "$CHROME" ]]; then
  echo "error: Google Chrome not found at $CHROME (set CHROME=/path/to/chrome)" >&2
  exit 1
fi

PROFILE="$(mktemp -d)"
trap 'rm -rf "$PROFILE"' EXIT

# Drops the alpha channel of an 8-bit RGBA PNG in place (App Store icons and tvOS back layers
# must be opaque). Plain stdlib Python, so it runs on a stock Mac.
flatten() {
  python3 -I - "$1" <<'PY'
import struct, sys, zlib
path = sys.argv[1]
data = open(path, "rb").read()
pos, ihdr, idat = 8, None, b""
while pos < len(data):
    n, kind = struct.unpack(">I4s", data[pos:pos + 8])
    body = data[pos + 8:pos + 8 + n]
    if kind == b"IHDR": ihdr = body
    elif kind == b"IDAT": idat += body
    pos += 12 + n
w, h, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", ihdr)
if color == 2: sys.exit(0)  # already RGB
assert depth == 8 and color == 6 and interlace == 0, "expected 8-bit non-interlaced RGBA"
raw, stride, bpp = zlib.decompress(idat), w * 4, 4
prev, out, i = bytearray(stride), bytearray(), 0
for _ in range(h):
    f, line = raw[i], bytearray(raw[i + 1:i + 1 + stride]); i += 1 + stride
    for x in range(stride):
        a = line[x - bpp] if x >= bpp else 0
        b = prev[x]
        c = prev[x - bpp] if x >= bpp else 0
        if f == 1: line[x] = (line[x] + a) & 255
        elif f == 2: line[x] = (line[x] + b) & 255
        elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
        elif f == 4:
            p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
    prev = line
    out.append(0)
    for x in range(0, stride, 4):
        assert line[x + 3] == 255, "back layer is not opaque"
        out += line[x:x + 3]
def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) \
    + chunk(b"IDAT", zlib.compress(bytes(out), 9)) + chunk(b"IEND", b"")
open(path, "wb").write(png)
PY
}

# render <art> <layer> <width> <height> <scale> <output>
render() {
  local art=$1 layer=$2 w=$3 h=$4 scale=$5 out=$6
  mkdir -p "$(dirname "$out")"
  "$CHROME" --headless=new --hide-scrollbars --allow-file-access-from-files \
    --user-data-dir="$PROFILE" --default-background-color=00000000 \
    --window-size="$w,$h" --force-device-scale-factor="$scale" --virtual-time-budget=5000 \
    --screenshot="$out" "file://$PAGE?art=$art&layer=$layer&w=$w&h=$h" >/dev/null 2>&1
  [[ -s "$out" ]] || { echo "error: Chrome did not write $out" >&2; exit 1; }
  if [[ $layer == back || $art == ios ]]; then flatten "$out"; fi
  echo "  ${out#"$ROOT/"}"
}

echo "Rendering brand artwork:"
for layer in Back Middle Front; do
  l=$(echo "$layer" | tr '[:upper:]' '[:lower:]')
  dir="$TV/App Icon.imagestack/$layer.imagestacklayer/Content.imageset"
  render icon "$l" 400 240 1 "$dir/icon@1x.png"
  render icon "$l" 400 240 2 "$dir/icon@2x.png"
  render appstore "$l" 1280 768 1 "$TV/App Icon - App Store.imagestack/$layer.imagestacklayer/Content.imageset/icon-appstore.png"
done
render topshelf flat 1920 720 1 "$TV/Top Shelf Image.imageset/topshelf@1x.png"
render topshelf flat 1920 720 2 "$TV/Top Shelf Image.imageset/topshelf@2x.png"
render topshelfwide flat 2320 720 1 "$TV/Top Shelf Image Wide.imageset/topshelf-wide@1x.png"
render topshelfwide flat 2320 720 2 "$TV/Top Shelf Image Wide.imageset/topshelf-wide@2x.png"
render ios flat 1024 1024 1 "$IOS/AppIcon-1024.png"
for scale in 1 2 3; do
  render wordmark front 600 200 "$scale" "$WORDMARK/wordmark@${scale}x.png"
done
echo "Done."
