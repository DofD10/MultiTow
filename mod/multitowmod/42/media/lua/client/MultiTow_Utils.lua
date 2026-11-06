--[[==========================================================================
    MultiTow_Utils.lua                                         [ client ]
  ----------------------------------------------------------------------------
    WAS:    Nur noch ein Platzhalter (eine "Weiterleitung").
    WARUM:  Frueher standen hier alle Hilfsfunktionen. Seit dem Multiplayer
            braucht auch der Server sie, deshalb sind sie nach
            shared/MultiTow_Common.lua umgezogen ("shared" laedt Client
            UND Server, "client" nur der Spieler-PC).
    NOCH DA, weil aeltere Dateien weiterhin  require "MultiTow_Utils"  schreiben.
            Sobald das keine Datei mehr tut, kann diese Datei weg.
============================================================================]]

require "MultiTow_Common"   -- <- laedt die eigentlichen Hilfsfunktionen
