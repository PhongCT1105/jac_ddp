#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}/.."
jac fmt main.jac web tests/experience --check
jac check main.jac web tests/experience --nowarn
jac test -d tests/experience
(
  jac build --client web
)
echo "Client build check passed; starting browser smoke."

smoke_port=18765
smoke_session="connection-agent-smoke"
desktop_session="connection-agent-desktop"
server_log="$(mktemp -t connection-agent-web.XXXXXX.log)"

cleanup() {
  jac browse -s "${smoke_session}" close >/dev/null 2>&1 || true
  jac browse -s "${desktop_session}" close >/dev/null 2>&1 || true
  if [[ -n "${server_pid:-}" ]]; then
    child_pids="$(pgrep -P "${server_pid}" 2>/dev/null || true)"
    if [[ -n "${child_pids}" ]]; then
      kill ${child_pids} >/dev/null 2>&1 || true
    fi
    kill "${server_pid}" >/dev/null 2>&1 || true
    wait "${server_pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${server_log}"
}
trap cleanup EXIT

nohup bash -c 'exec jac start -p "$1"' bash "${smoke_port}" \
  >"${server_log}" 2>&1 < /dev/null &
server_pid=$!
echo "Browser smoke server launched; waiting for readiness."

for _ in {1..40}; do
  if curl -fsS "http://localhost:${smoke_port}/" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "${server_pid}" 2>/dev/null; then
    cat "${server_log}" >&2
    exit 1
  fi
  sleep 0.25
done
curl -fsS "http://localhost:${smoke_port}/" >/dev/null
echo "Browser smoke server ready; running assertions."

click_selector() {
  local selector="$1"
  jac browse -s "${smoke_session}" wait "${selector}" >/dev/null
  jac browse -s "${smoke_session}" click "${selector}" >/dev/null
}

assert_snapshot() {
  local expected="$1"
  local snapshot=""
  for _ in {1..30}; do
    snapshot="$(jac browse -s "${smoke_session}" snapshot)"
    if grep -Fq "${expected}" <<<"${snapshot}"; then
      return 0
    fi
    sleep 0.1
  done
  printf '%s\n' "${snapshot}" >&2
  echo "Missing browser text: ${expected}" >&2
  return 1
}

assert_focus() {
  local expected="$1"
  jac browse -s "${smoke_session}" eval \
    "document.activeElement ? document.activeElement.textContent.trim() : ''" \
    | grep -Fq "${expected}"
}

jac browse -s "${smoke_session}" -v 390x844 open "http://localhost:${smoke_port}/" >/dev/null
jac browse -s "${smoke_session}" wait '#persona' >/dev/null
jac browse -s "${smoke_session}" eval \
  "const s=document.querySelector('#persona'); s.value='alice_builder'; s.dispatchEvent(new Event('change',{bubbles:true})); true" \
  >/dev/null
assert_snapshot "Software builder seeking thoughtful technical collaboration"
assert_focus "Review your demo profile"
click_selector '#confirm-profile'
assert_focus "Profile confirmed"
click_selector '#show-suggestion'
assert_snapshot "Bob Researcher"
assert_snapshot "Shared interest in thoughtful technical collaboration"
assert_focus "Bob Researcher"
click_selector '#open-interest'
assert_snapshot "Your response is private."
assert_snapshot "Bob Researcher could be a thoughtful connection for Alice Builder"
assert_focus "Thanks for letting us know"
if jac browse -s "${smoke_session}" snapshot | grep -Fq "It’s a match"; then
  echo "Alice's one-sided open leaked a match." >&2
  exit 1
fi
click_selector '#switch-bob'
assert_snapshot "Distributed systems researcher and software builder"
assert_focus "Review your demo profile"
click_selector '#confirm-profile'
click_selector '#show-suggestion'
assert_snapshot "Alice Builder"
click_selector '#open-interest'
assert_snapshot "It’s a match"
assert_snapshot "Alice Builder could be a thoughtful connection for Bob Researcher"
assert_focus "It’s a match"
click_selector '#open-thread'
assert_focus "Private human conversation"
assert_snapshot "Alice Builder could be a thoughtful connection for Bob Researcher"
jac browse -s "${smoke_session}" fill '#message' 'Hi Alice' >/dev/null
click_selector '#send-message'
assert_snapshot "Hi Alice"
click_selector '#reset-demo'
assert_snapshot "Demo reset. Choose a local demo person."

jac browse -s "${smoke_session}" eval \
  "(()=>{const s=document.querySelector('#persona'); s.value=''; s.dispatchEvent(new Event('change',{bubbles:true})); return true})()" \
  >/dev/null
assert_snapshot "Unable to select this demo person. Try again."
assert_snapshot "Retry profile"
click_selector '#retry-profile'
assert_snapshot "Unable to select this demo person. Try again."
click_selector '#reset-demo'

jac browse -s "${desktop_session}" -v 1280x800 open "http://localhost:${smoke_port}/" >/dev/null
jac browse -s "${desktop_session}" wait '#persona' >/dev/null
jac browse -s "${desktop_session}" snapshot | grep -Fq "Connection Agent"

echo "Web experience checks passed."
