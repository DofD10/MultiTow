package multitow;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.physics.CarController;

/**
 * Lenk-Automatik eines gezogenen Fahrzeugs: dafuer voruebergehend die vordere Kupplung einsetzen.
 *
 * <pre>
 *  Ein Fahrzeug in der Kettenmitte hat ZWEI Verbindungen:
 *        [1] ---- [2] ---- [3]
 *          vorne^      ^hinten
 *  Das Spiel kennt nur EIN Feld fuer "die" Verbindung (beim mittleren Fahrzeug steht dort die hintere).
 *  Zum Lenken braucht es aber die VORDERE -> kurz tauschen (enter) und zuruecktauschen (exit).
 * </pre>
 */
@Patch(className = "zombie.core.physics.CarController", methodName = "steerInDirectionOfTowing", warmUp = true)
public class PatchSteerTowing {
    @Patch.OnEnter
    public static void enter(@Patch.This CarController self) {
        ChainTow.swapToFront(self.vehicleObject);
    }

    @Patch.OnExit
    public static void exit(@Patch.This CarController self) {
        ChainTow.swapBack(self.vehicleObject);
    }
}
