Multi-Vehicle Towing - Uebersetzungen / Translations
=========================================================

DEUTSCH
-------
Alle Texte der Mod stehen in vier Dateien pro Sprache:

  42\media\lua\shared\Translate\<SPRACHE>\ContextMenu.json   (Eintraege im Fahrzeug-Rundmenue)
  42\media\lua\shared\Translate\<SPRACHE>\UI.json            (Optionsmenue, Meldungen)
  42\media\lua\shared\Translate\<SPRACHE>\Recipes.json       (Name des Rezepts)
  42\media\lua\shared\Translate\<SPRACHE>\Sandbox.json       (Server-Einstellungen fuer Multiplayer)

So fuegst du eine Sprache hinzu (Beispiel Franzoesisch):
 1. Ordner "42\media\lua\shared\Translate\EN" kopieren und die Kopie "FR" nennen.
    Die Ordnernamen sind die Kuerzel des Spiels (DE, FR, ES, PL, RU, CN, JP, KO, PTBR ...).
 2. In allen vier .json-Dateien nur die Texte HINTER dem Doppelpunkt uebersetzen.
    Die Schluessel (z.B. "ContextMenu_MultiTow_Attach") NICHT aendern.
 3. %1 und %2 sind Platzhalter fuer Fahrzeugnamen. Sie muessen im Text bleiben (Reihenfolge darf wechseln).
 4. Dateien als UTF-8 speichern. Sonderzeichen sind erlaubt; bei Problemen ae/oe/ue verwenden.
 5. Spiel starten, Sprache im Spiel einstellen und pruefen.

Fehlt ein Text in deiner Sprache, zeigt das Spiel die englische Fassung bzw. den Schluesselnamen.

ENGLISH
-------
All texts live in four files per language:

  42\media\lua\shared\Translate\<LANG>\ContextMenu.json   (entries in the vehicle radial menu)
  42\media\lua\shared\Translate\<LANG>\UI.json            (options menu, messages)
  42\media\lua\shared\Translate\<LANG>\Recipes.json       (recipe name)
  42\media\lua\shared\Translate\<LANG>\Sandbox.json       (server settings for multiplayer)

To add a language (example: French):
 1. Copy the folder "42\media\lua\shared\Translate\EN" and name the copy "FR".
    Folder names are the game's language codes (DE, FR, ES, PL, RU, CN, JP, KO, PTBR ...).
 2. Translate only the text AFTER the colon in all four .json files. Do NOT change the keys.
 3. %1 and %2 are placeholders for vehicle names and must stay in the text (their order may change).
 4. Save as UTF-8.
 5. Start the game, switch the language and check.
