#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
install_dir="${IKKUNA_INSTALL_DIR:-$HOME/Applications}"
install_path="$install_dir/Ikkuna.app"
mkdir -p "$install_dir"
# Replace the application atomically while keeping an old build until copy succeeds.
staging_dir="$(mktemp -d "$install_dir/.ikkuna-install.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto dist/Ikkuna.app "$staging_dir/Ikkuna.app"
was_running=false
if pgrep -u "$(id -u)" -x Ikkuna >/dev/null; then
    was_running=true
    echo 'Quitting Ikkuna before updating…'
    # An ordinary Quit lets the app release event taps and restore AX state.
    osascript -e 'tell application id "fi.iiro.Ikkuna" to quit'
    for ((attempt = 0; attempt < 100; attempt++)); do
        if ! pgrep -u "$(id -u)" -x Ikkuna >/dev/null; then break; fi
        sleep 0.1
    done
    if pgrep -u "$(id -u)" -x Ikkuna >/dev/null; then
        echo 'Ikkuna did not quit within 10 seconds. Installation cancelled.' >&2
        exit 1
    fi
fi
if [ -e "$install_path" ]; then mv "$install_path" "$staging_dir/previous.app"; fi
if ! mv "$staging_dir/Ikkuna.app" "$install_path"; then
    if [ -e "$staging_dir/previous.app" ]; then mv "$staging_dir/previous.app" "$install_path"; fi
    if [ "$was_running" = true ] && [ -d "$install_path" ]; then open "$install_path"; fi
    exit 1
fi
open "$install_path"
echo "Installed: $install_path"
