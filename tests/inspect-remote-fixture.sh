#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/skills/vscode-remote-codex-proxy/scripts/inspect_remote_codex.sh"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

fakebin="$fixture/bin"
home="$fixture/home/fixture-user"
proc_root="$fixture/proc"
codex="$home/.vscode-server/extensions/openai.chatgpt-1.2.3-linux-x64/bin/linux-x86_64/codex"
mkdir -p "$fakebin" "$(dirname "$codex")" "$proc_root/4242"
printf '#!/bin/sh\nexit 0\n' > "$codex"
chmod 755 "$codex"

cat > "$fakebin/ss" <<'EOF'
#!/bin/sh
printf 'LISTEN 0 128 127.0.0.1:17897 0.0.0.0:*\n'
EOF
cat > "$fakebin/pgrep" <<EOF
#!/bin/sh
printf '4242 %s app-server\n' '$codex'
EOF
cat > "$fakebin/wget" <<'EOF'
#!/bin/sh
printf '  HTTP/1.1 401 Unauthorized\n' >&2
exit 1
EOF
chmod 755 "$fakebin/ss" "$fakebin/pgrep" "$fakebin/wget"

write_env() {
  printf '%s\0' "$@" > "$proc_root/4242/environ"
}

secret='socks5://secret-user:secret-pass@proxy.example:1080'
write_env \
  'http_proxy=http://127.0.0.1:17897' \
  'https_proxy=http://127.0.0.1:17897' \
  'HTTP_PROXY=http://127.0.0.1:17897'

set +e
output="$(HOME="$home" PATH="$fakebin:$PATH" CODEX_INSPECT_PROC_ROOT="$proc_root" ALL_PROXY="$secret" "$script" 17897 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ]
printf '%s\n' "$output" | grep -qE 'FAIL[[:space:]]+\| Codex HTTPS_PROXY[[:space:]]+\| missing or different'
printf '%s\n' "$output" | grep -q 'configured names:'
if printf '%s\n' "$output" | grep -qE 'secret-user|secret-pass|proxy\.example|fixture-user'; then
  echo 'FAIL | diagnostic output disclosed fixture identity or proxy credentials' >&2
  exit 1
fi

write_env \
  'http_proxy=http://127.0.0.1:17897' \
  'https_proxy=http://127.0.0.1:17897' \
  'HTTP_PROXY=http://127.0.0.1:17897' \
  'HTTPS_PROXY=http://127.0.0.1:17897'

output="$(HOME="$home" PATH="$fakebin:$PATH" CODEX_INSPECT_PROC_ROOT="$proc_root" ALL_PROXY="$secret" "$script" 17897 2>&1)"
printf '%s\n' "$output" | grep -q 'Summary: FAIL=0'

printf 'PASS | remote diagnostic redaction/missing-env/complete-env\n'
