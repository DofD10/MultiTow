package multitow;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.vehicles.BaseVehicle;

/**
 * [MP] Multiplayer-Server: Kollision - Zustaendigkeit fuer die ganze Kette angleichen.
 * (Gleiche Idee wie {@link PatchAuthOnSeat}, nur ausgeloest durch einen Zusammenstoss.)
 */
@Patch(className = "zombie.vehicles.BaseVehicle", methodName = "authorizationServerCollide", warmUp = true)
public class PatchAuthServerCollide {
    @Patch.OnExit
    public static void exit(@Patch.This BaseVehicle self) {
        ChainTow.syncChainAuthority(self);
    }
}
