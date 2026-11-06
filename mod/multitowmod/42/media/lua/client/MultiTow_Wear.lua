--[[==========================================================================
    MultiTow_Wear.lua                                          [ client ]
  ----------------------------------------------------------------------------
    Multi-Vehicle Towing: Verschleiss der Verbindungen
    (Option "Verschleiss" im Bereich Gameplay)

    IDEE:
      Jede Sekunde schaut der Rechner des Fahrers (dort laeuft die Physik), wie
      stark jede Verbindung des Zuges belastet ist (dieselbe Rechnung wie das
      farbige Band) und zieht etwas vom Zustand der Verbindung ab.

    FORMEL (steht in MultiTow_Common.lua -> wearPerSecond):
      Verlust pro Sekunde = Stufe * Art * (0.01 + Belastung^2)
                            |       |       |      '-- stark belastet = viel mehr Verschleiss
                            |       |       '-- etwas Verschleiss gibt es immer
                            |       '-- Kette 1.0, Abschleppstange 0.3
                            '-- Aus 0 / Niedrig 0.5 / Normal 1 / Hoch 2 / Sehr hoch 4

    WANN:  Nur waehrend der Fahrt (ab 3 km/h) oder bei starkem Ruck (Belastung > 50 %).
    ENDE:  Bei 0 % reisst die Verbindung.

    [SP] Einzelspieler: sofort anwenden.
    [MP] Multiplayer:   alle 5 Sekunden an den Server melden, der entscheidet
                        (server/MultiTow_Server.lua -> Server.wear).
============================================================================]]

require "MultiTow_Common"
require "MultiTow_Train"

local INTERVAL_MS = 1000    -- jede Sekunde messen
local SEND_MS = 5000        -- [MP] alle 5 Sekunden das Gesammelte an den Server schicken
local nextRun, nextSend = 0, 0
local pending = {} -- Fahrzeug-ID -> angesammelter Verlust (nur Multiplayer)


-- ############################################################################
-- ##  EINEN ZUG DURCHGEHEN
-- ############################################################################

--- Verschleiss fuer alle Verbindungen hinter dem Zugfahrzeug "head".
--  seconds = wie viel Zeit seit der letzten Messung vergangen ist (hier immer 1)
--
--   head ===> v1 ===> v2 ===> v3          jede "===>" ist eine Verbindung;
--             ^        ^        ^          sie "gehoert" dem Fahrzeug DAHINTER
--             |        |        |          (dort stehen auch Zustand und Art)
local function wearTrain(head, seconds)
    local moving = math.abs(head:getCurrentSpeedKmHour()) >= 3   -- abs: rueckwaerts zaehlt auch
    local v = head:getVehicleTowing()
    local n = 0
    while v and n < 64 do                    -- n < 64 = Notbremse, falls die Kette je einen Kreis bildet
        n = n + 1
        local nextV = v:getVehicleTowing()   -- schon jetzt merken: die Verbindung koennte gleich reissen
        if MultiTow.linkWears(v) and multiTowLinkStress then
            local s = multiTowLinkStress(v)  -- Belastung 0..1 aus dem Java-Teil, -1 = unbekannt
            if s and s >= 0 and (moving or s > 0.5) then
                local loss = MultiTow.wearPerSecond(v, s) * seconds
                if loss > 0 then
                    if isClient() then
                        -- [MP] nur sammeln, der Server entscheidet
                        local id = v:getId()
                        pending[id] = (pending[id] or 0) + loss
                    else
                        -- [SP] direkt abziehen (und ggf. reissen lassen)
                        MultiTow.applyWear(v, loss)
                    end
                end
            end
        end
        v = nextV
    end
end

--- [MP] Gesammelten Verschleiss als eine Nachricht an den Server schicken und den Zwischenspeicher leeren.
--  Format der Nachricht:  { links = { {r = Fahrzeug-ID, l = Verlust}, ... } }
local function sendPending(player)
    local list = {}
    for id, loss in pairs(pending) do
        table.insert(list, { r = id, l = loss })
    end
    pending = {}
    if #list > 0 then
        sendClientCommand(player, "MultiTow", "wear", { links = list })
    end
end


-- ############################################################################
-- ##  TAKTGEBER (jeder Spiel-Tick, gearbeitet wird aber nur einmal pro Sekunde)
-- ############################################################################
Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now < nextRun then return end
    nextRun = now + INTERVAL_MS
    -- Gruende, gar nichts zu tun:
    if not MultiTow.Settings.enabled then return end                                             -- Mod aus
    if (MultiTow.WEAR_FACTORS[tonumber(MultiTow.Settings.wear) or 1] or 0) <= 0 then return end  -- Verschleiss "Aus"
    if isClient() and not MultiTow.serverReady then return end                                   -- [MP] Server ohne Java-Teil
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        local head = MultiTow.drivenTrainHead(p)   -- nur wer ein Zugfahrzeug FAEHRT, misst den Verschleiss
        if head then
            wearTrain(head, INTERVAL_MS / 1000)
            if isClient() and now >= nextSend then
                nextSend = now + SEND_MS
                sendPending(p)
            end
        end
    end
end)
