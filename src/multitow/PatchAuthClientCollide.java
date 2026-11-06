package multitow;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.vehicles.BaseVehicle;

/**
 * [MP] Multiplayer-Client: Kollision mit einer Kette - alle Glieder lokal rechnen, nicht nur ein Nachbarfahrzeug.
 * <p>
 * Hintergrund: Im MP rechnet immer EIN Spieler die Physik eines Fahrzeugs ("Zustaendigkeit").
 * Das Spiel kennt nur Paare (Zugfahrzeug + 1 Anhaenger). Wir geben die Zustaendigkeit
 * an die ganze Kette weiter, sonst ruckeln Glied 3, 4, ...
 */
@Patch(className = "zombie.vehicles.BaseVehicle", methodName = "authorizationClientCollide", warmUp = true)
public class PatchAuthClientCollide {
    @Patch.OnExit
    public static void exit(@Patch.This BaseVehicle self, @Patch.Argument(0) Object driver) {
        ChainTow.clientCollideChain(self, driver);
    }
}
