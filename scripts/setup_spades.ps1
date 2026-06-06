<#
.SYNOPSIS
    Build SPAdes 4.3.0-dev natively on Windows (MinGW, x86_64-w64-mingw32) — no
    WSL, Docker, VM, or container. Reproduces the native-Windows port: clones the
    pinned upstream commit, lays down the POSIX shim, builds bzip2, applies the
    MinGW source patch, configures, and compiles all SPAdes executables.

.DESCRIPTION
    SPAdes has no native-Windows build upstream: its code assumes char-based
    std::filesystem::path (path::value_type is wchar_t on Windows), and it
    vendors a Unix-only subset of LLVM-Support plus POSIX-only headers. This
    script rebuilds the fork that clears all of that:

      1. winlibs MinGW + MinGit on PATH (see setup_toolchain.ps1).
      2. POSIX shim at %LOCALAPPDATA%\spades-shim (mmap via CreateFileMapping,
         glob via FindFirstFile, rand48/sync/srandom, and stub headers for
         sys/{mman,resource,wait,statvfs}, syslog, glob, execinfo, pwd, socket,
         utsname). mingw_prelude.h is force-included into every TU.
      3. bzip2 1.0.8 static lib (libbz2.a).
      4. spades-mingw.patch: ~80 source files. Two themes —
         (a) path.value_type wchar->char: path.c_str()->path.string().c_str(),
             path args to std::string params get .string(), path->string members,
             config_common SFINAE treats path as string-like (matches POSIX);
         (b) finish the vendored LLVM Windows/Unix split: file_t=void*, the
             Unix Path.inc/Process/Program/Signals backend, status(file_t),
             convertFDToNativeFile, computeHostNumPhysicalCores stub; plus
             BamTools static-lib decoration, ws2_32 for knetfile, LLP64 bitfields.
      5. Configure + build all 13 spades-* executables.
      6. Stage binaries + the 4 MinGW runtime DLLs into <clone>\bin.

    Easel + HMMER DO link (libeasel.a + libhmmer.a + libhmmercpp.a are on the
    spades-core link line) — so this is the full spades-core, HMM domain matching
    included, not an --isolate-only subset.

.NOTES
    Pinned upstream: ablab/spades @ 67ab1c76b7b9e55faf5b8429610296512207df7f (VERSION 4.3.0-dev)
#>
[CmdletBinding()]
param(
    [string]$BuildRoot = (Join-Path $env:LOCALAPPDATA 'spades-build'),
    [string]$ShimDir   = (Join-Path $env:LOCALAPPDATA 'spades-shim'),
    [string]$Bzip2Dir  = (Join-Path $env:LOCALAPPDATA 'bzip2-1.0.8'),
    [string]$MinGW     = (Join-Path $env:LOCALAPPDATA 'winlibs\mingw64'),
    [string]$MinGit    = (Join-Path $env:LOCALAPPDATA 'mingit'),
    [string]$SpadesCommit = '67ab1c76b7b9e55faf5b8429610296512207df7f'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$patchDir = Join-Path $PSScriptRoot 'spades-patch'
function Info($m) { Write-Host "[spades] $m" -ForegroundColor Cyan }
function Die($m)  { Write-Host "[spades] ERROR: $m" -ForegroundColor Red; exit 1 }

# --- toolchain on PATH ---
if (-not (Test-Path "$MinGW\bin\g++.exe")) { Die "winlibs MinGW not found at $MinGW. Run setup_toolchain.ps1 first." }
$env:PATH = "$MinGW\bin;$MinGit\cmd;$env:PATH"
$gpp = "$MinGW\bin\g++.exe"; $gcc = "$MinGW\bin\gcc.exe"
$ar  = "$MinGW\bin\ar.exe";  $cmake = "$MinGW\bin\cmake.exe"

# --- 1. POSIX shim (copy hand-written sources, compile libposixshim.a) ---
Info "Laying down POSIX shim at $ShimDir"
New-Item -ItemType Directory -Force -Path "$ShimDir\sys" | Out-Null
Copy-Item "$patchDir\shim\*" $ShimDir -Recurse -Force
Info "Compiling libposixshim.a (mman.c + rand48.c)"
& $gcc -O2 -D_FILE_OFFSET_BITS=64 -c "$ShimDir\mman.c"   -o "$ShimDir\mman.o"   -I $ShimDir
& $gcc -O2 -c "$ShimDir\rand48.c" -o "$ShimDir\rand48.o" -I $ShimDir
& $ar rcs "$ShimDir\libposixshim.a" "$ShimDir\mman.o" "$ShimDir\rand48.o"
if (-not (Test-Path "$ShimDir\libposixshim.a")) { Die "failed to build libposixshim.a" }

# --- 2. bzip2 static lib ---
if (-not (Test-Path "$Bzip2Dir\libbz2.a")) {
    Info "Building bzip2 1.0.8 -> libbz2.a"
    $bzUrl = 'https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz'
    $tmp = Join-Path $env:TEMP 'bzip2-1.0.8.tar.gz'
    Invoke-WebRequest -Uri $bzUrl -OutFile $tmp
    tar -xzf $tmp -C (Split-Path $Bzip2Dir -Parent)
    Push-Location $Bzip2Dir
    & $gcc -O2 -D_FILE_OFFSET_BITS=64 -c blocksort.c huffman.c crctable.c randtable.c compress.c decompress.c bzlib.c
    & $ar rcs libbz2.a blocksort.o huffman.o crctable.o randtable.o compress.o decompress.o bzlib.o
    Pop-Location
}
if (-not (Test-Path "$Bzip2Dir\libbz2.a")) { Die "failed to build libbz2.a" }

# --- 3. obtain SPAdes source at the pinned commit ---
# Prefer the VENDORED source snapshot so a build never depends on ablab/spades staying
# available (or the pinned commit remaining fetchable). The snapshot is a `git archive`
# of $SpadesCommit; we re-init a tiny git repo around it so step 4 (`git apply` /
# `git checkout -- .`) and the build's revision detection keep working. `git add -f` is
# required: SPAdes tracks a few files its own .gitignore matches (e.g. ext/src/hmmer/src/build.c).
$srcTar = Join-Path $patchDir "spades-src-$($SpadesCommit.Substring(0,7)).tar.gz"
if (Test-Path "$BuildRoot\.git") {
    Info "Reusing existing SPAdes source at $BuildRoot"
} elseif (Test-Path $srcTar) {
    Info "Using bundled SPAdes source ($SpadesCommit) -> $(Split-Path $srcTar -Leaf)"
    New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
    & tar -xzf $srcTar -C $BuildRoot
    if ($LASTEXITCODE -ne 0) { Die "failed to extract bundled SPAdes source" }
    Push-Location $BuildRoot
    & git init -q
    & git add -f .
    & git -c user.email=build@localhost -c user.name=spades-windows commit -q -m "SPAdes $SpadesCommit (vendored snapshot)"
    Pop-Location
} else {
    Info "Cloning ablab/spades @ $SpadesCommit (no bundled source found)"
    & git clone https://github.com/ablab/spades.git $BuildRoot
    if ($LASTEXITCODE -ne 0) { Die "git clone failed (ablab/spades unreachable and no bundled source)" }
    Push-Location $BuildRoot; & git checkout $SpadesCommit; Pop-Location
}

# --- 4. apply the MinGW source patch ---
Info "Applying spades-mingw.patch"
Push-Location $BuildRoot
& git checkout -- . 2>$null   # reset tracked files so the patch applies cleanly
& git apply --whitespace=nowarn "$patchDir\spades-mingw.patch"
if ($LASTEXITCODE -ne 0) { Die "git apply failed — patch may need refresh against $SpadesCommit" }
# The mode-driver scripts (metaspades.py, rnaspades.py, ...) are POSIX symlinks to
# spades.py; on Windows git checks them out as 1-line text files containing
# "spades.py", which then crash. Mode is chosen by basename(argv[0]), so replace
# each with a real copy of spades.py to make `python metaspades.py` dispatch right.
$pipe = Join-Path $BuildRoot 'src\projects\spades\pipeline'
foreach ($drv in 'metaspades.py','rnaspades.py','plasmidspades.py','coronaspades.py',
                 'metaviralspades.py','metaplasmidspades.py','rnaviralspades.py') {
    $p = Join-Path $pipe $drv
    if (Test-Path $p) { Copy-Item (Join-Path $pipe 'spades.py') $p -Force }
}
Pop-Location

# --- 5. configure ---
# -static makes the 13 exes fully self-contained (no libgcc/libstdc++/libwinpthread/
# libgomp DLLs to travel). CMake's FindOpenMP otherwise links libgomp.dll.a (the
# import lib) which defeats -static, so point it at the static libgomp.a.
# _FILE_OFFSET_BITS=64 makes off_t 64-bit on MinGW (LLP64): the on-disk k-mer
# files exceed 2GB at large k / high coverage, so mmap offsets and stat sizes must
# be 64-bit (see the kmer_iterator/mmapped_reader LFS fix in spades-mingw.patch).
$cfgInc = "-I$ShimDir -I$Bzip2Dir -D_FILE_OFFSET_BITS=64 -include $ShimDir/mingw_prelude.h"
$whole  = "-Wl,--whole-archive $ShimDir/libposixshim.a $Bzip2Dir/libbz2.a -Wl,--no-whole-archive -static"
$gompA  = "$MinGW\lib\libgomp.a"
# Force the STATIC dlfcn (libdl.a = self-contained dlfcn-win32 over LoadLibrary).
# Otherwise CMake's FindOpenMP + LLVM's find_library(dl) pick the import lib
# libdl.dll.a, which makes every exe depend on a non-static libdl.dll.
$dlA    = "$MinGW\x86_64-w64-mingw32\lib\libdl.a"
$InstallPrefix = Join-Path $env:LOCALAPPDATA 'spades-install'
Info "Configuring (Ninja, internal OFF, fully static)"
& $cmake -S "$BuildRoot\src" -B "$BuildRoot\build_spades" -G Ninja `
    -DCMAKE_BUILD_TYPE=Release -DSPADES_BUILD_INTERNAL=OFF `
    -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ `
    -DCMAKE_INSTALL_PREFIX="$($InstallPrefix -replace '\\','/')" `
    -DBZIP2_INCLUDE_DIR="$Bzip2Dir" -DBZIP2_LIBRARY_RELEASE="$Bzip2Dir/libbz2.a" `
    -DOpenMP_gomp_LIBRARY="$gompA" -DOpenMP_dl_LIBRARY="$dlA" -DDL_LIB="$dlA" `
    "-DCMAKE_C_FLAGS=$cfgInc" "-DCMAKE_CXX_FLAGS=$cfgInc" `
    "-DCMAKE_EXE_LINKER_FLAGS=$whole" "-DCMAKE_SHARED_LINKER_FLAGS=$whole"
if ($LASTEXITCODE -ne 0) { Die "cmake configure failed" }

# --- 6. build all executables ---
$exes = @('spades-core','spades-hammer','spades-ionhammer','spades-bwa','spades-corrector-core',
          'spades-gbuilder','spades-gmapper','spades-gsimplifier','spades-gfa-split',
          'spades-convert-bin-to-fasta','spades-kmercount','spades-kmer-estimating','spades-read-filter')
$targets = $exes | ForEach-Object { "bin/$_.exe" }
Info "Building $($exes.Count) executables..."
& "$MinGW\bin\ninja.exe" -C "$BuildRoot\build_spades" @targets
if ($LASTEXITCODE -ne 0) { Die "ninja build failed" }

# --- 7a. stage binaries into <clone>\bin (source-tree layout; works for isolate/
#         careful/meta/rna/plasmid/sc/viral). Statically linked: no DLLs needed. ---
$binOut = Join-Path $BuildRoot 'bin'
New-Item -ItemType Directory -Force -Path $binOut | Out-Null
Copy-Item "$BuildRoot\build_spades\bin\*.exe" $binOut -Force

# --- 7b. produce the canonical INSTALL layout (bin\ + share\spades\). This is the
#         distributable form: spades.py's install-mode detection (patched to also
#         see spades-core.exe) points spades_home at share\spades, where the HMM
#         profiles, configs, test_dataset, sewage matrix and python modules live —
#         required for --bio / --corona / --sewage / --test. ---
Info "Installing canonical layout to $InstallPrefix"
& "$MinGW\bin\ninja.exe" -C "$BuildRoot\build_spades" install | Out-Null
if ($LASTEXITCODE -ne 0) { Die "ninja install failed" }

# --- The HMM databases (--bio / --corona) ship gzipped; HMMER/Easel decompress them by
#     shelling out to an external 'gzip', which does not exist on a stock Windows machine.
#     Ship them decompressed (Python pipeline globs *.hmm too) so HMM modes are self-contained. ---
function Expand-Gz([string]$gz) {
    $out = $gz.Substring(0, $gz.Length - 3)
    $in = [System.IO.File]::OpenRead($gz)
    try {
        $gs = New-Object System.IO.Compression.GzipStream($in, [System.IO.Compression.CompressionMode]::Decompress)
        $ofs = [System.IO.File]::Create($out)
        try { $gs.CopyTo($ofs) } finally { $ofs.Dispose(); $gs.Dispose() }
    } finally { $in.Dispose() }
    Remove-Item $gz -Force
}
foreach ($hd in @('biosynthetic_spades_hmms','coronaspades_hmms')) {
    $dir = Join-Path $InstallPrefix "share\spades\$hd"
    if (Test-Path $dir) { Get-ChildItem $dir -Filter '*.hmm.gz' | ForEach-Object { Expand-Gz $_.FullName } }
}

$built = (Get-ChildItem "$InstallPrefix\bin\spades-*.exe").Count
Info "Done. $built fully-static executables (no DLLs). Run from the install layout:"
Info "  python `"$InstallPrefix\bin\spades.py`" --isolate -1 r1.fq -2 r2.fq -o out"
Info "  python `"$InstallPrefix\bin\spades.py`" --test    # SPAdes' own E. coli 1K self-test"
