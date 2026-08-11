$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root 'skills\vscode-remote-codex-proxy\scripts\Inspect-CodexProxy.ps1'
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-proxy-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null

try {
    $sshConfig = Join-Path $fixture 'ssh-config'
    $settings = Join-Path $fixture 'settings.json'

    @'
Host codex-audit-fixture
    HostName 203.0.113.10
    User fixture
    RemoteForward 127.0.0.1:17897 127.0.0.1:9
'@ | Set-Content -LiteralPath $sshConfig -Encoding ASCII

    @'
{
  // Keep URL text intact while removing this comment.
  "remote.SSH.remotePlatform": { "codex-audit-fixture": "linux" },
  "remote.SSH.httpProxy": { "codex-audit-fixture": "http://127.0.0.1:17897" },
  "remote.SSH.httpsProxy": { "codex-audit-fixture": "http://127.0.0.1:17897" },
  "remote.SSH.serverInstallPath": {
    "codex-audit-fixture": "/home/fixture/.vscode-server-codex-proxy",
  },
}
'@ | Set-Content -LiteralPath $settings -Encoding UTF8

    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script `
        -HostAlias codex-audit-fixture `
        -LocalProxyPort 9 `
        -RemoteProxyPort 17897 `
        -SshConfigPath $sshConfig `
        -VsCodeSettingsPath $settings `
        -SkipNetwork `
        -AsJson `
        -AlwaysExitZero

    Assert-True ($LASTEXITCODE -eq 0) 'AlwaysExitZero should return 0'
    $results = ($output -join "`n") | ConvertFrom-Json

    $alias = $results | Where-Object Check -eq 'Alias resolves'
    $forward = $results | Where-Object Check -eq 'Reverse forward parsed'
    $jsonc = $results | Where-Object Check -eq 'VS Code settings parse'
    $proxy = $results | Where-Object Check -eq 'Per-alias proxy'

    Assert-True ($alias.Status -eq 'PASS') 'custom SSH alias should resolve'
    Assert-True ($alias.Evidence -eq 'host=203.0.113.10 user=fixture') 'custom SSH config must be used by ssh -G'
    Assert-True ($forward.Status -eq 'PASS') 'fixture reverse forward should parse'
    Assert-True ($jsonc.Status -eq 'PASS') 'VS Code JSONC should parse'
    Assert-True ($proxy.Status -eq 'PASS') 'URLs containing // must survive JSONC comment removal'

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script `
        -HostAlias codex-audit-fixture `
        -LocalProxyPort 9 `
        -RemoteProxyPort 17897 `
        -SshConfigPath $sshConfig `
        -VsCodeSettingsPath $settings `
        -SkipNetwork `
        -AsJson *> $null

    Assert-True ($LASTEXITCODE -eq 1) 'a FAIL result should produce exit code 1'

    # GitHub-hosted Windows runners can emit a harmless OpenSSH warning on
    # stderr even when `ssh -G` exits successfully. The diagnostic must treat
    # native exit status, not the presence of stderr, as the control signal.
    $fakeBin = Join-Path $fixture 'fake-bin'
    New-Item -ItemType Directory -Path $fakeBin | Out-Null
    @'
@echo off
1>&2 echo Pseudo-terminal will not be allocated because stdin is not a terminal.
echo host codex-audit-fixture
echo hostname 203.0.113.10
echo user fixture
echo remoteforward 127.0.0.1:17897 127.0.0.1:9
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $fakeBin 'ssh.cmd') -Encoding ASCII

    $originalPath = $env:PATH
    try {
        $env:PATH = "$fakeBin;$originalPath"
        $noisyOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script `
            -HostAlias codex-audit-fixture `
            -LocalProxyPort 9 `
            -RemoteProxyPort 17897 `
            -SshConfigPath $sshConfig `
            -VsCodeSettingsPath $settings `
            -SkipNetwork `
            -AsJson `
            -AlwaysExitZero
        Assert-True ($LASTEXITCODE -eq 0) 'successful ssh with stderr warning must not bypass AlwaysExitZero'
        $noisyResults = ($noisyOutput -join "`n") | ConvertFrom-Json
        $noisyAlias = $noisyResults | Where-Object Check -eq 'Alias resolves'
        Assert-True ($noisyAlias.Status -eq 'PASS') 'ssh -G stdout must remain parseable when stderr has a warning'
    } finally {
        $env:PATH = $originalPath
    }

    $anyListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, 0)
    try {
        $anyListener.Start()
        $anyPort = ([System.Net.IPEndPoint]$anyListener.LocalEndpoint).Port
        $anyOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script `
            -HostAlias codex-audit-fixture `
            -LocalProxyPort $anyPort `
            -RemoteProxyPort 17897 `
            -SshConfigPath $sshConfig `
            -VsCodeSettingsPath $settings `
            -SkipNetwork `
            -AsJson `
            -AlwaysExitZero
        $anyResult = (($anyOutput -join "`n") | ConvertFrom-Json) |
            Where-Object Check -eq 'Local port listening'
        Assert-True ($anyResult.Status -eq 'FAIL') '0.0.0.0 listener must not pass the loopback boundary'
        Assert-True ($anyResult.Evidence -match 'non-loopback listener') 'failure must identify the widened binding'
    } finally {
        $anyListener.Stop()
    }

    $loopbackListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $loopbackListener.Start()
        $loopbackPort = ([System.Net.IPEndPoint]$loopbackListener.LocalEndpoint).Port
        $loopbackOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script `
            -HostAlias codex-audit-fixture `
            -LocalProxyPort $loopbackPort `
            -RemoteProxyPort 17897 `
            -SshConfigPath $sshConfig `
            -VsCodeSettingsPath $settings `
            -SkipNetwork `
            -AsJson `
            -AlwaysExitZero
        $loopbackResult = (($loopbackOutput -join "`n") | ConvertFrom-Json) |
            Where-Object Check -eq 'Local port listening'
        Assert-True ($loopbackResult.Status -eq 'PASS') '127.0.0.1 listener should pass the loopback boundary'
    } finally {
        $loopbackListener.Stop()
    }

    Write-Output 'PASS | Inspect-CodexProxy.ps1 fixtures'
} finally {
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
