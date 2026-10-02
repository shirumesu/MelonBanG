#!/bin/bash
set -euo pipefail

case "$ARCHS" in
  arm64|x86_64) ;;
  *) exit 0 ;;
esac

for framework in "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"/*.framework; do
  name="$(basename "$framework" .framework)"
  binary="$framework/Versions/Current/$name"
  [ -f "$binary" ] || continue
  architectures="$(xcrun lipo -archs "$binary")"
  [ "$architectures" != "$ARCHS" ] || continue

  xcrun lipo "$binary" -thin "$ARCHS" -output "$binary"
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
    --preserve-metadata=identifier,entitlements,flags "$framework"
done
