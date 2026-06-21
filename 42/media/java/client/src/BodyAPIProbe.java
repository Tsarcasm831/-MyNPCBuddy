package com.lordtsarcasm.mynpcbuddy;

import me.zed_0xff.zombie_buddy.Exposer;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

/**
 * Safe reflection-only probes — never instantiates any class, never adds
 * anything to the world, never modifies save data.
 * Returns results as a newline-joined String so Lua can print them into the
 * MyNPCBuddy Console.
 */
@Exposer.LuaClass
public class BodyAPIProbe {

    // ── helpers ────────────────────────────────────────────────────────────────

    private static final String[] LMOVER_METHODS = {
        "new", "update", "render", "playAnim",
        "addToWorld", "removeFromWorld", "Despawn",
        "setX", "setY", "setZ", "getX", "getY", "getZ"
    };

    private static final String[] SURVIVOR_FACTORY_METHODS = {
        "CreateSurvivor", "InstansiateInCell", "InstantiateInCell"
    };

    private static final String[] ISO_SURVIVOR_METHODS = {
        "Despawn", "update", "pathTo", "addToWorld", "removeFromWorld"
    };

    private static final String[] PATHFIND_METHODS = {
        "pathToLocation", "pathToLocationF", "pathToCharacter", "moveToPoint", "update"
    };

    /** Log class existence, its constructors, and a filtered method list. */
    private static List<String> probeClass(String className, String[] methodFilter) {
        List<String> lines = new ArrayList<>();
        try {
            Class<?> cls = Class.forName(className);
            lines.add("FOUND: " + className);

            // Constructors
            Constructor<?>[] ctors = cls.getDeclaredConstructors();
            lines.add("  Constructors (" + ctors.length + "):");
            for (Constructor<?> c : ctors) {
                lines.add("    " + c.toString());
            }

            // All declared methods, filtered by name list
            Method[] methods = cls.getDeclaredMethods();
            lines.add("  Methods (filtered):");
            for (Method m : methods) {
                if (methodFilter == null) {
                    lines.add("    " + m.toString());
                } else {
                    for (String want : methodFilter) {
                        if (m.getName().equals(want)) {
                            lines.add("    " + m.toString());
                            break;
                        }
                    }
                }
            }

        } catch (ClassNotFoundException e) {
            lines.add("NOT FOUND: " + className);
        } catch (Exception e) {
            lines.add("ERROR probing " + className + ": " + e.getMessage());
        }
        return lines;
    }

    private static String join(List<String> lines) {
        StringBuilder sb = new StringBuilder();
        for (String l : lines) {
            if (sb.length() > 0) sb.append("\n");
            sb.append(l);
        }
        return sb.toString();
    }

    // ── public probe methods (called from Lua) ─────────────────────────────────

    public static String probeIsoLuaMover() {
        try {
            List<String> out = new ArrayList<>();
            out.add("=== Probe: IsoLuaMover ===");
            out.addAll(probeClass("zombie.iso.IsoLuaMover", LMOVER_METHODS));
            String result = join(out);
            System.out.println("[ZB-Probe] " + result.replace("\n", "\n[ZB-Probe] "));
            return result;
        } catch (Exception e) {
            return "probeIsoLuaMover EXCEPTION: " + e.getMessage();
        }
    }

    public static String probeSurvivorFactory() {
        try {
            List<String> out = new ArrayList<>();
            out.add("=== Probe: SurvivorFactory ===");
            out.addAll(probeClass("zombie.characters.SurvivorFactory", SURVIVOR_FACTORY_METHODS));
            String result = join(out);
            System.out.println("[ZB-Probe] " + result.replace("\n", "\n[ZB-Probe] "));
            return result;
        } catch (Exception e) {
            return "probeSurvivorFactory EXCEPTION: " + e.getMessage();
        }
    }

    public static String probeIsoSurvivor() {
        try {
            List<String> out = new ArrayList<>();
            out.add("=== Probe: IsoSurvivor ===");
            out.addAll(probeClass("zombie.characters.IsoSurvivor", ISO_SURVIVOR_METHODS));
            String result = join(out);
            System.out.println("[ZB-Probe] " + result.replace("\n", "\n[ZB-Probe] "));
            return result;
        } catch (Exception e) {
            return "probeIsoSurvivor EXCEPTION: " + e.getMessage();
        }
    }

    public static String probePathFindBehavior2() {
        try {
            List<String> out = new ArrayList<>();
            out.add("=== Probe: PathFindBehavior2 ===");
            out.addAll(probeClass("zombie.pathfind.PathFindBehavior2", PATHFIND_METHODS));
            String result = join(out);
            System.out.println("[ZB-Probe] " + result.replace("\n", "\n[ZB-Probe] "));
            return result;
        } catch (Exception e) {
            return "probePathFindBehavior2 EXCEPTION: " + e.getMessage();
        }
    }

    public static String probeAdjacentFreeTileFinder() {
        try {
            List<String> out = new ArrayList<>();
            out.add("=== Probe: AdjacentFreeTileFinder ===");
            out.addAll(probeClass("zombie.iso.AdjacentFreeTileFinder", null));
            out.add("=== Probe: AdjacentFreeTileFinderFull ===");
            out.addAll(probeClass("zombie.iso.AdjacentFreeTileFinderFull", null));
            String result = join(out);
            System.out.println("[ZB-Probe] " + result.replace("\n", "\n[ZB-Probe] "));
            return result;
        } catch (Exception e) {
            return "probeAdjacentFreeTileFinder EXCEPTION: " + e.getMessage();
        }
    }
}
