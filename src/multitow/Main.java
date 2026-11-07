package multitow;

import zombie.Lua.LuaManager;

/*
 * ==========================================================================
 *  Main.java                                         [ Java-Teil, Start ]
 * --------------------------------------------------------------------------
 *  WAS?   Einstiegspunkt. ZombieBuddy ruft main() EINMAL auf, sobald es
 *         MultiTowCore.jar geladen hat (mod.info: javaJarFile / javaPkgName).
 *  WARUM? Nur eine Zeile in console.txt - so sieht man sofort, ob der
 *         Java-Teil ueberhaupt geladen wurde und welche Version es ist.
 *
 *  Beispiel in console.txt:
 *    [MultiTowCore] Version 0.15.0 loaded. Chain coupling active: true
 *
 *  Die eigentliche Arbeit machen die Patch*-Klassen: ZombieBuddy findet sie
 *  ueber die Anmerkung @Patch und haengt sie in die Spiel-Methoden ein.
 * ==========================================================================
 */
/** Wird von ZombieBuddy beim Laden der Mod einmal aufgerufen. */
public class Main {
    public static void main(String[] args) {
        System.out.println("[MultiTowCore] Version " + ChainTow.VERSION + " loaded. Chain coupling active: " + ChainTow.isActive());
        registerLuaFunctionsNow();
    }

    /**
     * Unsere Lua-Funktionen (multiTowCoreVersion, multiTowConfigure ... aus {@link LuaApi}) sofort anmelden,
     * wenn Lua schon laeuft.
     *
     * <h3>Warum?</h3>
     * ZombieBuddy meldet die Funktionen nur an, wenn das Spiel Lua neu aufsetzt (LuaManager.Exposer.exposeAll).
     * Normal laedt das Spiel die Mods VORHER - dann klappt das. Bei manchen Spielern ist die Mod-Liste beim
     * Start aber leer und die Mods kommen erst danach (im Hauptmenue) dazu:
     * <pre>
     *   [ZB] ZomboidFileSystem.loadMods(0 mods)      &lt;- Start ohne Mods
     *   [ZB] Exposing class to Lua: ZombieBuddy       &lt;- Lua wird aufgesetzt (MultiTow noch unbekannt)
     *   [ZB] ZomboidFileSystem.loadMods(21 mods)     &lt;- jetzt erst MultiTowCore.jar
     *   [MultiTowCore] Version 0.16.0 loaded          &lt;- Java laeuft ...
     *   Lua: "Java part not loaded - basic mode"      &lt;- ... aber Lua kennt die Funktionen nicht
     * </pre>
     * Darum holen wir das Anmelden hier selbst nach. Doppelt anmelden (spaeter noch einmal durch ZombieBuddy)
     * schadet nicht - die Funktion wird nur ueberschrieben. Ist Lua noch nicht bereit (der normale Fall beim
     * Spielstart), passiert hier nichts und ZombieBuddy macht es wie bisher.
     */
    static void registerLuaFunctionsNow() {
        try {
            if (LuaManager.env == null || LuaManager.exposer == null) {
                return;   // Lua noch nicht aufgesetzt -> ZombieBuddy meldet sie gleich selbst an
            }
            LuaManager.exposer.exposeGlobalFunctions(new LuaApi());
            System.out.println("[MultiTowCore] Lua functions registered right away (Lua was already running when the JAR was loaded)");
        } catch (Throwable t) {
            System.out.println("[MultiTowCore] could not register the Lua functions right away (" + t + ") - they come after a game restart");
        }
    }
}
