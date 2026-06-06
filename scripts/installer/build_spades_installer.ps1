<#
.SYNOPSIS
    Build a single one-click Windows installer for the native SPAdes port.

.DESCRIPTION
    Stages a self-contained payload and compiles it into SPAdes-Windows-<ver>-Setup.exe
    with Inno Setup. The payload bundles everything needed to run SPAdes on a stock
    Windows machine with NO prerequisites (no WSL/Docker, no system Python, no MinGW):

        bin\          static spades-*.exe + spades.py + mode drivers + .bat launchers
        share\spades\ configs, HMM profiles, pyyaml3, spades_pipeline, test data
        python\       embedded Python 3.11 (downloaded if not cached)
        spades-shell.bat, README-WINDOWS.txt

    Run AFTER building/installing SPAdes (scripts\setup_spades.ps1 -> %LOCALAPPDATA%\spades-install).

.PARAMETER InstallTree
    The installed SPAdes layout (bin\ + share\spades\). Default %LOCALAPPDATA%\spades-install.

.PARAMETER OutDir
    Where to write the Setup .exe. Default <repo>\dist.

.PARAMETER PythonVersion
    Embeddable Python version to bundle. Default 3.11.9.
#>
[CmdletBinding()]
param(
    [string]$InstallTree   = (Join-Path $env:LOCALAPPDATA 'spades-install'),
    [string]$OutDir        = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'dist'),
    [string]$PythonVersion = '3.11.9',
    [string]$Iscc          = ''
)

$ErrorActionPreference = 'Stop'
function Info($m) { Write-Host "[installer] $m" -ForegroundColor Cyan }
function Die($m)  { Write-Host "[installer] ERROR: $m" -ForegroundColor Red; exit 1 }

$here    = $PSScriptRoot
$iss     = Join-Path $here 'spades_windows.iss'
$work    = Join-Path $env:LOCALAPPDATA 'spades-dist'
$payload = Join-Path $work 'payload'
$dl      = Join-Path $work 'dl'

if (-not (Test-Path (Join-Path $InstallTree 'bin\spades-core.exe'))) {
    Die "No built SPAdes at '$InstallTree' (expected bin\spades-core.exe). Run setup_spades.ps1 first."
}
$version = (Get-Content (Join-Path $InstallTree 'share\spades\VERSION') -ErrorAction SilentlyContinue | Select-Object -First 1)
if (-not $version) { $version = '4.3.0-dev' }
$version = $version.Trim()

# --- locate ISCC ---
if (-not $Iscc) {
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'InnoSetup6\ISCC.exe'),
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    )
    $Iscc = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Iscc -or -not (Test-Path $Iscc)) {
    Die "ISCC.exe (Inno Setup 6) not found. Install from https://jrsoftware.org/isdl.php or pass -Iscc."
}

# --- embedded Python (download if needed) ---
New-Item -ItemType Directory -Force -Path $dl | Out-Null
$pyZip = Join-Path $dl "python-$PythonVersion-embed-amd64.zip"
if (-not (Test-Path $pyZip)) {
    $url = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip"
    Info "Downloading embeddable Python $PythonVersion ..."
    Invoke-WebRequest -Uri $url -OutFile $pyZip -UseBasicParsing
}

# --- stage payload from scratch ---
if (Test-Path $payload) { Remove-Item $payload -Recurse -Force }
New-Item -ItemType Directory -Force -Path $payload | Out-Null

Info "Staging bin\ and share\ ..."
Copy-Item (Join-Path $InstallTree 'bin')   (Join-Path $payload 'bin')   -Recurse -Force
Copy-Item (Join-Path $InstallTree 'share') (Join-Path $payload 'share') -Recurse -Force

# The HMM databases (--bio / --corona) ship gzipped, and HMMER/Easel decompress them by
# shelling out to an external 'gzip' which does not exist on a stock Windows machine. Ship
# them decompressed so the HMM modes are self-contained. Uses .NET (no external gzip needed).
function Expand-Gz([string]$gz) {
    $out = $gz.Substring(0, $gz.Length - 3)   # strip .gz
    $in  = [System.IO.File]::OpenRead($gz)
    try {
        $gs  = New-Object System.IO.Compression.GzipStream($in, [System.IO.Compression.CompressionMode]::Decompress)
        $ofs = [System.IO.File]::Create($out)
        try { $gs.CopyTo($ofs) } finally { $ofs.Dispose(); $gs.Dispose() }
    } finally { $in.Dispose() }
    Remove-Item $gz -Force
}
$hmmDirs = @('biosynthetic_spades_hmms','coronaspades_hmms')
$nHmm = 0
foreach ($hd in $hmmDirs) {
    $dir = Join-Path $payload "share\spades\$hd"
    if (Test-Path $dir) {
        Get-ChildItem $dir -Filter '*.hmm.gz' | ForEach-Object { Expand-Gz $_.FullName; $nHmm++ }
    }
}
Info "Decompressed $nHmm HMM database file(s) for self-contained HMM modes."

Info "Staging embedded Python ..."
$pyDir = Join-Path $payload 'python'
New-Item -ItemType Directory -Force -Path $pyDir | Out-Null
Expand-Archive -Path $pyZip -DestinationPath $pyDir -Force
# Point the embedded interpreter at our bin\ and share\spades (._pth overrides PYTHONPATH).
$pthName = (Get-ChildItem $pyDir -Filter 'python*._pth' | Select-Object -First 1).Name
$pyMajorMinor = ($PythonVersion -split '\.')[0..1] -join ''
@(
    "python$pyMajorMinor.zip"
    '.'
    '..\bin'
    '..\share\spades'
    'import site'
) | Set-Content -Path (Join-Path $pyDir $pthName) -Encoding ascii

# --- generate .bat launchers for every mode (so users type 'spades', 'metaspades', ...) ---
Info "Generating launchers ..."
$binPay = Join-Path $payload 'bin'
Get-ChildItem $binPay -Filter '*.py' | Where-Object { $_.Name -ne 'spades_init.py' } | ForEach-Object {
    $stem = [IO.Path]::GetFileNameWithoutExtension($_.Name)
    $bat  = @"
@echo off
rem SPAdes launcher - runs $($_.Name) with the bundled Python.
"%~dp0..\python\python.exe" "%~dp0$($_.Name)" %*
"@
    Set-Content -Path (Join-Path $binPay "$stem.bat") -Value $bat -Encoding ascii
}

# --- "SPAdes Command Prompt" ---
$shell = @"
@echo off
set "PATH=%~dp0bin;%~dp0python;%PATH%"
title SPAdes for Windows
echo ============================================================
echo   SPAdes for Windows ($version) is ready.
echo.
echo   Try:   spades --help
echo          spades --test
echo          spades --isolate -1 reads_1.fq -2 reads_2.fq -o out_dir
echo          metaspades / plasmidspades / rnaspades / coronaspades ...
echo.
echo   (The classic 'spades.py ...' also works.)
echo ============================================================
echo.
cd /d "%USERPROFILE%"
cmd /k
"@
Set-Content -Path (Join-Path $payload 'spades-shell.bat') -Value $shell -Encoding ascii

# --- README ---
$readme = @"
SPAdes for Windows (native port) $version
=========================================

This is a fully self-contained, native-Windows build of the SPAdes genome
assembler. No WSL, Docker, Linux VM, system Python, or compiler is required -
everything (the assembler binaries and a private Python 3.11) is bundled here.

Quick start
-----------
  * Use the "SPAdes Command Prompt" shortcut in the Start Menu, then type:
        spades --help
        spades --test                 (runs the built-in E. coli self-test)
        spades --isolate -1 r1.fq -2 r2.fq -o out_dir

  * If you ticked "Add SPAdes to my PATH" during install, the 'spades' command
    (and metaspades, plasmidspades, rnaspades, coronaspades, ...) works in any
    terminal.

Modes:  --isolate --careful --sc --meta --rna --plasmid --metaviral --rnaviral
        --metaplasmid --bio --corona --sanger --iontorrent --sewage   (all 16 work)

Tips
----
  * On a laptop, cap memory and threads explicitly, e.g.:  spades --isolate -m 8 -t 4 ...
  * Output goes to the -o directory: contigs.fasta, scaffolds.fasta,
    assembly_graph_with_scaffolds.gfa, spades.log.

Project: https://github.com/MrMufasii/spades-windows-final
"@
Set-Content -Path (Join-Path $payload 'README-WINDOWS.txt') -Value $readme -Encoding ascii

# --- compile the installer ---
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Info "Compiling installer with Inno Setup ..."
& $Iscc "/DPayloadDir=$payload" "/DOutputDir=$OutDir" "/DAppVersion=$version" $iss | Out-Host
if ($LASTEXITCODE -ne 0) { Die "ISCC failed with exit code $LASTEXITCODE" }

$setup = Join-Path $OutDir "SPAdes-Windows-$version-Setup.exe"
if (Test-Path $setup) {
    $mb = [math]::Round((Get-Item $setup).Length / 1MB, 1)
    Info "DONE -> $setup  ($mb MB)"
} else {
    Die "Installer was not produced."
}
