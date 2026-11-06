--[[==========================================================================
    MultiTow_Hazard.lua                                        [ client ]
  ----------------------------------------------------------------------------
    Multi-Vehicle Towing: Warnblinker fuer gezogene Fahrzeuge

    EIN / AUS
      * im Fahrzeug-Rundmenue (Taste V) als Fahrer des Zugfahrzeugs, oder
      * automatisch beim Ankuppeln (Option "Warnblinker automatisch einschalten",
        Bereich Gameplay; das macht doAttach in MultiTow_Common.lua)
      Ob er an ist, steht beim Zugfahrzeug (modData MultiTowHazard), damit es
      im Multiplayer alle sehen.

    AUSSEHEN (persoenliche Einstellung, Bereich Allgemein)
      Amerikanisch:  Rueck- und Bremslichter der gezogenen Fahrzeuge blinken rot
                     (macht der Java-Teil, Hazard.java) + rotes Licht hinten,
                     gelb-oranges Licht vorne (diese Datei)
      Europaeisch:   Rueck-/Bremslichter blinken ebenfalls + oranges Licht
                     vorne und hinten (diese Datei)
      Die Lichter dieser Datei sind echte Lichtquellen der Welt: sie faerben
      Boden und Fahrzeug, am besten zu sehen in Daemmerung und Nacht.
      Orange Leuchten AM Fahrzeugmodell kennt das Spiel nicht.
      Umfang: nur das letzte Fahrzeug oder alle angekoppelten Fahrzeuge.

    WER MACHT WAS?
      +-----------------------------+------------------------------------------+
      | Java (Hazard.java)          | Takt (400 ms an / 400 ms aus),           |
      |                             | Rueck-/Bremslichter am Modell,           |
      |                             | welche Fahrzeuge gerade blinken          |
      +-----------------------------+------------------------------------------+
      | Lua (diese Datei)           | Rundmenue-Eintrag, Lichtquellen in der   |
      |                             | Welt im selben Takt an- und ausschalten  |
      +-----------------------------+------------------------------------------+
============================================================================]]

require "MultiTow_Common"
require "MultiTow_Train"

-- Werte der Auswahl "Warnblinker-Stil" im Optionsmenue (Reihenfolge der Eintraege)
MultiTow.HAZARD_STYLE_OFF, MultiTow.HAZARD_STYLE_US, MultiTow.HAZARD_STYLE_EU = 1, 2, 3

-- Farben der Blinklichter vorne und hinten (zusaetzlich zu den Rueckleuchten am Modell,
-- die mit manchen Optimierungs-Mods nicht sichtbar blinken). Werte: rot, gruen, blau, Reichweite in Feldern.
--   amerikanisch: hinten rot, vorne orange (wie die Blinker vorne an US-Autos)
--   europaeisch:  vorne und hinten orange
-- Reichweite klein halten: sonst strahlt das rote Licht hinten bis zur Front und die vorderen Blinker wirken rot-gelb
--                 R     G     B    Reichweite
local ORANGE   = { 1.0, 0.45, 0.0, 2 }
local AMBER_US = { 1.0, 0.55, 0.0, 1 }
local RED      = { 1.0, 0.05, 0.0, 1 }
local COLORS = {
    [2] = { rear = RED, front = AMBER_US },     -- 2 = amerikanisch
    [3] = { rear = ORANGE, front = ORANGE },    -- 3 = europaeisch
    -- 1 = aus -> kein Eintrag -> keine Lichter
}

--- Ist der Warnblinker dieses Zuges an?  (head = Zugfahrzeug)
function MultiTow.isHazardOn(head)
    return head ~= nil and head:getModData().MultiTowHazard == true
end

-- Einschalten/Ausschalten. Einzelspieler: sofort. Multiplayer: der Server setzt es und schickt es an alle.
function MultiTow.setHazard(player, head, on)
    if not head then return end
    if isClient() then
        -- [MP] Bitte an den Server (server/MultiTow_Server.lua -> Server.hazard)
        sendClientCommand(player, "MultiTow", "hazard", { v = head:getId(), on = on and true or false })
        return
    end
    -- "on and true or nil": bei AUS wird der Eintrag ganz geloescht statt "false" gespeichert
    head:getModData().MultiTowHazard = on and true or nil
    if isServer() then pcall(function() head:transmitModData() end) end   -- [MP] an alle Spieler verteilen
    MultiTow.log("Hazard lights", on and "on" or "off", "for train of", head:getId())
end

-- Einstellungen an den Java-Teil (Optionsmenue): Stil 1..3 -> 0..2, Umfang 1 = letztes, 2 = alle
--   >> WARUM -1: Lua zaehlt die Auswahl ab 1, der Java-Teil ab 0 (0 = aus).
function MultiTow.applyHazardSettings()
    local style = (tonumber(MultiTow.Settings.hazardStyle) or MultiTow.HAZARD_STYLE_EU) - 1
    if multiTowSetHazard then multiTowSetHazard(style, tonumber(MultiTow.Settings.hazardScope) or 1) end
end

-- ---------------------------------------------------------------------------
-- Rundmenue im Fahrzeug (Taste V): Eintrag fuer den Fahrer eines Zugfahrzeugs
-- ---------------------------------------------------------------------------
local ICON_ON = getTexture("media/ui/MultiTow_Hazard.png")       -- Warndreieck
local ICON_OFF = getTexture("media/ui/MultiTow_HazardOff.png")   -- Warndreieck, rot durchgestrichen

-- Wird beim Klick auf den Menue-Eintrag aufgerufen: an <-> aus
local function toggleHazard(player, head)
    MultiTow.setHazard(player, head, not MultiTow.isHazardOn(head))
end

-- Die Spiel-Funktion, die das Rundmenue IM Fahrzeug baut, wird "umwickelt":
--   erst baut das Spiel sein Menue (orig), dann haengen wir unseren Eintrag an.
-- !! ACHTUNG: "multiTowHazardPatched" verhindert, dass beim erneuten Laden der Datei doppelt umwickelt wird
--    (sonst stuende der Eintrag zweimal im Menue).
if ISVehicleMenu and ISVehicleMenu.showRadialMenu and not ISVehicleMenu.multiTowHazardPatched then
    ISVehicleMenu.multiTowHazardPatched = true
    local orig = ISVehicleMenu.showRadialMenu
    function ISVehicleMenu.showRadialMenu(playerObj)
        orig(playerObj)
        local ok, err = pcall(function()
            if not MultiTow.Settings.enabled then return end
            if isClient() and not MultiTow.serverReady then return end
            if not MultiTow.javaLoaded() then return end   -- Basis-Modus: Takt und Lichter kommen aus dem Java-Teil
            local head = MultiTow.drivenTrainHead(playerObj)   -- nur der Fahrer des Zugfahrzeugs bekommt den Eintrag
            if not head then return end
            local menu = getPlayerRadialMenu(playerObj:getPlayerNum())
            if not menu then return end
            local on = MultiTow.isHazardOn(head)
            -- Symbol zeigt, was der Klick bewirkt: Dreieck = einschalten, durchgestrichen = ausschalten
            menu:addSlice(getText(on and "UI_MultiTow_HazardTurnOff" or "UI_MultiTow_HazardTurnOn"),
                on and ICON_OFF or ICON_ON, toggleHazard, playerObj, head)
        end)
        if not ok then MultiTow.log("ERROR hazard menu:", tostring(err)) end
    end
end

-- ---------------------------------------------------------------------------
-- Blinklichter vorne und hinten (europaeisch orange, amerikanisch hinten rot / vorne orange), im Takt des Java-Teils
-- ---------------------------------------------------------------------------
--   Zeitstrahl:   |--- an 400 ms ---|--- aus 400 ms ---|--- an ---| ...
--   Bei jedem Wechsel (und NUR dann) werden alle Lichter entfernt und - in der "an"-Phase - neu gesetzt.
--   >> WARUM neu setzen statt verschieben: Lichtquellen der Welt sitzen fest auf einem Feld;
--      der Zug faehrt aber weiter, also bei jedem Blinken an der aktuellen Stelle neu anlegen.
local lights = {} -- Liste der gesetzten Lichtquellen
local lastPhase = nil   -- letzter Zustand des Takts (true = an, false = aus, nil = noch nie)

--- Alle von uns gesetzten Lichter wieder entfernen.
local function removeAll()
    local cell = getCell()
    for _, light in ipairs(lights) do
        if cell then pcall(function() cell:removeLamppost(light) end) end
    end
    lights = {}
end

-- Ein Licht an einem Ende des Fahrzeugs (rear = true: hinten, sonst vorne).
-- used: schon belegte Felder (zwischen zwei gekoppelten Fahrzeugen liegen hinten und vorne oft im selben Feld)
--
--     [ A ]-hinten  vorne-[ B ]      -> beide Punkte im selben Feld? Dann nur EIN Licht
local function addLight(cell, v, rear, col, used)
    local x, y = MultiTow.getHitchWorldPos(v, MultiTow.findAttachmentName(v, rear) or (rear and "trailer" or "trailerfront"))
    local fx, fy, z = math.floor(x), math.floor(y), math.floor(v:getZ())   -- Lichtquellen gibt es nur pro ganzem Feld
    local key = fx .. "," .. fy .. "," .. z
    if used[key] then return end
    used[key] = true
    local light = nil
    pcall(function()
        -- addLamppost(x, y, Etage, rot, gruen, blau, Reichweite) - eine Lampe, wie eine Strassenlaterne
        light = cell:addLamppost(fx, fy, z, col[1], col[2], col[3], col[4])
    end)
    if light then table.insert(lights, light) end
end

local hazardFailed = false   -- wird true nach einem Fehler -> ab dann bis zum Neustart nichts mehr tun

--- Einmal pro Spiel-Tick: hat der Takt gewechselt? Dann Lichter neu setzen bzw. entfernen.
local function hazardTick()
    local cell = getCell()
    if not cell or not multiTowHazardBlinkOn then return end   -- keine Welt geladen / Java-Teil fehlt
    local col = MultiTow.Settings.enabled and COLORS[tonumber(MultiTow.Settings.hazardStyle) or MultiTow.HAZARD_STYLE_EU] or nil
    local phase = col ~= nil and multiTowHazardBlinkOn() or false   -- Stil "aus" -> immer Phase "aus"
    if phase == lastPhase then return end    -- kein Wechsel -> nichts zu tun (spart viel Arbeit)
    lastPhase = phase
    removeAll()
    if not phase then return end
    -- nur Fahrzeuge in der Naehe der eigenen Figur (Lichtquellen kosten Rechenzeit)
    local p = getPlayer()
    if not p then return end
    -- Liste kommt aus dem Java-Teil (die Fahrzeugliste der Zelle ist mit manchen Optimierungs-Mods in Lua nicht nutzbar)
    if not multiTowHazardVehiclesNear then return end
    local list = multiTowHazardVehiclesNear(p:getX(), p:getY(), 60)   -- 60 Felder Umkreis
    local used = {}
    for i = 0, list:size() - 1 do
        local v = list:get(i)
        addLight(cell, v, true, col.rear, used)   -- hinten
        addLight(cell, v, false, col.front, used) -- vorne
    end
end

Events.OnTick.Add(function()
    if hazardFailed then return end
    local ok, err = pcall(hazardTick)
    if not ok then
        -- !! Sicherheitsnetz: lieber kein Licht als jede Sekunde eine Fehlermeldung
        hazardFailed = true
        MultiTow.log("ERROR orange hazard light (turned off until restart):", tostring(err))
        print("[MultiTow] ERROR orange hazard light: " .. tostring(err))
    end
end)

--- Ist p eine eigene Spielfigur an diesem PC?
--   >> WARUM: OnPlayerDeath kommt fuer JEDE Figur, die das Spiel als "Spieler" fuehrt - auch fuer NPCs
--      (z.B. Project A-Life) und im Multiplayer fuer andere Spieler. Dann sollen unsere Lichter nicht ausgehen.
--   Eigene Figuren = die Figuren von getSpecificPlayer(0 .. Anzahl-1) (bei geteiltem Bildschirm mehrere).
local function isOwnPlayer(p)
    if not p or not getSpecificPlayer then return false end
    local n = getNumActivePlayers and getNumActivePlayers() or 1
    for i = 0, math.max(1, n) - 1 do
        if getSpecificPlayer(i) == p then return true end
    end
    return false
end

-- Beim Verlassen des Spiels keine Lichter zuruecklassen (nur wenn die EIGENE Figur stirbt)
Events.OnPlayerDeath.Add(function(p)
    if isOwnPlayer(p) then removeAll() end
end)
Events.OnMainMenuEnter.Add(function() lights = {}; lastPhase = nil end)
