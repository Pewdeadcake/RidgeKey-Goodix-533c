#!/bin/bash
set -euo pipefail
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != x86_64 ]; then echo 'Run on Intel Dell macOS.'; exit 1; fi
if [ "$(id -u)" = 0 ]; then echo 'Run this command as your normal GUI user, without sudo.'; exit 1; fi
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
source "$script_dir/kit-common.sh"
kit="$(rk_script_kit "$script_dir" use)"
report="$kit/Collect-$(date +%Y%m%d-%H%M%S).txt"
{
  date -u
  sw_vers
  /usr/local/bin/ridgekeyctl status || true
  /usr/local/bin/ridgekeyctl list || true
  echo '--- daemon recent log ---'
  sudo tail -160 /Library/Logs/RidgeKey/ridgekeyd.log || true
} 2>&1 | tee "$report"
echo "Report: $report. Contains operational logs, no template/key/password dump."
