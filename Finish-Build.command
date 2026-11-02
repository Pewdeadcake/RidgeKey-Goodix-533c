#!/bin/bash
set -euo pipefail
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != x86_64 ]; then echo 'Run on Intel Dell macOS.'; exit 1; fi
if [ "$(id -u)" = 0 ]; then echo 'Run this command as your normal GUI user, without sudo.'; exit 1; fi
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
source "$script_dir/kit-common.sh"
kit="$(rk_script_kit "$script_dir" build)"
cd "$kit"
shasum -a 256 -c SHA256SUMS >/dev/null
export WORK="$HOME/Library/Caches/XPS-RidgeKey-533c-lab1"
export PREFIX="$WORK/prefix"
export DIST="$kit/Build-Output"
export PATH="$WORK/tools-venv/bin:$PREFIX/bin:$PATH"
export RK_RESUME_BUNDLE=1
bundle="$WORK/bundle/ridgekey-1.0.5331-macos-x86_64"
if [ ! -x "$bundle/RidgeKeyAgent.app/Contents/MacOS/ridgekey-agent" ]; then
  echo 'No completed agent bundle found. Run Build.command instead.'; exit 1
fi
mkdir -p "$DIST"
report="$kit/Finish-$(date +%Y%m%d-%H%M%S).txt"
echo 'Finishing existing bundle: verifies signatures and packages only. No recompilation or enrollment.'
set +e
bash "$kit/Source/RidgeKey/ci/build-libfprint-macos.sh" 2>&1 | tee "$report"
rc=${PIPESTATUS[0]}
set -e
echo "FINISH_EXIT=$rc; report: $report" | tee -a "$report"
if [ "$rc" != 0 ]; then exit "$rc"; fi
grep -q '^27c6:533c ' "$bundle/supported-devices.txt"
printf '%s\n' "$bundle" > "$kit/bundle-path.txt"
echo "BUILD_COMPLETE. Next: bash \"$kit/Install-Test.command\"" | tee -a "$report"
