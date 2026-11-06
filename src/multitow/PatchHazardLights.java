package multitow;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.vehicles.BaseVehicle;

/**
 * Warnblinker der gezogenen Fahrzeuge (siehe Hazard):
 *  - vorher: Bremslicht-Schalter des Fahrzeugs im Takt setzen, damit das Spiel die Lichter selbst einschaltet
 *    (und alles, was auf diesen Schalter achtet, das Fahrzeug neu zeichnet)
 *  - nachher: die Lichter im Fahrzeugbild zusaetzlich direkt setzen (auch ohne eigene Batterie im gezogenen Fahrzeug)
 *
 * <pre>
 *  updateLights()   --&gt;  [enter]  Hazard.beforeUpdateLights   (Schalter setzen)
 *                         [Spiel]  Lichter berechnen
 *                         [exit ]  Hazard.afterUpdateLights    (Lichter ueberschreiben)
 * </pre>
 */
@Patch(className = "zombie.vehicles.BaseVehicle", methodName = "updateLights", warmUp = true)
public class PatchHazardLights {
    @Patch.OnEnter
    public static void enter(@Patch.This BaseVehicle self) {
        Hazard.beforeUpdateLights(self);
    }

    @Patch.OnExit
    public static void exit(@Patch.This BaseVehicle self) {
        Hazard.afterUpdateLights(self);
    }
}
