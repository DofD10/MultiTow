--[[==========================================================================
    MultiTow_Server.lua                              [ nur Multiplayer-Server ]
  ----------------------------------------------------------------------------
    Multi-Vehicle Towing: Multiplayer-Server

    Im Multiplayer entscheidet der Server, wer an wem haengt. Die Clients
    schicken nur Wuensche ("attach", "detach", ...), der Server prueft die
    Regeln (Sandbox-Optionen), nimmt bzw. gibt den Haken und kuppelt.
    Der Java-Teil (MultiTowCore) meldet das Kuppeln dann per Netzwerkpaket an
    alle Spieler.

        Spieler-PC                         Server
        ----------                         ------
        "attach" a=12 b=13  ------------>  Server.attach()
                                             pruefen: nah genug? frei? zu lang?
                                             doAttach() -> Java kuppelt
        "fail" / Ton / Spruch  <---------  reply(...)

    Im Einzelspieler laeuft diese Datei zwar mit, macht aber nichts
    (isServer() ist dort false).
============================================================================]]

if not isServer() then return end

require "MultiTow_Common"
require "MultiTow_Train"

local Server = {}   -- alle Befehle, die ein Client schicken darf (Name = Befehl)

-- hinteres Fahrzeug (ID) -> { player = Spieler, time = ms }: wer hat abgekuppelt und bekommt den Haken zurueck?
local pendingReturn = {}
local PENDING_MS = 10000      -- so lange (10 s) wartet der Server auf das RETURN-Ereignis des Java-Teils
-- maximaler Abstand Spieler <-> Fahrzeug (in Feldern), wie im Original beim Ankuppeln
local MAX_DIST = 10

local function now()
    return getTimestampMs()
end

--- Antwort an genau EINEN Spieler schicken (kommt in client/MultiTow_Events.lua -> ServerCommands an)
local function reply(player, command, args)
    sendServerCommand(player, "MultiTow", command, args or {})
end

--- Ablehnung: ins Log schreiben und dem Spieler eine rote Meldung schicken.
--  key  = Textschluessel der Meldung,  why = Grund fuers Log (Englisch),  item = Gegenstand fuer %1
local function fail(player, key, why, item)
    MultiTow.log("SERVER refused", tostring(player and player:getUsername()), tostring(why or key))
    reply(player, "fail", { key = key, item = item })
end

--- Steht der Spieler nah genug am Fahrzeug? (Gegen Mogeln: kuppeln aus 100 m Entfernung)
--  >> WARUM ohne Wurzel: dx^2 + dy^2 <= MAX^2 ist dasselbe wie Abstand <= MAX, nur schneller.
local function isNear(player, veh)
    local dx = player:getX() - veh:getX()
    local dy = player:getY() - veh:getY()
    return dx * dx + dy * dy <= MAX_DIST * MAX_DIST
end

local function vid(v)
    if v then return v:getId() end
    return "nil"
end

--- Zusatzdaten (modData) eines Fahrzeugs an alle Spieler schicken
local function transmitVehicleModData(veh)
    if veh then pcall(function() veh:transmitModData() end) end
end

-- ---------------------------------------------------------------------------
-- Befehle der Clients
-- ---------------------------------------------------------------------------

-- Anmeldung: Antwort mit der Java-Version des Servers (nil = kein Java-Teil, dann bietet der Client nichts an)
function Server.hello(player, args)
    local core = multiTowCoreVersion and multiTowCoreVersion() or nil
    MultiTow.log("SERVER hello from", player:getUsername(), "client core:", tostring(args and args.core),
        "server core:", tostring(core))
    reply(player, "hello", { core = core })
end

--- Wunsch: Fahrzeug a soll Fahrzeug b ziehen.
--  args = { a = ID vorne, b = ID hinten, attA, attB = Kupplungspunkte, link = "chain"/"bar" }
--  Pruefungen der Reihe nach - die erste, die nicht passt, lehnt ab:
function Server.attach(player, args)
    -- 1) Java-Teil auf dem Server da?
    if not multiTowCoreVersion then
        return fail(player, "UI_MultiTow_ServerJavaMissing", "no java part on server")
    end
    -- 2) Mod in den Sandbox-Optionen an?
    if not MultiTow.Settings.enabled then
        return fail(player, "UI_MultiTow_Disabled", "mod disabled in sandbox options")
    end
    -- 3) Gibt es beide Fahrzeuge (und sind es zwei verschiedene)?
    local a = args and getVehicleById(tonumber(args.a) or -1)
    local b = args and getVehicleById(tonumber(args.b) or -1)
    if not a or not b or a == b then
        return fail(player, "UI_MultiTow_ActionFailed", "vehicle not found")
    end
    -- 4) Steht der Spieler bei beiden?
    if not isNear(player, a) or not isNear(player, b) then
        return fail(player, "UI_MultiTow_ActionFailed", "too far away")
    end
    -- 5) Ist hinten an a und vorne an b noch frei?
    if a:getVehicleTowing() ~= nil or b:getVehicleTowedBy() ~= nil then
        return fail(player, "UI_MultiTow_ActionFailed", "hitch already in use")
    end
    -- 6) Wuerde ein Kreis entstehen?  (A zieht B zieht C zieht A ...)
    if MultiTow.isAlreadyInSameChain(a, b) then
        return fail(player, "UI_MultiTow_ActionFailed", "same chain")
    end
    -- 7) Zug zu lang?
    if not MultiTow.isTrainLengthAllowed(a, b) then
        return fail(player, "UI_MultiTow_TooLong", "train too long")
    end
    -- 8) Stange an einem echten Anhaenger geht nicht
    local linkType = (args.link == "bar") and "bar" or "chain"
    if linkType == "bar" and not MultiTow.canUseBar(a, b) then
        return fail(player, "UI_MultiTow_ActionFailed", "tow bar not possible with a trailer")
    end
    local attA = args.attA or MultiTow.findAttachmentName(a, true)
    local attB = args.attB or MultiTow.findAttachmentName(b, false)
    MultiTow.log("SERVER attach", player:getUsername(), vid(a), "->", vid(b), attA, attB, linkType)
    -- -> alles ok: dieselbe Funktion wie im Einzelspieler (prueft Gegenstand, kuppelt, nimmt Gegenstand)
    local ok, failKey = MultiTow.doAttach(player, a, b, attA, attB, linkType)
    if not ok then
        return fail(player, failKey, "attach failed: " .. tostring(failKey),
            linkType == "bar" and MultiTow.TOWBAR_TYPE or MultiTow.HOOK_TYPE)
    end
end

--- Wunsch: Verbindung a -> b loesen.
function Server.detach(player, args)
    local a = args and getVehicleById(tonumber(args.a) or -1)
    local b = args and getVehicleById(tonumber(args.b) or -1)
    if not a or not b then
        return fail(player, "UI_MultiTow_ActionFailed", "vehicle not found")
    end
    if not isNear(player, a) and not isNear(player, b) then   -- hier reicht EINES der beiden
        return fail(player, "UI_MultiTow_ActionFailed", "too far away")
    end
    if a:getVehicleTowing() ~= b then
        return -- schon getrennt
    end
    -- merken, WER abgekuppelt hat: der bekommt gleich (Ereignis RETURN) den Gegenstand zurueck
    pendingReturn[b:getId()] = { player = player, time = now() }
    MultiTow.log("SERVER detach", player:getUsername(), vid(a), "->", vid(b))
    a:breakConstraint(true, false)
end

-- Verschleiss: der Rechner des Fahrers misst die Belastung und meldet alle paar Sekunden den Verlust.
-- Wir pruefen, dass der Spieler wirklich diesen Zug faehrt, und begrenzen den Wert (gegen Unsinn).
local MAX_WEAR_PER_MSG = 40   -- mehr als 40 % auf einmal glauben wir nicht
function Server.wear(player, args)
    if not args or type(args.links) ~= "table" then return end
    local head = MultiTow.drivenTrainHead(player)
    if not head then return end                 -- faehrt gar keinen Zug -> ignorieren
    for _, e in ipairs(args.links) do
        local rear = getVehicleById(tonumber(e.r) or -1)
        local loss = math.min(MAX_WEAR_PER_MSG, math.max(0, tonumber(e.l) or 0))   -- zwischen 0 und 40
        if rear and loss > 0 and MultiTow.getHead(rear) == head then   -- Verbindung gehoert wirklich zu SEINEM Zug
            MultiTow.applyWear(rear, loss)
        end
    end
end

-- Warnblinker: nur der Fahrer des Zugfahrzeugs darf schalten
function Server.hazard(player, args)
    local head = MultiTow.drivenTrainHead(player)
    if not head or not args or tonumber(args.v) ~= head:getId() then return end
    head:getModData().MultiTowHazard = args.on and true or nil
    head:transmitModData()                      -- alle Spieler sehen den neuen Zustand
    MultiTow.log("SERVER hazard", args.on and "on" or "off", "by", player:getUsername(), "train", head:getId())
end

-- Verteiler fuer alle Client-Befehle
--   !! ACHTUNG: Jeder Befehl laeuft in pcall. Ein Fehler in EINEM Befehl darf nie den ganzen Server-Tick stoeren.
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "MultiTow" or not player then return end
    local fn = Server[command]
    if not fn then return end                   -- unbekannter Befehl -> ignorieren
    local ok, err = pcall(fn, player, args)
    if not ok then
        MultiTow.log("SERVER ERROR in", command, tostring(err))
        print("[MultiTow] SERVER ERROR in " .. tostring(command) .. ": " .. tostring(err))
    end
end)

-- ---------------------------------------------------------------------------
-- Ereignisse des Java-Teils (Haken, Geraeusche)
-- ---------------------------------------------------------------------------
--   Gleicher "Briefkasten" wie im Einzelspieler (siehe Kopf von client/MultiTow_Events.lua),
--   nur dass der Server die Ergebnisse an die Spieler verteilt.

--- Naechster Spieler im Umkreis maxDist (oder nil)
local function nearestPlayer(x, y, maxDist)
    local best, bestD = nil, maxDist * maxDist
    local players = getOnlinePlayers()
    if not players then return nil end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local dx, dy = p:getX() - x, p:getY() - y
        local d = dx * dx + dy * dy
        if d <= bestD then
            best, bestD = p, d
        end
    end
    return best
end

--- Alle Spieler im Umkreis maxDist
local function playersNear(x, y, maxDist)
    local list = {}
    local players = getOnlinePlayers()
    if not players then return list end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local dx, dy = p:getX() - x, p:getY() - y
        if dx * dx + dy * dy <= maxDist * maxDist then
            table.insert(list, p)
        end
    end
    return list
end

--- Gegenstand auf den Boden legen (offX = kleiner Versatz, damit mehrere Teile nicht aufeinander liegen)
local function dropAt(x, y, z, fullType, offX)
    local sq = getCell() and getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z))
    if not sq then return false end
    -- auf dem Server schickt das Spiel neue Boden-Gegenstaende selbst an alle Clients
    local ok = pcall(function()
        sq:AddWorldInventoryItem(fullType, math.min(0.95, (x - math.floor(x)) + (offX or 0)), y - math.floor(y), 0.0)
    end)
    return ok
end

--- Gegenstand ins Inventar eines Spielers legen (und ihm das mitteilen).
--  rear = hinteres Fahrzeug, fuer den Zustand einer Abschleppstange
local function giveItem(player, fullType, rear)
    local inv = player:getInventory()
    local item = inv:AddItem(fullType)
    if item then
        MultiTow.applyReturnCondition(item, fullType, rear)
        sendAddItemToContainer(inv, item)      -- [MP] sonst sieht der Spieler den Gegenstand erst nach dem Neuladen
        return true
    end
    return false
end

--- RETURN: Gegenstand an den Spieler, der abgekuppelt hat.
--  Reihenfolge der Kandidaten:  1. wer "detach" geschickt hat (innerhalb 10 s)
--                               2. sonst der naechste Spieler im Umkreis von 8 Feldern
--                               3. sonst: auf den Boden
local function handleReturn(x, y, z, rearId, fullType)
    fullType = fullType or MultiTow.HOOK_TYPE
    local pending = rearId and pendingReturn[rearId]
    pendingReturn[rearId or -1] = nil
    local player = nil
    if pending and now() - pending.time < PENDING_MS then
        player = pending.player
    end
    if not player then
        player = nearestPlayer(x, y, 8)
    end
    local ok = false
    if player then
        local okCall, given = pcall(giveItem, player, fullType, rearId and getVehicleById(rearId))
        ok = okCall and given
        if ok then
            reply(player, "halo", { key = "UI_MultiTow_ItemReturned", kind = "good", item = fullType })
            MultiTow.log("SERVER item returned to", player:getUsername(), fullType)
        end
    end
    if not ok then
        dropAt(x, y, z, fullType, 0)
        MultiTow.log("SERVER item dropped on the ground (no player nearby)", fullType)
    end
end

--- BREAK: Teile auf den Boden, Warnung an alle in 30 Feldern Umkreis.
local function handleBreak(x, y, z, fullType)
    local drops, key = MultiTow.breakDrops(fullType)
    for i, t in ipairs(drops) do
        dropAt(x, y, z, t, (i - 1) * 0.15)
    end
    for _, p in ipairs(playersNear(x, y, 30)) do
        reply(p, "halo", { key = key, kind = "warn" })
    end
    MultiTow.log("SERVER link snapped:", tostring(fullType), "-> dropped", table.concat(drops, ", "), "at", math.floor(x), math.floor(y))
end

local SOUND_EVENTS = { ATTACH = true, DETACH = true, SNAP = true }

local settingsApplied = false   -- Sandbox-Optionen schon uebernommen?

--- Jeder Server-Tick
local function onTick()
    -- >> WARUM hier und nicht beim Laden: Die Sandbox-Werte stehen erst bereit, wenn die Welt laeuft.
    if not settingsApplied then
        settingsApplied = MultiTow.applySandbox()
    end
    if not multiTowPopEvent then return end
    for _ = 1, 16 do                 -- Server: bis zu 16 Nachrichten pro Tick (mehr Spieler = mehr los)
        local e = multiTowPopEvent()
        if not e then return end
        local t = luautils.split(e, "|")
        local x, y, z = tonumber(t[2]) or 0, tonumber(t[3]) or 0, tonumber(t[4]) or 0
        local rearId = tonumber(t[6])
        if t[1] == "RETURN" then
            handleReturn(x, y, z, rearId, t[7])
            transmitVehicleModData(rearId and getVehicleById(rearId))   -- Verbindungsdaten am Fahrzeug sind jetzt weg
        elseif t[1] == "BREAK" then
            handleBreak(x, y, z, t[7])
            transmitVehicleModData(rearId and getVehicleById(rearId))
        elseif SOUND_EVENTS[t[1]] then
            -- Ohne Spielerangabe = an ALLE; jeder Client entscheidet selbst, ob er nah genug ist
            sendServerCommand("MultiTow", "sound", { s = t[1], x = x, y = y, z = z })
            if t[1] == "ATTACH" then
                -- Spruch fuer den Spieler, der gekuppelt hat (= der naechste Spieler am Kupplungspunkt)
                local front = getVehicleById(tonumber(t[5]) or -1)
                local rear = getVehicleById(tonumber(t[6]) or -1)
                local p = nearestPlayer(x, y, 10)
                if p and front and rear then
                    reply(p, "remark", {
                        n = MultiTow.trainLength(front, rear),
                        max = MultiTow.getMaxFor(MultiTow.getHead(front)),
                    })
                end
            end
        end
    end
end

Events.OnTick.Add(onTick)

-- Sandbox-Optionen koennen vom Admin geaendert werden - regelmaessig neu uebernehmen
Events.EveryOneMinute.Add(function()
    MultiTow.applySandbox()
end)

MultiTow.log("SERVER part loaded, java core:", tostring(multiTowCoreVersion and multiTowCoreVersion() or nil))
