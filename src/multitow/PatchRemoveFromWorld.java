package multitow;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.vehicles.BaseVehicle;

/**
 * Wird ein Fahrzeug entladen, muessen vorher alle seine Verbindungen weg (sonst haengen Bullet-Verbindungen im Leeren).
 * <p>
 * Unterschied zu {@link PatchPermanentlyRemove}: hier {@code false} - die Merker bleiben,
 * damit der Zug beim naechsten Laden des Gebiets wieder zusammengekuppelt wird.
 */
@Patch(className = "zombie.vehicles.BaseVehicle", methodName = "removeFromWorld", warmUp = true)
public class PatchRemoveFromWorld {
    @Patch.OnEnter
    public static void enter(@Patch.This BaseVehicle self) {
        ChainTow.breakAll(self, false);
    }
}
