#!/bin/bash
# Rende il progetto firmabile con un account Apple gratuito (Personal Team), togliendo dagli
# entitlements le capacità che un account gratuito non può concedere: iCloud (container, servizi
# e kvstore) su tutte le piattaforme, più le notifiche push su tvOS.
#
# Serve perché con quelle chiavi Xcode si rifiuta di firmare — "Personal development teams do not
# support the iCloud capability" — e senza firma non si prova l'app su un dispositivo. Il codice
# non ne ha bisogno: senza container `LibraryStorage.isICloudAvailable` è false, la libreria
# ripiega sulla cartella Documents locale e la sincronizzazione CloudKit resta inerte.
#
# ATTENZIONE: Support/*.entitlements è generato da XcodeGen a partire da project.yml, quindi una
# `xcodegen generate` rimette le chiavi iCloud. Rieseguire questo script dopo ogni generazione:
# è idempotente. NON usarlo per una build destinata a TestFlight/App Store, dove iCloud serve.
#
# Uso: Scripts/strip-icloud-entitlements.sh [repo-root]
set -uo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SUPPORT="$REPO_ROOT/Support"

failures=0

fail() { echo "❌ $1"; failures=$((failures + 1)); }

has_key() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" >/dev/null 2>&1; }

ICLOUD_KEYS=(
    com.apple.developer.icloud-container-identifiers
    com.apple.developer.icloud-services
    com.apple.developer.ubiquity-kvstore-identifier
)
# Su tvOS le notifiche push sono dichiarate negli entitlements e un Personal Team non può
# concederle: senza toglierle la firma fallisce allo stesso modo di iCloud.
TVOS_EXTRA_KEYS=(aps-environment)

strip() {
    local plist="$1"
    if [ ! -f "$plist" ]; then
        fail "$(basename "$plist") non trovato in Support/: lancia prima \`xcodegen generate\`"
        return
    fi

    local keys=("${ICLOUD_KEYS[@]}")
    case "$plist" in *tvOS*) keys+=("${TVOS_EXTRA_KEYS[@]}") ;; esac

    for key in "${keys[@]}"; do
        /usr/libexec/PlistBuddy -c "Delete :$key" "$plist" >/dev/null 2>&1 || true
    done

    # La verifica, non il Delete, è ciò che rende affidabile il risultato: `Delete` su una chiave
    # già assente (seconda esecuzione) fallisce ed è normalissimo, quindi il suo esito non dice
    # se il file è a posto.
    for key in "${keys[@]}"; do
        if has_key "$plist" "$key"; then fail "$(basename "$plist"): $key è ancora presente"; fi
    done

    echo "✅ $(basename "$plist")"
}

for plist in "$SUPPORT"/Chunky-iOS.entitlements "$SUPPORT"/Chunky-macOS.entitlements "$SUPPORT"/Chunky-tvOS.entitlements; do
    strip "$plist"
done

if [ "$failures" -gt 0 ]; then
    echo
    echo "$failures entitlements da sistemare"
    exit 1
fi

echo
echo "Entitlements pronti per la firma con un account gratuito"
