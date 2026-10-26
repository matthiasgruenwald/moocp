#!/usr/bin/env bash
# Baut die App für den Mac in einer Kopie im Temp-Ordner und legt sie nach
# build/macos/Build/Products/<Debug|Release>/. Grund: docs/agents/testing.md.
#
#   bash tool/mac_bau.sh            Entwicklungsbau (Debug)
#   bash tool/mac_bau.sh release    Bau ohne Debugmodus
set -euo pipefail
MODUS="${1:-debug}"
case "$MODUS" in
  debug) ZIEL=Debug ;;
  release) ZIEL=Release ;;
  *) echo "Unbekannter Modus: $MODUS (debug oder release)" >&2; exit 2 ;;
esac
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d /tmp/moocp-bau.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
rsync -a --delete --exclude build --exclude .git --exclude .dart_tool "$REPO"/ "$TMP"/
(cd "$TMP" && flutter build macos --"$MODUS")
mkdir -p "$REPO/build/macos/Build/Products/$ZIEL"
rm -rf "$REPO/build/macos/Build/Products/$ZIEL/moocp.app"
cp -R "$TMP/build/macos/Build/Products/$ZIEL/moocp.app" "$REPO/build/macos/Build/Products/$ZIEL/"
echo BAU-OK
