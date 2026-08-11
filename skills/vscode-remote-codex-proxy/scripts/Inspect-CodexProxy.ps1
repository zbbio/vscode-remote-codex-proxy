[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostAlias,

    [ValidateRange(1, 65535)]
    [int]$LocalProxyPort = 7897,
    [ValidateRange(1, 65535)]
    [int]$RemoteProxyPort = 17897,

    [string]$SshConfigPath = "$HOME\.ssh\config",
    [string]$VsCodeSettingsPath = "$env:APPDATA\Code\User\settings.json",

    [switch]$SkipNetwork,
    [switch]$AsJson,
    [switch]$AlwaysExitZero
)

$ErrorActionPreference = 'Stop'
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string]$Layer,
        [string]$Check,
        [ValidateSet('PASS', 'FAIL', 'WARN', 'INFO')]
        [string]$Status,
        [string]$Evidence
    )

    $results.Add([pscustomobject]@{
        Layer    = $Layer
        Check    = $Check
        Status   = $Status
        Evidence = $Evidence
    })
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    $previousPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 materializes native stderr as ErrorRecord
        # objects. Preserve those records as evidence and let the process exit
        # code decide success instead of treating every warning as terminating.
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = @($output | ForEach-Object { $_.ToString() })
    }
}

function Get-MapValue {
    param($Map, [string]$Name)
    if ($null -eq $Map) { return $null }
    $property = $Map.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Remove-JsonComments {
    param([Parameter(Mandatory = $true)][string]$Text)

    $output = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    $inLineComment = $false
    $inBlockComment = $false

    for ($index = 0; $index -lt $Text.Length; $index++) {
        $current = $Text[$index]
        $next = if ($index + 1 -lt $Text.Length) { $Text[$index + 1] } else { [char]0 }

        if ($inLineComment) {
            if ($current -eq "`n") {
                $inLineComment = $false
                [void]$output.Append($current)
            }
            continue
        }

        if ($inBlockComment) {
            if ($current -eq '*' -and $next -eq '/') {
                $inBlockComment = $false
                $index++
            } elseif ($current -eq "`n") {
                [void]$output.Append($current)
            }
            continue
        }

        if ($inString) {
            [void]$output.Append($current)
            if ($escaped) {
                $escaped = $false
            } elseif ($current -eq [char]92) {
                $escaped = $true
            } elseif ($current -eq [char]34) {
                $inString = $false
            }
            continue
        }

        if ($current -eq [char]34) {
            $inString = $true
            [void]$output.Append($current)
        } elseif ($current -eq '/' -and $next -eq '/') {
            $inLineComment = $true
            $index++
        } elseif ($current -eq '/' -and $next -eq '*') {
            $inBlockComment = $true
            $index++
        } else {
            [void]$output.Append($current)
        }
    }

    return $output.ToString()
}

function Remove-JsonTrailingCommas {
    param([Parameter(Mandatory = $true)][string]$Text)

    $output = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false

    for ($index = 0; $index -lt $Text.Length; $index++) {
        $current = $Text[$index]

        if ($inString) {
            [void]$output.Append($current)
            if ($escaped) {
                $escaped = $false
            } elseif ($current -eq [char]92) {
                $escaped = $true
            } elseif ($current -eq [char]34) {
                $inString = $false
            }
            continue
        }

        if ($current -eq [char]34) {
            $inString = $true
            [void]$output.Append($current)
            continue
        }

        if ($current -eq ',') {
            $lookahead = $index + 1
            while ($lookahead -lt $Text.Length -and [char]::IsWhiteSpace($Text[$lookahead])) {
                $lookahead++
            }
            if ($lookahead -lt $Text.Length -and ($Text[$lookahead] -eq '}' -or $Text[$lookahead] -eq ']')) {
                continue
            }
        }

        [void]$output.Append($current)
    }

    return $output.ToString()
}

function ConvertFrom-VsCodeJson {
    param([Parameter(Mandatory = $true)][string]$Text)

    $withoutComments = Remove-JsonComments -Text $Text
    $strictJson = Remove-JsonTrailingCommas -Text $withoutComments
    return $strictJson | ConvertFrom-Json
}

$sshConfigExists = Test-Path -LiteralPath $SshConfigPath
if ($sshConfigExists) {
    Add-Result 'Configuration' 'SSH config exists' 'PASS' $SshConfigPath
} else {
    Add-Result 'Configuration' 'SSH config exists' 'FAIL' $SshConfigPath
}

$sshCommand = Get-Command ssh -ErrorAction SilentlyContinue
if ($null -eq $sshCommand) {
    Add-Result 'SSH' 'OpenSSH client available' 'FAIL' 'ssh was not found in PATH'
} elseif (-not $sshConfigExists) {
    Add-Result 'SSH' 'Alias resolves' 'FAIL' 'SSH config is unavailable; alias resolution skipped'
} else {
    Add-Result 'SSH' 'OpenSSH client available' 'PASS' $sshCommand.Source
    $sshInvocation = Invoke-NativeCapture -FilePath $sshCommand.Source -Arguments @('-F', $SshConfigPath, '-G', $HostAlias)
    $sshResolved = $sshInvocation.Output
    if ($sshInvocation.ExitCode -eq 0) {
        $joined = $sshResolved -join "`n"
        $hostName = ([regex]::Match($joined, '(?im)^hostname\s+(.+)$')).Groups[1].Value.Trim()
        $user = ([regex]::Match($joined, '(?im)^user\s+(.+)$')).Groups[1].Value.Trim()
        $forwardMatches = [regex]::Matches($joined, '(?im)^remoteforward\s+(.+)$')
        $forwards = @($forwardMatches | ForEach-Object { $_.Groups[1].Value.Trim() })
        Add-Result 'SSH' 'Alias resolves' 'PASS' "host=$hostName user=$user"

        # Windows OpenSSH may render loopback endpoints as either
        # 127.0.0.1:PORT or [127.0.0.1]:PORT. Normalize before comparing so
        # the diagnostic tests the route instead of depending on formatting.
        $normalizedForwards = @($forwards | ForEach-Object {
            $_ -replace '\[([^\]]+)\]', '$1'
        })
        $expectedRemote = [regex]::Escape("127.0.0.1:$RemoteProxyPort")
        $expectedLocal = [regex]::Escape("127.0.0.1:$LocalProxyPort")
        $matchingForward = $normalizedForwards | Where-Object {
            $_ -match "(^|\s)$expectedRemote(\s|$)" -and
            $_ -match "(^|\s)$expectedLocal(\s|$)"
        }
        if ($matchingForward) {
            Add-Result 'SSH' 'Reverse forward parsed' 'PASS' ($matchingForward -join '; ')
        } else {
            Add-Result 'SSH' 'Reverse forward parsed' 'FAIL' ("expected remote 127.0.0.1:{0} to local 127.0.0.1:{1}; parsed={2}" -f $RemoteProxyPort, $LocalProxyPort, ($forwards -join '; '))
        }
    } else {
        Add-Result 'SSH' 'Alias resolves' 'FAIL' ($sshResolved -join ' ')
    }
}

$listeners = @(Get-NetTCPConnection -State Listen -LocalPort $LocalProxyPort -ErrorAction SilentlyContinue)
$loopbackListeners = @($listeners | Where-Object { $_.LocalAddress -in @('127.0.0.1', '::1') })
$nonLoopbackListeners = @($listeners | Where-Object { $_.LocalAddress -notin @('127.0.0.1', '::1') })
if ($nonLoopbackListeners.Count -gt 0) {
    $bindings = @($nonLoopbackListeners | ForEach-Object {
        "{0}:{1};pid={2}" -f $_.LocalAddress, $_.LocalPort, $_.OwningProcess
    })
    Add-Result 'Local proxy' 'Local port listening' 'FAIL' ("non-loopback listener detected: {0}" -f ($bindings -join ','))
} elseif ($loopbackListeners.Count -gt 0) {
    $bindings = @($loopbackListeners | ForEach-Object {
        "{0}:{1};pid={2}" -f $_.LocalAddress, $_.LocalPort, $_.OwningProcess
    })
    Add-Result 'Local proxy' 'Local port listening' 'PASS' ($bindings -join ',')
} else {
    Add-Result 'Local proxy' 'Local port listening' 'FAIL' "no listener on port $LocalProxyPort"
}

if (Test-Path -LiteralPath $VsCodeSettingsPath) {
    try {
        $settingsText = Get-Content -LiteralPath $VsCodeSettingsPath -Raw -Encoding UTF8
        $settings = ConvertFrom-VsCodeJson -Text $settingsText
        Add-Result 'Configuration' 'VS Code settings parse' 'PASS' $VsCodeSettingsPath

        $platform = Get-MapValue $settings.'remote.SSH.remotePlatform' $HostAlias
        $httpProxy = Get-MapValue $settings.'remote.SSH.httpProxy' $HostAlias
        $httpsProxy = Get-MapValue $settings.'remote.SSH.httpsProxy' $HostAlias
        $serverPath = Get-MapValue $settings.'remote.SSH.serverInstallPath' $HostAlias

        if ($platform -eq 'linux') {
            Add-Result 'VS Code' 'Remote platform' 'PASS' "$HostAlias=linux"
        } else {
            Add-Result 'VS Code' 'Remote platform' 'FAIL' "$HostAlias=$platform"
        }

        $expectedProxy = "http://127.0.0.1:$RemoteProxyPort"
        if ($httpProxy -eq $expectedProxy -and $httpsProxy -eq $expectedProxy) {
            Add-Result 'VS Code' 'Per-alias proxy' 'PASS' $expectedProxy
        } else {
            Add-Result 'VS Code' 'Per-alias proxy' 'FAIL' "http=$httpProxy https=$httpsProxy expected=$expectedProxy"
        }

        if ($serverPath -and $serverPath -match '\.vscode-server') {
            Add-Result 'VS Code' 'Isolated server path' 'PASS' $serverPath
        } else {
            Add-Result 'VS Code' 'Isolated server path' 'WARN' "path=$serverPath"
        }
    } catch {
        Add-Result 'Configuration' 'VS Code settings parse' 'FAIL' $_.Exception.Message
    }
} else {
    Add-Result 'Configuration' 'VS Code settings exists' 'FAIL' $VsCodeSettingsPath
}

$codeCommand = Get-Command code -ErrorAction SilentlyContinue
if ($null -eq $codeCommand) {
    Add-Result 'Runtime' 'VS Code CLI available' 'WARN' 'code was not found in PATH'
} else {
    $statusText = (& $codeCommand.Source --status 2>&1) -join "`n"
    if ($statusText -match [regex]::Escape("SSH: $HostAlias")) {
        Add-Result 'Runtime' 'Dedicated Remote-SSH window' 'PASS' "SSH: $HostAlias"
    } else {
        Add-Result 'Runtime' 'Dedicated Remote-SSH window' 'WARN' 'alias not found in code --status'
    }

    if ($statusText -match 'openai\.chatgpt-[^\s]+-linux-x64[^\r\n]*codex[^\r\n]*app-server') {
        Add-Result 'Runtime' 'Linux Codex app-server' 'PASS' 'remote Linux Codex process found'

        if ($statusText -match 'openai\.chatgpt-[^\s]+-linux-x64[^\r\n]*codex\.real[^\r\n]*app-server') {
            Add-Result 'Runtime' 'Version-bound proxy wrapper' 'PASS' 'remote process is running codex.real through the wrapper'
        } else {
            Add-Result 'Runtime' 'Version-bound proxy wrapper' 'WARN' 'process runs plain codex; inspect /proc/<pid>/environ and check for extension upgrade drift'
        }
    } else {
        Add-Result 'Runtime' 'Linux Codex app-server' 'WARN' 'remote Linux Codex process not found'
    }
}

if (-not $SkipNetwork) {
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path -LiteralPath $curl) {
        $curlInvocation = Invoke-NativeCapture -FilePath $curl -Arguments @(
            '-x', "http://127.0.0.1:$LocalProxyPort",
            '-sS', '-o', 'NUL', '-w', '%{http_code}',
            '--connect-timeout', '15', 'https://api.openai.com/v1/models'
        )
        $statusCode = $curlInvocation.Output -join ' '
        if ($curlInvocation.ExitCode -eq 0 -and "$statusCode" -match '^\d{3}$' -and "$statusCode" -ne '000') {
            Add-Result 'Local proxy' 'OpenAI HTTP response' 'PASS' "HTTP $statusCode"
        } else {
            Add-Result 'Local proxy' 'OpenAI HTTP response' 'FAIL' ("exit={0} output={1}" -f $curlInvocation.ExitCode, $statusCode)
        }
    } else {
        Add-Result 'Local proxy' 'OpenAI HTTP response' 'WARN' 'curl.exe not found'
    }
}

$failed = @($results | Where-Object Status -eq 'FAIL').Count
$warnings = @($results | Where-Object Status -eq 'WARN').Count

if ($AsJson) {
    $results | ConvertTo-Json -Depth 4
} else {
    $results | Format-Table -AutoSize -Wrap
    Write-Output ""
    Write-Output "Summary: FAIL=$failed WARN=$warnings TOTAL=$($results.Count)"
}

if ($failed -gt 0 -and -not $AlwaysExitZero) {
    exit 1
}
