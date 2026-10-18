#!/bin/zsh
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

swiftc -O -swift-version 5 -target arm64-apple-macos14.0 "${EXTRA_FLAGS[@]}" \
  -module-cache-path build/ModuleCache Sources/*.swift -o build/mactidy
echo "已生成: $PWD/build/mactidy"
