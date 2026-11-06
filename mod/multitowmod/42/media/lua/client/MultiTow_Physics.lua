--[[==========================================================================
    MultiTow_Physics.lua                                       [ client ]
  ----------------------------------------------------------------------------
    WAS:    Die zwei Befehle "ankuppeln" und "abkuppeln", die das Rundmenue
            (Multitow_Client.lua) am Ende einer Aktion aufruft.
    WER MACHT DIE PHYSIK?
            Nicht Lua! Die eigentliche Verbindung (Seil, Gelenk, Stange) baut der
            Java-Teil MultiTowCore.jar, geladen von ZombieBuddy. Er erlaubt pro
            Fahrzeug eine vordere UND eine hintere Kupplung - das kann das Spiel
            von sich aus nicht.
    WAS MACHT LUA DANN?
            Es ruft die normalen Spiel-Funktionen auf (die der Java-Teil abfaengt)
            und kuemmert sich um den Gegenstand (Haken oder Abschleppstange).

    [SP] Einzelspieler: alles passiert direkt hier.
    [MP] Mehrspieler:   hier wird nur eine Anfrage an den Server geschickt,
                        der Server (server/MultiTow_Server.lua) kuppelt wirklich.
============================================================================]]

require "MultiTow_Common"

-- Kleine Hilfe fuers Log: Fahrzeug-Nummer oder "nil", damit nie ein Fehler entsteht
local function vid(v)
    if v then return v:getId() end
    return "nil"
end


-- ############################################################################
-- ##  ANKUPPELN
-- ############################################################################

--- vehA (vorne) zieht ab jetzt vehB (hinten).
--  playerObj  die Figur, die kuppelt (aus ihrem Inventar kommt Haken/Stange)
--  attA       Kupplungspunkt an vehA, meist "trailer" (hinten)
--  attB       Kupplungspunkt an vehB, meist "trailerfront" (vorne)
--  linkType   "chain" = Kette/Seil, "bar" = Abschleppstange
function MultiTow.attachToChain(playerObj, vehA, vehB, attA, attB, linkType)
    linkType = linkType or "chain"           -- nichts angegeben? dann Kette
    -- [MP] Multiplayer: der Server kuppelt (prueft Regeln, nimmt den Gegenstand, meldet es allen Spielern)
    if isClient() then
        MultiTow.log("ATTACH request to server", vid(vehA), "->", vid(vehB), attA, attB, linkType)
        sendClientCommand(playerObj, "MultiTow", "attach",
            { a = vehA:getId(), b = vehB:getId(), attA = attA, attB = attB, link = linkType })
        return                               -- <- hier ist fuer den Client Schluss, der Rest ist Einzelspieler
    end
    MultiTow.log("ATTACH Lua", vid(vehA), "->", vid(vehB), attA, attB, linkType)

    -- -> Die ganze Arbeit (Gegenstand pruefen, kuppeln, Gegenstand nehmen) macht doAttach in MultiTow_Common.lua.
    --    ok = hat geklappt?   failKey = Textschluessel der Fehlermeldung, falls nicht
    local ok, failKey = MultiTow.doAttach(playerObj, vehA, vehB, attA, attB, linkType)
    MultiTow.log("  after A: towing", vid(vehA:getVehicleTowing()),
        "towedBy", vid(vehA:getVehicleTowedBy()),
        "| B: towing", vid(vehB:getVehicleTowing()),
        "towedBy", vid(vehB:getVehicleTowedBy()), "| linked:", tostring(ok))
    if not ok then
        -- Rote Meldung ueber dem Kopf der Figur, z.B. "Benoetigt: Abschleppstange".
        -- pcall = "probier mal" - falls etwas schiefgeht, stuerzt nicht das ganze Menue ab.
        pcall(function()
            playerObj:setHaloNote(getText(failKey, MultiTow.getItemName(linkType == "bar" and MultiTow.TOWBAR_TYPE or MultiTow.HOOK_TYPE)), 255, 80, 80, 300)
        end)
    end
end


-- ############################################################################
-- ##  ABKUPPELN
-- ############################################################################

-- vehA = vorderes Fahrzeug der Kupplung, vehB = das dahinter.
-- Wichtig: nur vehA:breakConstraint aufrufen. Der Java-Teil loest genau EINE Kupplung
-- (die hintere von vehA); ein zusaetzlicher Aufruf bei vehB wuerde dessen hintere Kupplung kappen.
-- Der Haken kommt ueber das Ereignis "RETURN" vom Java-Teil zurueck (siehe MultiTow_Events.lua).
--
--      [ A ]==X==[ B ]-----[ C ]        X = diese Verbindung wird geloest
--                                       B -> C bleibt bestehen
function MultiTow.detachFromChain(playerObj, vehA, vehB)
    if isClient() then                       -- [MP] wieder nur eine Anfrage an den Server
        MultiTow.log("DETACH request to server", vid(vehA), "->", vid(vehB))
        sendClientCommand(playerObj, "MultiTow", "detach", { a = vehA:getId(), b = vehB:getId() })
        return
    end
    MultiTow.log("DETACH Lua", vid(vehA), "->", vid(vehB))
    if vehA:getVehicleTowing() == vehB then  -- nur loesen, wenn A wirklich (noch) B zieht
        vehA:breakConstraint(true, false)    -- (true = Verbindung ganz vergessen, false = nicht vom Netzwerk ausgeloest)
    end
    MultiTow.log("  after A: towing", vid(vehA:getVehicleTowing()),
        "| B: towedBy", vid(vehB:getVehicleTowedBy()))
end
