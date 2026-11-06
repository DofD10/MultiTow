package multitow;

import me.zed_0xff.zombie_buddy.Patch;

/**
 * [MP] Multiplayer-Client: Positionen der Kettenglieder ab dem 3. Fahrzeug bei anderen Spielern mitbewegen.
 * <p>
 * Laeuft nach jedem {@code VehicleManager.clientUpdate} (also staendig). Das Spiel selbst
 * bewegt nur das erste gezogene Fahrzeug mit - Glied 3+ wuerde sonst "hinterherspringen".
 */
@Patch(className = "zombie.vehicles.VehicleManager", methodName = "clientUpdate", warmUp = true)
public class PatchClientUpdate {
    @Patch.OnExit
    public static void exit() {
        ChainTow.clientUpdateChains();
    }
}
