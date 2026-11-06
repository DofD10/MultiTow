--[[==========================================================================
    MultiTow_Train.lua                                  [ client + server ]
  ----------------------------------------------------------------------------
    Kleine Helfer fuer GANZE Zuege (nicht einzelne Verbindungen).
    Benutzt von: Laerm, Spritverbrauch, Verschleiss, Ladungsgewicht,
                 Zug-Anzeige, Warnblinker, Server.

    Begriffe, die ueberall in der Mod vorkommen:

       Zugfahrzeug ("head")       gezogene Fahrzeuge
       [ A ] ======> [ B ] ======> [ C ] ======> [ D ]
         |  getVehicleTowing() ->    |
         |  <- getVehicleTowedBy()   |
       towedCount(A) = 3        trainVehicles(C) = {A, B, C, D}
============================================================================]]

require "MultiTow_Common"

-- Kleine Helfer fuer ganze Zuege (Laerm und Spritverbrauch)

--- Anzahl der gezogenen Fahrzeuge hinter diesem Fahrzeug.
--  Beispiel: A zieht B zieht C  ->  towedCount(A) = 2,  towedCount(B) = 1
function MultiTow.towedCount(head)
    local n, v = 0, head and head:getVehicleTowing()
    while v and n < 64 do                    -- 64 = Sicherheitsgrenze gegen Endlosschleifen
        n = n + 1
        v = v:getVehicleTowing()
    end
    return n
end

--- Einstellungen fuer diesen Zug: Typ des Zugfahrzeugs (PKW oder LKW) entscheidet.
--  carKey / truckKey = Namen in MultiTow.Settings, z.B. "noiseCar" / "noiseTruck"
--  >> WARUM das Zugfahrzeug? Es zieht den ganzen Zug - ob hinten ein PKW haengt, ist egal.
function MultiTow.trainSetting(head, carKey, truckKey)
    if MultiTow.isTruck(head) then
        return MultiTow.Settings[truckKey]
    end
    return MultiTow.Settings[carKey]
end

--- Alle Spieler, die auf diesem Rechner "zaehlen": Server = alle online, Einzelspieler = lokale Spieler.
--  (Lokale Spieler gibt es mehrere nur bei geteiltem Bildschirm.)
function MultiTow.relevantPlayers()
    local list = {}
    if isServer() then
        local players = getOnlinePlayers()
        if players then
            for i = 0, players:size() - 1 do table.insert(list, players:get(i)) end
        end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then table.insert(list, p) end
        end
    end
    return list
end

--- Alle Fahrzeuge eines Zuges von vorne nach hinten (Zugfahrzeug zuerst).
--  anyVehicle darf IRGENDEIN Fahrzeug des Zuges sein - wir laufen erst ganz nach vorne.
function MultiTow.trainVehicles(anyVehicle)
    local list = {}
    local v = MultiTow.getHead(anyVehicle)   -- nach vorne bis zum Zugfahrzeug
    while v and #list < 64 do
        table.insert(list, v)
        v = v:getVehicleTowing()             -- und dann Stueck fuer Stueck nach hinten
    end
    return list
end

--- Fahrzeug, in dem ein lokaler Spieler am Steuer eines Zuges sitzt (Zugfahrzeug mit mindestens einem Anhaengsel), sonst nil.
--  Drei Bedingungen, alle muessen stimmen:
--    1. der Spieler sitzt in einem Fahrzeug UND auf dem Fahrersitz
--    2. das Fahrzeug wird selbst NICHT gezogen (sonst waere es nicht vorne)
--    3. es zieht etwas (sonst ist es kein Zug)
function MultiTow.drivenTrainHead(player)
    local veh = player and player:getVehicle()
    if not veh or veh:getDriver() ~= player then return nil end
    if veh:getVehicleTowedBy() ~= nil or veh:getVehicleTowing() == nil then return nil end
    return veh
end


-- ############################################################################
-- ##  SPRITVERBRAUCH
-- ############################################################################

-- Spritverbrauch-Faktor des Zugfahrzeugs (auch fuer die Zug-Anzeige, deshalb hier und nicht in server/)
--   mode: 1 = aus, 2 = gleichmaessig, 3 = exponentiell; percent = Mehrverbrauch pro weiterem Fahrzeug; towed = gezogene Fahrzeuge
--
--   Beispiel mit 20 %:            k = towed - 1 (das erste gezogene Fahrzeug ist "normales Abschleppen")
--     towed | gleichmaessig 1+p*k | exponentiell (1+p)^k
--     ------+---------------------+---------------------
--       1   |       1.00          |       1.00
--       2   |       1.20          |       1.20
--       4   |       1.60          |       1.73
--       7   |       2.20          |       2.99
function MultiTow.fuelMultiplier(mode, percent, towed)
    local k = (tonumber(towed) or 0) - 1
    local p = (tonumber(percent) or 0) / 100
    if k < 1 or p <= 0 then return 1 end    -- bis 1 gezogenes Fahrzeug: kein Mehrverbrauch
    if mode == 2 then return 1 + p * k end
    if mode == 3 then return (1 + p) ^ k end
    return 1
end

--- Faktor fuer einen bestimmten Zug (Einstellungen je nach Typ des Zugfahrzeugs).
function MultiTow.trainFuelMultiplier(head)
    local mode = tonumber(MultiTow.trainSetting(head, "fuelModeCar", "fuelModeTruck")) or 1
    local pct = MultiTow.trainSetting(head, "fuelPctCar", "fuelPctTruck")
    return MultiTow.fuelMultiplier(mode, pct, MultiTow.towedCount(head))
end
