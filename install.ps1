#requires -Version 5.1
<#
.SYNOPSIS
    Antigravity 汉化层 —— 安装 / 更新
.DESCRIPTION
    把 resources\app.asar 解包成 resources\app 目录，并在主窗口 preload 末尾追加汉化注入器。
    全程只追加、不改业务代码，可用 uninstall.ps1 完整还原。
.PARAMETER AppDir
    手动指定 Antigravity 安装目录（默认自动探测）。
.PARAMETER Force
    强制重新解包 app.asar（升级后或目录损坏时用）。
.PARAMETER Check
    只检查当前状态，不做任何修改。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -Check
#>
[CmdletBinding()]
param(
    [string]$AppDir,
    [switch]$Force,
    [switch]$Check
)

# 让中文在 PS 5.1 / 7 的终端里都能正确显示
try {
    $prevOut = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Text.UTF8Encoding]::new($false)
} catch { }

$ErrorActionPreference = 'Stop'

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$InjectorPath = Join-Path $ScriptRoot 'src\injector.js'
$Marker = '// ===== Antigravity i18n zh-CN layer (do not edit below) ====='
# 老版本（手工安装时代）使用的中文标记，一并识别，避免重复注入
$LegacyMarkers = @('// ===== Antigravity 运行时汉化层 =====')

function Read-Utf8 {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding($false)))
}

function Say  ($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Good ($m) { Write-Host "[+] $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host "[x] $m" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- 探测安装目录
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

# ---------------------------------------------------------------- asar 解包
function Expand-Asar {
    param([string]$AsarPath, [string]$OutDir)

    $unpackedDir = "$AsarPath.unpacked"
    $bytes = [System.IO.File]::ReadAllBytes($AsarPath)
    if ($bytes.Length -lt 16) { throw 'asar 文件过小，格式不合法' }

    $hdrSize = [BitConverter]::ToUInt32($bytes, 4)
    $jsonLen = [BitConverter]::ToUInt32($bytes, 12)
    $json    = [Text.Encoding]::UTF8.GetString($bytes, 16, $jsonLen)
    $base    = 8 + $hdrSize
    $tree    = $json | ConvertFrom-Json

    $script:fileCount = 0
    $script:skipCount = 0

    $rootFull = [System.IO.Path]::GetFullPath($OutDir)

    # 注意：PowerShell 变量名大小写不敏感，参数叫 $RelPath、局部叫 $childRel，
    # 绝不能出现 $Rel / $rel 这种「看起来是两个变量其实是一个」的写法。
    function Copy-Node {
        param($Node, [string]$RelPath)

        foreach ($prop in $Node.files.PSObject.Properties) {
            $name  = $prop.Name
            $val   = $prop.Value
            $childRel = if ($RelPath) { $RelPath + '/' + $name } else { $name }

            $isDir = $val.PSObject.Properties.Name -contains 'files'
            if ($isDir) {
                Copy-Node -Node $val -RelPath $childRel
                continue
            }
            if ($val.PSObject.Properties.Name -contains 'link') {
                $script:skipCount++
                continue
            }

            $relWin = $childRel -replace '/', '\'
            $dest   = [System.IO.Path]::GetFullPath((Join-Path $rootFull $relWin))
            if (-not $dest.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
                throw "非法路径（越界）：$childRel"
            }
            $dir = [System.IO.Path]::GetDirectoryName($dest)
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }

            $offset = $val.offset
            if ($val.unpacked -and ($null -eq $offset)) {
                $src = Join-Path $unpackedDir $relWin
                if (Test-Path -LiteralPath $src) {
                    Copy-Item -LiteralPath $src -Destination $dest -Force
                    $script:fileCount++
                } else { $script:skipCount++ }
                continue
            }

            if ($null -eq $offset) { $script:skipCount++; continue }

            $off = [int64]$offset
            $sz  = [int]$val.size
            if ($sz -le 0) {
                [System.IO.File]::WriteAllBytes($dest, (New-Object byte[] 0))
            } else {
                $buf = New-Object byte[] $sz
                [Array]::Copy($bytes, ($base + $off), $buf, 0, $sz)
                [System.IO.File]::WriteAllBytes($dest, $buf)
            }
            $script:fileCount++
        }
    }

    Copy-Node -Node $tree -RelPath ''
    return @{ Files = $script:fileCount; Skipped = $script:skipCount }
}

# ---------------------------------------------------------------- preload 处理
function Get-PristinePreload {
    param([string]$Text)
    $cut = -1
    foreach ($mk in @($Marker) + $LegacyMarkers) {
        $i = $Text.IndexOf($mk)
        if ($i -ge 0 -and ($cut -lt 0 -or $i -lt $cut)) { $cut = $i }
    }
    if ($cut -ge 0) { return $Text.Substring(0, $cut).TrimEnd("`r", "`n") + "`r`n" }
    return $Text
}
function Test-Injected {
    param([string]$Text)
    foreach ($mk in @($Marker) + $LegacyMarkers) {
        if ($Text.Contains($mk)) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------- 主流程
if (-not (Test-Path $InjectorPath)) { Die "找不到注入器：$InjectorPath（请在仓库根目录运行本脚本）" }

$app = Find-AppDir
if (-not $app) {
    Die ('未找到 Antigravity 安装目录。请确认已安装 Antigravity，或用 -AppDir 手动指定：' + [Environment]::NewLine + '    .\install.ps1 -AppDir "C:\Users\你\AppData\Local\Programs\antigravity"')
}

$res         = Join-Path $app 'resources'
$asar        = Join-Path $res 'app.asar'
$asarOrig    = Join-Path $res 'app.asar.orig'
$workDir     = Join-Path $res 'app'
$pkgJson     = Join-Path $workDir 'package.json'
$preloadPath = Join-Path $workDir 'dist\preload.js'

Good "安装目录：$app"

if (-not (Test-Path $res)) { Die "缺少 resources 目录：$res" }

# --- 判断是否需要重新解包
$needUnpack = $false
if ($Force) { $needUnpack = $true }
elseif (-not (Test-Path $pkgJson)) { $needUnpack = $true }
elseif (Test-Path $asar) {
    # 升级后 Antigravity 会重新放回 app.asar；它比已解包目录新，说明版本变了
    if ((Get-Item $asar).LastWriteTime -gt (Get-Item $pkgJson).LastWriteTime) { $needUnpack = $true }
}

if (-not $needUnpack) {
    $ver = (Read-Utf8 $pkgJson | ConvertFrom-Json).version
    Say "已处于目录加载模式（Antigravity $ver），无需重新解包"
} else {
    if (-not (Test-Path $asar)) {
        if (Test-Path $asarOrig) { Move-Item -LiteralPath $asarOrig -Destination $asar; Warn 'app.asar 缺失，已从 app.asar.orig 还原' }
        else { Die "找不到 $asar" }
    }
    if ($Check) { Warn "需要解包（当前为 -Check 模式，不做修改）"; if (Test-Path $preloadPath) { } else { exit 0 } }
    if (-not $Check) {
        Say '解包 app.asar → resources\app（约 20MB，需要十几秒）'
        if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
        $n = Expand-Asar -AsarPath $asar -OutDir $workDir
        if (-not (Test-Path $pkgJson)) { Die '解包失败：package.json 不存在' }
        Good ("解包完成，{0} 个文件（跳过 {1}）" -f $n.Files, $n.Skipped)
        if (Test-Path $asarOrig) { Remove-Item $asarOrig -Force }
        Move-Item -LiteralPath $asar -Destination $asarOrig
        Good '原版 app.asar 已备份为 app.asar.orig'
    }
}

if (-not (Test-Path $preloadPath)) { Die "找不到 preload：$preloadPath" }

$ver = (Read-Utf8 $pkgJson | ConvertFrom-Json).version
$orig  = Get-PristinePreload (Read-Utf8 $preloadPath)
$inj   = Read-Utf8 $InjectorPath
$merged = $orig.TrimEnd("`r", "`n") + "`r`n`r`n" + $Marker + "`r`n" + $inj

if ($Check) {
    $patched = Test-Injected (Read-Utf8 $preloadPath)
    Write-Host ''
    Say          "Antigravity 版本 : $ver"
    Say          "安装目录         : $app"
    Say          "目录加载模式     : $($(if (Test-Path $pkgJson) { '是' } else { '否' }))"
    Say          "汉化层已注入     : $($(if ($patched) { '是' } else { '否' }))"
    $dictLine = Select-String -Path $InjectorPath -Pattern 'var DICT = \{' | Select-Object -First 1
    $nEntry = 0
    if ($dictLine) { $nEntry = ([regex]::Matches($dictLine.Line, '":\s*"')).Count }
    Say          "词表条目         : $nEntry"
    exit 0
}

[System.IO.File]::WriteAllText($preloadPath, $merged, (New-Object Text.UTF8Encoding($false)))
$origBytes = (New-Object Text.UTF8Encoding($false)).GetByteCount($orig)
$mergedBytes = (New-Object Text.UTF8Encoding($false)).GetByteCount($merged)
Good ("汉化层已写入 preload.js（原版 {0:N0} 字节 → 合并后 {1:N0} 字节）" -f $origBytes, $mergedBytes)

Write-Host ''
Good '安装完成。启动 Antigravity 即可看到中文界面。'
Write-Host ''
Warn '注意：Antigravity 升级会覆盖 resources\app 目录。升级后请重新运行本脚本。'
Warn '如果语言服务器连不上 Google（登录超时），那是代理问题，与本汉化层无关。'
