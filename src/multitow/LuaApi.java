package multitow;

import se.krka.kahlua.integration.annotations.LuaMethod;

/**
 * Globale Lua-Funktionen der Java-Erweiterung.
 *
 * <h3>Wie kommt Java nach Lua?</h3>
 * Jede Methode mit {@code @LuaMethod(name = "...", global = true)} ist im Lua-Teil
 * als ganz normale globale Funktion aufrufbar:
 * <pre>
 *   Java:  @LuaMethod(name = "multiTowIsTruck", global = true)  multiTowIsTruck(String)
 *   Lua:   if multiTowIsTruck(veh:getScriptName()) then ... end
 * </pre>
 *
 * <h3>Zahlen</h3>
 * Lua kennt nur EINE Zahlenart (double). Deshalb nehmen alle Methoden {@code double}
 * und wandeln selbst in int/float um ({@code Math.round}, {@code (float)}).
 *
 * <h3>Fehlt der Java-Teil?</h3>
 * Dann gibt es diese Funktionen in Lua einfach nicht (nil). Der Lua-Teil prueft deshalb
 * immer vorher: {@code if multiTowSnapLink then ... end}.
 *
 * <pre>
 *  Uebersicht              | Funktion(en)
 *  ------------------------+---------------------------------------------------------
 *  Info                    | multiTowCoreVersion, multiTowNetRole
 *  Regeln / Einstellungen  | multiTowConfigure, multiTowConfigureTrain, ...PowerBoost, multiTowSetAssist
 *  Warnblinker             | multiTowSetHazard, ...BlinkOn, ...VehiclesNear, ...ShouldBlink
 *  Sichtbare Verbindungen  | multiTowSetLinkStyle, ...ShowLinks, ...ShowLinksNear, ...
 *  Verschleiss             | multiTowLinkStress, multiTowSnapLink, multiTowIsBarLink
 *  Ereignisse Java -> Lua  | multiTowPopEvent
 * </pre>
 */
public class LuaApi {
    // ==================== Info ====================
    /** Versionsnummer des Java-Teils, z.B. "0.15.0" - oder "0.15.0 (inactive)", wenn er sich abgeschaltet hat. */
    @LuaMethod(name = "multiTowCoreVersion", global = true)
    public static String multiTowCoreVersion() {
        return ChainTow.VERSION + (ChainTow.isActive() ? "" : " (inactive)");
    }

    // ==================== Regeln / Einstellungen ====================
    /**
     * Einstellungen aus dem Optionsmenue. Zugfahrzeug-Typ: PKW oder LKW (siehe ChainTow.isTruckName).
     * @param requireHook ab dem 3. Fahrzeug ist ein Haken noetig (normales Ankuppel-Menue des Spiels wird dann ausgeblendet)
     * @param maxCars     Hoechstzahl Fahrzeuge im Zug inkl. Zugfahrzeug bei PKW als Zugfahrzeug, 0 = unbegrenzt
     * @param fixedCars   fester Kraftfaktor (1.5/2/2.5/3) bei PKW, 0 = automatisch
     */
    @LuaMethod(name = "multiTowConfigure", global = true)
    public static void multiTowConfigure(boolean enabled, boolean requireHook,
                                         double maxCars, boolean boostCars, double fixedCars,
                                         double maxTrucks, boolean boostTrucks, double fixedTrucks) {
        ChainTow.configure(enabled, requireHook,
            (int) Math.round(maxCars), boostCars, (float) fixedCars,
            (int) Math.round(maxTrucks), boostTrucks, (float) fixedTrucks);
    }

    /**
     * Mithelfen (ab 0.15.0): gezogene Fahrzeuge mit laufendem Motor fahren mit diesem Anteil ihrer eigenen
     * Motorkraft mit (0..100 %, 0 = aus). Wirkt nur, wenn die Kraft-Erhoehung des Zugfahrzeugs aus ist.
     */
    @LuaMethod(name = "multiTowSetAssist", global = true)
    public static void multiTowSetAssist(double percent) {
        ChainTow.setAssist((float) (percent / 100.0));
    }

    /** true, wenn ein Fahrzeug mit diesem Skript-Namen als LKW zaehlt (fuer die Lua-Menues). */
    @LuaMethod(name = "multiTowIsTruck", global = true)
    public static boolean multiTowIsTruck(String scriptName) {
        return ChainTow.isTruckName(scriptName);
    }

    /** Zusatzkraft pro weiterem gezogenem Fahrzeug (0.6 = +60 %, 0 = aus). */
    @LuaMethod(name = "multiTowSetPowerBoost", global = true)
    public static void multiTowSetPowerBoost(double value) {
        ChainTow.setPowerBoost((float) value);
    }

    /** Aktuelle Zusatzkraft pro weiterem Fahrzeug (Gegenstueck zu multiTowSetPowerBoost). */
    @LuaMethod(name = "multiTowGetPowerBoost", global = true)
    public static double multiTowGetPowerBoost() {
        return ChainTow.getPowerBoost();
    }

    /**
     * Zug-Einstellungen: Zugbremse (0..100 %, 100 = wie selbst gefahren) und Hoechstgeschwindigkeit fuer Zuege ab
     * 3 Fahrzeugen in km/h (0 = aus), jeweils fuer PKW- und LKW-Zuege.
     */
    @LuaMethod(name = "multiTowConfigureTrain", global = true)
    public static void multiTowConfigureTrain(double brakeCarPct, double brakeTruckPct, double speedCarKmh, double speedTruckKmh) {
        ChainTow.configureTrain((float) (brakeCarPct / 100.0), (float) (brakeTruckPct / 100.0), (float) speedCarKmh, (float) speedTruckKmh);   // Lua: Prozent 0..100  ->  Java: Anteil 0..1
    }

    // ==================== Warnblinker (siehe Hazard.java und MultiTow_Hazard.lua) ====================
    /** Warnblinker-Darstellung: style 0 = aus, 1 = amerikanisch, 2 = europaeisch; scope 1 = letztes Fahrzeug, 2 = alle. */
    @LuaMethod(name = "multiTowSetHazard", global = true)
    public static void multiTowSetHazard(double style, double scope) {
        Hazard.configure((int) Math.round(style), (int) Math.round(scope));
    }

    /** true in der hellen Haelfte des Blinktakts (damit Lua das orange Licht im selben Takt schaltet). */
    @LuaMethod(name = "multiTowHazardBlinkOn", global = true)
    public static boolean multiTowHazardBlinkOn() {
        return Hazard.blinkOn();
    }

    /** Gezogene Fahrzeuge im Umkreis, die gerade blinken sollen (fuer das orange Licht). Gibt eine Liste zurueck. */
    @LuaMethod(name = "multiTowHazardVehiclesNear", global = true)
    public static java.util.ArrayList<zombie.vehicles.BaseVehicle> multiTowHazardVehiclesNear(double x, double y, double maxDist) {
        return Hazard.blinkingNear((float) x, (float) y, (float) maxDist);
    }

    /** Soll dieses (gezogene) Fahrzeug gerade blinken (Warnblinker an, Batterie, Umfang)? */
    @LuaMethod(name = "multiTowHazardShouldBlink", global = true)
    public static boolean multiTowHazardShouldBlink(zombie.vehicles.BaseVehicle v) {
        return Hazard.shouldBlink(v);
    }

    // ==================== Sichtbare Verbindungen (LinkVisual / LinkModels) ====================
    /** Sichtbare Ketten/Stangen: 0 = aus, 1 = Bild, 2 = 3D-Modell (Ketten; Stangen bleiben Bild). Persoenlich. */
    @LuaMethod(name = "multiTowSetLinkStyle", global = true)
    public static void multiTowSetLinkStyle(double mode) {
        LinkModels.setMode((int) Math.round(mode));
    }

    /** (ab 0.16, Test) 3D-Kette abstimmen: Variante 0..7 der Ausrichtung, Groessenfaktor (1 = wie berechnet). */
    @LuaMethod(name = "multiTowSetLinkModelTuning", global = true)
    public static void multiTowSetLinkModelTuning(double variant, double size) {
        LinkModels.setModelTuning((int) Math.round(variant), (float) size);
    }

    /** (ab 0.16, Test) Aktuelle Variante der Ausrichtung (0..7). */
    @LuaMethod(name = "multiTowGetLinkModelVariant", global = true)
    public static double multiTowGetLinkModelVariant() {
        return ModelLinkStyle.getVariant();
    }

    /** (ab 0.16, Test) Aktueller Groessenfaktor des 3D-Modells. */
    @LuaMethod(name = "multiTowGetLinkModelSize", global = true)
    public static double multiTowGetLinkModelSize() {
        return ModelLinkStyle.getSizeFactor();
    }

    // ==================== Verschleiss (MultiTow_Wear.lua) ====================
    /** Belastung der Verbindung vor diesem (hinteren) Fahrzeug: 0 = entspannt, 1 = kurz vor dem Reissen, -1 = keine. */
    @LuaMethod(name = "multiTowLinkStress", global = true)
    public static double multiTowLinkStress(zombie.vehicles.BaseVehicle rear) {
        return LinkVisual.stressOf(rear);
    }

    /** Verbindung vor diesem (hinteren) Fahrzeug reissen lassen (Verschleiss). true = gerissen. */
    @LuaMethod(name = "multiTowSnapLink", global = true)
    public static boolean multiTowSnapLink(zombie.vehicles.BaseVehicle rear) {
        return ChainTow.snapLink(rear);
    }

    /** true, wenn die Verbindung vor diesem (hinteren) Fahrzeug eine starre Abschleppstange ist. */
    @LuaMethod(name = "multiTowIsBarLink", global = true)
    public static boolean multiTowIsBarLink(zombie.vehicles.BaseVehicle rear) {
        return ChainTow.isBarLink(rear);
    }

    // ==================== Belastungs-Baender ====================
    /** Band-Anzeige der Verbindungen (gruen bis rot je nach Belastung) an/aus. Persoenliche Einstellung. */
    @LuaMethod(name = "multiTowSetShowLinks", global = true)
    public static void multiTowSetShowLinks(boolean on) {
        LinkVisual.setEnabled(on);
    }

    /** Baender automatisch zeigen, wenn die Figur zu Fuss in der Naehe einer Verbindung steht. */
    @LuaMethod(name = "multiTowSetShowLinksNear", global = true)
    public static void multiTowSetShowLinksNear(boolean on) {
        LinkVisual.setNear(on);
    }

    /** Abstand (in Feldern, etwa Metern) fuer die Naehe-Anzeige, Standard 2. */
    @LuaMethod(name = "multiTowSetLinkNearDistance", global = true)
    public static void multiTowSetLinkNearDistance(double d) {
        LinkVisual.setNearDistance((float) d);
    }

    /** Feineinstellung der Band-Anzeige fuer Tests: ab welchem Seil-Abstand Belastung beginnt und bis wann sie rot wird. */
    @LuaMethod(name = "multiTowSetLinkTuning", global = true)
    public static void multiTowSetLinkTuning(double ropeStart, double ropeRange) {
        LinkVisual.setTuning((float) ropeStart, (float) ropeRange);
    }

    // ==================== Netzwerk + Ereignisse ====================
    /** "server", "client" oder "sp" - wo laeuft dieser Java-Teil gerade? */
    @LuaMethod(name = "multiTowNetRole", global = true)
    public static String multiTowNetRole() {
        if (zombie.network.GameServer.server) {
            return "server";
        }
        return zombie.network.GameClient.client ? "client" : "sp";
    }

    /**
 * Naechstes Haken-Ereignis ("BREAK|x|y|z" / "RETURN|x|y|z") oder nil. Wird vom Lua-Teil jeden Tick abgefragt.
 * <p>Alle Arten: BREAK, RETURN, ATTACH, DETACH, SNAP - Aufbau siehe ChainTow.hookEvent / soundEvent
 * und die Zerlegung in MultiTow_Events.lua.
 * <p>&gt;&gt; WARUM ein "Briefkasten" statt Lua direkt aufzurufen: das Abkuppeln passiert mitten in der
 * Physik des Spiels; dort Lua zu starten waere riskant. Lua holt die Post spaeter in Ruhe ab.
 */
    @LuaMethod(name = "multiTowPopEvent", global = true)
    public static String multiTowPopEvent() {
        return ChainTow.popEvent();
    }
}
