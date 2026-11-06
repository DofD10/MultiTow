package multitow;

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
    }
}
