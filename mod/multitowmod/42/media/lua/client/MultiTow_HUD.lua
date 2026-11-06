--[[==========================================================================
    MultiTow_HUD.lua                                           [ client ]
  ----------------------------------------------------------------------------
    Multi-Vehicle Towing: Zug-Anzeige (kleines Fenster beim Fahren)

    Sichtbar, solange die eigene Figur in einem Fahrzeug sitzt, das zu einem
    Zug gehoert. So sieht das Fenster aus:

        +--------------------------------------------+
        | Multi-Tow                                  |   <- Titel (gelb)
        | Fahrzeuge     4 / 6                        |
        | Tempo         52 / 60 km/h                 |   (orange, wenn zu schnell)
        | Belastung     [#######-----]  58 %  (#2)   |   <- Balken gruen..rot, #2 = 2. Verbindung
        | Schwaechste   [##########--]  83 %  (#1)   |
        | Gewicht       5230 kg                      |
        | Sprit         41 %  (x1.40)                |   (orange unter 15 %)
        +--------------------------------------------+

    Zeilen (jede im Optionsmenue abschaltbar):
      Fahrzeuge       Anzahl im Zug (und Grenze, falls eingestellt)
      Tempo           aktuelle Geschwindigkeit (und Tempolimit, falls eingestellt) in km/h oder mph
      Belastung       am staerksten belastete Verbindung, als Balken gruen -> rot
      Zustand         schwaechste Verbindung (Verschleiss), als Balken
      Gewicht         Gesamtgewicht des Zuges (mit eingestelltem Anteil der Ladung)
      Sprit           Tankfuellung des Zugfahrzeugs und Mehrverbrauch
    Position: frei verschiebbar (mit der Maus ziehen, wird gemerkt) oder an
              einer der 4 Ecken / 4 Seiten.

    AUFBAU DIESER DATEI (drei Schichten, von "rechnen" zu "malen"):
      1. hudData()   sammelt die Zahlen       (kein Zeichnen -> einfach zu testen)
      2. hudLines()  macht daraus Textzeilen
      3. MultiTowHUD zeichnet die Zeilen ins Fenster
============================================================================]]

require "ISUI/ISPanel"
require "MultiTow_Common"
require "MultiTow_Train"

-- Das Fenster ist ein "ISPanel" des Spiels (rechteckiges Feld der Oberflaeche), erweitert um unsere Funktionen
MultiTowHUD = ISPanel:derive("MultiTowHUD")

-- Reihenfolge = Auswahl im Optionsmenue
MultiTow.HUD_POS = { "free", "topleft", "top", "topright", "right", "bottomright", "bottom", "bottomleft", "left" }

local POS_FILE = "MultiTow_HUD.txt"   -- hier merkt sich die freie Position (Ordner Zomboid/Lua)
local FONT = UIFont.Small
local PAD = 8          -- Innenabstand des Fensters in Pixeln
local BAR_W = 90       -- Breite eines Balkens in Pixeln
local UPDATE_MS = 250  -- Zahlen 4x pro Sekunde auffrischen (gezeichnet wird trotzdem jedes Bild)

local function fontHgt()
    return getTextManager():getFontHeight(FONT)
end

local function textW(s)
    return getTextManager():MeasureStringX(FONT, s)   -- Breite eines Textes in Pixeln
end

--- Wert auf den Bereich 0..1 begrenzen
local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- Farbe von gruen (0) ueber gelb nach rot (1), wie das Band an der Verbindung
--     s = 0.0  ->  rot 0, gruen 1        (gruen)
--     s = 0.5  ->  rot 1, gruen 1        (gelb)
--     s = 1.0  ->  rot 1, gruen 0        (rot)
local function stressColor(s)
    return clamp01(s * 2), clamp01((1 - s) * 2), 0
end

-- ---------------------------------------------------------------------------
-- Daten fuer die Anzeige (ohne Zeichnen, damit es testbar bleibt)
-- ---------------------------------------------------------------------------
local shownStress = 0   -- angezeigte (geglaettete) Belastung

--- Alle Zahlen fuer die Anzeige.  Gibt nil zurueck, wenn die Figur in keinem Zug sitzt.
--  player = die eigene Figur,  dt = Sekunden seit dem letzten Aufruf (fuers Glaetten)
function MultiTow.hudData(player, dt)
    local veh = player and player:getVehicle()
    if not veh or not (veh:getVehicleTowing() or veh:getVehicleTowedBy()) then return nil end
    local list = MultiTow.trainVehicles(veh)   -- {Zugfahrzeug, 1. Anhaengsel, 2. ...}
    local head = list[1]
    local d = { count = #list, max = MultiTow.getMaxFor(head) }

    -- Tempo in der gewaehlten Einheit; Limit gilt erst ab 3 Fahrzeugen
    local mph = MultiTow.Settings.speedUnit == "mph"
    local kmh = math.abs(head:getCurrentSpeedKmHour())
    d.unit = mph and "mph" or "km/h"
    d.speed = mph and kmh / 1.609344 or kmh        -- 1 Meile = 1.609344 km
    local limit = tonumber(MultiTow.trainSetting(head, "speedCar", "speedTruck")) or 0
    d.limit = (#list >= 3 and limit > 0) and limit or nil

    -- staerkste Belastung, schwaechste Verbindung, Gewicht
    --   i = Position im Zug (1 = Zugfahrzeug). Die Verbindung VOR Fahrzeug i hat die Nummer i - 1.
    local maxS, maxAt, minC, minAt, weight = 0, nil, nil, nil, 0
    for i, v in ipairs(list) do
        weight = weight + MultiTow.trainMassOf(v)
        if i > 1 then
            local s = multiTowLinkStress and multiTowLinkStress(v) or -1
            if s and s > maxS then maxS, maxAt = s, i - 1 end
            if MultiTow.linkWears(v) then
                local c = MultiTow.linkCondition(v)
                if c and (not minC or c < minC) then minC, minAt = c, i - 1 end
            end
        end
    end
    -- schnell rot werden, langsam wieder gruen (kein Flackern)
    --   steigt der Wert: in ca. 1/12 Sekunde hinterher;   faellt er: hoechstens 0.8 pro Sekunde
    dt = dt or 0.25
    if maxS > shownStress then
        shownStress = shownStress + (maxS - shownStress) * math.min(1, dt * 12)
    else
        shownStress = math.max(maxS, shownStress - dt * 0.8)
    end
    d.stress, d.stressAt = shownStress, maxAt
    d.wearOn = (MultiTow.WEAR_FACTORS[tonumber(MultiTow.Settings.wear) or 1] or 0) > 0
    d.cond, d.condAt = minC, minAt
    d.weight = weight

    -- Sprit des Zugfahrzeugs (Anteil 0..1)
    pcall(function()
        local tank = head:getPartById("GasTank")
        if tank and tank:getContainerCapacity() > 0 then
            d.fuel = tank:getContainerContentAmount() / tank:getContainerCapacity()
        end
    end)
    d.fuelMult = MultiTow.trainFuelMultiplier(head)
    return d
end

-- Zeilen fuer die Anzeige: { label, text, bar (0..1 oder nil), r, g, b }
--   label = Text links,  text = Wert rechts,  bar = Fuellung eines Balkens (nil = kein Balken)
--   r, g, b = Farbe des Balkens; bei Zeilen OHNE Balken die Farbe des Wertes (nil = weiss)
function MultiTow.hudLines(d)
    local S = MultiTow.Settings
    local lines = {}
    if S.hudCount ~= false then
        local t = tostring(d.count)
        if d.max and d.max > 0 then t = t .. " / " .. tostring(d.max) end
        table.insert(lines, { getText("UI_MultiTow_HudVehicles"), t })
    end
    if S.hudSpeed ~= false then
        local t = tostring(math.floor(d.speed + 0.5))
        if d.limit then t = t .. " / " .. tostring(math.floor(d.limit + 0.5)) end
        local over = d.limit and d.speed > d.limit + 1          -- 1 km/h (mph) Toleranz
        table.insert(lines, { getText("UI_MultiTow_HudSpeed"), t .. " " .. d.unit, nil, over and 1 or nil, over and 0.6 or nil, over and 0.3 or nil })
    end
    if S.hudStress ~= false then
        local r, g, b = stressColor(d.stress)
        local t = tostring(math.floor(d.stress * 100 + 0.5)) .. " %"
        if d.stressAt and d.stress >= 0.05 then t = t .. "  (#" .. d.stressAt .. ")" end   -- Nummer erst ab 5 %
        table.insert(lines, { getText("UI_MultiTow_HudStress"), t, d.stress, r, g, b })
    end
    if S.hudCond ~= false and d.wearOn and d.cond then          -- nur wenn Verschleiss an ist
        local c = d.cond / 100
        local r, g, b = stressColor(1 - c)                       -- umgekehrt: voller Zustand = gruen
        local t = tostring(math.floor(d.cond + 0.5)) .. " %"
        if d.condAt then t = t .. "  (#" .. d.condAt .. ")" end
        table.insert(lines, { getText("UI_MultiTow_HudCond"), t, c, r, g, b })
    end
    if S.hudWeight ~= false then
        table.insert(lines, { getText("UI_MultiTow_HudWeight"), tostring(math.floor(d.weight + 0.5)) .. " kg" })
    end
    if S.hudFuel ~= false and d.fuel then
        local t = tostring(math.floor(d.fuel * 100 + 0.5)) .. " %"
        if d.fuelMult and d.fuelMult > 1.001 then t = t .. "  (x" .. string.format("%.2f", d.fuelMult) .. ")" end
        local low = d.fuel < 0.15                                -- unter 15 % -> orange
        table.insert(lines, { getText("UI_MultiTow_HudFuel"), t, nil, low and 1 or nil, low and 0.6 or nil, low and 0.3 or nil })
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- Fenster
-- ---------------------------------------------------------------------------

--- Neues (noch leeres, unsichtbares) Fenster. Groesse und Position setzt layout() spaeter.
function MultiTowHUD:new()
    local o = ISPanel.new(self, 100, 100, 200, 80)
    o.background = false      -- den Standard-Hintergrund malen wir selbst (prerender)
    o.lines = {}
    o.nextUpdate = 0
    o.lastUpdate = 0
    return o
end

--- Ist Position "Frei (mit der Maus ziehen)" gewaehlt?
function MultiTowHUD:isFree()
    return MultiTow.HUD_POS[tonumber(MultiTow.Settings.hudPos) or 2] == "free"
end

-- Groesse aus dem Inhalt, Position aus der Einstellung
function MultiTowHUD:layout()
    -- -> Groesse: so breit wie die laengste Beschriftung + laengster Wert (+ Balken)
    local lh = fontHgt() + 4                    -- Zeilenhoehe
    local labelW, valueW = 0, 0
    for _, l in ipairs(self.lines) do
        labelW = math.max(labelW, textW(l[1]))
        valueW = math.max(valueW, textW(l[2]) + (l[3] and (BAR_W + 8) or 0))
    end
    self.labelW = labelW
    local title = getText("UI_MultiTow_HudTitle")
    local w = math.max(textW(title), labelW + 12 + valueW) + PAD * 2
    local h = PAD * 2 + lh * (#self.lines + 1)  -- +1 fuer die Titelzeile
    self:setWidth(w)
    self:setHeight(h)

    -- -> Position
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local pos = MultiTow.HUD_POS[tonumber(MultiTow.Settings.hudPos) or 2] or "topleft"
    if pos == "free" then
        -- frei: gemerkte Position, aber immer ganz auf dem Bildschirm
        self:setX(math.max(0, math.min(sw - w, self:getX())))
        self:setY(math.max(0, math.min(sh - h, self:getY())))
        return
    end
    -- Abstaende so, dass die Spiel-Oberflaeche frei bleibt (Seitenleiste links, Stimmungen rechts, Armaturen unten)
    --
    --     topleft ------- top ------- topright
    --        |                            |
    --      left        (Mitte)          right
    --        |                            |
    --   bottomleft ---- bottom ---- bottomright
    --                  ^^^^^^ 240 px hoeher, damit das Armaturenbrett im Auto frei bleibt
    local left, right, top, bottom = 70, sw - w - 90, 20, sh - h - 240
    local cx, cy = math.floor((sw - w) / 2), math.floor((sh - h) / 2)
    local X = { topleft = left, top = cx, topright = right, right = right, bottomright = right, bottom = cx, bottomleft = left, left = left }
    local Y = { topleft = top, top = top, topright = top, right = cy, bottomright = sh - h - 20, bottom = bottom, bottomleft = sh - h - 20, left = cy }
    self:setX(X[pos] or left)
    self:setY(Y[pos] or top)
end

-- Aufruf aus OnTick (ein unsichtbares Fenster bekommt vom Spiel kein update(), muss sich aber selbst einblenden)
function MultiTowHUD:tick()
    local now = getTimestampMs()
    if now < self.nextUpdate then return end
    self.nextUpdate = now + UPDATE_MS
    -- dt = vergangene Sekunden (beim ersten Mal 0.25), hoechstens 1
    local dt = self.lastUpdate > 0 and math.min(1, (now - self.lastUpdate) / 1000) or 0.25
    self.lastUpdate = now
    local d = MultiTow.Settings.enabled and MultiTow.Settings.hud ~= false and MultiTow.hudData(getPlayer(), dt) or nil
    if not d then
        self:setVisible(false)   -- kein Zug / Option aus -> Fenster verstecken
        return
    end
    self.lines = MultiTow.hudLines(d)
    self:layout()
    self:setVisible(true)
end

--- Hintergrund: halbdurchsichtiges Dunkelgrau mit grauem Rand (prerender = VOR dem Inhalt)
function MultiTowHUD:prerender()
    self:drawRect(0, 0, self.width, self.height, 0.6, 0.05, 0.05, 0.05)
    self:drawRectBorder(0, 0, self.width, self.height, 0.7, 0.45, 0.45, 0.45)
end

--- Inhalt: Titel und Zeilen. (Werte bei drawRect/drawText: x, y, ..., Deckkraft, rot, gruen, blau)
function MultiTowHUD:render()
    local lh = fontHgt() + 4
    local y = PAD
    self:drawText(getText("UI_MultiTow_HudTitle"), PAD, y, 1, 0.85, 0.4, 1, FONT)
    y = y + lh
    local vx = PAD + (self.labelW or 0) + 12      -- hier beginnt die Werte-Spalte
    for _, l in ipairs(self.lines) do
        self:drawText(l[1], PAD, y, 0.8, 0.8, 0.8, 1, FONT)
        local x = vx
        if l[3] then
            -- Balken:  dunkler Hintergrund, farbige Fuellung, grauer Rand
            local bh = math.max(6, lh - 10)
            local by = y + math.floor((lh - 4 - bh) / 2)
            self:drawRect(x, by, BAR_W, bh, 0.8, 0.15, 0.15, 0.15)
            self:drawRect(x, by, math.floor(BAR_W * clamp01(l[3])), bh, 0.9, l[4] or 1, l[5] or 1, l[6] or 1)
            self:drawRectBorder(x, by, BAR_W, bh, 0.8, 0.4, 0.4, 0.4)
            x = x + BAR_W + 8
        end
        -- Farbe des Wertes: nur bei Zeilen ohne Balken die Zeilenfarbe, sonst weiss
        self:drawText(l[2], x, y, l[4] and l[3] == nil and l[4] or 1, l[5] and l[3] == nil and l[5] or 1, l[6] and l[3] == nil and l[6] or 1, 1, FONT)
        y = y + lh
    end
end

-- Freie Position: mit der Maus ziehen und beim Loslassen merken
function MultiTowHUD:onMouseUp(x, y)
    ISPanel.onMouseUp(self, x, y)
    if self:isFree() then MultiTow.hudSavePos(self:getX(), self:getY()) end
end

-- (dasselbe, wenn die Maus beim Loslassen schon ausserhalb des Fensters ist)
function MultiTowHUD:onMouseUpOutside(x, y)
    ISPanel.onMouseUpOutside(self, x, y)
    if self:isFree() then MultiTow.hudSavePos(self:getX(), self:getY()) end
end

--- Freie Position in die Datei Zomboid/Lua/MultiTow_HUD.txt schreiben, Inhalt z.B. "812,64"
function MultiTow.hudSavePos(x, y)
    pcall(function()
        local f = getFileWriter(POS_FILE, true, false)   -- true = Datei anlegen, false = ueberschreiben (nicht anhaengen)
        f:write(tostring(math.floor(x)) .. "," .. tostring(math.floor(y)))
        f:close()
    end)
end

--- Gemerkte Position lesen. Gibt x, y zurueck oder nil, nil (Datei fehlt / unlesbar)
function MultiTow.hudLoadPos()
    local x, y = nil, nil
    pcall(function()
        local f = getFileReader(POS_FILE, false)
        if f then
            local line = f:readLine()
            f:close()
            if line then
                -- Muster: Zahl, Komma, Zahl (Leerzeichen erlaubt, Minus erlaubt)
                local a, b = string.match(line, "^%s*(-?%d+)%s*,%s*(-?%d+)")
                x, y = tonumber(a), tonumber(b)
            end
        end
    end)
    return x, y
end

-- Einstellungen uebernehmen (aus dem Optionsmenue): Ziehen nur im freien Modus, sonst klickt man durch
--   >> WARUM durchklicken: Sitzt das Fenster fest in einer Ecke, soll es keine Mausklicks ins Spiel "verschlucken".
function MultiTow.hudApplySettings()
    local hud = MultiTow.hud
    if not hud then return end
    local free = hud:isFree()
    hud.moveWithMouse = free
    pcall(function() hud.javaObject:setConsumeMouseEvents(free) end)
    if free and not hud.posLoaded then        -- gemerkte Position nur einmal laden
        hud.posLoaded = true
        local x, y = MultiTow.hudLoadPos()
        if x and y then
            hud:setX(x)
            hud:setY(y)
        end
    end
    hud.nextUpdate = 0                        -- sofort neu aufbauen
end

Events.OnTick.Add(function()
    if MultiTow.hud then MultiTow.hud:tick() end
end)

-- Beim Spielstart das Fenster EINMAL anlegen (es bleibt dann die ganze Zeit da, nur ein-/ausgeblendet)
Events.OnGameStart.Add(function()
    if MultiTow.hud then return end
    local hud = MultiTowHUD:new()
    hud:initialise()
    hud:addToUIManager()
    hud:setVisible(false)
    MultiTow.hud = hud
    MultiTow.hudApplySettings()
end)
