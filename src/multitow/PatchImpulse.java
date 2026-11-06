package multitow;

import me.zed_0xff.zombie_buddy.Patch;

/**
 * Bullet meldet die Kraft auf eine Fahrzeug-Verbindung.
 * - merkt sich, wann das Spiel eine Verbindung wegen Ueberlastung loest (Kette gerissen)
 * - liefert die Belastung fuer die optionale Band-Anzeige (LinkVisual)
 *
 * Bullet = die Physik-Bibliothek des Spiels (laeuft in C++, meldet sich hier bei Java).
 * Argumente: (1) Fahrzeug-ID A, (2) Fahrzeug-ID B, (3) Kraft in diesem Physik-Schritt.
 */
@Patch(className = "zombie.core.physics.Bullet", methodName = "onVehicleConstraintImpulse", warmUp = true)
public class PatchImpulse {
    @Patch.OnEnter
    public static void enter(@Patch.Argument(1) int vidA, @Patch.Argument(2) int vidB, @Patch.Argument(3) float impulse) {
        ChainTow.markImpulse(impulse);          // -> Reiss-Erkennung
        LinkVisual.onImpulse(vidA, vidB, impulse);  // -> Belastungsanzeige / Verschleiss
    }
}
