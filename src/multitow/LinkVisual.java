package multitow;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.joml.Vector3f;

import zombie.characters.IsoPlayer;
import zombie.debug.LineDrawer;
import zombie.iso.IsoCamera;
import zombie.iso.IsoCell;
import zombie.iso.IsoWorld;
import zombie.network.GameServer;
import zombie.vehicles.BaseVehicle;
import zombie.vehicles.VehicleManager;

/**
 * Optionale Anzeige der Verbindungen als farbiges Band: gruen = entspannt, gelb = belastet, rot = kurz vor dem Reissen.
 *
 * Belastung = das Groessere aus
 *  - Kraft auf die Verbindung (Impuls aus der Physik) im Verhaeltnis zur Reissgrenze des Spiels (1500, gekippt 500)
 *  - Ueberdehnung eines Seils: Abstand der Kupplungspunkte ueber der Seillaenge (1,5) hinaus
 * Der Impuls ist nur dort bekannt, wo die Physik gerechnet wird (Einzelspieler / Fahrer im MP); sonst zaehlt die Dehnung.
 *
 * <pre>
 *   Farbe des Bandes je nach Belastung (0..1):
 *
 *   0.0          0.5          1.0
 *    |------------|------------|
 *   gruen       gelb          rot
 *   (r=0,g=1)  (r=1,g=1)   (r=1,g=0)
 *
 *   r = Belastung x 2        (ab 0.5 voll)
 *   g = (1 - Belastung) x 2  (bis 0.5 voll)
 * </pre>
 *
 * Wer nutzt die Belastung noch?  Die Zug-Anzeige (HUD) und der Verschleiss - ueber
 * {@link #stressOf(BaseVehicle)} bzw. die Lua-Funktion multiTowLinkStress.
 */
public final class LinkVisual {
    private static volatile boolean enabled = false;   // Baender immer zeigen (Optionsmenue)
    /** Nur Verbindungen in der Naehe anzeigen, wenn die Figur zu Fuss ist (unabhaengig von "enabled"). */
    private static volatile boolean near = false;
    private static volatile float nearDist = 2.0F;   // Felder

    /** Ab welchem Abstand (Seil) Belastung beginnt und ueber welche Strecke sie bis "rot" ansteigt. */
    private static volatile float ropeStart = 1.45F;
    private static volatile float ropeRange = 0.6F;

    // ConcurrentHashMap: onImpulse kommt aus der Physik, render aus dem Zeichnen -
    // moeglicherweise verschiedene Threads. Diese Map-Art vertraegt das.
    /** hinteres Fahrzeug -> {Belastung aus Impuls 0..1+, Zeitpunkt ns} */
    private static final Map<Short, float[]> IMPULSE = new ConcurrentHashMap<>();
    private static final Map<Short, Long> IMPULSE_TIME = new ConcurrentHashMap<>();
    /** hinteres Fahrzeug -> angezeigter (geglaetteter) Wert */
    private static final Map<Short, Float> SHOWN = new ConcurrentHashMap<>();
    private static long lastRenderNs;   // Zeit des letzten Bildes (fuer die Glaettung)

    // wiederverwendete Hilfsvektoren: nicht jedes Bild neue Objekte anlegen (schont den Speicher)
    private static final Vector3f TMP_A = new Vector3f();
    private static final Vector3f TMP_B = new Vector3f();

    private LinkVisual() {
    }

    // ---------------------------------------------------------------- Einstellungen aus Lua
    public static void setEnabled(boolean on) {
        enabled = on;
        if (!on) {
            IMPULSE.clear();
            IMPULSE_TIME.clear();
            SHOWN.clear();
        }
    }

    public static boolean isEnabled() {
        return enabled;
    }

    public static void setNear(boolean on) {
        near = on;
    }

    public static void setNearDistance(float d) {
        nearDist = Math.max(0.5F, d);   // mindestens einen halben Meter
    }

    private static boolean anyOn() {
        return enabled || near;
    }

    //
    //        P
    //        |  <- gesuchter Abstand
    //   A----+--------B        t = wie weit entlang A->B (0 = bei A, 1 = bei B), auf 0..1 begrenzt
    //
    /** Abstand eines Punkts (px,py) zur Strecke (ax,ay)-(bx,by), nur waagerecht. */
    private static float distToSegment(float px, float py, float ax, float ay, float bx, float by) {
        float vx = bx - ax, vy = by - ay;
        float len2 = vx * vx + vy * vy;
        float t = len2 < 1.0e-6F ? 0.0F : ((px - ax) * vx + (py - ay) * vy) / len2;
        t = t < 0.0F ? 0.0F : (t > 1.0F ? 1.0F : t);
        float cx = ax + t * vx - px, cy = ay + t * vy - py;
        return (float) Math.sqrt(cx * cx + cy * cy);
    }

    /** Nur fuer Tests (siehe LuaApi.multiTowSetLinkTuning). */
    public static void setTuning(float start, float range) {
        ropeStart = Math.max(0.0F, start);
        ropeRange = Math.max(0.05F, range);
    }

    /** Aufruf aus Bullet.onVehicleConstraintImpulse: A = vorderes, B = hinteres Fahrzeug der Verbindung. */
    public static void onImpulse(int vidA, int vidB, float impulse) {
        // immer merken (nicht nur bei sichtbaren Baendern): Zug-Anzeige und Verschleiss brauchen die Belastung auch
        try {
            BaseVehicle a = VehicleManager.instance.getVehicleByID((short) vidA);
            BaseVehicle b = VehicleManager.instance.getVehicleByID((short) vidB);
            // Reissgrenze des Spiels:  beide aufrecht -> 1500,  eines schraeg/gekippt -> 500
            // s = Kraft / Grenze  ->  1.0 heisst "genau an der Grenze"
            float limit = (a != null && b != null && a.getUpVectorDot() > 0.8F && b.getUpVectorDot() > 0.8F) ? 1500.0F : 500.0F;
            float s = Math.abs(impulse) / limit;
            short key = (short) vidB;   // gespeichert beim HINTEREN Fahrzeug
            long now = System.nanoTime();
            float[] cur = IMPULSE.get(key);
            Long t = IMPULSE_TIME.get(key);
            // innerhalb eines Bildes den groessten Wert behalten
            if (cur == null || t == null || now - t > 30_000_000L || s > cur[0]) {
                IMPULSE.put(key, new float[] { s });
                IMPULSE_TIME.put(key, now);
            }
        } catch (Throwable ignored) {
            // nur Anzeige
        }
    }

    /** Wert auf 0..1 begrenzen. */
    private static float clamp01(float v) {
        return v < 0.0F ? 0.0F : (v > 1.0F ? 1.0F : v);
    }

    private static final Vector3f TMP_C = new Vector3f();
    private static final Vector3f TMP_D = new Vector3f();

    /**
     * Belastung der Verbindung vor diesem (hinteren) Fahrzeug, 0 = entspannt, 1 = kurz vor dem Reissen.
     * Gleiche Rechnung wie das farbige Band (Dehnung bzw. Abweichung der Stange, Kraftstoesse der Physik).
     * -1 = keine Verbindung oder Positionen unbekannt.
     */
    public static float stressOf(BaseVehicle rear) {
        try {
            if (rear == null) {
                return -1.0F;
            }
            BaseVehicle front = rear.getVehicleTowedBy();
            if (front == null) {
                return -1.0F;
            }
            String[] att = ChainTow.frontAttOf(rear.vehicleId);
            String attA = att != null ? att[1] : front.getTowAttachmentSelf();
            String attB = att != null ? att[0] : front.getTowAttachmentOther();
            if (attA == null || attB == null) {
                return -1.0F;
            }
            Vector3f pa = front.getTowingWorldPos(attA, TMP_C);
            if (pa == null) {
                return -1.0F;
            }
            float ax = pa.x, ay = pa.y;
            Vector3f pb = rear.getTowedByWorldPos(attB, TMP_D);
            if (pb == null) {
                return -1.0F;
            }
            return linkStress(front, rear, ax, ay, pb.x, pb.y, System.nanoTime());
        } catch (Throwable t) {
            return -1.0F;
        }
    }

    /**
     * Belastung aus zwei Quellen - die groessere gewinnt:
     * <pre>
     *  1) Dehnung (aus den Positionen):
     *       Stange:    |Abstand - 1.0| ab 0.1 Abweichung, voll bei 0.4
     *       Seil:      Abstand ab ropeStart (1.45), voll nach ropeRange (0.6) mehr
     *       Anhaenger: Abstand ab 0.3, voll bei 1.0
     *  2) Kraftstoss (aus der Physik), klingt in 1 Sekunde linear auf 0 ab:
     *       Wert x (1 - Alter in Sekunden)
     * </pre>
     */
    private static float linkStress(BaseVehicle front, BaseVehicle rear, float ax, float ay, float bx, float by, long now) {
        boolean rope = !front.getScriptName().contains("Trailer") && !rear.getScriptName().contains("Trailer");
        float dx = ax - bx, dy = ay - by;
        float dist = (float) Math.sqrt(dx * dx + dy * dy);
        float stretch;
        if (ChainTow.isBarLink(rear)) {
            // Stange: Abstand bleibt fast gleich, jede Abweichung ist echte Belastung
            stretch = clamp01((Math.abs(dist - ChainTow.BAR_LENGTH) - 0.1F) / 0.3F);
        } else {
            stretch = rope ? clamp01((dist - ropeStart) / ropeRange) : clamp01((dist - 0.3F) / 0.7F);
        }
        float imp = 0.0F;
        float[] iv = IMPULSE.get(rear.vehicleId);
        Long it = IMPULSE_TIME.get(rear.vehicleId);
        if (iv != null && it != null) {
            float age = (now - it) / 1.0e9F;
            imp = age > 1.0F ? 0.0F : iv[0] * (1.0F - age);
        }
        return clamp01(Math.max(stretch, imp));
    }

    // ---------------------------------------------------------------- Zeichnen
    /** Aufruf nach LineDrawer.render(), also jedes Bild waehrend die Welt gezeichnet wird. */
    public static void render() {
        if (GameServer.server) {   // Server hat keinen Bildschirm
            return;
        }
        if (!ChainTow.isActive()) {   // Multi-Tow im geladenen Spielstand aus -> keine Ketten/Baender zeichnen
            return;
        }
        // zuerst die sichtbaren Ketten/Stangen, die Baender liegen darueber
        IsoCell cellForLinks = IsoWorld.instance == null ? null : IsoWorld.instance.currentCell;
        if (cellForLinks != null) {
            LinkModels.render(cellForLinks);
        }
        if (!anyOn()) {
            return;
        }
        try {
            IsoCell cell = cellForLinks;
            if (cell == null) {
                return;
            }
            long now = System.nanoTime();
            float dt = lastRenderNs == 0 ? 0.016F : Math.min(0.25F, (now - lastRenderNs) / 1.0e9F);   // Sekunden seit letztem Bild (max. 0.25)
            lastRenderNs = now;

            float zoom = 1.0F;
            try {
                zoom = IsoCamera.cameras[IsoCamera.frameState.playerIndex].zoom;
            } catch (Throwable ignored) {
                zoom = 1.0F;
            }
            // Linienstaerke an den Zoom anpassen: weit rausgezoomt duenner, nah dran dicker (2..8 Pixel)
            int thick = Math.max(2, Math.min(8, Math.round(5.0F / Math.max(0.25F, zoom))));

            // Naehe-Anzeige: nur fuer die Figur dieser Bildschirmhaelfte, und nur wenn sie zu Fuss ist
            IsoPlayer me = null;
            if (!enabled && near) {
                try {
                    me = IsoPlayer.getPlayer(IsoCamera.frameState.playerIndex);
                } catch (Throwable ignored) {
                    me = null;
                }
                if (me == null || me.getVehicle() != null) {
                    return;
                }
            }

            for (BaseVehicle front : cell.getVehicles()) {   // jede Verbindung genau einmal: von vorne aus gesehen
                BaseVehicle rear = front.getVehicleTowing();
                if (rear == null) {
                    continue;
                }
                String[] att = ChainTow.frontAttOf(rear.vehicleId);
                String attA = att != null ? att[1] : front.getTowAttachmentSelf();
                String attB = att != null ? att[0] : front.getTowAttachmentOther();
                if (attA == null || attB == null) {
                    continue;
                }
                Vector3f pa = front.getTowingWorldPos(attA, TMP_A);
                if (pa == null) {
                    continue;
                }
                float ax = pa.x, ay = pa.y, az = pa.z;
                Vector3f pb = rear.getTowedByWorldPos(attB, TMP_B);
                if (pb == null) {
                    continue;
                }
                float bx = pb.x, by = pb.y, bz = pb.z;

                float alpha = 1.0F;
                if (me != null) {
                    float d = distToSegment(me.getX(), me.getY(), ax, ay, bx, by);
                    if (d > nearDist + 0.5F) {
                        continue;
                    }
                    // weich einblenden zwischen nearDist + 0,5 und nearDist
                    alpha = d <= nearDist ? 1.0F : 1.0F - (d - nearDist) / 0.5F;
                }

                float target = linkStress(front, rear, ax, ay, bx, by, now);

                // Glaettung:
                //   Belastung steigt  -> schnell hinterher (in ca. 1/12 s)
                //   Belastung faellt  -> langsam zurueck (0.8 pro Sekunde)
                Float prev = SHOWN.get(rear.vehicleId);
                float shown = prev == null ? target : prev;
                // schnell rot werden, langsam wieder gruen (gut lesbar, kein Flackern)
                shown = target > shown ? shown + (target - shown) * Math.min(1.0F, dt * 12.0F)
                                       : Math.max(target, shown - dt * 0.8F);
                SHOWN.put(rear.vehicleId, shown);

                float r = clamp01(shown * 2.0F);
                float g = clamp01((1.0F - shown) * 2.0F);

                // Zeichnen:  erst ein etwas dickerer schwarzer Rand, darueber das farbige Band,
                //            an beiden Enden ein kleiner Kreis (Kupplungspunkte)
                //   o=============o
                LineDrawer.DrawIsoLine(ax, ay, az, bx, by, bz, 0.0F, 0.0F, 0.0F, 0.55F * alpha, thick + 2);
                LineDrawer.DrawIsoLine(ax, ay, az, bx, by, bz, r, g, 0.0F, 0.95F * alpha, thick);
                LineDrawer.DrawIsoCircle(ax, ay, az, 0.12F, 12, r, g, 0.0F, 0.95F * alpha);
                LineDrawer.DrawIsoCircle(bx, by, bz, 0.12F, 12, r, g, 0.0F, 0.95F * alpha);
            }
        } catch (Throwable t) {
            // !! Fehler beim Zeichnen -> Anzeige abschalten, statt jedes Bild erneut zu scheitern
            System.out.println("[MultiTowCore] ERROR in link display (turned off): " + t);
            enabled = false;
            near = false;
        }
    }
}
