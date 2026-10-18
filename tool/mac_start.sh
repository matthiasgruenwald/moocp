#!/usr/bin/env bash
# Startet die gebaute App im Testmodus neu und wartet auf den MCP-Server.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
L="$HOME/Library/Application Support/moocp/protokoll.log"
pkill -x moocp; sleep 1
N=$(wc -l < "$L")
open -n "$REPO/build/macos/Build/Products/Debug/moocp.app" --env MOOCP_TESTZUGANG="$HOME/.config/moocp/e2e/spike-credentials.env"
for i in $(seq 1 40); do sleep 3; tail -n +$((N+1)) "$L" | grep -q "MCP-Server läuft" && { echo START-OK; exit 0; }; done
echo START-FEHLT; exit 1
