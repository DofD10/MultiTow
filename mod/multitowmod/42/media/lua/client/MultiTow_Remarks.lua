--[[==========================================================================
    MultiTow_Remarks.lua                                       [ client ]
  ----------------------------------------------------------------------------
    Sprueche der Figur nach dem Ankuppeln
    (Option "Sprueche beim Ankuppeln", nur fuer dich sichtbar)
============================================================================]]

require "MultiTow_Common"

-- Sprueche der Figur nach dem Ankuppeln (Option "Sprueche beim Ankuppeln").
--
-- Mit Zuglaengen-Grenze: 4 Stufen, je naeher die Grenze, desto muehsamer klingt es:
--   Stufe 1: noch 3 oder mehr Plaetze frei   Stufe 2: noch 2 frei
--   Stufe 3: noch 1 frei                      Stufe 4: Grenze erreicht
-- Ohne Grenze (unbegrenzt): 6 Stufen immer sarkastischerer Sprueche ueber die Zuglaenge:
--   2 / 3 / 4 / 5-6 / 7-9 / 10+ Fahrzeuge
-- Pro Stufe gibt es 10 Texte (UI.json: UI_MultiTow_Limit<Stufe>_<1..10> und UI_MultiTow_Train<Stufe>_<1..10>),
-- einer davon wird zufaellig gewaehlt (nie zweimal hintereinander derselbe). %1 = Fahrzeuge im Zug, %2 = Grenze.
--
--   Beispiel Schluessel:  UI_MultiTow_Limit3_7   = Grenze-Stufe 3, Text Nr. 7
--                         UI_MultiTow_Train6_2   = ohne Grenze, 10+ Fahrzeuge, Text Nr. 2

local TEXTS_PER_STAGE = 10   -- !! ACHTUNG: muss zur Anzahl der Texte in UI.json passen, sonst fehlen Texte
local lastPick = {}          -- Stufe -> zuletzt gezeigte Text-Nummer (gegen direkte Wiederholung)

--- Stufe bei eingestellter Grenze:  wie viele Plaetze sind NOCH frei?
--    rest = Grenze - Zuglaenge      >=3 -> 1   2 -> 2   1 -> 3   0 -> 4
local function limitStage(length, max)
    local rest = max - length
    if rest >= 3 then return 1 end
    if rest == 2 then return 2 end
    if rest == 1 then return 3 end
    return 4
end

--- Stufe ohne Grenze: je laenger der Zug, desto sarkastischer.
local function trainStage(length)
    if length <= 2 then return 1 end
    if length == 3 then return 2 end
    if length == 4 then return 3 end
    if length <= 6 then return 4 end
    if length <= 9 then return 5 end
    return 6
end

--- Zufaelligen Text der Stufe waehlen, aber nie denselben wie beim letzten Mal.
--  prefix z.B. "UI_MultiTow_Limit2"  ->  Ergebnis z.B. "UI_MultiTow_Limit2_5"
local function pick(prefix)
    local n = ZombRand(TEXTS_PER_STAGE) + 1      -- ZombRand(10) liefert 0..9, also +1 -> 1..10
    if n == lastPick[prefix] then
        n = (n % TEXTS_PER_STAGE) + 1            -- gleiche Zahl? dann die naechste (10 springt auf 1)
    end
    lastPick[prefix] = n
    return prefix .. "_" .. n
end

-- Text ueber der Figur anzeigen (nur auf diesem PC, nicht im Chat)
--   >> WARUM zwei Wege: addLineChatElement zeigt den Text nur lokal an. Falls es die Funktion
--      in einer Spielversion nicht gibt, nehmen wir Say (das ist dann aber fuer alle sichtbar).
local function say(player, text)
    local ok = pcall(function() player:addLineChatElement(text) end)
    if not ok then
        pcall(function() player:Say(text) end)
    end
end

-- length = Fahrzeuge im Zug nach dem Ankuppeln, max = Grenze (0 = unbegrenzt)
function MultiTow.trainRemark(player, length, max)
    if not player or MultiTow.Settings.remarks == false then return end   -- Option aus
    length = tonumber(length) or 0
    max = tonumber(max) or 0
    if length < 2 then return end            -- ein einzelnes Fahrzeug ist kein Zug
    local key
    if max > 0 then
        key = pick("UI_MultiTow_Limit" .. limitStage(length, max))
    else
        key = pick("UI_MultiTow_Train" .. trainStage(length))
    end
    say(player, getText(key, tostring(length), tostring(max)))   -- %1 = Laenge, %2 = Grenze
end

-- Zuglaenge und Grenze fuer ein gerade gekuppeltes Paar (front -> rear)
function MultiTow.remarkForLink(player, front, rear)
    if not front or not rear then return end
    local length = MultiTow.trainLength(front, rear)
    local max = MultiTow.getMaxFor(MultiTow.getHead(front))   -- Grenze haengt vom Zugfahrzeug ab (PKW oder LKW)
    MultiTow.trainRemark(player, length, max)
end
