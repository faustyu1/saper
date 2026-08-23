#!/bin/sh
# Builds zig-out/Saper.app with a universal (Apple Silicon + Intel) binary.
# macOS only; the Intel slice needs the SDK that xcrun points at.
set -e
cd "$(dirname "$0")"

sdk=$(xcrun --show-sdk-path)

zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-macos --sysroot "$sdk"
cp zig-out/bin/saper /tmp/saper-x86_64

zig build bundle -Doptimize=ReleaseSmall
cp zig-out/Saper.app/Contents/MacOS/saper /tmp/saper-arm64

lipo -create /tmp/saper-arm64 /tmp/saper-x86_64 -output zig-out/Saper.app/Contents/MacOS/saper
rm -f /tmp/saper-arm64 /tmp/saper-x86_64
codesign --force --deep --sign - zig-out/Saper.app 2>/dev/null || true

lipo -info zig-out/Saper.app/Contents/MacOS/saper
du -sh zig-out/Saper.app
