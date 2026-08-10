# VS Code Remote-SSH Codex Proxy Plugin

这是一个社区维护的 Codex Plugin，用证据驱动的工程控制论循环诊断、修复、验证和回滚以下链路：

```text
Codex UI
  -> Remote-SSH extension host
  -> Linux x86_64 Codex app-server
  -> remote 127.0.0.1:<remote-port>
  -> SSH reverse tunnel
  -> Windows 127.0.0.1:<local-port>
  -> HTTP/mixed proxy
  -> OpenAI
```

核心原则：先定义可观测的成功条件，再寻找第一个失效边界；每次只改变一个边界，并用独立测量决定保留还是回滚。

> 本项目与 OpenAI、Microsoft、Clash 或 Mihomo 没有隶属或背书关系。

## 发布结构

本仓库采用 **Plugin 仓库** 结构，运行时 Skill 位于 `skills/vscode-remote-codex-proxy/`：

```text
.codex-plugin/plugin.json
skills/vscode-remote-codex-proxy/
  SKILL.md
  agents/openai.yaml
  scripts/
  references/
  evals/evals.json
tests/
.github/workflows/validate.yml
```

选择 Plugin 而不是“仓库根目录即 Skill”，是因为仓库级 README、CI 和测试不应被安装进 Skill 的运行时上下文。Skill 目录仍可被独立复制安装。

## 支持边界

- 本地：Windows、VS Code、Remote-SSH、OpenSSH client、HTTP/mixed proxy。
- 远端：Linux **x86_64**、Bash、VS Code Server、`openai.chatgpt-*-linux-x64`。
- 网络：远端仅通过 SSH reverse forward 访问本地回环代理。
- 变更范围：专用 SSH 别名、隔离的 VS Code Server、当前版本的 Codex 二进制入口。

当前 Wrapper 定位逻辑仅支持 `bin/linux-x86_64/codex`。其他 CPU 架构应先扩展定位和回归夹具，不能直接套用。

## 安装

仓库发布到 GitHub 后，可在 Codex 中调用 `$skill-installer`，要求从该 GitHub 仓库安装 `vscode-remote-codex-proxy`。

独立 Skill 的手动安装方式：

```powershell
$source = Join-Path (Get-Location) 'skills\vscode-remote-codex-proxy'
$target = Join-Path $HOME '.agents\skills\vscode-remote-codex-proxy'
Copy-Item -LiteralPath $source -Destination $target -Recurse
```

重启 Codex 或开启新任务后显式调用：

```text
Use $vscode-remote-codex-proxy to diagnose my Remote-SSH Codex connection.
```

## 诊断

本地只读诊断：

```powershell
.\skills\vscode-remote-codex-proxy\scripts\Inspect-CodexProxy.ps1 `
  -HostAlias codex-example `
  -LocalProxyPort 7897 `
  -RemoteProxyPort 17897
```

远端只读诊断：

```bash
bash inspect_remote_codex.sh 17897
```

诊断脚本默认不输出用户名、主机名或代理变量值。退出码为：`0` 无失败、`1` 至少一个检查失败、`2` 参数错误。`--always-zero` 仅用于必须返回零的报告采集器。

## Wrapper 修复与回滚

仅在本地代理、SSH 反向转发、远端真实 HTTP 响应、Linux 扩展和 Codex `app-server` 已被证实时使用：

```bash
bash repair_codex_proxy_wrapper.sh install 17897 "$HOME/.vscode-server-codex-proxy/.vscode-server"
bash repair_codex_proxy_wrapper.sh check 17897 "$HOME/.vscode-server-codex-proxy/.vscode-server"
bash repair_codex_proxy_wrapper.sh rollback 17897 "$HOME/.vscode-server-codex-proxy/.vscode-server"
```

定义：

```text
<repair-root> = ${server-root%/.vscode-server}/repairs
```

安装在替换目标前先生成保存原件、Wrapper 副本、补丁说明、验证记录和可执行回滚脚本。目标通过原子 `mv` 提交；提交失败时恢复原状态。回滚同时校验原始文件、保留二进制和当前 Wrapper 的 SHA-256，避免覆盖升级后的程序。

## 本地验证

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

GitHub Actions 会在 Ubuntu 与 Windows 重复结构、语法、脱敏、失败码、回滚和本地监听边界测试。

## 首次 GitHub 发布清单

1. 创建 GitHub 仓库并设置 `origin`。
2. 推送默认分支与 `v0.1.0` 标签。
3. 确认 Actions 全绿，并将工作流设为分支保护的必需检查。
4. 启用 Secret scanning、Push protection、Dependabot 与私密漏洞报告。
5. 创建 GitHub Release，核对版本与 `.codex-plugin/plugin.json` 一致。
6. 用全新目录执行一次安装、显式调用、失败诊断、修复和回滚冒烟测试。

私密漏洞报告只有在 GitHub 仓库创建并启用 **Security → Advisories → Private vulnerability reporting** 后才真正可用。

## 参考与贡献

- [Codex Skills 官方文档](https://developers.openai.com/codex/build-skills)
- [Codex Plugins 官方文档](https://developers.openai.com/plugins/build/plugins)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)

## License

[Apache License 2.0](LICENSE)
