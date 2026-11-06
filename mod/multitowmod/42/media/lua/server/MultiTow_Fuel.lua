--[[==========================================================================
    MultiTow_Fuel.lua                                 [ Einzelspieler + Server ]
  ----------------------------------------------------------------------------
    Multi-Vehicle Towing: Mehrverbrauch an Sprit
    (Option "Mehrverbrauch an Sprit", getrennt fuer PKW und LKW)

    WIE DAS SPIEL SPRIT RECHNET:
      In der Spiel-Funktion  Vehicles.Update.GasTank  (server/Vehicles/Vehicles.lua).
      Sie wird regelmaessig fuer jeden Tank aufgerufen und zieht den Verbrauch ab.

    UNSER TRICK ("Wrapper" = Huelle um die Original-Funktion):
        +---------------------------------------------+
        | unsere neue GasTank-Funktion                |
        |   1. Tankinhalt VORHER merken               |
        |   2. Original-Funktion rechnen lassen       |
        |   3. Verbrauch = vorher - nachher           |
        |   4. Aufschlag zusaetzlich abziehen         |
        +---------------------------------------------+
      So bleibt die Rechnung des Spiels unangetastet, wir legen nur drauf.

    Gilt erst ab dem 3. Fahrzeug (das normale Abschleppen von einem Fahrzeug bleibt wie im Spiel).
      k = zusaetzliche Fahrzeuge (gezogene Fahrzeuge - 1), p = Prozent aus den Optionen
      gleichmaessig:  Verbrauch x (1 + p * k)        z.B. 20 %, 3 gezogen: x 1.4
      exponentiell:   Verbrauch x (1 + p) hoch k     z.B. 20 %, 3 gezogen: x 1.44, 6 gezogen: x 2.49
    Laeuft im Einzelspieler und auf dem MP-Server (dort rechnet das Spiel den Tank).
============================================================================]]

if isClient() then return end   -- MP-Client: Tanks rechnet nur der Server

require "Vehicles/Vehicles"     -- die Spiel-Datei mit Vehicles.Update.GasTank MUSS vorher geladen sein
require "MultiTow_Common"
require "MultiTow_Train"

local FUEL_OFF = 1              -- Auswahl 1 im Optionsmenue = "Aus"

--- Aufschlag abziehen. Wird NACH der Original-Funktion aufgerufen.
--  vehicle  das Fahrzeug, dessen Tank gerade gerechnet wurde
--  part     der Tank (ein Fahrzeugteil)
--  before   Tankinhalt in Litern, bevor das Spiel gerechnet hat
local function extraFuel(vehicle, part, before)
    if not MultiTow.Settings.enabled then return end
    -- Fahrzeuge weit weg rechnet das Spiel als "VirtualVehicle" weiter (ohne Kupplungen) - die lassen wir aus
    if not instanceof(vehicle, "BaseVehicle") then return end
    if vehicle:getVehicleTowedBy() ~= nil then return end -- nur das Zugfahrzeug faehrt mit eigenem Motor
    local towed = MultiTow.towedCount(vehicle)
    if towed < 2 then return end                          -- 0 oder 1 gezogen: wie im Spiel
    local mode = tonumber(MultiTow.trainSetting(vehicle, "fuelModeCar", "fuelModeTruck")) or FUEL_OFF
    if mode == FUEL_OFF then return end
    local pct = MultiTow.trainSetting(vehicle, "fuelPctCar", "fuelPctTruck")
    local mult = MultiTow.fuelMultiplier(mode, pct, towed)   -- z.B. 1.6 = 60 % mehr
    if mult <= 1 then return end
    local after = part:getContainerContentAmount()
    local used = before - after                          -- so viel hat das Spiel gerade abgezogen
    if used <= 0 then return end                         -- Motor aus / nachgetankt -> nichts tun
    local newAmount = math.max(0, after - used * (mult - 1))   -- Aufschlag = Verbrauch * (Faktor - 1), nie unter 0
    part:setContainerContentAmount(newAmount, false, true)
    -- [MP] den neuen Tankinhalt an die Spieler schicken (im Einzelspieler passiert hier einfach nichts)
    pcall(function() vehicle:transmitPartModData(part) end)
end

--- Unsere Huelle um die Original-Funktion legen (nur einmal).
local function install()
    if not Vehicles or not Vehicles.Update or not Vehicles.Update.GasTank then
        MultiTow.log("WARNING: Vehicles.Update.GasTank not found - no extra fuel use")
        return
    end
    -- >> WARUM diese Markierung: Wird die Datei zweimal geladen, wuerde sonst die Huelle doppelt gewickelt
    --    und der Aufschlag doppelt abgezogen.
    if Vehicles.Update.multiTowWrapped then return end
    Vehicles.Update.multiTowWrapped = true
    local orig = Vehicles.Update.GasTank     -- Original merken
    Vehicles.Update.GasTank = function(vehicle, part, elapsedMinutes)
        local before = part and part:getContainerContentAmount() or 0
        orig(vehicle, part, elapsedMinutes)  -- das Spiel rechnet ganz normal
        -- unser Teil in pcall: ein Fehler bei uns darf die Spritrechnung des Spiels nie kaputtmachen
        local ok, err = pcall(extraFuel, vehicle, part, before)
        if not ok then MultiTow.log("ERROR extra fuel:", tostring(err)) end
    end
    MultiTow.log("Fuel: Vehicles.Update.GasTank wrapped")
end

install()
