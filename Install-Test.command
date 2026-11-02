#!/bin/bash
set -euo pipefail
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != x86_64 ]; then echo 'Run on Intel Dell macOS.'; exit 1; fi
if [ "$(id -u)" = 0 ]; then echo 'Run this command as your normal GUI user, without sudo.'; exit 1; fi
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
source "$script_dir/kit-common.sh"
kit="$(rk_script_kit "$script_dir" use)"
if [ ! -s "$kit/bundle-path.txt" ]; then
  echo "Build has not completed in: $kit"
  echo "Run: bash \"$kit/Build.command\""
  echo 'Wait for BUILD_COMPLETE before running Install-Test.command. No installation was attempted.'
  exit 1
fi
IFS= read -r bundle < "$kit/bundle-path.txt"
expected="$HOME/Library/Caches/XPS-RidgeKey-533c-lab1/bundle/ridgekey-1.0.5331-macos-x86_64"
if [ "$bundle" != "$expected" ] || [ ! -x "$bundle/bin/ridgekey-biostore-check" ]; then
  echo "The built bundle is missing or invalid. Run Build.command again in: $kit"
  exit 1
fi
if [ -e /usr/local/ridgekey ] && ! grep -q '1.0.5331' /usr/local/ridgekey/BUILDINFO.txt; then
  echo 'An existing non-lab RidgeKey is installed. It has not been changed; review migration first.'; exit 1
fi
echo 'Keychain preflight: synthetic bytes only, no fingerprint/password.'
sudo -v
cleanup() { sudo -n "$bundle/bin/ridgekey-biostore-check" --delete >/dev/null 2>&1 || true; }
trap cleanup EXIT
sudo "$bundle/bin/ridgekey-biostore-check" --write
sudo "$bundle/bin/ridgekey-biostore-reader" --read
"$bundle/bin/ridgekey-biostore-reader" --deny-user
cleanup
trap - EXIT
echo 'Installing RidgeKey lab daemon/app. Password auto-entry remains disabled by the lab gate.'
sudo /bin/bash "$bundle/install.sh"
echo 'Installed. Open RidgeKey > Fingerprints > Enroll. New native Milan enrollment is required ONCE.'
echo 'Before enrolling, keep every finger OFF the sensor while initial calibration runs.'
echo 'After enrollment, run Verify-Persistence.command. No PAM or admin rules have been enabled.'
open /Applications/RidgeKey.app
