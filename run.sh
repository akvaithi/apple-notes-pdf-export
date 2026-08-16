#!/bin/bash
# Export an Apple Notes folder tree to per-note PDFs, preserving handwriting.
#
#   ./run.sh <TopLevelNotesFolder> <DestinationDir> [StagingDir]
#
# Example:
#   ./run.sh College ~/Desktop/Notes\ Export
#
# Requires: macOS, Xcode Command Line Tools (swiftc), and for the terminal app
# running this — Automation access to Notes, Accessibility access (the hi-fi
# path drives Notes' menus), and Full Disk Access (to read Notes' container).

set -euo pipefail

ROOT_FOLDER="${1:?usage: run.sh <NotesFolder> <DestDir> [StagingDir]}"
DEST="${2:?usage: run.sh <NotesFolder> <DestDir> [StagingDir]}"
STAGING="${3:-$HOME/.cache/apple-notes-pdf-export}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/bin"
CONTAINER="$HOME/Library/Group Containers/group.com.apple.notes"

ACCOUNT_DIR="${NOTES_ACCOUNT_DIR:-$(find "$CONTAINER/Accounts" -maxdepth 1 -mindepth 1 -type d | head -1)}"
[ -d "$ACCOUNT_DIR" ] || { echo "cannot locate Notes account dir"; exit 1; }

mkdir -p "$STAGING"/{html,raw,paged,db,bin} "$DEST"

echo "==> compiling helpers"
for t in render paginate pdfmerge audit; do
  if [ ! -x "$STAGING/bin/$t" ] || [ "$BIN/$t.swift" -nt "$STAGING/bin/$t" ]; then
    swiftc -O -o "$STAGING/bin/$t" "$BIN/$t.swift"
  fi
done

echo "==> snapshotting Notes database"
# Notes is live; copy the WAL alongside so the snapshot is consistent.
cp "$CONTAINER/NoteStore.sqlite" "$STAGING/db/" 2>/dev/null || true
cp "$CONTAINER/NoteStore.sqlite-wal" "$STAGING/db/" 2>/dev/null || true
cp "$CONTAINER/NoteStore.sqlite-shm" "$STAGING/db/" 2>/dev/null || true
sqlite3 "$STAGING/db/NoteStore.sqlite" "PRAGMA journal_mode=DELETE;" >/dev/null 2>&1 || true

echo "==> resolving folder tree under '$ROOT_FOLDER'"
python3 "$BIN/build_folders.py" "$STAGING" "$ROOT_FOLDER"

echo "==> extracting note bodies"
rm -f "$STAGING"/html/*.html
osascript "$BIN/extract.applescript" "$STAGING" 2>/dev/null | tail -1

echo "==> classifying notes"
python3 "$BIN/build_jobs.py" "$STAGING" "$ACCOUNT_DIR" "$DEST"

echo "==> rendering local (fast) notes"
"$STAGING/bin/render" "$STAGING/fast.tsv" | tail -1

if [ -s "$STAGING/hifi.tsv" ]; then
  echo "==> exporting low-resolution notes via Notes.app"
  echo "    Notes will take over the screen; do not use the Mac until this finishes."
  osascript "$BIN/hifi_export.applescript" "$STAGING"
fi

echo "==> paginating and placing PDFs"
python3 "$BIN/assemble.py" "$STAGING"

echo "==> auditing output"
"$STAGING/bin/audit" "$DEST"

echo
echo "Done. PDFs are in: $DEST"
