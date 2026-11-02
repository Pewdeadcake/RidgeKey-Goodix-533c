#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
target=${1:?Agent app path required}
codesign --verify --strict "$target" || { echo 'AGENT_SIGNATURE_VERIFY=FAIL'; exit 1; }
if ! info=$(codesign --display --verbose=4 "$target" 2>&1); then
  printf '%s\n' "$info"; echo 'AGENT_SIGNATURE_DISPLAY=FAIL'; exit 1
fi
# Drain codesign completely before inspecting it. grep -q in a pipe can
# close its input early and turn a successful producer into SIGPIPE/141.
printf '%s\n' "$info"
count=0
flags=''
while IFS= read -r line; do
  if [[ "$line" =~ ^CodeDirectory.*flags=0x([0-9a-fA-F]+) ]]; then
    flags=${BASH_REMATCH[1]}
    count=$((count + 1))
  fi
done <<< "$info"
if [ "$count" != 1 ]; then echo 'AGENT_SIGNATURE_FLAGS=UNREADABLE'; exit 1; fi
# Match the exact CS_RUNTIME bit required by RidgeKey's daemon peer.c.
if [ "$((16#$flags & 0x10000))" = 0 ]; then
  echo "AGENT_SIGNATURE_RUNTIME=FAIL flags=0x$flags"; exit 1
fi
echo "AGENT_SIGNATURE_RUNTIME=PASS flags=0x$flags"
