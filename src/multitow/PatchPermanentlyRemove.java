package multitow;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.vehicles.BaseVehicle;

/**
 * Fahrzeug wird endgueltig geloescht (z.B. Admin entfernt es, Fahrzeug verschrottet):
 * ALLE Verbindungen vorher trennen.
 * <p>
 * {@code breakAll(self, true)}: true = auch die Merker fuers Wiederverbinden nach dem Laden loeschen,
 * denn dieses Fahrzeug kommt nie wieder.
 */
@Patch(className = "zombie.vehicles.BaseVehicle", methodName = "permanentlyRemove", warmUp = true)
public class PatchPermanentlyRemove {
    @Patch.OnEnter
    public static void enter(@Patch.This BaseVehicle self) {
        ChainTow.breakAll(self, true);
    }
}
