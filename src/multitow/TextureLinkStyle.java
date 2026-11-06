package multitow;

import zombie.core.SpriteRenderer;
import zombie.core.textures.Texture;
import zombie.iso.IsoCamera;
import zombie.iso.IsoUtils;
import zombie.iso.PlayerCamera;

/**
 * Zeichnet eine Verbindung als Bild: Kette (media/textures/MultiTow_LinkChain.png) oder Stange
 * (media/textures/MultiTow_LinkBar.png). Das Bild wird zwischen den Kupplungspunkten gedreht und Stueck fuer Stueck
 * wiederholt (eine lockere Kette haengt dabei durch). Darunter liegt ein schwacher Schatten auf dem Boden.
 * Hinweis: Das Bild liegt ueber den Fahrzeugen (es wird nicht von ihnen verdeckt).
 *
 * <pre>
 *   Bild (128 x 32, also 4:1), wird entlang der Verbindung wiederholt:
 *
 *   A |&lt;-- repeat --&gt;|&lt;-- repeat --&gt;|&lt;-- Rest --&gt;| B
 *     [ oOoOoOoOoOo ][ oOoOoOoOoOo ][ oOoOoO    ]
 *
 *   Bei Durchhang wird jede Bildlaenge in k Stuecke geteilt (mind. ca. 6 Stuecke insgesamt),
 *   damit die Kette einen runden Bogen bildet statt eines Knicks.
 * </pre>
 */
public final class TextureLinkStyle implements LinkStyle {
    private static final String CHAIN_TEX = "media/textures/MultiTow_LinkChain.png";
    private static final String BAR_TEX = "media/textures/MultiTow_LinkBar.png";
    /** Breite in Metern und Laenge, die ein Bild abdeckt (Bild ist 4:1). */
    private static final float CHAIN_WIDTH = 0.14F, CHAIN_REPEAT = 0.56F;
    private static final float BAR_WIDTH = 0.11F, BAR_REPEAT = 0.44F;

    // ---- Zustand ----
    private Texture chain, bar;
    private boolean loaded;   // nur EINMAL laden versuchen

    private final float[] p0 = new float[3];   // Hilfsspeicher fuer pointAt (Anfang eines Stuecks)
    private final float[] p1 = new float[3];   // ... und Ende

    /** Bilder beim ersten Gebrauch laden (nicht schon beim Spielstart - da sind sie evtl. noch nicht da). */
    private void load() {
        if (loaded) {
            return;
        }
        loaded = true;
        try {
            chain = Texture.getSharedTexture(CHAIN_TEX);
            bar = Texture.getSharedTexture(BAR_TEX);
        } catch (Throwable t) {
            System.out.println("[MultiTowCore] link textures not loaded: " + t);
        }
    }

    @Override
    public boolean isAvailable() {
        load();
        return chain != null && bar != null;
    }

    // Welt -> Bildschirm.  fixJigglyModels: dieselbe kleine Korrektur, die das Spiel fuer Fahrzeugmodelle nutzt,
    // sonst "zittert" das Bild beim Fahren gegen das Fahrzeug.
    private static float sx(float x, float y, float z, PlayerCamera cam) {
        return IsoUtils.XToScreenExact(x, y, z, 0) + cam.fixJigglyModelsX * cam.zoom;
    }

    private static float sy(float x, float y, float z, PlayerCamera cam) {
        return IsoUtils.YToScreenExact(x, y, z, 0) + cam.fixJigglyModelsY * cam.zoom;
    }

    @Override
    public void draw(LinkGeometry g, float light) {
        Texture tex = g.bar ? bar : chain;
        if (tex == null) {
            return;
        }
        PlayerCamera cam = IsoCamera.cameras[IsoCamera.frameState.playerIndex];
        // Trick: Punkt A und Punkt "A + 1 Meter" umrechnen -> Abstand auf dem Bildschirm = Pixel pro Meter (ppm)
        // Pixel pro Meter an dieser Stelle (beide Bodenachsen sind in der Iso-Ansicht gleich lang)
        float ox = sx(g.ax, g.ay, g.az, cam), oy = sy(g.ax, g.ay, g.az, cam);
        float ux = sx(g.ax + 1.0F, g.ay, g.az, cam) - ox, uy = sy(g.ax + 1.0F, g.ay, g.az, cam) - oy;
        float ppm = (float) Math.sqrt(ux * ux + uy * uy);
        float half = (g.bar ? BAR_WIDTH : CHAIN_WIDTH) * ppm * 0.5F;   // halbe Breite in Pixeln
        float repeat = g.bar ? BAR_REPEAT : CHAIN_REPEAT;

        // Schatten auf dem Boden (gerade, ohne Durchhang)
        quad(null, sx(g.ax, g.ay, g.groundZ, cam), sy(g.ax, g.ay, g.groundZ, cam),
            sx(g.bx, g.by, g.groundZ, cam), sy(g.bx, g.by, g.groundZ, cam), half * 0.6F, 0, 0, 0, 0.3F, 0, 1);

        // Kette/Stange in Stuecken. Jedes Stueck liegt ganz innerhalb einer Bildlaenge, so passt das Muster nahtlos.
        // Bei Durchhang wird jede Bildlaenge in k kleinere Stuecke geteilt, damit der Bogen rund aussieht.
        if (g.length < 0.01F) {
            return;
        }
        int k = g.sag > 0.0F ? Math.max(1, (int) Math.ceil(6.0 / (g.length / repeat))) : 1;
        float piece = repeat / k;
        int pieces = Math.min(64, (int) Math.ceil(g.length / piece));   // hoechstens 64 Stuecke (Rechenzeit)
        float c = Math.max(0.3F, Math.min(1.0F, light));   // Helligkeit 0.3 .. 1.0
        for (int i = 0; i < pieces; i++) {
            float d0 = i * piece;
            float d1 = Math.min(g.length, d0 + piece);
            g.pointAt(d0 / g.length, p0);
            g.pointAt(d1 / g.length, p1);
            // u0/u1 = welcher Teil des Bildes (0 = linker Rand, 1 = rechter Rand) auf dieses Stueck kommt
            float u0 = (float) (i % k) / k;
            float u1 = u0 + (d1 - d0) / repeat;
            quad(tex, sx(p0[0], p0[1], p0[2], cam), sy(p0[0], p0[1], p0[2], cam),
                sx(p1[0], p1[1], p1[2], cam), sy(p1[0], p1[1], p1[2], cam), half, c, c, c, 1.0F, u0, u1);
        }
    }

    /** Ein Rechteck der halben Breite "half" zwischen zwei Bildschirmpunkten. tex == null = einfarbig. */
    private static void quad(Texture tex, float x0, float y0, float x1, float y1, float half,
                             float r, float g, float b, float a, float u0, float u1) {
        float dx = x1 - x0, dy = y1 - y0;
        float len = (float) Math.sqrt(dx * dx + dy * dy);
        if (len < 0.5F) {   // kuerzer als ein halber Pixel -> lohnt nicht
            return;
        }
        // (nx, ny) = Richtung QUER zur Linie, halbe Breite lang.  Die 4 Ecken:
        //
        //   (x0-n) +------------------------+ (x1-n)
        //          |  x0 --------------> x1 |
        //   (x0+n) +------------------------+ (x1+n)
        float nx = -dy / len * half, ny = dx / len * half;
        if (tex == null) {
            SpriteRenderer.instance.renderPoly(x0 - nx, y0 - ny, x1 - nx, y1 - ny, x1 + nx, y1 + ny, x0 + nx, y0 + ny, r, g, b, a);
            return;
        }
        float xs = tex.getXStart(), xe = tex.getXEnd(), ys = tex.getYStart(), ye = tex.getYEnd();   // Bild kann in einem groesseren Sammelbild liegen
        float ua = xs + (xe - xs) * u0, ub = xs + (xe - xs) * u1;
        SpriteRenderer.instance.renderPoly(tex, x0 - nx, y0 - ny, x1 - nx, y1 - ny, x1 + nx, y1 + ny, x0 + nx, y0 + ny,
            r, g, b, a, ua, ys, ub, ys, ub, ye, ua, ye);
    }
}
