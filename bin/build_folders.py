#!/usr/bin/env python3
"""Query Notes.app for the folder graph and emit folders.tsv for the College subtree.

Notes' AppleScript `folders of account` is flat, so the hierarchy has to be
rebuilt from each folder's container id.
"""
import subprocess
import sys
import os

STAGING = sys.argv[1]
ROOT_NAME = sys.argv[2] if len(sys.argv) > 2 else "College"

PROBE = '''
tell application "Notes"
  set out to ""
  repeat with f in folders
    set cid to "NONE"
    try
      set cid to (id of container of f)
    end try
    set out to out & (id of f) & tab & (name of f) & tab & cid & tab & (count of notes of f) & linefeed
  end repeat
  return out
end tell
'''

raw = subprocess.run(["osascript", "-e", PROBE],
                     capture_output=True, text=True, check=True).stdout

folders = {}   # id -> (name, parent_id, count)
for line in raw.splitlines():
    if not line.strip():
        continue
    parts = line.split("\t")
    if len(parts) < 4:
        continue
    fid, name, parent, count = parts[0], parts[1], parts[2], parts[3]
    folders[fid] = (name, parent, int(count))

root_id = next((fid for fid, v in folders.items() if v[0] == ROOT_NAME), None)
if root_id is None:
    sys.exit(f"No folder named {ROOT_NAME!r} found")

children = {}
for fid, (name, parent, _) in folders.items():
    children.setdefault(parent, []).append(fid)


def sanitize(part):
    """Make one path component safe for the filesystem."""
    part = part.replace("/", "-").replace(":", "-").strip()
    return part or "Untitled"


rows = []
total = 0


def walk(fid, relpath):
    global total
    name, _, count = folders[fid]
    total += count
    rows.append((fid, relpath, count))
    for child in sorted(children.get(fid, []), key=lambda c: folders[c][0]):
        walk(child, relpath + "/" + sanitize(folders[child][0]))


walk(root_id, sanitize(folders[root_id][0]))

with open(os.path.join(STAGING, "folders.tsv"), "w") as fh:
    for fid, relpath, count in rows:
        fh.write(f"{fid}\t{relpath}\n")

for fid, relpath, count in rows:
    print(f"{count:5d}  {relpath}")
print(f"\n{len(rows)} folders, {total} notes total")
