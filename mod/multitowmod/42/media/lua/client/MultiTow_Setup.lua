--[[==========================================================================
    MultiTow_Setup.lua                                         [ client ]
  ----------------------------------------------------------------------------
    Multi-Vehicle Towing: Einrichtungsassistent

    WAS?    Beim ersten Start der Mod erscheint im Hauptmenue ein Fenster mit
            allen Optionen, aufgeteilt auf Seiten (Allgemein, Gameplay,
            Zug-Anzeige, PKW, LKW). Man blaettert mit Weiter/Zurueck und
            bestaetigt am Ende.
    WOHIN?  Die Werte landen in denselben Optionen wie im Optionsmenue
            (Optionen > DO Utilities > Multi-Vehicle Towing) und werden gespeichert.
    WOHER?  Die Seiten werden aus den Optionen selbst gebaut
            (MultiTow_Options.lua): jeder Titel beginnt eine neue Seite.
            Kommt also eine neue Option dazu, erscheint sie automatisch auch hier.

    WANN erscheint der Assistent?
      - solange die Datei Zomboid/Lua/MultiTow_setup.txt fehlt
        (also beim allerersten Start), oder
      - wenn im Optionsmenue "Einrichtungsassistent beim naechsten Start
        zeigen" angehakt ist.

    ABLAUF
      Hauptmenue betreten --(30 Ticks warten)--> setupWanted? --ja--> openSetup
                                                      |
                                                     nein -> nichts tun
============================================================================]]
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "MultiTow_Common"

-- ####################################################################
-- ##  Masse und Konstanten (alle Angaben in Bildschirm-Pixeln)
-- ####################################################################
local DONE_FILE = "MultiTow_setup.txt"   -- Merkzettel "Assistent schon erledigt" (liegt in Zomboid/Lua/)
local FONT = UIFont.Small
local W = 780         -- Fensterbreite (wird von fitLayout evtl. vergroessert)
local PAD = 16        -- Innenabstand zum Fensterrand
local SPLIT = 360     -- ab hier stehen die Regler
local CTRL_W = 300    -- Breite der Regler (Auswahl, Schieberegler)
local INFO_H = 70     -- Hoehe des grauen Infofelds unten
local WARN_ICON = 32  -- Groesse des Warndreiecks auf der ZombieBuddy-Warnseite
local BULLET_INDENT = 22   -- Einrueckung der Stichpunkte auf der Warnseite
-- Rot der Warnseite:          R     G     B
local RED_TITLE = {          1.0,  0.15, 0.15 }   -- Ueberschrift, kraeftig
local RED_TEXT  = {          1.0,  0.40, 0.40 }   -- Text, etwas heller (besser lesbar auf dunklem Grund)
local ICON_WARN = getTexture("media/ui/MultiTow_Hazard.png")   -- Warndreieck (dasselbe wie im Fahrzeug-Rundmenue)
local NOZB_TEX = getTexture("media/ui/MultiTow_NoZombieBuddy.png")   -- Zombie-Gesicht, rot durchgekreuzt
local NOZB_SIZE = 128     -- so gross wird es rechts oben auf der Warnseite gezeichnet (Datei: 256 x 256)

-- Kleiner Film unten auf der Warnseite (ein Zug faehrt durchs Bild).
--   !! Das Spiel kann keine GIF-Dateien abspielen. Deshalb liegt der Film als einzelne Bilder vor:
--      media/ui/MultiTow_Demo/frame_01.png ... frame_26.png   (je 480 x 201)
--   und wir zeigen sie selbst nacheinander, alle 120 ms das naechste.
--   (Das Original-GIF hat 51 Bilder zu je 60 ms; jedes zweite wurde weggelassen -> halbe Dateigroesse,
--    gleiche Laenge von etwa 3 Sekunden.)
--      Zeit:   0 ms    120 ms  240 ms  ...  3000 ms   3120 ms
--      Bild:   01      02      03      ...  26        01 (von vorne)
local DEMO_PATH = "media/ui/MultiTow_Demo/frame_%02d.png"
local DEMO_FRAMES = 26
local DEMO_MS = 120
local DEMO_W, DEMO_H = 480, 201
-- Bilder werden erst geladen, wenn die Warnseite sie braucht (die meisten Spieler sehen sie nie)
local demoTex = {}

--   Aufbau des Fensters:
--   +--------------------------------------------------------------+
--   | Titel                                                        |
--   | Seite 2 von 5:  Gameplay                                     |
--   |                                                              |
--   |             Beschriftung |  [ Regler ]                       |
--   |             Beschriftung |  [x]                              |
--   |  <------- SPLIT -------->                                    |
--   | +----------------------------------------------------------+ |
--   | | Infofeld: Erklaerung der Option unter der Maus           | |
--   | +----------------------------------------------------------+ |
--   | [Ueberspringen]                     [Zurueck]  [Weiter]      |
--   +--------------------------------------------------------------+

MultiTowSetup = ISPanel:derive("MultiTowSetup")   -- eigene Fensterklasse, abgeleitet vom Standard-Panel

--- Hoehe einer Textzeile in Pixeln.
local function fontHgt(f)
    return getTextManager():getFontHeight(f or FONT)
end

--- Breite eines Textes in Pixeln.
local function textW(s, f)
    return getTextManager():MeasureStringX(f or FONT, s)
end

--- Text auf Zeilen mit hoechstens maxW Pixeln Breite aufteilen (Zeilenumbruch an Leerzeichen).
--   Beispiel:  "Ein sehr langer Satz"  bei schmaler Breite  ->  { "Ein sehr", "langer Satz" }
local function wrap(text, maxW)
    local lines, cur = {}, ""
    for word in string.gmatch(text or "", "%S+") do      -- %S+ = ein Wort (alles ohne Leerzeichen)
        local test = cur == "" and word or (cur .. " " .. word)
        if textW(test) > maxW and cur ~= "" then
            -- Wort passt nicht mehr dazu -> bisherige Zeile abschliessen, Wort beginnt neue Zeile
            table.insert(lines, cur)
            cur = word
        else
            cur = test
        end
    end
    if cur ~= "" then table.insert(lines, cur) end      -- <- letzte angefangene Zeile nicht vergessen
    return lines
end

-- ---------------------------------------------------------------------------
-- Seiten aus den Optionen bauen (ohne Fenster, damit es testbar bleibt)
-- ---------------------------------------------------------------------------
-- Ergebnis: Liste von Seiten { title = Text, image = Pfad oder nil, items = { {kind, option, text} ... } }
--   kind: "option" (Regler/Haken/Auswahl), "key" (Taste, nur Anzeige), "text" (Hinweis)
--
--   Optionsliste (wie im Menue)          ->   Seiten im Assistenten
--   ---------------------------------         -----------------------------
--   description "DOHUB_IMAGE:..."             (Bild merken fuer die naechste Seite)
--   title "Allgemein"                    ->   Seite 1 (mit Bild)
--     tickbox / combobox / slider        ->     kind = "option"
--     keybind                            ->     kind = "key"
--     description                        ->     kind = "text"
--   title "Gameplay"                     ->   Seite 2
--     ...
function MultiTow.setupPages(options)
    local pages, page, pendingImage = {}, nil, nil
    for _, o in ipairs(options.data) do
        if o.type == "title" and o.name == MultiTow.DEBUG_SECTION then
            -- -> Debug-Bereich: KEINE Seite im Assistenten. page = nil -> alles danach wird uebersprungen
            page = nil
            pendingImage = nil
        elseif o.type == "title" then
            -- -> Ein Titel beginnt eine neue Seite
            page = { title = getText(o.name), image = pendingImage, items = {} }
            pendingImage = nil
            table.insert(pages, page)
        elseif o.type == "description" then
            local path = string.match(getText(o.text or ""), "^DOHUB_IMAGE:(.+)$")      -- Kopfbild (ab 0.14.0)
                or string.match(getText(o.text or ""), "^MULTITOW_IMAGE:(.+)$")           -- alte Schreibweise
            local note = string.match(getText(o.text or ""), "^MULTITOW_JAVANOTE:(.+)$")
            if path then
                pendingImage = path -- Kopfbild gehoert zur naechsten Seite (steht im Menue vor dem Titel)
            elseif note then
                -- "rote Optionen brauchen ZombieBuddy": wird nur gezeigt, wenn die Optionen rot sind (createChildren)
                if page then table.insert(page.items, { kind = "javaNote", text = note }) end
            elseif page then
                table.insert(page.items, { kind = "text", text = getText(o.text) })
            end
        elseif page and o.id ~= "showSetup" and o.id ~= "debugZBWarning" then
            -- >> WARUM ohne "showSetup" / "debugZBWarning": die Haken "Assistent wieder zeigen" und
            --    "Debug: Warnung zeigen" im Assistenten selbst anzubieten waere sinnlos
            if o.type == "keybind" then
                table.insert(page.items, { kind = "key", option = o })
            elseif o.type == "tickbox" or o.type == "combobox" or o.type == "slider" then
                table.insert(page.items, { kind = "option", option = o })
            end
        end
    end
    return pages
end

-- ---------------------------------------------------------------------------
-- Warnseite "ZombieBuddy ist nicht aktiv"
-- ---------------------------------------------------------------------------
--   +--------------------------------------------------------------+
--   | /!\  WARNUNG: ZombieBuddy ist nicht aktiv!       (rot, gross) |
--   |      Der Java-Teil wurde nicht geladen ...       (rot)        |
--   |   -  Keine Zuege mit 3 oder mehr Fahrzeugen      (rot)        |
--   |   -  ...                                                     |
--   |      Abhilfe: ZombieBuddy installieren ...       (hellgrau)   |
--   +--------------------------------------------------------------+
--   Erscheint als ERSTE Seite des Assistenten, wenn
--     a) der Java-Teil fehlt (ZombieBuddy laeuft nicht / MultiTowCore.jar nicht erlaubt), oder
--     b) die Debug-Option "debugZBWarning" angehakt ist (zum Ansehen, obwohl alles laeuft).

-- Was ohne ZombieBuddy fehlt: Textschluessel der Stichpunkte (Reihenfolge = Anzeige)
MultiTow.ZB_LOST_KEYS = {
    "UI_MultiTow_SetupZBLost1",   -- keine Zuege ab 3 Fahrzeugen
    "UI_MultiTow_SetupZBLost2",   -- keine starre Abschleppstange
    "UI_MultiTow_SetupZBLost3",   -- keine Zusatzkraft / Zugbremse / Tempolimit
    "UI_MultiTow_SetupZBLost4",   -- keine sichtbaren Ketten, keine Belastungsanzeige
    "UI_MultiTow_SetupZBLost5",   -- kein Verschleiss, keine Warnblinker
    "UI_MultiTow_SetupZBLost6",   -- [MP] Ankuppeln abgeschaltet
}

-- (MultiTow.javaLoaded steht in shared/MultiTow_Common.lua)

--- Soll die Warnseite erscheinen?  (Java fehlt  ODER  Debug-Haken gesetzt)
function MultiTow.setupWarningWanted(options)
    if not MultiTow.javaLoaded() then return true end
    local dbg = options and options:getOption("debugZBWarning")
    return dbg ~= nil and dbg:getValue() == true
end

--- Die Warnseite als Seite im selben Format wie setupPages (nur mit eigenen Eintrags-Arten).
--   kind: "warnTitle" (rot, gross, mit Warndreieck) | "warn" (rot) | "warnBullet" (rot, Stichpunkt) | "text" (Hinweis)
function MultiTow.setupWarningPage()
    -- Sonderfall "Java-Teil geladen, aber erst nach Neustart aktiv": eigene Ueberschrift, Einleitung und Abhilfe
    local restart = MultiTow.javaRestartNeeded()
    local items = {
        { kind = "warnTitle", text = getText(restart and "UI_MultiTow_SetupRestartTitle" or "UI_MultiTow_SetupZBTitle") },
        { kind = "warn", text = getText(restart and "UI_MultiTow_SetupRestartIntro" or "UI_MultiTow_SetupZBIntro") },
    }
    for _, key in ipairs(MultiTow.ZB_LOST_KEYS) do
        table.insert(items, { kind = "warnBullet", text = getText(key) })
    end
    table.insert(items, { kind = "text", text = getText(restart and "UI_MultiTow_SetupRestartFix" or "UI_MultiTow_SetupZBFix") })
    table.insert(items, { kind = "demo" })   -- der kleine Film ganz unten
    return { title = getText(restart and "UI_MultiTow_SetupRestartPage" or "UI_MultiTow_SetupZBPage"), warning = true, items = items }
end

--- Debug-Haken wieder ausschalten (nach Fertig / Ueberspringen - wie "showSetup").
local function clearDebugWarning(options)
    local dbg = options and options:getOption("debugZBWarning")
    if dbg then dbg:setValue(false) end
end

--- Gewaehlte Werte in die Optionen schreiben, speichern und anwenden.
--   values = { [Options-ID] = Wert, ... }
--   -> 1. jeden Wert in seine Option schreiben
--   -> 2. "Assistent wieder zeigen" ausschalten
--   -> 3. alles speichern (Datei der Mod-Optionen)
--   -> 4. Einstellungen sofort anwenden (MultiTow.Settings neu fuellen)
--   -> 5. Merkzettel-Datei anlegen
function MultiTow.setupCommit(options, values)
    for id, v in pairs(values) do
        local o = options:getOption(id)
        if o and o.setValue then o:setValue(v) end
    end
    local again = options:getOption("showSetup")
    if again then again:setValue(false) end
    clearDebugWarning(options)
    pcall(function() PZAPI.ModOptions:save() end)
    if options.apply then pcall(options.apply, options) end
    MultiTow.setupMarkDone()
end

--- Merkzettel-Datei schreiben: "Assistent erledigt".
--   !! ACHTUNG: alles in pcall - ein Schreibfehler (z.B. keine Rechte) darf das Hauptmenue nicht kaputt machen.
function MultiTow.setupMarkDone()
    pcall(function()
        local f = getFileWriter(DONE_FILE, true, false)   -- true = Datei anlegen, false = nicht anhaengen
        f:write("done")
        f:close()
    end)
end

--- Gibt es die Merkzettel-Datei schon?  (true = Assistent wurde schon einmal beendet/uebersprungen)
function MultiTow.setupIsDone()
    local done = false
    pcall(function()
        local f = getFileReader(DONE_FILE, false)   -- false = NICHT anlegen, wenn sie fehlt
        if f then
            done = true
            f:close()
        end
    end)
    return done
end

--- Soll der Assistent jetzt erscheinen?
--     Haken "wieder zeigen" gesetzt  -> ja
--     Debug-Haken "Warnung zeigen"   -> ja
--     sonst                          -> nur wenn die Merkzettel-Datei fehlt
function MultiTow.setupWanted(options)
    local again = options and options:getOption("showSetup")
    if again and again:getValue() then return true end
    local dbg = options and options:getOption("debugZBWarning")
    if dbg and dbg:getValue() then return true end
    return not MultiTow.setupIsDone()
end

-- ---------------------------------------------------------------------------
-- Fenster
-- ---------------------------------------------------------------------------
-- Spalten so breit wie die laengste Beschriftung (sonst ragt z.B. "Require Heavy Chain Hook..." links aus dem Fenster)
--   Beschriftungen stehen RECHTSBUENDIG vor SPLIT. Ist eine laenger als SPLIT,
--   beginnt sie links ausserhalb des Fensters -> deshalb SPLIT passend vergroessern.
local function fitLayout(pages)
    local labelW = 0
    for _, page in ipairs(pages) do
        for _, it in ipairs(page.items) do
            if it.option then labelW = math.max(labelW, textW(getText(it.option.name))) end
        end
    end
    SPLIT = math.max(360, PAD + labelW + 24)            -- mindestens 360
    W = math.max(780, SPLIT + CTRL_W + PAD + 8)         -- mindestens 780
    -- nie breiter als der Bildschirm
    W = math.min(W, getCore():getScreenWidth() - 20)
end

--- Fenster anlegen (noch ohne Inhalt - der kommt in createChildren).
function MultiTowSetup:new(options)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local pages = MultiTow.setupPages(options)
    fitLayout(pages)
    -- Warnseite (falls noetig) VOR alle anderen Seiten setzen; die Begruessung rutscht dann auf Seite 2
    local welcomeIndex = 1
    if MultiTow.setupWarningWanted(options) then
        table.insert(pages, 1, MultiTow.setupWarningPage())
        welcomeIndex = 2
    end
    local o = ISPanel.new(self, 0, 0, W, 400)   -- Hoehe 400 ist vorlaeufig, wird in createChildren angepasst
    o.options = options
    o.welcomeIndex = welcomeIndex                -- auf welcher Seite die Begruessung steht
    -- Optionen, die den Java-Teil brauchen, rot zeigen? (wie im Optionsmenue)
    if MultiTow.javaMarksWanted then o.javaMarks = MultiTow.javaMarksWanted() else o.javaMarks = not MultiTow.javaLoaded() end
    o.pages = pages
    o.pageIndex = 1
    o.rows = {}      -- pro Seite: Liste { y, h, label, tooltip, control, kind, option, valueLabel }
    o.backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.95 }
    o.borderColor = { r = 0.5, g = 0.5, b = 0.5, a = 1 }
    o.moveWithMouse = true                       -- Fenster mit der Maus verschiebbar
    o.screenW, o.screenH = sw, sh
    return o
end

-- aktueller Wert eines Reglers im Fenster (fuer die Regeln und zum Speichern)
--   | Typ       | Wert                         |
--   |-----------|------------------------------|
--   | tickbox   | true / false                 |
--   | combobox  | Nummer des Eintrags (ab 1)   |
--   | slider    | Zahl                         |
function MultiTowSetup:valueOf(row)
    local c = row.control
    if row.option.type == "tickbox" then return c:isSelected(1) end
    if row.option.type == "combobox" then return c.selected end
    if row.option.type == "slider" then return c:getCurrentValue() end
    return nil
end

--- Zeile zu einer Options-ID suchen (auf ALLEN Seiten, nicht nur der sichtbaren).
function MultiTowSetup:findRow(id)
    for _, rows in ipairs(self.rows) do
        for _, r in ipairs(rows) do
            if r.option and r.option.id == id then return r end
        end
    end
    return nil
end

-- ####################################################################
-- ##  Inhalt bauen
-- ####################################################################
-- Alle Seiten werden EINMAL komplett gebaut; Regler der unsichtbaren Seiten
-- sind nur versteckt (setVisible(false)). Blaettern = sichtbar/unsichtbar schalten.
--   >> WARUM so: die gewaehlten Werte bleiben beim Zurueckblaettern erhalten,
--      und die Fensterhoehe passt fuer die laengste Seite.
function MultiTowSetup:createChildren()
    ISPanel.createChildren(self)
    local lh = math.max(fontHgt() + 8, 24)                                -- Zeilenhoehe einer Option
    local top = PAD + fontHgt(UIFont.Medium) + 10 + fontHgt() + 10        -- unter Titel + Seitenzeile
    local maxBottom = 0                                                   -- unterster Punkt aller Seiten

    for pi, page in ipairs(self.pages) do
        local rows = {}
        local y = top
        if pi == self.welcomeIndex then
            -- Begruessung auf der ersten normalen Seite (Seite 1, oder Seite 2 hinter der Warnseite)
            for _, line in ipairs(wrap(getText("UI_MultiTow_SetupWelcome"), W - PAD * 2)) do
                table.insert(rows, { kind = "plain", y = y, h = fontHgt(), label = line })
                y = y + fontHgt() + 2
            end
            y = y + 8
        end
        if page.image then
            -- Kopfbild ueber die ganze Breite, Seitenverhaeltnis 640 x 120
            local tex = getTexture(page.image)
            if tex then
                local iw = W - PAD * 2
                local ih = math.floor(iw * 120 / 640)
                local img = ISImage:new(PAD, y, iw, ih, tex)
                img.autoScale = true
                img:initialise()
                img:setVisible(false)
                self:addChild(img)
                table.insert(rows, { kind = "image", y = y, h = ih, control = img })
                y = y + ih + 8
            end
        end
        -- Breite fuer Text. Auf der Warnseite steht rechts oben das durchgekreuzte Zombie-Bild,
        -- deshalb bricht der Text dort frueher um:
        --   | /!\ WARNUNG ...              +--------+ |
        --   | Der Java-Teil ...            | Zombie | |
        --   |  - Keine Zuege ...           |   X    | |
        --   |  - ...                       +--------+ |
        --   |<------- textMax ------->|16|<-NOZB_SIZE->|
        local textMax = W - PAD * 2
        local imageBottom = 0
        if page.warning then
            table.insert(rows, { kind = "warnImage", y = y, h = NOZB_SIZE })
            textMax = W - PAD * 2 - NOZB_SIZE - 16
            imageBottom = y + NOZB_SIZE
        end
        for _, it in ipairs(page.items) do
            if it.kind == "warnTitle" then
                -- [warnTitle] grosse rote Ueberschrift, links davon das Warndreieck
                local th = math.max(fontHgt(UIFont.Large), WARN_ICON)
                table.insert(rows, { kind = "warnTitle", y = y, h = th, label = it.text })
                y = y + th + 10
            elseif it.kind == "warn" then
                -- [warn] roter Fliesstext
                for _, line in ipairs(wrap(it.text, textMax)) do
                    table.insert(rows, { kind = "warn", y = y, h = fontHgt(), label = line })
                    y = y + fontHgt() + 2
                end
                y = y + 6
            elseif it.kind == "warnBullet" then
                -- [warnBullet] roter Stichpunkt; Folgezeilen eingerueckt unter dem Text, nicht unter dem Strich
                --    -  Erste Zeile des Stichpunkts
                --       zweite Zeile beginnt hier
                for li, line in ipairs(wrap(it.text, textMax - BULLET_INDENT)) do
                    table.insert(rows, { kind = "warnBullet", y = y, h = fontHgt(), label = line, first = (li == 1) })
                    y = y + fontHgt() + 2
                end
                y = y + 2
            elseif it.kind == "javaNote" then
                -- [javaNote] roter Hinweis, nur wenn die Java-Optionen rot markiert sind
                if self.javaMarks then
                    for _, line in ipairs(wrap(it.text, textMax)) do
                        table.insert(rows, { kind = "warn", y = y, h = fontHgt(), label = line })
                        y = y + fontHgt() + 2
                    end
                    y = y + 6
                end
            elseif it.kind == "demo" then
                -- [demo] Film, waagerecht in der Fenstermitte; unter dem Zombie-Bild, deshalb volle Breite moeglich
                y = math.max(y, imageBottom) + 4
                table.insert(rows, { kind = "demo", y = y, h = DEMO_H })
                y = y + DEMO_H + 6
            elseif it.kind == "text" then
                -- [text] Hinweistext, grau, mit Zeilenumbruch
                if rows[#rows] and rows[#rows].kind == "warnBullet" then y = y + 8 end   -- <- Luft nach den Stichpunkten
                for _, line in ipairs(wrap(it.text, textMax)) do
                    table.insert(rows, { kind = "hint", y = y, h = fontHgt(), label = line })
                    y = y + fontHgt() + 2
                end
                y = y + 6
            elseif it.kind == "key" then
                -- [key] Taste wird nur ANGEZEIGT (aendern geht im normalen Optionsmenue)
                local o = it.option
                table.insert(rows, { kind = "key", y = y, h = lh, option = o, label = getText(o.name),
                    needsJava = MultiTow.JAVA_OPTIONS and MultiTow.JAVA_OPTIONS[o.id] or false,
                    tooltip = o.tooltip and getText(o.tooltip),
                    value = getKeyName(tonumber(o.key) or 0) .. "   (" .. getText("UI_MultiTow_SetupKeyHint") .. ")" })
                y = y + lh
            else
                -- [option] passendes Bedienelement anlegen
                local o = it.option
                local row = { kind = "option", y = y, h = lh, option = o, label = getText(o.name),
                    tooltip = o.tooltip and getText(o.tooltip),
                    needsJava = MultiTow.JAVA_OPTIONS and MultiTow.JAVA_OPTIONS[o.id] or false }
                local cy = y + math.floor((lh - 20) / 2)     -- 20 px hohes Element mittig in der Zeile
                if o.type == "tickbox" then
                    local tb = ISTickBox:new(SPLIT, cy, 20, 20, "", nil, nil)
                    tb.choicesColor = { r = 1, g = 1, b = 1, a = 1 }
                    tb:initialise()
                    tb:addOption("")                          -- ein einzelnes Kaestchen ohne eigenen Text
                    tb:setSelected(1, o.value and true or false)
                    row.control = tb
                elseif o.type == "combobox" then
                    local cb = ISComboBox:new(SPLIT, y + 2, CTRL_W, lh - 4, nil, nil)
                    cb:initialise()
                    for _, v in ipairs(o.values) do cb:addOption(v) end
                    cb.selected = o.selected or 1
                    row.control = cb
                elseif o.type == "slider" then
                    local sl = ISSliderPanel:new(SPLIT, y + 2, CTRL_W - 60, lh - 4)   -- 60 px Platz fuer die Zahl
                    sl:initialise()
                    sl:setValues(o.min, o.max, o.step, o.step * 10)
                    sl:setCurrentValue(o.value, true)
                    row.control = sl
                    row.valueX = SPLIT + CTRL_W - 50            -- <- hier wird die Zahl gezeichnet (render)
                end
                row.control:setVisible(false)                   -- erst showPage macht die richtige Seite sichtbar
                self:addChild(row.control)
                table.insert(rows, row)
                y = y + lh
            end
        end
        maxBottom = math.max(maxBottom, y, imageBottom)   -- <- das Bild darf nicht ins Infofeld ragen
        self.rows[pi] = rows
    end

    -- Infofeld (Erklaerung der Option unter der Maus) und Knoepfe
    self.infoY = maxBottom + 10
    local by = self.infoY + INFO_H + 12          -- y der Knopfreihe
    local bh = math.max(fontHgt() + 10, 28)      -- Knopfhoehe
    self:setHeight(by + bh + PAD)
    -- Fenster in der Bildschirmmitte
    self:setX(math.floor((self.screenW - W) / 2))
    self:setY(math.max(0, math.floor((self.screenH - self.height) / 2)))

    --   [Ueberspringen] ................... [Zurueck] [Weiter]
    --    links                                rechts, je 140 px
    self.skipBtn = ISButton:new(PAD, by, 200, bh, getText("UI_MultiTow_SetupSkip"), self, MultiTowSetup.onSkip)
    self.backBtn = ISButton:new(W - PAD - 2 * 140 - 10, by, 140, bh, getText("UI_MultiTow_SetupBack"), self, MultiTowSetup.onBack)
    self.nextBtn = ISButton:new(W - PAD - 140, by, 140, bh, getText("UI_MultiTow_SetupNext"), self, MultiTowSetup.onNext)
    for _, b in ipairs({ self.skipBtn, self.backBtn, self.nextBtn }) do
        b:initialise()
        b:instantiate()
        self:addChild(b)
    end
    self.skipBtn:setWidth(math.max(200, textW(getText("UI_MultiTow_SetupSkip")) + 20))   -- langer Text (z.B. Deutsch)
    self:showPage(1)
end

--- Seite i anzeigen: Regler dieser Seite sichtbar, alle anderen versteckt.
function MultiTowSetup:showPage(i)
    self.pageIndex = math.max(1, math.min(#self.pages, i))   -- auf 1 .. Seitenanzahl begrenzen
    for pi, rows in ipairs(self.rows) do
        for _, r in ipairs(rows) do
            if r.control then r.control:setVisible(pi == self.pageIndex) end
        end
    end
    self.backBtn:setEnable(self.pageIndex > 1)               -- auf Seite 1 gibt es kein Zurueck
    local last = self.pageIndex == #self.pages
    -- auf der letzten Seite heisst "Weiter" -> "Fertig"
    self.nextBtn:setTitle(getText(last and "UI_MultiTow_SetupFinish" or "UI_MultiTow_SetupNext"))
end

function MultiTowSetup:onBack()
    self:showPage(self.pageIndex - 1)
end

--- Knopf "Weiter" bzw. auf der letzten Seite "Fertig".
function MultiTowSetup:onNext()
    if self.pageIndex < #self.pages then
        self:showPage(self.pageIndex + 1)
        return
    end
    -- letzte Seite: alles uebernehmen
    --   Werte von ALLEN Seiten einsammeln, nicht nur von der sichtbaren
    local values = {}
    for _, rows in ipairs(self.rows) do
        for _, r in ipairs(rows) do
            if r.kind == "option" then values[r.option.id] = self:valueOf(r) end
        end
    end
    MultiTow.setupCommit(self.options, values)
    MultiTow.log("Setup assistant finished")
    self:close()
end

-- Ueberspringen: Werte bleiben wie sie sind, Assistent kommt nicht wieder
function MultiTowSetup:onSkip()
    local again = self.options:getOption("showSetup")
    if again then again:setValue(false) end
    clearDebugWarning(self.options)
    pcall(function() PZAPI.ModOptions:save() end)
    MultiTow.setupMarkDone()
    MultiTow.log("Setup assistant skipped")
    self:close()
end

--- Fenster UND den dunklen Hintergrund entfernen.
function MultiTowSetup:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if self.cover then
        self.cover:setVisible(false)
        self.cover:removeFromUIManager()
    end
    MultiTow.setupWindow = nil      -- <- damit openSetup spaeter wieder ein Fenster oeffnen darf
end

-- Regeln (z.B. nur der Tempo-Regler der gewaehlten Einheit) und Wertanzeige der Schieberegler
--   Laeuft jedes Bild. Die Regeln selbst stehen in MultiTow_Options.lua (MultiTow.optionEnabled).
--   >> WARUM eigenes "get": die Regel soll die Werte IM FENSTER sehen (noch nicht gespeichert),
--      nicht die alten Werte aus den Optionen.
function MultiTowSetup:update()
    ISPanel.update(self)
    local get = function(id)
        local r = self:findRow(id)
        if r then return self:valueOf(r) end          -- Wert aus dem Fenster
        local o = self.options:getOption(id)
        return o and o:getValue()                     -- sonst gespeicherter Wert
    end
    for _, r in ipairs(self.rows[self.pageIndex] or {}) do
        if r.kind == "option" and MultiTow.optionEnabled then
            local on = MultiTow.optionEnabled(r.option.id, get)
            r.disabled = not on                       -- render zeichnet die Beschriftung dann grau
            if r.option.type == "tickbox" then
                pcall(function() r.control:disableOption("", not on) end)
            else
                r.control.disabled = not on
            end
        end
    end
end

-- ####################################################################
-- ##  Zeichnen (jedes Bild)
-- ####################################################################
function MultiTowSetup:render()
    ISPanel.render(self)
    local page = self.pages[self.pageIndex]
    if not page then return end
    -- Kopf: Titel und Seitenzahl
    self:drawText(getText("UI_MultiTow_SetupTitle"), PAD, PAD, 1, 0.85, 0.4, 1, UIFont.Medium)   -- goldgelb
    local sub = getText("UI_MultiTow_SetupPage", tostring(self.pageIndex), tostring(#self.pages)) .. ":  " .. page.title
    if page.warning then
        self:drawText(sub, PAD, PAD + fontHgt(UIFont.Medium) + 6, RED_TEXT[1], RED_TEXT[2], RED_TEXT[3], 1, FONT)   -- Warnseite: rot
    else
        self:drawText(sub, PAD, PAD + fontHgt(UIFont.Medium) + 6, 1, 1, 1, 1, FONT)
    end

    local mx, my = self:getMouseX(), self:getMouseY()
    local hover = nil                       -- Zeile unter der Maus (fuer das Infofeld)
    if page.warning then
        -- Warnseite: doppelter roter Rahmen ums ganze Fenster
        self:drawRectBorder(1, 1, self.width - 2, self.height - 2, 1, RED_TITLE[1], RED_TITLE[2], RED_TITLE[3])
        self:drawRectBorder(2, 2, self.width - 4, self.height - 4, 1, RED_TITLE[1], RED_TITLE[2], RED_TITLE[3])
    end
    for _, r in ipairs(self.rows[self.pageIndex] or {}) do
        if r.kind == "demo" then
            -- welches Bild gerade dran ist, ergibt sich aus der Uhrzeit (laeuft so immer gleich schnell,
            -- egal wie viele Bilder pro Sekunde das Spiel zeichnet)
            local n = math.floor(getTimestampMs() / DEMO_MS) % DEMO_FRAMES + 1
            demoTex[n] = demoTex[n] or getTexture(string.format(DEMO_PATH, n))
            local x = math.floor((self.width - DEMO_W) / 2)
            if demoTex[n] then
                self:drawTextureScaled(demoTex[n], x, r.y, DEMO_W, DEMO_H, 1, 1, 1, 1)
            end
            self:drawRectBorder(x - 1, r.y - 1, DEMO_W + 2, DEMO_H + 2, 1, 0.45, 0.45, 0.45)   -- duenner grauer Rahmen
        elseif r.kind == "warnImage" then
            -- durchgekreuztes Zombie-Bild rechts oben
            if NOZB_TEX then
                self:drawTextureScaled(NOZB_TEX, self.width - PAD - NOZB_SIZE, r.y, NOZB_SIZE, NOZB_SIZE, 1, 1, 1, 1)
            end
        elseif r.kind == "warnTitle" then
            -- Warndreieck links, Ueberschrift daneben, senkrecht mittig
            local tx = PAD
            if ICON_WARN then
                self:drawTextureScaled(ICON_WARN, PAD, r.y + math.floor((r.h - WARN_ICON) / 2), WARN_ICON, WARN_ICON, 1, 1, 1, 1)
                tx = PAD + WARN_ICON + 10
            end
            local ty = r.y + math.floor((r.h - fontHgt(UIFont.Large)) / 2)
            self:drawText(r.label, tx, ty, RED_TITLE[1], RED_TITLE[2], RED_TITLE[3], 1, UIFont.Large)
        elseif r.kind == "warn" then
            self:drawText(r.label, PAD, r.y, RED_TEXT[1], RED_TEXT[2], RED_TEXT[3], 1, FONT)
        elseif r.kind == "warnBullet" then
            if r.first then
                self:drawText("-", PAD + 6, r.y, RED_TITLE[1], RED_TITLE[2], RED_TITLE[3], 1, FONT)   -- Stichpunkt-Strich
            end
            self:drawText(r.label, PAD + BULLET_INDENT, r.y, RED_TEXT[1], RED_TEXT[2], RED_TEXT[3], 1, FONT)
        elseif r.kind == "plain" then
            self:drawText(r.label, PAD, r.y, 0.9, 0.9, 0.9, 1, FONT)        -- Begruessung: hellgrau
        elseif r.kind == "hint" then
            self:drawText(r.label, PAD, r.y, 0.65, 0.65, 0.65, 1, FONT)     -- Hinweis: dunkler grau
        elseif r.kind == "option" or r.kind == "key" then
            local ty = r.y + math.floor((r.h - fontHgt()) / 2)              -- Text senkrecht mittig
            if my >= r.y and my < r.y + r.h and mx >= 0 and mx < self.width then
                hover = r
                self:drawRect(PAD - 6, r.y, self.width - 2 * PAD + 12, r.h, 0.08, 1, 1, 1)   -- leichte Hervorhebung
            end
            local a = r.disabled and 0.45 or 1                              -- abgeschaltet = grau
            if r.needsJava and self.javaMarks then
                -- braucht den Java-Teil, der fehlt: rot (abgeschaltet: dunkleres Rot)
                self:drawTextRight(r.label, SPLIT - 16, ty, a, RED_TEXT[2] * a, RED_TEXT[3] * a, 1, FONT)
            else
                self:drawTextRight(r.label, SPLIT - 16, ty, a, a, a, 1, FONT)
            end
            if r.kind == "key" then
                self:drawText(r.value, SPLIT, ty, 0.8, 0.8, 0.8, 1, FONT)
            elseif r.valueX then
                self:drawText(tostring(r.control:getCurrentValue()), r.valueX, ty, a, a, a, 1, FONT)
            end
        end
    end

    -- Infofeld
    self:drawRect(PAD, self.infoY, self.width - 2 * PAD, INFO_H, 0.5, 0.12, 0.12, 0.12)
    self:drawRectBorder(PAD, self.infoY, self.width - 2 * PAD, INFO_H, 0.6, 0.4, 0.4, 0.4)
    local info = hover and hover.tooltip or getText("UI_MultiTow_SetupInfo")   -- ohne Maus: allgemeiner Hinweis
    local iy = self.infoY + 6
    for i, line in ipairs(wrap(info, self.width - 2 * PAD - 16)) do
        if iy + fontHgt() > self.infoY + INFO_H then break end   -- !! nur so viele Zeilen wie ins Feld passen
        self:drawText(line, PAD + 8, iy, 0.85, 0.85, 0.85, 1, FONT)
        iy = iy + fontHgt() + 1
    end
end

-- Fenster oeffnen (mit abgedunkeltem Hintergrund, damit man nicht aus Versehen ins Hauptmenue klickt)
--   Ebenen von hinten nach vorne:   Hauptmenue  <  cover (60 % schwarz)  <  Assistent
function MultiTow.openSetup()
    if MultiTow.setupWindow then return end          -- schon offen -> kein zweites Fenster
    local options = PZAPI and PZAPI.ModOptions and PZAPI.ModOptions:getOptions(MultiTow.OPTIONS_ID or "MultiTowRoadTrain")
    if not options then return end
    -- gespeicherte Werte laden (sonst zeigt der Assistent die Standardwerte statt der eigenen)
    pcall(function() PZAPI.ModOptions:load() end)
    -- fuer die Fehlersuche: hat der Assistent den Java-Teil gefunden?
    MultiTow.log("Setup assistant: Java part loaded =", tostring(MultiTow.javaLoaded()),
        "| warning page =", tostring(MultiTow.setupWarningWanted(options)))
    local cover = ISPanel:new(0, 0, getCore():getScreenWidth(), getCore():getScreenHeight())
    cover.backgroundColor = { r = 0, g = 0, b = 0, a = 0.6 }
    cover.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    cover:initialise()
    cover:addToUIManager()
    local win = MultiTowSetup:new(options)
    win:initialise()
    win:instantiate()
    win.cover = cover
    win:addToUIManager()
    win:setAlwaysOnTop(true)
    win:bringToTop()
    MultiTow.setupWindow = win
end

-- ####################################################################
-- ##  Automatischer Start im Hauptmenue
-- ####################################################################
-- Beim Betreten des Hauptmenues pruefen (kurz warten, bis das Hauptmenue fertig aufgebaut ist)
--   waitTicks:  -1 = nichts zu tun  |  > 0 = herunterzaehlen  |  0 = jetzt pruefen
local waitTicks = -1
Events.OnMainMenuEnter.Add(function()
    waitTicks = 30
end)
-- Im Hauptmenue laeuft OnFETick (OnTick gibt es erst im Spiel)
Events.OnFETick.Add(function()
    if waitTicks < 0 then return end
    waitTicks = waitTicks - 1
    if waitTicks > 0 then return end
    waitTicks = -1
    if MainScreen and MainScreen.instance and MainScreen.instance.inGame then return end   -- Pausenmenue im Spiel -> nicht
    local options = PZAPI and PZAPI.ModOptions and PZAPI.ModOptions:getOptions(MultiTow.OPTIONS_ID or "MultiTowRoadTrain")
    if not options then return end
    pcall(function() PZAPI.ModOptions:load() end)
    if MultiTow.setupWanted(options) then
        MultiTow.log("Showing setup assistant")
        MultiTow.openSetup()
    end
end)
