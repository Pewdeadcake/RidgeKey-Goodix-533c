#!/bin/bash
set -euo pipefail
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = x86_64 ] || { echo 'Run on Intel macOS'; exit 1; }
[ "$(id -u)" != 0 ] || { echo 'Run without sudo'; exit 1; }
root="$(cd "$(dirname "$0")" && pwd -P)"
name=ridgekey-1.0.5331-macos-x86_64
bundle="$HOME/Library/Caches/XPS-RidgeKey-533c-lab1/bundle/$name"
[ -f "$bundle/BUILDINFO.txt" ] || { echo 'Complete Build.command or Finish-Build.command first'; exit 1; }
[ "$("$bundle/bin/ridgekeyd" --version)" = 'ridgekeyd 1.0.5331' ]
grep -q '^27c6:533c ' "$bundle/supported-devices.txt"
bash "$root/Source/RidgeKey/scripts/check-agent-runtime.sh" "$bundle/RidgeKeyAgent.app"
codesign --verify --strict "$bundle/RidgeKey.app"
out="$root/Releases/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
# Export the build bundle only. Never use the installed /usr/local tree,
# /Library/Application Support, Keychains, home directories or device captures.
members=(bin lib include launchd licenses patches RidgeKey.app RidgeKeyAgent.app RidgeKey.bundle install.sh uninstall.sh ridgekey-sudo ridgekey-admin ridgekey-sign typetest-as-daemon.sh BUILDINFO.txt supported-devices.txt LICENSE README.txt)
for entry in "${members[@]}"; do [ -e "$bundle/$entry" ] || { echo "Incomplete bundle: $entry"; exit 1; }; done
tar -C "$bundle" -czf "$out/$name.tar.gz" "${members[@]}"
(cd "$out" && shasum -a 256 "$name.tar.gz" > "$name.tar.gz.sha256")
echo "RELEASE_EXPORT_COMPLETE: $out"
echo 'Publish matching source with this archive. It is a binary bundle, not a notarized installer; source build + Install-Test is the documented installation path.'
