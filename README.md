# 3Dark

macOS-App zum Archivieren von 3D-Druck-Modellen.

Jedes Modell ist ein Ordner im Archiv; Beschreibung, Tags und Druckparameter
liegen als `model.md` (Markdown mit YAML-Frontmatter) daneben — vollständig
nutzbar auch ohne die App. Details: [KONZEPT.md](KONZEPT.md).

## Bauen

Xcode ≥ 16 (macOS 14+ als Ziel):

```sh
open 3Dark.xcodeproj
```

oder per CLI:

```sh
xcodebuild -project 3Dark.xcodeproj -scheme 3Dark -configuration Debug build
```

Zum Ausprobieren liegt unter `Beispielarchiv/` ein Mini-Archiv, das sich
beim ersten Start als Archiv-Ordner auswählen lässt.
