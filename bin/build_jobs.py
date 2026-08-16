#!/usr/bin/env python3
"""Classify each note into the fast (local HTML) or hi-fi (Notes export) path
and lay out every output path.

A note goes hi-fi when its only rendering of handwriting is a low-resolution
fallback image, since magnifying that during pagination would just blur it.
"""
import os
import re
import sys
import glob
import struct
import base64
import sqlite3
import collections

STAGING, ACCOUNT_DIR, DEST = sys.argv[1], sys.argv[2], sys.argv[3]
LOWRES_W = 800

IMAGE_UTIS = {"public.jpeg", "public.png", "public.heic", "public.tiff",
              "public.image", "com.compuserve.gif"}

db = sqlite3.connect(f"file:{STAGING}/db/NoteStore.sqlite?mode=ro", uri=True)
att = collections.defaultdict(list)
for pk, uti, uuid, fname in db.execute("""
    SELECT a.ZNOTE, a.ZTYPEUTI, m.ZIDENTIFIER, m.ZFILENAME
    FROM ZICCLOUDSYNCINGOBJECT a
    LEFT JOIN ZICCLOUDSYNCINGOBJECT m ON a.ZMEDIA = m.Z_PK
    WHERE a.ZNOTE IS NOT NULL AND a.ZTYPEUTI IS NOT NULL"""):
    att[pk].append((uti, uuid, fname))


def resolve(uuid, fname):
    if not uuid or not fname:
        return None
    base = os.path.join(ACCOUNT_DIR, "Media", uuid)
    for pat in (os.path.join(base, "*", fname), os.path.join(base, fname)):
        hits = [h for h in glob.glob(pat) if os.path.isfile(h)]
        if hits:
            return hits[0]
    return None


def png_widths(html):
    """Widths of images embedded as base64 data URIs."""
    out = []
    for m in re.finditer(r'src="data:image/(\w+);base64,([^"]{64,})"', html):
        head = base64.b64decode(m.group(2)[:200] + "==")
        if head[:8] == b"\x89PNG\r\n\x1a\n":
            out.append(struct.unpack(">II", head[16:24])[0])
        elif head[:2] == b"\xff\xd8":
            out.append(10 ** 6)          # JPEG: assume fine, they're photos
    return out


def safe(name, fallback="Untitled"):
    name = re.sub(r'[/:\x00-\x1f]', "-", name).strip().rstrip(".")
    name = re.sub(r"\s+", " ", name)
    return (name[:120] or fallback)


fast, hifi, finals = [], [], []
used = collections.Counter()
stats = collections.Counter()

for line in open(f"{STAGING}/manifest.tsv", encoding="utf-8"):
    line = line.rstrip("\n")
    if not line.strip():
        continue
    idx, relpath, title, moddate, noteid = line.split("\t")
    pk = int(noteid.rsplit("/p", 1)[1])
    html_path = os.path.join(STAGING, "html", f"{idx}.html")
    html = open(html_path, encoding="utf-8", errors="replace").read()

    widths = png_widths(html)
    utis = [u for u, _, _ in att.get(pk, [])]
    has_paper = any(u.startswith("com.apple.paper") for u in utis)

    lowres = bool(widths) and max(widths) < LOWRES_W
    if lowres or (has_paper and not widths):
        kind = "hifi"
    else:
        kind = "fast"
    stats[kind] += 1

    # non-image attachments that live outside the HTML body
    extras = []
    for uti, uuid, fname in att.get(pk, []):
        if uti in IMAGE_UTIS or uti.startswith("com.apple.paper"):
            continue
        p = resolve(uuid, fname)
        if p:
            extras.append(p)
            stats["extras_appended"] += 1

    outdir = os.path.join(DEST, relpath)
    base = safe(title)
    used[(outdir, base.lower())] += 1
    n = used[(outdir, base.lower())]
    final = os.path.join(outdir, f"{base}.pdf" if n == 1 else f"{base} ({n}).pdf")

    src = os.path.join(STAGING, "raw", f"{idx}.pdf")
    if kind == "fast":
        fast.append((html_path, src))
    else:
        hifi.append((idx, noteid, src))

    finals.append((idx, kind, src, final, ";".join(extras)))

os.makedirs(f"{STAGING}/raw", exist_ok=True)
os.makedirs(f"{STAGING}/paged", exist_ok=True)
for _, _, _, final, _ in finals:
    os.makedirs(os.path.dirname(final), exist_ok=True)

with open(f"{STAGING}/fast.tsv", "w", encoding="utf-8") as fh:
    for h, o in fast:
        fh.write(f"{h}\t{o}\n")
with open(f"{STAGING}/hifi.tsv", "w", encoding="utf-8") as fh:
    for idx, nid, o in hifi:
        fh.write(f"{idx}\t{nid}\t{o}\n")
with open(f"{STAGING}/finals.tsv", "w", encoding="utf-8") as fh:
    for row in finals:
        fh.write("\t".join(row) + "\n")

print(f"total {len(finals)}   fast {stats['fast']}   hifi {stats['hifi']}"
      f"   extras {stats['extras_appended']}")
