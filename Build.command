#!/bin/bash
set -euo pipefail
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != x86_64 ]; then echo 'Run on Intel Dell macOS.'; exit 1; fi
if [ "$(id -u)" = 0 ]; then echo 'Run this command as your normal GUI user, without sudo.'; exit 1; fi
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
cd "$script_dir"
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != x86_64 ]; then echo 'Build on the Intel Dell in macOS.'; exit 1; fi
source "$script_dir/kit-common.sh"
kit="$(rk_script_kit "$script_dir" build)"
rk_localize "$kit" Build.command
shasum -a 256 -c SHA256SUMS >/dev/null
export WORK="$HOME/Library/Caches/XPS-RidgeKey-533c-lab1"
export PREFIX="$WORK/prefix"
export DIST="$kit/Build-Output"
export FORCE_PKGCONF=1
mkdir -p "$WORK" "$DIST"
report="$kit/Build-$(date +%Y%m%d-%H%M%S).txt"
set +e
(
  set -Eeuo pipefail
  trap 'rk_error=$?; printf "BUILD_ERROR line=%s status=%s\n" "$LINENO" "$rk_error" >&2; exit "$rk_error"' ERR
  xcode-select -p >/dev/null || { echo 'Install Command Line Tools: xcode-select --install'; exit 1; }
  for tool in clang swift python3 git make perl codesign; do command -v "$tool" >/dev/null || { echo "Missing tool: $tool"; exit 1; }; done
  echo 'Preparing private Python build tools (existing downloads/cache are retained).'
  python3 -m venv "$WORK/tools-venv"
  export PATH="$WORK/tools-venv/bin:$PATH"
  python3 -m pip install 'meson==1.7.2' 'ninja==1.11.1.4' 'packaging==24.2' 'cmake==3.31.6'
  bash "$kit/Source/RidgeKey/ci/build-libfprint-macos.sh"
) 2>&1 | tee "$report"
rc=${PIPESTATUS[0]}
set -e
echo "BUILD_EXIT=$rc; report: $report" | tee -a "$report"
if [ "$rc" != 0 ]; then echo 'Build failed; installation is not ready. Send this complete report.' | tee -a "$report"; exit "$rc"; fi
bundle="$WORK/bundle/ridgekey-1.0.5331-macos-x86_64"
grep -qi '^27c6:533c ' "$bundle/supported-devices.txt"
printf '%s\n' "$bundle" > "$kit/bundle-path.txt"
echo "BUILD_COMPLETE. Nothing installed. Next: bash \"$kit/Install-Test.command\"" | tee -a "$report"
