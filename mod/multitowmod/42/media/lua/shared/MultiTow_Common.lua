MultiTow = MultiTow or {}   -- globale Tabelle der Mod ("or {}": nicht ueberschreiben, falls schon vorhanden)

--[[==========================================================================
    MultiTow_Common.lua                                        [ shared ]
  ----------------------------------------------------------------------------
    WAS?    Gemeinsame Funktionen fuer Client, Server und Einzelspieler
            (frueher client/MultiTow_Utils.lua).
    WARUM?  Liegt in "shared", weil der Server im Multiplayer dieselben
            Regeln (Zuglaenge, Haken) pruefen muss.

    INHALT (Kapitel in dieser Datei)
      1. Einstellungen (Standardwerte)        6. Multiplayer + Sandbox-Regeln
      2. Logdatei                             7. Ankuppeln (doAttach)
      3. Kupplungspunkte + Abstaende          8. Zustand / Verschleiss
      4. Zug: Laenge, Kopf, LKW/PKW           9. Gewicht (Fahrzeug + Ladung)
      5. Gegenstaende (Haken, Stange)        10. Reissen + Stangen-Regel

    LEGENDE DER KOMMENTARE (in allen Dateien der Mod)
      --[[====        Kopfkasten einer Datei (Block-Kommentar mit = Linien)
      -- #### ...     grosses Kapitel
      -- ---- ...     Abschnitt
      --- Text        Beschreibung der folgenden Funktion
      -- >> WARUM     Begruendung einer Entscheidung
      -- !! ACHTUNG   Stolperfalle - hier vorsichtig sein
      -- -> 1. 2. 3.  Ablauf in Schritten
      -- [SP] [MP]    gilt nur fuer Einzelspieler / Multiplayer
      ... -- <-       Hinweis am Zeilenende
============================================================================]]

-- ####################################################################
-- ##  1. Einstellungen
-- ####################################################################
-- Einstellungen aus dem Optionsmenue (MultiTow_Options.lua setzt sie). Standard: Mod an, Zuglaenge unbegrenzt.
--   [SP] Werte kommen aus dem Optionsmenue
--   [MP] Regel-Werte kommen aus den Sandbox-Optionen des Servers (applySandbox, Kapitel 6),
--        persoenliche Werte (Anzeige, Warnblinker-Stil, Toene) weiter aus dem Optionsmenue
MultiTow.Settings = MultiTow.Settings or {
    enabled = true, requireHook = false, sounds = true, maxCar = 0, maxTruck = 0,
    -- Zug: Bremse in Prozent, Tempolimit im gewaehlten Mass (0 = aus), Spritverbrauch, Laerm
    speedUnit = "kmh",
    brakeCar = 50, brakeTruck = 50,
    speedCar = 0, speedTruck = 0,
    fuelModeCar = 1, fuelModeTruck = 1,       -- 1 = aus, 2 = gleichmaessig, 3 = exponentiell
    fuelPctCar = 20, fuelPctTruck = 20,       -- Mehrverbrauch in Prozent pro zusaetzlichem Fahrzeug
    noiseCar = true, noiseTruck = true,
    -- Gameplay: Verschleiss der Verbindungen (Auswahl 1..5) und wie viel Ladungsgewicht zaehlt (Auswahl 1..5)
    wear = 3, cargo = 5,
    -- Warnblinker: automatisch beim Ankuppeln (Regel), Stil 1 aus / 2 amerikanisch / 3 europaeisch, Umfang 1 letztes / 2 alle
    hazardAuto = true, hazardStyle = 3, hazardScope = 1,
    -- Zug-Anzeige (persoenlich): an/aus, Position (Auswahl 1..9), welche Zeilen
    hud = true, hudPos = 2,
    hudCount = true, hudSpeed = true, hudStress = true, hudCond = true, hudWeight = true, hudFuel = true,
}

-- ####################################################################
-- ##  1b. Mit oder ohne Java-Teil (ZombieBuddy)?
-- ####################################################################
--   ZombieBuddy ist FREIWILLIG. Ohne ihn laeuft die Mod im Basis-Modus:
--
--   +-----------------------------+------------------+-------------------+
--   |                             | mit ZombieBuddy  | ohne (Basis-Modus) |
--   +-----------------------------+------------------+-------------------+
--   | Zuege ab 3 Fahrzeugen       |       ja         |  nein              |
--   | Abschleppen mit 2 Fahrzeugen|  ja (+ Stange)   |  ja, wie im Spiel  |
--   | Ladungsgewicht, Sprit, Laerm|       ja         |  ja                |
--   | Zug-Anzeige                 |       ja         |  ja (ohne Belastung)|
--   | Verschleiss, Warnblinker,   |       ja         |  nein              |
--   | Ketten sichtbar, Toene ...  |                  |                    |
--   +-----------------------------+------------------+-------------------+

--- Hat ZombieBuddy den Java-Teil geladen?
--   multiTowCoreVersion gibt es NUR, wenn ZombieBuddy MultiTowCore.jar geladen hat.
--   >> WARUM nicht "(inactive)" pruefen: das steht auch da, wenn man die Mod im Optionsmenue
--      ausschaltet - das ist kein fehlendes ZombieBuddy.
function MultiTow.javaLoaded()
    return multiTowCoreVersion ~= nil
end

--- Java-Teil geladen, aber fuer Lua noch nicht erreichbar -> Spiel neu starten?
--   Passiert, wenn man MultiTow im Mod-Menue einschaltet, waehrend das Spiel laeuft: ZombieBuddy laedt
--   MultiTowCore.jar dann nach, das Spiel laedt aber nur die Lua-Dateien neu. Die Funktionen des Java-Teils
--   (multiTowCoreVersion usw.) gibt es fuer Lua erst nach einem Neustart des Spiels.
--   Wir fragen ZombieBuddy, ob es den Java-Teil in diesem Lauf geladen hat. Kennt ZombieBuddy die Frage
--   nicht (alte Version), kommt false heraus - dann bleibt es beim normalen Hinweis "ZombieBuddy fehlt".
function MultiTow.javaRestartNeeded()
    if MultiTow.javaLoaded() or ZombieBuddy == nil then return false end
    -- !! Alte ZombieBuddy-Versionen kennen getJavaModStatus nicht. Den Aufruf von nil schreibt das Spiel auch
    --    innerhalb von pcall als "Lua error" ins Log (gemeldet in einem Fehlerbericht) - darum vorher pruefen.
    if ZombieBuddy.getJavaModStatus == nil then return false end
    local ok, loaded = pcall(function()
        for _, id in ipairs({ "MultiTowRoadTrain", "multitow" }) do   -- Mod-ID oder Java-Paketname (javaPkgName)
            local st = ZombieBuddy.getJavaModStatus(id)
            if st ~= nil and st.loaded == true then return true end
        end
        return false
    end)
    return ok and loaded == true
end

-- Optionen, die OHNE Java-Teil nichts bewirken. Im Optionsmenue und im Einrichtungsassistenten
-- werden sie rot geschrieben, wenn der Java-Teil fehlt (MultiTow_Options.lua / MultiTow_Setup.lua).
--   !! ACHTUNG: Kommt eine neue Option dazu, die den Java-Teil braucht, hier eintragen.
MultiTow.JAVA_OPTIONS = {}
for _, id in ipairs({
    -- Allgemein
    "requireHook",                       -- Haken: erst ab 3 Fahrzeugen
    "sounds", "remarks",                 -- kommen ueber Ereignisse des Java-Teils
    "showChains",                        -- zeichnet der Java-Teil
    "hazardStyle", "hazardScope",        -- Takt und Fahrzeugliste aus dem Java-Teil
    "showLinks", "linkKey", "linkKeyMode", "showLinksNear",   -- Belastungs-Baender
    "speedUnit",                         -- nur fuer das Tempolimit (Java)
    -- Gameplay
    "wear", "hazardAuto", "assistPower",
    -- Zug-Anzeige
    "hudStress", "hudCond",              -- Belastung / Zustand gibt es nur mit Verschleiss
    -- Debug
    "debugHostServerJava",               -- startet ZombieBuddy auf dem Host-Server (macht der Java-Teil)
}) do MultiTow.JAVA_OPTIONS[id] = true end
for _, suffix in ipairs({ "Car", "Truck" }) do
    for _, id in ipairs({ "maxVehicles", "boostMode", "brake", "speedKmh", "speedMph" }) do
        MultiTow.JAVA_OPTIONS[id .. suffix] = true
    end
end

-- Verschleiss: Auswahl -> Faktor (Aus, Niedrig, Normal, Hoch, Sehr hoch)
--   Auswahl:   1     2      3      4      5
--   Faktor:    0    0.5    1.0    2.0    4.0
MultiTow.WEAR_FACTORS = { 0, 0.5, 1.0, 2.0, 4.0 }
-- Ladungsgewicht: Auswahl -> Prozent (Aus = Spiel rechnet wie immer, sonst 25/50/75/100 %)
--   !! ACHTUNG: Eintrag 1 ist nil -> bedeutet "Mod mischt sich nicht ein" (siehe trainMassOf)
MultiTow.CARGO_PCT = { nil, 25, 50, 75, 100 }

-- ####################################################################
-- ##  2. Logdatei  (Zomboid/Lua/MultiTow_log.txt)
-- ####################################################################
local LOG_FILE = "MultiTow_log.txt"

-- Eine Zeile an die Logdatei anhaengen (Fehler werden verschluckt, damit das Spiel nie daran scheitert)
--   Aufruf:   MultiTow.log("Attach", 12, "->", 15)
--   Ergebnis: "1729850000000 Attach 12 -> 15"     (vorne die Uhrzeit in Millisekunden)
function MultiTow.log(...)
    local args = {...}
    local parts = { tostring(getTimestampMs()) }
    for i = 1, #args do
        parts[#parts + 1] = tostring(args[i])     -- tostring: auch nil/true/Objekte werden lesbar
    end
    local line = table.concat(parts, " ")

    pcall(function()
        local w = getFileWriter(LOG_FILE, true, true)   -- true, true = anlegen falls noetig, ANHAENGEN
        if w then
            w:write(line .. "\n")
            w:close()
        end
    end)
end

-- Beim Laden der Mod die Datei leeren
--   (getFileWriter mit append = false ueberschreibt die alte Datei)
pcall(function()
    local w = getFileWriter(LOG_FILE, true, false)
    if w then
        w:write("=== MultiTow log started ===\n")
        w:close()
    end
end)

-- ####################################################################
-- ##  3. Kupplungspunkte und Abstaende
-- ####################################################################
--          vorne                                   hinten
--   "trailerfront" o====[  Fahrzeug  ]====o "trailer"
--
-- Findet den passenden Kupplungsnamen (unterstützt Vanilla & Mod-Fahrzeuge)
--   -> 1. Gibt es den Standardnamen ("trailer" / "trailerfront")? Dann den.
--   -> 2. Sonst alle Kupplungspunkte des Fahrzeug-Skripts nach typischen Woertern durchsuchen.
--   -> 3. Nichts gefunden -> trotzdem den Standardnamen zurueckgeben.
function MultiTow.findAttachmentName(veh, isRear)
    local defaultName = isRear and "trailer" or "trailerfront"
    if not veh then return defaultName end
    local script = veh:getScript()
    if not script then return defaultName end

    if script:getAttachmentById(defaultName) then
        return defaultName
    end

    local count = script:getAttachmentCount()
    for i = 0, count - 1 do
        local att = script:getAttachment(i)
        if att then
            local id = att:getId()
            local low = string.lower(id)
            if isRear then
                -- hinten: enthaelt trailer/hook/tow/rear, aber NICHT "front"
                if not string.find(low, "front") and (string.find(low, "trailer") or string.find(low, "hook") or string.find(low, "tow") or string.find(low, "rear")) then
                    return id
                end
            else
                -- vorne: "front" oder eines der Kupplungswoerter
                if string.find(low, "front") or string.find(low, "trailer") or string.find(low, "hook") or string.find(low, "tow") then
                    return id
                end
            end
        end
    end
    return defaultName
end

-- Gibt die exakte Weltposition eines Kupplungshakens zurück
--   (x, y, z) in Weltkoordinaten; falls das Spiel keinen Punkt liefert: Fahrzeugmitte
function MultiTow.getHitchWorldPos(veh, attName)
    local v = Vector3f.new()                              -- leerer Vektor, den das Spiel befuellt
    local pos = veh:getAttachmentWorldPos(attName, v)
    if pos then
        return pos:x(), pos:y(), pos:z()
    end
    return veh:getX(), veh:getY(), veh:getZ()
end

-- Berechnet den Abstand zwischen zwei Kupplungshaken
--   nur waagerecht (x/y) - die Hoehe spielt beim Ankuppeln keine Rolle.  Pythagoras: sqrt(dx^2 + dy^2)
function MultiTow.getHitchDistance(vehA, vehB, attA, attB)
    local x1, y1 = MultiTow.getHitchWorldPos(vehA, attA)
    local x2, y2 = MultiTow.getHitchWorldPos(vehB, attB)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

-- ####################################################################
-- ##  4. Der Zug: Nachbarn, Laenge, Zugfahrzeug, LKW oder PKW
-- ####################################################################
--   [ Kopf ] -> [ 2 ] -> [ 3 ] -> [ 4 ]
--      getVehicleTowing():  Kopf -> 2      ("wen ziehe ich?")
--      getVehicleTowedBy(): 2 -> Kopf      ("wer zieht mich?")

-- Welches Fahrzeug haengt hinten dran? (Der Java-Teil "MultiTowCore" fuehrt jetzt
-- mehrere Kupplungen pro Fahrzeug, die Spiel-Funktionen liefern daher die echte Kette.)
function MultiTow.getChainTowing(veh)
    if not veh then return nil end
    return veh:getVehicleTowing()
end

-- Von welchem Fahrzeug wird dieses gezogen?
function MultiTow.getChainTowedBy(veh)
    if not veh then return nil end
    return veh:getVehicleTowedBy()
end

-- Wie viele Fahrzeuge hat der Zug, wenn vehA (samt allen davor) und vehB (samt allen dahinter) gekuppelt werden?
--
--   vehA und alle davor          vehB und alle dahinter
--   [K]-[x]-[vehA]       +       [vehB]-[y]               = 5 Fahrzeuge
--   <--- zaehlt rueckwaerts      zaehlt vorwaerts --->
--
--   !! ACHTUNG: Die Grenzen 64 / 128 schuetzen vor einer Endlosschleife, falls eine Kette kaputt ist.
function MultiTow.trainLength(vehA, vehB)
    local n = 0
    local v = vehA
    while v and n < 64 do
        n = n + 1
        v = v:getVehicleTowedBy()
    end
    v = vehB
    while v and n < 128 do
        n = n + 1
        v = v:getVehicleTowing()
    end
    return n
end

-- Zugfahrzeug = erstes Fahrzeug der Kette (wird selbst nicht gezogen)
--   einfach immer nach vorne gehen, bis keiner mehr zieht
function MultiTow.getHead(veh)
    local n = 0
    while veh and veh:getVehicleTowedBy() and n < 64 do
        veh = veh:getVehicleTowedBy()
        n = n + 1
    end
    return veh
end

-- LKW oder PKW? Die Regel steht im Java-Teil (ChainTow.isTruckName), damit sie nur an einer Stelle gepflegt wird.
--   >> WARUM pcall: fehlt der Java-Teil oder hat er einen Fehler, gilt das Fahrzeug einfach als PKW.
function MultiTow.isTruck(veh)
    if not veh or not multiTowIsTruck then return false end
    local ok, res = pcall(function() return multiTowIsTruck(veh:getScriptName()) end)
    return ok and res == true
end

-- Hoechstzahl Fahrzeuge fuer einen Zug mit diesem Zugfahrzeug (0 = unbegrenzt)
function MultiTow.getMaxFor(headVeh)
    if MultiTow.isTruck(headVeh) then
        return MultiTow.Settings.maxTruck or 0
    end
    return MultiTow.Settings.maxCar or 0
end

-- Darf vehA an vehB gekuppelt werden (Einstellung "maximale Fahrzeuge", je nach Typ des Zugfahrzeugs)?
function MultiTow.isTrainLengthAllowed(vehA, vehB)
    local max = MultiTow.getMaxFor(MultiTow.getHead(vehA))
    if max <= 0 then return true end                   -- 0 = keine Grenze
    return MultiTow.trainLength(vehA, vehB) <= max
end

-- ####################################################################
-- ##  5. Gegenstaende: Haken, Abschleppstange, Inventar
-- ####################################################################

-- Gegenstand, der ab dem 3. Fahrzeug zum Ankuppeln noetig sein kann (Einstellung "Haken noetig")
MultiTow.HOOK_TYPE = "Base.HeavyChain_Hook"

--- Anzeigename des Hakens in der Sprache des Spielers (Ersatz: englischer Name).
function MultiTow.getHookName()
    local name = nil
    pcall(function()
        local item = getScriptManager():FindItem(MultiTow.HOOK_TYPE)
        if item then name = item:getDisplayName() end
    end)
    return name or "Heavy Chain Hook"
end

-- Abschleppstange (starre Verbindung) und ihre kaputte Form (nur noch Schrott)
MultiTow.TOWBAR_TYPE = "Base.MultiTowTowBar"
MultiTow.TOWBAR_BROKEN_TYPE = "Base.MultiTowTowBarBroken"

-- Anzeigename eines Gegenstands (fuer Meldungen)
function MultiTow.getItemName(fullType)
    local name = nil
    pcall(function()
        local item = getScriptManager():FindItem(fullType)
        if item then name = item:getDisplayName() end
    end)
    return name or tostring(fullType)
end

--- "Base.HeavyChain_Hook" -> "HeavyChain_Hook"  (alles bis zum ersten Punkt abschneiden)
--   >> WARUM: manche Inventar-Funktionen finden Gegenstaende nur mit, manche nur ohne "Base."
local function shortType(fullType)
    return (string.gsub(fullType, "^.-%.", ""))   -- <- Klammern: gsub liefert 2 Werte, wir wollen nur den Text
end

-- Hat der Spieler diesen Gegenstand (auch in Rucksaecken/Taschen)?
function MultiTow.hasItem(playerObj, fullType)
    if not playerObj then return false end
    local inv = playerObj:getInventory()
    if not inv then return false end
    local ok, found = pcall(function()
        return inv:containsTypeRecurse(fullType) or inv:containsTypeRecurse(shortType(fullType))
    end)
    return ok and found and true or false
end

-- Einen Gegenstand aus dem Inventar entfernen (auch aus Rucksaecken). true (+ der Gegenstand) = hat geklappt.
--   -> 1. Gegenstand suchen (mit und ohne "Base.")
--   -> 2. aus dem Behaelter nehmen, in dem er WIRKLICH liegt (z.B. Rucksack, nicht Hauptinventar)
--   -> 3. [MP] dem Client mitteilen
--   -> 4. Inventarfenster neu zeichnen lassen
function MultiTow.consumeItem(playerObj, fullType)
    if not playerObj then return false end
    local inv = playerObj:getInventory()
    if not inv then return false end
    local taken = nil
    local ok, done = pcall(function()
        local item = inv:getFirstTypeRecurse(fullType) or inv:getFirstTypeRecurse(shortType(fullType))
        if not item then return false end
        taken = item
        local container = item:getContainer() or inv
        container:Remove(item)
        if isServer() then
            -- Multiplayer: dem Client mitteilen, dass der Gegenstand weg ist
            sendRemoveItemFromContainer(container, item)
        end
        return true
    end)
    if ok and done then
        pcall(function()
            if ISInventoryPage and ISInventoryPage.dirtyUI then ISInventoryPage.dirtyUI() end
        end)
    end
    if ok and done then return true, taken end
    return false
end

-- Gegenstand, der die Verbindung zwischen vehB und seinem Vordermann bildet (kommt beim Abkuppeln zurueck), oder nil
--   Gespeichert im hinteren Fahrzeug (modData):
--     MultiTowItem = "Base.MultiTowTowBar" / "Base.HeavyChain_Hook"   (neue Form)
--     MultiTowHook = true                                              (alte Form aus frueheren Versionen)
function MultiTow.linkItemOf(vehB)
    if not vehB then return nil end
    local md = vehB:getModData()
    if not md then return nil end
    if type(md.MultiTowItem) == "string" then return md.MultiTowItem end
    if md.MultiTowHook == true then return MultiTow.HOOK_TYPE end   -- <- alte Spielstaende weiter lesbar
    return nil
end

-- Ist die Verbindung vor vehB eine starre Abschleppstange?
function MultiTow.isBarLink(vehB)
    if not vehB then return false end
    local md = vehB:getModData()
    return md ~= nil and md.MultiTowLink == "bar"
end

-- Traegt der Spieler den Haken bei sich (auch in Rucksaecken/Taschen)? Er wird nicht verbraucht.
function MultiTow.hasHook(playerObj)
    if not playerObj then return false end
    local inv = playerObj:getInventory()
    if not inv then return false end
    local ok, found = pcall(function()
        return inv:containsTypeRecurse(MultiTow.HOOK_TYPE) or inv:containsTypeRecurse("HeavyChain_Hook")
    end)
    return ok and found and true or false
end

-- Einen Haken aus dem Inventar entfernen (auch aus Rucksaecken). Gibt true zurueck, wenn es geklappt hat.
function MultiTow.consumeHook(playerObj)
    return MultiTow.consumeItem(playerObj, MultiTow.HOOK_TYPE)
end

-- Hat die Verbindung zwischen vehB und seinem Vordermann einen Haken gekostet?
function MultiTow.isHookLink(vehB)
    return MultiTow.linkItemOf(vehB) == MultiTow.HOOK_TYPE
end

-- Braucht dieses Ankuppeln einen Haken? Ja, wenn der Zug danach mindestens 3 Fahrzeuge hat und die Einstellung an ist.
--   [1]-[2]          -> kein Haken (normales Abschleppen wie im Spiel)
--   [1]-[2]-[3]      -> Haken noetig (falls Option an)
function MultiTow.needsHook(vehA, vehB)
    if not MultiTow.Settings.requireHook then return false end
    return MultiTow.trainLength(vehA, vehB) >= 3
end

-- Verhindert Endlosschleifen (Kreis-Kupplungen)
--   Sucht vehB einmal nach hinten und einmal nach vorne von vehA aus.
--   Gefunden = beide sind schon im selben Zug -> Ankuppeln wuerde einen Kreis bilden:
--       [A]-[x]-[B]
--        ^-------'      <- verboten
function MultiTow.isAlreadyInSameChain(vehA, vehB)
    local curr = vehA
    local safety = 0
    while curr and safety < 25 do
        if curr == vehB then return true end
        curr = MultiTow.getChainTowing(curr)
        safety = safety + 1
    end
    curr = vehA
    safety = 0
    while curr and safety < 25 do
        if curr == vehB then return true end
        curr = MultiTow.getChainTowedBy(curr)
        safety = safety + 1
    end
    return false
end

-- Sucht ein koppelbares Fahrzeug im 3-Felder-Umkreis
--   Rueckgabe: bestes Fahrzeug, und ob sourceVeh dabei VORNE ist (true) oder hinten (false)
--
--      . . . . . . .
--      . . . . . . .      7 x 7 Felder um den Spieler (S)
--      . . . S . . .      in jedem Feld: steht dort ein Fahrzeug?
--      . . . . . . .      -> beide Richtungen pruefen (A zieht B / B zieht A)
--      . . . . . . .      -> der kleinste Abstand der Kupplungspunkte gewinnt
--
--   !! ACHTUNG: nur Abstaende unter 2.2 Feldern zaehlen (bestDist startet bei 2.2).
function MultiTow.findValidChainPartner(playerObj, sourceVeh)
    local px = math.floor(playerObj:getX())
    local py = math.floor(playerObj:getY())
    local pz = playerObj:getZ()
    local cell = getCell()
    if not cell then return nil end

    local bestVeh = nil
    local bestDist = 2.2
    local bestIsSourceFront = true

    for x = px - 3, px + 3 do
        for y = py - 3, py + 3 do
            local sq = cell:getGridSquare(x, y, pz)
            if sq then
                local cand = sq:getVehicleContainer()
                if cand and cand ~= sourceVeh and not MultiTow.isAlreadyInSameChain(sourceVeh, cand) then

                    -- Option A: sourceVeh (vorne) zieht cand (hinten)
                    --   [sourceVeh] hinten o--o vorne [cand]
                    if MultiTow.getChainTowing(sourceVeh) == nil and MultiTow.getChainTowedBy(cand) == nil then
                        local attA = MultiTow.findAttachmentName(sourceVeh, true)
                        local attB = MultiTow.findAttachmentName(cand, false)
                        local dist = MultiTow.getHitchDistance(sourceVeh, cand, attA, attB)
                        if dist < bestDist then
                            bestDist = dist
                            bestVeh = cand
                            bestIsSourceFront = true
                        end
                    end

                    -- Option B: cand (vorne) zieht sourceVeh (hinten)
                    --   [cand] hinten o--o vorne [sourceVeh]
                    if MultiTow.getChainTowing(cand) == nil and MultiTow.getChainTowedBy(sourceVeh) == nil then
                        local attA = MultiTow.findAttachmentName(cand, true)
                        local attB = MultiTow.findAttachmentName(sourceVeh, false)
                        local dist = MultiTow.getHitchDistance(cand, sourceVeh, attA, attB)
                        if dist < bestDist then
                            bestDist = dist
                            bestVeh = cand
                            bestIsSourceFront = false
                        end
                    end

                end
            end
        end
    end

    return bestVeh, bestIsSourceFront
end

-- ---------------------------------------------------------------------------
-- Multiplayer
-- ---------------------------------------------------------------------------
--   +----------------+------------+------------+
--   |                | isClient() | isServer() |
--   +----------------+------------+------------+
--   | Einzelspieler  |   false    |   false    |
--   | MP-Client      |   true     |   false    |
--   | MP-Server      |   false    |   true     |
--   +----------------+------------+------------+

-- true auf einem MP-Server oder MP-Client (nicht im Einzelspieler)
function MultiTow.isMP()
    return isClient() or isServer()
end

-- Zusatzkraft: Index der Auswahl (1..6) -> Wert. -1 = aus, 0 = automatisch, sonst fester Faktor
MultiTow.BOOST_VALUES = { -1, 1.5, 2.0, 2.5, 3.0, 0 }

-- Tempolimit in km/h umrechnen (Einstellung kann km/h oder mph sein)
--   1 Meile = 1.609344 km   ->   50 mph = 80.5 km/h
function MultiTow.speedToKmh(value)
    value = tonumber(value) or 0
    if MultiTow.Settings.speedUnit == "mph" then
        return value * 1.609344
    end
    return value
end

-- Zugbremse, Tempolimit und Mithelfen an den Java-Teil geben
--   >> WARUM immer km/h: der Java-Teil rechnet nur in km/h, die Umrechnung passiert hier.
function MultiTow.applyTrainSettings()
    local s = MultiTow.Settings
    if multiTowConfigureTrain then
        multiTowConfigureTrain(tonumber(s.brakeCar) or 0, tonumber(s.brakeTruck) or 0,
            MultiTow.speedToKmh(s.speedCar), MultiTow.speedToKmh(s.speedTruck))
    end
    -- Mithelfen (ab 0.15.0): Prozent der eigenen Motorkraft laufender gezogener Fahrzeuge (0 = aus).
    --   Gibt es die Funktion nicht (alter Java-Teil), passiert einfach nichts.
    if multiTowSetAssist then
        multiTowSetAssist(tonumber(s.assist) or 0)
    end
end

-- Im Multiplayer gelten die Regeln aus den Sandbox-Optionen des Servers (fuer alle Spieler gleich).
-- Im Einzelspieler kommen sie aus dem Optionsmenue (MultiTow_Options.lua). Gibt true zurueck, wenn angewendet.
--   [MP] SandboxVars.MultiTow.<Name> (sandbox-options.txt)  ->  MultiTow.Settings.<name>
--   !! ACHTUNG: "~= false" statt "== true" bei Schaltern, die standardmaessig AN sind:
--      fehlt der Wert (alte Server-Einstellung), bleibt der Schalter dann an.
function MultiTow.applySandbox()
    if not MultiTow.isMP() then return false end
    local sv = SandboxVars and SandboxVars.MultiTow
    if not sv then return false end

    --- Auswahl der Zusatzkraft -> (an?, fester Faktor oder 0 = automatisch)
    local function boost(idx)
        local v = MultiTow.BOOST_VALUES[tonumber(idx) or 6] or 0
        return v >= 0, (v >= 0) and v or 0
    end

    MultiTow.Settings.enabled = sv.Enabled ~= false
    MultiTow.Settings.requireHook = sv.RequireHook == true
    MultiTow.Settings.maxCar = tonumber(sv.MaxVehiclesCar) or 0
    MultiTow.Settings.maxTruck = tonumber(sv.MaxVehiclesTruck) or 0
    local carOn, carFixed = boost(sv.BoostCar)
    local truckOn, truckFixed = boost(sv.BoostTruck)

    local S = MultiTow.Settings
    S.speedUnit = (tonumber(sv.SpeedUnit) == 2) and "mph" or "kmh"
    S.brakeCar = tonumber(sv.BrakeCar) or 50
    S.brakeTruck = tonumber(sv.BrakeTruck) or 50
    S.speedCar = tonumber(sv.SpeedLimitCar) or 0
    S.speedTruck = tonumber(sv.SpeedLimitTruck) or 0
    S.fuelModeCar = tonumber(sv.FuelModeCar) or 1
    S.fuelModeTruck = tonumber(sv.FuelModeTruck) or 1
    S.fuelPctCar = tonumber(sv.FuelPercentCar) or 20
    S.fuelPctTruck = tonumber(sv.FuelPercentTruck) or 20
    S.noiseCar = sv.NoiseCar ~= false
    S.noiseTruck = sv.NoiseTruck ~= false
    S.wear = tonumber(sv.Wear) or 3
    S.cargo = tonumber(sv.CargoWeight) or 5
    S.hazardAuto = sv.HazardAuto ~= false
    -- Mithelfen (ab 0.15.0): nur wenn die Kraft-Erhoehung bei PKW und LKW aus ist
    S.assist = (not carOn and not truckOn) and (tonumber(sv.AssistPower) or 0) or 0
    MultiTow.applyTrainSettings()

    -- Regeln auch an den Java-Teil (er prueft beim Ankuppeln selbst noch einmal)
    if multiTowConfigure then
        multiTowConfigure(MultiTow.Settings.enabled, MultiTow.Settings.requireHook,
            MultiTow.Settings.maxCar, carOn, carFixed,
            MultiTow.Settings.maxTruck, truckOn, truckFixed)
    end
    MultiTow.log("Sandbox settings:", tostring(MultiTow.Settings.enabled), "hook:", tostring(MultiTow.Settings.requireHook),
        "cars:", MultiTow.Settings.maxCar, tostring(carOn), carFixed,
        "trucks:", MultiTow.Settings.maxTruck, tostring(truckOn), truckFixed)
    return true
end


-- ---------------------------------------------------------------------------
-- Ankuppeln mit Gegenstand (Einzelspieler und Server benutzen dieselbe Funktion)
-- ---------------------------------------------------------------------------
-- linkType: "chain" (Kette/Seil, ab dem 3. Fahrzeug evtl. mit Haken) oder "bar" (starre Abschleppstange, immer mit Stange)
-- Gibt true zurueck oder false + Textschluessel fuer die Fehlermeldung.
--
--   -> 1. Pruefen: Stange bzw. Haken im Inventar?           (sonst Abbruch mit Meldung)
--   -> 2. Art der Verbindung im hinteren Fahrzeug merken     (modData)
--   -> 3. Spiel-Funktion addPointConstraint kuppeln lassen   (der Java-Teil haengt sich hier ein)
--   -> 4. Hat es geklappt? Sonst Merker zuruecknehmen
--   -> 5. Warnblinker evtl. automatisch einschalten
--   -> 6. Gegenstand aus dem Inventar nehmen, Zustand der Verbindung setzen
function MultiTow.doAttach(player, vehA, vehB, attA, attB, linkType)
    local bar = (linkType == "bar")
    if bar and not MultiTow.hasItem(player, MultiTow.TOWBAR_TYPE) then
        return false, "UI_MultiTow_NeedTowBar"
    end
    local needHook = (not bar) and MultiTow.needsHook(vehA, vehB)
    if needHook and not MultiTow.hasHook(player) then
        return false, "UI_MultiTow_NeedHook"
    end

    --- [MP] geaenderte modData des hinteren Fahrzeugs an alle Spieler schicken
    local function transmit()
        if isServer() then pcall(function() vehB:transmitModData() end) end
    end

    -- Art der Verbindung VOR dem Ankuppeln merken: der Java-Teil liest sie (und nach dem Laden wieder)
    local md = vehB:getModData()
    md.MultiTowItem = nil
    md.MultiTowHook = nil
    md.MultiTowLink = bar and "bar" or nil
    transmit()

    vehA:addPointConstraint(player, vehB, attA, attB)

    -- !! ACHTUNG: addPointConstraint meldet keinen Fehler - also nachsehen, ob B wirklich an A haengt.
    if vehA:getVehicleTowing() ~= vehB then
        md.MultiTowLink = nil
        transmit()
        return false, "UI_MultiTow_ActionFailed"
    end

    -- Gegenstand verbrauchen und merken: beim Abkuppeln kommt er zurueck, beim Reissen faellt er (kaputt) runter
    local item = bar and MultiTow.TOWBAR_TYPE or (needHook and MultiTow.HOOK_TYPE or nil)
    -- Warnblinker automatisch einschalten (Option "Warnblinker automatisch" im Bereich Gameplay)
    if MultiTow.Settings.hazardAuto then
        local head = MultiTow.getHead(vehA)
        if head then
            head:getModData().MultiTowHazard = true   -- <- steht beim Zugfahrzeug, gilt fuer den ganzen Zug
            if isServer() then pcall(function() head:transmitModData() end) end
        end
    end

    -- Zustand der neuen Verbindung (fuer den Verschleiss): Abschleppstange behaelt ihren Zustand, sonst neu = 100 %
    md.MultiTowCond = 100
    if item then
        local consumed, obj = MultiTow.consumeItem(player, item)
        if consumed then
            md.MultiTowItem = item
            if bar and obj then
                md.MultiTowCond = math.max(1, MultiTow.itemConditionPct(obj))   -- mindestens 1 %, sonst reisst sie sofort
            end
            MultiTow.log("  item consumed:", item, "condition", md.MultiTowCond)
        else
            MultiTow.log("  WARNING: item missing when consuming:", item)
        end
    end
    transmit()
    return true
end

-- ---------------------------------------------------------------------------
-- Zustand von Gegenstaenden und Verbindungen (Verschleiss)
-- ---------------------------------------------------------------------------
--   Abschleppstange im Inventar   <-->   Verbindung im Zug
--   Zustand 73 / 100                     MultiTowCond = 73   (im hinteren Fahrzeug)
--        ankuppeln:  Gegenstand -> Verbindung   (doAttach)
--        abkuppeln:  Verbindung -> Gegenstand   (applyReturnCondition)

-- Zustand eines Gegenstands in Prozent (0..100)
function MultiTow.itemConditionPct(item)
    local ok, pct = pcall(function()
        local max = item:getConditionMax()
        if not max or max <= 0 then return 100 end   -- Gegenstand ohne Zustand gilt als neu
        return item:getCondition() / max * 100
    end)
    return ok and pct or 100
end

-- Zustand eines Gegenstands in Prozent setzen
--   Beispiel: ConditionMax 100, pct 72.6  ->  setCondition(73)   (gerundet, mindestens 1)
function MultiTow.setItemConditionPct(item, pct)
    pcall(function()
        local max = item:getConditionMax()
        if max and max > 0 then
            item:setCondition(math.max(1, math.min(max, math.floor(max * pct / 100 + 0.5))))
        end
    end)
end

-- Zustand der Verbindung vor diesem (hinteren) Fahrzeug in Prozent, nil = keine Verbindung
function MultiTow.linkCondition(rear)
    if not rear or not rear:getVehicleTowedBy() then return nil end
    return tonumber(rear:getModData().MultiTowCond) or 100
end

-- Verschleisst diese Verbindung? Nicht bei echten Anhaengern (feste Anhaengerkupplung des Spiels).
function MultiTow.linkWears(rear)
    local front = rear and rear:getVehicleTowedBy()
    return front ~= nil and MultiTow.canUseBar(front, rear)
end

-- Kette nutzt sich schneller ab als die Stange
MultiTow.WEAR_CHAIN, MultiTow.WEAR_BAR = 1.0, 0.3

-- Verschleiss pro Sekunde bei dieser Belastung (0..1). Ruhige Fahrt (0.1): ca. 0.02 %/s, harter Ruck (1.0): ca. 1 %/s.
--
--   Formel:  Einstellung  x  Art (Kette 1.0 / Stange 0.3)  x  (0.01 + Belastung^2)
--
--   Belastung  | 0.0   | 0.1   | 0.5   | 1.0
--   -----------+-------+-------+-------+------
--   %/s Kette  | 0.01  | 0.02  | 0.26  | 1.01     (Einstellung "Normal" = 1.0)
--
--   >> WARUM hoch 2: kleine Rucke sollen kaum schaden, harte Rucke dafuer deutlich.
function MultiTow.wearPerSecond(rear, stress)
    local factor = MultiTow.WEAR_FACTORS[tonumber(MultiTow.Settings.wear) or 1] or 0
    if factor <= 0 then return 0 end
    local typeFactor = MultiTow.isBarLink(rear) and MultiTow.WEAR_BAR or MultiTow.WEAR_CHAIN
    stress = math.max(0, math.min(1, tonumber(stress) or 0))
    return factor * typeFactor * (0.01 + stress * stress)
end

-- Verschleiss anwenden (Einzelspieler und Server). Bei 0 % reisst die Verbindung.
--   [MP] nur der Server ruft das auf; die Clients melden ihm den Verschleiss (Befehl "wear")
function MultiTow.applyWear(rear, loss)
    loss = tonumber(loss) or 0
    if not rear or loss <= 0 or not MultiTow.linkWears(rear) then return end
    local md = rear:getModData()
    local cond = (tonumber(md.MultiTowCond) or 100) - loss
    md.MultiTowCond = math.max(0, cond)
    if isServer() then pcall(function() rear:transmitModData() end) end
    if cond <= 0 then
        MultiTow.log("WEAR link worn out ->", rear:getId())
        if multiTowSnapLink then multiTowSnapLink(rear) end   -- Java-Teil trennt + meldet "SNAP"
    end
end

-- Abgekuppelter Gegenstand: Abschleppstange bekommt den Zustand der Verbindung zurueck
function MultiTow.applyReturnCondition(item, fullType, rear)
    if not item or fullType ~= MultiTow.TOWBAR_TYPE or not rear then return end
    local cond = tonumber(rear:getModData().MultiTowCond)
    if cond then MultiTow.setItemConditionPct(item, cond) end
end

-- ---------------------------------------------------------------------------
-- Gewicht (Fahrzeug + Ladung)
-- ---------------------------------------------------------------------------
--   Zug-Gewicht eines Fahrzeugs = Leergewicht + Ladung x eingestellter Anteil
--                                 (emptyMass)    (cargoWeight)  (CARGO_PCT)

-- Gewicht der Ladung eines Fahrzeugs: Inhalt aller Behaelter (Kofferraum, Sitze, Handschuhfach, Tank-Gegenstaende ...)
function MultiTow.cargoWeight(veh)
    local w = 0
    pcall(function()
        for i = 0, veh:getPartCount() - 1 do
            local part = veh:getPartByIndex(i)
            local c = part:getItemContainer()
            if c then w = w + c:getCapacityWeight() end   -- getCapacityWeight = Gewicht des Inhalts
        end
    end)
    return w
end

-- Leergewicht: Gewicht laut Fahrzeug-Skript plus eingebaute Teile (Reifen, Motor, Tueren ...), wie das Spiel rechnet
--   -> 1. getInitialMass (Grundgewicht)  - klappt das nicht: Gewicht aus dem Fahrzeug-Skript
--   -> 2. Gewicht jedes eingebauten Teils dazuzaehlen
function MultiTow.emptyMass(veh)
    local ok, m = pcall(function() return veh:getInitialMass() end)
    if not ok or not m or m <= 0 then
        ok, m = pcall(function() return veh:getScript():getMass() end)
        m = ok and m or 0
    end
    pcall(function()
        for i = 0, veh:getPartCount() - 1 do
            local item = veh:getPartByIndex(i):getInventoryItem()
            if item then m = m + item:getWeight() end
        end
    end)
    return m
end

-- Gewicht, mit dem dieses Fahrzeug im Zug rechnet (Leergewicht + eingestellter Anteil der Ladung)
--   Einstellung "Aus" (pct = nil): einfach das Gewicht, das das Spiel selbst verwendet (getMass)
function MultiTow.trainMassOf(veh)
    local pct = MultiTow.CARGO_PCT[tonumber(MultiTow.Settings.cargo) or 1]
    if not pct then
        local ok, m = pcall(function() return veh:getMass() end)
        return ok and m or MultiTow.emptyMass(veh)
    end
    return MultiTow.emptyMass(veh) + MultiTow.cargoWeight(veh) * pct / 100
end

-- ####################################################################
-- ##  10. Reissen und Stangen-Regel
-- ####################################################################

-- Was faellt beim Reissen einer Verbindung auf den Boden? (Liste der Gegenstaende, Textschluessel der Meldung)
--   Abschleppstange -> eine kaputte Stange (nur noch Schrott)
--   Haken           -> Schwere Kette + Grosser Haken
function MultiTow.breakDrops(fullType)
    if fullType == MultiTow.TOWBAR_TYPE then
        return { MultiTow.TOWBAR_BROKEN_TYPE }, "UI_MultiTow_BarBroke"
    end
    return { "Base.HeavyChain", "Base.LargeHook" }, "UI_MultiTow_HookBroke"
end

-- Abschleppstange nur zwischen zwei normalen Fahrzeugen: echte Anhaenger haben schon eine feste Deichsel
--   erkannt am Skriptnamen: enthaelt er "Trailer" (z.B. "Base.TrailerCover"), ist es ein Anhaenger
function MultiTow.canUseBar(vehA, vehB)
    local function isTrailer(v)
        local ok, name = pcall(function() return tostring(v:getScript():getName()) end)
        return ok and name and string.find(name, "Trailer", 1, true) ~= nil   -- true = einfache Suche, kein Muster
    end
    return vehA ~= nil and vehB ~= nil and not isTrailer(vehA) and not isTrailer(vehB)
end
