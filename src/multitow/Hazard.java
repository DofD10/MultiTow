package multitow;

import se.krka.kahlua.vm.KahluaTable;
import zombie.core.skinnedmodel.model.ModelInstance;
import zombie.core.skinnedmodel.model.VehicleModelInstance;
import zombie.vehicles.BaseVehicle;

/**
 * Warnblinker fuer gezogene Fahrzeuge.
 * Ob er an ist, steht beim Zugfahrzeug (modData "MultiTowHazard" = true), damit es im Multiplayer alle sehen.
 * Wie er aussieht, stellt jeder Spieler selbst ein:
 *   Stil: 0 = aus, 1 = amerikanisch (Rueck- und Bremslichter blinken rot), 2 = europaeisch (wie 1, dazu orangefarbenes
 *         Licht am Heck - das Licht selbst setzt MultiTow_Hazard.lua, weil Lichtquellen der Welt dort einfacher sind)
 *   Umfang: 1 = nur das letzte Fahrzeug, 2 = alle angekoppelten Fahrzeuge
 * Die Rueckleuchten leuchten im Fahrzeugbild nur in der Farbe, die das Spiel gemalt hat (rot); die Farbe laesst sich
 * nicht aendern, nur an/aus.
 *
 * <pre>
 *  ABLAUF PRO BILD (fuer jedes sichtbare Fahrzeug)
 *
 *    Spiel: BaseVehicle.updateLights()
 *      |
 *      |-- [PatchHazardLights.enter] beforeUpdateLights
 *      |       shouldBlink?  ja  -&gt; Bremslicht-Schalter = Takt (an/aus)
 *      |                     nein -&gt; falls wir ihn gesteuert hatten: wieder aus
 *      |
 *      |-- Spiel setzt die Lichter im Fahrzeugbild (braucht Batterie im Fahrzeug!)
 *      |
 *      '-- [PatchHazardLights.exit]  afterUpdateLights
 *              shouldBlink?  ja  -&gt; Lichter im Bild direkt setzen (klappt auch ohne Batterie)
 *
 *  Takt (fuer ALLE Fahrzeuge gleich, aus der Uhrzeit berechnet):
 *    |####|    |####|    |####|        # = an (400 ms), Luecke = aus (400 ms)
 * </pre>
 *
 * !! ACHTUNG: Alles hier ist "nur Anzeige". Jeder Fehler wird verschluckt -
 *    ein kaputter Warnblinker darf niemals die Fahrphysik oder das Spiel stoeren.
 */
public final class Hazard {
    public static final String FLAG = "MultiTowHazard";   // Name des Eintrags im modData des Zugfahrzeugs
    /** Takt: 400 ms an, 400 ms aus (ca. 1,25 Mal pro Sekunde, wie ein echter Warnblinker). */
    public static final long HALF_PERIOD_MS = 400L;

    private static volatile int style = 2;   // 0 = aus, 1 = amerikanisch, 2 = europaeisch
    private static volatile int scope = 1;   // 1 = nur letztes Fahrzeug, 2 = alle gezogenen

    // Positionen der Lichter im Fahrzeugbild (siehe BaseVehicle.updateLights)
    //
    //   textureLightsEnables2[...]   (0 = aus, 1 = an)
    //   +-------+----------------------------+
    //   | 5, 9  | Bremslichter               |
    //   | 12, 1 | Ruecklichter rechts/links  |
    //   | 4, 8  | Scheinwerfer (nutzen wir nicht) |
    //   +-------+----------------------------+
    private static final int STOP_A = 5, STOP_B = 9, REAR_RIGHT = 12, REAR_LEFT = 1;

    private Hazard() {
    }

    /** Einstellungen aus Lua uebernehmen (unsinnige Werte werden auf erlaubte begrenzt). */
    public static void configure(int newStyle, int newScope) {
        style = Math.max(0, Math.min(2, newStyle));
        scope = newScope == 2 ? 2 : 1;
    }

    // ---- einfache Abfragen ----
    public static int getStyle() {
        return style;
    }

    public static int getScope() {
        return scope;
    }

    /** true in der hellen Haelfte des Blinktakts (fuer alle Fahrzeuge gleich, daher blinken sie gemeinsam). */
    public static boolean blinkOn() {
        // Uhrzeit in ms / 400 = Nummer des Halbtakts.  gerade -> an, ungerade -> aus
        //   0..399 ms -> 0 (an),  400..799 -> 1 (aus),  800..1199 -> 2 (an) ...
        return (System.currentTimeMillis() / HALF_PERIOD_MS) % 2L == 0L;
    }

    /** Ist der Warnblinker fuer dieses Zugfahrzeug eingeschaltet? */
    public static boolean isOn(BaseVehicle head) {
        try {
            if (head == null || !head.hasModData()) {
                return false;
            }
            KahluaTable t = head.getModData();
            Object v = t.rawget(FLAG);
            return v instanceof Boolean && (Boolean) v;   // nur echtes true zaehlt (nil / Text -> aus)
        } catch (Throwable t) {
            return false;
        }
    }

    /** Zugfahrzeug der Kette (wie ChainTow.head, hier eigene Kopie, damit Hazard unabhaengig bleibt). */
    private static BaseVehicle head(BaseVehicle v) {
        int n = 0;
        while (v != null && v.getVehicleTowedBy() != null && n++ < 256) {
            v = v.getVehicleTowedBy();
        }
        return v;
    }

    //   Pruefung              | blinkt nicht, wenn ...
    //   ----------------------+------------------------------------------------
    //   Stil                  | "aus" gewaehlt
    //   gezogen?              | das Fahrzeug wird gar nicht gezogen (Zugfahrzeug blinkt selbst normal)
    //   Umfang                | "nur letztes" und hinten haengt noch eins dran
    //   Schalter + Batterie   | Warnblinker aus ODER Batterie des ZUGFAHRZEUGS leer
    /** Soll dieses (gezogene) Fahrzeug gerade blinken? Unabhaengig vom Takt. */
    public static boolean shouldBlink(BaseVehicle v) {
        if (style == 0 || v == null || v.getVehicleTowedBy() == null || !ChainTow.isActive()) {
            return false;
        }
        if (scope == 1 && v.getVehicleTowing() != null) {
            return false; // nur das letzte Fahrzeug
        }
        BaseVehicle h = head(v);
        return isOn(h) && h.getBatteryCharge() > 0.0F;
    }

    /**
     * Alle gezogenen Fahrzeuge in der Naehe (Abstand in Feldern), die gerade blinken sollen - fuer das orange Licht in Lua.
     * Die Liste wird hier in Java gebaut: die Fahrzeugliste der Zelle ist in Lua nicht immer benutzbar
     * (manche Optimierungs-Mods ersetzen sie durch eine eigene Klasse).
     */
    public static java.util.ArrayList<BaseVehicle> blinkingNear(float x, float y, float maxDist) {
        java.util.ArrayList<BaseVehicle> out = new java.util.ArrayList<>();
        try {
            zombie.iso.IsoCell cell = zombie.iso.IsoWorld.instance == null ? null : zombie.iso.IsoWorld.instance.currentCell;
            if (cell == null) {
                return out;
            }
            float max2 = maxDist * maxDist;   // Quadrat: spart die Wurzel beim Vergleichen
            for (BaseVehicle v : cell.getVehicles()) {   // Java-Liste: hier klappt das immer
                if (v.getVehicleTowedBy() == null || !shouldBlink(v)) {
                    continue;
                }
                float dx = v.getX() - x, dy = v.getY() - y;
                if (dx * dx + dy * dy <= max2) {
                    out.add(v);
                }
            }
        } catch (Throwable t) {
            // nur Anzeige
        }
        return out;
    }

    // ---- Merklisten ----
    // WeakHashMap: wird ein Fahrzeug entladen, verschwindet es von selbst aus DRIVEN (kein Speicherleck)
    /** Fahrzeuge, deren Bremslicht-Schalter wir gerade steuern (zum Zuruecksetzen, wenn der Warnblinker ausgeht). */
    private static final java.util.Set<BaseVehicle> DRIVEN = java.util.Collections.newSetFromMap(new java.util.WeakHashMap<>());
    private static final java.util.Set<Short> LOGGED = new java.util.HashSet<>();   // Fahrzeuge, die schon einmal im Log stehen

    /** Fehlersuche: wie oft das Spiel die Lichter eines blinkenden Fahrzeugs in 5 Sekunden neu setzt (einmal pro Fahrzeug). */
    private static final java.util.Map<Short, long[]> CALLS = new java.util.HashMap<>();

    // c[0] = Startzeit (oder -1 = fertig gemeldet),  c[1] = Anzahl Aufrufe
    //   >> WARUM: zeigte, dass manche Optimierungs-Mods die Lichter nur selten neu setzen
    //      (in einem Test nur 65 Mal in 5 s statt ca. 300)
    private static void countCall(BaseVehicle v) {
        long now = System.currentTimeMillis();
        long[] c = CALLS.get(v.vehicleId);
        if (c == null) {
            CALLS.put(v.vehicleId, new long[] { now, 1 });
            return;
        }
        if (c[0] < 0) {
            return; // schon gemeldet
        }
        c[1]++;
        if (now - c[0] >= 5000L) {
            System.out.println("[MultiTowCore] Hazard check: vehicle " + v.getId() + " lights updated " + c[1]
                + " times in " + (now - c[0]) / 1000 + " s (about 300 = every frame; few = the game does not redraw it)");
            c[0] = -1;
        }
    }

    /** Vor BaseVehicle.updateLights: Bremslicht-Schalter im Takt an/aus. */
    public static void beforeUpdateLights(BaseVehicle v) {
        try {
            if (shouldBlink(v)) {
                countCall(v);
                DRIVEN.add(v);
                v.setStoplightsOn(blinkOn());   // Takt -> Bremslicht-Schalter
                if (LOGGED.add(v.vehicleId)) {
                    // einmal pro Fahrzeug ins Log, hilft bei der Fehlersuche
                    Object mi = v.sprite == null || v.sprite.modelSlot == null ? null : v.sprite.modelSlot.model;
                    System.out.println("[MultiTowCore] Hazard lights blinking on vehicle " + v.getId()
                        + " (style " + style + ", battery " + v.getBatteryCharge()
                        + ", model " + (mi == null ? "missing" : mi.getClass().getSimpleName()) + ")");
                }
            } else if (DRIVEN.remove(v)) {
                v.setStoplightsOn(false);   // Warnblinker aus: Schalter zuruecksetzen (sonst bliebe Bremslicht an)
            }
        } catch (Throwable t) {
            // nur Anzeige
        }
    }

    /** Nach BaseVehicle.updateLights (jedes Bild, solange das Fahrzeug zu sehen ist). */
    public static void afterUpdateLights(BaseVehicle v) {
        try {
            if (!shouldBlink(v)) {
                return;
            }
            ModelInstance mi = v.sprite == null || v.sprite.modelSlot == null ? null : v.sprite.modelSlot.model;
            if (!(mi instanceof VehicleModelInstance)) {   // kein Fahrzeugmodell (z.B. zu weit weg) -> nichts zu tun
                return;
            }
            VehicleModelInstance inst = (VehicleModelInstance) mi;
            float on = blinkOn() ? 1.0F : 0.0F;
            inst.textureLightsEnables2[STOP_A] = on;
            inst.textureLightsEnables2[STOP_B] = on;
            if (on > 0.0F) {
                // Ruecklichter im hellen Takt zusaetzlich an (im dunklen Takt bleibt, was das Spiel gesetzt hat)
                inst.textureLightsEnables2[REAR_RIGHT] = 1.0F;
                inst.textureLightsEnables2[REAR_LEFT] = 1.0F;
            }
        } catch (Throwable t) {
            // nur Anzeige
        }
    }
}
