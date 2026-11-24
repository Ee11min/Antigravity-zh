#requires -Version 5.1
<#
.SYNOPSIS
    修改词表后重建 injector.js
.DESCRIPTION
    等价于：python src\dict.py && python src\build.py
    需要 Python 3（仅改词表的人需要，普通用户用 install.ps1 即可）。
#>
[CmdletBinding()]
param()

# 让中文在 PS 5.1 / 7 的终端里都能正确显示
try {
    $prevOut = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Text.UTF8Encoding]::new($false)
} catch { }

$ErrorActionPreference = 'Stop'
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$src = Join-Path $ScriptRoot 'src'

$py = $null
foreach ($cand in @('python', 'python3', 'py')) {
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd) { $py = $cmd.Source; break }
}
if (-not $py) {
    Write-Host '[x] 未找到 Python。改词表需要 Python 3：https://www.python.org/downloads/' -ForegroundColor Red
    exit 1
}

& $py (Join-Path $src 'dict.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $py (Join-Path $src 'build.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ''
Write-Host '[+] 重建完成。运行 .\install.ps1 让改动生效。' -ForegroundColor Green
