package multitow;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.physics.CarController;

/**
 * Mehr Motorkraft fuer das Zugfahrzeug bei mehreren gezogenen Fahrzeugen.
 * <p>
 * Haengt sich hinter {@code CarController.checkTire} - dort hat das Spiel die Motorkraft
 * fuer dieses Bild gerade ausgerechnet; {@code ChainTow.boostEngine} erhoeht sie dann
 * (Einstellung "Zusatzkraft": aus / fester Faktor / automatisch nach Anzahl der Fahrzeuge).
 * Dort sitzt auch das Tempolimit fuer Zuege (Gas weg ueber dem Limit).
 * Wirkt erst ab 2 gezogenen Fahrzeugen, also Zuegen mit 3+ Fahrzeugen.
 * <p>
 * !! ACHTUNG: laeuft in jedem Physik-Schritt - muss sehr schnell sein.
 */
@Patch(className = "zombie.core.physics.CarController", methodName = "checkTire", warmUp = true)
public class PatchEngineBoost {
    @Patch.OnExit
    public static void exit(@Patch.This CarController self, @Patch.Argument(0) Object vars) {
        ChainTow.boostEngine(self.vehicleObject, vars);
    }
}
