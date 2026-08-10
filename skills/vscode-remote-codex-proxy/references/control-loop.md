# Engineering-control loop for Remote-SSH Codex

Use this reference when planning a deployment or explaining why a troubleshooting action is justified.

## Contents

- [1. System model](#1-system-model)
- [2. Control vocabulary](#2-control-vocabulary)
- [3. State vector](#3-state-vector)
- [4. Observation phase](#4-observation-phase)
- [5. Hypothesis phase](#5-hypothesis-phase)
- [6. Control phase](#6-control-phase)
- [7. Measurement phase](#7-measurement-phase)
- [8. Disturbance phase](#8-disturbance-phase)
- [9. Stop conditions](#9-stop-conditions)

## 1. System model

The user-visible output is a functioning Codex conversation in a remote VS Code workspace. It depends on a chain of subsystems:

```text
User input
  ↓
VS Code renderer and Codex webview
  ↓
remote extension host
  ↓
Linux openai.chatgpt extension
  ↓
Linux codex app-server
  ↓
HTTP proxy at remote loopback
  ↓
SSH reverse forwarding channel
  ↓
local Mihomo/Clash HTTP or mixed port
  ↓
OpenAI
```

A failure observed at the top can originate in any lower layer. Reinstalling the UI cannot repair a broken transport layer, and changing the proxy cannot install a missing Linux extension.

## 2. Control vocabulary

| Control concept | Project meaning |
|---|---|
| Reference value | Codex answers a minimal request in the remote workspace |
| Plant | VS Code, SSH, remote server, extension, proxy, and OpenAI |
| Sensors | Logs, process tree, port listeners, paths, HTTP responses |
| Controller | The troubleshooting agent and user-approved changes |
| Actuators | SSH config, VS Code settings, extension installation, reconnect |
| Disturbances | Port conflicts, stale extension hosts, proxy shutdown, TLS-client differences |
| Feedback | Measurements taken after each minimal change |

## 3. State vector

Track these booleans or concrete values:

```text
L = local proxy listens and reaches OpenAI
S = dedicated SSH alias resolves to intended host/user
R = reverse forward is active on remote loopback
T = remote client completes TLS and receives HTTP
E = Linux extension exists in isolated VS Code Server
A = extension activates and starts Linux Codex app-server
O = browser authorization completes
Q = minimal Codex request succeeds
```

The useful state is:

```text
L ∧ S ∧ R ∧ T ∧ E ∧ A ∧ O ∧ Q
```

Diagnose from left to right. The first false term is normally the next control target.

## 4. Observation phase

Capture baseline evidence before writes:

1. Hash or copy files that may change.
2. Record current SSH alias resolution with `ssh -G`.
3. Record local proxy listener and direct OpenAI response.
4. Record the active Remote-SSH alias and isolated server path.
5. Record remote proxy environment, listener, extension path, and process tree.
6. Record whether the Codex view is built-in chat or the `openai.chatgpt` view.

Avoid collecting secrets. Redact credentials embedded in URLs.

## 5. Hypothesis phase

Phrase hypotheses so they can be falsified:

- Good: “The extension is installed only on Windows; a Linux extension path will be absent.”
- Weak: “VS Code is buggy.”
- Good: “The reverse tunnel works, but Linux curl has a TLS-stack-specific failure; wget should receive an HTTP response.”
- Weak: “The proxy is broken.”

Predict an observable result before applying a control.

## 6. Control phase

Choose the action with the smallest blast radius:

1. Dedicated alias instead of changing an existing shared host entry.
2. Remote loopback listener instead of LAN exposure.
3. Per-alias VS Code settings instead of account-wide shell variables.
4. Isolated VS Code Server directory instead of reusing a polluted server.
5. One-command proxy variables instead of editing `.bashrc`.
6. Remote integrated-terminal installation instead of ambiguous local CLI flags.

Change one boundary at a time. Multiple simultaneous changes destroy causal attribution.

## 7. Measurement phase

After every control:

1. Verify the configuration was parsed, not merely written.
2. Verify a new process or listener exists where expected.
3. Exercise the next boundary with an independent request.
4. Compare the observation with the prediction.
5. Keep or revert the change based on evidence.

The strongest success signal is end-to-end behavior. Intermediate signals remain valuable because they localize failures.

## 8. Disturbance phase

Test whether recovery is repeatable:

- Disconnect and reconnect the dedicated alias.
- Confirm the remote port disappears and returns.
- Restart VS Code and confirm the Linux extension reactivates.
- Temporarily stop and restore the local proxy with user permission.
- Confirm an ordinary SSH alias remains unaffected.

The goal is stable feedback behavior, not a one-time lucky success.

## 9. Stop conditions

Stop and ask the user when:

- A password, MFA, or ChatGPT authorization is required.
- The desired proxy scope is ambiguous.
- The only remaining action would modify global shell or system settings.
- A port is owned by an unknown process and changing it could affect other work.
- Existing user changes overlap the proposed edits.

Do not call a system complete until the minimal Codex request returns successfully or clearly state that authorization remains.
