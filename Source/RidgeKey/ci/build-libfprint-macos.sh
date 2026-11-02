#!/bin/bash
# ci/build-libfprint-macos.sh - build RidgeKey for macOS: libfprint stack + ridgekeyd + ridgekeyctl
#
# Builds libusb + GLib + gusb + libfprint (match-on-chip drivers, patched) + RidgeKey (src/)
# on macOS x86_64 and packages a RELOCATABLE bundle:
#   bin/ridgekeyd bin/ridgekeyctl                  the daemon and its client
#   bin/{enroll,verify,identify,manage-prints}     libfprint examples (diagnostics)
#   bin/ridgekey-pamcheck  lib/pam/pam_ridgekey.so    sudo fingerprint (opt-in via ridgekey-sudo)
#   lib/*.dylib  launchd/  install.sh  uninstall.sh  ridgekey-sudo
# Same script runs in GitHub Actions (.github/workflows/libfprint-macos.yml) and on a Mac.
#
# Needs: Xcode CLT (clang, git, python3, perl), network. No Homebrew, no sudo.
# Everything is built into $PREFIX (scratch) and packaged into $DIST/*.tar.gz.
#
# SAFETY: patches/libfprint/0001 removes the sensor-wipe path (BMKT_CMD_DEL_FULL_DB, 0x84), which
# would also erase Windows Hello / BIOS prints. The build fails if that patch is not in effect.
# clear-storage is never shipped.
#
# Env overrides: PREFIX WORK DIST LIBUSB_VER GLIB_TAG GUSB_TAG LIBFPRINT_TAG PKGCONF_TAG FORCE_PKGCONF=1
# Written for /bin/bash 3.2 (macOS default).

set -Eeuo pipefail
trap 'rk_error=$?; printf "BUILD_ERROR file=%s line=%s status=%s\n" "${BASH_SOURCE[0]}" "$LINENO" "$rk_error" >&2; exit "$rk_error"' ERR

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
PATCHES="$REPO/patches/libfprint"

PREFIX="${PREFIX:-$HOME/opt/libfprint-build}"
WORK="${WORK:-$HOME/src/fprint-build}"
DIST="${DIST:-$WORK/dist}"
ARCH="$(uname -m)"

LIBUSB_VER="${LIBUSB_VER:-1.0.30}"
PKGCONF_TAG="${PKGCONF_TAG:-pkgconf-2.3.0}"
GLIB_TAG="${GLIB_TAG:-2.84.0}"
GUSB_TAG="${GUSB_TAG:-0.3.10}"          # 0.3.x: no json-glib dependency
LIBFPRINT_TAG="${LIBFPRINT_TAG:-v1.94.10}"

LIBUSB_URL="https://github.com/libusb/libusb/releases/download/v$LIBUSB_VER/libusb-$LIBUSB_VER.tar.bz2"
PKGCONF_URL="https://github.com/pkgconf/pkgconf.git"
GLIB_URL="https://gitlab.gnome.org/GNOME/glib.git"
GLIB_MIRROR="https://github.com/GNOME/glib.git"     # official read-only mirror, same tags
GUSB_URL="https://github.com/hughsie/libgusb.git"
LIBFPRINT_URL="https://gitlab.freedesktop.org/libfprint/libfprint.git"

EXAMPLES="enroll verify identify manage-prints"   # never clear-storage
# Match-on-chip drivers only (prints live on the sensor, like the 840 G8's Synaptics). Every one
# is checked below for whole-store erase paths (patches/libfprint/0001 + 0004).
DRIVERS="goodix53x5"
RK_VER="$(sed -n 's/^#define RK_VERSION *"\(.*\)"/\1/p' "$REPO/src/common/ridgekey-protocol.h")"
[ -n "$RK_VER" ] || { echo "cannot read RK_VERSION from src/common/ridgekey-protocol.h"; exit 1; }
BUNDLE_NAME="ridgekey-$RK_VER-macos-$ARCH"
LOG="$WORK/build.log"
if [ "${RK_RESUME_BUNDLE:-0}" = 1 ]; then LOG="$WORK/finish-bundle.log"; fi

# ---------------------------------------------------------------------------------------------
gh_group()    { [ -n "${GITHUB_ACTIONS:-}" ] && echo "::group::$*" || true; }
gh_endgroup() { [ -n "${GITHUB_ACTIONS:-}" ] && echo "::endgroup::" || true; }
log() { gh_endgroup; printf '\n\033[1;34m==> %s\033[0m\n' "$*"; echo "[$(date +%T)] $*" >> "$LOG"; gh_group "$*"; }
die() { gh_endgroup; [ -n "${GITHUB_ACTIONS:-}" ] && echo "::error::$*"; printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
run() {
  local first
  first=$(wc -l < "$LOG")
  if "$@" >> "$LOG" 2>&1; then return 0; fi
  # Parallel Ninja output can put the fatal error far before its last 40 lines.
  # Emit this failing command's complete output, not unrelated earlier builds.
  sed -n "$((first + 1)),\$p" "$LOG"
  die "failed: $* (full log: $LOG)"
}

# fetch NAME URL TAG TAGVAR [MIRROR_URL] - up to 3 tries per URL (servers have outages, e.g.
# gitlab.gnome.org 503), then the official mirror if one is given.
fetch() {
  local dir="$WORK/$1" url try
  if [ -d "$dir/.git" ]; then echo "    using existing clone $dir"; return; fi
  for url in "$2" ${5:+"$5"}; do
    for try in 1 2 3; do
      rm -rf "$dir"
      if git clone --quiet --depth 1 --branch "$3" "$url" "$dir"; then
        [ "$url" = "$2" ] || echo "    cloned $1 from the mirror $url"
        return
      fi
      echo "    clone of $1 from $url failed (try $try of 3)"
      [ $try -lt 3 ] && sleep $((try * 20))
    done
  done
  die "clone of $1 at '$3' failed - check the server, or set $4 to an existing tag"
}

# pick_opts SRCDIR name=value ... -> OPTS: only options this project version defines
pick_opts() {
  local src=$1 kv n; shift
  OPTS=()
  for kv in "$@"; do
    n=${kv%%=*}
    # grep -q exits 0 on a match even if one of the two files does not exist (GNU and BSD grep)
    if grep -Eqs "option\([[:space:]]*'$n'" "$src/meson_options.txt" "$src/meson.options"; then
      OPTS+=("-D$kv")
    else
      echo "    (skip -D$kv: not an option in this version)"
    fi
  done
}

# build_meson NAME SRCDIR name=value ...
build_meson() {
  local name=$1 src=$2; shift 2
  pick_opts "$src" "$@"
  if [ "$name" = glib ]; then
    # Repair partial/stale installed PCRE2 metadata using GLib's cached wrap.
    OPTS+=(--force-fallback-for=libpcre2-8)
  fi
  echo "    meson: $name ${OPTS[*]+${OPTS[*]}}"
  rm -rf "$src/_build"
  run meson setup "$src/_build" "$src" --prefix="$PREFIX" --libdir=lib \
      --buildtype=debugoptimized --wrap-mode=default ${OPTS[@]+"${OPTS[@]}"}
  run meson compile -C "$src/_build"
  run meson install -C "$src/_build" --quiet
}

private_glib_ready() {
  local module file
  for module in glib-2.0 gobject-2.0 gio-2.0; do
    pkg-config --exact-version="$GLIB_TAG" "$module" || return 1
  done
  for file in include/glib-2.0/glib.h include/glib-2.0/glib-object.h \
    include/glib-2.0/gio/gio.h lib/glib-2.0/include/glibconfig.h include/pcre2.h \
    lib/libglib-2.0.dylib lib/libgobject-2.0.dylib lib/libgio-2.0.dylib; do
    [ -f "$PREFIX/$file" ] || return 1
  done
  return 0
}

# ---------------------------------------------------------------------------------------------
apply_patches() {
  die "Use the pre-patched private libfprint source; do not enable other drivers in this lab."
}

# Make every Mach-O in a bundle reference siblings via @rpath; fail on any foreign dependency.
relocate() {
  local B=$1 f d cur r bad=0
  for f in "$B"/lib/*.dylib; do
    [ -L "$f" ] && continue
    cur=$(otool -D "$f" | tail -1)
    install_name_tool -id "@rpath/$(basename "$cur")" "$f" 2>/dev/null
  done
  for f in "$B"/lib/*.dylib "$B"/bin/*; do
    [ -L "$f" ] && continue
    for d in $(otool -L "$f" | tail -n +2 | awk '{print $1}'); do
      case "$d" in "$PREFIX"/*|"$WORK"/*) install_name_tool -change "$d" "@rpath/$(basename "$d")" "$f" 2>/dev/null ;; esac
    done
    for r in $(otool -l "$f" | awk '/cmd LC_RPATH/{getline; getline; print $2}'); do
      install_name_tool -delete_rpath "$r" "$f" 2>/dev/null || true
    done
    case "$f" in
      */bin/*) install_name_tool -add_rpath "@executable_path/../lib" "$f" ;;
      *)       install_name_tool -add_rpath "@loader_path" "$f" ;;
    esac
    codesign --force --sign - "$f" >/dev/null 2>&1 || die "codesign failed for $f"
  done
  # verify: only system libs and @rpath/@loader_path/@executable_path allowed
  for f in "$B"/lib/*.dylib "$B"/bin/*; do
    [ -L "$f" ] && continue
    for d in $(otool -L "$f" | tail -n +2 | awk '{print $1}'); do
      case "$d" in /usr/lib/*|/System/*|@rpath/*|@loader_path/*|@executable_path/*) ;;
        *) echo "    FOREIGN: $(basename "$f") -> $d"; bad=1 ;; esac
    done
  done
  [ $bad -eq 0 ] || die "bundle links outside itself (Homebrew or build paths leaked) - see FOREIGN lines"
  echo "    bundle is self-contained"
}

license_copy() {
  local file copied=0
  for file in COPYING COPYING.LIB COPYING.LGPL LICENSE LICENCE LICENSE.md LICENSE.txt LICENSES/LGPL-2.1-or-later.txt; do
    if [ -f "$1/$file" ]; then cp "$1/$file" "$BUNDLE/licenses/$2-$(basename "$file")"; copied=1; break; fi
  done
  for file in NOTICE NOTICE.txt; do
    if [ -f "$1/$file" ]; then cp "$1/$file" "$BUNDLE/licenses/$2-$(basename "$file")"; fi
  done
  if [ "$copied" = 0 ]; then echo "    (no license file found for $2 in $1)"; fi
  return 0
}

# ---------------------------------------------------------------------------------------------
[ "$(uname -s)" = Darwin ] || die "run on macOS"
mkdir -p "$WORK" "$PREFIX" "$DIST"; : > "$LOG"
log "macOS $(sw_vers -productVersion) $ARCH | libfprint $LIBFPRINT_TAG | prefix $PREFIX"

for t in git python3 perl curl install_name_tool otool codesign; do
  command -v $t >/dev/null || die "$t missing (install Xcode CLT: xcode-select --install)"
done

# Isolation: only our prefix is visible to pkg-config; nothing from /usr/local or Homebrew.
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
# pkgconf lives in this private prefix. Its defaults would otherwise treat
# our include/lib directories as system paths and silently strip their flags.
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1
export PKG_CONFIG_ALLOW_SYSTEM_LIBS=1
unset PKG_CONFIG_PATH
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"

log "Python build tools"
if ! command -v meson >/dev/null || ! command -v ninja >/dev/null; then
  run python3 -m pip install --user --upgrade meson ninja packaging
fi
python3 -c 'import packaging' 2>/dev/null || run python3 -m pip install --user packaging
echo "    meson $(meson --version), ninja $(ninja --version)"

if [ "${RK_RESUME_BUNDLE:-0}" != 1 ]; then
log "pkg-config"
if [ -z "${FORCE_PKGCONF:-}" ] && command -v pkg-config >/dev/null; then
  echo "    using $(command -v pkg-config)"
else
  fetch pkgconf "$PKGCONF_URL" "$PKGCONF_TAG" PKGCONF_TAG
  build_meson pkgconf "$WORK/pkgconf" tests=disabled \
    with-system-includedir=/usr/include with-system-libdir=/usr/lib
  ln -sf pkgconf "$PREFIX/bin/pkg-config"
fi

log "libusb $LIBUSB_VER"
if [ ! -f "$PREFIX/lib/pkgconfig/libusb-1.0.pc" ]; then
  ( cd "$WORK" && curl -fsSL -o "libusb-$LIBUSB_VER.tar.bz2" "$LIBUSB_URL" ) || die "libusb download failed"
  rm -rf "$WORK/libusb" && mkdir -p "$WORK/libusb"
  tar xjf "$WORK/libusb-$LIBUSB_VER.tar.bz2" -C "$WORK/libusb" --strip-components=1
  ( cd "$WORK/libusb" && run ./configure --prefix="$PREFIX" --disable-static && run make -j"$(sysctl -n hw.ncpu)" && run make install )
fi
pkg-config --modversion libusb-1.0 >/dev/null || die "pkg-config can't see libusb-1.0"

log "GLib $GLIB_TAG (pcre2/libffi/libintl as meson subprojects)"
fetch glib "$GLIB_URL" "$GLIB_TAG" GLIB_TAG "$GLIB_MIRROR"
if private_glib_ready; then
  echo "    reusing complete installed GLib $GLIB_TAG"
else
  build_meson glib "$WORK/glib" \
    tests=false introspection=disabled nls=disabled man-pages=disabled \
    documentation=false selinux=disabled libmount=disabled sysprof=disabled
fi

log "gusb $GUSB_TAG"
fetch libgusb "$GUSB_URL" "$GUSB_TAG" GUSB_TAG
if pkg-config --exact-version="$GUSB_TAG" gusb && \
   [ -f "$PREFIX/include/gusb-1/gusb.h" ] && [ -f "$PREFIX/lib/libgusb.dylib" ]; then
  echo "    reusing complete installed gusb $GUSB_TAG"
else
  build_meson gusb "$WORK/libgusb" docs=false introspection=false tests=false vapi=false
fi

log "private libfprint with complete Goodix 533c Milan driver"
bash "$REPO/../build-goodix-deps.sh"
FP_SOURCE="$REPO/../libfprint"
grep -q fp_device_identify_finish_with_update "$FP_SOURCE/libfprint/fp-device.h" || die "missing template-update API"
build_meson libfprint "$FP_SOURCE" \
  drivers="$DRIVERS" introspection=false udev_rules=disabled udev_hwdb=disabled \
  gtk-examples=false doc=false installed-tests=false tod=false
log "Offline core and full Milan tests (no reader access)"
run meson test -C "$FP_SOURCE/_build" --no-rebuild --print-errorlogs fpi-device goodix53x5-milan-synthetic goodix53x5-milan-runtime goodix53x5-milan-transport
run bash "$REPO/tests/store/run.sh"

# Supported USB IDs of exactly the drivers built (libfprint's own tool): for the installer's
# reader check, the app and the docs. "vvvv:pppp | Driver name" per line.
SUPPORTED="$WORK/supported-devices.txt"
"$FP_SOURCE/_build/libfprint/fprint-list-supported-devices" 2>/dev/null \
  | grep -E '^[0-9a-f]{4}:[0-9a-f]{4} \| ' > "$SUPPORTED" || true
[ -s "$SUPPORTED" ] || die "could not list the supported devices"
grep -q '^27c6:533c ' "$SUPPORTED" || die "27c6:533c missing from the supported devices"
[ "$(wc -l < "$SUPPORTED" | tr -d ' ')" = 1 ] || die "unexpected extra sensor IDs in lab build"
echo "    $(wc -l < "$SUPPORTED" | tr -d ' ') supported USB readers:"
cut -d'|' -f2 "$SUPPORTED" | sort | uniq -c | sed 's/^/     /'

log "RidgeKey $RK_VER (ridgekeyd, ridgekeyctl)"
rm -rf "$WORK/ridgekey-build"
run meson setup "$WORK/ridgekey-build" "$REPO/src" --prefix="$PREFIX" --libdir=lib --buildtype=debugoptimized
run meson compile -C "$WORK/ridgekey-build"
run meson install -C "$WORK/ridgekey-build" --quiet

log "Bundle $BUNDLE_NAME"
BUNDLE="$WORK/bundle/$BUNDLE_NAME"
rm -rf "$WORK/bundle"; mkdir -p "$BUNDLE/bin" "$BUNDLE/lib" "$BUNDLE/licenses" "$BUNDLE/patches"
cp -a "$PREFIX"/lib/*.dylib "$BUNDLE/lib/"
cp -a "$PREFIX/include" "$BUNDLE/"
mkdir -p "$BUNDLE/lib/pkgconfig"
for pc in "$PREFIX"/lib/pkgconfig/*.pc; do
  sed "s|^prefix=.*|prefix=\${pcfiledir}/../..|" "$pc" > "$BUNDLE/lib/pkgconfig/$(basename "$pc")"
done
for b in ridgekeyd ridgekeyctl ridgekey-pamcheck ridgekey-typetest ridgekey-agent ridgekey-authcheck ridgekey-biostore-check ridgekey-biostore-reader; do
  [ -x "$PREFIX/bin/$b" ] || die "$b not built"
  cp "$PREFIX/bin/$b" "$BUNDLE/bin/"
done
mkdir -p "$BUNDLE/launchd"
cp "$REPO/launchd/"*.plist "$BUNDLE/launchd/"
cp "$REPO/scripts/install.sh" "$REPO/scripts/uninstall.sh" "$REPO/scripts/ridgekey-sudo" \
   "$REPO/scripts/ridgekey-sign" "$REPO/scripts/ridgekey-admin" "$REPO/scripts/typetest-as-daemon.sh" "$BUNDLE/"
chmod 755 "$BUNDLE/install.sh" "$BUNDLE/uninstall.sh" "$BUNDLE/ridgekey-sudo" "$BUNDLE/ridgekey-sign" \
  "$BUNDLE/ridgekey-admin" "$BUNDLE/typetest-as-daemon.sh"
for ex in $EXAMPLES; do
  [ -x "$FP_SOURCE/_build/examples/$ex" ] || die "example $ex not built"
  cp "$FP_SOURCE/_build/examples/$ex" "$BUNDLE/bin/"
done
relocate "$BUNDLE"

for d in $(otool -L "$BUNDLE/bin/ridgekey-agent" | tail -n +2 | awk '{print $1}'); do
  case "$d" in /usr/lib/*|/System/*) ;; *) die "ridgekey-agent links $d - must use system libraries only" ;; esac
done

# PAM module: loaded into sudo, so it must depend on system libraries only.
mkdir -p "$BUNDLE/lib/pam"
cp "$PREFIX/lib/pam/pam_ridgekey.so" "$BUNDLE/lib/pam/"
codesign --force --sign - "$BUNDLE/lib/pam/pam_ridgekey.so" >/dev/null 2>&1 || die "codesign failed for pam_ridgekey.so"
for d in $(otool -L "$BUNDLE/lib/pam/pam_ridgekey.so" | tail -n +2 | awk '{print $1}'); do
  case "$d" in /usr/lib/*|/System/*) ;; *) die "pam_ridgekey.so links $d - must use system libraries only" ;; esac
done
nm -gU "$BUNDLE/lib/pam/pam_ridgekey.so" | grep -q '_pam_sm_authenticate$' || die "pam_sm_authenticate not exported"
echo "    pam_ridgekey.so: system libraries only, pam_sm_authenticate exported"

# Authorization plugin: loaded into macOS's authorizationhost - system libraries only.
AP="$BUNDLE/RidgeKey.bundle"
mkdir -p "$AP/Contents/MacOS"
cp "$PREFIX/lib/authplugin/RidgeKey.so" "$AP/Contents/MacOS/RidgeKey"
cat > "$AP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>RidgeKey</string>
  <key>CFBundleIdentifier</key><string>io.github.labrouss.ridgekey.authplugin</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>RidgeKey</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>$RK_VER</string>
  <key>CFBundleVersion</key><string>$RK_VER</string>
</dict>
</plist>
PLIST
plutil -lint "$AP/Contents/Info.plist" >/dev/null || die "RidgeKey.bundle Info.plist is invalid"
file "$AP/Contents/MacOS/RidgeKey" | grep -Eq 'bundle|shared library' || die "RidgeKey.bundle executable is not loadable Mach-O"
for d in $(otool -L "$AP/Contents/MacOS/RidgeKey" | tail -n +2 | awk '{print $1}'); do
  case "$d" in /usr/lib/*|/System/*) ;; *) die "RidgeKey.bundle links $d - must use system libraries only" ;; esac
done
nm -gU "$AP/Contents/MacOS/RidgeKey" | grep -q '_AuthorizationPluginCreate$' || die "AuthorizationPluginCreate not exported"
codesign --force --sign - --identifier io.github.labrouss.ridgekey.authplugin "$AP" >/dev/null 2>&1 \
  || die "codesign failed for RidgeKey.bundle"
codesign --verify --strict "$AP" || die "RidgeKey.bundle signature does not verify"
echo "    RidgeKey.bundle: system libraries only, AuthorizationPluginCreate exported"

log "RidgeKey.app (SwiftUI)"
run bash "$REPO/scripts/build-app.sh" "$BUNDLE/RidgeKey.app"
"$BUNDLE/RidgeKey.app/Contents/MacOS/RidgeKey" --version || die "RidgeKey.app does not start"

# Lock-screen agent as a background-only app bundle: System Settings -> Accessibility then shows
# "RidgeKey Agent" with the RidgeKey icon instead of a bare executable. It receives the stored
# password, so: hardened runtime, fixed identifier (ridgekeyd checks both), system libs only.
log "RidgeKeyAgent.app"
AA="$BUNDLE/RidgeKeyAgent.app"
mkdir -p "$AA/Contents/MacOS" "$AA/Contents/Resources"
mv "$BUNDLE/bin/ridgekey-agent" "$AA/Contents/MacOS/ridgekey-agent"
ln -s ../RidgeKeyAgent.app/Contents/MacOS/ridgekey-agent "$BUNDLE/bin/ridgekey-agent"   # CLI: --version, --type-test
AGENT_ICON_KEY=""
if [ -f "$BUNDLE/RidgeKey.app/Contents/Resources/RidgeKey.icns" ]; then
  cp "$BUNDLE/RidgeKey.app/Contents/Resources/RidgeKey.icns" "$AA/Contents/Resources/"
  AGENT_ICON_KEY="<key>CFBundleIconFile</key><string>RidgeKey</string>"
fi
cat > "$AA/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>ridgekey-agent</string>
  <key>CFBundleIdentifier</key><string>io.github.labrouss.ridgekey.agent</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>RidgeKey Agent</string>
  <key>CFBundleDisplayName</key><string>RidgeKey Agent</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$RK_VER</string>
  <key>CFBundleVersion</key><string>$RK_VER</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSBackgroundOnly</key><true/>
  $AGENT_ICON_KEY
</dict>
</plist>
PLIST
plutil -lint "$AA/Contents/Info.plist" >/dev/null || die "RidgeKeyAgent.app Info.plist is invalid"
else
  log "Resume existing compiled bundle (no dependency/compiler rebuild)"
  BUNDLE="$WORK/bundle/$BUNDLE_NAME"
  FP_SOURCE="$REPO/../libfprint"
  SUPPORTED="$WORK/supported-devices.txt"
  if [ ! -s "$SUPPORTED" ]; then cp "$BUNDLE/supported-devices.txt" "$SUPPORTED"; fi
  AA="$BUNDLE/RidgeKeyAgent.app"
  for binary in ridgekeyd ridgekeyctl ridgekey-biostore-check ridgekey-biostore-reader; do
    [ -x "$BUNDLE/bin/$binary" ] || die "incomplete cached bundle: $binary; run Build.command"
  done
  cached_version=$("$BUNDLE/bin/ridgekeyd" --version)
  [ "$cached_version" = "ridgekeyd $RK_VER" ] || die "cached daemon version mismatch"
  grep -q '^27c6:533c ' "$SUPPORTED" || die "cached bundle is not the 533c build"
  [ "$(wc -l < "$SUPPORTED" | tr -d ' ')" = 1 ] || die "unexpected extra cached sensor IDs"
  [ -f "$AA/Contents/Info.plist" ] || die "agent Info.plist missing"
  plutil -lint "$AA/Contents/Info.plist" >/dev/null || die "agent Info.plist invalid"
  codesign --verify --strict "$BUNDLE/RidgeKey.app" || die "cached settings app signature invalid"
  for cached_file in "$BUNDLE"/lib/*.dylib "$BUNDLE"/bin/*; do
    [ -L "$cached_file" ] && continue
    codesign --verify --strict "$cached_file" || die "cached signature invalid: $cached_file"
  done
  cp "$REPO/scripts/ridgekey-sign" "$BUNDLE/ridgekey-sign"
  chmod 755 "$BUNDLE/ridgekey-sign"
fi
codesign --force --sign - --options runtime --identifier io.github.labrouss.ridgekey.agent "$AA" >/dev/null 2>&1 \
  || die "codesign failed for RidgeKeyAgent.app"
run bash "$REPO/scripts/check-agent-runtime.sh" "$AA"
echo "    agent strict signature + numeric CS_RUNTIME flag verified"
"$BUNDLE/bin/ridgekey-agent" --version || die "ridgekey-agent does not start from the bundle"
echo "    RidgeKeyAgent.app: hardened runtime, system libraries only, icon: ${AGENT_ICON_KEY:+yes}"

cp "$PATCHES"/*.patch "$BUNDLE/patches/"
cp "$REPO/LICENSE" "$BUNDLE/LICENSE"
cp "$SUPPORTED" "$BUNDLE/supported-devices.txt"
license_copy "$FP_SOURCE" libfprint
license_copy "$REPO/../goodix533c" goodix53x5
license_copy "$WORK/openssl" openssl
license_copy "$WORK/libdeflate" libdeflate
license_copy "$WORK/glib" glib
license_copy "$WORK/libgusb" gusb
license_copy "$WORK/libusb" libusb
for d in "$WORK"/glib/subprojects/*/; do
  [ -d "$d" ] && [ "$(basename "$d")" != packagecache ] && license_copy "$d" "glib-sub-$(basename "$d")"
done

{
  echo "RidgeKey $RK_VER for macOS - ridgekeyd, ridgekeyctl and libfprint $LIBFPRINT_TAG"
  echo "built:   $(date -u +%FT%TZ) on macOS $(sw_vers -productVersion) $ARCH, target $MACOSX_DEPLOYMENT_TARGET"
  echo "ci:      ${GITHUB_SERVER_URL:-local}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-} commit ${GITHUB_SHA:-local}"
  echo
  echo "Sources (LGPL-2.1+ components; corresponding source = these tags + patches/):"
  echo "  libusb    $LIBUSB_VER  $LIBUSB_URL"
  for n in glib libgusb; do
    echo "  $n  $(git -C "$WORK/$n" describe --tags --always 2>/dev/null) $(git -C "$WORK/$n" rev-parse HEAD) $(git -C "$WORK/$n" remote get-url origin)"
  done
  echo
  echo "Private libfprint base: 0c97a47d8ef405cd577b87058c1e89cae9d242e7; Goodix: 52584a593d29e1cf8b317f53cb46c54396a3e4f1; RidgeKey: 4968672f775c119e96a9f7e5041536e801069aab"
  echo "Drivers: $DRIVERS ($(wc -l < "$SUPPORTED" | tr -d ' ') USB IDs, see supported-devices.txt)"
  echo "533c-lab1: only Goodix 27c6:533c/GM168SEC registered, no sensor storage/erase API registered."
  echo "Biometric template and preprocessing state: UID-root System Keychain items."
  echo "Screen unlock blocked until local Enable-Unlock.command; admin authorization disabled."
} > "$BUNDLE/BUILDINFO.txt"

cat > "$BUNDLE/README.txt" <<'EOF'
RidgeKey - fingerprint daemon for macOS (Synaptics match-in-sensor readers)

Install / upgrade (keeps existing prints):
  xattr -dr com.apple.quarantine .        # only if downloaded with a browser
  sudo ./install.sh

Use (as your normal user):
  ridgekeyctl status
  ridgekeyctl enroll right-index          # ~8 touches
  ridgekeyctl verify                      # exit code 0 = match
  ridgekeyctl list
  ridgekeyctl delete right-index

Fingerprint for sudo (optional; your password keeps working):
  sudo ridgekey-sudo enable               # then test in a NEW terminal: sudo -k; sudo -v
  sudo ridgekey-sudo disable

Fingerprint for admin dialogs (optional; the password dialog still appears as a fallback):
  sudo ridgekey-admin enable
  sudo ridgekey-admin disable             # restores the original macOS rules exactly

Uninstall:  sudo ./uninstall.sh            (keeps prints)
            sudo ./uninstall.sh --purge    (deletes RidgeKey's prints from the sensor first)
Log:        /Library/Logs/RidgeKey/ridgekeyd.log

Diagnostics (stop the daemon first: sudo launchctl bootout system/io.github.labrouss.ridgekey):
  bin/ridgekeyd --probe
  G_MESSAGES_DEBUG=all bin/enroll | bin/verify | bin/identify    (libfprint examples)

RidgeKey never erases the whole sensor; Windows Hello / BIOS prints are left alone.
EOF

if [ -z "${GITHUB_ACTIONS:-}" ] && [ -z "${SMOKE:-}" ]; then
  echo "    (smoke test skipped locally: with the sensor attached it would start a real enrollment)"
else
log "Smoke test (moved bundle, scratch prefix hidden)"
SMOKE="$WORK/smoke"; rm -rf "$SMOKE"; mkdir -p "$SMOKE"; cp -a "$BUNDLE" "$SMOKE/"
mv "$PREFIX" "$PREFIX.hidden"
set +e
# Pick a finger, then enroll initialises libfprint -> gusb -> libusb and enumerates USB.
# CI runners have no reader, so "No devices detected." is the expected success marker.
SB="$SMOKE/$BUNDLE_NAME/bin"
POUT=$("$SB/ridgekeyd" --probe 2>&1); PRC=$?
COUT=$(perl -e 'alarm 20; exec @ARGV' "$SB/ridgekeyctl" status 2>&1); CRC=$?
VOUT=$("$SB/ridgekeyd" --version 2>&1); VRC=$?
echo "$VOUT"; echo "$POUT"; echo "$COUT"
SMOKE_ERR=""
[ "$VRC" = 0 ] || SMOKE_ERR="ridgekeyd --version failed (exit $VRC)"
echo "$POUT" | grep -q 'no supported fingerprint sensor found\|driver=' || SMOKE_ERR="ridgekeyd --probe failed (exit $PRC)"
[ "$CRC" = 3 ] || SMOKE_ERR="ridgekeyctl status without a daemon should exit 3, got $CRC"
OUT=$( cd "$SMOKE/$BUNDLE_NAME" && printf '1\n' | perl -e 'alarm 30; exec @ARGV' ./bin/enroll 2>&1 )
RC=$?
set -e
mv "$PREFIX.hidden" "$PREFIX"
echo "$OUT" | tail -15
[ -z "$SMOKE_ERR" ] || die "smoke test: $SMOKE_ERR"
echo "    ridgekeyd --version/--probe and ridgekeyctl run from the moved bundle"
echo "$OUT" | grep -q 'Library not loaded\|image not found\|dyld\[' && die "dyld could not load the bundle"
if echo "$OUT" | grep -q 'No devices detected\|Enrolling\|Selected device'; then
  echo "    enroll initialised libfprint (exit $RC) - libraries resolve inside the bundle"
else
  die "smoke test: enroll did not reach device discovery (exit $RC)"
fi
fi

log "Package"
tar -C "$WORK/bundle" -czf "$DIST/$BUNDLE_NAME.tar.gz" "$BUNDLE_NAME"
( cd "$DIST" && shasum -a 256 "$BUNDLE_NAME.tar.gz" > "$BUNDLE_NAME.tar.gz.sha256" )
gh_endgroup
echo "Done: $DIST/$BUNDLE_NAME.tar.gz. Use the kit's Install-Test.command, not a generic installer."
