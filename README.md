# VS Code Remote-SSH Codex Proxy Skill

让 Codex 在 VS Code Remote-SSH 环境中通过 Windows 本机代理正常工作。

当 Codex 在远端 Linux 主机上无法连接、反复重连，或在 VS Code / 扩展升级后失效时，调用这个 Skill。它不是需要单独运行的应用：你在 Codex 中调用它，Codex 会根据当前环境完成诊断、修复、验证和需要时的回滚。

## 适合遇到这些情况

- Remote-SSH 窗口中的 Codex 无法连接，或显示 `Reconnecting 5/5`、`stream disconnected before completion`。
- Windows 本机代理可用，但远端 Linux 环境无法通过代理访问服务。
- SSH 反向转发、远端 VS Code Server 或 Codex `app-server` 没有继承代理配置。
- 更新 VS Code、Remote-SSH 或 `openai.chatgpt` 扩展后，原本可用的连接再次失效。

## 它会做什么

- 定位问题是在本机代理、SSH 转发、远端网络、扩展安装，还是 Codex 进程入口。
- 只修改已经证实需要修改的专用 SSH 配置、隔离的 VS Code Server 或当前扩展入口。
- 在修改前保存原件；修改后给出可复查的验证结果和可执行的回滚方式。

## 安装

### 在 Codex 中安装

在 Codex 中调用 `$skill-installer` 并提供下面的 Skill 目录 URL：

```text
https://github.com/zbbio/vscode-remote-codex-proxy/tree/main/skills/vscode-remote-codex-proxy
```

安装后新开一个任务，或重启 Codex，使它发现新 Skill。

### 手动安装

```powershell
$repository = Join-Path $HOME 'src\vscode-remote-codex-proxy'
git clone https://github.com/zbbio/vscode-remote-codex-proxy.git $repository
$source = Join-Path $repository 'skills\vscode-remote-codex-proxy'
$skillRoot = Join-Path $HOME '.codex\skills'
$target = Join-Path $skillRoot 'vscode-remote-codex-proxy'
Copy-Item -LiteralPath $source -Destination $target -Recurse
```

## 使用

在 Codex 中明确调用：

```text
Use $vscode-remote-codex-proxy to diagnose my Remote-SSH Codex connection.
```

也可以直接描述现象，例如“Remote-SSH 里的 Codex 一直重连，帮我检查代理”。Skill 会收集必要的环境信息，并按发现的问题继续处理。

## 这是一个 Skill，不是另一个应用

运行时入口是 [`skills/vscode-remote-codex-proxy/SKILL.md`](skills/vscode-remote-codex-proxy/SKILL.md)。它包含给 Codex 的操作步骤、命令和判断条件。

仓库根目录的 [`.codex-plugin/plugin.json`](.codex-plugin/plugin.json) 只提供打包和分发元数据。实际被 Codex 加载和执行的是上述 Skill 目录，因此仓库的 README、CI 和测试不会占用 Skill 的运行时上下文。

## 支持范围

- 本地：Windows、VS Code、Remote-SSH、OpenSSH client，以及 HTTP/mixed proxy。
- 远端：Linux x86_64、Bash、VS Code Server 和 `openai.chatgpt-*-linux-x64` 扩展。
- 网络：远端通过 SSH reverse forward 访问 Windows 本机回环代理。

当前 Wrapper 修复只支持 `bin/linux-x86_64/codex`。其他 CPU 架构需要先补充对应的定位逻辑和回归测试。

## 诊断、修复与回滚

通常直接调用 Skill 即可。它会先运行只读检查，再决定是否需要修改。若需要为 Codex 入口添加代理 Wrapper，安装程序会保存原始二进制、生成验证记录和回滚脚本；扩展升级后也会重新检查入口是否发生变化。

本地只读诊断脚本也可以单独运行：

```powershell
.\skills\vscode-remote-codex-proxy\scripts\Inspect-CodexProxy.ps1 `
  -HostAlias codex-example `
  -LocalProxyPort 7897 `
  -RemoteProxyPort 17897
```

诊断输出默认隐藏用户名、主机名和代理变量值。脚本退出码为：`0` 表示没有失败检查，`1` 表示至少一个检查失败，`2` 表示参数错误。

## 技术细节

以下内容供想了解实现或参与维护的人查阅，不是首次使用前必须阅读的内容：

- [运行时操作步骤](skills/vscode-remote-codex-proxy/SKILL.md)
- [诊断与变更流程](skills/vscode-remote-codex-proxy/references/control-loop.md)
- [常见故障模式](skills/vscode-remote-codex-proxy/references/failure-modes.md)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)

## 开发验证

```powershell
python .\tests\validate_repository.py
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Inspect-CodexProxy.Tests.ps1
python "$HOME\.codex\skills\.system\skill-creator\scripts\quick_validate.py" .\skills\vscode-remote-codex-proxy
python "$HOME\.codex\skills\.system\plugin-creator\scripts\validate_plugin.py" .
```

Linux 或 WSL：

```bash
bash -n skills/vscode-remote-codex-proxy/scripts/*.sh tests/*.sh
shellcheck skills/vscode-remote-codex-proxy/scripts/*.sh tests/*.sh
bash tests/inspect-remote-fixture.sh
bash tests/repair-wrapper-fixture.sh
```

> 本项目与 OpenAI、Microsoft、Clash 或 Mihomo 没有隶属或背书关系。

## License

[Apache License 2.0](LICENSE)
