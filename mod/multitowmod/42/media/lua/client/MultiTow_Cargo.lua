--[[==========================================================================
    MultiTow_Cargo.lua                                         [ client ]
  ----------------------------------------------------------------------------
    Multi-Vehicle Towing: Ladungsgewicht
    (Option "Ladungsgewicht" im Bereich Gameplay)

    DAS PROBLEM IM SPIEL:
      Das Spiel rechnet das Gewicht eines Fahrzeugs nur beim Laden aus
      (Leergewicht + alles, was drin liegt) und aendert es danach nicht mehr,
      auch wenn man den Kofferraum voll- oder leerraeumt.

    WAS DIESE DATEI MACHT:
      Fuer Fahrzeuge in einem Zug rechnen wir alle 2 Sekunden neu:
          Gewicht = Leergewicht + eingestellter Anteil der Ladung (25/50/75/100 %)
      Schwerere Anhaengsel ziehen staerker an den Verbindungen, bremsen und
      beschleunigen traeger - das macht die Physik des Spiels von selbst,
      sobald das Gewicht stimmt.

    WO LAEUFT DAS?
      Auf dem Rechner des Fahrers (dort rechnet die Physik).
      "Aus" = wir fassen nichts an, das Spiel rechnet wie immer.
============================================================================]]

require "MultiTow_Common"   -- trainMassOf, emptyMass, cargoWeight, Settings
require "MultiTow_Train"    -- trainVehicles

-- ---- Einstellungen dieser Datei -------------------------------------------
local INTERVAL_MS = 2000    -- alle 2000 ms = 2 Sekunden neu rechnen (oefter waere unnoetige Arbeit)
local nextRun = 0           -- Zeitpunkt (in ms), ab dem wieder gerechnet wird
local changed = {} -- Fahrzeug -> true: Gewicht von uns gesetzt (spaeter wieder zuruecksetzen)

--- Gewicht eines Fahrzeugs setzen, aber nur wenn es sich wirklich aendert.
--  m wird auf ganze Kilogramm gerundet und ist nie kleiner als 1
--  (ein Gewicht von 0 wuerde die Physik durcheinanderbringen).
local function setMass(veh, m)
    m = math.max(1, math.floor(m + 0.5))
    pcall(function()
        -- >> WARUM der Vergleich: setMass loest in der Physik eine Neuberechnung aus - das sparen wir uns bei gleichem Wert
        if math.abs(veh:getMass() - m) >= 1 then veh:setMass(m) end
    end)
end


-- ############################################################################
-- ##  JEDEN SPIEL-TICK: ALLE 2 SEKUNDEN DIE GEWICHTE ANPASSEN
-- ############################################################################
Events.OnTick.Add(function()
    -- -> 1. Nur alle 2 Sekunden wirklich arbeiten
    local now = getTimestampMs()
    if now < nextRun then return end
    nextRun = now + INTERVAL_MS

    -- -> 2. Ist die Option an? CARGO_PCT[1] ist "Aus" (nil), alles andere ein Prozentwert
    local active = MultiTow.Settings.enabled and MultiTow.CARGO_PCT[tonumber(MultiTow.Settings.cargo) or 1] ~= nil

    -- -> 3. Alle Fahrzeuge der Zuege einsammeln, in denen gerade ein Spieler auf diesem PC sitzt
    --       (getNumActivePlayers > 1 nur bei geteiltem Bildschirm)
    local inTrain = {}
    if active then
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            local veh = p and p:getVehicle()
            if veh and (veh:getVehicleTowing() or veh:getVehicleTowedBy()) then   -- Fahrzeug gehoert zu einem Zug
                for _, v in ipairs(MultiTow.trainVehicles(veh)) do
                    inTrain[v] = true
                    setMass(v, MultiTow.trainMassOf(v))
                    changed[v] = true                -- merken: dieses Gewicht haben WIR gesetzt
                end
            end
        end
    end

    -- -> 4. Aufraeumen
    -- nicht mehr im Zug (oder Option aus): Gewicht wie das Spiel (Leergewicht + ganze Ladung)
    for v in pairs(changed) do
        if not inTrain[v] then
            setMass(v, MultiTow.emptyMass(v) + MultiTow.cargoWeight(v))
            changed[v] = nil
        end
    end
end)
