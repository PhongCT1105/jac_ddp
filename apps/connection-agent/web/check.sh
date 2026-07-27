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
jac browse -s "${smoke_session}" wait '#visitor-name' >/dev/null
assert_snapshot "Find an unexpected conversation"
assert_snapshot "Keep sensitive information out"
click_selector '#find-connections'
assert_snapshot "Enter a name or nickname."
jac browse -s "${smoke_session}" eval \
  "document.activeElement && document.activeElement.id" | grep -Fq 'visitor-name'

jac browse -s "${smoke_session}" fill '#visitor-name' 'Sebastian Demo' >/dev/null
jac browse -s "${smoke_session}" fill '#visitor-profile' \
  'I build thoughtful software and enjoy education, community projects, distributed systems, creative tools, long walks, and conversations with curious people.' >/dev/null
click_selector '#find-connections'
jac browse -s "${smoke_session}" wait '#edit-profile' >/dev/null
assert_snapshot "Three fictional profiles worth exploring"
assert_snapshot "Deterministic demo ranking"
assert_snapshot "fictional candidates ranked"
assert_snapshot "They are not compatibility scores"
assert_focus "Three fictional profiles worth exploring"
jac browse -s "${smoke_session}" eval \
  "document.querySelectorAll('.result-card').length" | grep -Fq '3'

click_selector '#edit-profile'
jac browse -s "${smoke_session}" eval \
  "document.querySelector('#visitor-profile').value.includes('distributed systems')" \
  | grep -Fq 'true'
click_selector '#find-connections'
jac browse -s "${smoke_session}" wait '#start-over' >/dev/null
click_selector '#start-over'
jac browse -s "${smoke_session}" eval \
  "document.querySelector('#visitor-name').value === '' && document.querySelector('#visitor-profile').value === ''" \
  | grep -Fq 'true'

jac browse -s "${desktop_session}" -v 1280x800 open "http://localhost:${smoke_port}/" >/dev/null
jac browse -s "${desktop_session}" wait '#visitor-profile' >/dev/null
jac browse -s "${desktop_session}" snapshot | grep -Fq "Find an unexpected conversation"

echo "Web experience checks passed."
