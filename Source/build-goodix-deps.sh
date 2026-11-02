#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
: "${WORK:?Run Build.command}" "${PREFIX:?Run Build.command}"
fetch_pin() {
  local name=$1 url=$2 tag=$3 pin=$4 target="$WORK/$1"
  if [ ! -d "$target/.git" ]; then
    [ ! -e "$target" ] || { echo "Unexpected existing directory: $target"; exit 1; }
    git clone --depth 1 --branch "$tag" "$url" "$target"
  fi
  [ "$(git -C "$target" rev-parse HEAD)" = "$pin" ] || { echo "Wrong source revision: $name"; exit 1; }
}
fetch_pin openssl https://github.com/openssl/openssl.git openssl-3.5.9 45e844fa2a14ec92d146bd8f5778ac130b6625fb
if [ ! -f "$PREFIX/lib/pkgconfig/openssl.pc" ]; then
  ( cd "$WORK/openssl"
    perl Configure darwin64-x86_64-cc shared no-tests --prefix="$PREFIX" --libdir=lib
    make -j"$(sysctl -n hw.ncpu)"
    make install_sw )
fi
fetch_pin libdeflate https://github.com/ebiggers/libdeflate.git v1.26 92e6a0db9fa848d742f9eb286c92afc60f2c3dda
cmake -S "$WORK/libdeflate" -B "$WORK/libdeflate-build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
  -DLIBDEFLATE_BUILD_SHARED_LIB=ON -DLIBDEFLATE_BUILD_STATIC_LIB=OFF -DLIBDEFLATE_BUILD_GZIP=OFF
cmake --build "$WORK/libdeflate-build" --parallel "$(sysctl -n hw.ncpu)"
cmake --install "$WORK/libdeflate-build"
pkg-config --exists openssl libdeflate
echo "Goodix dependencies: OpenSSL $(pkg-config --modversion openssl), libdeflate $(pkg-config --modversion libdeflate)"
