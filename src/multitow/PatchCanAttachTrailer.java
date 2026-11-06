package multitow;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.vehicles.BaseVehicle;

/**
 * Pruefung "kann angekuppelt werden" kettenfaehig machen (wichtig fuers Wiederverbinden nach dem Laden).
 *
 * <pre>
 *  enter:  Kupplungen des Fahrzeugs kurz so umstellen, dass die Spiel-Pruefung "frei" sieht
 *  (Spiel prueft)
 *  exit:   alles wieder zuruecksetzen
 * </pre>
 * !! ACHTUNG: enter und exit gehoeren zusammen - wer eins aendert, muss das andere pruefen.
 */
@Patch(className = "zombie.vehicles.BaseVehicle", methodName = "canAttachTrailer", warmUp = true)
public class PatchCanAttachTrailer {
    @Patch.OnEnter
    public static void enter(@Patch.This BaseVehicle self, @Patch.AllArguments Object[] args) {
        ChainTow.canAttachEnter(self, args);
    }

    @Patch.OnExit
    public static void exit(@Patch.This BaseVehicle self) {
        ChainTow.canAttachExit(self);
    }
}
