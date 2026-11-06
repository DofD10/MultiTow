--[[==========================================================================
    MultiTow_Noise.lua                                [ Einzelspieler + Server ]
  ----------------------------------------------------------------------------
    Multi-Vehicle Towing: Laerm waehrend der Fahrt
    (Option "Laerm lockt Zombies an", getrennt fuer PKW und LKW)

    Ketten rasseln und locken Zombies an, Abschleppstangen sind deutlich leiser.
    Alle 2 Sekunden macht jede Verbindung eines fahrenden Zuges ein Geraeusch
    fuer Zombies. Man HOERT es nicht - es ist nur fuer die Zombie-KI.
    Je schneller der Zug, desto weiter reicht es:

        Reichweite in Feldern
         40 |                               ........ Kette (max 40)
            |                    ..........
         20 |.........  <- Kette: 20 + Tempo/4
         15 |                           ------------ Stange (max 15)
          8 |---------  <- Stange: 8 + Tempo/10
            +-----------------------------------------> km/h
            0        20        40        60        80

    WO:  Im Einzelspieler und im Multiplayer auf dem Server (dort "leben" die
         Zombies), NICHT auf MP-Clients - deshalb die erste Zeile unten.
============================================================================]]

-- !! ACHTUNG: Auf einem Multiplayer-Client sofort aufhoeren. Zombies werden dort nicht gesteuert;
--    Laerm vom Client wuerde nichts bewirken (oder doppelt zaehlen).
if isClient() then return end

require "MultiTow_Common"
require "MultiTow_Train"

local INTERVAL_MS = 2000    -- alle 2 Sekunden ein "Rassel-Geraeusch"
local MIN_KMH = 5           -- darunter (fast Stillstand) macht der Zug keinen Laerm
local lastPos = {} -- Fahrzeug-ID -> { x, y, t }
local nextRun = 0

--- Reichweite des Geraeuschs in Feldern.
--  bar = true bei Abschleppstange, sonst Kette;  kmh = Geschwindigkeit des Zuges
local function radiusFor(bar, kmh)
    if bar then
        return math.min(15, 8 + kmh / 10)
    end
    return math.min(40, 20 + kmh / 4)
end

-- Geschwindigkeit aus der Positionsaenderung (funktioniert auch auf dem Server, wo die Physik nicht laeuft)
--   >> WARUM nicht einfach getCurrentSpeedKmHour()? Auf dem Server wird nicht gefahren, nur
--      die Position kommt vom Fahrer an. Deshalb: Strecke seit der letzten Messung / Zeit.
--   Rechnung:  Felder (= Meter) pro Sekunde * 3.6 = km/h
local function speedKmh(veh, now)
    local id = veh:getId()
    local x, y = veh:getX(), veh:getY()
    local last = lastPos[id]
    lastPos[id] = { x = x, y = y, t = now }  -- fuer das naechste Mal merken
    if not last or now <= last.t then return 0 end   -- erste Messung: noch kein Vergleich moeglich
    local dx, dy = x - last.x, y - last.y
    return math.sqrt(dx * dx + dy * dy) / ((now - last.t) / 1000) * 3.6
end

--- Ein Geraeusch an jedem gezogenen Fahrzeug des Zuges.
--  player = der Fahrer (das Spiel will wissen, "wer" den Laerm macht)
local function noiseForTrain(player, head, now)
    local kmh = speedKmh(head, now)
    if kmh < MIN_KMH then return end
    if MultiTow.trainSetting(head, "noiseCar", "noiseTruck") == false then return end   -- Option fuer diesen Zugtyp aus
    local v = head:getVehicleTowing()
    local n = 0
    while v and n < 64 do
        n = n + 1
        local r = math.floor(radiusFor(MultiTow.isBarLink(v), kmh))
        pcall(function()
            -- addSound(Verursacher, x, y, Etage, Reichweite, Lautstaerke) - Spiel-Funktion fuer Zombie-Geraeusche
            addSound(player, math.floor(v:getX()), math.floor(v:getY()), math.floor(v:getZ()), r, r)
        end)
        v = v:getVehicleTowing()
    end
end

--- Taktgeber: jeder Tick, gearbeitet wird alle 2 Sekunden.
local function onTick()
    local now = getTimestampMs()
    if now < nextRun then return end
    nextRun = now + INTERVAL_MS
    if not MultiTow.Settings.enabled then return end
    local seen = {}          -- jeden Zug nur einmal (bei geteiltem Bildschirm koennten zwei Spieler im selben sitzen)
    for _, p in ipairs(MultiTow.relevantPlayers()) do
        local veh = p:getVehicle()
        -- nur der Fahrer eines Zugfahrzeugs, das mindestens zwei Fahrzeuge zieht
        -- (= ab 3 Fahrzeugen im Zug; normales Abschleppen bleibt wie im Spiel)
        if veh and not seen[veh] and veh:getDriver() == p and veh:getVehicleTowedBy() == nil
            and MultiTow.towedCount(veh) >= 2 then
            seen[veh] = true
            noiseForTrain(p, veh, now)
        end
    end
end

Events.OnTick.Add(onTick)
