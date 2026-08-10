#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/skills/vscode-remote-codex-proxy/scripts/repair_codex_proxy_wrapper.sh"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

server_root="$fixture/.vscode-server"
target="$server_root/extensions/openai.chatgpt-1.2.3-linux-x64/bin/linux-x86_64/codex"
mkdir -p "$(dirname "$target")"
cat > "$target" <<'ORIGINAL'
#!/bin/sh
echo ORIGINAL_BEHAVIOR
ORIGINAL
chmod 755 "$target"

baseline_hash="$(sha256sum "$target" | awk '{print $1}')"

"$script" install 17897 "$server_root"
grep -q CODEX_REMOTE_PROXY_WRAPPER "$target"
[ -x "${target}.real" ]

repair_dir="$(find "$fixture/repairs" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
for artifact in codex.original codex.wrapper original.sha256 patch.txt rollback.sh verification.txt; do
  [ -f "$repair_dir/$artifact" ]
done

"$repair_dir/rollback.sh" --check

# Refuse to overwrite a target that changed after wrapper installation.
printf '\n# fixture drift\n' >> "$target"
if "$script" rollback 17897 "$server_root" "$repair_dir" >/dev/null 2>&1; then
  echo 'FAIL | rollback overwrote a changed target' >&2
  exit 1
fi
cp -p "$repair_dir/codex.wrapper" "$target"

"$script" rollback 17897 "$server_root" "$repair_dir"
[ ! -e "${target}.real" ]
[ "$(sha256sum "$target" | awk '{print $1}')" = "$baseline_hash" ]
[ "$("$target")" = ORIGINAL_BEHAVIOR ]

# A complete rollback must permit a clean second installation.
sleep 1
"$script" install 17897 "$server_root"
second_repair="$(find "$fixture/repairs" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
"$script" rollback 17897 "$server_root" "$second_repair"
[ "$("$target")" = ORIGINAL_BEHAVIOR ]

if "$script" install 70000 "$server_root" >/dev/null 2>&1; then
  echo 'FAIL | invalid port was accepted' >&2
  exit 1
fi

# A failed atomic commit must leave the original executable in place while the
# prebuilt evidence and rollback artifacts remain available for diagnosis.
transaction_server="$fixture/transaction/.vscode-server"
transaction_target="$transaction_server/extensions/openai.chatgpt-9.9.9-linux-x64/bin/linux-x86_64/codex"
mkdir -p "$(dirname "$transaction_target")" "$fixture/failing-bin"
cp -p "$repair_dir/codex.original" "$transaction_target"
cat > "$fixture/failing-bin/mv" <<'FAIL_MV'
#!/bin/sh
exit 73
FAIL_MV
chmod 755 "$fixture/failing-bin/mv"
transaction_hash="$(sha256sum "$transaction_target" | awk '{print $1}')"
if PATH="$fixture/failing-bin:$PATH" "$script" install 17897 "$transaction_server" >/dev/null 2>&1; then
  echo 'FAIL | simulated atomic commit failure was accepted' >&2
  exit 1
fi
[ "$(sha256sum "$transaction_target" | awk '{print $1}')" = "$transaction_hash" ]
[ ! -e "${transaction_target}.real" ]
transaction_repair="$(find "$fixture/transaction/repairs" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
for artifact in codex.original codex.wrapper original.sha256 patch.txt rollback.sh verification.txt; do
  [ -f "$transaction_repair/$artifact" ]
done

printf 'PASS | repair wrapper install/artifacts/drift-guard/rollback/reinstall/atomic-failure\n'
