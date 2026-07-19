# 3Dark

A macOS app for archiving 3D print models — file-system first.

Every model is a folder inside your archive; description, tags, and print
settings live next to the files in a `model.md` (markdown with YAML front
matter). Everything stays fully usable without the app: browse it in
Finder, edit it in any text editor, sync it with any service, version it
with git. See [CONCEPT.md](CONCEPT.md) for the full design.

## Features

- **Folder-based archive** — one folder per model, `model.md` as the
  single source of truth; external edits are picked up live (FSEvents +
  polling fallback)
- **3D preview** — STL, OBJ, PLY, USDZ via SceneKit/ModelIO plus a
  built-in 3MF parser; camera reset; multi-part assemblies render side
  by side in a combined view
- **Thumbnails** — rendered offscreen automatically, or pick any image
  file of the model as its thumbnail
- **Tags & collections** — chip-based editing with suggestions, sidebar
  filters (AND/OR), rating filter, full-text search
- **Grid and list view** — switchable, remembered across launches
- **Import** — drop ZIPs or folders onto the app; contained text files
  are folded into the model.md in hierarchy order, redundant copies are
  cleaned up, sources stay untouched; source link, license, author, and
  title are extracted automatically from bundled readme and PDF files
  (deterministic patterns, empty fields only)
- **Trash** — deleted models move to a `deleted/` folder inside the
  archive and can be restored or removed for good from the trash view
- **AI enrichment (opt-in)** — with an Anthropic API key (Settings → AI),
  one click fetches a model's source page and suggests missing metadata;
  suggestions are stored as separate `ai_*` fields, marked with ✨ in the
  UI, and never overwrite your data until you accept them
- **Cura hand-off** — send any 3D file to UltiMaker Cura with one click
- **Localized** — English and German, switchable in Settings (⌘,),
  light/dark/system appearance; Liquid Glass styling on macOS 26

## Building

Requires Xcode 16 or newer (deployment target macOS 14):

```sh
open 3Dark.xcodeproj
```

or via CLI:

```sh
xcodebuild -project 3Dark.xcodeproj -scheme 3Dark -configuration Debug build
```

A small sample archive ships in `SampleArchive/` — select it as the
archive folder on first launch to explore the app.

## File format

```markdown
---
title: 3DBenchy
tags: [calibration, boat]
collections: [Getting Started]
material: PLA
nozzle: 0.4
layer_height: 0.2
supports: no
rating: 4
---

## Description

Classic calibration model …
```

Legacy German front matter keys from earlier versions are still read and
migrate to the English keys automatically on the next save.
