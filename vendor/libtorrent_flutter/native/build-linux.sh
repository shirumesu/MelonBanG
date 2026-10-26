#!/bin/bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")" && pwd -P)"
output_dir="$1"
architecture="$2"
cache_dir="$output_dir/build"
openssl_version=3.6.5
openssl_sha256=a2157c2830efdec3788939b00c9b0638306d3f0bbb76dc4832ee503bb397df98
openssl_source="$cache_dir/openssl-$openssl_version"
openssl_install="$cache_dir/openssl-$openssl_version-install"
# libtorrent uses Boost.JSON, newer than many distributions' Boost.
boost_version=1.92.0
boost_sha256=ea7b982002cc9dfbe59b0b217b206f470dc75f3de0bb2973d844118934d82411
boost_source="$cache_dir/boost-$boost_version"
boost_install="$cache_dir/boost-$boost_version-install"

mkdir -p "$cache_dir"
if [ ! -d "$openssl_source" ]; then
  archive="$cache_dir/openssl-$openssl_version.tar.gz"
  curl --fail --location --retry 3 --retry-all-errors \
    "https://github.com/openssl/openssl/releases/download/openssl-$openssl_version/openssl-$openssl_version.tar.gz" \
    --output "$archive"
  printf '%s  %s\n' "$openssl_sha256" "$archive" | sha256sum -c -
  tar -xzf "$archive" -C "$cache_dir"
fi

case "$architecture" in
  x86_64) openssl_target=linux-x86_64 ;;
  arm64) openssl_target=linux-aarch64 ;;
  *) echo "Unsupported Linux architecture: $architecture" >&2; exit 1 ;;
esac

# Linked into a shared library, so the static archives need -fPIC.
if [ ! -f "$openssl_install/lib/libssl.a" ]; then
  (
    cd "$openssl_source"
    ./Configure "$openssl_target" no-shared no-module no-tests -fPIC \
      "--prefix=$openssl_install" --libdir=lib --openssldir=/etc/ssl
    make -j"$(nproc)" build_libs
    make install_dev
  )
fi

if [ ! -d "$boost_source" ]; then
  archive="$cache_dir/boost-$boost_version.tar.xz"
  curl --fail --location --retry 3 --retry-all-errors \
    "https://github.com/boostorg/boost/releases/download/boost-$boost_version/boost-$boost_version-b2-nodocs.tar.xz" \
    --output "$archive"
  printf '%s  %s\n' "$boost_sha256" "$archive" | sha256sum -c -
  tar -xJf "$archive" -C "$cache_dir"
fi

# Only headers are used; installing the Boost.System stub also installs them
# with the CMake package files.
if [ ! -d "$boost_install/lib/cmake/boost_headers-$boost_version" ]; then
  (
    cd "$boost_source"
    ./bootstrap.sh
    ./b2 -d0 install "--prefix=$boost_install" --with-system link=static variant=release
  )
fi

cmake -S "$source_dir" -B "$cache_dir/bridge" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$openssl_install;$boost_install" \
  -DOPENSSL_ROOT_DIR="$openssl_install" \
  -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$output_dir"
cmake --build "$cache_dir/bridge" --parallel "$(nproc)"
strip --strip-unneeded "$output_dir/liblibtorrent_flutter.so"
