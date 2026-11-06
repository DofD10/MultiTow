--[[==========================================================================
    Multitow_Client.lua                                        [ client ]
  ----------------------------------------------------------------------------
    Das Rundmenue AUSSERHALB des Fahrzeugs (Taste V, neben einem Auto stehen)
    und die "Aktion" (Animation + Wartebalken) beim Kuppeln.

    Ablauf, wenn du im Menue "Multi-Tow: Ankuppeln" klickst:

      [Klick] --> startMultiTowAction()          prueft Gegenstand, plant Weg
                     |
                     +--> ISWalkToTimedAction     hinlaufen (falls > 2.5 Felder weg)
                     +--> ISMultiTowAction        buecken, 90 Ticks warten
                              |
                              '--> perform() --> MultiTow.attachToChain()   (MultiTow_Physics.lua)
                                              oder MultiTow.detachFromChain()
============================================================================]]

require "Vehicles/ISUI/ISVehicleMenu"         -- Spiel: das Fahrzeug-Rundmenue
require "TimedActions/ISBaseTimedAction"      -- Spiel: Grundlage fuer alle Aktionen mit Wartebalken
require "MultiTow_Languages"
require "MultiTow_Utils"
require "MultiTow_Physics"


-- ############################################################################
-- ##  DIE AKTION "KUPPELN" (mit Wartebalken)
-- ############################################################################
--  In Project Zomboid laeuft alles, was Zeit braucht, als "Timed Action":
--  das Spiel ruft der Reihe nach isValid / waitToStart / start / update ... / perform auf.

ISMultiTowAction = ISBaseTimedAction:derive("ISMultiTowAction")   -- "derive" = eigene Aktion auf Basis der Spiel-Aktion

--- Darf die Aktion (weiter)laufen? Wird immer wieder gefragt.
function ISMultiTowAction:isValid()
    if self.vehicleA == nil or self.vehicleB == nil then return false end
    -- Haken bzw. Abschleppstange waehrend der Aktion weggelegt? Dann abbrechen.
    if self.isAttach then
        if self.linkType == "bar" then
            if not MultiTow.hasItem(self.character, MultiTow.TOWBAR_TYPE) then return false end
        elseif MultiTow.needsHook(self.vehicleA, self.vehicleB) and not MultiTow.hasHook(self.character) then
            return false
        end
    end
    return true
end

--- Vor dem Start: Figur dreht sich zum Fahrzeug. Solange sie sich noch dreht -> warten (true).
function ISMultiTowAction:waitToStart()
    self.character:faceThisObject(self.vehicleA)
    return self.character:shouldBeTurning()
end

--- Jeder Tick waehrend der Aktion: hinschauen und "schwer arbeiten" (macht muede/hungrig wie im Spiel)
function ISMultiTowAction:update()
    self.character:faceThisObject(self.vehicleA)
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
end

--- Start: Buecken-Animation und das Kupplungs-Geraeusch des Spiels
function ISMultiTowAction:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.sound = self.character:getEmitter():playSound("VehicleTrailerAttach")
end

--- Abgebrochen (weggelaufen, Esc ...): Geraeusch stoppen
function ISMultiTowAction:stop()
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

--- Fertig (Wartebalken voll): jetzt WIRKLICH kuppeln oder abkuppeln
function ISMultiTowAction:perform()
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end

    if self.isAttach then
        MultiTow.attachToChain(self.character, self.vehicleA, self.vehicleB, self.attachmentA, self.attachmentB, self.linkType)
    else
        MultiTow.detachFromChain(self.character, self.vehicleA, self.vehicleB)
    end

    ISBaseTimedAction.perform(self)   -- !! nicht vergessen: sagt dem Spiel "Aktion beendet"
end

--- Neue Aktion anlegen.
--  vehicleA = vorderes Fahrzeug,  vehicleB = hinteres
--  isAttach = true: ankuppeln, false: abkuppeln;  linkType = "chain" oder "bar"
function ISMultiTowAction:new(character, vehicleA, vehicleB, attachmentA, attachmentB, isAttach, linkType)
    local o = ISBaseTimedAction.new(self, character)
    o.stopOnWalk = true      -- wer loslaeuft, bricht ab
    o.stopOnRun = true
    o.maxTime = 90           -- Dauer in Ticks (ca. 1.5 Sekunden bei normaler Geschwindigkeit)
    o.vehicleA = vehicleA
    o.vehicleB = vehicleB
    o.attachmentA = attachmentA
    o.attachmentB = attachmentB
    o.isAttach = isAttach
    o.linkType = linkType or "chain"
    return o
end


-- ############################################################################
-- ##  SYMBOLE UND START DER AKTION
-- ############################################################################

-- Eigenes Symbol fuer alle Eintraege dieser Mod im Rundmenue (damit klar ist: das ist die Mod, nicht das Spiel)
--   "A or B": falls unser Bild fehlt, nimm ein Symbol aus dem Spiel
local ICON_ATTACH = getTexture("media/ui/MultiTow_RoadTrain.png") or getTexture("media/ui/ZoomIn.png")
local ICON_DETACH = getTexture("media/ui/MultiTow_RoadTrainOff.png") or getTexture("media/ui/ZoomOut.png")
local ICON_BAR = getTexture("media/ui/MultiTow_TowBar.png") or ICON_ATTACH
local ICON_BAR_OFF = getTexture("media/ui/MultiTow_TowBarOff.png") or ICON_DETACH

-- Text und Symbol fuer das Abkuppeln, je nachdem womit die Verbindung gemacht wurde
--   Stange -> "...Abschleppstange zurueck"   Haken -> "...Haken zurueck"   sonst -> "Abkuppeln"
local function detachSlice(rear)
    if MultiTow.isBarLink(rear) then return "detachBar", ICON_BAR_OFF end
    if MultiTow.isHookLink(rear) then return "detachHook", ICON_DETACH end
    return "detach", ICON_DETACH
end

--- Wird beim Klick auf einen Menue-Eintrag aufgerufen.
local function startMultiTowAction(playerObj, vehA, vehB, isAttach, linkType)
    linkType = linkType or "chain"
    -- -> 1. Fehlt der Gegenstand? Dann nur eine rote Meldung, keine Aktion.
    if isAttach and linkType == "bar" and not MultiTow.hasItem(playerObj, MultiTow.TOWBAR_TYPE) then
        pcall(function()
            playerObj:setHaloNote(getText("UI_MultiTow_NeedTowBar", MultiTow.getItemName(MultiTow.TOWBAR_TYPE)), 255, 80, 80, 300)
        end)
        return
    end
    -- Einstellung "Haken noetig": ohne Gegenstand nur eine Meldung
    if isAttach and linkType ~= "bar" and MultiTow.needsHook(vehA, vehB) and not MultiTow.hasHook(playerObj) then
        pcall(function()
            playerObj:setHaloNote(getText("UI_MultiTow_NeedHook", MultiTow.getHookName()), 255, 80, 80, 300)
        end)
        return
    end

    -- -> 2. Welche Kupplungspunkte?  vorne: hinterer Haken von A,  hinten: vorderer Haken von B
    local attA = MultiTow.findAttachmentName(vehA, true)
    local attB = MultiTow.findAttachmentName(vehB, false)

    -- -> 3. Die Mitte zwischen beiden Punkten ist der Arbeitsplatz der Figur
    local x1, y1 = MultiTow.getHitchWorldPos(vehA, attA)
    local x2, y2 = MultiTow.getHitchWorldPos(vehB, attB)
    local midX = (x1 + x2) * 0.5
    local midY = (y1 + y2) * 0.5

    local dx = playerObj:getX() - midX
    local dy = playerObj:getY() - midY
    local distToHitch = math.sqrt(dx * dx + dy * dy)   -- Satz des Pythagoras = Luftlinie

    -- -> 4. Zu weit weg? Erst hinlaufen (wird in die Warteschlange VOR die Kuppel-Aktion gestellt)
    if distToHitch > 2.5 then
        local sq = getCell():getGridSquare(math.floor(midX), math.floor(midY), playerObj:getZ())
        if sq then
            ISTimedActionQueue.add(ISWalkToTimedAction:new(playerObj, sq))
        end
    end

    -- -> 5. Die eigentliche Aktion
    ISTimedActionQueue.add(ISMultiTowAction:new(playerObj, vehA, vehB, attA, attB, isAttach, linkType))
end


-- ############################################################################
-- ##  RUNDMENUE NEBEN DEM FAHRZEUG
-- ############################################################################
--  Die Spiel-Funktion wird "umwickelt": erst baut das Spiel sein normales Menue,
--  dann fuegen wir unsere Eintraege hinzu.
--
--  Moegliche Eintraege (Beispiel: Figur steht bei B):
--
--     [ A ] =====> [ B ] =====> [ C ]          [ D ]  <- frei, nah an C
--                    |
--       "B von A abkuppeln"  (nur wenn A selbst gezogen wird, sonst macht das das Spiel)
--       "C von B abkuppeln"  (nur wenn B in der Mitte haengt)
--       "D an C ankuppeln"   (Kette, ab 3 Fahrzeugen)  /  "... mit Abschleppstange"

local old_showRadialMenuOutside = ISVehicleMenu.showRadialMenuOutside
function ISVehicleMenu.showRadialMenuOutside(playerObj)
    old_showRadialMenuOutside(playerObj)     -- zuerst das normale Menue des Spiels

    if not playerObj or playerObj:getVehicle() then return end
    -- Mod im Optionsmenue ausgeschaltet: nur das normale Spielmenue
    if not MultiTow.Settings.enabled then return end
    -- Multiplayer: nur anbieten, wenn auch der Server den Java-Teil hat (Antwort auf "hello")
    if isClient() and not MultiTow.serverReady then return end
    -- Basis-Modus (kein ZombieBuddy): keine eigenen Eintraege. Das normale Abschleppen des Spiels
    -- (2 Fahrzeuge) steht weiter im Menue. Ohne Java-Teil wuerde ein 3. Fahrzeug die erste Verbindung loesen,
    -- und eine Abschleppstange waere nur ein Seil.
    if not MultiTow.javaLoaded() then return end

    local vehicle = ISVehicleMenu.getVehicleToInteractWith(playerObj)   -- das Fahrzeug, bei dem die Figur steht
    if not vehicle then return end

    local menu = getPlayerRadialMenu(playerObj:getPlayerNum())
    if not menu then return end

    local rearVeh = MultiTow.getChainTowing(vehicle)     -- wen zieht dieses Fahrzeug?
    local frontVeh = MultiTow.getChainTowedBy(vehicle)   -- wer zieht dieses Fahrzeug?

    -- (a) Fahrzeug haengt in der Mitte: hintere Verbindung loesen anbieten
    if rearVeh and frontVeh ~= nil then
        local nameA = tostring(vehicle:getScript():getName())
        local nameB = tostring(rearVeh:getScript():getName())
        local key, icon = detachSlice(rearVeh)
        menu:addSlice(
            MultiTow.getText(key, nameB, nameA),
            icon,
            startMultiTowAction,   -- <- Funktion, die beim Klick laeuft
            playerObj,             -- \
            vehicle,               --  |  ihre Argumente
            rearVeh,               --  |
            false                  -- /   false = abkuppeln
        )
    end

    -- (b) Der Vordermann wird selbst gezogen: vordere Verbindung loesen anbieten
    --     (ist der Vordermann das Zugfahrzeug, bietet das Spiel selbst "Abkuppeln" an)
    if frontVeh and frontVeh:getVehicleTowedBy() ~= nil then
        local nameA = tostring(frontVeh:getScript():getName())
        local nameB = tostring(vehicle:getScript():getName())
        local key, icon = detachSlice(vehicle)
        menu:addSlice(
            MultiTow.getText(key, nameB, nameA),
            icon,
            startMultiTowAction,
            playerObj,
            frontVeh,
            vehicle,
            false
        )
    end

    -- (c) Ankuppeln: gibt es in der Naehe ein passendes Fahrzeug?
    local partner, isSourceFront = MultiTow.findValidChainPartner(playerObj, vehicle)
    if partner then
        -- isSourceFront = true: unser Fahrzeug ist vorne, der Partner haengt sich hinten an
        local vehA = isSourceFront and vehicle or partner
        local vehB = isSourceFront and partner or vehicle

        local allowed = MultiTow.isTrainLengthAllowed(vehA, vehB)   -- Zuglaengen-Grenze aus den Optionen
        local nameA = tostring(vehA:getScript():getName())
        local nameB = tostring(vehB:getScript():getName())
        -- Kette/Seil: nur ab dem 3. Fahrzeug (fuer zwei Fahrzeuge gibt es das normale Spielmenue)
        if allowed and (MultiTow.getChainTowedBy(vehA) ~= nil or MultiTow.getChainTowing(vehB) ~= nil) then
            menu:addSlice(
                MultiTow.getText(MultiTow.needsHook(vehA, vehB) and "attachHook" or "attach", nameB, nameA),
                ICON_ATTACH,
                startMultiTowAction,
                playerObj,
                vehA,
                vehB,
                true,
                "chain"
            )
        end
        -- Abschleppstange: auch schon fuer zwei Fahrzeuge, nur wenn der Spieler eine dabei hat
        if allowed and MultiTow.canUseBar(vehA, vehB) and MultiTow.hasItem(playerObj, MultiTow.TOWBAR_TYPE) then
            menu:addSlice(
                MultiTow.getText("attachBar", nameB, nameA),
                ICON_BAR,
                startMultiTowAction,
                playerObj,
                vehA,
                vehB,
                true,
                "bar"
            )
        end
    end
end

-- Warnung, falls der Java-Teil (ZombieBuddy) nicht geladen wurde
--   multiTowCoreVersion gibt es NUR, wenn ZombieBuddy den Java-Teil geladen hat.
--   Fehlt sie, laeuft nur das normale Abschleppen des Spiels (zwei Fahrzeuge).
Events.OnGameStart.Add(function()
    if multiTowCoreVersion then
        MultiTow.log("MultiTowCore:", tostring(multiTowCoreVersion()))
        print("[MultiTow] Java part: " .. tostring(multiTowCoreVersion()))
    elseif MultiTow.javaRestartNeeded() then
        -- Java-Teil wurde waehrend des Spiels nachgeladen (Mod im Mod-Menue eingeschaltet): erst nach Neustart aktiv
        MultiTow.log("WARNING: MultiTowCore (Java) was loaded while the game was running - restart needed, basic mode until then")
        print("[MultiTow] WARNING: Java part was loaded while the game was running - please restart the game")
        pcall(function()
            local p = getPlayer()
            if p then p:setHaloNote(getText("UI_MultiTow_JavaRestart"), 255, 165, 40, 600) end
        end)
    else
        MultiTow.log("WARNING: MultiTowCore (Java) not loaded - basic mode (vanilla coupling only)")
        print("[MultiTow] WARNING: Java part not loaded (is ZombieBuddy enabled? JAR approved?)")
        pcall(function()
            local p = getPlayer()
            if p then p:setHaloNote(getText("UI_MultiTow_JavaMissing"), 255, 80, 80, 400) end
        end)
    end
end)
