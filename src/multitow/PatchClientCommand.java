package multitow;

import me.zed_0xff.zombie_buddy.Patch;

/**
 * [MP] Multiplayer-Server: erkennt den Befehl "vehicle.detachTrailerSpontaneous" (beim Client ist eine Verbindung gerissen),
 * BEVOR das Spiel ihn ausfuehrt. So wissen wir beim folgenden Abkuppeln, dass die Kette gerissen ist.
 * Nur die Variante triggerEvent(name, a, b, c, d) wird gepatcht.
 *
 * <pre>
 *  Client: Kette reisst --&gt; sendet "vehicle / detachTrailerSpontaneous"
 *  Server: triggerEvent("OnClientCommand", "vehicle", "detachTrailerSpontaneous", player, args)
 *            ^-- hier lauschen wir mit (nur lesen, nichts aendern)
 *          --&gt; markSpontaneousServer()  --&gt; folgendes Abkuppeln = "gerissen" (Gegenstand faellt kaputt runter)
 * </pre>
 * >> WARUM strictMatch: triggerEvent gibt es mit vielen Argument-Anzahlen; wir wollen genau die mit 5.
 */
@Patch(className = "zombie.Lua.LuaEventManager", methodName = "triggerEvent", strictMatch = true)
public class PatchClientCommand {
    @Patch.OnEnter
    public static void enter(@Patch.Argument(0) String name, @Patch.Argument(1) Object module,
                             @Patch.Argument(2) Object command, @Patch.Argument(3) Object player,
                             @Patch.Argument(4) Object args) {
        if (zombie.network.GameServer.server && "OnClientCommand".equals(name)
            && "vehicle".equals(module) && "detachTrailerSpontaneous".equals(command)) {   // <- nur dieser eine Befehl
            ChainTow.markSpontaneousServer();
        }
    }
}
