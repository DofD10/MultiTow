package multitow;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.vehicles.BaseVehicle;

/**
 * Merkt sich, wann das Spiel eine Verbindung loest, weil ein Fahrzeug kippt.
 * <p>
 * Bedingung: Fahrzeug hat eine Verbindung UND steht schraeg (Aufrecht-Wert unter 0.8).
 * !! ACHTUNG: Das zaehlt danach genau wie "Kette gerissen" (gleicher Zeitstempel lastImpulseNs):
 *    Geraeusch SNAP, Gegenstand faellt kaputt bzw. als Einzelteile auf den Boden.
 */
@Patch(className = "zombie.vehicles.BaseVehicle", methodName = "checkTrailerVerticalAlignment", warmUp = true)
public class PatchTipping {
    @Patch.OnEnter
    public static void enter(@Patch.This BaseVehicle self) {
        ChainTow.markTipping(self);
    }
}
