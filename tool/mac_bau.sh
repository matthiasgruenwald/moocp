#!/usr/bin/env bash
# Baut die App für den Mac (Debug) in einer Kopie im Temp-Ordner und legt sie
# nach build/macos/Build/Products/Debug/. Grund: docs/agents/testing.md.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d /tmp/moocp-bau.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
rsync -a --delete --exclude build --exclude .git --exclude .dart_tool "$REPO"/ "$TMP"/
(cd "$TMP" && flutter build macos --debug)
mkdir -p "$REPO/build/macos/Build/Products/Debug"
rm -rf "$REPO/build/macos/Build/Products/Debug/moocp.app"
cp -R "$TMP/build/macos/Build/Products/Debug/moocp.app" "$REPO/build/macos/Build/Products/Debug/"
echo BAU-OK
