# apple-notes-pdf-export

Exports an Apple Notes folder tree to one PDF per note, mirroring the folder
structure — built specifically to survive **Apple Pencil handwritten notes**,
which every simpler approach mangles or drops.

First run: 262 college notes → 262 PDFs / 971 pages, no content lost.

## Why this isn't a ten-line script

Notes offers no bulk PDF export, and each obvious workaround loses something:

| Approach | What breaks |
|---|---|
| AppleScript `body` → HTML → PDF | Inline images survive as base64, but **handwriting and PDF attachments are dropped entirely** |
| Notes' `File > Export To > PDF` | Renders handwriting at full resolution, then **crams the whole note into a tiny column** on 1–2 Letter pages |
| `File > Print` → Save as PDF | Byte-for-byte the same bad layout as Export To |
| Reading the fallback renders off disk | Notes keeps a flattened PNG per drawing, but many are **as small as 224px wide** — illegible |

The fix is a hybrid: pick the best available source per note, then re-lay-out
everything through one pagination pass.

## How it works

1. **Enumerate** the folder tree. `folders of account` returns a *flat* list, so
   the hierarchy is rebuilt from each folder's `container` id. Folder references
   go stale the instant they cross a `tell`/handler boundary, so everything is
   addressed by `folder id` inside each block.
2. **Extract** each note's HTML body, keyed by note id.
3. **Classify.** A note goes down the *hi-fi* path when its only local rendering
   of handwriting is a low-resolution fallback (`< 800px` wide), or it has a
   `com.apple.paper` attachment with no embedded image at all. Everything else
   takes the *fast* path.
4. **Render.**
   - *fast*: `WKWebView` → one tall PDF page.
   - *hi-fi*: drive `File > Export To > PDF` through Accessibility, which makes
     Notes render the Paper bundle at full resolution (e.g. 1536 × 21118).
5. **Paginate** — the important part. Each source page is measured for its
   content bounding box, then drawn onto Letter pages under a clip-and-magnify
   transform, sliced vertically with a 12pt overlap. Because the source PDF is
   *drawn* rather than rasterized, embedded images keep native resolution.
6. **Merge** file attachments that live outside the note body (Notes stores them
   at `Media/<mediaUUID>/<generation>/<filename>`, reachable only by joining
   `ZICCLOUDSYNCINGOBJECT.ZMEDIA` — the attachment's own `ZIDENTIFIER` does *not*
   name that directory).
7. **Audit** every output page for ink coverage, so blank pages and empty
   documents surface instead of hiding in a 900-page pile.

## Usage

```bash
./run.sh College ~/Desktop/Notes\ Export
```

Arguments: top-level Notes folder, destination directory, optional staging dir
(defaults to `~/.cache/apple-notes-pdf-export`).

The terminal app running this needs **Automation** access to Notes,
**Accessibility** access (the hi-fi path clicks menus), and **Full Disk Access**
(to read `~/Library/Group Containers/group.com.apple.notes`).

While the hi-fi phase runs, Notes holds the screen — roughly 3.5s per note.

## What a PDF does and does not preserve

Preserved: all visible content, handwriting at full render resolution, attached
PDFs embedded losslessly, folder structure.

**Not** preserved: editable Pencil vector strokes, note creation/modification
dates, tags, pinned state, checklist interactivity, and links as live data.
Treat the output as an archive copy, not a backup you can restore into Notes.

## Layout

```
bin/build_folders.py           rebuild folder hierarchy from the flat list
bin/extract.applescript        dump note bodies + ids
bin/survey_attachments.applescript  diagnostic: attachment counts and names
bin/build_jobs.py              classify fast vs hi-fi, resolve attachments, plan paths
bin/render.swift               HTML -> one tall PDF page (WKWebView)
bin/hifi_export.applescript    drive Notes' own PDF export
bin/paginate.swift             clip-and-magnify slicing into Letter pages
bin/pdfmerge.swift             concatenate PDFs / images (PDFKit)
bin/assemble.py                paginate + merge + place at final paths
bin/audit.swift                per-page ink coverage report
```
