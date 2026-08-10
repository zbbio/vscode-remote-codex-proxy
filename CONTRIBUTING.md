# Contributing

感谢改进这个 Skill。提交变更前请遵循以下流程。

## 原则

- 先证明第一个失效边界，再提出修改。
- 使用合成夹具；不要提交真实主机、账户、地址、令牌、日志或未打码截图。
- 保持普通 SSH 会话、全局 Shell 配置和无关 VS Code Server 不受影响。
- 修改程序入口时必须保留原始文件、哈希、验证记录和可执行回滚。

## 开发流程

1. 从 `main` 创建短生命周期分支。
2. 修改 `SKILL.md`、脚本或 reference。
3. 为行为变化增加或更新隔离测试。
4. 运行：

   ```powershell
   python .\tests\validate_repository.py
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Inspect-CodexProxy.Tests.ps1
   ```

   ```bash
   bash -n scripts/*.sh tests/*.sh
   bash tests/repair-wrapper-fixture.sh
   ```

5. 检查 `git diff --check`、`git status --short` 和暂存文件列表。

## Pull request

说明以下内容：

- 观察到的失败层与证据；
- 修改的分支、字段或脚本行为；
- 基线与修改后的测试结果；
- 回滚方式；
- 是否影响已有命令行接口。

## 文档风格

- `SKILL.md` 使用简洁的祈使句。
- 将核心流程留在 `SKILL.md`，详细故障模式放入 `references/`。
- 新增脚本参数时同步更新 README、Skill 和测试。
