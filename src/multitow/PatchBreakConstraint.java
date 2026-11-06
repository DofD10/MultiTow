package multitow;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.vehicles.BaseVehicle;

/**
 * <b>Abkuppeln</b> - das Spiel will die Verbindung eines Fahrzeugs loesen.
 * <ul>
 *   <li>Das Spiel kennt nur EINE Verbindung pro Fahrzeug und wuerde einfach "die" loesen.</li>
 *   <li>Wir entscheiden in {@code ChainTow.breakConstraint}, WELCHE der (bis zu zwei) Verbindungen gemeint ist.</li>
 *   <li>Rueckgabe true = wir haben es erledigt, Spiel-Methode wird uebersprungen.</li>
 * </ul>
 * Argumente: forgetID = Merker fuer Wiederverbinden nach dem Laden loeschen?  remote = kam vom Netzwerk?
 */
@Patch(className = "zombie.vehicles.BaseVehicle", methodName = "breakConstraint", warmUp = true)
public class PatchBreakConstraint {
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(@Patch.This BaseVehicle self,
                                @Patch.Argument(0) boolean forgetID,
                                @Patch.Argument(1) boolean remote) {
        return ChainTow.breakConstraint(self, forgetID, remote);
    }
}
