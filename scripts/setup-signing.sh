#!/bin/bash
set -euo pipefail
if [ "$(uname -s)" != Darwin ]; then
    echo 'Signing must be configured on macOS.' >&2
    exit 1
fi
if [ "$#" -ne 1 ] || [ -z "$1" ] || [ "$1" = '-' ]; then
    echo 'Usage: ./scripts/setup-signing.sh "certificate name or SHA-1 hash"' >&2
    echo 'Available code signing identities:' >&2
    security find-identity -v -p codesigning
    echo 'If none are available, create a Code Signing certificate in Keychain Access (see README).' >&2
    exit 1
fi
requested_identity="$1"
selected_identity=''
# Store the exact certificate hash, not a shell fragment or an ambiguous name.
while IFS= read -r line; do
    if [[ "$line" =~ ([[:xdigit:]]{40})[[:space:]]+\"(.*)\" ]]; then
        identity_hash="${BASH_REMATCH[1]}"
        identity_name="${BASH_REMATCH[2]}"
        if [ "$requested_identity" = "$identity_hash" ] || [ "$requested_identity" = "$identity_name" ]; then
            if [ -n "$selected_identity" ]; then
                echo 'Multiple matching certificates. Use an exact SHA-1 hash.' >&2
                exit 1
            fi
            selected_identity="$identity_hash"
        fi
    fi
done < <(security find-identity -v -p codesigning)
if [ -z "$selected_identity" ]; then
    echo 'No valid code signing identity with a private key matches that name or hash.' >&2
    echo 'Code signing identities, including invalid identities and their errors:' >&2
    security find-identity -p codesigning >&2
    echo 'For a self-signed certificate, open it in Keychain Access, expand Trust,' >&2
    echo 'set Code Signing to Always Trust, save, and retry.' >&2
    echo 'If it is absent above, check that its name matches and it has a private key in your login keychain.' >&2
    exit 1
fi
signing_dir="${IKKUNA_SIGNING_CONFIG_DIR:-$HOME/Library/Application Support/Ikkuna}"
mkdir -p "$signing_dir"
printf '%s\n' "$selected_identity" > "$signing_dir/signing-identity"
echo "Saved signing identity: $selected_identity"
echo 'Future builds will use this certificate. Reinstall Ikkuna and grant Accessibility once.'
