#!/bin/bash
set -euo pipefail
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != x86_64 ]; then echo 'Run on Intel Dell macOS.'; exit 1; fi
if [ "$(id -u)" = 0 ]; then echo 'Run this command as your normal GUI user, without sudo.'; exit 1; fi
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
source "$script_dir/kit-common.sh"
kit="$(rk_script_kit "$script_dir" use)"
report="$kit/Persistence-$(date +%Y%m%d-%H%M%S).txt"
{
  echo 'PRINTS_BEFORE_RESTART'
  /usr/local/bin/ridgekeyctl list
  sudo launchctl kickstart -k system/io.github.labrouss.ridgekey
  sleep 3
  echo 'PRINTS_AFTER_RESTART'
  /usr/local/bin/ridgekeyctl list
  echo 'SAME_FINGER: follow prompt, this does NOT unlock or need a stored account password.'
  /usr/local/bin/ridgekeyctl verify -t 45
  echo 'RELOAD_AND_VERIFY=PASS (one genuine trial, not a biometric accuracy estimate)'
} 2>&1 | tee "$report"
echo "Report: $report. Next, test other fingers manually with ridgekeyctl verify -t 45."
