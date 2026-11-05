# Deine Nexus-Skripte

Lua- und Luau-Dateien direkt hier in **Scripts** hochladen. Das Vorschaubild hat denselben Basisnamen und liegt daneben:

```
Scripts/
  tsb.lua
  tsb.png
  rivals.luau
  rivals.webp
```

Nexus zeigt den Dateinamen, das passende Bild und **Im Editor öffnen**. Das Öffnen führt den Code noch nicht aus. Unterstützte Bilder: PNG, WebP, JPG/JPEG und GIF, bis 6 MB. Skripte: UTF-8, bis 1.900.000 Bytes. Aktuell bis 100 Skripte. Gleichnamige Lua/Luau-Dateien unterscheiden sich im Namen; ein Bild kann zu beiden passen.

Nach einem Commit erstellt die GitHub-Aktion **Nexus script catalog** automatisch `catalog.json`. Die Desktop-App prüft diese Liste beim Start und alle 30 Sekunden; bei Bedarf **Aktualisieren** drücken. Erst die Fertigstellung der GitHub-Aktion abwarten. Bei einer Netzstörung bleibt die zuletzt gespeicherte Bibliothek verfügbar. `catalog.json` wird automatisch verwaltet.

Dieser Ordner ist **öffentlich**. Nur Skripte und Bilder hochladen, die öffentlich geteilt werden sollen. Der Quellcode der Desktop-Anwendung bleibt im separaten privaten Repository.
