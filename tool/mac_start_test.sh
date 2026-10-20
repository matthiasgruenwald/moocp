#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(mktemp -d /tmp/moocp-mac-start-test.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT
MOCKS="$TEST_ROOT/bin"
TEST_LOG="$TEST_ROOT/protokoll.log"
mkdir -p "$MOCKS"
: > "$TEST_LOG"
sed "s|^L=.*|L=\"$TEST_LOG\"|" "$SCRIPT_DIR/mac_start.sh" > "$TEST_ROOT/mac_start.sh"

cat > "$MOCKS/open" <<'MOCK'
#!/usr/bin/env bash
while (($#)); do
  if [[ "$1" == --env ]]; then
    printf '%s\n' "$2" >> "$MOOCP_OPEN_ARGS_FILE"
    shift 2
  else
    shift
  fi
done
printf 'MCP-Server läuft auf 127.0.0.1\n' >> "$MOOCP_TEST_LOG"
if [[ -n "${MOOCP_TESTZUGANG_PROFILE:-}" ]]; then
  python3 -c 'import json,os; print("\n".join("MCP-Server bereit ["+k+"]" for k in json.loads(os.environ["MOOCP_TESTZUGANG_PROFILE"]) if k != os.environ.get("MOOCP_FEHLEND")))' >> "$MOOCP_TEST_LOG"
fi
MOCK
cat > "$MOCKS/pkill" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat > "$MOCKS/sleep" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$MOCKS/open" "$MOCKS/pkill" "$MOCKS/sleep"

export PATH="$MOCKS:$PATH"
export MOOCP_TEST_LOG="$TEST_LOG"
export MOOCP_OPEN_ARGS_FILE="$TEST_ROOT/open-args"
: > "$MOOCP_OPEN_ARGS_FILE"

assert_env_args() {
  local expected="$1"
  : > "$MOOCP_OPEN_ARGS_FILE"
  bash "$TEST_ROOT/mac_start.sh" > "$TEST_ROOT/start.log"
  grep -Fq -- "$expected" "$MOOCP_OPEN_ARGS_FILE"
  grep -q '^START-OK$' "$TEST_ROOT/start.log"
}

assert_no_test_args() {
  : > "$MOOCP_OPEN_ARGS_FILE"
  bash "$TEST_ROOT/mac_start.sh" > "$TEST_ROOT/start.log"
  if grep -Eq 'MOOCP_TESTZUGANG(_PROFILE|_ADRESSE)?=' "$MOOCP_OPEN_ARGS_FILE"; then
    echo 'Unexpected test-login option passed to open' >&2
    exit 1
  fi
  grep -q '^START-OK$' "$TEST_ROOT/start.log"
}

unset MOOCP_TESTZUGANG_PROFILE MOOCP_TESTZUGANG MOOCP_TESTZUGANG_ADRESSE
assert_no_test_args

export MOOCP_TESTZUGANG_PROFILE='{"standard":{"file":"/tmp/testzugang.env","address":"https://moodle.schule.example"}}'
assert_env_args 'MOOCP_TESTZUGANG_PROFILE={"standard":{"file":"/tmp/testzugang.env","address":"https://moodle.schule.example"}}'
export MOOCP_TESTZUGANG_PROFILE='{"standard":{"file":"/tmp/testzugang.env","address":"https://moodle.schule.example"},"zweites":{"file":"/tmp/zweites.env","address":"https://zweite.schule.example"}}'
assert_env_args 'MOOCP_TESTZUGANG_PROFILE='
export MOOCP_FEHLEND=zweites
if bash "$TEST_ROOT/mac_start.sh" > "$TEST_ROOT/start.log"; then
  echo 'Ein fehlender zweiter Server wurde als bereit gemeldet' >&2
  exit 1
fi
grep -q 'START-FEHLT' "$TEST_ROOT/start.log"
unset MOOCP_FEHLEND
unset MOOCP_TESTZUGANG_PROFILE

export MOOCP_TESTZUGANG='/tmp/legacy-testzugang.env'
export MOOCP_TESTZUGANG_ADRESSE='https://moodle.schule.example'
assert_env_args 'MOOCP_TESTZUGANG=/tmp/legacy-testzugang.env'
grep -Fq -- 'MOOCP_TESTZUGANG_ADRESSE=https://moodle.schule.example' "$MOOCP_OPEN_ARGS_FILE"

echo 'mac_start smoke test passed'
