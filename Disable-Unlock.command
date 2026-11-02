#!/bin/bash
set -euo pipefail
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != x86_64 ]; then echo 'Run on Intel Dell macOS.'; exit 1; fi
if [ "$(id -u)" = 0 ]; then echo 'Run this command as your normal GUI user, without sudo.'; exit 1; fi
sudo rm -f '/Library/Application Support/RidgeKey/533c-unlock-enabled'
echo 'Lab screen-unlock disabled. Enrolled templates remain; normal password login is available.'
