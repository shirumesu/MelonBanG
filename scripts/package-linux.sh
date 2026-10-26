#!/bin/bash
# Builds the Linux release files into dist/:
#   MelonBanG-<version>-linux-x64.AppImage  the app; also the update package
#   manifest.json (+ manifest.json.sig)     what the in-app updater trusts
#
#   scripts/package-linux.sh [-c service-configuration.json] [-k signing-key.pem]
#
# Build on the oldest supported distribution (Ubuntu 22.04): the AppImage
# runs where its glibc is at least as new. Needs jq, patchelf, curl and the
# build packages listed in the README.
#
# The AppImage carries libmpv with its codecs and everything else the
# program links, except what any desktop with GTK 3 already has: libraries
# GTK itself links, and those AppImage's exclude list leaves to the system.
# The VA-API and VDPAU loaders come from the system so that its GPU drivers
# match them; the bundled copies are only used where the system has none.
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
jq -e 'type == "object"' "$configuration" >/dev/null 2>&1 ||
  fail 'Service configuration must be a valid JSON object; use .env.service.example.json as the template.'
for key in BANGUMI_CLIENT_ID DANDANPLAY_APP_ID DANDANPLAY_APP_SECRET; do
  value=$(jq -r --arg key "$key" '.[$key] // ""' "$configuration")
  [[ -n ${value//[[:space:]]/} ]] || fail "Missing build setting $key. Fill $configuration."
done
version=$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/p' pubspec.yaml)
flutter=${FLUTTER_ROOT:+$FLUTTER_ROOT/bin/}flutter

"$flutter" pub get
"$flutter" build linux --release \
  "--dart-define=MELONBANG_VERSION=$version" \
  "--dart-define-from-file=$configuration"

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
app=$staging/MelonBanG.AppDir
cp -a build/linux/x64/release/bundle "$app"
mkdir -p "$app/licenses" "$app/lib/fallback"
cp LICENSE THIRD_PARTY.md "$app/licenses/"
for plugin in media_kit_video libtorrent_flutter; do
  cp "vendor/$plugin/LICENSE" "$app/licenses/$plugin.txt"
done

# Pinned: a later list may start or stop excluding a library.
excludelist=$(curl --fail --silent --show-error --location --retry 3 \
  https://raw.githubusercontent.com/AppImageCommunity/pkg2appimage/19e30b276ffedf4d3b4b56bc6320f463625a74f8/excludelist |
  sed -e 's/#.*//' -e 's/[[:space:]]//g' | grep -v '^$')
gtk=$(ldconfig -p | awk '$1 == "libgtk-3.so.0" { print $NF; exit }')
[[ -n $gtk ]] || fail 'libgtk-3 is not installed.'
system=$(printf '%s\n' "$excludelist" libgtk-3.so.0 $(ldd "$gtk" | awk '{ print $1 }'))
fallback='^lib(va|va-drm|va-x11|va-wayland|vdpau)\.so'

objects=("$app/melonbang" "$app"/lib/*.so)
ldd "${objects[@]}" | awk '$2 == "=>" && $3 ~ /^\// { print $1, $3 }' | sort -u |
  while read -r name path; do
    if grep -qxF "$name" <<<"$system"; then continue; fi
    if [[ $name =~ $fallback ]]; then
      cp -L "$path" "$app/lib/fallback/$name"
    elif [[ ! -e $app/lib/$name ]]; then
      cp -L "$path" "$app/lib/$name"
    fi
  done
ldd "${objects[@]}" "$app"/lib/*.so* 2>/dev/null | grep 'not found' &&
  fail 'A bundled library has a missing dependency.'
# Each library finds its neighbours; the program already looks in lib/.
for library in "$app"/lib/*.so* "$app"/lib/fallback/*.so*; do
  chmod u+w "$library"
  patchelf --set-rpath '$ORIGIN' "$library"
done

cp linux/packaging/melonbang.desktop "$app/"
cp linux/packaging/melonbang.png "$app/melonbang.png"
ln -s melonbang.png "$app/.DirIcon"
cat >"$app/AppRun" <<'EOF'
#!/bin/sh
here=$(dirname "$(readlink -f "$0")")
# Bundled VA-API and VDPAU loaders only where the system has none.
if ! /sbin/ldconfig -p 2>/dev/null | grep -q 'libva\.so\.2 '; then
  export LD_LIBRARY_PATH="$here/lib/fallback${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
exec "$here/melonbang" "$@"
EOF
chmod 755 "$app/AppRun"

appimagetool=$staging/appimagetool
curl --fail --silent --show-error --location --retry 3 --output "$appimagetool" \
  https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
printf '%s  %s\n' ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0 "$appimagetool" |
  sha256sum -c - >/dev/null
chmod 755 "$appimagetool"

dist=$project/dist
rm -rf "$dist"
mkdir "$dist"
image_name=MelonBanG-$version-linux-x64.AppImage
image=$dist/$image_name
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$appimagetool" --no-appstream "$app" "$image"

size=$(stat -c %s "$image")
digest=$(sha256sum "$image" | cut -d' ' -f1)
manifest=$dist/manifest.json
printf '{"version":"%s","platforms":{"linux-x64":{"urls":["https://github.com/shirumesu/MelonBanG/releases/download/v%s/%s"],"sha256":"%s","size":%s}}}' \
  "$version" "$version" "$image_name" "$digest" "$size" >"$manifest"
if [[ -n $signing_key ]]; then
  openssl dgst -sha256 -sign "$signing_key" -out "$manifest.sig" "$manifest"
else
  echo 'No signing key: the in-app updater will not accept this release.' >&2
fi
ls -1 "$dist"/*
