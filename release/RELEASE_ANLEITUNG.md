> **0.14.0:** Reihenfolge beim Hochladen und Steam-Abhängigkeit „DO Utilities“ siehe `D:\Claude\DOUtilities\release\RELEASE_ANLEITUNG.md`.

# Workshop-Release – Multi-Vehicle Towing 0.16.2

Alles ist vorbereitet unter `C:\Users\Alex\Zomboid\Workshop\MultiVehicleRoadTrain\`:

```
MultiVehicleRoadTrain\
  preview.png          Vorschaubild für Steam (256 x 256, so verlangt es das Spiel)
  workshop.txt         Titel, Beschreibung, Tags, Sichtbarkeit (liest das Spiel beim Hochladen)
  Contents\mods\multitowmod\
    42\                die Mod (Lua, Java-Teil, Bilder, Übersetzungen)
    common\            leerer Pflichtordner für Build 42
    CHANGELOG.md
```

## 1. Vorher kurz prüfen
- **Neu in 0.16.2 (Host-Spiele):** Java-Teil neu gebaut – ZombieBuddy fragt nach der Freigabe (**Ja + dauerhaft**), Konsole zeigt `[MultiTowCore] Version 0.16.2 loaded`.
  - **Schalter aus** (Standard): Host starten → startet ganz normal (wichtigster Test!).
  - **Schalter an** (Optionen → DO Utilities → Multi-Tow → Debug-Optionen anzeigen → „Host-Spiele: ZombieBuddy auf dem Host-Server starten (Test)“ → Übernehmen): Host starten → `console.txt`: `Host server: ZombieBuddy start option passed ...` (nur EINE Startoption), `coop-console.txt`: `[MultiTowCore] Multiplayer mode: server` und `Version 0.16.2 loaded`. Im Spiel Kette mit 3 Fahrzeugen kuppeln.
  - Nach Neustart **ohne** Öffnen der Optionen: Schalter wirkt trotzdem (wird beim Klick auf Host aus ModOptions.ini gelesen).
- **Neu in 0.16.1 (Fehlerbehebung):** Java-Teil neu gebaut – ZombieBuddy fragt nach der Freigabe (Ja), Konsole zeigt `[MultiTowCore] Version 0.16.1 loaded`.
  - Normaler Start (Mods schon beim Spielstart aktiv): alles wie vorher, Optionsseite zeigt den Java-Teil 0.16.1.
  - Nachstellen des Fehlers: im Hauptmenü alle Mods aus → Spiel neu starten → ZombieBuddy, DO Utilities und Multi-Tow im Hauptmenü einschalten (ohne Neustart) → Spielstand laden. Erwartet: voller Modus (nicht „basic mode“) und in der Konsole `[MultiTowCore] Lua functions registered right away ...`.
  - Keine Meldung „Object tried to call nil in pcall“ mehr in console.txt.
  - Optionen → DO Utilities: Karte zeigt **Multi-Vehicle Towing v0.16.1**, keine Meldung „... was updated ... Please restart“ (die Mod liest ihre Version jetzt selbst aus der mod.info).
  - **Spielstand ohne Multi-Tow:** Im Hauptmenü Multi-Tow an, beim Laden eines Spielstands in dessen Mod-Liste Multi-Tow aus → im Spiel normales Abschleppen (nur 2 Fahrzeuge, keine Kette), Konsole: `Java part paused`. Zurück ins Hauptmenü → Konsole: `active again`.
  - Unsigniert wie 0.16.0 (keine `.zbs`-Datei im Mod).
- **Neu in 0.16.0 (3D-Kette):** Spiel **ganz neu starten** (neue Modelle und Haken werden nur beim Start geladen). ZombieBuddy fragt nach der Freigabe (Ja), Konsole zeigt `[MultiTowCore] Version 0.16.0 loaded`.
  - Spieloptionen: „3D-Gegenstände am Boden“ an. Kette zwischen zwei Fahrzeugen: echtes 3D-Modell, flackert beim Fahren nicht, Glieder bleiben bei jedem Abstand gleich groß. Stange: weiter ein Bild.
  - „3D-Gegenstände am Boden“ aus: die Kette ist wieder das alte Bild.
  - Kette mit Haken auf den Boden legen / in die Hand nehmen: neues Modell (Rolle mit roten Haken), neues Symbol im Inventar.
  - W900-Mod: Fahrzeug hinter einen Auflieger (z. B. Container) kuppeln – es bleibt auf normaler Höhe. Konsole: `hitches at wheel height for … vehicle type(s)`.
  - Unsigniert: Die `.zbs`-Datei liegt NICHT im Mod, bis ZombieBuddy deinen Eintrag in der Autorenliste kennt (dann signieren, siehe `D:\Claude\MultiTow\signing`).
- **Neu in 0.15.0 (Mithelfen):** Java-Teil neu gebaut – ZombieBuddy fragt nach der Freigabe (Ja), Konsole zeigt `[MultiTowCore] Version 0.15.0 loaded`.
  Optionen → Multi-Vehicle Towing: bei **PKW und LKW** „Höhe der Zusatzleistung“ auf **Aus** stellen → erst dann ist „Laufende gezogene Fahrzeuge helfen mit (%)“ (Gameplay) einstellbar.
  Zug kuppeln, bei einem gezogenen Fahrzeug den **Motor laufen lassen**, losfahren: Der Zug zieht spürbar besser an. Konsole: `Running towed vehicles help with 50% ...`.
- Spiel mit der aktuellen Mod einmal starten: ZombieBuddy-Freigabe bestätigen, Konsole zeigt `[MultiTowCore] Version 0.12.6 loaded`.
- Einmal **ohne** ZombieBuddy starten (Basis-Modus): Mod lädt ohne Fehler, Warnseite im Assistenten, rote Optionen.
- Kurz kuppeln, fahren, abkuppeln – keine roten Fehler.
- Optionen → **DO Utilities** → Karte „Multi-Vehicle Towing“ öffnen: Bilder, Optionen, Debug-Bereich und „Zurück“ funktionieren; beim Darüberfahren ist die Karte hellblau (74ABED), die Schrift der Knöpfe „Zurück“ / „Workshop-Seite“ dunkel.
- Konsole (`console.txt`) prüfen: `[DofDHub] hub file v9 is active` und `[DofDHub] page built: 2 mods, 2 with options (hub file v9)`.
- Neu in 0.14.0 prüfen: Name in der Mod-Liste „Multi-Vehicle Towing“, Rundmenü „Multi-Tow: Attach …“, Zug-Anzeige mit Titel „Multi-Tow“.
- Neu in 0.14.0 (Neustart-Hinweis): Spiel **ohne** MultiTow starten, MultiTow im Mod-Menü einschalten → in den Optionen steht oben orange „Restart needed …“.
- Der Java-Teil ist unverändert und meldet weiter `Version 0.12.6`; ZombieBuddy fragt nicht neu nach der Freigabe.
- Die Optionsseite kommt jetzt aus der eigenen Mod **DO Utilities** (Pflicht-Mod). Reihenfolge beim Hochladen: siehe Hinweis ganz oben.

## 2. Hochladen im Spiel
1. Hauptmenü → **WORKSHOP** → den Punkt zum Erstellen/Aktualisieren eigener Objekte wählen.
2. **MultiVehicleRoadTrain** auswählen → **Next**.
3. Titel, Beschreibung und Tags kommen aus `workshop.txt` (kannst du dort noch ändern).
3a. Der Titel auf Steam wird beim Hochladen zu **Multi-Vehicle Towing** (aus `workshop.txt`). Workshop-ID und Link bleiben gleich; der Ordner heißt weiter `MultiVehicleRoadTrain`.
4. Sichtbarkeit: steht auf **public**. Wenn du erst selbst testen willst: auf **private** oder **friends only** stellen, später auf Steam umschalten.
5. Hochladen bestätigen. Das Spiel trägt danach die neue Workshop-ID in `workshop.txt` ein (`id=...`) – **diese Datei nicht löschen**, sonst wird beim nächsten Update ein neuer Eintrag angelegt.

## 3. Auf der Steam-Seite der Mod (wichtig!)
1. **ZombieBuddy NICHT als Voraussetzung eintragen:** ZombieBuddy ist jetzt freiwillig (ohne läuft der Basis-Modus).
   Falls du es schon unter „Add/Remove Required Items" eingetragen hast (Workshop-ID **3619862853**): dort wieder **entfernen**.
   Sonst zwingt Steam beim Abonnieren alle Spieler, ZombieBuddy mit zu abonnieren. Die Empfehlung steht in der Beschreibung.
2. **Beschreibung prüfen:** `workshop.txt` ist reines ASCII (das Spiel liest die Datei nicht sicher als UTF-8); die Beschreibung ist nur noch Englisch.
   Für die Fassung mit Sonderzeichen (z. B. ⚠): Inhalt von `WORKSHOP_DESCRIPTION.txt` auf der Steam-Seite unter „Edit Title & Description" einfügen.
3. **Screenshots** hinzufügen (z. B. deine Kopfbilder, Zug-Anzeige, Warnblinker bei Nacht).
4. **Change Notes:** Inhalt von `STEAM_CHANGELOG.txt` einfügen – oben steht die neueste Version; wurde eine Version nie hochgeladen (z. B. 0.12.5), deren Abschnitt mit einfügen (Steam-Seite → „Change Notes“ → Eintrag des neuen Uploads bearbeiten). Die Datei ist schon im Steam-Format (BBCode).

## 4. Spätere Updates
- Ich baue die Mod wie gewohnt, kopiere sie nach `Contents\mods\multitowmod\` und passe Version/Changelog an.
- Jedes Update des Java-Teils bedeutet: ZombieBuddy fragt alle Spieler noch einmal nach der Freigabe
  (bis die Signatur funktioniert, siehe `D:\Claude\MultiTow\signing`).

## Hinweise
- **Mehrspieler** ist in der Beschreibung als „experimentell, ungetestet" markiert.
- Die Mod ist **nicht signiert** (ZombieBuddy 2.3.4 kann den Schlüssel vom Steam-Profil nicht lesen). Steht so auch in der Beschreibung.
- `ZBVersionMin=2.3.4` in `mod.info`: ältere ZombieBuddy-Versionen laden den Java-Teil nicht (die Mod läuft dann im Basis-Modus).
- `require=\ZombieBuddy` steht nicht mehr in `mod.info` – die Mod lässt sich auch ohne ZombieBuddy aktivieren.
- Steam erlaubt höchstens 8000 Zeichen Beschreibung; die jetzige hat etwa 7700. Bei Ergänzungen etwas anderes kürzen.

## Ab jetzt bei jedem Release: Changelog-Kopie in 42
- `CHANGELOG.md` liegt zusätzlich als Kopie in `42\CHANGELOG.md`. **Beide müssen gleich sein** – nach jeder Änderung am Changelog die Kopie erneuern.
- DO Utilities (ab 1.1.0) liest den Changelog dort und zeigt ihn im Fenster "What's new" und im Reiter "Changelogs".
