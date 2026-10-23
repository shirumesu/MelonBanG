#!/bin/bash
# Builds the macOS release files into dist/:
#   MelonBanG-<version>-macos-arm64.dmg  disk image to drag into Applications
#   MelonBanG-<version>-macos-arm64.zip  the app bundle; the update package
#   manifest.json (+ manifest.json.sig)  what the in-app updater trusts
#
#   scripts/package-macos.sh [-c service-configuration.json] [-k signing-key.pem]
#
# Without -k the manifest is unsigned and the in-app updater will not accept
# the release.
set -euo pipefail

configuration=.env.service.json
signing_key=
while getopts 'c:k:' option; do
  case $option in
    c) configuration=$OPTARG ;;
    k) signing_key=$OPTARG ;;
    *) exit 2 ;;
  esac
done

fail() {
  echo "$1" >&2
  exit 1
}

project=$(cd "$(dirname "$0")/.." && pwd)
cd "$project"
[[ -f $configuration ]] ||
  fail 'Copy .env.service.example.json to .env.service.json and fill the service registrations, or pass -c.'
configuration=$(cd "$(dirname "$configuration")" && pwd)/$(basename "$configuration")
plutil -convert json -o /dev/null "$configuration" 2>/dev/null ||
  fail 'Service configuration must be a valid JSON object; use .env.service.example.json as the template.'
for key in BANGUMI_CLIENT_ID DANDANPLAY_APP_ID DANDANPLAY_APP_SECRET; do
  value=$(plutil -extract "$key" raw -o - "$configuration" 2>/dev/null || true)
  [[ -n ${value//[[:space:]]/} ]] || fail "Missing build setting $key. Fill $configuration."
done
version=$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/p' pubspec.yaml)
flutter=${FLUTTER_ROOT:+$FLUTTER_ROOT/bin/}flutter

"$flutter" pub get
"$flutter" build macos --release \
  "--dart-define=MELONBANG_VERSION=$version" \
  "--dart-define-from-file=$configuration"

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
app=$staging/MelonBanG.app
ditto build/macos/Build/Products/Release/melonbang.app "$app"
resources=$app/Contents/Resources
cp LICENSE THIRD_PARTY.md "$resources/"
mkdir "$resources/licenses"
for plugin in media_kit_video libtorrent_flutter; do
  cp "vendor/$plugin/LICENSE" "$resources/licenses/$plugin.txt"
done

# A local build carries whatever identity Signing.local.xcconfig names, with
# its development entitlements. Releases are ad-hoc signed on every machine;
# without a Developer ID there is nothing for Gatekeeper to trust anyway.
for framework in "$app"/Contents/Frameworks/*.framework; do
  codesign --force --sign - --timestamp=none "$framework"
done
codesign --force --sign - --timestamp=none \
  --entitlements macos/Runner/Release.entitlements "$app"
codesign --verify --deep --strict "$app"

dist=$project/dist
rm -rf "$dist"
mkdir "$dist"
archive_name=MelonBanG-$version-macos-arm64.zip
archive=$dist/$archive_name
# ditto keeps the frameworks' symbolic links, which the signatures cover.
ditto -c -k --keepParent "$app" "$archive"

image=$staging/image
mkdir "$image"
mv "$app" "$image/"
ln -s /Applications "$image/Applications"
hdiutil create -quiet -volname MelonBanG -srcfolder "$image" -format ULFO \
  "$dist/MelonBanG-$version-macos-arm64.dmg"

size=$(stat -f %z "$archive")
digest=$(shasum -a 256 "$archive" | cut -d' ' -f1)
manifest=$dist/manifest.json
printf '{"version":"%s","platforms":{"macos-arm64":{"urls":["https://github.com/shirumesu/MelonBanG/releases/download/v%s/%s"],"sha256":"%s","size":%s}}}' \
  "$version" "$version" "$archive_name" "$digest" "$size" >"$manifest"
if [[ -n $signing_key ]]; then
  openssl dgst -sha256 -sign "$signing_key" -out "$manifest.sig" "$manifest"
else
  echo 'No signing key: the in-app updater will not accept this release.' >&2
fi
ls -1 "$dist"/*
