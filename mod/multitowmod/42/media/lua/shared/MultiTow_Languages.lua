--[[==========================================================================
    MultiTow_Languages.lua                              [ client + server ]
  ----------------------------------------------------------------------------
    WAS:    Kurze Namen fuer die Texte des Rundmenues (Taste V)
            -> lange Uebersetzungsschluessel.
    WO STEHEN DIE TEXTE?
            Nicht im Code! Alle sichtbaren Texte liegen in den Uebersetzungs-
            dateien, je Sprache ein Ordner:
              media/lua/shared/Translate/<SPRACHE>/ContextMenu.json   Rundmenue   ("ContextMenu_MultiTow_...")
              media/lua/shared/Translate/<SPRACHE>/UI.json            Optionen    ("UI_MultiTow_...")
    NEUE SPRACHE?
            Ordner kopieren (z.B. EN -> FR), nur die Texte rechts uebersetzen,
            die Schluessel links NICHT aendern. Mehr dazu: Translations_README.txt
============================================================================]]

-- Die Tabelle "MultiTow" ist der gemeinsame Topf fuer alles aus dieser Mod.
-- "MultiTow or {}" heisst: gibt es sie schon (andere Datei war schneller), nimm sie, sonst leg sie neu an.
MultiTow = MultiTow or {}

-- Kurzname (im Code)   ->   Uebersetzungsschluessel (in ContextMenu.json)
local KEYS = {
    attach = "ContextMenu_MultiTow_Attach",              -- "Multi-Tow: Ankuppeln (%1 an %2)"
    attachHook = "ContextMenu_MultiTow_AttachHook",      -- ... verbraucht Heavy Chain Hook
    detach = "ContextMenu_MultiTow_Detach",              -- "Multi-Tow: Abkuppeln (%1 von %2)"
    detachHook = "ContextMenu_MultiTow_DetachHook",      -- ... Haken zurueck
    attachBar = "ContextMenu_MultiTow_AttachBar",        -- mit Abschleppstange ankuppeln
    detachBar = "ContextMenu_MultiTow_DetachBar",        -- ... Abschleppstange zurueck
}

--- Text in der Spielsprache holen.
--  key   Kurzname aus KEYS (z.B. "attach") oder direkt ein Schluessel
--  arg1  ersetzt %1 im Text (hier: Name des hinteren Fahrzeugs)
--  arg2  ersetzt %2 im Text (hier: Name des vorderen Fahrzeugs)
--  >> WARUM drei Faelle: getText des Spiels mag keine "nil"-Argumente, daher nur so viele uebergeben wie da sind.
function MultiTow.getText(key, arg1, arg2)
    local id = KEYS[key] or key           -- unbekannter Kurzname? dann ist es schon der Schluessel
    if arg2 ~= nil then return getText(id, arg1, arg2) end
    if arg1 ~= nil then return getText(id, arg1) end
    return getText(id)
end
