#!/bin/bash
set -euo pipefail
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != x86_64 ]; then echo 'Run on Intel Dell macOS.'; exit 1; fi
if [ "$(id -u)" = 0 ]; then echo 'Run this command as your normal GUI user, without sudo.'; exit 1; fi
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
cd "$script_dir"
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != x86_64 ]; then echo 'Run on Intel Dell macOS.'; exit 1; fi
source "$script_dir/kit-common.sh"
kit="$(rk_script_kit "$script_dir" build)"
rk_localize "$kit" Check-Keychain.command
shasum -a 256 -c SHA256SUMS >/dev/null
if [ ! -x "$kit/ridgekey-biostore-check" ] || [ ! -x "$kit/ridgekey-biostore-reader" ]; then
  echo 'Building synthetic Keychain tools from source (requires Xcode Command Line Tools).'
  bash "$kit/tools/rebuild-keychain-tools.sh"
fi
tool="$kit/ridgekey-biostore-check"
reader="$kit/ridgekey-biostore-reader"
chmod u+x "$tool" "$reader"
report="$kit/Keychain-$(date +%Y%m%d-%H%M%S).txt"
cleanup() { sudo -n "$tool" --delete >/dev/null 2>&1 || true; }
trap cleanup EXIT
sudo -v
{
  echo '533c Keychain preflight: synthetic 1 MiB + 4096 bytes, no fingerprint/password storage.'
  sudo "$tool" --write || exit $?
  sudo "$reader" --read || exit $?
  "$reader" --deny-user || exit $?
  sudo "$tool" --delete || exit $?
  echo 'KEYCHAIN_PREFLIGHT=PASS'
} 2>&1 | tee "$report"
trap - EXIT
echo "Report: $report"
