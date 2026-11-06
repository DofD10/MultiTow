package multitow;

import me.zed_0xff.zombie_buddy.Patch;

/**
 * Nach dem Zeichnen der Debug-Linien (jedes Bild, waehrend die Welt gezeichnet wird) die Verbindungs-Baender zeichnen.
 * <p>
 * >> WARUM ausgerechnet LineDrawer.render: das ist ein Zeitpunkt, an dem die 3D-Welt gerade
 *    gezeichnet wird - Kette/Stange erscheinen so IN der Welt statt ueber der Oberflaeche.
 */
@Patch(className = "zombie.debug.LineDrawer", methodName = "render", warmUp = true)
public class PatchLinkRender {
    @Patch.OnExit
    public static void exit() {
        LinkVisual.render();
    }
}
