package multitow;

import zombie.iso.IsoCell;
import zombie.iso.weather.ClimateManager;
import zombie.vehicles.BaseVehicle;

/**
 * Sichtbare Darstellung der Verbindungen (Kette/Stange zwischen den Fahrzeugen).
 * Arten: 0 = aus, 1 = Bild (TextureLinkStyle), 2 = 3D-Modell (ModelLinkStyle, ab 0.16; nur Ketten - Stangen bleiben ein Bild;
 *        faellt auf das Bild zurueck, wenn das Modell nicht gezeichnet werden kann).
 *
 * <pre>
 *  Wer ruft wen?
 *    PatchLinkRender  -&gt;  LinkVisual.render  -&gt;  LinkModels.render  -&gt;  LinkGeometry.compute
 *                                                                   -&gt;  LinkStyle.draw
 * </pre>
 * &gt;&gt; WARUM ueber LinkVisual: so gibt es nur EINEN Patch fuers Zeichnen; Ketten zuerst,
 *    die Belastungs-Baender danach (liegen dadurch obenauf).
 */
public final class LinkModels {
    public static final int OFF = 0, TEXTURE = 1, MODEL = 2;

    private static volatile int mode = TEXTURE;
    private static final TextureLinkStyle TEXTURE_STYLE = new TextureLinkStyle();
    /** 3D-Darstellung der Ketten (ab 0.16). */
    private static final ModelLinkStyle MODEL_STYLE = new ModelLinkStyle();
    private static LinkStyle modelStyle = MODEL_STYLE;
    private static final LinkGeometry GEO = new LinkGeometry();   // EIN Objekt fuer alle Verbindungen, wird jedes Mal neu befuellt
    private static boolean failed;   // nach einem Fehler aus, bis die Option geaendert wird

    private LinkModels() {
    }

    /** Neue Art aus dem Optionsmenue. Setzt auch einen frueheren Fehler zurueck (neuer Versuch). */
    public static void setMode(int m) {
        mode = Math.max(OFF, Math.min(MODEL, m));
        failed = false;
        MODEL_STYLE.resetBroken();
    }

    /** Abstimmung des 3D-Modells (Test): Variante 0..7 der Ausrichtung und Groessenfaktor. Neuer Versuch nach Fehler. */
    public static void setModelTuning(int variant, float size) {
        ModelLinkStyle.setTuning(variant, size);
        MODEL_STYLE.resetBroken();
        failed = false;
    }

    public static int getMode() {
        return mode;
    }

    /**
     * Welche Darstellung gilt gerade?
     * <pre>
     *  Modus 2 und Modell fertig  -&gt; Modell
     *  sonst, Bilder geladen      -&gt; Bild
     *  sonst                      -&gt; nichts (null)
     * </pre>
     */
    private static LinkStyle current() {
        if (mode == MODEL && modelStyle != null && modelStyle.isAvailable()) {
            return modelStyle;
        }
        return TEXTURE_STYLE.isAvailable() ? TEXTURE_STYLE : null;
    }

    /** Aufruf aus LinkVisual.render (jedes Bild, waehrend die Welt gezeichnet wird). */
    public static void render(IsoCell cell) {
        if (mode == OFF || failed) {
            return;
        }
        try {
            LinkStyle style = current();
            if (style == null) {
                return;
            }
            float light = 1.0F;
            try {
                // Helligkeit: nachts nicht ganz schwarz (mindestens 25 %), tagsueber 100 %
                light = 0.25F + 0.75F * ClimateManager.getInstance().getAmbient();
            } catch (Throwable ignored) {
                light = 1.0F;
            }
            for (BaseVehicle v : cell.getVehicles()) {
                if (v.getVehicleTowedBy() != null && GEO.compute(v)) {   // jede Verbindung einmal: vom hinteren Fahrzeug aus
                    if (GEO.bar && style == modelStyle) {
                        // Stange: gibt es nur als Bild
                        if (TEXTURE_STYLE.isAvailable()) {
                            TEXTURE_STYLE.draw(GEO, light);
                        }
                    } else {
                        style.draw(GEO, light);
                    }
                }
            }
        } catch (Throwable t) {
            failed = true;
            System.out.println("[MultiTowCore] ERROR drawing links (turned off until the option changes): " + t);
        }
    }
}
