#!/usr/bin/env bash
set -u

remote_port="${1:-17897}"
exit_policy="${2:-strict}"
failures=0

case "$remote_port" in
  ''|*[!0-9]*)
    printf 'usage: inspect_remote_codex.sh [remote-port] [--always-zero]\n' >&2
    exit 2
    ;;
esac

if [ "$remote_port" -lt 1 ] || [ "$remote_port" -gt 65535 ]; then
  printf 'FAIL | remote port must be between 1 and 65535\n' >&2
  exit 2
fi

if [ "$exit_policy" != strict ] && [ "$exit_policy" != --always-zero ]; then
  printf 'usage: inspect_remote_codex.sh [remote-port] [--always-zero]\n' >&2
  exit 2
fi

report() {
  local status="$1"
  local check="$2"
  local evidence="$3"
  printf '%-5s | %-28s | %s\n' "$status" "$check" "$evidence"
  if [ "$status" = "FAIL" ]; then
    failures=$((failures + 1))
  fi
}

redact_home() {
  sed "s#^${HOME}/#~/#"
}

report INFO "identity" "redacted by default"
report INFO "kernel" "$(uname -srmo)"

listener_output=""
if command -v ss >/dev/null 2>&1; then
  listener_output="$(ss -lntp 2>/dev/null | grep -E "127\.0\.0\.1:${remote_port}([[:space:]]|$)" || true)"
elif command -v netstat >/dev/null 2>&1; then
  listener_output="$(netstat -lntp 2>/dev/null | grep -E "127\.0\.0\.1:${remote_port}([[:space:]]|$)" || true)"
fi

if [ -n "$listener_output" ]; then
  report PASS "remote loopback listener" "127.0.0.1:${remote_port}"
else
  report FAIL "remote loopback listener" "nothing found on 127.0.0.1:${remote_port}"
fi

proxy_names="$(env | sed -nE 's/^((http|https|all|no)_proxy)=.*/\1/ip' | sort -fu | tr '\n' ' ' || true)"
if [ -n "$proxy_names" ]; then
  report INFO "current proxy variables" "configured names: ${proxy_names% } (values redacted)"
else
  report INFO "current proxy variables" "none"
fi

extension_path="$(
  find "$HOME" -maxdepth 8 -type d \
    -path '*/extensions/openai.chatgpt-*-linux-x64' \
    -print 2>/dev/null | sort -V | tail -n 1
)"

if [ -n "$extension_path" ]; then
  report PASS "Linux extension path" "$(printf '%s\n' "$extension_path" | redact_home)"

  codex_binary="$extension_path/bin/linux-x86_64/codex"
  if grep -q 'CODEX_REMOTE_PROXY_WRAPPER' "$codex_binary" 2>/dev/null && [ -x "${codex_binary}.real" ]; then
    report PASS "version-bound wrapper" "present in newest extension"
  else
    report INFO "version-bound wrapper" "plain codex in newest extension; inspect process environment before deciding"
  fi
else
  report FAIL "Linux extension path" "openai.chatgpt-*-linux-x64 not found"
fi

codex_process=""
if command -v pgrep >/dev/null 2>&1; then
  codex_process="$(
    pgrep -af 'openai\.chatgpt-.*-linux-x64/.*/codex(\.real)? .*app-server' |
      head -n 1 || true
  )"
fi

if [ -n "$codex_process" ]; then
  codex_pid="$(printf '%s\n' "$codex_process" | awk '{print $1}')"
  report PASS "Codex app-server" "pid=${codex_pid} executable=codex app-server"

  proc_root="${CODEX_INSPECT_PROC_ROOT:-/proc}"
  if [ -r "${proc_root}/${codex_pid}/environ" ]; then
    process_env="$(tr '\0' '\n' < "${proc_root}/${codex_pid}/environ")"
    for proxy_name in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY; do
      if printf '%s\n' "$process_env" | grep -qx "${proxy_name}=http://127.0.0.1:${remote_port}"; then
        report PASS "Codex ${proxy_name}" "http://127.0.0.1:${remote_port}"
      else
        report FAIL "Codex ${proxy_name}" "missing or different"
      fi
    done
  else
    report FAIL "Codex proxy environment" "process environment is unreadable"
  fi
else
  report FAIL "Codex app-server" "Linux Codex app-server process not found"
fi

if command -v wget >/dev/null 2>&1; then
  headers="$(
    https_proxy="http://127.0.0.1:${remote_port}" \
      wget -S --spider --timeout=15 'https://api.openai.com/v1/models' 2>&1 || true
  )"
  http_status="$(printf '%s\n' "$headers" | grep -Eo 'HTTP/[0-9.]+[[:space:]]+[0-9]{3}' | tail -n 1 || true)"
  if [ -n "$http_status" ]; then
    report PASS "OpenAI through tunnel" "$http_status"
  else
    last_line="$(printf '%s\n' "$headers" | tail -n 1)"
    report FAIL "OpenAI through tunnel" "${last_line:-no HTTP response}"
  fi
else
  report INFO "OpenAI through tunnel" "wget not installed; use another independent HTTP client"
fi

printf '\nSummary: FAIL=%d\n' "$failures"
if [ "$exit_policy" = --always-zero ]; then
  exit 0
fi

[ "$failures" -eq 0 ]
