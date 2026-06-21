package com.lordtsarcasm.mynpcbuddy;

import me.zed_0xff.zombie_buddy.Exposer;
import zombie.core.logger.ExceptionLogger;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import java.util.ArrayList;

/**
 * Virtual companion brain with no spawned entity.
 * Watches the world and decides what action the companion would take.
 */
@Exposer.LuaClass
public class CompanionBrain {

    // Internal state
    private boolean enabled = false;
    private String mode = "IDLE";
    private String currentOrder = "FOLLOW";
    private String dangerState = "SAFE";
    private float lastKnownPlayerX = 0.0f;
    private float lastKnownPlayerY = 0.0f;
    private float lastKnownPlayerZ = 0.0f;
    private int nearbyZombieCount = 0;
    private float closestZombieDistance = Float.MAX_VALUE;
    private String desiredAction = "WAIT_NO_PLAYER";

    // Virtual companion position
    private float companionX = 0.0f;
    private float companionY = 0.0f;
    private float companionZ = 0.0f;
    private boolean hasVirtualPosition = false;
    private float scoutAngle = 0.0f; // radians, for scout circle

    // Scout anchor (fixed when Order: Scout is activated)
    private float scoutAnchorX = 0.0f;
    private float scoutAnchorY = 0.0f;
    private float scoutAnchorZ = 0.0f;
    private boolean hasScoutAnchor = false;

    // Thresholds for decision making
    private static final float FLEE_DISTANCE = 3.0f;
    private static final float ALERT_DISTANCE = 10.0f;
    private static final int SCAN_RADIUS = 10;

    // Virtual movement constants
    private static final float MOVE_STEP = 0.5f;        // tiles per tick
    private static final float FOLLOW_STOP_DIST = 3.0f; // stop following if closer than this
    private static final float SCOUT_RADIUS = 4.0f;     // orbit radius around player
    private static final float SCOUT_ANGLE_STEP = 0.15f; // radians per tick (~8.6 deg)

    // Singleton instance
    private static CompanionBrain instance = null;

    public static CompanionBrain getInstance() {
        if (instance == null) {
            instance = new CompanionBrain();
        }
        return instance;
    }

    private CompanionBrain() {
        // Private constructor for singleton
    }

    public boolean isEnabled() {
        return enabled;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public String getMode() {
        return mode != null ? mode : "UNKNOWN";
    }

    public float getLastKnownPlayerX() {
        return lastKnownPlayerX;
    }

    public float getLastKnownPlayerY() {
        return lastKnownPlayerY;
    }

    public float getLastKnownPlayerZ() {
        return lastKnownPlayerZ;
    }

    public int getNearbyZombieCount() {
        return nearbyZombieCount;
    }

    public float getClosestZombieDistance() {
        return closestZombieDistance;
    }

    public String getDesiredAction() {
        return desiredAction != null ? desiredAction : "UNKNOWN";
    }

    public float getCompanionX() { return companionX; }
    public float getCompanionY() { return companionY; }
    public float getCompanionZ() { return companionZ; }
    public boolean hasVirtualPosition() { return hasVirtualPosition; }

    public float getScoutAnchorX() { return scoutAnchorX; }
    public float getScoutAnchorY() { return scoutAnchorY; }
    public float getScoutAnchorZ() { return scoutAnchorZ; }
    public boolean hasScoutAnchor() { return hasScoutAnchor; }

    public String getCurrentOrder() {
        return currentOrder != null ? currentOrder : "FOLLOW";
    }

    public void setCurrentOrder(String order) {
        if (order != null) {
            this.currentOrder = order;
        }
    }

    /**
     * Set order with side-effects: auto-init vpos for STAY/SCOUT, set scout anchor for SCOUT.
     * Called when the player clicks an order button.
     */
    public void setOrderWithInit(String order) {
        if (order == null) return;
        this.currentOrder = order;

        IsoPlayer player = null;
        if (IsoPlayer.players != null && IsoPlayer.players.length > 0) {
            player = IsoPlayer.players[0];
        }

        if ("STAY".equals(order)) {
            if (!hasVirtualPosition && player != null) {
                resetVirtualPosition(player);
            }
            String vposStr = hasVirtualPosition
                ? String.format("(%.1f,%.1f,%.0f)", companionX, companionY, companionZ)
                : "none";
            System.out.println("[MyNPCBuddy] Order set: STAY, holding vpos=" + vposStr);

        } else if ("SCOUT".equals(order)) {
            if (!hasVirtualPosition && player != null) {
                resetVirtualPosition(player);
            }
            // Anchor to current vpos if available, else player position
            if (hasVirtualPosition) {
                scoutAnchorX = companionX;
                scoutAnchorY = companionY;
                scoutAnchorZ = companionZ;
            } else if (player != null) {
                scoutAnchorX = player.getX();
                scoutAnchorY = player.getY();
                scoutAnchorZ = player.getZ();
            }
            hasScoutAnchor = (hasVirtualPosition || player != null);
            scoutAngle = 0.0f;
            System.out.println(String.format(
                "[MyNPCBuddy] Order set: SCOUT, anchor=(%.1f,%.1f,%.0f)",
                scoutAnchorX, scoutAnchorY, scoutAnchorZ));

        } else if ("FOLLOW".equals(order)) {
            System.out.println("[MyNPCBuddy] Order set: FOLLOW");
        }
    }

    public String getDangerState() {
        return dangerState != null ? dangerState : "SAFE";
    }

    /**
     * Update the companion state based on current world conditions.
     * Called once per second when Brain Tick is running and companion is enabled.
     * Does NOT spawn any entity or move anything.
     */
    public String update() {
        if (!enabled) {
            return "Companion disabled";
        }

        try {
            // Get player with null checks
            IsoPlayer player = null;
            if (IsoPlayer.players != null && IsoPlayer.players.length > 0) {
                player = IsoPlayer.players[0];
            }

            if (player == null) {
                desiredAction = "WAIT_NO_PLAYER";
                mode = "WAITING";
                return formatStatusLine();
            }

            // Update last known player position
            lastKnownPlayerX = player.getX();
            lastKnownPlayerY = player.getY();
            lastKnownPlayerZ = player.getZ();

            // Get player square with null check
            IsoGridSquare playerSquare = player.getCurrentSquare();
            if (playerSquare == null) {
                desiredAction = "WAIT_NO_PLAYER";
                mode = "WAITING";
                return formatStatusLine();
            }

            // Get cell with null check
            IsoCell cell = playerSquare.getCell();
            if (cell == null) {
                desiredAction = "WAIT_NO_PLAYER";
                mode = "WAITING";
                return formatStatusLine();
            }

            // Scan for zombies
            scanForZombies(player, cell);

            // Make decision based on zombie proximity
            makeDecision();

            // Auto-initialize virtual position if not yet set
            if (!hasVirtualPosition) {
                resetVirtualPosition(player);
            }

            // Update virtual companion position based on desired action
            updateVirtualPosition(player, cell);

            return formatStatusLine();

        } catch (Exception e) {
            System.out.println("[MyNPCBuddy] CompanionBrain update error: " + e.getMessage());
            ExceptionLogger.logException(e);
            return "Companion ERROR: " + e.getMessage();
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Virtual position management
    // ──────────────────────────────────────────────────────────────────────────

    public void resetVirtualPosition(IsoPlayer player) {
        if (player == null) return;
        companionX = player.getX() + 2.0f;
        companionY = player.getY() + 2.0f;
        companionZ = player.getZ();
        hasVirtualPosition = true;
        // Clear scout anchor so next Order: Scout click re-anchors fresh
        hasScoutAnchor = false;
        scoutAngle = 0.0f;
        System.out.println(String.format(
            "[MyNPCBuddy] Virtual companion position reset: x=%.1f y=%.1f z=%.0f",
            companionX, companionY, companionZ));
    }

    private void updateVirtualPosition(IsoPlayer player, IsoCell cell) {
        if (!hasVirtualPosition || player == null) return;

        String action = getDesiredAction();

        if ("FOLLOW_PLAYER".equals(action)) {
            float dist = dist2D(companionX, companionY, lastKnownPlayerX, lastKnownPlayerY);
            if (dist > FOLLOW_STOP_DIST) {
                float dx = lastKnownPlayerX - companionX;
                float dy = lastKnownPlayerY - companionY;
                float len = (float) Math.sqrt(dx * dx + dy * dy);
                if (len > 0) {
                    companionX += (dx / len) * Math.min(MOVE_STEP, dist - FOLLOW_STOP_DIST);
                    companionY += (dy / len) * Math.min(MOVE_STEP, dist - FOLLOW_STOP_DIST);
                }
            }

        } else if ("HOLD_POSITION".equals(action)) {
            // do not move

        } else if ("SCOUT_AREA".equals(action)) {
            // Orbit the fixed scout anchor, not the live player position
            float anchorX = hasScoutAnchor ? scoutAnchorX : lastKnownPlayerX;
            float anchorY = hasScoutAnchor ? scoutAnchorY : lastKnownPlayerY;
            scoutAngle += SCOUT_ANGLE_STEP;
            if (scoutAngle > 2 * Math.PI) scoutAngle -= (float)(2 * Math.PI);
            float targetX = anchorX + SCOUT_RADIUS * (float) Math.cos(scoutAngle);
            float targetY = anchorY + SCOUT_RADIUS * (float) Math.sin(scoutAngle);
            float dx = targetX - companionX;
            float dy = targetY - companionY;
            float len = (float) Math.sqrt(dx * dx + dy * dy);
            if (len > 0.1f) {
                float step = Math.min(MOVE_STEP, len);
                companionX += (dx / len) * step;
                companionY += (dy / len) * step;
            }

        } else if ("FLEE".equals(action)) {
            // Move away from closest zombie — find it
            IsoZombie closestZombie = findClosestZombie(player, cell);
            if (closestZombie != null) {
                float zx = closestZombie.getX();
                float zy = closestZombie.getY();
                float dx = companionX - zx;
                float dy = companionY - zy;
                float len = (float) Math.sqrt(dx * dx + dy * dy);
                if (len > 0) {
                    companionX += (dx / len) * MOVE_STEP;
                    companionY += (dy / len) * MOVE_STEP;
                }
            } else {
                // No zombie found — fall back to following player
                float dist = dist2D(companionX, companionY, lastKnownPlayerX, lastKnownPlayerY);
                if (dist > FOLLOW_STOP_DIST) {
                    float dx = lastKnownPlayerX - companionX;
                    float dy = lastKnownPlayerY - companionY;
                    float len = (float) Math.sqrt(dx * dx + dy * dy);
                    if (len > 0) {
                        companionX += (dx / len) * Math.min(MOVE_STEP, dist - FOLLOW_STOP_DIST);
                        companionY += (dy / len) * Math.min(MOVE_STEP, dist - FOLLOW_STOP_DIST);
                    }
                }
            }
            // Keep Z synced to player floor
            companionZ = lastKnownPlayerZ;

        } else {
            // WAIT_NO_PLAYER or unknown — do not move
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Helper math
    // ──────────────────────────────────────────────────────────────────────────

    public float dist2D(float x1, float y1, float x2, float y2) {
        float dx = x2 - x1;
        float dy = y2 - y1;
        return (float) Math.sqrt(dx * dx + dy * dy);
    }

    public float distToPlayer() {
        if (!hasVirtualPosition) return -1.0f;
        return dist2D(companionX, companionY, lastKnownPlayerX, lastKnownPlayerY);
    }

    private IsoZombie findClosestZombie(IsoPlayer player, IsoCell cell) {
        if (player == null || cell == null) return null;
        ArrayList zombies = cell.getZombieList();
        if (zombies == null) return null;
        IsoZombie closest = null;
        float closestDist = Float.MAX_VALUE;
        int playerZInt = (int) player.getZ();
        for (Object obj : zombies) {
            if (obj == null || !(obj instanceof IsoZombie)) continue;
            IsoZombie zombie = (IsoZombie) obj;
            if ((int) zombie.getZ() != playerZInt) continue;
            float d = dist2D(zombie.getX(), zombie.getY(), companionX, companionY);
            if (d < closestDist) {
                closestDist = d;
                closest = zombie;
            }
        }
        return closest;
    }

    // ──────────────────────────────────────────────────────────────────────────

    private void scanForZombies(IsoPlayer player, IsoCell cell) {
        nearbyZombieCount = 0;
        closestZombieDistance = Float.MAX_VALUE;

        if (cell == null || player == null) {
            return;
        }

        ArrayList zombies = cell.getZombieList();
        if (zombies == null) {
            return;
        }

        float playerX = player.getX();
        float playerY = player.getY();
        float playerZ = player.getZ();
        int playerZInt = (int) playerZ;

        for (Object obj : zombies) {
            if (obj == null) continue;
            if (!(obj instanceof IsoZombie)) continue;

            IsoZombie zombie = (IsoZombie) obj;
            if (zombie == null) continue;

            float zz = zombie.getZ();
            if ((int) zz != playerZInt) continue;

            float zx = zombie.getX();
            float zy = zombie.getY();

            float distance = (float) Math.sqrt(
                Math.pow(zx - playerX, 2) + Math.pow(zy - playerY, 2)
            );

            if (distance <= SCAN_RADIUS) {
                nearbyZombieCount++;
                if (distance < closestZombieDistance) {
                    closestZombieDistance = distance;
                }
            }
        }
    }

    private void makeDecision() {
        if (closestZombieDistance <= FLEE_DISTANCE) {
            dangerState = "DANGER";
            desiredAction = "FLEE";
            mode = "COMBAT";
        } else if (closestZombieDistance <= ALERT_DISTANCE && nearbyZombieCount > 0) {
            dangerState = "CAUTION";
            mode = "ALERT";
            applyOrderDecision();
        } else {
            dangerState = "SAFE";
            mode = "IDLE";
            applyOrderDecision();
        }
    }

    private void applyOrderDecision() {
        String order = getCurrentOrder();
        if ("FOLLOW".equals(order)) {
            desiredAction = "FOLLOW_PLAYER";
        } else if ("STAY".equals(order)) {
            desiredAction = "HOLD_POSITION";
        } else if ("SCOUT".equals(order)) {
            desiredAction = "SCOUT_AREA";
        } else {
            desiredAction = "FOLLOW_PLAYER";
        }
    }

    private String formatStatusLine() {
        String closestStr = (nearbyZombieCount == 0) ? "none" : String.format("%.1f", closestZombieDistance);
        String virtPos = hasVirtualPosition
            ? String.format("(%.1f,%.1f,%.0f)", companionX, companionY, companionZ)
            : "none";
        String distStr = hasVirtualPosition
            ? String.format("%.1f", distToPlayer())
            : "n/a";
        return String.format(
            "Companion order=%s danger=%s action=%s state=%s zombies=%d closest=%s | vpos=%s distToPlayer=%s",
            getCurrentOrder(), getDangerState(), getDesiredAction(), getMode(),
            nearbyZombieCount, closestStr, virtPos, distStr);
    }

    /**
     * Get full status string for the Companion Status button.
     */
    public String getFullStatus() {
        StringBuilder sb = new StringBuilder();
        sb.append("=== Companion Brain Status ===\n");
        sb.append("Enabled: ").append(enabled).append("\n");
        sb.append("Current Order: ").append(getCurrentOrder()).append("\n");
        sb.append("Danger State: ").append(getDangerState()).append("\n");
        sb.append("Mode: ").append(getMode()).append("\n");
        sb.append("Last Known Player: x=").append(String.format("%.1f", lastKnownPlayerX))
          .append(" y=").append(String.format("%.1f", lastKnownPlayerY))
          .append(" z=").append(String.format("%.0f", lastKnownPlayerZ)).append("\n");
        sb.append("Nearby Zombie Count: ").append(nearbyZombieCount).append("\n");
        sb.append("Closest Zombie Distance: ");
        if (nearbyZombieCount == 0) {
            sb.append("none");
        } else {
            sb.append(String.format("%.1f", closestZombieDistance)).append(" tiles");
        }
        sb.append("\n");
        sb.append("Desired Action: ").append(getDesiredAction()).append("\n");
        sb.append("Has Virtual Position: ").append(hasVirtualPosition).append("\n");
        if (hasVirtualPosition) {
            sb.append("Virtual Companion Position: x=").append(String.format("%.1f", companionX))
              .append(" y=").append(String.format("%.1f", companionY))
              .append(" z=").append(String.format("%.0f", companionZ)).append("\n");
            sb.append("Distance To Player: ").append(String.format("%.1f", distToPlayer())).append(" tiles\n");
        } else {
            sb.append("Virtual Companion Position: none\n");
            sb.append("Distance To Player: n/a\n");
        }
        sb.append("Has Scout Anchor: ").append(hasScoutAnchor).append("\n");
        if (hasScoutAnchor) {
            sb.append("Scout Anchor Position: x=").append(String.format("%.1f", scoutAnchorX))
              .append(" y=").append(String.format("%.1f", scoutAnchorY))
              .append(" z=").append(String.format("%.0f", scoutAnchorZ)).append("\n");
        } else {
            sb.append("Scout Anchor Position: none\n");
        }
        sb.append("==============================");
        return sb.toString();
    }

    // Static bridge methods for Lua integration

    public static String luaUpdate() {
        return getInstance().update();
    }

    public static boolean luaIsEnabled() {
        return getInstance().isEnabled();
    }

    public static void luaSetEnabled(boolean enabled) {
        getInstance().setEnabled(enabled);
    }

    public static String luaGetFullStatus() {
        return getInstance().getFullStatus();
    }

    public static String luaGetDesiredAction() {
        return getInstance().getDesiredAction();
    }

    public static void luaSetOrder(String order) {
        getInstance().setCurrentOrder(order);
    }

    public static void luaSetOrderWithInit(String order) {
        getInstance().setOrderWithInit(order);
    }

    public static String luaGetCurrentOrder() {
        return getInstance().getCurrentOrder();
    }

    public static String luaGetDangerState() {
        return getInstance().getDangerState();
    }

    public static void luaResetVirtualPosition() {
        CompanionBrain brain = getInstance();
        IsoPlayer player = null;
        if (IsoPlayer.players != null && IsoPlayer.players.length > 0) {
            player = IsoPlayer.players[0];
        }
        brain.resetVirtualPosition(player);
    }

    public static boolean luaHasVirtualPosition() {
        return getInstance().hasVirtualPosition();
    }

    public static float luaGetCompanionX() { return getInstance().getCompanionX(); }
    public static float luaGetCompanionY() { return getInstance().getCompanionY(); }
    public static float luaGetCompanionZ() { return getInstance().getCompanionZ(); }

    public static float luaDistToPlayer() { return getInstance().distToPlayer(); }

    public static boolean luaHasScoutAnchor() { return getInstance().hasScoutAnchor(); }
    public static float luaGetScoutAnchorX() { return getInstance().getScoutAnchorX(); }
    public static float luaGetScoutAnchorY() { return getInstance().getScoutAnchorY(); }
    public static float luaGetScoutAnchorZ() { return getInstance().getScoutAnchorZ(); }
}
