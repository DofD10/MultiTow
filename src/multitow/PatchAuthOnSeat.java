package multitow;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.vehicles.BaseVehicle;

/**
 * [MP] Multiplayer-Server: Fahrer steigt ein/aus - Zustaendigkeit fuer die ganze Kette angleichen.
 *
 * <pre>
 *  Spieler setzt sich ans Steuer von [K]
 *    vorher:  [K]=Spieler  [2]=Spieler  [3]=Server  [4]=Server     &lt;- ruckelt
 *    nachher: [K]=Spieler  [2]=Spieler  [3]=Spieler [4]=Spieler    &lt;- syncChainAuthority
 * </pre>
 */
@Patch(className = "zombie.vehicles.BaseVehicle", methodName = "authorizationServerOnSeat", warmUp = true)
public class PatchAuthOnSeat {
    @Patch.OnExit
    public static void exit(@Patch.This BaseVehicle self) {
        ChainTow.syncChainAuthority(self);
    }
}
