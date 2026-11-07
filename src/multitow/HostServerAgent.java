package multitow;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.lang.management.ManagementFactory;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import zombie.ZomboidFileSystem;

/*
 * ==========================================================================
 *  HostServerAgent.java                       [ Java-Teil, TEST / Debug ]
 * --------------------------------------------------------------------------
 *  WAS?   ZombieBuddy auch auf dem Server von "Host"-Spielen starten
 *         (Debug-Option "Host games: start ZombieBuddy on the hosted server").
 *
 *  WARUM? Bei "Host" startet das Spiel im Hintergrund einen eigenen Server
 *         (zombie.network.CoopMaster.launchServer). Von den eigenen Start-
 *         optionen gibt es ihm NUR die Einstellung der Speicherverwaltung mit
 *         (getGarbageCollector) - die Startoption von ZombieBuddy nicht.
 *         Ohne ZombieBuddy hat der Server keinen Java-Teil -> keine Ketten.
 *
 *  WIE?   getGarbageCollector() liefert EINEN Eintrag fuer die Startzeile des
 *         Servers. Den ersetzen wir durch eine "Argument-Datei" (@Datei) - das
 *         versteht das java-Programm seit Java 9: jede Zeile der Datei zaehlt
 *         wie eine eigene Startoption. So kommen beide hinein:
 *
 *           Startzeile Server:  java ... @C:/Users/x/Zomboid/MultiTow_host_server_args.txt zombie.network.GameServer -coop ...
 *           Inhalt der Datei:   "-XX:+UseZGC"                                   (wie vorher, falls es eine gab)
 *                               "-agentpath:C:/.../zbNative.dll=policy=deny-new" (ZombieBuddy, wie beim Spiel selbst)
 *
 *  !! policy=deny-new: der Server hat keinen Bildschirm, er koennte nicht nachfragen. Er laedt nur JARs, die du
 *     im Spiel schon dauerhaft erlaubt hast (gleiche Datei .zombie_buddy/mod_approvals.json). policy=allow-all bleibt.
 *  !! Wirkt fuer ALLE Java-Mods des Spielers, nicht nur fuer Multi-Tow (ZombieBuddy laedt auf dem Server, was erlaubt ist).
 *  !! Standard: AUS. Nur wenn der Haken gesetzt ist (Lua: multiTowSetHostServerAgent).
 * ==========================================================================
 */
//  !! public (Klasse UND replaceGcArgument): ZombieBuddy kopiert den Patch-Code IN die Spielklasse CoopMaster
//     (Paket zombie.network). Von dort darf nur auf oeffentliche Klassen/Methoden zugegriffen werden - sonst
//     IllegalAccessError beim Klick auf "Host" (so passiert im ersten Test).
public final class HostServerAgent {
    private static volatile boolean enabled = false;
    private static final String ARGS_FILE = "MultiTow_host_server_args.txt";

    private HostServerAgent() {
    }

    static void setEnabled(boolean on) {
        if (on != enabled) {
            System.out.println("[MultiTowCore] Host games: start ZombieBuddy on the hosted server = " + on);
        }
        enabled = on;
    }

    static boolean isEnabled() {
        return enabled;
    }

    /** Aus der Patch-Klasse: Rueckgabe von CoopMaster.getGarbageCollector() ersetzen (oder unveraendert lassen). */
    public static String replaceGcArgument(String gc) {
        if (!enabledNow()) {
            return gc;
        }
        try {
            List<String> agents = zombieBuddyArguments(ManagementFactory.getRuntimeMXBean().getInputArguments(),
                System.getProperty("user.dir"), System.getProperty("java.library.path"));
            if (agents.isEmpty()) {
                System.out.println("[MultiTowCore] Host server: no ZombieBuddy start option found in this game's start options - the hosted server starts without it.");
                return gc;
            }
            List<String> lines = new ArrayList<>();
            if (gc != null && !gc.isEmpty()) {
                lines.add(gc);
            }
            lines.addAll(agents);
            File f = new File(ZomboidFileSystem.instance.getCacheDir(), ARGS_FILE);
            try (Writer w = new OutputStreamWriter(new FileOutputStream(f, false), StandardCharsets.UTF_8)) {
                for (String l : lines) {
                    w.write(quote(l));
                    w.write(System.lineSeparator());
                }
            }
            System.out.println("[MultiTowCore] Host server: ZombieBuddy start option passed to the hosted server " + agents
                + " (via " + f.getAbsolutePath() + ")");
            return "@" + f.getAbsolutePath();
        } catch (Throwable t) {
            System.out.println("[MultiTowCore] Host server: could not pass ZombieBuddy to the hosted server (" + t + ") - it starts as usual.");
            return gc;
        }
    }

    /**
     * Ist die Option JETZT an? Massgeblich ist die gespeicherte Einstellung (Zomboid/Lua/ModOptions.ini), nicht nur
     * der Wert, den Lua zuletzt geschickt hat.
     * >> WARUM: Das Spiel liest ModOptions.ini erst, wenn das Optionsmenue aufgebaut wird. Manche Mods (z. B. ein
     *    Optimierungs-Mod, der das Optionsmenue erst beim Oeffnen baut) verschieben das - dann meldet Lua beim Start
     *    "aus", obwohl der Haken gesetzt und gespeichert ist (so im Test passiert: erst true, nach dem Neuladen false).
     *    Beim Klick auf "Host" lesen wir deshalb die Datei selbst. Nicht lesbar -> der Wert von Lua.
     */
    static boolean enabledNow() {
        try {
            Boolean saved = readSavedOption(new File(new File(ZomboidFileSystem.instance.getCacheDir(), "Lua"), "ModOptions.ini"));
            return saved != null ? saved : enabled;
        } catch (Throwable t) {
            return enabled;
        }
    }

    /** Zeile "tickbox|MultiTowRoadTrain|debugHostServerJava|true" aus ModOptions.ini lesen (null = nicht gefunden). */
    static Boolean readSavedOption(File ini) {
        if (ini == null || !ini.isFile()) {
            return null;
        }
        try (BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(ini), StandardCharsets.UTF_8))) {
            String line;
            Boolean found = null;
            while ((line = r.readLine()) != null) {
                String[] t = line.trim().split("\\|");
                if (t.length >= 4 && "MultiTowRoadTrain".equals(t[1]) && "debugHostServerJava".equals(t[2])) {
                    found = "true".equalsIgnoreCase(t[3].trim());
                }
            }
            return found;
        } catch (Throwable t) {
            return null;
        }
    }

    /**
     * Die Startoptionen von ZombieBuddy aus den Startoptionen des Spiels heraussuchen und fuer den Server anpassen.
     * Nur die ERSTE wird uebernommen: steht ZombieBuddy doppelt in den Startoptionen (z. B. in ProjectZomboid64.json
     * UND in den Steam-Startoptionen), wuerde der Server sonst zweimal versuchen, ihn zu starten.
     * Eigene Methode ohne Spiel-Klassen, damit man sie ohne Spiel testen kann.
     */
    static List<String> zombieBuddyArguments(List<String> input, String userDir, String libraryPath) {
        List<String> out = new ArrayList<>();
        if (input == null) {
            return out;
        }
        for (String a : input) {
            if (a == null) {
                continue;
            }
            String low = a.toLowerCase();
            if (!out.isEmpty()) {
                break;   // nur die erste ZombieBuddy-Startoption
            }
            if (low.startsWith("-agentlib:zbnative")) {
                // "-agentlib:zbNative=opts" sucht die DLL ueber Suchpfade. Fuer den Server lieber den festen Pfad nehmen.
                String opts = a.indexOf('=') >= 0 ? a.substring(a.indexOf('=') + 1) : "";
                File lib = findNativeLibrary(userDir, libraryPath);
                String head = lib != null ? "-agentpath:" + slashes(lib.getAbsolutePath()) : a.substring(0, a.indexOf('=') >= 0 ? a.indexOf('=') : a.length());
                out.add(head + "=" + serverOptions(opts));
            } else if (low.startsWith("-agentpath:") && low.contains("zbnative")) {
                int eq = a.indexOf('=');
                String head = eq >= 0 ? a.substring(0, eq) : a;
                String opts = eq >= 0 ? a.substring(eq + 1) : "";
                out.add(slashes(head) + "=" + serverOptions(opts));
            } else if (low.startsWith("-javaagent:") && low.contains("zombiebuddy")) {
                int eq = a.indexOf('=');
                String jar = (eq >= 0 ? a.substring(0, eq) : a).substring("-javaagent:".length());
                File jf = new File(jar);
                if (!jf.isAbsolute() && userDir != null) {
                    jf = new File(userDir, jar);
                }
                String opts = eq >= 0 ? a.substring(eq + 1) : "";
                out.add("-javaagent:" + slashes(jf.getAbsolutePath()) + "=" + serverOptions(opts));
            }
        }
        return out;
    }

    /** Optionen fuer den Server: policy=prompt (oder keine) -> policy=deny-new, weil der Server nicht fragen kann. */
    static String serverOptions(String opts) {
        List<String> parts = new ArrayList<>();
        boolean hasPolicy = false;
        for (String p : (opts == null ? "" : opts).split(",")) {
            String t = p.trim();
            if (t.isEmpty()) {
                continue;
            }
            if (t.toLowerCase().startsWith("policy=")) {
                hasPolicy = true;
                String v = t.substring(7).trim().toLowerCase();
                parts.add(v.equals("allow-all") || v.equals("deny-new") ? "policy=" + v : "policy=deny-new");
            } else {
                parts.add(t);
            }
        }
        if (!hasPolicy) {
            parts.add("policy=deny-new");
        }
        return String.join(",", parts);
    }

    private static File findNativeLibrary(String userDir, String libraryPath) {
        String[] names = { "zbNative.dll", "libzbNative.so", "libzbNative.dylib" };
        List<String> dirs = new ArrayList<>();
        if (userDir != null) {
            dirs.add(userDir);
            dirs.add(userDir + File.separator + "jre64" + File.separator + "bin");
        }
        if (libraryPath != null) {
            for (String d : libraryPath.split(File.pathSeparator)) {
                if (!d.isEmpty()) {
                    dirs.add(d);
                }
            }
        }
        for (String d : dirs) {
            for (String n : names) {
                File f = new File(d, n);
                if (f.isFile()) {
                    return f;
                }
            }
        }
        return null;
    }

    private static String slashes(String s) {
        return s.replace('\\', '/');
    }

    /** Eine Zeile der Argument-Datei: in Anfuehrungszeichen, Backslash und " maskiert (Leerzeichen in Pfaden!). */
    static String quote(String s) {
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }
}
