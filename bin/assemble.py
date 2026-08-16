#!/usr/bin/env python3
"""Paginate every rendered note into Letter pages, append any file attachments
that live outside the note body, and place the result at its final path."""
import os
import sys
import shutil
import subprocess
import collections

STAGING = sys.argv[1]
BIN = os.path.join(STAGING, "bin")
paginate = os.path.join(BIN, "paginate")
pdfmerge = os.path.join(BIN, "pdfmerge")

stats = collections.Counter()
problems = []

rows = [l.rstrip("\n").split("\t")
        for l in open(f"{STAGING}/finals.tsv", encoding="utf-8") if l.strip()]

for i, (idx, kind, src, final, extras) in enumerate(rows, 1):
    if not (os.path.exists(src) and os.path.getsize(src) > 0):
        problems.append((idx, kind, final, "no rendered source"))
        stats["missing_source"] += 1
        continue

    paged = os.path.join(STAGING, "paged", f"{idx}.pdf")
    r = subprocess.run([paginate, src, paged], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(paged):
        problems.append((idx, kind, final, f"paginate failed: {r.stderr.strip()[:80]}"))
        stats["paginate_failed"] += 1
        continue

    os.makedirs(os.path.dirname(final), exist_ok=True)
    extra_files = [e for e in extras.split(";") if e and os.path.exists(e)]
    if extra_files:
        r = subprocess.run([pdfmerge, final, paged] + extra_files,
                           capture_output=True, text=True)
        if r.returncode != 0:
            shutil.copyfile(paged, final)
            problems.append((idx, kind, final, "attachment merge failed; note body only"))
            stats["merge_failed"] += 1
        else:
            stats["with_attachments"] += 1
    else:
        shutil.copyfile(paged, final)

    stats[f"ok_{kind}"] += 1
    if i % 40 == 0:
        print(f"  {i}/{len(rows)}")

print("\n".join(f"{k}: {v}" for k, v in sorted(stats.items())))
if problems:
    print(f"\nproblems ({len(problems)}):")
    for p in problems:
        print("  ", p)
