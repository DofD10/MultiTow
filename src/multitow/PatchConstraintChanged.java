package multitow;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.vehicles.BaseVehicle;

/**
 * [MP] Multiplayer-Server: nach jeder Aenderung einer Verbindung die Zustaendigkeit fuer die ganze Kette angleichen.
 * Ausgeloest bei: ankuppeln, abkuppeln, reissen.
 */
@Patch(className = "zombie.vehicles.BaseVehicle", methodName = "constraintChanged", warmUp = true)
public class PatchConstraintChanged {
    @Patch.OnExit
    public static void exit(@Patch.This BaseVehicle self) {
        ChainTow.syncChainAuthority(self);
    }
}
