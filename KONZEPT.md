# 3Dark — Konzept

Archiv-App für 3D-Druck-Modelle auf macOS. Dateien und Metadaten bleiben
vollständig im Dateisystem nutzbar — die App ist nur ein komfortabler
Aufsatz, keine Voraussetzung.

## Ziele

- Alle 3D-Modelle an einem Ort archivieren, inkl. Beschreibung und Druckhinweisen
- Datenhaltung als lokale Ordnerstruktur, ein Ordner pro Modell
- Metadaten in einer Markdown-Datei im jeweiligen Ordner → ohne App lesbar/editierbar
- 3D-Vorschau direkt in der App
- Tagging und vollständige Filterung

## Nicht-Ziele (bewusst)

- Keine Datenbank als primäre Datenhaltung (nur als flüchtiger Index/Cache)
- Keine Cloud-/Server-Komponente (Sync überlässt man iCloud Drive o. Ä.)
- Kein eigener Slicer, kein Editieren der 3D-Geometrie

## Datenhaltung

```
3D-Archiv/                  ← frei wählbarer Wurzelordner
├── Benchy/
│   ├── model.md            ← Metadaten + Beschreibung (Pflichtdatei, von App erzeugt)
│   ├── benchy.stl
│   ├── benchy.3mf
│   ├── .thumbnail.png      ← von der App generiert, regenerierbar
│   └── fotos/
│       └── druck-01.jpg
└── Zahnbürstenhalter/
    └── ...
```

Regeln:

- **Das Dateisystem ist die einzige Wahrheit.** Die App liest und schreibt
  ausschließlich `model.md` und die Dateien im Ordner.
- Ordnername = Anzeigename (überschreibbar via `title` im Frontmatter).
- Externe Änderungen (Editor, Finder) erkennt die App per FSEvents und
  aktualisiert ihren Index automatisch.
- Der Wurzelordner wird per Security-Scoped Bookmark gemerkt.

## Metadaten-Schema (`model.md`)

YAML-Frontmatter für strukturierte Daten, darunter freier Markdown-Text:

```markdown
---
title: 3DBenchy
tags: [kalibrierung, boot, deko]
quelle: https://www.printables.com/model/3161-3d-benchy
autor: CreativeTools
lizenz: CC BY-ND
material: PLA
duese: 0.4
schichthoehe: 0.2
stuetzen: nein
gedruckt: 2026-07-01
bewertung: 4
---

## Beschreibung

Klassisches Kalibrierungsmodell …

## Druckhinweise

Bei 0.2 mm ohne Stützen problemlos …
```

- Alle Frontmatter-Felder sind optional außer `title` und `tags`.
- Unbekannte Felder bleiben beim Speichern erhalten (Roundtrip-sicher).
- Datumsfelder als ISO-Format (`YYYY-MM-DD`).

## Unterstützte Formate

| Format | Archivieren | Vorschau | Umsetzung |
|--------|-------------|----------|-----------|
| STL    | ✅ | ✅ | ModelIO/SceneKit nativ |
| 3MF    | ✅ | ✅ | eigener Parser (ZIP + XML-Mesh) |
| sonstige Dateien (Fotos, PDFs, …) | ✅ | Bilder ja | einfache Dateiliste im Modell-Detail |

## App-Aufbau (UI)

Dreispaltiges Standard-Layout (`NavigationSplitView`):

1. **Sidebar:** „Alle Modelle", Tag-Liste mit Zählern, später Smart Folders.
   Mehrere Tags anklickbar → UND/ODER-Umschalter.
2. **Übersicht:** Grid mit Thumbnails + Titel + Tags; Suchfeld (Volltext über
   Titel, Tags, Beschreibung); Sortierung nach Name/Datum/Bewertung.
3. **Detailansicht:**
   - 3D-Vorschau (SceneKit-View: rotieren, zoomen; Material-neutral gerendert)
   - Metadaten-Formular (Frontmatter-Felder) + Tag-Editor mit Autocomplete
   - Markdown-Bereich: gerenderte Anzeige, umschaltbar auf Editor
   - Dateiliste des Ordners mit „Im Finder zeigen" und **„In Cura öffnen"**

Thumbnails rendert die App beim ersten Anzeigen offscreen aus der 3D-Datei
und legt sie als `.thumbnail.png` im Modellordner ab (versteckt, regenerierbar).

## Technik

- Swift 5.x, SwiftUI, Zielversion macOS 14+
- SceneKit + ModelIO für STL-Vorschau; eigener 3MF-Loader
- Yams (SPM) für YAML-Frontmatter
- FSEvents für Ordnerüberwachung
- Index: in-memory beim Start aufgebaut (Frontmatter aller `model.md` parsen);
  bei Archiven dieser Größenordnung schnell genug, kein SQLite nötig
- Verteilung: lokal signierte App, kein App Store; deshalb keine harten
  Sandbox-Einschränkungen nötig
- „In Cura öffnen": `NSWorkspace.open` mit der UltiMaker-Cura-App

## MVP-Umfang (v1) — umgesetzt

- [x] Wurzelordner wählen + merken
- [x] Modell-Liste/Grid mit Thumbnails
- [x] STL- und 3MF-Vorschau
- [x] `model.md` lesen/schreiben (Frontmatter-Formular + Markdown-Editor)
- [x] Tags vergeben, Tag-Sidebar, kombinierte Filter, Volltextsuche
- [x] Neues Modell anlegen (Ordner + `model.md`-Gerüst), Dateien per Drag & Drop in den Ordner
- [x] „Im Finder zeigen" / „In Cura öffnen"
- [x] FSEvents: externe Änderungen live übernehmen

## Später (Roadmap)

- **v1.1:** ZIP-Import per Drag & Drop (Printables-Downloads auto-entpacken),
  Duplikaterkennung per Datei-Hash
- **v1.2:** G-Code archivieren + Metadaten (Druckzeit, Filament) auslesen,
  Druckhistorie als Tabelle im Markdown
- **v1.3:** Smart Folders (gespeicherte Filter), Bewertungs-/Statistik-Ansicht
- **später:** Quick-Look-Plugin für STL im Finder, STEP-Ablage
