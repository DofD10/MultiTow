package multitow;

import zombie.core.Core;
import zombie.core.skinnedmodel.model.ItemModelRenderer;
import zombie.core.skinnedmodel.model.WorldItemModelDrawer;
import zombie.inventory.InventoryItem;
import zombie.inventory.InventoryItemFactory;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;

/**
 * Zeichnet eine Kette als echtes 3D-Modell (ab 0.16): das Modell eines kurzen Kettenstuecks (
 * media/models_X/WorldItems/MultiTow_LinkSegment.glb, 2 Glieder) wird mehrmals hintereinander entlang der Verbindung gezeichnet.
 * Stangen bleiben ein Bild (TextureLinkStyle), siehe LinkModels.
 *
 * <h3>Wie zeichnet man ein Modell an eine beliebige Stelle?</h3>
 * Genau so, wie das Spiel Gegenstaende auf dem Boden zeichnet: {@link WorldItemModelDrawer#renderMain} mit einem
 * unsichtbaren Gegenstand (Base.MultiTowLinkSegment, nur fuer die Anzeige, liegt nirgends in der Welt).
 * Lage und Groesse kommen aus dem Gegenstand selbst:
 * <pre>
 *   worldZRotation  = Drehung um die Hochachse (Richtung der Kette)      -> im Modell: Drehung um Y
 *   worldYRotation  = Neigung (Kette steigt/faellt, haengt durch)          -> im Modell: Drehung um Z
 *   worldScale      = Laenge dieses Stuecks / Laenge des Modells (fast immer 0.94 .. 1.06)
 *
 *   A o==[2 Glieder]==[2 Glieder]==[2 Glieder]==o B      (n Stuecke entlang der ECHTEN Kettenlaenge mit Durchhang)
 * </pre>
 * !! Das Spiel zeichnet Bodenmodelle nur, wenn in den Optionen "3D-Gegenstaende am Boden" an ist. Sonst (oder wenn
 *    das Modell fehlt) faellt LinkModels automatisch auf das Bild zurueck.
 *
 * <h3>Ausrichtung (Test)</h3>
 * Wie herum das Spiel das Modell dreht, laesst sich ohne Ausprobieren nicht sicher sagen. Darum gibt es 8 Varianten
 * (Vorzeichen der Drehung, 0 oder 90 Grad versetzt, Vorzeichen der Neigung), einstellbar ueber die Lua-Funktion
 * multiTowSetLinkModelTuning (Admin-Optionen in DO Utilities). Sobald die richtige feststeht, wird sie Standard.
 */
public final class ModelLinkStyle implements LinkStyle {
    /** Name des Anzeige-Gegenstands (media/scripts/MultiTow_items.txt). */
    private static final String ITEM_TYPE = "Base.MultiTowLinkSegment";
    /** Laenge des Modells (ein Glied flach + ein Glied hochkant) in Metern. MUSS zum Modell passen
     *  (MultiTow_LinkSegment.glb: 0.1217 m, von der Mitte eines flachen Glieds zur Mitte des naechsten). */
    private static final float SEG_LEN = 0.1217F;
    /** Punkte, mit denen die (durchhaengende) Kette vermessen wird. */
    private static final int SAMPLES = 32;
    /** Winzige Zusatzdrehung in Grad, die das Atlas-Bild des Spiels abschaltet (siehe draw). */
    private static final float NO_ATLAS_ANGLE = 0.001F;

    // ---- Abstimmung (Lua: multiTowSetLinkModelTuning) ----
    private static volatile int variant = 0;          // 0..7, siehe yaw()/pitch()
    private static volatile float sizeFactor = 1.0F;  // so viel groesser zeichnet das Spiel das Modell als gedacht

    private InventoryItem item;
    private boolean created;     // nur EINMAL versuchen, den Gegenstand anzulegen
    private boolean broken;      // Spiel hat das Modell abgelehnt -> bis zur naechsten Abstimmung aus

    private final float[] p0 = new float[3];
    private final float[] p1 = new float[3];
    // Kurve der Kette als Punktliste (x, y, z in Etagen) + Strecke vom Anfang bis zu jedem Punkt (Meter)
    private final float[][] pts = new float[SAMPLES + 1][3];
    private final float[] dist = new float[SAMPLES + 1];

    /** Variante (0..7) und Groessenfaktor setzen. Setzt einen frueheren Fehler zurueck (neuer Versuch). */
    public static void setTuning(int v, float size) {
        variant = Math.max(0, Math.min(7, v));
        sizeFactor = Math.max(0.1F, Math.min(10.0F, size));
        System.out.println("[MultiTowCore] link model tuning: variant " + variant + ", size " + sizeFactor);
    }

    public static int getVariant() {
        return variant;
    }

    public static float getSizeFactor() {
        return sizeFactor;
    }

    void resetBroken() {
        broken = false;
    }

    private InventoryItem item() {
        if (!created) {
            created = true;
            try {
                item = InventoryItemFactory.CreateItem(ITEM_TYPE);
                if (item == null) {
                    System.out.println("[MultiTowCore] link model: item " + ITEM_TYPE + " not found - using the picture");
                }
            } catch (Throwable t) {
                System.out.println("[MultiTowCore] link model: item not created (" + t + ") - using the picture");
                item = null;
            }
        }
        return item;
    }

    @Override
    public boolean isAvailable() {
        if (broken) {
            return false;
        }
        try {
            if (!Core.getInstance().isOption3DGroundItem()) {   // Spieler hat 3D-Bodengegenstaende aus
                return false;
            }
        } catch (Throwable t) {
            return false;
        }
        return item() != null;
    }

    // Drehung um die Hochachse in Grad. Varianten:  bit 0 = Vorzeichen, bit 1 = 90 Grad versetzt
    private static float yaw(float dx, float dy) {
        float deg = (float) Math.toDegrees(Math.atan2(dy, dx));
        if ((variant & 1) != 0) {
            deg = -deg;
        }
        if ((variant & 2) != 0) {
            deg += 90.0F;
        }
        return wrap(deg);
    }

    // Neigung in Grad.  bit 2 = Vorzeichen
    private static float pitch(float horiz, float dzMeters) {
        float deg = (float) Math.toDegrees(Math.atan2(dzMeters, Math.max(1.0e-4F, horiz)));
        return wrap((variant & 4) != 0 ? -deg : deg);
    }

    private static float wrap(float deg) {
        deg %= 360.0F;
        return deg < 0.0F ? deg + 360.0F : deg;
    }

    /** Punkt auf der vermessenen Kurve in der Strecke s (Meter vom Anfang) -> out. */
    private void at(float s, float[] out) {
        int k = 1;
        while (k < SAMPLES && dist[k] < s) {
            k++;
        }
        float seg = dist[k] - dist[k - 1];
        float f = seg > 1.0e-6F ? (s - dist[k - 1]) / seg : 0.0F;
        f = Math.max(0.0F, Math.min(1.0F, f));
        for (int c = 0; c < 3; c++) {
            out[c] = pts[k - 1][c] + (pts[k][c] - pts[k - 1][c]) * f;
        }
    }

    @Override
    public void draw(LinkGeometry g, float light) {
        InventoryItem it = item();
        if (it == null || g.length < 0.05F) {
            return;
        }
        IsoCell cell = IsoWorld.instance == null ? null : IsoWorld.instance.currentCell;
        if (cell == null) {
            return;
        }
        // 1) Kurve vermessen: Punkte entlang der Kette und die Strecke bis zu jedem Punkt (ECHTE Kettenlaenge,
        //    mit Durchhang). Frueher wurde nur der gerade Abstand A-B genommen: bei nahen Fahrzeugen haengt die
        //    Kette aber stark durch, die wenigen Stuecke wurden riesig gestreckt (Glieder "immer groesser").
        for (int k = 0; k <= SAMPLES; k++) {
            g.pointAt((float) k / SAMPLES, pts[k]);
            if (k == 0) {
                dist[0] = 0.0F;
            } else {
                float ex = pts[k][0] - pts[k - 1][0], ey = pts[k][1] - pts[k - 1][1];
                float ez = (pts[k][2] - pts[k - 1][2]) * LinkGeometry.LEVEL_HEIGHT;
                dist[k] = dist[k - 1] + (float) Math.sqrt(ex * ex + ey * ey + ez * ez);
            }
        }
        float arc = dist[SAMPLES];
        // 2) So viele Stuecke, dass jedes etwa seine echte Laenge hat (Glieder bleiben gleich gross).
        //    Rest wird auf alle verteilt: Abweichung hoechstens ein halbes Stueck (bei 1 m Kette etwa +-6 %).
        float unit = SEG_LEN * sizeFactor;                       // so lang ist ein Stueck bei worldScale 1
        int n = Math.max(1, Math.min(64, Math.round(arc / unit)));
        for (int i = 0; i < n; i++) {
            at(arc * i / n, p0);
            at(arc * (i + 1) / n, p1);
            float dx = p1[0] - p0[0], dy = p1[1] - p0[1];
            float dz = (p1[2] - p0[2]) * LinkGeometry.LEVEL_HEIGHT;
            float horiz = (float) Math.sqrt(dx * dx + dy * dy);
            float len = (float) Math.sqrt(horiz * horiz + dz * dz);
            float mx = (p0[0] + p1[0]) * 0.5F, my = (p0[1] + p1[1]) * 0.5F, mz = (p0[2] + p1[2]) * 0.5F;
            IsoGridSquare sq = cell.getGridSquare((int) Math.floor(mx), (int) Math.floor(my), (int) Math.floor(mz));
            if (sq == null) {
                continue;
            }
            it.setWorldScale(len / unit);
            it.setWorldXRotation(0.0F);
            it.setWorldZRotation(yaw(dx, dy));
            it.setWorldYRotation(pitch(horiz, dz));
            // !! NICHT die kurze Form renderMain(..., 0f) benutzen: die nimmt, wenn moeglich, ein fertiges Bild aus dem
            //    "World Item Atlas" des Spiels. Das passt nur, solange sich nichts bewegt - beim Fahren aendern sich
            //    Drehung/Groesse jedes Bild, das Atlas-Bild ist dann nie fertig und die Kette FLACKERT.
            //    Ein Zusatzwinkel > 0 (hier 0.001 Grad, unsichtbar) schaltet den Atlas fuer diesen Aufruf ab;
            //    -1 = Drehung aus dem Gegenstand nehmen (worldX/Y/ZRotation).
            ItemModelRenderer.RenderStatus st = WorldItemModelDrawer.renderMain(it, sq, sq, mx, my, mz, NO_ATLAS_ANGLE, -1.0F, false);
            if (st == ItemModelRenderer.RenderStatus.Failed || st == ItemModelRenderer.RenderStatus.NoModel) {
                broken = true;   // Modell fehlt / abgelehnt -> ab jetzt Bild (bis zur naechsten Abstimmung)
                System.out.println("[MultiTowCore] link model not drawn (" + st + ") - using the picture");
                return;
            }
        }
    }
}
