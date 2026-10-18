#!/usr/bin/env bash
# Startet die gebaute App neu und wartet auf den MCP-Server.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
L="$HOME/Library/Application Support/moocp/protokoll.log"
pkill -x moocp; sleep 1
N=$(wc -l < "$L")
env_args=()
for name in MOOCP_TESTZUGANG_PROFILE MOOCP_TESTZUGANG MOOCP_TESTZUGANG_ADRESSE; do
  if [[ "${!name+x}" == x ]]; then
    env_args+=(--env "$name=${!name}")
  fi
done
open -n "$REPO/build/macos/Build/Products/Debug/moocp.app" "${env_args[@]}"
for i in $(seq 1 40); do sleep 3; tail -n +$((N+1)) "$L" | grep -q "MCP-Server läuft" && { echo START-OK; exit 0; }; done
echo START-FEHLT; exit 1
