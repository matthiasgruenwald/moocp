#!/usr/bin/env bash
# Startet die gebaute App neu und wartet auf alle gebundenen Testprofile.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
L="$HOME/Library/Application Support/moocp/protokoll.log"
pkill -x moocp; sleep 1
N=0
[[ ! -f "$L" ]] || N=$(wc -l < "$L")
erwartet=$(python3 -c 'import json,os; p=json.loads(os.environ.get("MOOCP_TESTZUGANG_PROFILE") or "{}"); print("\n".join(p))') || exit 2
env_args=()
for name in MOOCP_TESTZUGANG_PROFILE MOOCP_TESTZUGANG MOOCP_TESTZUGANG_ADRESSE; do
  if [[ "${!name+x}" == x ]]; then
    env_args+=(--env "$name=${!name}")
  fi
done
open -n "$REPO/build/macos/Build/Products/Debug/moocp.app" "${env_args[@]}"
for i in $(seq 1 40); do
  sleep 3
  neu=$(tail -n +$((N+1)) "$L" 2>/dev/null)
  if [[ -z "$erwartet" ]]; then
    grep -q "MCP-Server läuft" <<< "$neu" && { echo START-OK; exit 0; }
  else
    bereit=true
    while IFS= read -r kennung; do
      grep -Fq "MCP-Server bereit [$kennung]" <<< "$neu" || bereit=false
    done <<< "$erwartet"
    $bereit && { echo START-OK; exit 0; }
  fi
done
echo 'START-FEHLT: Nicht alle erwarteten MCP-Server sind bereit.'; exit 1
