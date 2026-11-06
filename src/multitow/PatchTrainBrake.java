package multitow;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.physics.CarController;

/**
 * Zugbremse: nach der Steuerung eines gezogenen Fahrzeugs dessen Bremskraft an das Zugfahrzeug anpassen.
 * <p>
 * Ohne das schieben die gezogenen Fahrzeuge beim Bremsen das Zugfahrzeug an
 * (Einstellung "Zugbremse" in Prozent, 0 = aus).
 * <p>
 * Ab 0.15.0 im selben Haken: Mithelfen. Ein gezogenes Fahrzeug mit laufendem Motor faehrt mit, wenn das
 * Zugfahrzeug Gas gibt (Einstellung in Prozent der eigenen Motorkraft, siehe ChainTow.assistEngine).
 */
@Patch(className = "zombie.core.physics.CarController", methodName = "updateTrailer", warmUp = true)
public class PatchTrainBrake {
    @Patch.OnExit
    public static void exit(@Patch.This CarController self) {
        ChainTow.trainBrake(self);
        ChainTow.assistEngine(self);
    }
}
