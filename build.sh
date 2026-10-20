#!/bin/zsh
# ./build.sh        Build the command-line tool and the app, install the app in /Applications and reopen it
# ./build.sh cli    Build only the command-line tool
# ./build.sh release  Build and package build/MacTidy-<version>.zip for a GitHub release, without installing
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build

# Some Command Line Tools installs ship a stale usr/include/swift/module.modulemap that
# redefines SwiftBridging and breaks every SDK import; mask it with an empty file.
CLT_SWIFT_INC="/Library/Developer/CommandLineTools/usr/include/swift"
EXTRA_FLAGS=()
if [[ -f "$CLT_SWIFT_INC/module.modulemap" && -f "$CLT_SWIFT_INC/bridging.modulemap" ]]; then
  : > build/empty.modulemap
  cat > build/overlay.yaml <<EOF
{ "version": 0, "roots": [ { "type": "file",
  "name": "$CLT_SWIFT_INC/module.modulemap",
  "external-contents": "$PWD/build/empty.modulemap" } ] }
EOF
  EXTRA_FLAGS=(-vfsoverlay "$PWD/build/overlay.yaml")
fi
SWIFTC=(swiftc -O -swift-version 5 -target arm64-apple-macos14.0 "${EXTRA_FLAGS[@]}" -module-cache-path build/ModuleCache)

"${SWIFTC[@]}" Sources/Core/*.swift Sources/CLI/*.swift -o build/mactidy
echo "Built: $PWD/build/mactidy"
[[ "${1:-}" == "cli" ]] && exit 0

APP_NAME="MacTidy.app"
APP="build/$APP_NAME"
EXEC="MacTidy"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f Resources/AppIcon.icns || Tools/make_icon.swift -nt Resources/AppIcon.icns ]]; then
  "${SWIFTC[@]}" Tools/make_icon.swift -o build/make_icon
  build/make_icon build/icon_1024.png
  ICONSET=build/AppIcon.iconset
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) build/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for lproj in Resources/*.lproj; do
  ditto "$lproj" "$APP/Contents/Resources/$(basename "$lproj")"
done

"${SWIFTC[@]}" -parse-as-library Sources/Core/*.swift Sources/App/*.swift -o "$APP/Contents/MacOS/$EXEC"

# A stable self-signed identity keeps privacy grants (Full Disk Access) valid across rebuilds;
# ad-hoc signatures change every build and silently invalidate them. The identity lives in its own
# never-locking keychain so codesign doesn't stall on a login-keychain prompt.
SIGN_NAME="MacTidy Local Signing"
KC="$HOME/Library/Keychains/mactidy-signing.keychain-db"
KC_PASS="mactidy-local-signing"
signing_identity() { security find-identity -p codesigning "$KC" | awk -v n="\"$SIGN_NAME\"" 'index($0, n) { print $2; exit }'; }
if [[ ! -f "$KC" ]]; then
  security create-keychain -p "$KC_PASS" "$KC"
  security set-keychain-settings "$KC"
fi
if ! security list-keychains -d user | grep -q "$KC"; then
  security list-keychains -d user -s $(security list-keychains -d user | tr -d '" ') "$KC"
fi
security unlock-keychain -p "$KC_PASS" "$KC"
if [[ -z "$(signing_identity)" ]]; then
  TMP=$(mktemp -d)
  cat > "$TMP/cfg" <<EOF
[req]
distinguished_name=dn
prompt=no
x509_extensions=ext
[dn]
CN=$SIGN_NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cfg" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:tmp -out "$TMP/id.p12"
  security import "$TMP/id.p12" -k "$KC" -P tmp -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC" >/dev/null
  rm -rf "$TMP"
fi
codesign --force --keychain "$KC" --sign "$(signing_identity)" "$APP"
echo "Built: $PWD/$APP"

if [[ "${1:-}" == "release" ]]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
  ZIP="build/MacTidy-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  shasum -a 256 "$ZIP"
  echo "Packaged: $PWD/$ZIP"
  exit 0
fi

if pkill -x "$EXEC"; then
  for _ in {1..50}; do pgrep -x "$EXEC" >/dev/null || break; sleep 0.1; done
fi
rm -rf "/Applications/$APP_NAME"
ditto "$APP" "/Applications/$APP_NAME"
touch "/Applications/$APP_NAME"
echo "Installed: /Applications/$APP_NAME"
open "/Applications/$APP_NAME"
