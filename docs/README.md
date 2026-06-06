# Validation — native-Windows SPAdes

Every assembly below was produced by the **native-Windows** `spades-*.exe` (fully static, no
WSL/Docker/VM). Accuracy is alignment-free: **31-mer identity** (every assembled 31-mer must
appear in the reference — catches any single-base, port-induced drift) and **genome fraction**
(fraction of reference 31-mers recovered). Reproduce with
[`../scripts/validation/validate_ecoli.py`](../scripts/validation/validate_ecoli.py).

![Assembly accuracy](img/accuracy.png)
![Contiguity](img/contiguity.png)

## E. coli K-12 MG1655 — real Illumina reads (the headline test)

ENA **`ERR1473771`** (Illumina HiSeq 2500, 2×100 bp, ~85×; a real K-12 MG1655-background
isolate), run through the **default** pipeline (BayesHammer error correction → multi-k assembly),
contigs compared to NC_000913.3 — `ecoli_realreads_metrics.json`:

| Metric | Value |
|---|--:|
| Contigs (≥ 1 kb) | 185 (77) |
| Total assembly | 4,564,471 bp |
| Largest contig | 356,696 bp |
| N50 / L50 | 117,598 bp / 12 |
| **Genome fraction** | **99.21 %** |
| **31-mer identity** | **99.73 %** |
| Wall-clock | ~3.6 min (`-t 8 -m 24`, incl. error correction) |

The residual ~0.27 % off-reference is *real*: a laboratory-evolved MG1655 derivative carries
genuine strain variation vs the canonical reference, plus real sequencing error — not port drift.

> The first SRA accession we tried was mislabeled/contaminated (0 % 31-mer match to MG1655), so the
> validation now verifies a candidate's reads against the reference before assembling.

## E. coli K-12 MG1655 — simulated 30× (`ecoli_denovo_metrics.json`)

145 contigs, N50 175.9 kb, largest 327.1 kb, **99.997 % identity / 99.71 % genome fraction**. The
whole 4.64 Mb chromosome at ~100 % identity; fragmentation is the expected short-read break at the
seven ~5 kb *rrn* operons / IS elements, not a port defect.

## M. genitalium G37 — 580 kb, repeat-rich (`mgenitalium_metrics.json`)

The full chromosome assembles into a **single 580,060 bp contig** at **100.0 % 31-mer identity /
99.99 % genome fraction**. This is the case that used to crash `spades-core` at K21 on Windows — a
single **LLP64** bug (a 32-bit `-1ul` sentinel), now fixed.

## Phage λ — 48.5 kb (`metrics.json`)

Single 48,457 bp contig, **99.967 % identity / 99.885 % genome fraction**, GC 49.8 %.

## Stress test + resources

A deliberately punishing 2×300 MiSeq set (89 % singleton k-mers) drives k-mer counting to
**k=127 over a >2 GB on-disk k-mer file** — the exact path the LFS fix repairs (previously a hard
`stat(2) … value too large` abort). It now runs through k=127 at **normal memory (~5.5 GB)**:

![Resource usage](img/resources.png)

All 13 executables are **fully static** — `objdump -p` shows only Windows system DLLs (KERNEL32,
ADVAPI32, UCRT `api-ms-win-crt-*`), no MinGW DLLs. See
[`../scripts/spades-patch/README.md`](../scripts/spades-patch/README.md) for the port internals.
