#!/usr/bin/env python3
"""De novo assembly validation for the native-Windows SPAdes port.

Downloads the E. coli K-12 MG1655 reference (NC_000913.3), assembles reads with
the native SPAdes, and reports QUAST-style contiguity (N50/L50/largest) plus
alignment-free accuracy: **31-mer identity** (every assembled 31-mer must occur in
the reference) and **genome fraction** (fraction of reference 31-mers recovered).

No external tools beyond the SPAdes install and stock Windows Python 3.x.

  # simulated reads (reproduces docs/ecoli_denovo_metrics.json):
  python validate_ecoli.py --spades %LOCALAPPDATA%\\spades-install\\bin\\spades.py --workdir C:\\spdval

  # real reads (e.g. an ENA/SRA FASTQ pair):
  python validate_ecoli.py --spades ...\\spades.py --workdir C:\\spdval ^
      --reads1 R1.fastq.gz --reads2 R2.fastq.gz   # default pipeline (with error correction)
"""
import argparse, gzip, json, os, random, subprocess, sys, urllib.request

ACC = "NC_000913.3"
COMP = {"A": "T", "T": "A", "G": "C", "C": "G", "N": "N"}
RC = lambda s: "".join(COMP.get(b, "N") for b in reversed(s))


def readfa(path):
    seqs, name, buf = {}, None, []
    for line in open(path):
        if line.startswith(">"):
            if name: seqs[name] = "".join(buf)
            name, buf = line[1:].split()[0], []
        else:
            buf.append(line.strip())
    if name: seqs[name] = "".join(buf)
    return seqs


def one_seq(path):
    return next(iter(readfa(path).values())).upper()


def simulate(src, cov, p1, p2, rl=150, frag=350, err=0.001, seed=2026):
    rng = random.Random(seed); n = int(len(src) * cov / (2 * rl)); q = "I" * rl; bases = "ACGT"
    mut = lambda s: "".join(rng.choice(bases) if rng.random() < err else b for b in s)
    with gzip.open(p1, "wt") as a, gzip.open(p2, "wt") as b:
        for i in range(n):
            p = rng.randint(0, len(src) - frag); f = src[p:p + frag]
            a.write(f"@r{i}/1\n{mut(f[:rl])}\n+\n{q}\n")
            b.write(f"@r{i}/2\n{mut(RC(f[-rl:]))}\n+\n{q}\n")


def n50(lengths):
    tot, acc = sum(lengths), 0
    for i, L in enumerate(sorted(lengths, reverse=True)):
        acc += L
        if acc >= tot / 2: return L, i + 1
    return 0, 0


def kmer_accuracy(contigs, ref, k=31):
    refk = {ref[i:i + k] for i in range(len(ref) - k + 1)}
    hit = tot = 0; covered = set()
    for s in contigs.values():
        if len(s) < k: continue
        best = max([s, RC(s)], key=lambda c: sum(1 for i in range(0, max(1, len(c) - k + 1), 17) if c[i:i + k] in refk))
        for i in range(len(best) - k + 1):
            tot += 1; km = best[i:i + k]
            if km in refk: hit += 1; covered.add(km)
    return (round(100 * hit / tot, 4) if tot else 0.0, round(100 * len(covered) / len(refk), 4))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spades", required=True, help="path to spades.py")
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--reads1", default=""); ap.add_argument("--reads2", default="")
    ap.add_argument("--isolate", action="store_true",
                    help="use --isolate (skips error correction; for clean high-cov data)")
    ap.add_argument("--threads", type=int, default=8); ap.add_argument("--mem", type=int, default=24)
    args = ap.parse_args()
    args.spades = os.path.abspath(args.spades)
    os.makedirs(args.workdir, exist_ok=True)

    ref_fa = os.path.join(args.workdir, "ecoli_ref.fasta")
    if not os.path.exists(ref_fa):
        url = (f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
               f"?db=nuccore&id={ACC}&rettype=fasta&retmode=text")
        print(f"[val] downloading {ACC} ...", flush=True)
        open(ref_fa, "w").write(urllib.request.urlopen(url, timeout=120).read().decode())
    ref = one_seq(ref_fa); print(f"[val] reference {len(ref):,} bp", flush=True)

    if args.reads1:
        r1, r2 = os.path.abspath(args.reads1), os.path.abspath(args.reads2)
    else:
        r1 = os.path.join(args.workdir, "sim_1.fq.gz"); r2 = os.path.join(args.workdir, "sim_2.fq.gz")
        if not os.path.exists(r1):
            print("[val] simulating 30x reads ...", flush=True); simulate(ref, 30, r1, r2)

    asm = os.path.join(args.workdir, "asm"); contigs = os.path.join(asm, "contigs.fasta")
    cmd = [sys.executable, args.spades, "-1", r1, "-2", r2, "-o", asm,
           "-t", str(args.threads), "-m", str(args.mem)]
    if args.isolate: cmd.insert(2, "--isolate")
    print("[val] running:", " ".join(cmd), flush=True)
    rc = subprocess.run(cmd).returncode
    assert rc == 0, f"SPAdes failed (rc={rc})"

    con = readfa(contigs); lens = [len(s) for s in con.values()]
    nn, ll = n50(lens); ident, frac = kmer_accuracy(con, ref)
    res = dict(reference=f"E. coli K-12 MG1655 ({ACC})", ref_len=len(ref),
               reads=("real: " + r1) if args.reads1 else "simulated 30x 2x150",
               n_contigs=len(lens), n_contigs_ge1kb=sum(1 for L in lens if L >= 1000),
               total_len=sum(lens), largest=max(lens), n50=nn, l50=ll,
               identity_pct=ident, genome_fraction_pct=frac)
    print("[val] RESULT", json.dumps(res, indent=2), flush=True)


if __name__ == "__main__":
    main()
