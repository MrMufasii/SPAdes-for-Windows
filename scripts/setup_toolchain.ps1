<#
.SYNOPSIS
    Install a complete portable MinGW-w64 (winlibs) needed to BUILD the GUI.

.DESCRIPTION
    The pure-Rust core/CLI build with only the rustup GNU toolchain. The GUI,
    however, pulls winit/rfd -> the `windows` crates, which generate Windows
    import libraries via `dlltool`. rustup's bundled `dlltool` is incomplete (it
    can't find its assembler `as.exe`), so GUI builds fail with
    "dlltool ... CreateProcess".

    This script downloads a complete portable MinGW-w64 (winlibs — full gcc +
    binutils, no installer, no Visual Studio) into %LOCALAPPDATA%\winlibs. Its
    `as.exe`/`dlltool.exe` let GUI builds link. `build_gui.ps1` puts it on PATH
    automatically.

    This is a BUILD-time dependency only; the produced GUI .exe needs none of it.
#>
[CmdletBinding()]
param([string]$Dir = (Join-Path $env:LOCALAPPDATA 'winlibs'))

$ErrorActionPreference = 'Stop'

$existing = Get-ChildItem -Path $Dir -Recurse -Filter 'as.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existing) {
    Write-Host "MinGW-w64 already present: $($existing.FullName)" -ForegroundColor Green
    return
}

Write-Host "Querying latest winlibs release..." -ForegroundColor Cyan
$rel = (Invoke-WebRequest -Uri "https://api.github.com/repos/brechtsanders/winlibs_mingw/releases/latest" `
        -Headers @{ 'User-Agent' = 'ps' } -UseBasicParsing).Content | ConvertFrom-Json
$asset = $rel.assets | Where-Object {
    $_.name -match 'x86_64' -and $_.name -match 'posix-seh' -and $_.name -match 'ucrt' -and
    $_.name -match 'zip$' -and $_.name -notmatch 'mcf'
} | Select-Object -First 1
if (-not $asset) { throw "Could not find a suitable winlibs x86_64 UCRT zip asset." }

$zip = Join-Path $env:LOCALAPPDATA 'winlibs.zip'
Write-Host ("Downloading {0} ({1} MB)..." -f $asset.name, [math]::Round($asset.size / 1MB, 0)) -ForegroundColor Cyan
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing

if (Test-Path $Dir) { [System.IO.Directory]::Delete($Dir, $true) }
Add-Type -AssemblyName System.IO.Compression.FileSystem
Write-Host "Extracting to $Dir ..." -ForegroundColor Cyan
[System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $Dir)
[System.IO.File]::Delete($zip)

$as = Get-ChildItem -Path $Dir -Recurse -Filter 'as.exe' | Select-Object -First 1
if (-not $as) { throw "Extraction did not yield as.exe" }
Write-Host "MinGW-w64 installed. Binutils at: $($as.DirectoryName)" -ForegroundColor Green
