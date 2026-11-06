--[[==========================================================================
    MultiTow_Events.lua                                        [ client ]
  ----------------------------------------------------------------------------
    Der "Briefkasten" zwischen Java-Teil und Lua.

    Der Java-Teil (MultiTowCore.jar) darf keine Lua-Funktionen direkt aufrufen.
    Stattdessen legt er kurze Textnachrichten in eine Warteschlange, und diese
    Datei holt sie jeden Tick mit multiTowPopEvent() ab:

        Java:  "BREAK|7084.6|11201.5|0|254|253|Base.MultiTowTowBar"
                  |      |       |    |  |   |   '-- Gegenstand der Verbindung
                  |      |       |    |  |   '-- hinteres Fahrzeug (ID)
                  |      |       |    |  '-- vorderes Fahrzeug (ID)
                  |      x       y    z (Etage)
                  '-- Art des Ereignisses
        Lua:   luautils.split(text, "|")  ->  t[1] .. t[7]
============================================================================]]

require "MultiTow_Utils"
require "MultiTow_Remarks"

-- Der Java-Teil meldet, wenn eine mit Gegenstand bezahlte Verbindung (Haken oder Abschleppstange) geloest wurde:
--   RETURN|x|y|z|vorne|hinten|Gegenstand  abgekuppelt -> Gegenstand zurueck ins Inventar
--   BREAK|x|y|z|vorne|hinten|Gegenstand   waehrend der Fahrt gerissen ->
--       Haken: Kette und grosser Haken fallen auf den Boden; Stange: eine kaputte Stange (nur noch Schrott)
-- Geraeusche (unabhaengig vom Haken):
--   ATTACH|x|y|z  angekuppelt   DETACH|x|y|z  abgekuppelt   SNAP|x|y|z  Verbindung gerissen
-- Wir fragen die Ereignisse jeden Tick ab (leer = fast kostenlos).
--
-- Multiplayer: Diese Ereignisse entstehen nur auf dem Server (server/MultiTow_Server.lua erledigt Haken und Gegenstaende).
-- Der Server schickt den Clients Befehle: "hello" (Antwort auf unsere Anmeldung), "sound", "halo" und "fail".


-- ############################################################################
-- ##  KLEINE HELFER
-- ############################################################################

--- Inventar-Fenster neu zeichnen lassen (sonst sieht man einen neuen Gegenstand erst nach dem Umsortieren).
local function refreshInventoryUI()
    pcall(function()
        if ISInventoryPage and ISInventoryPage.dirtyUI then ISInventoryPage.dirtyUI() end
    end)
end

--- Farbige Meldung ueber dem Kopf der eigenen Figur (r, g, b = 0..255).
--    gruen  120,255,120  = gut      orange 255,160,60 = Warnung      rot 255,80,80 = Fehler
local function halo(text, r, g, b)
    pcall(function()
        local p = getPlayer()
        if p then p:setHaloNote(text, r, g, b, 300) end   -- 300 = Anzeigedauer
    end)
end


-- ############################################################################
-- ##  RETURN: abgekuppelt -> Gegenstand zurueck
-- ############################################################################

--- fullType  z.B. "Base.MultiTowTowBar" (fehlt bei alten Ereignissen -> Haken)
--  rearId    ID des hinteren Fahrzeugs (dort steht der Zustand der Verbindung)
local function handleReturn(fullType, rearId)
    fullType = fullType or MultiTow.HOOK_TYPE
    local p = getPlayer()
    if not p then return end
    local ok = pcall(function()
        local item = p:getInventory():AddItem(fullType)
        -- Abschleppstange: Zustand der Verbindung (Verschleiss) geht auf den Gegenstand ueber
        MultiTow.applyReturnCondition(item, fullType, rearId and getVehicleById(rearId))
    end)
    if ok then
        refreshInventoryUI()
        halo(getText("UI_MultiTow_ItemReturned", MultiTow.getItemName(fullType)), 120, 255, 120)
        MultiTow.log("Item returned to inventory:", fullType)
    else
        MultiTow.log("ERROR: could not put item into inventory:", fullType)
    end
end


-- ############################################################################
-- ##  BREAK: waehrend der Fahrt gerissen -> Teile fallen auf den Boden
-- ############################################################################

--- Einen Gegenstand auf ein Feld legen.  offX/offY = Position innerhalb des Feldes (0..1)
--  >> WARUM zwei Versuche: Je nach Spielversion nimmt AddWorldInventoryItem einen Namen ODER einen fertigen Gegenstand.
local function dropItem(sq, fullType, offX, offY)
    local ok = pcall(function()
        sq:AddWorldInventoryItem(fullType, offX, offY, 0.0)
    end)
    if not ok then
        pcall(function()
            local item = instanceItem(fullType)
            if item then sq:AddWorldInventoryItem(item, offX, offY, 0.0) end
        end)
    end
end

--- x, y, z  Stelle der gerissenen Verbindung;  fullType  welcher Gegenstand drin war
local function handleBreak(x, y, z, fullType)
    local cell = getCell()
    if not cell then return end
    local fx, fy = math.floor(x), math.floor(y)          -- Feld (ganze Zahlen)
    local sq = cell:getGridSquare(fx, fy, math.floor(z))
    if not sq then
        MultiTow.log("BREAK: square not loaded, nothing dropped")
        return
    end
    local ox, oy = x - fx, y - fy                        -- Nachkommastellen = Position im Feld
    local drops, key = MultiTow.breakDrops(fullType)     -- welche Teile fallen runter + Text der Meldung
    for i, t in ipairs(drops) do
        -- Teile leicht versetzt nebeneinander (je 0.15), aber nie ueber den Feldrand hinaus (0.95)
        dropItem(sq, t, math.min(0.95, ox + (i - 1) * 0.15), oy)
    end
    halo(getText(key), 255, 160, 60)
    MultiTow.log("Link snapped:", tostring(fullType), "-> dropped", table.concat(drops, ", "), "at", fx, fy)
end


-- ############################################################################
-- ##  GERAEUSCHE
-- ############################################################################

-- Kettengeraeusche, Definition in media/scripts/MultiTow_sounds.txt, Dateien in media/sound/
local SOUNDS = {
    ATTACH = "MultiTowAttach",
    DETACH = "MultiTowDetach",
    SNAP = "MultiTowSnap",
}

--- Geraeusch an einer Stelle der Welt abspielen (man hoert es von dort, nicht vom Kopf der Figur).
function MultiTow.playSoundAt(name, x, y, z)
    local played = false
    local cell = getCell()
    if cell then
        local sq = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z))
        if sq then
            played = pcall(function() sq:playSound(name) end)
        end
    end
    if not played then
        -- Notloesung: Geraeusch direkt beim Spieler
        pcall(function() getPlayer():getEmitter():playSound(name) end)
    end
end


-- ############################################################################
-- ##  [MP] ANMELDUNG BEIM SERVER
-- ############################################################################

-- Multiplayer: beim Server anmelden. Er antwortet mit seiner Java-Version (oder nichts, wenn dort kein Java-Teil laeuft).
--   Ablauf:   Client --"hello" + eigene Version-->  Server
--             Client <--"hello" + Server-Version--  Server     -> ServerCommands.hello weiter unten
local helloSent = false
local function sendHello()
    if helloSent or not isClient() then return end   -- nur einmal, und nur im Multiplayer
    local p = getPlayer()
    if not p then return end                         -- Figur noch nicht da? naechsten Tick nochmal
    helloSent = true
    MultiTow.serverReady = false                     -- bis zur Antwort: Menue-Eintraege ausgeblendet
    sendClientCommand(p, "MultiTow", "hello", { core = multiTowCoreVersion and multiTowCoreVersion() or "" })
    MultiTow.log("hello sent to server")
end


-- ############################################################################
-- ##  JEDEN TICK: BRIEFKASTEN DES JAVA-TEILS LEEREN
-- ############################################################################
local function onTick()
    sendHello()
    if not multiTowPopEvent then return end   -- Java-Teil nicht geladen -> es gibt keinen Briefkasten
    for _ = 1, 8 do                           -- hoechstens 8 Nachrichten pro Tick (der Rest kommt im naechsten)
        local e = multiTowPopEvent()
        if not e then return end              -- Briefkasten leer
        local t = luautils.split(e, "|")
        if t[1] == "RETURN" then
            handleReturn(t[7], tonumber(t[6]))
        elseif t[1] == "BREAK" then
            handleBreak(tonumber(t[2]) or 0, tonumber(t[3]) or 0, tonumber(t[4]) or 0, t[7])
        elseif SOUNDS[t[1]] then
            if MultiTow.Settings.sounds ~= false then
                MultiTow.playSoundAt(SOUNDS[t[1]], tonumber(t[2]) or 0, tonumber(t[3]) or 0, tonumber(t[4]) or 0)
            end
            -- Einzelspieler: Spruch der Figur nach dem Ankuppeln (im MP schickt ihn der Server)
            if t[1] == "ATTACH" and not isClient() then
                local p = getPlayer()
                local x, y = tonumber(t[2]) or 0, tonumber(t[3]) or 0
                -- nur wenn die Figur nah dran ist: (Abstand)^2 <= 100  bedeutet  Abstand <= 10 Felder
                if p and (p:getX() - x) ^ 2 + (p:getY() - y) ^ 2 <= 100 then
                    MultiTow.remarkForLink(p, getVehicleById(tonumber(t[5]) or -1), getVehicleById(tonumber(t[6]) or -1))
                end
            end
        end
    end
end

Events.OnTick.Add(onTick)

-- ---------------------------------------------------------------------------
-- Multiplayer: Befehle vom Server
-- ---------------------------------------------------------------------------
--   Jeder Befehl ist eine Funktion in dieser Tabelle. Der Name = der Befehl,
--   den der Server mit sendServerCommand(..., "MultiTow", "<name>", args) schickt.
local ServerCommands = {}

--- Antwort auf unsere Anmeldung. args.core = Java-Version des Servers (leer = kein Java-Teil)
function ServerCommands.hello(args)
    local core = args and args.core
    MultiTow.serverCore = core
    -- bereit nur, wenn BEIDE Seiten den Java-Teil haben
    MultiTow.serverReady = core ~= nil and core ~= "" and multiTowCoreVersion ~= nil
    MultiTow.log("server hello: core =", tostring(core), "ready =", tostring(MultiTow.serverReady))
    if not MultiTow.serverReady then
        halo(getText("UI_MultiTow_ServerJavaMissing"), 255, 80, 80)
    end
end

--- Der Server sagt: "an Stelle x/y/z ist gerade gekuppelt/abgekuppelt/gerissen worden".
function ServerCommands.sound(args)
    if MultiTow.Settings.sounds == false or not args then return end   -- Kettengeraeusche sind persoenlich abschaltbar
    local name = SOUNDS[args.s]
    local p = getPlayer()
    if not name or not p then return end
    local x, y, z = tonumber(args.x) or 0, tonumber(args.y) or 0, tonumber(args.z) or 0
    local dx, dy = p:getX() - x, p:getY() - y
    if dx * dx + dy * dy > 60 * 60 then return end   -- weiter als 60 Felder weg? dann hoert man es eh nicht
    MultiTow.playSoundAt(name, x, y, z)
end

--- Meldung ueber dem Kopf.  args.kind: "good" (gruen), "warn" (orange), sonst rot
function ServerCommands.halo(args)
    if not args or not args.key then return end
    local name = MultiTow.getItemName(args.item or MultiTow.HOOK_TYPE)
    if args.kind == "good" then
        refreshInventoryUI()          -- "good" heisst meist: Gegenstand zurueck im Inventar
        halo(getText(args.key, name), 120, 255, 120)
    elseif args.kind == "warn" then
        halo(getText(args.key, name), 255, 160, 60)
    else
        halo(getText(args.key, name), 255, 80, 80)
    end
end

--- Spruch der Figur. args.n = Zuglaenge, args.max = Grenze
function ServerCommands.remark(args)
    if not args then return end
    MultiTow.trainRemark(getPlayer(), args.n, args.max)
end

--- Der Server hat eine Anfrage abgelehnt (z.B. Zug zu lang, Gegenstand fehlt).
function ServerCommands.fail(args)
    if not args or not args.key then return end
    MultiTow.log("server refused:", tostring(args.key))
    halo(getText(args.key, MultiTow.getItemName(args.item or MultiTow.HOOK_TYPE)), 255, 80, 80)
end

-- Verteiler: jede Server-Nachricht an die passende Funktion oben weitergeben
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "MultiTow" then return end   -- Nachrichten anderer Mods ignorieren
    local fn = ServerCommands[command]
    if fn then fn(args) end
end)

-- Multiplayer: Sandbox-Optionen koennen vom Admin geaendert werden - regelmaessig neu uebernehmen
Events.EveryOneMinute.Add(function()
    if MultiTow.isMP() then MultiTow.applySandbox() end
end)
