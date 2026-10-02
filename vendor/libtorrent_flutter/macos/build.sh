#!/bin/bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")" && pwd -P)"
output_dir="$1"
architecture="$2"
deployment_target="$3"
cache_dir="$output_dir/build"
openssl_version=3.6.5
openssl_sha256=a2157c2830efdec3788939b00c9b0638306d3f0bbb76dc4832ee503bb397df98
openssl_source="$cache_dir/openssl-$openssl_version"
openssl_install="$cache_dir/openssl-$openssl_version-install"
sdk_root="$(xcrun --sdk macosx --show-sdk-path)"

mkdir -p "$cache_dir"
if [ ! -d "$openssl_source" ]; then
  archive="$cache_dir/openssl-$openssl_version.tar.gz"
  curl --fail --location --retry 3 --retry-all-errors \
    "https://github.com/openssl/openssl/releases/download/openssl-$openssl_version/openssl-$openssl_version.tar.gz" \
    --output "$archive"
  printf '%s  %s\n' "$openssl_sha256" "$archive" | shasum -a 256 -c -
  tar -xzf "$archive" -C "$cache_dir"
fi

case "$architecture" in
  arm64) openssl_target=darwin64-arm64-cc ;;
  x86_64) openssl_target=darwin64-x86_64-cc ;;
  *) echo "Unsupported macOS architecture: $architecture" >&2; exit 1 ;;
esac

if [ ! -f "$openssl_install/lib/libssl.a" ]; then
  (
    cd "$openssl_source"
    ./Configure "$openssl_target" no-shared no-module no-tests \
      "--prefix=$openssl_install" --libdir=lib --openssldir=/etc/ssl \
      "-mmacosx-version-min=$deployment_target" "-isysroot$sdk_root"
    make -j4 build_libs
    make install_dev
  )
fi

cmake -S "$source_dir" -B "$cache_dir/native" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$openssl_install;$(brew --prefix boost)" \
  -DCMAKE_OSX_ARCHITECTURES="$architecture" \
  -DCMAKE_OSX_SYSROOT="$sdk_root" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
  -DOPENSSL_ROOT_DIR="$openssl_install" \
  -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$output_dir"
cmake --build "$cache_dir/native" --parallel 4
xcrun strip -x "$output_dir/liblibtorrent_flutter.dylib"
