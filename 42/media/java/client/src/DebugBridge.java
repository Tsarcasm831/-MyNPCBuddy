package com.lordtsarcasm.mynpcbuddy;

import me.zed_0xff.zombie_buddy.Exposer;
import zombie.core.logger.ExceptionLogger;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import java.util.ArrayList;

/**
 * Static bridge called from Lua to run Java-side debug helpers.
 * Phase 3: player position probe + zombie scanning — no AI, no spawning, no save writes.
 */
@Exposer.LuaClass
public class DebugBridge {

    public static void printPlayerPosition() {
        try {
            IsoPlayer player = IsoPlayer.players[0];
            if (player == null) {
                System.out.println("[MyNPCBuddy] no player found");
                return;
            }
            float x = player.getX();
            float y = player.getY();
            float z = player.getZ();
            System.out.println("[MyNPCBuddy] player position x=" + x + " y=" + y + " z=" + z);
        } catch (Exception e) {
            System.out.println("[MyNPCBuddy] printPlayerPosition error - " + e.getMessage());
            ExceptionLogger.logException(e);
        }
    }

    public static void scanAreaForZombies() {
        try {
            IsoPlayer player = IsoPlayer.players[0];
            if (player == null) {
                System.out.println("[MyNPCBuddy] no player found");
                return;
            }

            float playerX = player.getX();
            float playerY = player.getY();
            float playerZ = player.getZ();

            IsoGridSquare playerSquare = player.getCurrentSquare();
            if (playerSquare == null) {
                System.out.println("[MyNPCBuddy] player square not found");
                return;
            }

            IsoCell cell = playerSquare.getCell();
            if (cell == null) {
                System.out.println("[MyNPCBuddy] cell not found");
                return;
            }

            int radius = 10;
            int zombieCount = 0;
            IsoZombie closestZombie = null;
            float closestDistance = Float.MAX_VALUE;

            ArrayList zombies = cell.getZombieList();
            if (zombies == null) {
                System.out.println("[MyNPCBuddy] no zombies nearby");
                System.out.println("[MyNPCBuddy] player position x=" + playerX + " y=" + playerY + " z=" + playerZ);
                System.out.println("[MyNPCBuddy] zombie count within radius " + radius + " = 0");
                return;
            }

            for (Object obj : zombies) {
                if (!(obj instanceof IsoZombie)) continue;
                IsoZombie zombie = (IsoZombie) obj;
                if (zombie == null) continue;

                float zx = zombie.getX();
                float zy = zombie.getY();
                float zz = zombie.getZ();

                if ((int)zz != (int)playerZ) continue;

                float distance = (float) Math.sqrt(
                    Math.pow(zx - playerX, 2) + Math.pow(zy - playerY, 2)
                );

                if (distance <= radius) {
                    zombieCount++;
                    if (distance < closestDistance) {
                        closestDistance = distance;
                        closestZombie = zombie;
                    }
                }
            }

            System.out.println("[MyNPCBuddy] player position x=" + playerX + " y=" + playerY + " z=" + playerZ);
            System.out.println("[MyNPCBuddy] zombie count within radius " + radius + " = " + zombieCount);

            if (zombieCount == 0) {
                System.out.println("[MyNPCBuddy] no zombies nearby");
            } else if (closestZombie != null) {
                System.out.println("[MyNPCBuddy] closest zombie at x=" + closestZombie.getX()
                    + " y=" + closestZombie.getY()
                    + " z=" + closestZombie.getZ()
                    + " distance=" + String.format("%.2f", closestDistance));
            }
        } catch (Exception e) {
            System.out.println("[MyNPCBuddy] scanAreaForZombies error - " + e.getMessage());
            ExceptionLogger.logException(e);
        }
    }

    public static String brainTick() {
        try {
            IsoPlayer player = IsoPlayer.players[0];
            if (player == null) {
                return "BrainTick ERROR: no player";
            }

            float playerX = player.getX();
            float playerY = player.getY();
            float playerZ = player.getZ();

            IsoGridSquare playerSquare = player.getCurrentSquare();
            if (playerSquare == null) {
                return "BrainTick ERROR: no square";
            }

            IsoCell cell = playerSquare.getCell();
            if (cell == null) {
                return "BrainTick ERROR: no cell";
            }

            int radius = 10;
            int zombieCount = 0;
            float closestDistance = Float.MAX_VALUE;

            ArrayList zombies = cell.getZombieList();
            if (zombies != null) {
                for (Object obj : zombies) {
                    if (!(obj instanceof IsoZombie)) continue;
                    IsoZombie zombie = (IsoZombie) obj;
                    if (zombie == null) continue;

                    float zz = zombie.getZ();
                    if ((int)zz != (int)playerZ) continue;

                    float zx = zombie.getX();
                    float zy = zombie.getY();
                    float distance = (float) Math.sqrt(
                        Math.pow(zx - playerX, 2) + Math.pow(zy - playerY, 2)
                    );

                    if (distance <= radius) {
                        zombieCount++;
                        if (distance < closestDistance) {
                            closestDistance = distance;
                        }
                    }
                }
            }

            String closestStr = (zombieCount == 0) ? "none" : String.format("%.1f", closestDistance);
            return String.format("BrainTick player=(%.1f,%.1f,%.0f) zombies=%d closest=%s",
                playerX, playerY, playerZ, zombieCount, closestStr);
        } catch (Exception e) {
            return "BrainTick ERROR: " + e.getMessage();
        }
    }

    // ============ Companion Brain Bridge Methods ============

    public static String brainTickWithCompanion() {
        // Update companion state first (reads live player pos, scans zombies, updates vpos)
        CompanionBrain.luaUpdate();

        // Gather player position from companion brain (already updated above)
        String playerPos;
        try {
            IsoPlayer player = (IsoPlayer.players != null && IsoPlayer.players.length > 0)
                ? IsoPlayer.players[0] : null;
            if (player != null) {
                playerPos = String.format("(%.1f,%.1f,%.0f)",
                    player.getX(), player.getY(), player.getZ());
            } else {
                playerPos = "none";
            }
        } catch (Exception e) {
            playerPos = "err";
        }

        String virtPos;
        String distStr;
        if (CompanionBrain.luaHasVirtualPosition()) {
            virtPos = String.format("(%.1f,%.1f,%.0f)",
                CompanionBrain.luaGetCompanionX(),
                CompanionBrain.luaGetCompanionY(),
                CompanionBrain.luaGetCompanionZ());
            distStr = String.format("%.1f", CompanionBrain.luaDistToPlayer());
        } else {
            virtPos = "none";
            distStr = "n/a";
        }

        String order  = CompanionBrain.luaGetCurrentOrder();
        String danger = CompanionBrain.luaGetDangerState();
        String action = CompanionBrain.luaGetDesiredAction();

        CompanionBrain brain = CompanionBrain.getInstance();
        int zombieCount = brain.getNearbyZombieCount();
        String closestStr;
        if (zombieCount == 0) {
            closestStr = "none";
        } else {
            closestStr = String.format("%.1f", brain.getClosestZombieDistance());
        }

        return String.format(
            "BrainTick player=%s vpos=%s dist=%s order=%s danger=%s action=%s zombies=%d closest=%s",
            playerPos, virtPos, distStr, order, danger, action, zombieCount, closestStr);
    }

    public static boolean companionIsEnabled() {
        return CompanionBrain.luaIsEnabled();
    }

    public static void companionSetEnabled(boolean enabled) {
        CompanionBrain.luaSetEnabled(enabled);
    }

    public static String companionGetFullStatus() {
        return CompanionBrain.luaGetFullStatus();
    }

    public static String companionGetDesiredAction() {
        return CompanionBrain.luaGetDesiredAction();
    }

    public static void companionSetOrder(String order) {
        CompanionBrain.luaSetOrder(order);
    }

    public static void companionSetOrderWithInit(String order) {
        CompanionBrain.luaSetOrderWithInit(order);
    }

    public static String companionGetCurrentOrder() {
        return CompanionBrain.luaGetCurrentOrder();
    }

    public static String companionGetDangerState() {
        return CompanionBrain.luaGetDangerState();
    }

    public static void companionResetVirtualPos() {
        CompanionBrain.luaResetVirtualPosition();
    }

    public static boolean companionHasVirtualPos() {
        return CompanionBrain.luaHasVirtualPosition();
    }

    public static float companionGetVirtualX() { return CompanionBrain.luaGetCompanionX(); }
    public static float companionGetVirtualY() { return CompanionBrain.luaGetCompanionY(); }
    public static float companionGetVirtualZ() { return CompanionBrain.luaGetCompanionZ(); }

    public static float companionDistToPlayer() { return CompanionBrain.luaDistToPlayer(); }

    public static boolean companionHasScoutAnchor() { return CompanionBrain.luaHasScoutAnchor(); }
    public static float companionGetScoutAnchorX() { return CompanionBrain.luaGetScoutAnchorX(); }
    public static float companionGetScoutAnchorY() { return CompanionBrain.luaGetScoutAnchorY(); }
    public static float companionGetScoutAnchorZ() { return CompanionBrain.luaGetScoutAnchorZ(); }
}
