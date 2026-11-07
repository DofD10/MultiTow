package multitow;

import me.zed_0xff.zombie_buddy.Patch;

/**
 * "Host"-Spiele: ZombieBuddy auch auf dem Hintergrund-Server starten (nur wenn die Debug-Option an ist).
 * Ersetzt die Rueckgabe von CoopMaster.getGarbageCollector() durch eine Argument-Datei - Erklaerung in {@link HostServerAgent}.
 */
@Patch(className = "zombie.network.CoopMaster", methodName = "getGarbageCollector")
public class PatchCoopServerAgent {
    // suppress = Throwable: geht hier trotzdem etwas schief, bleibt die Rueckgabe des Spiels unveraendert und
    // "Host" startet wie immer (statt mit einem Fehler abzubrechen).
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Return(readOnly = false) String ret) {
        ret = HostServerAgent.replaceGcArgument(ret);
    }
}
