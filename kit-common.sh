#!/bin/bash
# SPDX-License-Identifier: MIT -- script paths, not biometric storage paths.
rk_is_kit() {
  [ -f "$1/Source/RidgeKey/ci/build-libfprint-macos.sh" ] && [ -d "$1/Source/libfprint" ]
}
rk_script_kit() {
  local dir="$1" mode="${2:-use}" parent child
  rk_is_kit "$dir" || { echo "Not a complete RidgeKey source kit: $dir" >&2; return 1; }
  if [ "$mode" = use ] && [ ! -f "$dir/bundle-path.txt" ]; then
    parent=$(dirname "$dir")
    if rk_is_kit "$parent" && [ -f "$parent/bundle-path.txt" ]; then
      echo "Using completed build in parent kit: $parent" >&2
      dir="$parent"
    else
      child="$dir/XPS-RidgeKey-533c-Lab"
      if rk_is_kit "$child" && [ -f "$child/bundle-path.txt" ]; then
        echo "Using completed build in nested kit: $child" >&2
        dir="$child"
      fi
    fi
  fi
  printf '%s\n' "$dir"
}
rk_localize() {
  local source="$1" command="$2" destination
  case "$source" in
    /Volumes/*)
      destination="$HOME/XPS-RidgeKey-533c-Lab"
      shasum -a 256 -c "$source/SHA256SUMS" >/dev/null
      if [ -e "$destination" ]; then
        if rk_is_kit "$destination" && cmp -s "$source/SHA256SUMS" "$destination/SHA256SUMS"; then
          echo "Using existing internal copy: $destination" >&2
        else
          echo "An older/different local kit exists: $destination. Apply the fix there or run its command; no files overwritten." >&2
          return 1
        fi
      else
        mkdir -p "$destination"
        ditto "$source" "$destination"
      fi
      echo "LOCAL_COPY_READY: $destination (USB no longer required)" >&2
      exec /bin/bash "$destination/$command"
      ;;
  esac
}
