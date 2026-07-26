#!/usr/bin/env bash
# Focused behavior checks for the destructive/process-safety helpers used by
# e2e_lan_sandbox_embedding.sh. No Jac servers are started.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/demo/lib.sh
source "$HERE/../../scripts/demo/lib.sh"
# shellcheck source=lan_test_lib.sh
source "$HERE/lan_test_lib.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/jacgrid-lan-safety.XXXXXX")"
CHILD_PID=""
SERVER_PID=""
cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    if [ -n "$CHILD_PID" ]; then
        kill "$CHILD_PID" 2>/dev/null || true
        wait "$CHILD_PID" 2>/dev/null || true
    fi
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

echo "[1/5] failed backup leaves original state untouched"
live="$TMP_ROOT/partial-live"
saved="$TMP_ROOT/partial-saved"
mkdir -p "$live" "$saved"
printf 'original\n' >"$live/identity"
printf 'collision\n' >"$saved/already-here"
mode="untouched"
if new_mode="$(jacgrid_backup_test_state "$live" "$saved" 2>/dev/null)"; then
    fail "backup unexpectedly accepted an occupied destination ($new_mode)"
fi
jacgrid_restore_test_state "$live" "$saved" "$mode"
[ "$(cat "$live/identity")" = original ] \
    || fail "cleanup changed original state after failed backup"

echo "[2/5] successful backup restores original and removes only test state"
rm -rf "$saved"
mode="$(jacgrid_backup_test_state "$live" "$saved")"
[ "$mode" = backed_up ] || fail "expected backed_up mode, got '$mode'"
[ ! -e "$live" ] || fail "live state remained after successful backup"
mkdir -p "$live"
printf 'test-owned\n' >"$live/identity"
jacgrid_restore_test_state "$live" "$saved" "$mode"
[ "$(cat "$live/identity")" = original ] || fail "original state was not restored"
[ ! -e "$saved" ] || fail "saved state remained after restore"

echo "[3/5] initially absent state removes only the test-created directory"
absent_live="$TMP_ROOT/absent-live"
absent_saved="$TMP_ROOT/absent-saved"
mode="$(jacgrid_backup_test_state "$absent_live" "$absent_saved")"
[ "$mode" = absent ] || fail "expected absent mode, got '$mode'"
mkdir -p "$absent_live"
printf 'test-owned\n' >"$absent_live/identity"
jacgrid_restore_test_state "$absent_live" "$absent_saved" "$mode"
[ ! -e "$absent_live" ] || fail "test-created state was not removed"

echo "[4/5] process ancestry and stale PID ownership are enforced"
sleep 30 &
CHILD_PID=$!
jacgrid_pid_is_descendant "$CHILD_PID" "$$" \
    || fail "live child was not recognized as this test's descendant"
if jacgrid_pid_is_descendant "$$" "$CHILD_PID"; then
    fail "ancestor was incorrectly recognized as child descendant"
fi
OWNED_PIDS=(111 "$CHILD_PID" 222)
jacgrid_forget_owned_pid "$CHILD_PID"
[ "${OWNED_PIDS[*]}" = "111 222" ] || fail "stopped PID remained owned: ${OWNED_PIDS[*]}"

echo "[5/5] listener resolution rejects a foreign bind-race process"
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 40); do
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 && break
    sleep 0.05
done
resolved="$(jacgrid_listener_pid_for_owner "$port" "$$")" \
    || fail "owned listener was not resolved"
[ "$resolved" = "$SERVER_PID" ] \
    || fail "resolved listener $resolved, expected $SERVER_PID"
foreign=""
if foreign="$(jacgrid_listener_pid_for_owner "$port" "$CHILD_PID" 2>/dev/null)"; then
    fail "foreign listener was accepted for unrelated owner $CHILD_PID"
fi
[ -z "$foreign" ] || fail "foreign listener PID leaked through resolver: $foreign"
kill -0 "$SERVER_PID" 2>/dev/null \
    || fail "foreign-listener rejection signaled a process it did not own"

echo "PASS: state ownership, failed-backup survival, PID forgetting, and bind-race rejection"
