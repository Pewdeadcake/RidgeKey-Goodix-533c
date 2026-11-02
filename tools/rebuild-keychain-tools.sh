#!/bin/bash
set -euo pipefail
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = x86_64 ] || { echo 'Run on Intel macOS'; exit 1; }
root="$(cd "$(dirname "$0")/.." && pwd -P)"
src="$root/Source/RidgeKey/src"
for name in ridgekey-biostore-check ridgekey-biostore-reader; do
  reader_flag=''
  if [ "$name" = ridgekey-biostore-reader ]; then reader_flag=-DRK_PREFLIGHT_READER; fi
  xcrun clang -arch x86_64 -mmacosx-version-min=13.0 -std=c11 -Wall -Wextra -Werror \
    '-DRK_BIO_SERVICE="io.github.labrouss.ridgekey.goodix533c.preflight.v1"' ${reader_flag:+"$reader_flag"} \
    -I"$src/daemon" "$src/daemon/bio-keychain.c" "$src/tools/biostore-check.c" \
    -framework Security -framework CoreFoundation -o "$root/$name"
done
echo 'Synthetic preflight tools rebuilt locally (ignored by Git and the source manifest).'
