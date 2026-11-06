package multitow;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.vehicles.BaseVehicle;

/**
 * <b>Ankuppeln</b> - Gilt fuer beide Varianten von addPointConstraint (mit und ohne "remote").
 *
 * <pre>
 *  Spiel will A an B kuppeln
 *        |
 *        v
 *  ChainTow.addPointConstraint(self, args)
 *        |-- true  -> wir haben selbst gekuppelt (Kette!), Spiel-Methode wird uebersprungen
 *        '-- false -> normales Spiel-Verhalten
 * </pre>
 *
 *  So liest man einen Patch (gilt fuer alle Patch*-Dateien):
 *    @Patch(className, methodName)  -> in welche Spiel-Methode wir uns einhaengen
 *    @Patch.OnEnter                 -> laeuft VOR der Spiel-Methode
 *    @Patch.OnEnter(skipOn = true)  -> gibt sie true zurueck, wird die Spiel-Methode UEBERSPRUNGEN
 *    @Patch.OnExit                  -> laeuft NACH der Spiel-Methode
 *    @Patch.This                    -> das Objekt, auf dem die Methode laeuft ("self")
 *    @Patch.Argument(n)             -> das n-te Argument der Spiel-Methode (ab 0)
 *    warmUp = true                  -> Patch schon beim Laden vorbereiten, nicht erst beim ersten Aufruf
 *
 * >> WARUM AllArguments: die beiden Varianten haben unterschiedlich viele Argumente,
 *    so faengt EIN Patch beide ab.
 */
@Patch(className = "zombie.vehicles.BaseVehicle", methodName = "addPointConstraint", warmUp = true)
public class PatchAddPointConstraint {
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(@Patch.This BaseVehicle self, @Patch.AllArguments Object[] args) {
        return ChainTow.addPointConstraint(self, args);
    }
}
