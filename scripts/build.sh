#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ]; then
    echo 'Ikkuna.app must be built on macOS 13 or newer with Xcode Command Line Tools.' >&2
    exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
    echo 'Install Command Line Tools first: xcode-select --install' >&2
    exit 1
fi
signing_file="${IKKUNA_SIGNING_CONFIG_DIR:-$HOME/Library/Application Support/Ikkuna}/signing-identity"
signing_identity="${SIGNING_IDENTITY:-}"
if [ -z "$signing_identity" ] && [ -f "$signing_file" ]; then
    IFS= read -r signing_identity < "$signing_file" || true
    if [ -z "$signing_identity" ] || [ "$signing_identity" = '-' ]; then
        echo "Invalid signing configuration: $signing_file" >&2
        exit 1
    fi
fi
if [ -z "$signing_identity" ]; then
    signing_identity='-'
fi
if [ "$signing_identity" = '-' ]; then
    echo 'Warning: ad hoc signing resets Accessibility identity on rebuild.' >&2
    echo 'Configure a persistent certificate with ./scripts/setup-signing.sh (see README).' >&2
fi
swift test
swift build -c release --product Ikkuna
binary_dir="$(swift build -c release --show-bin-path)"
app_path="$PWD/dist/Ikkuna.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/Ikkuna" "$app_path/Contents/MacOS/Ikkuna"
cp Info.plist "$app_path/Contents/Info.plist"
cp README.md "$app_path/Contents/Resources/README.md"
# A configured certificate must remain available; never silently fall back to ad hoc.
codesign --force --sign "$signing_identity" --identifier fi.iiro.Ikkuna "$app_path"
codesign --verify --strict "$app_path"
echo "Built: $app_path"
