package multitow;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentLinkedQueue;

import se.krka.kahlua.vm.KahluaTable;

import org.joml.Vector3f;

import zombie.ZomboidFileSystem;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.core.physics.Bullet;
import zombie.core.physics.CarController;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.PacketTypes;
import zombie.network.packets.INetworkPacket;
import zombie.vehicles.BaseVehicle;
import zombie.vehicles.VehicleManager;

/*
 * ##########################################################################
 * ##  ChainTow.java  -  das Herzstueck des Java-Teils
 * ##########################################################################
 *
 *  WAS?    Ersetzt das Kuppeln/Abkuppeln des Spiels durch eine Version, die
 *          KETTEN kann:  [Zugfahrzeug] -> [2] -> [3] -> [4] ...
 *  WARUM?  Im Spiel hat jedes Fahrzeug nur EIN Verbindungs-Feld. Kuppelt man
 *          [2] an [3], loest das Spiel vorher die Verbindung [1]-[2]. Eine reine
 *          Lua-Mod kommt da nicht heran - deshalb dieser Java-Teil.
 *  WIE?    Die Patch*-Klassen haengen sich in Spiel-Methoden ein und rufen
 *          die oeffentlichen Methoden dieser Klasse auf.
 *
 *  INHALT (Abschnitte, jeweils mit "// ----...---- Name" markiert)
 *    Ankuppeln  |  Abkuppeln  |  Multiplayer  |  Wiederverbinden nach dem Laden
 *    Einstellungen  |  PKW oder LKW?  |  Lenkung des mittleren Fahrzeugs
 *    Mehr Kraft  |  Zugbremse  |  Haken: Ereignisse fuer Lua
 *
 *  WICHTIGE BEGRIFFE
 *    Bullet          Physik-Bibliothek des Spiels; eine "Verbindung" ist dort ein
 *                    Constraint mit einer Nummer (cid / constraintTowing).
 *    vorne / hinten  "front" zieht, "rear" wird gezogen.
 *    ModData         Lua-Tabelle am Fahrzeug, wird im Spielstand gespeichert.
 *    Zustaendigkeit  [MP] welcher Spieler die Physik eines Fahrzeugs rechnet.
 */

/**
 * Kettenfaehige Version der Fahrzeug-Kupplung von Project Zomboid (Build 42).
 *
 * Das Spiel kennt pro Fahrzeug nur EINE Verbindung: addPointConstraint() loest zuerst alle bestehenden
 * Verbindungen beider Fahrzeuge (breakConstraint). Hier wird stattdessen nur die Verbindung geloest,
 * die wirklich im Weg ist (hintere Kupplung von A, vordere Kupplung von B). Ein mittleres Fahrzeug
 * kann so gleichzeitig gezogen werden und selbst ziehen.
 *
 * Konvention fuer BaseVehicle.constraintTowing:
 *   - hat ein Fahrzeug ein hinteres Fahrzeug: Nummer der Verbindung zu diesem (wie im Original)
 *   - hat es nur ein vorderes Fahrzeug:        Nummer der Verbindung zum vorderen (wie im Original)
 * Die Nummer der Verbindung zum vorderen Fahrzeug merken wir uns zusaetzlich in FRONT_LINK.
 *
 * Multiplayer (ab 0.8.0): Der Server entscheidet, wer an wem haengt, und schickt Kuppeln/Abkuppeln als Pakete
 * an alle Clients. Der Server erzeugt keine Bullet-Verbindungen (wie im Original), die Clients schon.
 * Der Java-Teil muss dafuer auf dem Server UND auf allen Clients geladen sein.
 */
public final class ChainTow {
    public static final String VERSION = "0.16.2";

    // ==================================================================
    //  Merklisten (nur im Speicher, nicht im Spielstand)
    // ==================================================================
    //
    //    [A] ===cid 17===> [B] ===cid 23===> [C]
    //
    //    FRONT_LINK:  B -> 17,  C -> 23             (Verbindung VOR dem Fahrzeug)
    //    FRONT_ATT:   B -> {"trailerfront", "trailer"}  (Kupplungsnamen dieser Verbindung)
    //    A.constraintTowing = 17, B.constraintTowing = 23 (hinten), C.constraintTowing = 23 (nur vorne)
    //
    /** Fahrzeug-ID des HINTEREN Fahrzeugs -> Nummer der Bullet-Verbindung (vorne -> hinten). */
    private static final Map<Short, Integer> FRONT_LINK = new HashMap<>();

    /** Fahrzeug-ID des HINTEREN Fahrzeugs -> {eigene vordere Kupplung, Kupplung des Vordermanns}. */
    private static final Map<Short, String[]> FRONT_ATT = new HashMap<>();
    private static final ThreadLocal<Object[]> SAVED_ATT = new ThreadLocal<>();   // Zwischenspeicher fuer swapToFront/swapBack (pro Thread)

    // ---- Einstellungen (kommen aus dem Optionsmenue ueber LuaApi.multiTowConfigure) ----
    /** Mod an/aus. Aus = voellig das Original-Verhalten des Spiels. */
    private static volatile boolean enabled = true;
    /** Hoechstzahl Fahrzeuge im Zug inkl. Zugfahrzeug; 0 = unbegrenzt. Getrennt nach Typ des Zugfahrzeugs (PKW / LKW). */
    private static volatile int maxCar = 0;
    private static volatile int maxTruck = 0;
    /** Ab dem 3. Fahrzeug braucht man einen Haken: dann blockieren wir das normale Ankuppel-Menue des Spiels (die Mod prueft den Gegenstand selbst). */
    private static volatile boolean requireHook = false;
    /** Zugfahrzeug bekommt bei mehr als einem gezogenen Fahrzeug mehr Motorkraft (getrennt nach PKW / LKW). */
    private static volatile boolean boostCarEnabled = true;
    private static volatile boolean boostTruckEnabled = true;
    /** Fester Faktor (1.5, 2, 2.5, 3); 0 = automatisch nach Anzahl der gezogenen Fahrzeuge. */
    private static volatile float boostCarFixed = 0.0F;
    private static volatile float boostTruckFixed = 0.0F;
    /** Zugbremse: Anteil der eigenen Bremskraft, mit der gezogene Fahrzeuge mitbremsen (0 = wie im Original, 1 = wie selbst gefahren). */
    private static volatile float brakeCar = 0.0F;
    private static volatile float brakeTruck = 0.0F;
    /**
     * Mithelfen (ab 0.15.0): Anteil der EIGENEN Motorkraft, mit dem ein gezogenes Fahrzeug mit laufendem Motor mitfaehrt
     * (0 = aus, 1 = volle Kraft). Wirkt nur, wenn fuer den Zug-Typ (PKW/LKW) die Kraft-Erhoehung des Zugfahrzeugs aus ist.
     */
    private static volatile float assistPct = 0.0F;
    /** Hoechstgeschwindigkeit fuer Zuege ab 3 Fahrzeugen in km/h, 0 = aus. */
    private static volatile float speedCar = 0.0F;
    private static volatile float speedTruck = 0.0F;
    /** Laenge der Abschleppstange (Abstand der Kupplungspunkte). */
    public static final float BAR_LENGTH = 1.0F;
    /** Merkzeichen im ModData des hinteren Fahrzeugs: "bar" = starre Abschleppstange, sonst Kette/Seil. */
    private static final String LINK_FLAG = "MultiTowLink";
    /** Merkzeichen im ModData des hinteren Fahrzeugs: Gegenstand, der die Verbindung bildet (kommt zurueck bzw. faellt runter). */
    private static final String ITEM_FLAG = "MultiTowItem";
    private static final String HOOK_ITEM = "Base.HeavyChain_Hook";

    /** Automatik: Zusatzkraft pro weiterem gezogenem Fahrzeug (ab dem 2.). 0.6 = +60 %. */
    private static volatile float powerBoost = 0.6F;

    // ---- Haken-Ereignisse fuer den Lua-Teil ----
    // Gruende fuers Trennen - bestimmen, was danach passiert:
    //
    //   Grund            | Geraeusch | Gegenstand (Haken/Stange)
    //   -----------------+-----------+------------------------------------------
    //   OTHER   (0)      | DETACH    | RETURN -> zurueck ins Inventar
    //   IMPULSE (1)      | SNAP      | BREAK  -> faellt kaputt auf den Boden
    //   REMOVAL (2)      | -         | -  (Merker bleibt fuers Wiederverbinden)
    //   REPLACE (3)      | -         | RETURN
    //   RELINK  (4)      | -         | -
    //   REMOTE  (5)      | -         | -  (macht der Server)
    private static final String HOOK_FLAG = "MultiTowHook";
    private static final int REASON_OTHER = 0;
    private static final int REASON_IMPULSE = 1;
    private static final int REASON_REMOVAL = 2;
    /** Verbindung wird nur geloest, weil ein neues Ankuppeln sie ersetzt (kein Abkuppel-Geraeusch). */
    private static final int REASON_REPLACE = 3;
    /** Dieselbe Verbindung wird nur neu aufgebaut (z.B. im MP beim Einsteigen des Fahrers): kein Haken, kein Geraeusch. */
    private static final int REASON_RELINK = 4;
    /** Client fuehrt ein Abkuppeln aus, das der Server per Paket geschickt hat: Haken/Geraeusche macht der Server. */
    private static final int REASON_REMOTE = 5;
    private static final ConcurrentLinkedQueue<String> EVENTS = new ConcurrentLinkedQueue<>();   // Briefkasten Java -> Lua (Lua holt mit multiTowPopEvent ab)
    /** Zeitpunkt, zu dem das Spiel zuletzt eine Verbindung wegen Ueberlastung/Umkippen loesen wollte. */
    private static volatile long lastImpulseNs;

    // Merker "dieses Paar wird gerade WIEDER verbunden" (nach dem Laden / Umkehren):
    // dann kein Geraeusch, kein Spruch, keine Laengenpruefung. Gilt nur 3 Sekunden.
    private static volatile short lastReconnectA = -1;
    private static volatile short lastReconnectB = -1;
    private static volatile long lastReconnectMs;
    private static final ThreadLocal<Deque<Object[]>> CAN_ATTACH_STACK = ThreadLocal.withInitial(ArrayDeque::new);   // fuer canAttachEnter/-Exit (Stapel, falls verschachtelt)

    // Reflection: Zugriff auf PRIVATE Felder von BaseVehicle.
    //   >> WARUM: das Spiel bietet keine Methode, um NUR ein Feld zu leeren (setVehicleTowing
    //      wuerde gleich alles andere mit aendern). Mit Reflection setzen wir genau ein Feld.
    //   !! ACHTUNG: Nach einem Spiel-Update koennen die Feldnamen anders heissen -> dann
    //      reflectionOk = false und die Mod schaltet sich ab (statt das Spiel abstuerzen zu lassen).
    private static Field fTowing;
    private static Field fAttSelf;
    private static Field fAttOther;
    private static boolean attOk;
    private static Field fVarsEngineForce;
    private static Field fTowedBy;
    private static Field fTowingId;
    private static Field fTowedById;
    private static boolean reflectionOk;
    private static boolean warnedInactive;

    static {
        try {
            fTowing = field("vehicleTowing");
            fTowedBy = field("vehicleTowedBy");
            fTowingId = field("vehicleTowingId");
            fTowedById = field("vehicleTowedById");
            reflectionOk = true;
        } catch (Throwable t) {
            reflectionOk = false;
            System.out.println("[MultiTowCore] ERROR: game fields not accessible, chain coupling stays off: " + t);
        }
    }

    static {
        try {
            fAttSelf = field("towAttachmentSelf");
            fAttOther = field("towAttachmentOther");
            attOk = true;
        } catch (Throwable t) {
            attOk = false;
            System.out.println("[MultiTowCore] WARNING: hitch names not accessible, steering of the middle vehicle may be wrong: " + t);
        }
    }

    private ChainTow() {
    }

    /** Privates Feld von BaseVehicle holen und zugaenglich machen. */
    private static Field field(String name) throws Exception {
        Field f = BaseVehicle.class.getDeclaredField(name);
        f.setAccessible(true);
        return f;
    }

    // ------------------------------------------------------------------ Ist die Mod im laufenden Spiel ueberhaupt an?
    //   Der Java-Teil bleibt geladen, bis das Spiel beendet wird - auch wenn danach ein Spielstand OHNE Multi-Tow
    //   geladen wird (jeder Spielstand hat seine eigene Mod-Liste):
    //     Hauptmenue: 73 Mods inkl. Multi-Tow  -> ZombieBuddy laedt MultiTowCore.jar
    //     Spielstand: 72 Mods, OHNE Multi-Tow  -> Lua-Teil, Menues, Gegenstaende fehlen, Java-Teil liefe aber weiter
    //   Darum schaut isActive() nach, ob die Mod in der gerade geladenen Mod-Liste steht. Wenn nicht, ruht der
    //   Java-Teil und das Spiel schleppt ganz normal ab (nur 2 Fahrzeuge, keine Kette, kein Warnblinker).
    //   >> Nachgeschaut wird hoechstens einmal pro Sekunde (isActive wird sehr oft aufgerufen).
    private static final String MOD_ID = "MultiTowRoadTrain";
    private static volatile boolean modInList = true;   // bis zur ersten Pruefung: an (wie bisher)
    private static volatile long nextModCheckNs;
    private static volatile Boolean loggedModState;      // zuletzt ins Log geschriebener Zustand (nur Wechsel melden)

    /** Steht Multi-Tow in der Mod-Liste, mit der das Spiel gerade laeuft? (gemerkt, einmal pro Sekunde neu) */
    static boolean modInLoadedList() {
        long now = System.nanoTime();
        if (now - nextModCheckNs >= 0) {
            nextModCheckNs = now + 1_000_000_000L;
            try {
                List<String> mods = ZomboidFileSystem.instance == null ? null : ZomboidFileSystem.instance.getModIDs();
                if (mods != null && !mods.isEmpty()) {          // leere Liste = Spiel laedt gerade -> alten Stand behalten
                    boolean found = false;
                    for (Object o : mods.toArray()) {           // Kopie: die Liste kann sich beim Laden aendern
                        String id = o == null ? "" : o.toString();
                        if (id.startsWith("\\")) {
                            id = id.substring(1);               // Build 42 schreibt manche IDs mit "\" davor
                        }
                        if (MOD_ID.equalsIgnoreCase(id)) {
                            found = true;
                            break;
                        }
                    }
                    modInList = found;
                    if (loggedModState == null || loggedModState != found) {
                        if (loggedModState != null || !found) {
                            System.out.println(found
                                ? "[MultiTowCore] Multi-Vehicle Towing is in the loaded mod list again - Java part active."
                                : "[MultiTowCore] Multi-Vehicle Towing is NOT in the loaded mod list (for example not enabled for this save game)"
                                    + " - Java part paused, the game tows as usual.");
                        }
                        loggedModState = found;
                    }
                }
            } catch (Throwable t) {
                // Liste gerade nicht lesbar -> alten Stand behalten
            }
        }
        return modInList;
    }

    /** Aktiv im Einzelspieler, auf dem Server und auf den Clients (im MP muss der Java-Teil ueberall geladen sein).
     *  Nicht aktiv, wenn Multi-Tow in der gerade geladenen Mod-Liste fehlt (siehe modInLoadedList). */
    public static boolean isActive() {
        if (!reflectionOk || !enabled || !modInLoadedList()) {
            return false;
        }
        if ((GameServer.server || GameClient.client) && !warnedInactive) {
            warnedInactive = true;
            System.out.println("[MultiTowCore] Multiplayer mode: " + (GameServer.server ? "server" : "client")
                + ". The Java part must be loaded on the server and on every client.");
        }
        return true;
    }

    //   +---------------+---------------+
    //   | Einzelspieler |  Authority    |
    //   | MP-Server     |  Authority    |
    //   | MP-Client     |  NICHT        |   <- Client fuehrt nur aus, was der Server sagt
    //   +---------------+---------------+
    /** Ereignisse (Haken, Geraeusche) entstehen dort, wo entschieden wird: im Einzelspieler oder auf dem Server. */
    private static boolean isAuthority() {
        return !GameClient.client;
    }

    private static void log(String s) {
        System.out.println("[MultiTowCore] " + s);
    }

    private static String id(BaseVehicle v) {
        return v == null ? "nil" : String.valueOf(v.getId());
    }

    // ------------------------------------------------------------------ Ankuppeln

    // args (wie im Spiel):  [0] Spieler   [1] Fahrzeug B   [2] Kupplung A   [3] Kupplung B   [4] remote (nur Variante 2)
    // !! Jeder Fehler hier faellt auf das Original zurueck (return false) - lieber normales Spiel als Absturz.
    /**
     * Ersatz fuer BaseVehicle.addPointConstraint(player, vehicleB, attachmentA, attachmentB[, remote]).
     * @return true = Original ueberspringen
     */
    public static boolean addPointConstraint(BaseVehicle a, Object[] args) {
        if (!isActive()) {
            return false;
        }
        try {
            BaseVehicle b = (BaseVehicle) args[1];
            String attA = (String) args[2];
            String attB = (String) args[3];
            if (b == null || a == b) {   // Unsinn -> nichts tun, aber Original auch ueberspringen
                return true;
            }
            IsoPlayer player = args[0] instanceof IsoPlayer ? (IsoPlayer) args[0] : null;
            boolean remote = args.length >= 5 && Boolean.TRUE.equals(args[4]);
            return attach(a, b, attA, attB, player, remote);
        } catch (Throwable t) {
            log("ERROR in addPointConstraint, using vanilla code: " + t);
            t.printStackTrace(System.out);
            return false;
        }
    }

    /** Damit eine abgelehnte Kupplung, die das Spiel jedes Bild neu versucht, nicht jedes Bild ins Log schreibt. */
    private static long lastRejectKey, lastRejectMs;

    private static void logReject(BaseVehicle a, BaseVehicle b, String why) {
        // beide IDs zu einer Zahl zusammenstecken:  A (obere Bits) | B (untere 16 Bits)
        long key = ((long) a.vehicleId << 16) | (b.vehicleId & 0xFFFF);
        long now = System.currentTimeMillis();
        if (key != lastRejectKey || now - lastRejectMs > 10000L) {   // neues Paar oder 10 s Ruhe -> wieder loggen
            log("Coupling rejected (" + why + "): " + id(a) + " -> " + id(b));
        }
        lastRejectKey = key;
        lastRejectMs = now;
    }

    /** Eigene Werte einer Verbindung (stehen beim hinteren Fahrzeug) von einem Fahrzeug aufs andere uebertragen. */
    private static final String[] LINK_KEYS = { LINK_FLAG, ITEM_FLAG, HOOK_FLAG, "MultiTowCond" };

    private static void moveModData(BaseVehicle from, BaseVehicle to, String[] keys) {
        try {
            KahluaTable f = from.getModData();
            KahluaTable t = to.getModData();
            for (String k : keys) {
                t.rawset(k, f.rawget(k));
                f.rawset(k, null);
            }
            if (GameServer.server) {
                from.transmitModData();
                to.transmitModData();
            }
        } catch (Throwable t) {
            log("ERROR moving link data: " + t);
        }
    }

    /**
     * Kern des Ankuppelns:  A (vorne) zieht B (hinten).
     * <pre>
     *  -> 1. Sonderfall Fahrerwechsel: Verbindung umdrehen
     *  -> 2. Kreise verhindern
     *  -> 3. Hoechstzahl Fahrzeuge pruefen
     *  -> 4. Kupplungspunkte holen
     *  -> 5. NUR die stoerenden alten Verbindungen loesen
     *  -> 6. Bullet-Verbindung anlegen (Seil / Stange / Gelenk)
     *  -> 7. Felder im Spiel + eigene Merklisten setzen
     *  -> 8. [MP] Server: Zustaendigkeit + Paket an alle
     *  -> 9. Log + Geraeusch
     * </pre>
     */
    private static boolean attach(BaseVehicle a, BaseVehicle b, String attA, String attB, IsoPlayer player, boolean remote) {
        a.setPreviouslyMoved(true);

        // ---- 1. ----
        //   vorher:   [b] ---> [a]        (b zieht a, aber im Fahrersitz von a sitzt jemand)
        //   nachher:  [a] ---> [b]        (a zieht b)
        // Fahrerwechsel: Setzt sich jemand ans Steuer des GEZOGENEN Fahrzeugs (a), waehrend im Zugfahrzeug (b) keiner
        // sitzt, dreht das Spiel die Verbindung um: a soll jetzt b ziehen (CarController.updateTrailer).
        // Das machen wir mit, wenn danach kein Fahrzeug zwei Anhaengsel haette (zwei einzelne Fahrzeuge oder Zugende).
        if (a.getVehicleTowedBy() == b && b.getVehicleTowing() == a) {
            if (a.getVehicleTowing() != null || b.getVehicleTowedBy() != null) {
                logReject(a, b, "driver in the middle of a train, link not reversed");
                return true;
            }
            log("Reversing link for the new driver: " + id(b) + " -> " + id(a) + " becomes " + id(a) + " -> " + id(b));
            moveModData(a, b, LINK_KEYS);                                   // Kette/Stange/Zustand gehoeren zum neuen hinteren Fahrzeug
            moveModData(b, a, new String[] { Hazard.FLAG });                // Warnblinker gehoert zum neuen Zugfahrzeug
            breakLink(b, a, true, REASON_RELINK);                           // ohne Geraeusch, ohne Gegenstand
            // wie ein Wiederverbinden behandeln: kein Kuppel-Geraeusch, kein Spruch, keine Laengenpruefung
            lastReconnectA = a.vehicleId;
            lastReconnectB = b.vehicleId;
            lastReconnectMs = System.currentTimeMillis();
        }

        // ---- 2. ----
        // Kreise verhindern: b darf nicht schon (hinten) in der Kette von a haengen und umgekehrt
        int guard = 0;
        for (BaseVehicle v = b; v != null && guard < 64; v = v.getVehicleTowing(), guard++) {
            if (v == a) {
                logReject(a, b, "loop");
                return true;
            }
        }
        guard = 0;
        for (BaseVehicle v = a.getVehicleTowedBy(); v != null && guard < 64; v = v.getVehicleTowedBy(), guard++) {
            if (v == b) {
                logReject(a, b, "loop");
                return true;
            }
        }

        // ---- 3. ----
        // Hoechstzahl Fahrzeuge im Zug (beim automatischen Wiederverbinden nach dem Laden nicht pruefen)
        boolean isReconnect = a.vehicleId == lastReconnectA && b.vehicleId == lastReconnectB
            && System.currentTimeMillis() - lastReconnectMs < 3000L;
        int max = maxFor(head(a));
        if (!isReconnect && max > 0 && !GameClient.client) {   // [MP] der Client prueft nicht, das hat der Server schon
            int len = trainLength(a, b);
            if (len > max) {
                log("Coupling rejected (train too long): " + len + " > " + max);
                return true;
            }
        }

        // ---- 4. ----   (lokale Koordinaten = relativ zur Fahrzeugmitte)
        // Kupplungspunkte zuerst ermitteln, damit wir nichts loesen, was wir nicht neu verbinden koennen
        Vector3f v1 = a.getTowingLocalPos(attA, new Vector3f());
        Vector3f v2 = b.getTowedByLocalPos(attB, new Vector3f());
        if (v1 == null || v2 == null) {
            log("Coupling rejected: hitch point missing (" + attA + " / " + attB + ")");
            return true;
        }

        // ---- 5. ----
        //   [x] -> [a] -> [oldRear]     [oldFront] -> [b] -> [y]
        //              ^^ weg                    ^^ weg
        //   [x] -> [a] ----------------------------> [b] -> [y]      (x-a und b-y bleiben!)
        // nur die Verbindungen loesen, die wirklich kollidieren
        BaseVehicle oldRear = a.getVehicleTowing();
        boolean relink = oldRear == b;
        if (oldRear != null) {
            breakLink(a, oldRear, true, relink ? REASON_RELINK : REASON_REPLACE);
        }
        BaseVehicle oldFront = b.getVehicleTowedBy();
        if (oldFront != null) {
            breakLink(oldFront, b, true, REASON_REPLACE);
        }

        // ---- 6. ----  Art der Bullet-Verbindung
        //   +-------------------------+----------------------+-----------------------------------+
        //   | Fall                    | Bullet-Verbindung    | Verhalten                         |
        //   +-------------------------+----------------------+-----------------------------------+
        //   | MP-Server               | keine (cid = -1)     | Physik rechnen nur die Clients    |
        //   | Abschleppstange         | 6DoF, versetzt       | fester Abstand, knickt seitlich   |
        //   | zwei normale Autos      | Seil (1.5 lang)      | darf locker durchhaengen          |
        //   | ein echter Anhaenger    | 6DoF (Gelenk)        | wie im Original                   |
        //   +-------------------------+----------------------+-----------------------------------+
        int cid;
        String nameA = a.getScriptName();
        String nameB = b.getScriptName();
        boolean bar = isBarLink(b);
        if (!isReconnect && !GameServer.server) {
            // weich ankuppeln: die ersten 2 Sekunden gibt die Verbindung nach (wie beim Anhaenger im Original)
            a.beginAttachingTrailer();
        }
        if (GameServer.server) {
            // Der Server rechnet keine Fahrzeug-Verbindungen (wie im Original), das machen die Clients
            cid = -1;
        } else if (bar) {
            // Starre Stange: Gelenk am Haken des Vordermanns, die Stange ist fest am hinteren Fahrzeug
            // (Drehpunkt BAR_LENGTH vor dessen vorderer Kupplung). Winkelgrenzen wie beim Anhaenger im Original.
            cid = Bullet.add6DofConstraint(
                a.vehicleId, b.vehicleId,
                v1.x, v1.y, v1.z, v2.x, v2.y, v2.z + BAR_LENGTH,
                0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F,
                (float) (-Math.PI / 4), (float) (-Math.PI / 2), -0.05235988F,
                (float) (Math.PI / 4), (float) (Math.PI / 2), 0.05235988F);
        } else if (!nameA.contains("Trailer") && !nameB.contains("Trailer")) {
            cid = Bullet.addRopeConstraint(a.vehicleId, b.vehicleId, v1.x, v1.y, v1.z, v2.x, v2.y, v2.z, 1.5F);
        } else {
            cid = Bullet.add6DofConstraint(
                a.vehicleId, b.vehicleId,
                v1.x, v1.y, v1.z, v2.x, v2.y, v2.z,
                0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F,
                (float) (-Math.PI / 4), (float) (-Math.PI / 2), -0.05235988F,
                (float) (Math.PI / 4), (float) (Math.PI / 2), 0.05235988F);
        }
        // Weiches Ankuppeln: ERP = wie schnell Bullet Abweichungen korrigiert (klein = weich).
        // Fuer alle 6 Achsen (3 x verschieben, 3 x drehen).
        if (cid != -1 && a.isAttachingTrailer()) {
            for (int axis = 0; axis < 6; axis++) {
                Bullet.setConstraintERP(cid, 0.02F, axis);
            }
        }

        // ---- 7. ----
        // Kupplungsnamen des hinteren Glieds von b sichern: setVehicleTowedBy ueberschreibt sie
        String keepSelf = b.getTowAttachmentSelf();
        String keepOther = b.getTowAttachmentOther();

        // Hat b nach dem Laden noch eine hintere Verbindung "offen" (gespeichert, aber noch nicht aufgebaut)?
        //   >> WARUM wichtig: sonst wuerden wir b's hintere Kupplungsnamen ueberschreiben und das
        //      Wiederverbinden mit dem Fahrzeug dahinter klappt nicht mehr.
        boolean hasPendingRear = false;
        try {
            hasPendingRear = b.getVehicleTowing() == null
                && (fTowingId.getInt(b) != -1
                    || (GameClient.client && VehicleManager.instance.getTowedVehicleID(b.vehicleId) != -1));
        } catch (IllegalAccessException e) {
            // ignorieren
        }
        a.constraintTowing = cid;
        FRONT_LINK.put(b.vehicleId, cid);
        FRONT_ATT.put(b.vehicleId, new String[] { attB, attA });
        if (b.getVehicleTowing() == null) {
            b.constraintTowing = cid;
        }
        // Spiel-Felder setzen. !! ACHTUNG Reihenfolge: setVehicleTowedBy ueberschreibt b's Kupplungsnamen,
        // deshalb danach b's hintere Verbindung (falls vorhanden) wieder eintragen.
        a.setVehicleTowing(b, attA, attB);
        b.setVehicleTowedBy(a, attA, attB);
        BaseVehicle bRear = b.getVehicleTowing();
        if (bRear != null) {
            b.setVehicleTowing(bRear, keepSelf, keepOther);
        } else if (hasPendingRear && attOk) {
            // b muss sich nach dem Laden noch mit seinem hinteren Fahrzeug verbinden: dafuer braucht es seine hinteren Kupplungsnamen
            try {
                fAttSelf.set(b, keepSelf);
                fAttOther.set(b, keepOther);
            } catch (IllegalAccessException e) {
                throw new IllegalStateException(e);
            }
        }
        a.constraintChanged();
        b.constraintChanged();

        if (GameServer.server) {
            // ---- 8. ----  [MP]
            // wie im Original: frisch gekuppelte, fahrerlose Fahrzeuge rechnet erst einmal der kuppelnde Spieler
            if (player != null && a.netPlayerAuthorization == BaseVehicle.Authorization.Server
                && b.netPlayerAuthorization == BaseVehicle.Authorization.Server) {
                a.setNetPlayerAuthorization(BaseVehicle.Authorization.LocalCollide, player.onlineId);
                a.authSimulationTime = System.currentTimeMillis();
                b.setNetPlayerAuthorization(BaseVehicle.Authorization.LocalCollide, player.onlineId);
                b.authSimulationTime = System.currentTimeMillis();
            }
            syncChainAuthority(a);
            if (!remote) {
                VehicleManager.instance.attachTowing(a, b, attA, attB);   // Paket "angekuppelt" an alle Clients
            }
        }

        // ---- 9. ----
        log("COUPLED " + id(a) + " -> " + id(b) + " | link " + cid + " | "
            + (bar ? "tow bar" : (nameA.contains("Trailer") || nameB.contains("Trailer") ? "joint" : "rope"))
            + " | a: towing " + id(a.getVehicleTowing()) + " towedBy " + id(a.getVehicleTowedBy())
            + " | b: towing " + id(b.getVehicleTowing()) + " towedBy " + id(b.getVehicleTowedBy()));
        if (!isReconnect && !relink && isAuthority()) {
            soundEvent("ATTACH", a, b);
        }
        return true;
    }

    // ------------------------------------------------------------------ Abkuppeln

    /**
     * Ersatz fuer BaseVehicle.breakConstraint(forgetID, remote): loest GENAU EINE Verbindung.
     * Zuerst die zum hinteren Fahrzeug (wie getTowingPartner im Original), sonst die zum vorderen.
     * @return true = Original ueberspringen
     */
    public static boolean breakConstraint(BaseVehicle x, boolean forgetID, boolean remote) {
        if (!isActive()) {
            return false;
        }
        try {
            // Grund herausfinden:
            //   gab es in den letzten 20 ms einen Ueberlastungs-/Kipp-Merker?  -> gerissen (IMPULSE)
            //   sonst                                                           -> normal abgekuppelt (OTHER)
            //   [MP] Client: immer REMOTE (Ereignisse macht der Server)
            int reason = System.nanoTime() - lastImpulseNs < 20_000_000L ? REASON_IMPULSE : REASON_OTHER;
            if (GameClient.client) {
                reason = REASON_REMOTE;
            }
            BaseVehicle rear = x.getVehicleTowing();
            if (rear != null) {
                breakLink(x, rear, forgetID, reason, remote);
                return true;
            }
            BaseVehicle front = x.getVehicleTowedBy();
            if (front != null) {
                breakLink(front, x, forgetID, reason, remote);
                return true;
            }
            // keine Verbindung bekannt: Original macht bei constraintTowing == -1 ebenfalls nichts   // <- sonst Original laufen lassen
            return x.constraintTowing == -1;
        } catch (Throwable t) {
            log("ERROR in breakConstraint, using vanilla code: " + t);
            t.printStackTrace(System.out);
            return false;
        }
    }

    /** Loest alle Verbindungen eines Fahrzeugs (fuer Entladen / Entfernen aus der Welt). */
    public static void breakAll(BaseVehicle x, boolean forgetID) {
        if (!isActive()) {
            return;
        }
        try {
            BaseVehicle rear = x.getVehicleTowing();
            if (rear != null) {
                breakLink(x, rear, forgetID, REASON_REMOVAL);
            }
            BaseVehicle front = x.getVehicleTowedBy();
            if (front != null) {
                breakLink(front, x, forgetID, REASON_REMOVAL);
            }
        } catch (Throwable t) {
            log("ERROR in breakAll: " + t);
            t.printStackTrace(System.out);
        }
    }

    /** Kurzform ohne "remote". */
    private static void breakLink(BaseVehicle front, BaseVehicle rear, boolean forgetID, int reason) {
        breakLink(front, rear, forgetID, reason, false);
    }

    /**
     * Loest die Verbindung front -> rear, alle anderen Verbindungen der beiden bleiben bestehen.
     * @param remote true = kommt bereits vom Netz (Server schickt dann kein Paket mehr)
     */
    private static void breakLink(BaseVehicle front, BaseVehicle rear, boolean forgetID, int reason, boolean remote) {
        if (isAuthority()) {
            // -> 1. Ereignisse fuer Lua (Gegenstand + Geraeusch), siehe Tabelle "Gruende fuers Trennen" oben
            if (reason != REASON_REMOVAL && reason != REASON_RELINK && reason != REASON_REMOTE) {
                hookEvent(front, rear, reason == REASON_IMPULSE);
            }
            if (reason == REASON_IMPULSE) {
                soundEvent("SNAP", front, rear);
            } else if (reason == REASON_OTHER) {
                soundEvent("DETACH", front, rear);
            }
        }
        // -> 2. Bullet-Verbindung entfernen (Nummer aus unserer Merkliste, sonst aus dem Spiel-Feld)
        FRONT_ATT.remove(rear.vehicleId);
        Integer stored = FRONT_LINK.remove(rear.vehicleId);
        int cid = stored != null ? stored : front.constraintTowing;
        if (cid != -1 && !GameServer.server) {
            Bullet.removeConstraint(cid);
        }

        // -> 3. NUR die beiden Felder dieser einen Verbindung leeren (per Reflection, siehe oben).
        //       forgetID: auch die gespeicherten IDs loeschen -> nach dem Laden NICHT wieder verbinden
        try {
            fTowing.set(front, null);
            fTowedBy.set(rear, null);
            if (forgetID) {
                fTowingId.setInt(front, -1);
                fTowedById.setInt(rear, -1);
            }
        } catch (IllegalAccessException e) {
            throw new IllegalStateException(e);
        }

        // -> 4. constraintTowing neu setzen (Konvention siehe Klassen-Beschreibung):
        //       front: hat es selbst noch einen Vordermann? dann dessen Nummer, sonst -1
        Integer ownFront = FRONT_LINK.get(front.vehicleId);
        front.constraintTowing = ownFront != null ? ownFront : -1;
        if (rear.getVehicleTowing() == null) {
            rear.constraintTowing = -1;
        }
        front.constraintChanged();
        rear.constraintChanged();

        if (GameServer.server) {
            // -> 5. [MP] Server: allen Clients melden + Zustaendigkeit beider Teil-Zuege angleichen
            if (!remote && reason != REASON_REMOVAL) {
                sendDetach(front, rear);
            }
            syncChainAuthority(front);
            syncChainAuthority(rear);
        }

        log("DETACHED " + id(front) + " -> " + id(rear) + " | link " + cid
            + " | front: towing " + id(front.getVehicleTowing()) + " towedBy " + id(front.getVehicleTowedBy())
            + " | rear: towing " + id(rear.getVehicleTowing()) + " towedBy " + id(rear.getVehicleTowedBy()));
    }

    /**
     * Verbindung vor diesem (hinteren) Fahrzeug reissen lassen, z.B. weil sie verschlissen ist.
     * Wirkt wie ein Reissen waehrend der Fahrt: Ereignis BREAK (Gegenstand faellt kaputt bzw. als Einzelteile runter)
     * und Geraeusch SNAP. Nur im Einzelspieler und auf dem Server (MP-Clients melden es dem Server).
     */
    public static boolean snapLink(BaseVehicle rear) {
        if (!isActive() || rear == null || !isAuthority()) {
            return false;
        }
        BaseVehicle front = rear.getVehicleTowedBy();
        if (front == null) {
            return false;
        }
        try {
            log("Link worn out: " + id(front) + " -> " + id(rear));
            breakLink(front, rear, true, REASON_IMPULSE, false);
            return true;
        } catch (Throwable t) {
            log("ERROR in snapLink: " + t);
            return false;
        }
    }

    // (gleiche Rechnung wie MultiTow.trainLength in MultiTow_Common.lua - bitte beide gleich halten)
    /** Anzahl Fahrzeuge im Zug, wenn a (samt allen vor ihm) und b (samt allen hinter ihm) verbunden wuerden. */
    private static int trainLength(BaseVehicle a, BaseVehicle b) {
        int n = 0;
        for (BaseVehicle v = a; v != null && n < 256; v = v.getVehicleTowedBy()) {
            n++;
        }
        for (BaseVehicle v = b; v != null && n < 512; v = v.getVehicleTowing()) {
            n++;
        }
        return n;
    }

    // ------------------------------------------------------------------ Multiplayer

    /**
     * Server: Abkuppeln an alle Clients melden. Das Original (VehicleManager.detachTowing) wuerde auch den Eintrag
     * des hinteren Fahrzeugs aus der Abschlepp-Liste loeschen und damit dessen eigene hintere Verbindung vergessen.
     */
    private static void sendDetach(BaseVehicle front, BaseVehicle rear) {
        try {
            VehicleManager vm = VehicleManager.instance;
            // towedVehicleMap = Liste des Spiels "wer zieht wen" (fuers Wiederverbinden). Nur DIESEN Eintrag loeschen.
            if (vm.towedVehicleMap.containsKey(front.vehicleId) && vm.towedVehicleMap.get(front.vehicleId) == rear.vehicleId) {
                vm.towedVehicleMap.remove(front.vehicleId);
            }
            INetworkPacket.sendToAll(PacketTypes.PacketType.VehicleTowingDetach, front, rear);
        } catch (Throwable t) {
            log("ERROR in sendDetach: " + t);
        }
    }

    private static Field fPacketA;
    private static Field fPacketB;

    /**
     * Client: Ersatz fuer VehicleTowingDetachPacket.processClient. Das Original loest bei BEIDEN Fahrzeugen alle
     * Verbindungen (bei einer Kette reisst dann die halbe Kette ab). Wir loesen nur die Verbindung zwischen den beiden.
     * @return true = Original ueberspringen
     */
    public static boolean clientDetachPacket(Object packet) {
        if (!isActive() || packet == null) {
            return false;
        }
        try {
            // Felder des Pakets einmalig per Reflection holen (die Klasse kennen wir erst zur Laufzeit)
            if (fPacketA == null) {
                fPacketA = packet.getClass().getDeclaredField("vehicleA");
                fPacketA.setAccessible(true);
                fPacketB = packet.getClass().getDeclaredField("vehicleB");
                fPacketB.setAccessible(true);
            }
            zombie.network.fields.vehicle.VehicleID ida = (zombie.network.fields.vehicle.VehicleID) fPacketA.get(packet);
            zombie.network.fields.vehicle.VehicleID idb = (zombie.network.fields.vehicle.VehicleID) fPacketB.get(packet);
            short aId = ida.getID();
            short bId = idb.getID();
            VehicleManager vm = VehicleManager.instance;
            if (vm.towedVehicleMap.containsKey(aId) && vm.towedVehicleMap.get(aId) == bId) {
                vm.towedVehicleMap.remove(aId);
            }
            BaseVehicle a = ida.getVehicle();
            BaseVehicle b = idb.getVehicle();
            // Faelle:
            //   beide Fahrzeuge geladen           -> Richtung pruefen und loesen
            //   nur eines geladen (anderes fern)  -> ueber die Verbindung des geladenen loesen
            if (a != null && b != null) {
                if (a.getVehicleTowing() == b) {
                    breakLink(a, b, true, REASON_REMOTE, true);
                } else if (b.getVehicleTowing() == a) {
                    breakLink(b, a, true, REASON_REMOTE, true);
                }
            } else if (a != null && a.getVehicleTowing() != null && a.getVehicleTowing().vehicleId == bId) {
                breakLink(a, a.getVehicleTowing(), true, REASON_REMOTE, true);
            } else if (b != null && b.getVehicleTowedBy() != null && b.getVehicleTowedBy().vehicleId == aId) {
                breakLink(b.getVehicleTowedBy(), b, true, REASON_REMOTE, true);
            }
            return true;
        } catch (Throwable t) {
            log("ERROR in clientDetachPacket, using vanilla code: " + t);
            return false;
        }
    }

    /** Alle Fahrzeuge der Kette, vom Zugfahrzeug bis zum letzten. */
    private static List<BaseVehicle> chainOf(BaseVehicle any) {
        List<BaseVehicle> list = new ArrayList<>();
        BaseVehicle v = head(any);
        while (v != null && list.size() < 64 && !list.contains(v)) {   // Schutz gegen Endlosschleife / Kreis
            list.add(v);
            v = v.getVehicleTowing();
        }
        return list;
    }

    private static final ThreadLocal<Boolean> IN_SYNC = ThreadLocal.withInitial(() -> Boolean.FALSE);   // Sperre: syncChainAuthority ruft sich sonst ueber constraintChanged selbst wieder auf

    /**
     * Server: Im MP rechnet ein Client die Physik der Fahrzeuge, fuer die er "zustaendig" ist. Das Original gibt die
     * Zustaendigkeit nur an das direkt gekoppelte Fahrzeug weiter. Bei einer Kette muss EIN Client alle Glieder rechnen,
     * sonst ziehen Server und Client gegeneinander. Regel: hat ein Fahrzeug der Kette einen Fahrer, ist dessen Client
     * zustaendig; sonst ein Client, der gerade mit der Kette kollidiert; sonst der Server.
     */
    public static void syncChainAuthority(BaseVehicle any) {
        if (!GameServer.server || any == null || !isActive() || IN_SYNC.get()) {
            return;
        }
        IN_SYNC.set(Boolean.TRUE);
        try {
            List<BaseVehicle> chain = chainOf(any);
            if (chain.size() < 3) {
                return; // zwei Fahrzeuge regelt das Original richtig
            }
            // Wer ist zustaendig?   Prioritaet:
            //   1. Fahrer irgendwo in der Kette      -> Local       (dessen Client)
            //   2. Spieler kollidiert mit der Kette  -> LocalCollide
            //   3. sonst                             -> Server
            BaseVehicle.Authorization auth = BaseVehicle.Authorization.Server;
            int playerId = -1;
            for (BaseVehicle v : chain) {
                IsoGameCharacter d = v.getDriver();
                if (d instanceof IsoPlayer) {
                    auth = BaseVehicle.Authorization.Local;
                    playerId = ((IsoPlayer) d).getOnlineID();
                    break;
                }
            }
            if (playerId == -1) {
                for (BaseVehicle v : chain) {
                    if (v.isNetPlayerAuthorization(BaseVehicle.Authorization.LocalCollide) && v.getNetPlayerId() != -1) {
                        auth = BaseVehicle.Authorization.LocalCollide;
                        playerId = v.getNetPlayerId();
                        break;
                    }
                }
            }
            long now = System.currentTimeMillis();
            for (BaseVehicle v : chain) {
                if (!v.isNetPlayerAuthorization(auth) || !v.isNetPlayerId((short) playerId)) {   // nur aendern, wenn noetig (spart Netzwerk)
                    v.setNetPlayerAuthorization(auth, playerId);
                    if (playerId != -1) {
                        v.authSimulationTime = now;
                    }
                }
            }
        } catch (Throwable t) {
            log("ERROR in syncChainAuthority: " + t);
        } finally {
            IN_SYNC.set(Boolean.FALSE);
        }
    }

    /** Client: Kollision mit einer Kette - das Original uebernimmt nur ein Nachbarfahrzeug, wir die ganze Kette. */
    public static void clientCollideChain(BaseVehicle v, Object driver) {
        if (!GameClient.client || v == null || !(driver instanceof IsoPlayer) || !isActive()) {
            return;
        }
        try {
            List<BaseVehicle> chain = chainOf(v);
            if (chain.size() < 3) {
                return;
            }
            short pid = ((IsoPlayer) driver).getOnlineID();
            long now = System.currentTimeMillis();
            for (BaseVehicle c : chain) {
                if (c.getDriver() == null && !c.isNetPlayerAuthorization(BaseVehicle.Authorization.Local)
                    && !c.isNetPlayerAuthorization(BaseVehicle.Authorization.LocalCollide)) {
                    c.setNetPlayerAuthorization(BaseVehicle.Authorization.LocalCollide, pid);
                    c.authSimulationTime = now;
                    c.interpolation.clearAll();   // alte Netzwerk-Positionen verwerfen, sonst springt es zurueck
                }
            }
        } catch (Throwable t) {
            log("ERROR in clientCollideChain: " + t);
        }
    }

    private static Method mUpdateVehiclePos;
    private static boolean updatePosFailed;

    /**
     * Client: Bei anderen Spielern bewegt das Original nur das Zugfahrzeug und das erste gezogene Fahrzeug mit
     * (alle weiteren Glieder wuerden einfrieren). Wir fuehren die Positions-Aktualisierung fuer den Rest der Kette nach.
     */
    public static void clientUpdateChains() {
        if (!GameClient.client || updatePosFailed || !isActive()) {
            return;
        }
        try {
            if (mUpdateVehiclePos == null) {
                mUpdateVehiclePos = VehicleManager.class.getDeclaredMethod("updateVehiclePos",
                    BaseVehicle.class, zombie.vehicles.VehicleInterpolation.class);
                mUpdateVehiclePos.setAccessible(true);
            }
            //   [Kopf] -> [1] -> [2] -> [3]
            //   Spiel bewegt:  Kopf, 1
            //   wir bewegen:   2 (nach 1), 3 (nach 2) ...   - jedes Glied folgt seinem Vordermann
            ArrayList<BaseVehicle> vehicles = VehicleManager.instance.getVehicles();
            for (int i = 0; i < vehicles.size(); i++) {
                BaseVehicle headV = vehicles.get(i);
                if (headV.getVehicleTowedBy() != null || headV.getVehicleTowing() == null) {   // nur Zugfahrzeuge mit Anhang
                    continue;
                }
                BaseVehicle prev = headV.getVehicleTowing();
                BaseVehicle cur = prev.getVehicleTowing();
                int guard = 0;
                while (cur != null && guard++ < 64) {
                    if (!cur.isNetPlayerAuthorization(BaseVehicle.Authorization.Local)
                        && !cur.isNetPlayerAuthorization(BaseVehicle.Authorization.LocalCollide)) {
                        mUpdateVehiclePos.invoke(VehicleManager.instance, cur, prev.interpolation);
                    }
                    prev = cur;
                    cur = cur.getVehicleTowing();
                }
            }
        } catch (Throwable t) {
            updatePosFailed = true;   // !! einmal Fehler -> abschalten statt jedes Bild Fehler
            log("ERROR in clientUpdateChains (disabled): " + t);
        }
    }

    /**
     * Server: Ein Client meldet "Verbindung ist bei mir gerissen" (vehicle.detachTrailerSpontaneous). Das gleich
     * folgende Abkuppeln zaehlt dann als Reissen (Kette + grosser Haken fallen auf den Boden).
     */
    public static void markSpontaneousServer() {
        if (GameServer.server && isActive()) {
            lastImpulseNs = System.nanoTime();
        }
    }

    // ------------------------------------------------------------------ Wiederverbinden nach dem Laden

    /**
     * BaseVehicle.canAttachTrailer verlangt, dass BEIDE Fahrzeuge noch keine Verbindung haben (constraintTowing == -1).
     * Ein mittleres Fahrzeug hat aber schon eine, sobald sein Nachbar sich verbunden hat. Deshalb kam nach dem Laden
     * eine der beiden Verbindungen nie zustande. Waehrend der Pruefung setzen wir die Nummern kurz auf -1, wenn bei a die
     * hintere und bei b die vordere Kupplung wirklich frei ist, und stellen sie danach wieder her.
     */
    public static void canAttachEnter(BaseVehicle a, Object[] args) {
        Deque<Object[]> stack = CAN_ATTACH_STACK.get();
        Object[] entry = null;
        try {
            if (isActive() && args != null && args.length >= 1 && args[0] instanceof BaseVehicle) {
                BaseVehicle b = (BaseVehicle) args[0];
                boolean reconnect = args.length >= 4 && Boolean.TRUE.equals(args[3]);   // 4. Argument = Spiel verbindet nach dem Laden
                if (b != null && b != a && a.getVehicleTowing() == null && b.getVehicleTowedBy() == null) {
                    boolean ok = true;
                    if (reconnect) {
                        lastReconnectA = a.vehicleId;
                        lastReconnectB = b.vehicleId;
                        lastReconnectMs = System.currentTimeMillis();
                    } else {
                        int len = trainLength(a, b);
                        int max = maxFor(head(a));
                        if (max > 0 && len > max) {
                            ok = false;
                        } else if (len >= 3) {
                            // Zuege mit 3+ Fahrzeugen werden nur ueber das Mod-Menue gekuppelt (dort gelten Haken-Regel und Limit)
                            ok = false;
                        }
                    }
                    if (ok) {
                        entry = new Object[] { a, b, a.constraintTowing, b.constraintTowing };   // alte Nummern merken
                        a.constraintTowing = -1;
                        b.constraintTowing = -1;
                    }
                }
            }
        } catch (Throwable t) {
            log("ERROR in canAttachEnter: " + t);
        }
        stack.push(entry == null ? new Object[0] : entry);   // IMMER etwas ablegen, damit Exit das Gegenstueck findet
    }

    /** Gegenstueck zu canAttachEnter: gemerkte Nummern zurueckschreiben. */
    public static void canAttachExit(BaseVehicle a) {
        Deque<Object[]> stack = CAN_ATTACH_STACK.get();
        try {
            Object[] entry = stack.poll();
            if (entry != null && entry.length == 4) {
                ((BaseVehicle) entry[0]).constraintTowing = (Integer) entry[2];
                ((BaseVehicle) entry[1]).constraintTowing = (Integer) entry[3];
            }
        } catch (Throwable t) {
            log("ERROR in canAttachExit: " + t);
        }
    }

    // ------------------------------------------------------------------ Einstellungen

    /**
     * Regeln vom Lua-Teil (LuaApi.multiTowConfigure).
     * [SP] aus dem Optionsmenue, [MP] aus den Sandbox-Optionen des Servers.
     * Negative Werte werden auf 0 gesetzt (Math.max) - kaputte Eingaben koennen so nichts anrichten.
     */
    public static void configure(boolean enable, boolean hookRequired,
                                 int maxCars, boolean boostCars, float fixedCars,
                                 int maxTrucks, boolean boostTrucks, float fixedTrucks) {
        enabled = enable;
        requireHook = hookRequired;
        maxCar = Math.max(0, maxCars);
        maxTruck = Math.max(0, maxTrucks);
        boostCarEnabled = boostCars;
        boostCarFixed = Math.max(0.0F, fixedCars);
        boostTruckEnabled = boostTrucks;
        boostTruckFixed = Math.max(0.0F, fixedTrucks);
        log("Settings: enabled=" + enabled + ", hook required=" + requireHook
            + " | cars: max=" + (maxCar == 0 ? "unlimited" : String.valueOf(maxCar)) + ", extra power=" + boostText(boostCarEnabled, boostCarFixed)
            + " | trucks: max=" + (maxTruck == 0 ? "unlimited" : String.valueOf(maxTruck)) + ", extra power=" + boostText(boostTruckEnabled, boostTruckFixed));
    }

    /** Text fuers Log: "off" / "automatic" / "2.0x". */
    private static String boostText(boolean on, float fixed) {
        return on ? (fixed > 0 ? fixed + "x" : "automatic") : "off";
    }

    // ------------------------------------------------------------------ PKW oder LKW?

    /**
     * Unterscheidung nach dem Namen des Fahrzeug-Skripts (z.B. "PickUpTruck", "StepVan", "Van", "VanAmbulance"):
     * enthaelt der Name truck, van, pickup, bus, ambulance, lorry, semi oder tractor, ist es ein LKW,
     * alles andere zaehlt als PKW. Gilt fuer Fahrzeuge anderer Mods genauso.
     */
    public static boolean isTruckName(String scriptName) {
        if (scriptName == null) {
            return false;
        }
        String n = scriptName.toLowerCase(java.util.Locale.ROOT);   // Locale.ROOT: sonst macht z.B. Tuerkisch aus "I" ein anderes i
        return n.contains("truck") || n.contains("van") || n.contains("pickup") || n.contains("bus")
            || n.contains("ambulance") || n.contains("lorry") || n.contains("semi") || n.contains("tractor");
    }

    private static boolean isTruck(BaseVehicle v) {
        try {
            return v != null && isTruckName(v.getScriptName());
        } catch (Throwable t) {
            return false;
        }
    }

    /** Zugfahrzeug = das erste Fahrzeug der Kette (wird selbst nicht gezogen). */
    private static BaseVehicle head(BaseVehicle v) {
        int guard = 0;
        while (v != null && v.getVehicleTowedBy() != null && guard++ < 128) {
            v = v.getVehicleTowedBy();
        }
        return v;
    }

    /** Hoechstzahl je nach Typ des Zugfahrzeugs (0 = unbegrenzt). */
    private static int maxFor(BaseVehicle headVehicle) {
        return isTruck(headVehicle) ? maxTruck : maxCar;
    }

    // ------------------------------------------------------------------ Lenkung des mittleren Fahrzeugs

    /**
     * Das Spiel kennt pro Fahrzeug nur EIN Paar Kupplungsnamen. Die Lenk-Automatik eines gezogenen Fahrzeugs
     * (CarController.steerInDirectionOfTowing) braucht aber die VORDERE Kupplung. Beim mittleren Fahrzeug steht
     * dort die hintere, deshalb lenkte es wild. Waehrend der Berechnung setzen wir die vordere ein
     * und danach wieder die urspruengliche zurueck.
     */
    public static void swapToFront(BaseVehicle v) {
        try {
            SAVED_ATT.remove();
            if (!attOk || v == null || !isActive() || v.getVehicleTowedBy() == null) {
                return;
            }
            String[] front = FRONT_ATT.get(v.vehicleId);
            if (front == null) {
                return;
            }
            SAVED_ATT.set(new Object[] { v, v.getTowAttachmentSelf(), v.getTowAttachmentOther() });
            fAttSelf.set(v, front[0]);
            fAttOther.set(v, front[1]);
        } catch (Throwable t) {
            log("ERROR in swapToFront: " + t);
        }
    }

    /**
     * Gegenstueck zu swapToFront: die gemerkten Kupplungsnamen zurueckschreiben.
     * !! ACHTUNG: nur wenn es dasselbe Fahrzeug ist (saved[0] == v) - Sicherheit gegen Verwechslung.
     */
    public static void swapBack(BaseVehicle v) {
        try {
            Object[] saved = SAVED_ATT.get();
            SAVED_ATT.remove();
            if (saved != null && saved[0] == v) {
                fAttSelf.set(v, saved[1]);
                fAttOther.set(v, saved[2]);
            }
        } catch (Throwable t) {
            log("ERROR in swapBack: " + t);
        }
    }

    // ------------------------------------------------------------------ Mehr Kraft fuer das Zugfahrzeug

    // Rechenbeispiel Automatik (powerBoost 0.6):
    //   gezogene Fahrzeuge:   1      2      3      4
    //   Faktor Motorkraft:   1.0    1.6    2.2    2.8
    public static float getPowerBoost() {
        return powerBoost;
    }

    public static void setPowerBoost(float f) {
        powerBoost = Math.max(0.0F, f);
        log("Extra power per additional vehicle: " + powerBoost);
    }

    /**
     * Nach CarController.checkTire(): Motorkraft des Zugfahrzeugs erhoehen.
     * Faktor = 1 + Zusatzkraft * (gezogene Fahrzeuge - 1); bei nur einem gezogenen Fahrzeug bleibt alles wie im Original.
     */
    private static Field fVarsBrakingForce;

    /**
     * Nach CarController.checkTire() beim Zugfahrzeug (Zug ab 3 Fahrzeugen):
     *  - Zusatzkraft: Motorkraft * Faktor
     *  - Tempolimit: ueber der Hoechstgeschwindigkeit kein Gas mehr, deutlich darueber leicht bremsen
     */
    public static void boostEngine(BaseVehicle v, Object vars) {
        try {
            if (v == null || vars == null || !isActive() || v.getVehicleTowedBy() != null) {   // nur das Zugfahrzeug selbst
                return;
            }
            int n = 0;
            for (BaseVehicle x = v.getVehicleTowing(); x != null && n < 64; x = x.getVehicleTowing()) {
                n++;
            }
            if (n < 2) {   // Zug mit nur 2 Fahrzeugen: wie im Original
                return;
            }
            if (fVarsEngineForce == null) {
                fVarsEngineForce = vars.getClass().getDeclaredField("engineForce");
                fVarsEngineForce.setAccessible(true);
                fVarsBrakingForce = vars.getClass().getDeclaredField("brakingForce");
                fVarsBrakingForce.setAccessible(true);
            }
            boolean truck = isTruck(v);
            float e = fVarsEngineForce.getFloat(vars);

            if (truck ? boostTruckEnabled : boostCarEnabled) {
                float boostFixed = truck ? boostTruckFixed : boostCarFixed;
                if (e != 0.0F) {   // 0 = kein Gas -> nichts zu verstaerken
                    float factor = boostFixed > 0.0F ? boostFixed : 1.0F + powerBoost * (n - 1);
                    e = e * factor;
                    fVarsEngineForce.setFloat(vars, e);
                }
            }

            // Tempolimit:
            //   Tempo >= Limit       -> Gas weg
            //   Tempo >  Limit + 4   -> zusaetzlich bremsen, je schneller desto staerker (hoechstens 4-fach)
            float limit = truck ? speedTruck : speedCar;
            if (limit > 0.0F) {
                float speed = v.getCurrentSpeedKmHour();
                if (speed >= limit && e > 0.0F) {
                    fVarsEngineForce.setFloat(vars, 0.0F);
                }
                if (speed > limit + 4.0F) {
                    float b = fVarsBrakingForce.getFloat(vars);
                    float want = v.getBrakingForce() * Math.min(4.0F, (speed - limit) / 4.0F);
                    if (want > b) {
                        fVarsBrakingForce.setFloat(vars, want);
                    }
                }
            }
        } catch (Throwable t) {
            log("ERROR in boostEngine: " + t);
        }
    }

    // ------------------------------------------------------------------ Zugbremse

    private static Field fCtrlSteering;

    /**
     * Nach CarController.updateTrailer() eines gezogenen Fahrzeugs: Bremst das Zugfahrzeug, bremst dieses Fahrzeug
     * anteilig mit. 100 % = so stark, als wuerde man es selbst fahren und genauso bremsen wie das Zugfahrzeug.
     * Das Original laesst gezogene Autos nur leicht schleifen (Bremskraft 10), Anhaenger gar nicht.
     */
    public static void trainBrake(CarController c) {
        try {
            if (c == null || GameServer.server || !isActive()) {   // Server rechnet keine Physik
                return;
            }
            BaseVehicle v = c.vehicleObject;
            if (v == null || v.getVehicleTowedBy() == null) {
                return;
            }
            BaseVehicle h = head(v);
            if (h == null || h == v || !h.isBraking()) {   // nur wenn das Zugfahrzeug gerade bremst
                return;
            }
            float pct = isTruck(h) ? brakeTruck : brakeCar;
            if (pct <= 0.0F) {
                return;
            }
            CarController hc = h.getController();
            float headBase = h.getBrakingForce();
            // ratio = wie stark bremst das Zugfahrzeug GERADE im Verhaeltnis zu seiner Grund-Bremskraft?
            //   (13 als Ersatzwert, falls das Zugfahrzeug keinen Controller hat)
            // target = eigene Grund-Bremskraft x ratio x Prozent-Einstellung
            float ratio = (hc != null && headBase > 0.0F) ? hc.brakingForce / headBase : 13.0F;
            if (ratio <= 0.0F) {
                ratio = 1.0F;
            }
            float target = v.getBrakingForce() * ratio * pct;
            if (target <= c.brakingForce) {   // bremst schon staerker -> nicht abschwaechen
                return;
            }
            if (fCtrlSteering == null) {
                fCtrlSteering = CarController.class.getDeclaredField("vehicleSteering");
                fCtrlSteering.setAccessible(true);
            }
            c.brakingForce = target;
            Bullet.controlVehicle(v.vehicleId, c.engineForce, target, fCtrlSteering.getFloat(c));   // neue Bremskraft sofort an die Physik geben
        } catch (Throwable t) {
            log("ERROR in trainBrake: " + t);
        }
    }

    /** Zugbremse (0..1, wird begrenzt) und Tempolimit (km/h) vom Lua-Teil (MultiTow.applyTrainSettings). */
    public static void configureTrain(float brakeCars, float brakeTrucks, float speedCars, float speedTrucks) {
        brakeCar = Math.max(0.0F, Math.min(1.0F, brakeCars));
        brakeTruck = Math.max(0.0F, Math.min(1.0F, brakeTrucks));
        speedCar = Math.max(0.0F, speedCars);
        speedTruck = Math.max(0.0F, speedTrucks);
        log("Train settings | cars: brake " + Math.round(brakeCar * 100) + "%, speed limit " + (speedCar > 0 ? speedCar + " km/h" : "off")
            + " | trucks: brake " + Math.round(brakeTruck * 100) + "%, speed limit " + (speedTruck > 0 ? speedTruck + " km/h" : "off"));
    }

    // ------------------------------------------------------------------ Mithelfen (ab 0.15.0)

    /** Einstellung "laufende Fahrzeuge helfen mit": 0..1 (Anteil der eigenen Motorkraft). */
    public static void setAssist(float pct) {
        assistPct = Math.max(0.0F, Math.min(1.0F, pct));
        log("Running towed vehicles help with " + Math.round(assistPct * 100) + "% of their own engine power"
            + " (only while the towing vehicle has no extra power)");
    }

    public static float getAssist() {
        return assistPct;
    }

    /**
     * Nach CarController.updateTrailer() eines gezogenen Fahrzeugs (direkt nach trainBrake):
     * Laeuft sein Motor und gibt das Zugfahrzeug Gas, faehrt es selbst mit.
     * <pre>
     *   Kraft = Motorkraft des Zugfahrzeugs (jetzt, also mit seiner Gaspedal-Stellung)
     *         * (Motorleistung dieses Fahrzeugs / Motorleistung des Zugfahrzeugs)   -> "gleich viel Gas, eigener Motor"
     *         * Einstellung (0..1)
     * </pre>
     * Bremst das Zugfahrzeug, greift die Zugbremse (keine Hilfe). Rueckwaerts hilft es ebenso (Kraft negativ).
     * Greift das Tempolimit (Zugfahrzeug ohne Gas), hilft auch niemand mit.
     * Nur wenn die Kraft-Erhoehung fuer diesen Zug-Typ aus ist - sonst wuerde beides zusammen zu stark.
     */
    public static void assistEngine(CarController c) {
        try {
            if (c == null || GameServer.server || !isActive() || assistPct <= 0.0F) {
                return;
            }
            BaseVehicle v = c.vehicleObject;
            if (v == null || v.getVehicleTowedBy() == null || !v.isEngineRunning()) {
                return;
            }
            BaseVehicle h = head(v);
            if (h == null || h == v || h.isBraking()) {
                return;
            }
            if (isTruck(h) ? boostTruckEnabled : boostCarEnabled) {
                return;
            }
            CarController hc = h.getController();
            if (hc == null || hc.engineForce == 0.0F) {
                return;
            }
            float headPower = h.getEnginePower();
            float ownPower = v.getEnginePower();
            if (headPower <= 0.0F || ownPower <= 0.0F) {
                return;
            }
            float ratio = Math.min(3.0F, ownPower / headPower);
            float force = hc.engineForce * ratio * assistPct;
            if (fCtrlSteering == null) {
                fCtrlSteering = CarController.class.getDeclaredField("vehicleSteering");
                fCtrlSteering.setAccessible(true);
            }
            c.engineForce = force;
            c.brakingForce = 0.0F;        // das Original laesst gezogene Autos leicht schleifen - beim Mitfahren nicht
            Bullet.controlVehicle(v.vehicleId, force, 0.0F, fCtrlSteering.getFloat(c));
        } catch (Throwable t) {
            log("ERROR in assistEngine: " + t);
        }
    }

    // ------------------------------------------------------------------ Haken: Ereignisse fuer Lua

    /**
     * Wurde die Verbindung mit einem Haken bezahlt (Lua setzt das Merkzeichen "MultiTowHook" im Fahrzeug-ModData des
     * hinteren Fahrzeugs), meldet das Loesen dem Lua-Teil:
     *   BREAK  = Verbindung ist waehrend der Fahrt gerissen  -> Kette und grosser Haken fallen auf den Boden
     *   RETURN = Verbindung wurde abgekuppelt                -> Haken kommt ins Inventar zurueck
     * Beim Entladen eines Fahrzeugs (Chunk) passiert nichts, das Merkzeichen bleibt fuers Wiederverbinden erhalten.
     */
    private static void hookEvent(BaseVehicle front, BaseVehicle rear, boolean spontaneous) {
        try {
            KahluaTable t = rear.getModData();
            if (t == null) {
                return;
            }
            // Gegenstand der Verbindung: neues Merkzeichen (Typ als Text) oder altes Haken-Merkzeichen
            Object it = t.rawget(ITEM_FLAG);
            String item = it instanceof String ? (String) it : null;
            if (item == null && Boolean.TRUE.equals(t.rawget(HOOK_FLAG))) {
                item = HOOK_ITEM;
            }
            t.rawset(HOOK_FLAG, null);
            t.rawset(ITEM_FLAG, null);
            t.rawset(LINK_FLAG, null);   // Merkzeichen weg: Verbindung gibt es ja nicht mehr
            if (item == null) {
                return;
            }

            Vector3f v = null;
            try {
                String att = front.getTowAttachmentSelf();
                if (att != null) {
                    v = front.getAttachmentWorldPos(att, new Vector3f());
                }
            } catch (Throwable ignored) {
                v = null;
            }
            float x = v != null ? v.x : (front.getX() + rear.getX()) * 0.5F;
            float y = v != null ? v.y : (front.getY() + rear.getY()) * 0.5F;
            float z = front.getZ();
            // Nachricht an Lua, Felder mit | getrennt:
            //   BREAK|1234.5|5678.2|0.0|17|23|Base.MultiTowTowBar
            //   ^Art  ^x     ^y     ^z  ^vorne ^hinten ^Gegenstand
            EVENTS.add((spontaneous ? "BREAK|" : "RETURN|") + x + "|" + y + "|" + z + "|" + front.getId() + "|" + rear.getId() + "|" + item);
            log("Item event: " + (spontaneous ? "BREAK" : "RETURN") + " " + item + " at " + x + " / " + y);
        } catch (Throwable th) {
            log("ERROR in hookEvent: " + th);
        }
    }

    /** true = die Verbindung zum Vordermann ist eine starre Abschleppstange (Merkzeichen im ModData, bleibt im Spielstand). */
    public static boolean isBarLink(BaseVehicle rear) {
        try {
            KahluaTable t = rear == null ? null : rear.getModData();
            return t != null && "bar".equals(t.rawget(LINK_FLAG));
        } catch (Throwable th) {
            return false;
        }
    }

    /**
     * Geraeusch-Ereignis fuer den Lua-Teil: "ATTACH|x|y|z" (angekuppelt), "DETACH|x|y|z" (abgekuppelt),
     * "SNAP|x|y|z" (Verbindung gerissen). Position = Kupplungspunkt des vorderen Fahrzeugs.
     */
    private static void soundEvent(String type, BaseVehicle front, BaseVehicle rear) {
        try {
            Vector3f v = null;
            try {
                String att = front.getTowAttachmentSelf();
                if (att != null) {
                    v = front.getAttachmentWorldPos(att, new Vector3f());
                }
            } catch (Throwable ignored) {
                v = null;
            }
            float x = v != null ? v.x : (front.getX() + rear.getX()) * 0.5F;
            float y = v != null ? v.y : (front.getY() + rear.getY()) * 0.5F;
            EVENTS.add(type + "|" + x + "|" + y + "|" + front.getZ() + "|" + front.getId() + "|" + rear.getId());
        } catch (Throwable th) {
            log("ERROR in soundEvent: " + th);
        }
    }

    /** Fuer die Band-Anzeige: {vordere Kupplung des hinteren Fahrzeugs, hintere Kupplung des Vordermanns} oder null. */
    static String[] frontAttOf(short rearId) {
        return FRONT_ATT.get(rearId);
    }

    /** Fuer Lua: naechstes Ereignis ("BREAK|x|y|z" oder "RETURN|x|y|z") oder null. */
    public static String popEvent() {
        return EVENTS.poll();
    }

    /** Das Spiel loest gleich eine Verbindung wegen Ueberlastung (Impuls) - Aufruf aus Bullet.onVehicleConstraintImpulse. */
    public static void markImpulse(float impulse) {
        if (impulse >= 500.0F && isActive()) {   // ab 500 gilt es als "Ruck, der reissen laesst"
            lastImpulseNs = System.nanoTime();
        }
    }

    /** Das Spiel loest gleich eine Verbindung, weil das Fahrzeug kippt - Aufruf aus BaseVehicle.checkTrailerVerticalAlignment. */
    public static void markTipping(BaseVehicle v) {
        try {
            if (v != null && v.constraintTowing != -1 && v.getUpVectorDot() < 0.8F && isActive()) {   // UpVectorDot: 1 = aufrecht, 0 = auf der Seite
                lastImpulseNs = System.nanoTime();
            }
        } catch (Throwable t) {
            // ignorieren
        }
    }
}
