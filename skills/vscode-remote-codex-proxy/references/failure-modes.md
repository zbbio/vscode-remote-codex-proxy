# Failure modes and evidence

Read this reference when the basic architecture exists but Codex still fails or a previously working setup regresses.

| Symptom | Likely boundary | Strong evidence | Preferred next action |
|---|---|---|---|
| Dedicated alias will not connect | SSH parsing/authentication | `ssh -G <alias>`, Remote-SSH log | Correct alias/host/user; let the user enter the password |
| `remote port forwarding failed` | Remote listener conflict | Remote `ss -lntp`, concurrent SSH sessions | Close stale dedicated sessions or consistently choose one alternate port |
| Local proxy port is closed | Local proxy | `Get-NetTCPConnection`, direct local proxy request | Start/fix Mihomo or use its real HTTP/mixed port |
| Remote endpoint refuses connections | Reverse forward | `ssh -G`, remote `ss` | Fix `RemoteForward`; reconnect because an existing session does not change |
| Remote endpoint listens on `0.0.0.0` | Security boundary | Remote `ss` | Rebind explicitly to `127.0.0.1` |
| OpenAI request returns 401/403/404/421 | Transport works | HTTP status through the tunnel | Continue to runtime/authentication |
| Linux curl reports TLS EOF | Client TLS stack | Compare curl and wget | Use a second TLS client before blaming SSH or the proxy |
| Codex icon exists but does nothing | Contribution registered, runtime absent | Remote Linux extension path and process tree | Verify remote installation and activation |
| Extension says installed but no Linux path | Wrong installation authority | Windows versus remote extension directories | Install from the active remote integrated terminal |
| Remote extension never activates | Stale extension host | Extension-host PID before/after reload | Reload the dedicated Remote-SSH window |
| Codex process exists but `/proc/<pid>/environ` lacks proxies | Child environment boundary | Four direct environment checks | Use the isolated binary wrapper fallback after transport succeeds |
| Bootstrap script exports proxies but Codex does not | Environment stripped between processes | Bootstrap text versus `/proc/<pid>/environ` | Trust the process environment; stop editing bootstrap settings |
| `server-env-setup` exists but proxies remain absent | Server startup hook unused | Fresh Server PID plus absent process variables | Remove it from the causal path; use a verified mechanism |
| `chatgpt.cliExecutable` is configured but direct `codex` still runs | Production setting ignored | `code --status` process path | Treat the setting as inactive; use the version-bound wrapper |
| Previously working Codex regresses after extension update | Wrapper overwritten by new version | Old path had `codex.real`; newest version runs plain `codex` | Back up and wrap the new version; never reuse the old binary |
| Killing Codex shows “Codex stopped unexpectedly” | Expected restart boundary | Old PID disappears and panel offers Restart | Use Restart or reload the dedicated window |
| New process path ends in `codex.real` | Wrapper active | `code --status` plus four proxy variables | Continue to remote HTTP and minimal prompt tests |
| Sidebar renders but streams reconnect 5/5 | Runtime transport or session | Process env, tunnel request, latest logs | Find the first failed measurement; do not reinstall blindly |
| Browser authorization never returns | OAuth callback/session | Browser and extension logs without tokens | Let the user finish login, then retry from the sidebar |
| Ordinary SSH unexpectedly uses proxy | Scope leaked globally | Ordinary session environment and startup files | Remove global edits; retain per-alias isolation |
| VS Code Server cannot download remotely | Bootstrap network | Remote-SSH installation log | Set `remote.SSH.localServerDownload` to `always` |

## Regression signature learned from extension upgrades

The recurring sequence is:

1. Codex works through a wrapper in `openai.chatgpt-OLD-linux-x64`.
2. VS Code installs `openai.chatgpt-NEW-linux-x64`.
3. The extension launches the new plain `codex` binary.
4. The child process has no proxy variables even though SSH and the remote HTTP endpoint still work.
5. The UI reports `stream disconnected before completion` and `Reconnecting 5/5`.

Confirm this signature by comparing versioned process paths before changing anything. Reapply the wrapper only to the newest version and preserve its own original binary as `codex.real`.

## Evidence hierarchy

From weakest to strongest:

1. A menu item or icon appears.
2. An installation notification says success.
3. An extension ID appears in a list.
4. The extension resolves to a Linux remote path.
5. A Linux Codex child runs under the remote extension host.
6. `/proc/<pid>/environ` contains the expected proxy variables.
7. A remote request through the tunnel receives a real HTTP response.
8. Two minimal remote Codex requests complete.

## Log routing

Inspect only the implicated layer:

- SSH resolution: `ssh -G`
- Remote-SSH bootstrap: Remote-SSH output channel
- Remote extension runtime: remote extension-host log and process tree
- Codex app-server: Codex extension output/logs and `/proc/<pid>/environ`
- UI/webview: renderer log and visible Codex panel

Correlate timestamps with the latest reload. Old errors are historical evidence, not current state.
