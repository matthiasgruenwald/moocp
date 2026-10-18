#!/usr/bin/env bash
# Ruft ein Werkzeug der laufenden App auf, ohne Claude-Sitzung -- zum
# Durchspielen im Testkurs:
#
#   bash tool/mcp_aufruf.sh <werkzeug> '<json-argumente>'
#   bash tool/mcp_aufruf.sh kurs_uebersicht '{"kurs":43}'
#
# Schreibende Werkzeuge warten auf die Freigabe in der App (bis 30 Minuten);
# deshalb ohne Zeitgrenze.
#
# Unter Windows in Git Bash aufrufen, unter macOS in der Shell. Nicht aus
# Python heraus: Das Python auf dem
# Entwicklungsrechner ist ein gepacktes Programm, dem Windows %APPDATA%
# umleitet -- es und jede Bash, die es startet, sehen die Einstellungen der App
# nicht, und die App weist die Anfrage „ohne gültigen Schlüssel" ab.
#
# Den Schlüssel liest das Skript aus den Einstellungen der App, ohne ihn
# auszugeben. Jede Anfrage bekommt eigene Dateien; parallele Aufrufe
# überschreiben sich nicht.
if [ "$(uname)" = Darwin ]; then D="$HOME/Library/Application Support/moocp"; else D="$(cygpath -u "$APPDATA")/moocp"; fi
F="$D/einstellungen.json"
T=$(sed -n 's/.*"schluessel": *"\([0-9a-f]*\)".*/\1/p' "$F")
[ -n "$T" ] || { echo "Kein Schlüssel in $F -- läuft die App schon einmal gestartet?" >&2; exit 2; }
U=http://127.0.0.1:47811/mcp
H=(-H "Content-Type: application/json" -H "Accept: application/json, text/event-stream")
if command -v cygpath >/dev/null; then PY=python; else PY=python3; fi
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
K=$TMPD/kopf.txt
ANF="$TMPD"/anfrage.json
ANT="$TMPD"/antwort.json
curl -s -D "$K" -o /dev/null -X POST $U -H "Authorization: Bearer $T" "${H[@]}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"mcp_aufruf","version":"1"}}}'
SID=$(grep -i "^mcp-session-id:" "$K" | tr -d '\r' | awk '{print $2}')
[ -n "$SID" ] || { echo "Keine Antwort von $U -- läuft die App?" >&2; exit 2; }
S=(-H "Authorization: Bearer $T" -H "Mcp-Session-Id: $SID" -H "MCP-Protocol-Version: 2025-06-18")
curl -s -o /dev/null -X POST $U "${S[@]}" "${H[@]}" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
# Die Anfrage baut Python (json.dumps): Bash halbierte Backslashes in Pfaden.
# Die Argumente gehen als UTF-8-Datei hinüber, nicht über die Kommandozeile:
# Dort kommen sie über die Codepage an, und was nicht in Latin-1 liegt, ging
# verloren (… wurde zum Steuerzeichen U+0085, € verschwand).
ARG="$TMPD"/argumente.json
printf '%s' "${2:-{\}}" > "$ARG"
$PY -c "import json,sys;print(json.dumps({'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':sys.argv[1],'arguments':json.loads(open(sys.argv[2],'rb').read().decode('utf-8'))}}))" "$1" "$ARG" > "$ANF"
curl -s -X POST $U "${S[@]}" "${H[@]}" --data-binary @"$ANF" > "$ANT"
$PY -c "
import sys, json
sys.stdout.reconfigure(encoding='utf-8')
d = json.loads(open(sys.argv[1], 'rb').read().decode('utf-8'))
if 'error' in d:
    print('JSON-RPC-Fehler:', d['error'])
else:
    r = d['result']
    print('isError:', r.get('isError', False))
    for c in r.get('content', []):
        print(c.get('text'))
" "$ANT"
