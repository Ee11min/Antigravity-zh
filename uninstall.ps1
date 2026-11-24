#requires -Version 5.1
<#
.SYNOPSIS
    Antigravity 简体中文汉化层 —— 完全卸载
.DESCRIPTION
    从 preload.js 中剥掉汉化注入器，并把 resources\app 目录还原成原始 app.asar。
.PARAMETER AppDir
    手动指定 Antigravity 安装目录（默认自动探测）。
.PARAMETER KeepUnpacked
    只剥掉注入器，保留解包后的目录结构。
#>
[CmdletBinding()]
param(
    [string]$AppDir,
    [switch]$KeepUnpacked
)

# 让中文在 PS 5.1 / 7 的终端里都能正确显示
try {
    $prevOut = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Text.UTF8Encoding]::new($false)
} catch { }

$ErrorActionPreference = 'Stop'

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$Markers = @(
    '// ===== Antigravity i18n zh-CN layer (do not edit below) =====',
    '// ===== Antigravity 运行时汉化层 ====='
)

function Read-Utf8 {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding($false)))
}

function Say  ($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Good ($m) { Write-Host "[+] $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host "[x] $m" -ForegroundColor Red; exit 1 }

function Find-AppDir {
    $c = @()
    if ($AppDir) { $c += $AppDir }
    $c += (Join-Path $env:LOCALAPPDATA 'Programs\antigravity')
    $c += (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity')
    if ($env:ProgramFiles) { $c += (Join-Path $env:ProgramFiles 'Antigravity') }
    if (${env:ProgramFiles(x86)}) { $c += (Join-Path ${env:ProgramFiles(x86)} 'Antigravity') }
    foreach ($p in $c) {
        if ($p -and (Test-Path (Join-Path $p 'Antigravity.exe'))) { return (Resolve-Path $p).Path }
    }
    return $null
}

$app = Find-AppDir
if (-not $app) { Die '未找到 Antigravity 安装目录，请用 -AppDir 指定' }

$res      = Join-Path $app 'resources'
$asar     = Join-Path $res 'app.asar'
$asarOrig = Join-Path $res 'app.asar.orig'
$workDir  = Join-Path $res 'app'
$preload  = Join-Path $workDir 'dist\preload.js'

Good "安装目录：$app"

# 1) 剥掉注入器
if (Test-Path $preload) {
    $txt = Read-Utf8 $preload
    $cut = -1
    foreach ($mk in $Markers) {
        $i = $txt.IndexOf($mk)
        if ($i -ge 0 -and ($cut -lt 0 -or $i -lt $cut)) { $cut = $i }
    }
    if ($cut -ge 0) {
        $clean = $txt.Substring(0, $cut).TrimEnd("`r", "`n") + "`r`n"
        [System.IO.File]::WriteAllText($preload, $clean, (New-Object Text.UTF8Encoding($false)))
        Good '已从 preload.js 移除汉化注入器'
    } else {
        Say 'preload.js 里没有汉化注入器，跳过'
    }
} else {
    Say 'preload.js 不存在（可能未安装或已还原），跳过'
}

if ($KeepUnpacked) {
    Warn '按 -KeepUnpacked 要求，保留 resources\app 目录'
    Good '卸载完成（目录加载模式仍生效，界面已回英文）'
    exit 0
}

# 2) 还原 app.asar
if (Test-Path $asarOrig) {
    if (Test-Path $asar) { Remove-Item $asar -Force }
    Move-Item -LiteralPath $asarOrig -Destination $asar
    Good '已还原原始 app.asar'
} elseif (-not (Test-Path $asar)) {
    Warn '找不到 app.asar.orig，无法还原打包形式；只能保留目录加载模式'
    exit 1
} else {
    Say 'app.asar 本就存在，无需还原'
}

# 3) 删除解包目录
if (Test-Path $workDir) {
    Remove-Item $workDir -Recurse -Force
    Good '已删除解包目录 resources\app'
}

Write-Host ''
Good '卸载完成。下次启动 Antigravity 即为原版英文界面。'
