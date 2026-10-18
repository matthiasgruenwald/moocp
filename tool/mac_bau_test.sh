#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(mktemp -d /tmp/moocp-mac-bau-test.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT
FIXTURE="$TEST_ROOT/repo"
MOCKS="$TEST_ROOT/bin"
mkdir -p "$FIXTURE/tool" "$MOCKS"
cp "$SCRIPT_DIR/mac_bau.sh" "$FIXTURE/tool/"
chmod +x "$FIXTURE/tool/mac_bau.sh"

cat > "$MOCKS/rsync" <<'MOCK'
#!/usr/bin/env bash
source="${@: -2:1}"
destination="${@: -1}"
cp -R "$source"/. "$destination"
MOCK
cat > "$MOCKS/mktemp" <<'MOCK'
#!/usr/bin/env bash
path="$(/usr/bin/mktemp "$@")"
printf '%s\n' "$path" > "$MOOCP_TEMP_PATH_FILE"
printf '%s\n' "$path"
MOCK
cat > "$MOCKS/flutter" <<'MOCK'
#!/usr/bin/env bash
if [[ "${MOCK_FLUTTER_FAIL:-}" == 1 ]]; then
  exit 23
fi
mkdir -p build/macos/Build/Products/Debug/moocp.app
printf 'built\n' > build/macos/Build/Products/Debug/moocp.app/result
MOCK
chmod +x "$MOCKS/rsync" "$MOCKS/mktemp" "$MOCKS/flutter"

export PATH="$MOCKS:$PATH"
export MOOCP_TEMP_PATH_FILE="$TEST_ROOT/temp-path"

"$FIXTURE/tool/mac_bau.sh" > "$TEST_ROOT/success.log"
APP="$FIXTURE/build/macos/Build/Products/Debug/moocp.app"
[[ -f "$APP/result" ]]
[[ ! -e "$(cat "$MOOCP_TEMP_PATH_FILE")" ]]
grep -q '^BAU-OK$' "$TEST_ROOT/success.log"

if MOCK_FLUTTER_FAIL=1 "$FIXTURE/tool/mac_bau.sh" > "$TEST_ROOT/failure.log" 2>&1; then
  echo 'Build failure unexpectedly succeeded' >&2
  exit 1
fi
[[ ! -e "$(cat "$MOOCP_TEMP_PATH_FILE")" ]]
echo 'mac_bau smoke test passed'
