---
name: vscode-remote-codex-proxy
description: Set up, verify, repair, and roll back the proxy path for Codex in VS Code Remote-SSH when a Linux remote host must reach the network through a Windows local HTTP or mixed proxy over an SSH reverse tunnel. Use when the user wants to run Codex inside VS Code Remote-SSH through a Windows proxy, or for missing remote Codex, `openai.chatgpt`, `stream disconnected before completion`, `Reconnecting 5/5`, remote extension upgrades, proxy variables missing from the Codex child process, or recurring failures after a previously working setup.
---

# VS Code Remote-SSH Codex Proxy

Treat the setup as a controlled distributed system:

`Codex UI -> remote extension host -> Linux Codex app-server -> remote 127.0.0.1:<remote-port> -> SSH reverse tunnel -> local 127.0.0.1:<local-port> -> OpenAI`

Set up or repair the first required boundary only. Preserve evidence, scope every change to the dedicated SSH alias and isolated VS Code Server, and verify the final behavior with a real Codex response.

## Safety and scope

- Let the user enter SSH passwords and complete browser authorization. Never store passwords, tokens, cookies, or authorization URLs.
- Bind the remote proxy endpoint to `127.0.0.1`.
- Keep ordinary SSH sessions and unrelated remote programs unchanged.
- Do not edit `.bashrc`, `.profile`, system proxy settings, firewall rules, or remote services for a dedicated-window deployment.
- Back up every edited file and preserve the original Codex binary before wrapping it.
- Treat a VS Code/Codex extension update as configuration drift: it may install a new versioned directory and replace the wrapper.
- Apply the bundled discovery and wrapper scripts only to Linux x86_64 extension layouts (`*-linux-x64/bin/linux-x86_64`). Classify any other architecture as unsupported until its path and executable behavior have dedicated tests.

## Inputs

Discover rather than guess:

```text
<alias>        dedicated SSH alias
<host>         remote hostname or IP
<user>         remote Linux account
<local-port>   local HTTP/mixed proxy port
<remote-port>  remote loopback proxy port
<server-root>  isolated VS Code Server root
```

Read [references/control-loop.md](references/control-loop.md) before deployment and [references/failure-modes.md](references/failure-modes.md) when a working setup regresses.

## Control loop

### 1. Define acceptance criteria

- `ssh -G <alias>` resolves the intended host/user and exact reverse forward.
- The local proxy listens on `127.0.0.1:<local-port>`.
- The remote endpoint listens only on `127.0.0.1:<remote-port>`.
- A remote request through that endpoint receives a real OpenAI HTTP response.
- `openai.chatgpt-<version>-linux-x64` exists under the isolated Server.
- A Linux Codex `app-server` runs under the remote extension host.
- The Codex process either inherits the four proxy variables natively or runs through the verified wrapper.
- Two minimal Codex prompts complete without reconnect loops.

### 2. Observe the baseline

Run locally:

```powershell
ssh -G <alias>
Get-NetTCPConnection -State Listen -LocalPort <local-port>
code --status
scripts/Inspect-CodexProxy.ps1 -HostAlias <alias> -LocalProxyPort <local-port> -RemoteProxyPort <remote-port>
```

Pass `-SshConfigPath` and `-VsCodeSettingsPath` when the active files are not at their defaults. The Windows diagnostic accepts VS Code JSONC comments and trailing commas. Both diagnostic scripts return `1` when any check is `FAIL` and `2` for invalid arguments; use `-AlwaysExitZero` only when a report collector requires exit `0`.

Run in the active remote integrated terminal:

```bash
scripts/inspect_remote_codex.sh <remote-port>
```

Use `<remote-port> --always-zero` only for report collection that must not propagate failed checks.

Record the remote extension version and process path. A transition from:

```text
.../openai.chatgpt-OLD-linux-x64/.../codex.real ... app-server
```

to:

```text
.../openai.chatgpt-NEW-linux-x64/.../codex ... app-server
```

is strong evidence that an extension update replaced the version-bound wrapper.

### 3. Classify the first broken boundary

1. Local proxy
2. SSH alias and reverse forward
3. Remote loopback listener
4. Remote TLS/HTTP reachability
5. Remote Linux extension installation
6. Extension activation and Codex process
7. Codex child-process proxy environment
8. Browser authorization
9. Minimal Codex request

Do not patch the Codex binary while layers 1-6 are unproven.

## Baseline deployment

Use a dedicated alias:

```sshconfig
Host <alias>
    HostName <host>
    User <user>
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ExitOnForwardFailure yes
    RemoteForward 127.0.0.1:<remote-port> 127.0.0.1:<local-port>
```

Configure only that alias in VS Code and merge with existing settings:

```json
{
  "remote.SSH.remotePlatform": { "<alias>": "linux" },
  "remote.SSH.httpProxy": { "<alias>": "http://127.0.0.1:<remote-port>" },
  "remote.SSH.httpsProxy": { "<alias>": "http://127.0.0.1:<remote-port>" },
  "remote.SSH.serverInstallPath": { "<alias>": "/home/<user>/.vscode-server-codex-proxy" },
  "remote.SSH.localServerDownload": "always"
}
```

Install `openai.chatgpt` from the active remote integrated terminal. Verify a Linux path rather than trusting a local extension list.

## Diagnose child-process proxy inheritance

VS Code Remote-SSH proxy settings can successfully bootstrap the Server while the Codex child process still receives no proxy variables. Do not infer child inheritance from bootstrap logs.

Find the remote Codex PID from `code --status`, then inspect it directly:

```bash
tr '\0' '\n' < /proc/<codex-pid>/environ \
  | grep -E '^(http_proxy|https_proxy|HTTP_PROXY|HTTPS_PROXY)='
```

Require all four variables to equal `http://127.0.0.1:<remote-port>` when using the wrapper.

Do not spend repeated cycles on mechanisms already disproven by process evidence. Current production combinations may ignore or strip:

- proxy variables exported only by the Remote-SSH bootstrap shell;
- isolated `server-env-setup` files;
- the development-only `chatgpt.cliExecutable` setting.

Treat these as hypotheses until `/proc/<pid>/environ` proves inheritance.

## Version-bound binary wrapper fallback

Use this fallback only when transport works, the Linux extension and app-server exist, and the Codex child lacks proxy variables.

The bundled script is local to the skill. Transfer it to a private path on the remote host with `scp` or a base64 paste through the active integrated terminal; do not assume a local skill path exists remotely. Set mode `700`, then run the remote copy:

```bash
/home/<user>/.vscode-server-codex-proxy/tools/repair_codex_proxy_wrapper.sh \
  install <remote-port> <server-root>
```

The script:

- locates the newest `openai.chatgpt-*-linux-x64` directory;
- hashes and preserves the original binary;
- stores the original as `codex.real`;
- atomically replaces `codex` with a wrapper that exports lower- and upper-case HTTP/HTTPS proxy variables;
- creates `codex.wrapper`, `patch.txt`, `verification.txt`, and `rollback.sh` under `<repair-root>/<timestamp>-<pid>`, where `<repair-root> = ${server-root%/.vscode-server}/repairs`;
- builds every evidence and rollback artifact before atomically committing the wrapper, and restores the original target if the commit sequence fails;
- refuses to overwrite an existing preserved binary;
- validates ports and required Linux commands before modification.

Restart only the Codex app-server or reload the dedicated Remote-SSH window. If the panel reports that Codex stopped, use its **Restart** action.

Verify after restart:

```bash
/home/<user>/.vscode-server-codex-proxy/tools/repair_codex_proxy_wrapper.sh \
  check <remote-port> <server-root>
```

Strong runtime evidence includes `codex.real ... app-server`, four matching proxy variables, a loopback listener, and a real remote OpenAI HTTP response.

### Upgrade drift rule

Every extension upgrade creates a new versioned directory. Re-run observation before repair. If the newest process path uses plain `codex` and the new directory lacks `codex.real`, apply the wrapper to that new version. Never copy an old binary into a new extension version.

## Independent measurements

Local proxy:

```powershell
curl.exe -x http://127.0.0.1:<local-port> -I https://api.openai.com/v1/models
```

Remote tunnel:

```bash
https_proxy=http://127.0.0.1:<remote-port> \
  wget -S --spider --timeout=15 https://api.openai.com/v1/models
```

HTTP `401`, `403`, `404`, or `421` proves CONNECT, TLS, and HTTP transport. A Linux `curl` TLS EOF alongside a successful `wget` result indicates client-stack variation, not a broken tunnel.

Finish with two harmless prompts in the remote Codex view. A visible answer is stronger evidence than process or transport checks alone.

## Rollback

Run the repair-specific rollback generated during installation:

```bash
<repair-root>/<timestamp>-<pid>/rollback.sh --check
<repair-root>/<timestamp>-<pid>/rollback.sh --apply
```

Then restart the Codex app-server. Rollback restores only that extension version's original binary.
It verifies the stored original, preserved binary, and currently installed wrapper hashes before applying. If the target changed after installation, stop and diagnose upgrade drift rather than overwriting it. A successful rollback removes the version-local `codex.real`; the timestamped repair directory retains the preserved original and evidence.

## Report

Return:

```markdown
# Outcome
[working / partially working]

## First broken layer
[fact and evidence]

## Controls applied
[exact scoped files and changed behavior]

## Measurements
[baseline and modified commands, literal outcomes, exit statuses]

## Artifacts
[modified wrapper, preserved original, patch record, verification record, rollback]

## Upgrade note
[current extension version and drift rule]
```
