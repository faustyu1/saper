#!/bin/sh
# Regenerates every icon asset from src/icongen.zig.
# The PNG encoder in the repo writes uncompressed PNGs, so the files are run
# through sips afterwards purely to shrink them; the pixels do not change.
# macOS only, because iconutil ships with Xcode's command line tools.
set -e
cd "$(dirname "$0")/.."

zig build icon
for n in 16 32 64 128 256 512 1024; do
    sips -s format png "assets/icon_$n.png" --out "assets/icon_$n.png" >/dev/null
done

# The two mask layers belong to the Icon Composer document, not to the repo
# root, so move them in and drop the intermediates.
mkdir -p assets/Saper.icon/Assets
for layer in banner pole; do
    sips -s format png "assets/icon_layer_$layer.png" \
        --out "assets/Saper.icon/Assets/$layer.png" >/dev/null
    rm -f "assets/icon_layer_$layer.png"
done

work=$(mktemp -d)/Saper.iconset
mkdir -p "$work"
cp assets/icon_16.png   "$work/icon_16x16.png"
cp assets/icon_32.png   "$work/icon_16x16@2x.png"
cp assets/icon_32.png   "$work/icon_32x32.png"
cp assets/icon_64.png   "$work/icon_32x32@2x.png"
cp assets/icon_128.png  "$work/icon_128x128.png"
cp assets/icon_256.png  "$work/icon_128x128@2x.png"
cp assets/icon_256.png  "$work/icon_256x256.png"
cp assets/icon_512.png  "$work/icon_256x256@2x.png"
cp assets/icon_512.png  "$work/icon_512x512.png"
cp assets/icon_1024.png "$work/icon_512x512@2x.png"
iconutil -c icns "$work" -o assets/Saper.icns

python3 - <<'PY'
import struct
sizes = [16, 32, 64, 128, 256]
entries, blob = [], b''
offset = 6 + 16 * len(sizes)
for n in sizes:
    data = open(f'assets/icon_{n}.png', 'rb').read()
    side = 0 if n >= 256 else n
    entries.append(struct.pack('<BBBBHHII', side, side, 0, 0, 1, 32, len(data), offset))
    offset += len(data)
    blob += data
open('assets/saper.ico', 'wb').write(
    struct.pack('<HHH', 0, 1, len(sizes)) + b''.join(entries) + blob)
PY

# macOS 26 layered icon: Icon Composer document -> Assets.car (+ a legacy .icns
# rendered from the same document, which replaces the iconutil one above).
# Needs Xcode; without it the flat .icns built above is used on its own.
if xcrun --find actool >/dev/null 2>&1; then
    out=$(mktemp -d)
    xcrun actool assets/Saper.icon \
        --compile "$out" \
        --platform macosx \
        --minimum-deployment-target 26.0 \
        --app-icon Saper \
        --output-partial-info-plist "$out/partial.plist" \
        --optimization space \
        --compress-pngs >/dev/null
    cp "$out/Assets.car" assets/Assets.car
    cp "$out/Saper.icns" assets/Saper.icns
    echo "layered icon compiled (Assets.car)"
else
    echo "actool not found - keeping the flat icon only"
fi

echo "icons rebuilt"
