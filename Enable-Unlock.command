#!/bin/bash
set -euo pipefail
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != x86_64 ]; then echo 'Run on Intel Dell macOS.'; exit 1; fi
if [ "$(id -u)" = 0 ]; then echo 'Run this command as your normal GUI user, without sudo.'; exit 1; fi
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
source "$script_dir/kit-common.sh"
kit="$(rk_script_kit "$script_dir" use)"
echo 'Experimental screen-unlock convenience; not Apple Touch ID, FileVault or Apple Pay.'
echo 'Only proceed after persistence + same/different-finger tests behave correctly.'
echo 'RidgeKey will now ask LOCALLY for your macOS account password and store it in System Keychain.'
/usr/local/bin/ridgekeyctl password set
sudo install -d -o root -g wheel -m 755 '/Library/Application Support/RidgeKey'
sudo install -o root -g wheel -m 600 /dev/null '/Library/Application Support/RidgeKey/533c-unlock-enabled'
echo 'Grant Accessibility to RidgeKey Agent in System Settings, then lock with Control-Command-Q.'
echo 'No restart or NVRAM reset. Enter your password manually if fingerprint unlock does not work.'
