#!/usr/bin/env bash
set -euo pipefail

action="${1:-check}"
remote_port="${2:-17897}"
server_root="${3:-$HOME/.vscode-server-codex-proxy/.vscode-server}"
repair_root="${server_root%/.vscode-server}/repairs"

fail() {
  printf 'FAIL | %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

case "$action" in
  install|check|rollback) ;;
  *) fail 'usage: repair_codex_proxy_wrapper.sh {install|check|rollback} [remote-port] [server-root] [repair-dir]' ;;
esac

case "$remote_port" in
  ''|*[!0-9]*) fail 'remote port must be an integer between 1 and 65535' ;;
esac

if [ "$remote_port" -lt 1 ] || [ "$remote_port" -gt 65535 ]; then
  fail 'remote port must be between 1 and 65535'
fi

case "$server_root" in
  *"'"*) fail "server root must not contain a single quote" ;;
esac

for required in find sort tail grep dirname basename awk; do
  require_command "$required"
done

case "$action" in
  install) for required in sha256sum stat cp chmod mkdir date mv rm cat; do require_command "$required"; done ;;
  check) for required in pgrep ss; do require_command "$required"; done ;;
  rollback) for required in sha256sum cp rm; do require_command "$required"; done ;;
esac

latest_binary() {
  find "$server_root/extensions" -type f \
    -path '*/openai.chatgpt-*-linux-x64/bin/linux-x86_64/codex' \
    -perm -u+x -print 2>/dev/null | sort -V | tail -n 1
}

target="$(latest_binary)"
[ -n "$target" ] || fail "Codex Linux binary not found under $server_root/extensions"
real="${target}.real"
version="$(basename "$(dirname "$(dirname "$(dirname "$target")")")")"

install_wrapper() {
  if grep -q 'CODEX_REMOTE_PROXY_WRAPPER' "$target" 2>/dev/null; then
    [ -x "$real" ] || fail "wrapper exists but $real is missing"
    printf 'PASS | already wrapped | version=%s target=%s\n' "$version" "$target"
    return
  fi

  [ ! -e "$real" ] || fail "refusing to overwrite existing preserved binary: $real"

  stamp="$(date +%Y%m%d-%H%M%S)-$$"
  repair="$repair_root/$stamp"
  mkdir -p "$repair_root"
  mkdir "$repair"

  original_hash="$(sha256sum "$target" | awk '{print $1}')"
  original_mode="$(stat -c %a "$target")"
  cp -p "$target" "$repair/codex.original"
  cp -p "$target" "$real"
  printf '%s  %s\n' "$original_hash" "$repair/codex.original" > "$repair/original.sha256"

  tmp="${target}.tmp.$$"
  installed=0
  complete=0
  cleanup_install() {
    status=$?
    set +e
    rm -f "$tmp"
    if [ "$installed" -eq 1 ] && [ "$complete" -eq 0 ]; then
      cp -p "$repair/codex.original" "$target"
    fi
    if [ "$complete" -eq 0 ]; then
      rm -f "$real"
    fi
    exit "$status"
  }
  trap cleanup_install EXIT INT TERM

  cat > "$tmp" <<WRAPPER
#!/bin/sh
# CODEX_REMOTE_PROXY_WRAPPER
unset ALL_PROXY all_proxy
export http_proxy=http://127.0.0.1:${remote_port}
export https_proxy=http://127.0.0.1:${remote_port}
export HTTP_PROXY=http://127.0.0.1:${remote_port}
export HTTPS_PROXY=http://127.0.0.1:${remote_port}
export no_proxy=localhost,127.0.0.1
export NO_PROXY=localhost,127.0.0.1
exec "\$(dirname "\$0")/codex.real" "\$@"
WRAPPER
  chmod 755 "$tmp"
  wrapper_hash="$(sha256sum "$tmp" | awk '{print $1}')"
  cp -p "$tmp" "$repair/codex.wrapper"

  cat > "$repair/patch.txt" <<PATCH
TARGET=$target
VERSION=$version
CHANGED_FIELD=Codex child-process proxy environment
BEFORE=Original Codex binary launched directly
AFTER=Wrapper exports lower/upper HTTP and HTTPS proxy variables to 127.0.0.1:${remote_port}, then execs codex.real
ORIGINAL_SHA256=$original_hash
ORIGINAL_MODE=$original_mode
PATCH

  cat > "$repair/rollback.sh" <<ROLLBACK
#!/bin/sh
set -eu
target='$target'
preserved='$real'
original='$repair/codex.original'
expected_original='$original_hash'
expected_wrapper='$wrapper_hash'
actual_original=\$(sha256sum "\$original" | awk '{print \$1}')
actual_target=\$(sha256sum "\$target" | awk '{print \$1}')
actual_preserved=\$(sha256sum "\$preserved" | awk '{print \$1}')
[ "\$actual_original" = "\$expected_original" ] || {
  echo "ROLLBACK_BLOCKED original hash mismatch: \$actual_original" >&2
  exit 1
}
[ "\$actual_preserved" = "\$expected_original" ] || {
  echo "ROLLBACK_BLOCKED preserved binary hash mismatch: \$actual_preserved" >&2
  exit 1
}
[ "\$actual_target" = "\$expected_wrapper" ] || {
  echo "ROLLBACK_BLOCKED target changed since wrapper installation: \$actual_target" >&2
  exit 1
}
case "\${1:---check}" in
  --check) echo "ROLLBACK_READY target=\$target original_sha256=\$actual_original wrapper_sha256=\$actual_target" ;;
  --apply) cp -p "\$original" "\$target"; rm -f "\$preserved"; echo "ROLLBACK_APPLIED target=\$target sha256=\$actual_original" ;;
  *) echo 'usage: rollback.sh [--check|--apply]' >&2; exit 2 ;;
esac
ROLLBACK
  chmod 700 "$repair/rollback.sh"

  cat > "$repair/verification.txt" <<VERIFICATION
BASELINE_COMMAND=sha256sum $target
BASELINE_OUTPUT=$original_hash
BASELINE_EXIT=0
MODIFIED_COMMAND=mv -f $tmp $target
MODIFIED_EXPECTED=target=$target mode=755 wrapper_sha256=$wrapper_hash original=$real
ROLLBACK_CHECK_COMMAND=$repair/rollback.sh --check
VERIFICATION

  # Commit only after the preserved original, wrapper copy, patch, verification,
  # and executable rollback artifact all exist.
  mv -f "$tmp" "$target"
  installed=1
  modified_hash="$(sha256sum "$target" | awk '{print $1}')"
  [ "$modified_hash" = "$wrapper_hash" ] || fail "installed wrapper hash mismatch: $modified_hash"

  {
    echo "MODIFIED_OUTPUT=target=$target mode=$(stat -c %a "$target") wrapper_sha256=$wrapper_hash original=$real"
    echo 'MODIFIED_EXIT=0'
    "$repair/rollback.sh" --check
    echo "ROLLBACK_CHECK_EXIT=$?"
  } >> "$repair/verification.txt"

  complete=1
  trap - EXIT INT TERM

  printf 'PASS | installed | version=%s target=%s repair=%s\n' "$version" "$target" "$repair"
}

check_wrapper() {
  failures=0
  report() {
    status="$1"; label="$2"; evidence="$3"
    printf '%-5s | %-24s | %s\n' "$status" "$label" "$evidence"
    [ "$status" != FAIL ] || failures=$((failures + 1))
  }

  if grep -q 'CODEX_REMOTE_PROXY_WRAPPER' "$target" 2>/dev/null && [ -x "$real" ]; then
    report PASS 'wrapper files' "$target -> $real"
  else
    report FAIL 'wrapper files' "wrapper or codex.real missing for $version"
  fi

  pid="$(pgrep -f "${real} .*app-server" | head -n 1 || true)"
  if [ -n "$pid" ] && [ -r "/proc/$pid/environ" ]; then
    report PASS 'Codex app-server' "pid=$pid path=$real"
    env_text="$(tr '\0' '\n' < "/proc/$pid/environ")"
    for name in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY; do
      if printf '%s\n' "$env_text" | grep -qx "${name}=http://127.0.0.1:${remote_port}"; then
        report PASS "$name" "http://127.0.0.1:${remote_port}"
      else
        report FAIL "$name" 'missing or mismatched'
      fi
    done
  else
    report FAIL 'Codex app-server' 'restart Codex, then run check again'
  fi

  if ss -lnt 2>/dev/null | grep -qE "127\\.0\\.0\\.1:${remote_port}([[:space:]]|$)"; then
    report PASS 'remote listener' "127.0.0.1:${remote_port}"
  else
    report FAIL 'remote listener' "127.0.0.1:${remote_port} absent"
  fi

  if command -v wget >/dev/null 2>&1; then
    headers="$(https_proxy="http://127.0.0.1:${remote_port}" wget -S --spider --timeout=15 https://api.openai.com/v1/models 2>&1 || true)"
    status="$(printf '%s\n' "$headers" | grep -Eo 'HTTP/[0-9.]+[[:space:]]+[0-9]{3}' | tail -n 1 || true)"
    if [ -n "$status" ]; then
      report PASS 'OpenAI transport' "$status"
    else
      report FAIL 'OpenAI transport' "$(printf '%s\n' "$headers" | tail -n 1)"
    fi
  fi

  printf 'Summary: FAIL=%d\n' "$failures"
  [ "$failures" -eq 0 ]
}

rollback_latest() {
  repair="${4:-$(find "$repair_root" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort | tail -n 1)}"
  [ -n "$repair" ] || fail "no repair directory found under $repair_root"
  [ -x "$repair/rollback.sh" ] || fail "rollback script missing: $repair/rollback.sh"
  "$repair/rollback.sh" --check
  "$repair/rollback.sh" --apply
}

case "$action" in
  install) install_wrapper ;;
  check) check_wrapper ;;
  rollback) rollback_latest "$@" ;;
esac
