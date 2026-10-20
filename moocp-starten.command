#!/usr/bin/env bash
# moocp auf dem Mac starten – per Doppelklick im Finder oder im Terminal:
#
#   bash moocp-starten.command
#
# Gibt es noch keinen Bau oder ist der Quelltext neuer als der Bau, wird
# zuerst gebaut (dauert einige Minuten). Sonst startet sofort die vorhandene App.
# Läuft die App schon, kommt sie nur in den Vordergrund.
#
# Erster Doppelklick: macOS fragt, ob das Skript laufen darf – im Finder mit
# Rechtsklick > Öffnen bestätigen, danach geht es per Doppelklick.
set -euo pipefail
cd "$(dirname "$0")"
# Aus dem Finder kommt ein knapper PATH ohne Homebrew.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
APP="build/macos/Build/Products/Debug/moocp.app"

veraltet() {
  [ ! -d "$APP" ] && return 0
  [ -n "$(find lib skills pubspec.yaml macos -type f \
    -newer "$APP/Contents/MacOS/moocp" -not -path '*/dist/*' -print -quit 2>/dev/null)" ]
}

if pgrep -x moocp >/dev/null; then
  echo "moocp läuft schon – wird in den Vordergrund geholt."
  open "$APP"
  exit 0
fi

if veraltet; then
  echo "Die App wird gebaut (einige Minuten) ..."
  python3 skills/build.py
  bash tool/mac_bau.sh
fi
open "$APP"
echo "moocp ist gestartet. Dieses Fenster darf geschlossen werden."
