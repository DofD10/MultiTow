--[[==========================================================================
    MultiTow_Shared.lua                                 [ client + server ]
  ----------------------------------------------------------------------------
    WAS:    Gibt JEDEM Fahrzeugtyp (auch aus anderen Mods) einen vorderen und
            einen hinteren Kupplungspunkt.
    WARUM:  Im normalen Spiel haben viele Autos nur EINEN Haken (hinten), weil
            sie nie selbst gezogen werden. In einem Zug aus mehreren Fahrzeugen muss aber fast
            jedes Fahrzeug vorne gezogen werden UND hinten ziehen.
    WANN:   Einmal beim Laden der Welt (Ereignis OnInitGlobalModData).

    So liegen die Punkte (Blick von oben, Fahrtrichtung nach rechts):

            "trailer"                                   "trailerfront"
               (hinten)                                     (vorne)
                 o----[==========  Fahrzeug  ==========]----o
                 |<-- halbe Laenge + 0.15 -->|<-- halbe Laenge + 0.15 -->|
                                         Mitte
============================================================================]]


-- ############################################################################
-- ##  EINEN KUPPLUNGSPUNKT ERGAENZEN
-- ############################################################################

--- Legt einen Kupplungspunkt an, falls das Fahrzeug ihn noch nicht hat.
--  script     Bauplan des Fahrzeugtyps (VehicleScript), gilt fuer ALLE Autos dieses Typs
--  attachId   Name des Punkts: "trailer" (hinten) oder "trailerfront" (vorne)
--  isFront    true = vorne anbringen, false = hinten
--  height     Hoehe des Punkts (0 = Fahrzeugmitte wie bisher; siehe avgWheelHeight)
local function ensureAttachment(script, attachId, isFront, height)
    if script:getAttachmentById(attachId) then return end   -- schon vorhanden -> nichts tun (Original bleibt unangetastet)

    local ext = script:getExtents()          -- Groesse des Fahrzeugs: x = Breite, y = Hoehe, z = Laenge
    if not ext then return end

    -- !! ACHTUNG: Die Extents sind schon mit der Modellgroesse multipliziert, die Punkte aber nicht.
    --    Deshalb teilen wir unten durch "scale", sonst saessen die Haken bei grossen Modellen zu weit draussen.
    local scale = script:getModelScale() or 1.0
    if scale <= 0 then scale = 1.0 end

    -- Halbe Fahrzeuglänge plus kleiner Abstand für die Deichsel/Kupplung
    local halfLen = (ext:z() / scale) * 0.5 + 0.15

    local attach = ModelAttachment.new(attachId)
    -- Koordinaten des Punkts relativ zur Fahrzeugmitte:  (seitlich, hoch, vor/zurueck)
    local y = height or 0.0
    if isFront then
        attach:getOffset():set(0.0, y, halfLen)      -- +z = nach vorne
    else
        attach:getOffset():set(0.0, y, -halfLen)     -- -z = nach hinten
    end

    script:addAttachment(attach)
end


-- ############################################################################
-- ##  ALLE FAHRZEUGTYPEN DURCHGEHEN
-- ############################################################################

--- (ab 0.16) Hoehe der Radmitten (Mittelwert aller Raeder) = gute Hoehe fuer einen Haken. nil = keine Raeder.
--  >> WARUM: Bei manchen Mod-Fahrzeugen liegt die Fahrzeugmitte (Hoehe 0) sehr hoch, z.B. beim Container-Auflieger
--     der W900-Mod (rSemiTruck). Ein Haken dort zieht das angehaengte Fahrzeug nach oben.
local function avgWheelHeight(script)
    local ok, h = pcall(function()
        local n = script:getWheelCount()
        if not n or n <= 0 then return nil end
        local sum = 0
        for w = 0, n - 1 do sum = sum + script:getWheel(w):getOffset():y() end
        return sum / n
    end)
    return ok and h or nil
end

local function patchAllVehicleAttachments()
    local scripts = getScriptManager():getAllVehicleScripts()   -- Liste aller Fahrzeugtypen (Java-Liste, beginnt bei 0)
    local lowered = 0
    for i = 0, scripts:size() - 1 do
        local script = scripts:get(i)
        -- Hoehe: Hat das Fahrzeug schon einen der beiden Haken (fast alle Autos des Spiels), bleibt alles wie bisher (0).
        -- Hat es KEINEN (z.B. Sattelauflieger aus Mods, die nur einen Koenigszapfen "trailerTruck" haben),
        -- kommen beide neuen Haken auf Hoehe der Radmitten.
        local height = nil
        if not script:getAttachmentById("trailer") and not script:getAttachmentById("trailerfront") then
            height = avgWheelHeight(script)
            if height then lowered = lowered + 1 end
        end
        -- "trailer" ist in PZ der hintere Haken, "trailerfront" der vordere
        ensureAttachment(script, "trailer", false, height)
        ensureAttachment(script, "trailerfront", true, height)
    end
    print("[MultiTow] hitches at wheel height for " .. lowered .. " vehicle type(s) without own hitches")
    print("[MultiTow] All vehicles and trailers enabled for multi-coupling.")   -- steht in der console.txt
end

-- >> WARUM gerade dieses Ereignis: Es kommt nachdem alle Fahrzeug-Skripte (auch von anderen Mods) geladen sind,
--    aber bevor die ersten Fahrzeuge in der Welt auftauchen.
Events.OnInitGlobalModData.Add(patchAllVehicleAttachments)