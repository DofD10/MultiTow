--[[==========================================================================
    MultiTow_Options.lua                                       [ client ]
  ----------------------------------------------------------------------------
    Optionsmenue der Mod (Hauptmenue -> Optionen -> "DO Utilities" -> Multi-Vehicle Towing).
    Die Werte gehen an den Java-Teil (MultiTowCore) und an die Lua-Menues.

    WIE FUNKTIONIEREN MOD-OPTIONEN IN BUILD 42?
      Das Spiel bietet "PZAPI.ModOptions". Man beschreibt nur, WELCHE Optionen
      es gibt (Haken, Auswahl, Regler, Taste) - das Spiel baut daraus die Seite,
      speichert die Werte in Zomboid/Lua/ModOptions.ini und laedt sie wieder.

    ABLAUF DIESER DATEI
      1. Optionen beschreiben (Abschnitte Allgemein, Gameplay, Zug-Anzeige, PKW, LKW)
      2. applySettings(): Werte auslesen und an MultiTow.Settings + Java-Teil geben
      3. Trick: eigener Reiter statt Sammelseite "Mods" (ganz unten)

    PERSOENLICH ODER REGEL?
      persoenlich (gilt auch im MP nur fuer dich): Geraeusche, Ketten-Bild,
                   Warnblinker-Aussehen, Band-Anzeige, Sprueche, Zug-Anzeige
      Regel (im MP kommen sie stattdessen vom Server / Sandbox-Optionen):
                   alles andere
============================================================================]]

-- !! ACHTUNG: Ohne PZAPI.ModOptions (sehr alte Spielversion) gibt es kein Menue -> Datei sofort verlassen
if not PZAPI or not PZAPI.ModOptions then return end

require "MultiTow_Utils"

-- Eindeutiger Name unserer Optionen (steht so auch in ModOptions.ini). NICHT aendern, sonst sind alle Einstellungen weg.
local OPTIONS_ID = "MultiTowRoadTrain"
MultiTow.OPTIONS_ID = OPTIONS_ID
local options = PZAPI.ModOptions:create(OPTIONS_ID, "Multi-Vehicle Towing")

-- Grundmuster jeder Option:
--     options:addTickBox( id,  Beschriftung,  Standardwert,  Tooltip )      Haken an/aus
--     options:addComboBox( id, Beschriftung, Tooltip ) + :addItem(...)      Auswahlliste
--     options:addSlider( id, Beschriftung, min, max, Schritt, Standard, Tooltip )
--   id           = Name, unter dem der Wert gespeichert wird
--   Beschriftung = Uebersetzungsschluessel aus UI.json

options:addDescription("UI_MultiTow_Description")

-- ############################################################################
-- ##  1. OPTIONEN BESCHREIBEN
-- ############################################################################

-- ---- Allgemein (gilt fuer alle Fahrzeuge) ----
options:addDescription("UI_MultiTow_HeaderGeneral")
options:addTitle("UI_MultiTow_SectionGeneral")
-- Rote Hinweiszeile "Rot geschriebene Optionen brauchen ZombieBuddy". Der Text beginnt mit MULTITOW_JAVANOTE:
-- und wird nur gezeigt, wenn der Java-Teil fehlt (oder die Debug-Vorschau an ist) - siehe addDescription unten.
options:addDescription("UI_MultiTow_JavaNote")
local enabled = options:addTickBox("enabled", "UI_MultiTow_Enabled", true, "UI_MultiTow_Enabled_tt")
-- Gegenstand (Haken) ab dem 3. Fahrzeug noetig?
local requireHook = options:addTickBox("requireHook", "UI_MultiTow_RequireHook", false, "UI_MultiTow_RequireHook_tt")

-- Kettengeraeusche beim Kuppeln, Abkuppeln und Reissen
local sounds = options:addTickBox("sounds", "UI_MultiTow_Sounds", true, "UI_MultiTow_Sounds_tt")
-- Ketten und Abschleppstangen zwischen den Fahrzeugen sichtbar zeichnen (Bild; spaeter evtl. 3D-Modell)
local showChains = options:addTickBox("showChains", "UI_MultiTow_ShowChains", true, "UI_MultiTow_ShowChains_tt")
-- Warnblinker: Aussehen und an welchen Fahrzeugen (persoenlich; ein-/ausgeschaltet wird im Rundmenue mit V)
local hazardStyle = options:addComboBox("hazardStyle", "UI_MultiTow_HazardStyle", "UI_MultiTow_HazardStyle_tt")
hazardStyle:addItem("UI_MultiTow_HazardStyleOff", false)
hazardStyle:addItem("UI_MultiTow_HazardStyleUS", false)
hazardStyle:addItem("UI_MultiTow_HazardStyleEU", true)
local hazardScope = options:addComboBox("hazardScope", "UI_MultiTow_HazardScope", "UI_MultiTow_HazardScope_tt")
hazardScope:addItem("UI_MultiTow_HazardScopeLast", true)
hazardScope:addItem("UI_MultiTow_HazardScopeAll", false)
-- Verbindungen als farbiges Band anzeigen (gruen = entspannt, rot = kurz vor dem Reissen)
local showLinks = options:addTickBox("showLinks", "UI_MultiTow_ShowLinks", false, "UI_MultiTow_ShowLinks_tt")
-- Taste fuer die Band-Anzeige (Standard: K) und ob sie gehalten oder umgeschaltet wird
local linkKey = options:addKeyBind("linkKey", "UI_MultiTow_LinkKey", Keyboard.KEY_K, "UI_MultiTow_LinkKey_tt")
local LINK_MODE_HOLD, LINK_MODE_TOGGLE = 1, 2
local linkKeyMode = options:addComboBox("linkKeyMode", "UI_MultiTow_LinkKeyMode", "UI_MultiTow_LinkKeyMode_tt")
linkKeyMode:addItem("UI_MultiTow_LinkKeyHold", true)
linkKeyMode:addItem("UI_MultiTow_LinkKeyToggle", false)
-- Baender automatisch zeigen, wenn man zu Fuss nah an einer Verbindung steht (ca. 2 m)
local showLinksNear = options:addTickBox("showLinksNear", "UI_MultiTow_ShowLinksNear", true, "UI_MultiTow_ShowLinksNear_tt")
-- Sprueche der Figur nach dem Ankuppeln
local remarks = options:addTickBox("remarks", "UI_MultiTow_Remarks", true, "UI_MultiTow_Remarks_tt")
-- Masseinheit fuer das Tempolimit: davon haengt ab, welcher Tempo-Regler (km/h oder mph) unten aktiv ist
local UNIT_KMH, UNIT_MPH = 1, 2
local speedUnit = options:addComboBox("speedUnit", "UI_MultiTow_SpeedUnit", "UI_MultiTow_SpeedUnit_tt")
speedUnit:addItem("UI_MultiTow_UnitKmh", true)
speedUnit:addItem("UI_MultiTow_UnitMph", false)

-- ---- Gameplay (Regeln; im Multiplayer aus den Sandbox-Optionen des Servers) ----
options:addSeparator()
options:addTitle("UI_MultiTow_SectionGameplay")
local wearSel = options:addComboBox("wear", "UI_MultiTow_Wear", "UI_MultiTow_Wear_tt")
wearSel:addItem("UI_MultiTow_WearOff", false)
wearSel:addItem("UI_MultiTow_WearLow", false)
wearSel:addItem("UI_MultiTow_WearNormal", true)
wearSel:addItem("UI_MultiTow_WearHigh", false)
wearSel:addItem("UI_MultiTow_WearVeryHigh", false)
local cargoSel = options:addComboBox("cargo", "UI_MultiTow_Cargo", "UI_MultiTow_Cargo_tt")
cargoSel:addItem("UI_MultiTow_CargoOff", false)
-- Texte ueber Uebersetzungsschluessel: ein "%" direkt im Text bringt die Uebersetzungsfunktion des Spiels durcheinander
cargoSel:addItem("UI_MultiTow_Cargo25", false)
cargoSel:addItem("UI_MultiTow_Cargo50", false)
cargoSel:addItem("UI_MultiTow_Cargo75", false)
cargoSel:addItem("UI_MultiTow_Cargo100", true)
local hazardAuto = options:addTickBox("hazardAuto", "UI_MultiTow_HazardAuto", true, "UI_MultiTow_HazardAuto_tt")
-- Mithelfen (ab 0.15.0): gezogene Fahrzeuge mit laufendem Motor fahren mit X % ihrer eigenen Motorkraft mit.
--   Nur einstellbar, wenn die Kraft-Erhoehung des Zugfahrzeugs bei PKW UND LKW aus ist (siehe updateEnabledSliders);
--   sonst wirkt sie nicht (0 an den Java-Teil). 0 = aus.
local assistPower = options:addSlider("assistPower", "UI_MultiTow_Assist", 0, 100, 10, 50, "UI_MultiTow_Assist_tt")

-- ---- Zug-Anzeige (persoenlich, auch im Multiplayer) ----
options:addSeparator()
options:addTitle("UI_MultiTow_SectionHud")
local hudOn = options:addTickBox("hud", "UI_MultiTow_Hud", true, "UI_MultiTow_Hud_tt")
local hudPos = options:addComboBox("hudPos", "UI_MultiTow_HudPos", "UI_MultiTow_HudPos_tt")
-- Reihenfolge wie MultiTow.HUD_POS (MultiTow_HUD.lua)
for i, key in ipairs({ "Free", "TopLeft", "Top", "TopRight", "Right", "BottomRight", "Bottom", "BottomLeft", "Left" }) do
    hudPos:addItem("UI_MultiTow_HudPos" .. key, i == 2)
end
local hudLines = {}
for _, key in ipairs({ "Count", "Speed", "Stress", "Cond", "Weight", "Fuel" }) do
    hudLines[key] = options:addTickBox("hud" .. key, "UI_MultiTow_HudShow" .. key, true, "UI_MultiTow_HudShow" .. key .. "_tt")
end

-- ---- PKW und LKW ----
--   Eine Auswahlliste liefert nur die NUMMER des gewaehlten Eintrags (1, 2, 3 ...).
--   Diese zwei Tabellen uebersetzen Nummer -> echten Wert:
--      Eintrag:      1    2    3    4    5    6    7
--      MAX_VALUES:   3    4    5    6    7    8    0 (unbegrenzt)
-- Reihenfolge der Eintraege = Zahlenwerte (0 = unbegrenzt)
local MAX_VALUES = { 3, 4, 5, 6, 7, 8, 0 }
-- Zusatzkraft fuers Zugfahrzeug. -1 = aus, 0 = automatisch, sonst fester Faktor
local BOOST_VALUES = { -1, 1.5, 2.0, 2.5, 3.0, 0 }

-- Die beiden Bereiche PKW und LKW haben dieselben Optionen. Massgebend ist der Typ des Zugfahrzeugs (erstes Fahrzeug des Zuges).
local function addVehicleSection(headerKey, titleKey, hintKey, suffix)
    options:addSeparator()
    options:addDescription(headerKey)
    options:addTitle(titleKey)
    options:addDescription(hintKey)

    local maxVeh = options:addComboBox("maxVehicles" .. suffix, "UI_MultiTow_MaxVehicles", "UI_MultiTow_MaxVehicles_tt")
    maxVeh:addItem("3", false)
    maxVeh:addItem("4", false)
    maxVeh:addItem("5", false)
    maxVeh:addItem("6", false)
    maxVeh:addItem("7", false)
    maxVeh:addItem("8", false)
    maxVeh:addItem("UI_MultiTow_Unlimited", true)

    local boostSel = options:addComboBox("boostMode" .. suffix, "UI_MultiTow_BoostFactor", "UI_MultiTow_BoostFactor_tt")
    boostSel:addItem("UI_MultiTow_BoostOff", false)
    boostSel:addItem("1.5x", false)
    boostSel:addItem("2x", false)
    boostSel:addItem("2.5x", false)
    boostSel:addItem("3x", false)
    boostSel:addItem("UI_MultiTow_BoostAuto", true)

    -- Zugbremse: 0 = gezogene Fahrzeuge bremsen nicht mit, 100 = so stark, als wuerde jemand darin selbst bremsen
    local brake = options:addSlider("brake" .. suffix, "UI_MultiTow_Brake", 0, 100, 5, 50, "UI_MultiTow_Brake_tt")
    -- Hoechstgeschwindigkeit ab 3 Fahrzeugen (0 = aus). Nur der Regler der gewaehlten Einheit ist aktiv.
    local speedKmh = options:addSlider("speedKmh" .. suffix, "UI_MultiTow_SpeedKmh", 0, 150, 5, 0, "UI_MultiTow_Speed_tt")
    local speedMph = options:addSlider("speedMph" .. suffix, "UI_MultiTow_SpeedMph", 0, 95, 5, 0, "UI_MultiTow_Speed_tt")
    -- Mehrverbrauch an Sprit: aus, gleichmaessig (+x % pro Fahrzeug) oder exponentiell (x % hoch Anzahl)
    local fuelMode = options:addComboBox("fuelMode" .. suffix, "UI_MultiTow_FuelMode", "UI_MultiTow_FuelMode_tt")
    fuelMode:addItem("UI_MultiTow_FuelOff", true)
    fuelMode:addItem("UI_MultiTow_FuelStatic", false)
    fuelMode:addItem("UI_MultiTow_FuelExp", false)
    local fuelPct = options:addSlider("fuelPercent" .. suffix, "UI_MultiTow_FuelPercent", 0, 100, 5, 20, "UI_MultiTow_FuelPercent_tt")
    -- Laerm fuer Zombies waehrend der Fahrt (Ketten laut, Stangen leiser)
    local noise = options:addTickBox("noise" .. suffix, "UI_MultiTow_Noise", true, "UI_MultiTow_Noise_tt")

    -- Prozent-Regler nur aktiv, wenn der Mehrverbrauch an ist
    fuelMode.onChange = function(_, selected)
        fuelPct:setEnabled(selected ~= 1)
    end

    return { max = maxVeh, boost = boostSel, brake = brake, speedKmh = speedKmh, speedMph = speedMph,
        fuelMode = fuelMode, fuelPct = fuelPct, noise = noise }
end

local carSec = addVehicleSection("UI_MultiTow_HeaderCar", "UI_MultiTow_SectionCar", "UI_MultiTow_SectionCarHint", "Car")
local truckSec = addVehicleSection("UI_MultiTow_HeaderTruck", "UI_MultiTow_SectionTruck", "UI_MultiTow_SectionTruckHint", "Truck")

-- Mithelfen nur, wenn bei PKW und LKW die Kraft-Erhoehung aus ist (Eintrag 1 = "Aus")
--   car/truck: gerade gewaehlte Eintraege (beim Anklicken), sonst die gespeicherten Werte
local function assistAllowed(car, truck)
    return (car or carSec.boost:getValue()) == 1 and (truck or truckSec.boost:getValue()) == 1
end
carSec.boost.onChange = function(_, selected) assistPower:setEnabled(assistAllowed(selected, nil)) end
truckSec.boost.onChange = function(_, selected) assistPower:setEnabled(assistAllowed(nil, selected)) end

-- ---- Debug (ganz unten) ----
--   +--------------------------------------------------+
--   | Debug                                            |
--   |   [ ] Debug-Optionen zeigen        <- immer da   |
--   |   - - - - - - - - - - - - - - - - - - - - - - -  |
--   |   [ ] Einrichtungsassistent ...    <- nur        |
--   |   [ ] ZombieBuddy-Warnung ...      <- sichtbar,  |
--   |                                       wenn oben  |
--   |                                       angehakt   |
--   +--------------------------------------------------+
--   >> WARUM ganz unten: Das Optionsmenue des Spiels kennt kein "Ausblenden". Weil darunter nichts
--      mehr kommt, koennen wir einfach alles ab der ersten Debug-Option verstecken (macht der Hub, Hub.setDebugVisible).
--   Der Einrichtungsassistent ueberspringt diesen ganzen Bereich (MultiTow.DEBUG_SECTION).
MultiTow.DEBUG_SECTION = "UI_MultiTow_SectionDebug"
options:addSeparator()
options:addTitle(MultiTow.DEBUG_SECTION)
local showDebug = options:addTickBox("showDebug", "UI_MultiTow_ShowDebug", false, "UI_MultiTow_ShowDebug_tt")
-- Ab hier: die versteckbaren Debug-Optionen. Die ERSTE davon markiert, ab welcher Hoehe versteckt wird.
local debugOptions = {
    -- Einrichtungsassistent (MultiTow_Setup.lua) beim naechsten Start im Hauptmenue noch einmal zeigen
    options:addTickBox("showSetup", "UI_MultiTow_ShowSetup", false, "UI_MultiTow_ShowSetup_tt"),
    -- Warnseite "ZombieBuddy ist nicht aktiv" im Assistenten zeigen, auch wenn ZombieBuddy laeuft.
    --   Wirkt wie "showSetup": beim naechsten Hauptmenue erscheint der Assistent, danach schaltet sich der Haken aus.
    options:addTickBox("debugZBWarning", "UI_MultiTow_DebugZBWarning", false, "UI_MultiTow_DebugZBWarning_tt"),
    -- Vorschau: Optionen, die den Java-Teil brauchen, rot zeigen, auch wenn ZombieBuddy laeuft (bleibt an, bis man ihn abhakt)
    options:addTickBox("debugRedOptions", "UI_MultiTow_DebugRedOptions", false, "UI_MultiTow_DebugRedOptions_tt"),
}
local debugRed = debugOptions[3]
-- Ein-/Ausblenden des Debug-Bereichs macht ab 0.14.0 der Hub (Mod "DO Utilities"): siehe Anmeldung ganz unten (debug = ...).

--- Sollen die Java-Optionen rot erscheinen?  (Java-Teil fehlt  ODER  Debug-Vorschau an)
--   Das Rot-Faerben selbst macht ab 0.14.0 der Hub (Anmeldung ganz unten: marks = ...).
--   selected: gerade angeklickter Wert der Vorschau (sonst der gespeicherte)
function MultiTow.javaMarksWanted(selected)
    if not MultiTow.javaLoaded() then return true end
    if selected ~= nil then return selected == true end
    return debugRed:getValue() == true
end

-- Vorschau-Haken wirkt sofort beim Anklicken: den Hub bitten, die Markierung "java" neu zu zeichnen
debugRed.onChange = function(_, selected)
    local hub = DofDRegistry and DofDRegistry.hub
    if hub and hub.refreshMarks then hub.refreshMarks(OPTIONS_ID, "java", MultiTow.javaMarksWanted(selected)) end
end



--- Werte eines PKW-/LKW-Abschnitts lesen.
--  Rueckgabe: Hoechstzahl Fahrzeuge, Zusatzkraft an?, fester Faktor (0 = automatisch)
local function readVehicleSection(sec)
    local maxVehicles = MAX_VALUES[sec.max:getValue()] or 0
    local boostValue = BOOST_VALUES[sec.boost:getValue()] or 0
    local boostOn = boostValue >= 0
    return maxVehicles, boostOn, boostOn and boostValue or 0
end

--- Ist mph gewaehlt? (selected = gerade gewaehlter Eintrag, sonst gespeicherter Wert)
local function isMph(selected)
    return (selected or speedUnit:getValue()) == UNIT_MPH
end

-- Nur den Tempo-Regler der gewaehlten Einheit aktiv schalten, Prozent-Regler nur bei Mehrverbrauch
local function updateEnabledSliders(unitSelected)
    local mph = isMph(unitSelected)
    for _, sec in ipairs({ carSec, truckSec }) do
        sec.speedKmh:setEnabled(not mph)
        sec.speedMph:setEnabled(mph)
        sec.fuelPct:setEnabled(sec.fuelMode:getValue() ~= 1)
    end
    assistPower:setEnabled(assistAllowed())
end
-- Dieselben Regeln fuer den Einrichtungsassistenten: ist diese Option gerade einstellbar?
-- get(id) liefert den aktuellen Wert einer anderen Option.
function MultiTow.optionEnabled(id, get)
    if string.find(id, "^speedKmh") then return get("speedUnit") ~= UNIT_MPH end
    if string.find(id, "^speedMph") then return get("speedUnit") == UNIT_MPH end
    local suffix = string.match(id, "^fuelPercent(%a+)$")
    if suffix then return get("fuelMode" .. suffix) ~= 1 end
    if id == "assistPower" then return get("boostModeCar") == 1 and get("boostModeTruck") == 1 end
    return true
end

speedUnit.onChange = function(_, selected)
    updateEnabledSliders(selected)
end

-- ---------------------------------------------------------------------------
-- Band-Anzeige: Schalter im Menue ODER Taste (halten bzw. umschalten)
-- ---------------------------------------------------------------------------
--   Drei Wege, die Baender einzuschalten - jeder reicht:
--     Haken "Belastung anzeigen"  ODER  Taste im Umschalt-Modus  ODER  Taste gerade gedrueckt (Halte-Modus)
--   applied = was zuletzt an den Java-Teil geschickt wurde (nur bei Aenderung erneut schicken)
local linkView = { toggled = false, holding = false, applied = nil }

local function updateLinkDisplay()
    local on = (MultiTow.Settings.showLinks or linkView.toggled or linkView.holding) and true or false
    if on ~= linkView.applied then
        linkView.applied = on
        if multiTowSetShowLinks then
            multiTowSetShowLinks(on)
        end
    end
end

--- Tippt der Spieler gerade im Chat? Dann soll die Taste K NICHT die Baender schalten.
local function isTyping()
    local ok, res = pcall(function()
        return ISChat and ISChat.instance and ISChat.instance.focused
    end)
    return ok and res and true or false
end

--- Eingestellte Taste (Zahl) oder nil, wenn keine Taste belegt ist
local function linkKeyCode()
    local k = linkKey:getValue()
    if k == nil or k == 0 then return nil end
    return k
end

-- Taste GEDRUECKT (einmal beim Herunterdruecken)
Events.OnKeyStartPressed.Add(function(key)
    local k = linkKeyCode()
    if not k or key ~= k then return end
    local p = getPlayer()
    if not p or isTyping() then return end
    if linkKeyMode:getValue() == LINK_MODE_TOGGLE then
        linkView.toggled = not linkView.toggled
        pcall(function()
            p:setHaloNote(getText(linkView.toggled and "UI_MultiTow_LinksOn" or "UI_MultiTow_LinksOff"), 255, 255, 255, 150)
        end)
    else
        linkView.holding = true
    end
    updateLinkDisplay()
end)

-- Taste losgelassen: im Halte-Modus Anzeige wieder aus
Events.OnKeyPressed.Add(function(key)
    local k = linkKeyCode()
    if not k or key ~= k then return end
    if linkView.holding then
        linkView.holding = false
        updateLinkDisplay()
    end
end)

-- ############################################################################
-- ##  2. WERTE UEBERNEHMEN
-- ############################################################################
--  Wird aufgerufen: beim Klick auf "Uebernehmen", im Hauptmenue und beim Laden eines Spielstands.
--  Reihenfolge:   persoenliche Einstellungen  ->  [MP? dann Server-Regeln, fertig]  ->  Regeln aus diesem Menue
local function applySettings()
    local maxCar, boostCarOn, boostCarFixed = readVehicleSection(carSec)
    local maxTruck, boostTruckOn, boostTruckFixed = readVehicleSection(truckSec)

    -- Kettengeraeusche sind eine persoenliche Einstellung, auch im Multiplayer
    MultiTow.Settings.sounds = sounds:getValue() and true or false
    -- Band-Anzeige ist ebenfalls persoenlich (nur Anzeige auf diesem PC)
    MultiTow.Settings.showLinks = showLinks:getValue() and true or false
    if linkKeyMode:getValue() ~= LINK_MODE_TOGGLE then
        linkView.toggled = false
    end
    updateLinkDisplay()
    MultiTow.Settings.showLinksNear = showLinksNear:getValue() and true or false
    if multiTowSetShowLinksNear then
        multiTowSetShowLinksNear(MultiTow.Settings.showLinksNear)
    end
    MultiTow.Settings.remarks = remarks:getValue() and true or false
    -- sichtbare Ketten/Stangen: 1 = Bild, 0 = aus (2 = 3D-Modell ist vorbereitet, aber noch nicht gebaut)
    MultiTow.Settings.showChains = showChains:getValue() and true or false
    if multiTowSetLinkStyle then
        -- 2 = 3D-Kette (ab Java 0.16; Stangen und ohne "3D-Gegenstaende am Boden" automatisch Bild), 0 = aus
        multiTowSetLinkStyle(MultiTow.Settings.showChains and 2 or 0)
    end
    MultiTow.Settings.hazardStyle = hazardStyle:getValue() or 3
    MultiTow.Settings.hazardScope = hazardScope:getValue() or 1
    if MultiTow.applyHazardSettings then MultiTow.applyHazardSettings() end

    -- Zug-Anzeige ist persoenlich
    MultiTow.Settings.hud = hudOn:getValue() and true or false
    MultiTow.Settings.hudPos = hudPos:getValue() or 2
    for key, opt in pairs(hudLines) do
        MultiTow.Settings["hud" .. key] = opt:getValue() and true or false
    end
    if MultiTow.hudApplySettings then MultiTow.hudApplySettings() end

    -- Multiplayer: die Regeln kommen aus den Sandbox-Optionen des Servers, nicht aus diesem Menue
    if MultiTow.isMP() then
        MultiTow.applySandbox()
        return
    end

    MultiTow.Settings.enabled = enabled:getValue() and true or false
    MultiTow.Settings.requireHook = requireHook:getValue() and true or false
    MultiTow.Settings.maxCar = maxCar
    MultiTow.Settings.maxTruck = maxTruck
    MultiTow.Settings.wear = wearSel:getValue() or 3
    MultiTow.Settings.cargo = cargoSel:getValue() or 5
    MultiTow.Settings.hazardAuto = hazardAuto:getValue() and true or false

    -- Bremse, Tempolimit, Sprit, Laerm
    local S = MultiTow.Settings
    local mph = isMph()
    S.speedUnit = mph and "mph" or "kmh"
    S.brakeCar = tonumber(carSec.brake:getValue()) or 50
    S.brakeTruck = tonumber(truckSec.brake:getValue()) or 50
    S.speedCar = tonumber((mph and carSec.speedMph or carSec.speedKmh):getValue()) or 0
    S.speedTruck = tonumber((mph and truckSec.speedMph or truckSec.speedKmh):getValue()) or 0
    S.fuelModeCar = carSec.fuelMode:getValue() or 1
    S.fuelModeTruck = truckSec.fuelMode:getValue() or 1
    S.fuelPctCar = tonumber(carSec.fuelPct:getValue()) or 20
    S.fuelPctTruck = tonumber(truckSec.fuelPct:getValue()) or 20
    S.noiseCar = carSec.noise:getValue() and true or false
    S.noiseTruck = truckSec.noise:getValue() and true or false
    -- Mithelfen: nur wenn die Kraft-Erhoehung bei PKW und LKW aus ist, sonst 0 (aus)
    S.assist = (not boostCarOn and not boostTruckOn) and (tonumber(assistPower:getValue()) or 0) or 0
    MultiTow.applyTrainSettings()
    MultiTow.log("Train:", "brake", S.brakeCar, S.brakeTruck, "speed", S.speedCar, S.speedTruck, S.speedUnit,
        "fuel", S.fuelModeCar, S.fuelPctCar, S.fuelModeTruck, S.fuelPctTruck, "noise", tostring(S.noiseCar), tostring(S.noiseTruck),
        "assist", S.assist)

    if multiTowConfigure then
        multiTowConfigure(MultiTow.Settings.enabled, MultiTow.Settings.requireHook,
            maxCar, boostCarOn, boostCarFixed,
            maxTruck, boostTruckOn, boostTruckFixed)
    end
    MultiTow.log("Settings:", tostring(MultiTow.Settings.enabled), "hook:", tostring(MultiTow.Settings.requireHook),
        "cars:", maxCar, tostring(boostCarOn), boostCarFixed,
        "trucks:", maxTruck, tostring(boostTruckOn), boostTruckFixed)
end

-- Das Spiel ruft options.apply auf, wenn man im Optionsmenue "Uebernehmen" klickt
options.apply = applySettings

Events.OnMainMenuEnter.Add(applySettings) -- beim Spielstart des Hauptmenues
Events.OnGameStart.Add(applySettings)     -- beim Laden eines Spielstands


-- ############################################################################
-- ##  3. SEITE IM HUB "DO Utilities" (frueher: eigener Reiter "Road Train")
-- ############################################################################
--
--   Frueher: [Anzeige] [Audio] ... [Mods: alle anderen] [Road Train: nur wir]
--   Jetzt:   [Anzeige] [Audio] ... [Mods: alle anderen] [DO Utilities: Karten aller Mods von DofD]
--            Ein Klick auf die Karte "Multi-Vehicle Towing" zeigt unsere Optionen auf derselben Seite.
--
-- Den Rahmen (Seite "DO Utilities", Karten, Zurueck-Knopf, Einhaengen in das Spiel) macht der Hub - ab 0.14.0 die eigene Mod
-- "DO Utilities" (DOUtilities.lua, mod.info: require=\DOUtilities). Er baut unsere Optionen mit der Funktion des Spiels auf eine Teilseite.
-- Kopfbilder, Debug-Bereich zum Ein-/Ausklappen und rote Markierungen macht ab 0.14.0 der Hub (Felder in der Anmeldung).
-- Hier steht nur noch, was UNSERE Seite besonders macht: Hinweis fuer den Java-Teil und ein Fehler-Umgehen bei der Tastenwahl.
-- Speichern/Laden der Werte (ModOptions.ini) laeuft unveraendert ueber das Spiel.

--- Baut unsere Optionsseite. Der Hub ruft das auf, wenn er die Seite "DO Utilities" zusammensetzt.
--  screen    der Optionsbildschirm (MainOptions)
--  runBuild  ruft die Funktion des Spiels auf, die unsere Optionen als Seite baut
--            (der Hub hat vorher PZAPI.ModOptions.Data auf unseren Eintrag gesetzt und danach macht er es wieder rueckgaengig)
local function buildOptionsPage(screen, runBuild)
    -- Kopfbilder (DOHUB_IMAGE:...) setzt der Hub selbst ein. Wir ergaenzen nur den Hinweis "rote Optionen brauchen
    -- ZombieBuddy" und geben alles andere an die vorige Funktion weiter (die des Hubs).
    local previousAddDescription = screen.addDescription or MainOptions.addDescription
    screen.addDescription = function(panel, x, y, text)
        -- nur wenn noetig, dann in Rot (<RGB:...> = Farbe im Rich-Text)
        local note = type(text) == "string" and text:match("^MULTITOW_JAVANOTE:(.+)$") or nil
        if note then
            -- Sonderfall: Java-Teil wurde waehrend des Spiels nachgeladen -> Hinweis "bitte neu starten" (orange)
            if MultiTow.javaRestartNeeded() then
                return previousAddDescription(panel, x, y, "<RGB:1,0.65,0.15> " .. getText("UI_MultiTow_JavaRestartNote"))
            end
            if MultiTow.javaMarksWanted() then
                return previousAddDescription(panel, x, y, "<RGB:1,0.35,0.35> " .. note)
            end
            return   -- Java-Teil da: Zeile ganz weglassen
        end
        return previousAddDescription(panel, x, y, text)
    end

    runBuild()
    screen.addDescription = previousAddDescription   -- zurueck an den Hub (er raeumt danach selbst auf)

    -- Die gespeicherten Werte sind jetzt geladen: passende Regler aktiv/grau schalten
    updateEnabledSliders()
    -- Debug-Bereich und rote Markierungen richtet der Hub NACH dieser Funktion ein (Anmeldung unten).
    -- Fehler im Spiel umgehen: Beim Tastenwechsel sucht das Spiel den Eintrag ueber den Namen des Knopfes
    -- (bei Mods der Textschluessel "UI_MultiTow_LinkKey"), vergleicht ihn aber mit der uebersetzten
    -- Beschriftung ("Link stress hotkey"). Findet nichts -> Absturz. Wir geben dem Knopf die Beschriftung als Namen.
    local el = linkKey.element
    if el and el.btn and el.txt then
        el.btn.internal = el.txt:getName()
    end
end

-- Beim Hub anmelden (ab Hub-Version 5): wir tragen uns in die gemeinsame Liste ein. So weiss die Seite "DO Utilities", dass diese
-- Mod installiert ist (und wie ihre Seite gebaut wird). Den Hub selbst brauchen wir dafuer nicht - er kann vor oder nach uns
-- geladen werden und liest die Liste erst, wenn er die Seite baut.
DofDRegistry = DofDRegistry or {}
DofDRegistry.mods = DofDRegistry.mods or {}
DofDRegistry.mods[OPTIONS_ID] = {
    id = OPTIONS_ID,
    name = "Multi-Vehicle Towing",
    version = "0.15.0",
    build = buildOptionsPage,
    -- (ab Hub-Version 8) Debug-Bereich ganz unten: "showDebug" blendet alles ab "showSetup" ein/aus
    debug = { toggle = "showDebug", first = "showSetup" },
    -- (ab Hub-Version 8) Optionen, die den Java-Teil brauchen: rot, solange er fehlt (oder die Debug-Vorschau an ist)
    marks = {
        { name = "java", ids = MultiTow.JAVA_OPTIONS, color = { 1.0, 0.35, 0.35 },
          active = function() return MultiTow.javaMarksWanted() end },
    },
}
