package multitow;

import org.joml.Vector3f;

import zombie.vehicles.BaseVehicle;

/**
 * Lage einer Verbindung in der Welt: die beiden Kupplungspunkte, Art (Kette/Stange) und wie stark eine lockere
 * Kette durchhaengt. Wird von jeder Darstellungsart benutzt (heute: Bild, spaeter: 3D-Modell), damit die
 * Berechnung nur an einer Stelle steht.
 *
 * <pre>
 *   Seitenansicht einer lockeren Kette:
 *
 *   A (ax,ay,az) o                         o B (bx,by,bz)
 *                 \                       /
 *                  '-._               _.-'
 *                      '-----+-----'
 *                            |  &lt;- sag (Durchhang in der Mitte)
 *   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~  groundZ (Boden)
 *
 *   length &gt;= CHAIN_LENGTH oder Stange  -&gt;  sag = 0 (gerade Linie)
 * </pre>
 *
 * !! ACHTUNG Einheiten: x/y sind Felder (= etwa Meter), z ist in ETAGEN.
 *    Zum Rechnen in Metern deshalb z mal LEVEL_HEIGHT, zurueck geteilt durch LEVEL_HEIGHT.
 */
public final class LinkGeometry {
    /** Hoehe einer Etage in Metern (z-Koordinate der Welt ist in Etagen). */
    public static final float LEVEL_HEIGHT = 2.44949F;
    /** Laenge einer Kette/eines Seils in Metern (ab hier ist sie straff, siehe LinkVisual ropeStart). */
    public static final float CHAIN_LENGTH = 1.45F;

    // ---- Ergebnis von compute() (oeffentliche Felder: werden jedes Bild neu gefuellt, kein Kopieren noetig) ----
    public BaseVehicle front;
    public BaseVehicle rear;
    /** Kupplungspunkt vorne (am vorderen Fahrzeug) und hinten (am hinteren Fahrzeug), Welt-Koordinaten. */
    public float ax, ay, az, bx, by, bz;
    /** Boden unter der Verbindung (Etage), fuer den Schatten. */
    public float groundZ;
    public boolean bar;   // true = Abschleppstange, false = Kette/Seil
    /** Durchhang in der Mitte in Metern (0 = straff). */
    public float sag;
    /** Abstand der Kupplungspunkte in Metern. */
    public float length;

    private static final Vector3f TMP_A = new Vector3f();
    private static final Vector3f TMP_B = new Vector3f();

    /** Fuellt die Daten fuer die Verbindung vor "rear". false = keine (darstellbare) Verbindung. */
    public boolean compute(BaseVehicle rear) {
        this.rear = rear;
        this.front = rear == null ? null : rear.getVehicleTowedBy();
        if (front == null) {
            return false;
        }
        // echte Anhaenger haben ihre Deichsel im Modell, da zeichnen wir nichts
        if (front.getScriptName().contains("Trailer") || rear.getScriptName().contains("Trailer")) {
            return false;
        }
        // Kupplungsnamen: bevorzugt aus ChainTow (stimmen auch beim mittleren Fahrzeug), sonst aus dem Spiel
        String[] att = ChainTow.frontAttOf(rear.vehicleId);
        String attA = att != null ? att[1] : front.getTowAttachmentSelf();
        String attB = att != null ? att[0] : front.getTowAttachmentOther();
        if (attA == null || attB == null) {
            return false;
        }
        Vector3f pa = front.getTowingWorldPos(attA, TMP_A);
        if (pa == null) {
            return false;
        }
        ax = pa.x;
        ay = pa.y;
        az = pa.z;
        Vector3f pb = rear.getTowedByWorldPos(attB, TMP_B);
        if (pb == null) {
            return false;
        }
        bx = pb.x;
        by = pb.y;
        bz = pb.z;
        groundZ = (float) Math.floor(Math.min(az, bz));   // Etage des tieferen Punkts
        bar = ChainTow.isBarLink(rear);
        float dx = bx - ax, dy = by - ay, dz = (bz - az) * LEVEL_HEIGHT;
        length = (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (bar || length >= CHAIN_LENGTH) {
            sag = 0.0F;
        } else {
            // Naeherung fuer ein durchhaengendes Seil der Laenge L zwischen zwei Punkten im Abstand d
            //   sag = Wurzel( 3 x d x (L - d) / 8 ),  hoechstens 0.5 m
            //   Beispiel: L = 1.45, d = 1.0  ->  sag = ca. 0.41 m
            sag = (float) Math.min(0.5, Math.sqrt(3.0 * length * (CHAIN_LENGTH - length) / 8.0));
        }
        return true;
    }

    /** Punkt auf der Verbindung, t = 0 (vorne) .. 1 (hinten), mit Durchhang. Ergebnis in out[0..2]. */
    public void pointAt(float t, float[] out) {
        out[0] = ax + (bx - ax) * t;
        out[1] = ay + (by - ay) * t;
        // Durchhang als Parabel:  4 x t x (1 - t)  ist 0 an den Enden und 1 in der Mitte (t = 0.5)
        //   t:      0     0.25   0.5   0.75   1
        //   Form:   0     0.75   1.0   0.75   0
        out[2] = az + (bz - az) * t - sag * 4.0F * t * (1.0F - t) / LEVEL_HEIGHT;
        // nicht unter den Boden haengen (Kette liegt dann auf)
        float floor = groundZ + 0.02F / LEVEL_HEIGHT;
        if (out[2] < floor) {
            out[2] = floor;
        }
    }
}
