# Native-Windows SPAdes port

A from-source fork that makes **SPAdes 4.3.0-dev** compile, link, and run as a
**native Windows application** (MinGW / `x86_64-w64-mingw32`) — no WSL, Docker,
VM, or container. All 13 `spades-*` executables build **fully static** (zero runtime
DLLs), and `spades.py` runs the full pipeline end-to-end. `--isolate` (k up to 99,
4-word k-mers, exact-substring contigs incl. repeat resolution), `--careful` (real
spades-bwa MismatchCorrector), and `--meta` (metaSPAdes) are all validated to produce
correct, bit-exact contigs on synthetic data under stock Windows Python.

Reproduce with `..\setup_spades.ps1` (clones, patches, builds static, installs the
canonical `bin\` + `share\spades\` layout to `%LOCALAPPDATA%\spades-install`).

## Mode status (validated on synthetic data + SPAdes' own `--test`)

**Working (all 16):** `--isolate`, `--careful`, `--sc`, `--meta`, `--rna`, `--plasmid`,
`--metaviral`, `--rnaviral`, `--metaplasmid`, `--bio`, `--corona`, `--sanger`,
`--sewage`, `--iontorrent`, plus `spades.py --test` (official E. coli-1K self-test
**PASSES**) and all `*spades.py` mode-driver scripts. `--bio`/`--corona` exercise HMM
domain matching via Easel/HMMER — the same `hmmscan` machinery prokka/bakta need — now
running natively.

**`--iontorrent` fix (GCC strict-aliasing miscompilation).** The IonHammer corrector's
HKMer (homopolymer k-mer = `HSeq<16>`, element = 1-byte `HomopolymerRun` union) path stores
k-mers through the type-punning `adt::array_vector`/`KMerVector` proxy machinery. At `-O2/-O3`
GCC's strict-aliasing assumptions reorder/elide the punned loads, corrupting ~1/3 of records
during the **disk-split buffering** (`KMerSortingSplitter::DumpBuffers`). The corrupted bytes no
longer hash to the bucket file they physically live in, so the perfect-hash index can't find them:
`KMerData::operator[](HKMer)`→`seq_idx` returns `NOT_FOUND(-1)` → `operator[]((size_t)-1)` → huge
OOB read → segfault. (The earlier-suspected "second crash" in `TOneErrorClustering` was just
downstream fallout of the same corruption.) Regular-KMer (uint64 element) takes a different code
path with no 1-byte-union punning, which is why this was IonTorrent-only and never reproduced on
Linux. **Fix:** `target_compile_options(spades-ionhammer PRIVATE -fno-strict-aliasing)` in
`src/projects/ionhammer/CMakeLists.txt` — makes the intentional type-punning well-defined.
Validated: `--iontorrent` now yields an **exact-match** 1000 bp contig (100% identity,
`contig == reference`) on the bundled ecoli_1K test, fully static.

## Real-genome assembly: small genomes **and** large repeat-rich bacterial chromosomes

* *Enterobacteria phage λ* (NC_001416, 48,502 bp) — single 48,457 bp contig, 99.885 % genome
  fraction / 99.967 % identity.
* *Mycoplasma genitalium* G37 (NC_000908.2, **580 kb**, repeat-rich) — **single 580,060 bp
  contig, 100.000 % 31-mer identity, 99.986 % genome fraction**. A 250 kb sub-region likewise
  assembles into one contig at 100 % identity. See [`docs/validation/`](../../docs/validation/).

### The repeat-rich-chromosome crash was an LLP64 bug (fixed)

Large repeat-rich chromosomes used to crash `spades-core` at K21 with `0xC0000005`. The root
cause was **not** heap corruption (an earlier hypothesis): it is a single classic **LLP64
defect** in graph construction.

`FastGraphFromSequencesConstructor::CollectLinkRecords` emits a placeholder `LinkRecord` for the
"end" slot of every self-conjugate edge. That placeholder's default constructor set its 64-bit
`hash_and_mask_` field with **`-1ul`**. On Windows `unsigned long` is **32-bit** (LLP64), so
`-1ul` is `0xFFFFFFFF`, which widens to `0x00000000FFFFFFFF` — *not* all-ones. `IsInvalid()`
tests `hash_and_mask_ + 1 == 0`; with the truncated sentinel that is `0x100000000 != 0`, so the
placeholder records were **never recognised as invalid**. They survived the vertex-grouping
filter, became real vertex groups, and `LinkEdge` linked a phantom `EdgeId(0)` into the vertex
adjacency (`SmallPODVector`). On Linux (`unsigned long` is 64-bit) the sentinel is genuinely
all-ones, so this never manifested upstream.

The phantom null edge is reachable only through vertex-adjacency iteration
(`GraphEdgeIterator`/`IterationHelper`), not through the edge-storage iterator (`g.edges()`),
which is why it slipped past edge-level checks. Every consumer that then dereferenced
`EdgeNucls(EdgeId(0))` (a null-buffer `Sequence`) read `data_[…]` through a null pointer:
benign heap slack on Linux, an unmapped-page fault on Windows — first in coverage filling
(`Sequence::start<RtSeq>()`), then in `SelfConjugateDisruptor::ProcessEdge` →
`SplitEdge` → `HiddenAddEdge` → `Sequence::operator[]`.

**Fix** (`assembly_graph/construction/debruijn_graph_constructor.hpp`): initialise the sentinel
with a true 64-bit value, `hash_and_mask_(~uint64_t(0))`. One token. Localised with `gdb`
(register/disassembly inspection of the faulting `mov (%rax,%r8,8)` with `rax == 8`, i.e.
`null_buffer + 8`) plus targeted adjacency-integrity instrumentation, since the winlibs MinGW
toolchain ships no `libasan`.

A companion defensive guard in `coverage_filling.hpp` mirrors the read-side
`CoverageHashMapBuilder` and skips edge (k+1)-mers absent from the coverage perfect-hash
(`phm_.valid(kwh)`) instead of dereferencing `data_[size_t(-1)]` — the same NOT_FOUND→OOB class
as the IonTorrent bug, hardened for Windows.

### High-coverage / long-read assembly at k=127: 32-bit `stat`/`off_t` (fixed)

High coverage or long (2×250/2×300) reads push k-mer counting to **k=127**, where the on-disk
k-mer files exceed **2 GB** (e.g. ~150 M distinct 127-mers × 32 B). Two LFS/LLP64 defects then
bite on Windows/MinGW:

* `io/kmers/{kmer_iterator,mmapped_reader}.hpp` sized those files with the C `stat()`, whose
  `struct stat::st_size` is **32-bit** on MinGW → `stat()` fails with `EOVERFLOW` (errno 132,
  "value too large") and `spades-core` aborts at *Condensing graph*. **Fix:** read the size with
  `std::filesystem::file_size()` (64-bit, already used throughout the port).
* `MMappedReader` maps those files in 64 MB blocks at increasing offsets, but `off_t` is **32-bit**
  on MinGW (LLP64), so block offsets > 2 GB truncate. **Fix:** build with
  `-D_FILE_OFFSET_BITS=64` (C/C++ flags **and** the shim's `mman.c`), making `off_t` 64-bit.

Verified: `--isolate` on a 75× 2×300 read set now drives k=127 over a >2 GB k-mer file without
the abort (it previously died at k=127 with `stat(2) … value too large`).

### Fully static: forcing static `libdl`

`-static` already drops libgcc/libstdc++/libwinpthread/libgomp, but CMake's `FindOpenMP` and
LLVM-support's `find_library(dl)` resolve `dl` to the **import lib** `libdl.dll.a` (by full path),
which `-static` cannot override — so every exe pulled in a non-static **`libdl.dll`**. winlibs
ships a self-contained static `libdl.a` (dlfcn-win32 over `LoadLibrary`); pointing CMake at it
(`-DOpenMP_dl_LIBRARY=<…>/libdl.a -DDL_LIB=<…>/libdl.a`) eliminates the DLL. **`objdump -p` now
shows only Windows system DLLs** (KERNEL32, ADVAPI32, the UCRT `api-ms-win-crt-*` forwarders) for
all 13 executables.

## Contents

| File | What it is |
|------|------------|
| `spades-mingw.patch` | `git diff` against ablab/spades `67ab1c76` (VERSION 4.3.0-dev). ~102 files. Apply with `git apply`. |
| `spades-src-67ab1c7.tar.gz` | Vendored pinned upstream source (`git archive` of `67ab1c76`, symlinks de-referenced). `setup_spades.ps1` uses it so a build never depends on ablab/spades staying available; the patch applies on top. |
| `shim/` | Hand-written POSIX shim headers/sources (copied to `%LOCALAPPDATA%\spades-shim`, force-included via `-include mingw_prelude.h`). |

## Why a fork was needed (no native-Windows SPAdes exists upstream)

1. **`std::filesystem::path::value_type` is `wchar_t` on Windows** (char on POSIX).
   SPAdes assumes char-based paths in ~91 sites: `path.c_str()` → `wchar_t*`,
   path→`std::string` implicit conversion, etc. Fixes: `.string().c_str()`, add
   `.string()` on path args to string params, `config_common` SFINAE treats path
   as string-like. **The runtime show-stopper:** the logger passed
   `file.filename().c_str()` (wchar_t*) to cppformat, which threw
   *"string pointer is null"* and broke **all** logging.
2. **Vendored LLVM-Support is only half-ported** for Windows. Completed the Unix
   backend: `file_t = void*`, force-Unix the `.inc` files, `status(file_t)`
   signature, `convertFDToNativeFile` inline (was `#ifndef _WIN32`),
   `computeHostNumPhysicalCores` MinGW stub.
3. **POSIX the C/C++ stdlib lacks on MinGW** — supplied by the shim: `mmap`
   (CreateFileMapping; **must align the offset down to the 64 KB allocation
   granularity** — MapViewOfFile rejects the 4 KB page-aligned offsets SPAdes
   produces), `glob` (FindFirstFile), `rand48`/`sync`/`srandom`/`vfork`/`pipe`,
   and stub headers (`sys/{mman,resource,wait,statvfs}`, `syslog`, `glob`,
   `execinfo`, `pwd`, `socket`, `utsname`).
4. **LLP64** (`long` is 32-bit on Windows): bitfields and comparators that used
   `long`/`unsigned long` for 64-bit values switched to `size_t`; `7UL` → `size_t`.
5. **Linking:** BamTools `__declspec(dllimport)` decoration emptied for the static
   build; `ws2_32` added for `knetfile`'s sockets.
6. **`spades.py` (pure Python) Windows fixes:** forward-slash paths in configs
   (boost INFO treats `\` as an escape); **LF newlines** on generated YAML
   (`open(..., newline='\n')` — yaml-cpp rejects CRLF) and `library.inl` writes
   datasets with `F_None` not `F_Text`; `check_binaries` appends `.exe`; mode-driver
   scripts (`metaspades.py` …) are POSIX symlinks that checkout broken on Windows —
   `setup_spades.ps1` rewrites them as real copies (mode = `basename(argv[0])`).
7. **GQF capacity guard (`--meta`):** metaSPAdes' counting-quotient-filter
   (`ext/src/gqf/gqf.c`) has no overflow guard; count-encoding outruns the filter's
   distinct-key sizing, and past ~94% load `find_first_empty_slot` runs off the slots
   array — heap slack on Linux, segfault on Windows. Added a load guard to `qf_insert`.

## Distribution

Built **fully static** via `-static` + `-DOpenMP_gomp_LIBRARY=<mingw>/lib/libgomp.a`
(CMake's FindOpenMP otherwise links `libgomp.dll.a`, defeating `-static`). `objdump -p`
shows zero non-system DLLs on all 13 exes. `build_installer.ps1` stages the source-tree
layout (static binaries in `bin/`, full pipeline dir, per-project `configs/`,
`ext/src/python_libs`); runs under stock Windows Python 3.x — no MinGW/MSYS needed.

## Easel + HMMER

`libeasel.a`, `libhmmer.a`, and `libhmmercpp.a` are on the `spades-core` link line
— this is the **full** spades-core with HMM domain matching, not an isolate-only
subset. Only HMMER's daemon files (sockets) and BWA's unused `shm` path were
dropped. The same `hmmscan` machinery that blocks native prokka/bakta links here.
