#!/usr/bin/env bash
# Ruft ein Werkzeug der laufenden App auf, ohne Claude-Sitzung -- zum
# Durchspielen im Testkurs:
#
#   bash tool/mcp_aufruf.sh <werkzeug> '<json-argumente>' [mcp-name]
#   bash tool/mcp_aufruf.sh kurs_uebersicht '{"kurs":43}'
#   bash tool/mcp_aufruf.sh kurs_uebersicht '{}' moodle-test
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
H=(-H "Content-Type: application/json" -H "Accept: application/json, text/event-stream")
if command -v cygpath >/dev/null; then PY=python; else PY=python3; fi
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
CFG="$TMPD/curl.conf"
UF="$TMPD/url.txt"
if ! "$PY" -c '
import json,sys
j=json.load(open(sys.argv[1],encoding="utf-8"))
t=j.get("schluessel","")
if not isinstance(t,str) or not t or any(c not in "0123456789abcdef" for c in t): raise ValueError()
p=j.get("profile") or []
wahl=sys.argv[3]
if wahl:
 p=[x for x in p if wahl in (x.get("mcpName"),x.get("name"),x.get("kennung"))]
 if len(p)!=1: raise ValueError()
port=p[0].get("port") if p else j.get("port",47811)
port=int(port)
if port<1 or port>65535: raise ValueError()
open(sys.argv[2],"w",encoding="utf-8").write("header = "+json.dumps("Authorization: Bearer "+t)+"\n")
open(sys.argv[4],"w",encoding="ascii").write("http://127.0.0.1:"+str(port)+"/mcp")
' "$F" "$CFG" "${3:-}" "$UF" 2>/dev/null; then
  echo "Einstellungen fehlen oder das Profil ist ungültig -- läuft die App schon einmal gestartet?" >&2
  exit 2
fi
U=$(cat "$UF")
K="$TMPD/kopf.txt"
ANF="$TMPD"/anfrage.json
ANT="$TMPD"/antwort.json
curl -s -D "$K" -o /dev/null -X POST "$U" --config "$CFG" "${H[@]}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"mcp_aufruf","version":"1"}}}'
SID=$(grep -i "^mcp-session-id:" "$K" | tr -d '\r' | awk '{print $2}')
[ -n "$SID" ] || { echo "Keine Antwort von $U -- läuft die App?" >&2; exit 2; }
S=(-H "Mcp-Session-Id: $SID" -H "MCP-Protocol-Version: 2025-06-18")
curl -s -o /dev/null -X POST "$U" --config "$CFG" "${S[@]}" "${H[@]}" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
# Die Anfrage baut Python (json.dumps): Bash halbierte Backslashes in Pfaden.
# Die Argumente gehen als UTF-8-Datei hinüber, nicht über die Kommandozeile:
# Dort kommen sie über die Codepage an, und was nicht in Latin-1 liegt, ging
# verloren (… wurde zum Steuerzeichen U+0085, € verschwand).
ARG="$TMPD"/argumente.json
printf '%s' "${2:-{\}}" > "$ARG"
$PY -c "import json,sys;print(json.dumps({'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':sys.argv[1],'arguments':json.loads(open(sys.argv[2],'rb').read().decode('utf-8'))}}))" "$1" "$ARG" > "$ANF"
curl -s -X POST "$U" --config "$CFG" "${S[@]}" "${H[@]}" --data-binary @"$ANF" > "$ANT"
$PY -c "
import sys, json
sys.stdout.reconfigure(encoding='utf-8')
try:
    d = json.loads(open(sys.argv[1], 'rb').read().decode('utf-8'))
    token = json.load(open(sys.argv[2], encoding='utf-8')).get('schluessel', '')
    sauber = lambda s: str(s).replace(token, '[geschwärzt]') if token else str(s)
    if 'error' in d:
        print('JSON-RPC-Fehler:', sauber(d['error']))
    else:
        r = d['result']
        print('isError:', r.get('isError', False))
        for c in r.get('content', []):
            print(sauber(c.get('text', '')))
except Exception:
    print('Antwort konnte nicht gelesen werden.')
" "$ANT" "$F"
