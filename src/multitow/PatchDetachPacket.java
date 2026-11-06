package multitow;

import me.zed_0xff.zombie_buddy.Patch;

/**
 * [MP] Multiplayer-Client: Abkuppel-Paket vom Server kettenfaehig verarbeiten (nur die eine Verbindung loesen).
 *
 * <pre>
 *  Server: "trenne 2 von 3"
 *    Spiel allein:  loest ALLE Verbindungen von 2  ->  [K]-[2]  [3]  und  [K] [2]  (falsch)
 *    mit Patch:     loest nur 2-3                  ->  [K]-[2]  [3]               (richtig)
 * </pre>
 * Typ "Object", weil die Paket-Klasse zur Compile-Zeit nicht sichtbar sein muss.
 */
@Patch(className = "zombie.network.packets.vehicle.VehicleTowingDetachPacket", methodName = "processClient", warmUp = true)
public class PatchDetachPacket {
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(@Patch.This Object self) {
        return ChainTow.clientDetachPacket(self);
    }
}
