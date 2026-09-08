#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
cd "$(pwd -P)"

brew_prefix="$(brew --prefix)"
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$brew_prefix;$brew_prefix/opt/openssl@3" \
  -DCMAKE_OSX_ARCHITECTURES="$(uname -m)" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DCMAKE_INSTALL_PREFIX="$PWD/Libraries"
cmake --build build --parallel 4
cmake --install build

# Keep the native dependency closure inside the app, independent of Homebrew.
for library in Libraries/*.dylib; do
  [ -L "$library" ] && continue
  chmod u+w "$library"
  install_name_tool -id "@rpath/$(basename "$library")" "$library"
  while IFS= read -r dependency; do
    case "$dependency" in
      "$brew_prefix"/*)
        install_name_tool -change "$dependency" \
          "@loader_path/$(basename "$(realpath "$dependency")")" "$library"
        ;;
      @loader_path/*)
        install_name_tool -change "$dependency" \
          "@loader_path/$(basename "$(realpath "Libraries/${dependency##*/}")")" "$library"
        ;;
    esac
  done < <(otool -L "$library" | tail -n +2 | awk '{print $1}')
  codesign --force --sign - "$library"
done

# CocoaPods resolves symlinks before embedding, so reference only real filenames.
for library in Libraries/*.dylib; do
  if [ -L "$library" ]; then rm "$library"; fi
done
