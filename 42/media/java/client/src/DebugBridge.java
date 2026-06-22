package com.lordtsarcasm.mynpcbuddy;

import me.zed_0xff.zombie_buddy.Exposer;
import zombie.core.logger.ExceptionLogger;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.characters.SurvivorDesc;
import zombie.characters.SurvivorFactory;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoMovingObject;
import zombie.iso.sprite.IsoSprite;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.ModelManager.ModelSlot;
import zombie.core.skinnedmodel.visual.BaseVisual;
import zombie.core.skinnedmodel.visual.HumanVisual;
import zombie.core.skinnedmodel.animation.AnimationPlayer;
import zombie.scripting.objects.ModelScript;
import zombie.debug.DebugOptions;
import zombie.core.Core;
import java.util.ArrayList;
import java.lang.reflect.Field;

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

    // ============ Test NPC Body (debug-only, IsoPlayer NPC pattern) ============

    private static IsoPlayer testNpc = null;
    private static boolean visMaintActive = false;

    // ============ Render trace (temporary diagnostic) ============
    // Test A: dispatch proof for IsoPlayer.render advice (incremented for ANY player, before identity filter).
    private static volatile int playerRenderGlobalCount = 0;
    private static volatile int renderCallsSeen = 0;
    private static volatile long lastRenderFrame = 0;
    private static volatile long lastRenderTimeMs = 0;
    private static volatile String lastRenderNpcId = null;
    private static volatile String lastRenderSlotId = null;

    // ============ FBO render trace (temporary diagnostic) ============
    // Control target #1: no-arg dispatch proof for FBORenderCell.renderMovingObjects advice.
    private static volatile int fboMovingObjectsProofCount = 0;

    // ============ Square render trace (temporary diagnostic) ============
    // Test B: no-arg dispatch proof for IsoGridSquare.renderCharacters advice.
    private static volatile int squarePatchProofCount = 0;
    private static volatile int sqRenderGlobalCount = 0;
    private static volatile int sqRenderCallsSeen = 0;
    private static volatile long lastSqRenderFrame = 0;
    private static volatile long lastSqRenderTimeMs = 0;
    private static volatile int npcEncounteredCount = 0;
    private static volatile long lastNpcEncounterFrame = 0;
    private static volatile long lastNpcEncounterTimeMs = 0;
    private static volatile String sqSkipReason = null;
    private static volatile int sqRenderX = -1;
    private static volatile int sqRenderY = -1;
    private static volatile int sqRenderZ = -1;
    private static volatile int sqRenderZCutoff = -1;
    private static volatile boolean sqRenderParam2 = false;
    private static volatile boolean npcInMovingObjects = false;
    private static volatile boolean npcSpriteNull = false;
    private static volatile boolean npcOnFloorVal = false;

    public static boolean hasTestNpc() {
        return testNpc != null;
    }

    public static boolean isVisMaintActive() {
        return visMaintActive;
    }

    public static void maintainTestNpcVisibility() {
        if (testNpc == null) return;
        try {
            testNpc.setAlphaAndTarget(1.0f);
        } catch (Exception e) {
            System.out.println("[MyNPCBuddy] maintainTestNpcVisibility ERROR: " + e.getMessage());
            ExceptionLogger.logException(e);
        }
    }

    public static String npcStatus() {
        try {
            if (testNpc == null) {
                String msg = "NPC Status: no test NPC exists";
                System.out.println("[MyNPCBuddy] " + msg);
                return msg;
            }

            StringBuilder sb = new StringBuilder();
            String objId = Integer.toHexString(System.identityHashCode(testNpc));
            sb.append("NPC Status: obj=0x").append(objId).append("\n");
            sb.append("  isNpc: ").append(testNpc.isNpc()).append("\n");
            sb.append("  isLocal: ").append(testNpc.isLocal()).append("\n");
            sb.append("  isLocalPlayer: ").append(testNpc.isLocalPlayer()).append("\n");

            float x = testNpc.getX();
            float y = testNpc.getY();
            float z = testNpc.getZ();
            sb.append("  pos: (").append(x).append(", ").append(y).append(", ").append(z).append(")\n");

            IsoGridSquare sq = testNpc.getCurrentSquare();
            if (sq == null) {
                sb.append("  square: NULL\n");
            } else {
                sb.append("  square: (").append(sq.getX()).append(",").append(sq.getY()).append(",").append(sq.getZ()).append(")\n");
                Object room = sq.getRoom();
                sb.append("  room: ").append(room != null ? room.toString() : "null").append("\n");
            }

            Object building = testNpc.getCurrentBuilding();
            sb.append("  building: ").append(building != null ? building.toString() : "null").append("\n");

            sb.append("  isSceneCulled: ").append(testNpc.isSceneCulled()).append("\n");
            sb.append("  isInvisible: ").append(testNpc.isInvisible()).append("\n");
            sb.append("  doRender: ").append(testNpc.getDoRender()).append("\n");

            sb.append("  alpha[0]: ").append(testNpc.getAlpha(0)).append("\n");
            sb.append("  targetAlpha[0]: ").append(testNpc.getTargetAlpha(0)).append("\n");
            sb.append("  visMaintActive: ").append(visMaintActive).append("\n");

            IsoCell cell = testNpc.getCell();
            if (cell != null) {
                boolean inObjectList = cell.getObjectList().contains(testNpc);
                sb.append("  inCellObjectList: ").append(inObjectList).append("\n");
            } else {
                sb.append("  inCellObjectList: cell is NULL\n");
            }

            sb.append("  numPlayers: ").append(IsoPlayer.numPlayers).append("\n");
            int playersSlot = -1;
            if (IsoPlayer.players != null) {
                for (int i = 0; i < IsoPlayer.players.length; i++) {
                    if (IsoPlayer.players[i] == testNpc) {
                        playersSlot = i;
                        break;
                    }
                }
            }
            sb.append("  playersSlot: ").append(playersSlot >= 0 ? playersSlot : "NOT_FOUND").append("\n");

            if (sq != null) {
                boolean inMovingObjects = sq.getMovingObjects().contains(testNpc);
                sb.append("  inSquareMovingObjects: ").append(inMovingObjects).append("\n");
            }

            String msg = sb.toString();
            System.out.println("[MyNPCBuddy] " + msg.replace("\n", " | "));
            return msg;

        } catch (Exception e) {
            String msg = "NPC Status ERROR: " + e.getMessage();
            System.out.println("[MyNPCBuddy] " + msg);
            ExceptionLogger.logException(e);
            return msg;
        }
    }

    public static String npcModelStatus() {
        try {
            if (testNpc == null) {
                String msg = "NPC Model Status: no test NPC exists";
                System.out.println("[MyNPCBuddy] " + msg);
                return msg;
            }

            StringBuilder sb = new StringBuilder();
            String objId = Integer.toHexString(System.identityHashCode(testNpc));
            sb.append("NPC Model Status: obj=0x").append(objId).append("\n");

            // 1. ModelManager global state
            try {
                sb.append("  MM.created: ").append(ModelManager.instance.isCreated()).append("\n");
                sb.append("  MM.debugEnableModels: ").append(ModelManager.instance.debugEnableModels).append("\n");
                sb.append("  MM.ContainsChar: ").append(ModelManager.instance.ContainsChar(testNpc)).append("\n");
            } catch (Exception e) {
                sb.append("  MM global state: ERROR: ").append(e.getMessage()).append("\n");
            }

            // 2. Character registration state
            try {
                sb.append("  isAddedToModelManager: ").append(testNpc.isAddedToModelManager()).append("\n");
            } catch (Exception e) {
                sb.append("  isAddedToModelManager: ERROR: ").append(e.getMessage()).append("\n");
            }

            // 3. Visual data
            try {
                BaseVisual visual = testNpc.getVisual();
                sb.append("  getVisual: ").append(visual != null ? visual.getClass().getSimpleName() : "NULL").append("\n");
                if (visual instanceof HumanVisual) {
                    ModelScript script = ((HumanVisual) visual).getModelScript();
                    sb.append("  getModelScript: ").append(script != null ? script.getName() : "NULL").append("\n");
                } else if (visual == null) {
                    sb.append("  getModelScript: SKIPPED (visual is null)\n");
                } else {
                    sb.append("  getModelScript: SKIPPED (visual is not HumanVisual)\n");
                }
            } catch (Exception e) {
                sb.append("  Visual data: ERROR: ").append(e.getMessage()).append("\n");
            }

            // 4. Animation player (lazy-created/read diagnostic)
            try {
                AnimationPlayer ap = testNpc.getAnimationPlayer();
                sb.append("  getAnimationPlayer: ").append(ap != null ? "non-null (lazy-created/read diagnostic)" : "NULL (lazy-created/read diagnostic)").append("\n");
            } catch (Exception e) {
                sb.append("  getAnimationPlayer: ERROR (lazy-created/read diagnostic): ").append(e.getMessage()).append("\n");
            }

            // 5. Legs sprite and model slot
            try {
                IsoSprite legs = testNpc.getLegsSprite();
                sb.append("  legsSprite: ").append(legs != null ? "non-null" : "NULL").append("\n");
                if (legs != null) {
                    sb.append("  legsSprite.hasActiveModel: ").append(legs.hasActiveModel()).append("\n");
                    ModelSlot slot = legs.modelSlot;
                    sb.append("  legsSprite.modelSlot: ").append(slot != null ? "non-null" : "NULL").append("\n");
                    if (slot != null) {
                        sb.append("    slot.active: ").append(slot.active).append("\n");
                        sb.append("    slot.remove: ").append(slot.remove).append("\n");
                        sb.append("    slot.model: ").append(slot.model != null ? "non-null" : "NULL").append("\n");
                        sb.append("    slot.character: ").append(slot.character != null ? Integer.toHexString(System.identityHashCode(slot.character)) : "NULL").append("\n");
                        sb.append("    slot.isRendering: ").append(slot.isRendering()).append("\n");
                        sb.append("    slot.framesSinceStart: ").append(slot.framesSinceStart).append("\n");
                    }
                }
            } catch (Exception e) {
                sb.append("  Legs sprite/model slot: ERROR: ").append(e.getMessage()).append("\n");
            }

            // 6. useParts (reflection — protected field)
            try {
                Field f = IsoGameCharacter.class.getDeclaredField("useParts");
                f.setAccessible(true);
                sb.append("  useParts: ").append(f.getBoolean(testNpc)).append("\n");
            } catch (Exception e) {
                sb.append("  useParts: REFLECTION_FAILED: ").append(e.getMessage()).append("\n");
            }

            // 7. DebugOptions.isoSprite.renderModels
            try {
                sb.append("  renderModels: ").append(DebugOptions.instance.isoSprite.renderModels.getValue()).append("\n");
            } catch (Exception e) {
                sb.append("  renderModels: ERROR: ").append(e.getMessage()).append("\n");
            }

            // 8. Core.displayPlayerModel
            try {
                sb.append("  displayPlayerModel: ").append(Core.getInstance().isDisplayPlayerModel()).append("\n");
            } catch (Exception e) {
                sb.append("  displayPlayerModel: ERROR: ").append(e.getMessage()).append("\n");
            }

            // 9. checkCanSeeClient (direct test)
            try {
                sb.append("  checkCanSeeClient: ").append(IsoPlayer.getInstance().checkCanSeeClient(testNpc)).append("\n");
            } catch (Exception e) {
                sb.append("  checkCanSeeClient: ERROR: ").append(e.getMessage()).append("\n");
            }

            // 10. spottedByPlayer
            try {
                sb.append("  spottedByPlayer: ").append(testNpc.spottedByPlayer).append("\n");
            } catch (Exception e) {
                sb.append("  spottedByPlayer: ERROR: ").append(e.getMessage()).append("\n");
            }

            String msg = sb.toString();
            System.out.println("[MyNPCBuddy] " + msg.replace("\n", " | "));
            return msg;

        } catch (Exception e) {
            String msg = "NPC Model Status ERROR: " + e.getMessage();
            System.out.println("[MyNPCBuddy] " + msg);
            ExceptionLogger.logException(e);
            return msg;
        }
    }

    // ============ Render trace (temporary diagnostic) ============

    public static void onNpcRenderEnter(IsoPlayer self) {
        playerRenderGlobalCount++;
        if (testNpc == null || self != testNpc) return;
        renderCallsSeen++;
        lastRenderFrame = zombie.iso.IsoCamera.frameState.frameCount;
        lastRenderTimeMs = System.currentTimeMillis();
        lastRenderNpcId = Integer.toHexString(System.identityHashCode(self));
        try {
            zombie.iso.sprite.IsoSprite legs = self.getLegsSprite();
            if (legs != null && legs.modelSlot != null) {
                lastRenderSlotId = Integer.toHexString(System.identityHashCode(legs.modelSlot));
            } else {
                lastRenderSlotId = "null";
            }
        } catch (Exception e) {
            lastRenderSlotId = "error:" + e.getMessage();
        }
    }

    // Test B: smallest-possible proof that the renderCharacters advice dispatches.
    // Called from the no-arg Patch_IsoGridSquareRenderCharacters.onEnter().
    public static void incrementSquarePatchProofCounter() {
        squarePatchProofCount++;
    }

    // Control target #1: smallest-possible proof that the live FBO character render
    // path (FBORenderCell.renderMovingObjects) dispatches under ZombieBuddy.
    // Called from the no-arg Patch_FBORenderMovingObjects.onEnter().
    public static void incrementFboMovingObjectsProofCounter() {
        fboMovingObjectsProofCount++;
    }

    public static int getFboMovingObjectsProofCount() {
        return fboMovingObjectsProofCount;
    }

    private static void resetRenderTrace() {
        playerRenderGlobalCount = 0;
        renderCallsSeen = 0;
        lastRenderFrame = 0;
        lastRenderTimeMs = 0;
        lastRenderNpcId = null;
        lastRenderSlotId = null;
    }

    public static String npcRenderTrace() {
        try {
            StringBuilder sb = new StringBuilder();
            sb.append("=== NPC Render Trace ===\n");
            sb.append("  playerRenderGlobalCount (Test A): ").append(playerRenderGlobalCount).append("\n");
            sb.append("  renderCallsSeen: ").append(renderCallsSeen).append("\n");
            if (testNpc == null) {
                sb.append("  testNpc exists: false (no test NPC spawned)\n");
                String msg = sb.toString();
                System.out.println("[MyNPCBuddy] " + msg.replace("\n", " | "));
                return msg;
            }
            sb.append("  testNpc exists: true\n");
            sb.append("  npcIdentity: 0x").append(Integer.toHexString(System.identityHashCode(testNpc))).append("\n");
            if (renderCallsSeen > 0) {
                long nowMs = System.currentTimeMillis();
                long elapsedMs = nowMs - lastRenderTimeMs;
                sb.append("  lastRenderFrame: ").append(lastRenderFrame).append("\n");
                sb.append("  msSinceLastRender: ").append(elapsedMs).append("\n");
                sb.append("  lastRenderNpcId: 0x").append(lastRenderNpcId).append("\n");
                sb.append("  lastRenderSlotId: 0x").append(lastRenderSlotId).append("\n");
                sb.append("  alpha: ").append(testNpc.getAlpha()).append("\n");
                sb.append("  targetAlpha: ").append(testNpc.getTargetAlpha()).append("\n");
            } else {
                sb.append("  render() was NEVER entered for this NPC\n");
            }
            String msg = sb.toString();
            System.out.println("[MyNPCBuddy] " + msg.replace("\n", " | "));
            return msg;
        } catch (Exception e) {
            String msg = "NPC Render Trace ERROR: " + e.getMessage();
            System.out.println("[MyNPCBuddy] " + msg);
            ExceptionLogger.logException(e);
            return msg;
        }
    }

    // ============ Square render trace (temporary diagnostic) ============

    public static void onSquareRenderEnter(IsoGridSquare sq, Object[] args) {
        sqRenderGlobalCount++;
        if (testNpc == null) return;
        try {
            IsoGridSquare npcCurSq = testNpc.getCurrentSquare();
            IsoGridSquare npcMovSq = testNpc.getMovingSquare();
            boolean isNpcSquare = (sq == npcCurSq || sq == npcMovSq);
            boolean inList = sq.getMovingObjects().contains(testNpc);
            if (!isNpcSquare && !inList) return;

            sqRenderCallsSeen++;
            lastSqRenderFrame = zombie.iso.IsoCamera.frameState.frameCount;
            lastSqRenderTimeMs = System.currentTimeMillis();
            sqRenderX = sq.getX();
            sqRenderY = sq.getY();
            sqRenderZ = sq.getZ();

            int zCutoff = (Integer) args[0];
            boolean param2 = (Boolean) args[1];
            sqRenderZCutoff = zCutoff;
            sqRenderParam2 = param2;
            npcInMovingObjects = inList;

            if (sq.getZ() >= zCutoff) {
                sqSkipReason = "square z=" + sq.getZ() + " >= zCutoff=" + zCutoff + " (method returns before loop)";
                return;
            }

            npcSpriteNull = (testNpc.getSprite() == null);
            Boolean onFloor = getNpcOnFloor();
            npcOnFloorVal = (onFloor != null) ? onFloor : false;

            if (inList) {
                npcEncounteredCount++;
                lastNpcEncounterFrame = zombie.iso.IsoCamera.frameState.frameCount;
                lastNpcEncounterTimeMs = System.currentTimeMillis();

                if (npcSpriteNull) {
                    sqSkipReason = "NPC sprite is null (offset 228-236: sprite==null → skip)";
                } else if (param2 && !npcOnFloorVal) {
                    sqSkipReason = "param2=true (on-floor pass) but npc.onFloor=false (offset 282-291 → skip)";
                } else if (!param2 && npcOnFloorVal) {
                    sqSkipReason = "param2=false (off-floor pass) but npc.onFloor=true (offset 294-303 → skip)";
                } else {
                    sqSkipReason = "NO SKIP CONDITION FOUND — NPC should reach render()";
                }
            } else {
                sqSkipReason = "NPC not in this square's movingObjects (isNpcSquare=" + isNpcSquare + ")";
            }
        } catch (Exception e) {
            sqSkipReason = "onSquareRenderEnter ERROR: " + e.getMessage();
        }
    }

    private static Boolean getNpcOnFloor() {
        try {
            Field f = IsoMovingObject.class.getDeclaredField("onFloor");
            f.setAccessible(true);
            return f.getBoolean(testNpc);
        } catch (Exception e) {
            return null;
        }
    }

    private static void resetSqRenderTrace() {
        squarePatchProofCount = 0;
        sqRenderGlobalCount = 0;
        sqRenderCallsSeen = 0;
        lastSqRenderFrame = 0;
        lastSqRenderTimeMs = 0;
        npcEncounteredCount = 0;
        lastNpcEncounterFrame = 0;
        lastNpcEncounterTimeMs = 0;
        sqSkipReason = null;
        sqRenderX = -1;
        sqRenderY = -1;
        sqRenderZ = -1;
        sqRenderZCutoff = -1;
        sqRenderParam2 = false;
        npcInMovingObjects = false;
        npcSpriteNull = false;
        npcOnFloorVal = false;
    }

    public static String npcSquareRenderTrace() {
        try {
            StringBuilder sb = new StringBuilder();
            sb.append("=== NPC Square Render Trace ===\n");
            sb.append("  squarePatchProofCount (Test B): ").append(squarePatchProofCount).append("\n");
            if (testNpc == null) {
                sb.append("  no test NPC exists\n");
                String msg = sb.toString();
                System.out.println("[MyNPCBuddy] " + msg.replace("\n", " | "));
                return msg;
            }
            sb.append("  npcIdentity: 0x").append(Integer.toHexString(System.identityHashCode(testNpc))).append("\n");
            IsoGridSquare npcSq = testNpc.getCurrentSquare();
            sb.append("  npcCurrentSquare: ").append(npcSq != null ? npcSq.getX() + "," + npcSq.getY() + "," + npcSq.getZ() : "NULL").append("\n");
            IsoGridSquare npcMovSq = testNpc.getMovingSquare();
            sb.append("  npcMovingSquare: ").append(npcMovSq != null ? npcMovSq.getX() + "," + npcMovSq.getY() + "," + npcMovSq.getZ() : "NULL").append("\n");
            sb.append("  sqRenderCallsSeen: ").append(sqRenderCallsSeen).append("\n");
            sb.append("  sqRenderGlobalCount: ").append(sqRenderGlobalCount).append("\n");
            if (sqRenderCallsSeen > 0) {
                long nowMs = System.currentTimeMillis();
                sb.append("  lastSqRenderFrame: ").append(lastSqRenderFrame).append("\n");
                sb.append("  msSinceLastSqRender: ").append(nowMs - lastSqRenderTimeMs).append("\n");
                sb.append("  sqRenderCoords: ").append(sqRenderX).append(",").append(sqRenderY).append(",").append(sqRenderZ).append("\n");
                sb.append("  sqRenderZCutoff: ").append(sqRenderZCutoff).append("\n");
                sb.append("  sqRenderParam2: ").append(sqRenderParam2).append("\n");
                sb.append("  npcInMovingObjects: ").append(npcInMovingObjects).append("\n");
                sb.append("  npcEncounteredCount: ").append(npcEncounteredCount).append("\n");
                if (npcEncounteredCount > 0) {
                    sb.append("  lastNpcEncounterFrame: ").append(lastNpcEncounterFrame).append("\n");
                    sb.append("  msSinceLastEncounter: ").append(nowMs - lastNpcEncounterTimeMs).append("\n");
                }
                sb.append("  npcSpriteNull: ").append(npcSpriteNull).append("\n");
                sb.append("  npcOnFloor: ").append(npcOnFloorVal).append("\n");
                sb.append("  skipReason: ").append(sqSkipReason != null ? sqSkipReason : "none").append("\n");
            } else {
                sb.append("  renderCharacters() NEVER called for NPC's square\n");
                sb.append("  sqRenderGlobalCount: ").append(sqRenderGlobalCount).append("\n");
                sb.append("  -> square may be out of render range or z cutoff\n");
            }
            String msg = sb.toString();
            System.out.println("[MyNPCBuddy] " + msg.replace("\n", " | "));
            return msg;
        } catch (Exception e) {
            String msg = "NPC Square Render Trace ERROR: " + e.getMessage();
            System.out.println("[MyNPCBuddy] " + msg);
            ExceptionLogger.logException(e);
            return msg;
        }
    }

    public static String spawnTestNpc() {
        try {
            if (testNpc != null) {
                String msg = "Spawn NPC Body: test NPC already exists, refusing to spawn another";
                System.out.println("[MyNPCBuddy] " + msg);
                return msg;
            }

            IsoPlayer player = null;
            if (IsoPlayer.players != null && IsoPlayer.players.length > 0) {
                player = IsoPlayer.players[0];
            }
            if (player == null) {
                String msg = "Spawn NPC Body: no player found";
                System.out.println("[MyNPCBuddy] " + msg);
                return msg;
            }

            IsoGridSquare playerSquare = player.getCurrentSquare();
            if (playerSquare == null) {
                String msg = "Spawn NPC Body: player square not found";
                System.out.println("[MyNPCBuddy] " + msg);
                return msg;
            }

            IsoCell cell = playerSquare.getCell();
            if (cell == null) {
                String msg = "Spawn NPC Body: cell not found";
                System.out.println("[MyNPCBuddy] " + msg);
                return msg;
            }

            int spawnX = (int) player.getX() + 3;
            int spawnY = (int) player.getY();
            int spawnZ = (int) player.getZ();

            System.out.println("[MyNPCBuddy] Spawn NPC Body: request received, target pos=("
                + spawnX + "," + spawnY + "," + spawnZ + ")");

            IsoGridSquare spawnSquare = cell.getGridSquare(spawnX, spawnY, spawnZ);
            if (spawnSquare == null) {
                String msg = "Spawn NPC Body: spawn square is null at ("
                    + spawnX + "," + spawnY + "," + spawnZ + ") — try moving to a loaded area";
                System.out.println("[MyNPCBuddy] " + msg);
                return msg;
            }

            SurvivorDesc desc = SurvivorFactory.CreateSurvivor();
            if (desc == null) {
                String msg = "Spawn NPC Body: SurvivorFactory.CreateSurvivor() returned null";
                System.out.println("[MyNPCBuddy] " + msg);
                return msg;
            }

            System.out.println("[MyNPCBuddy] Spawn NPC Body: SurvivorDesc created, class="
                + desc.getClass().getName());

            IsoPlayer npc = new IsoPlayer(cell, desc, spawnX, spawnY, spawnZ);
            if (npc == null) {
                String msg = "Spawn NPC Body: IsoPlayer constructor returned null";
                System.out.println("[MyNPCBuddy] " + msg);
                return msg;
            }

            npc.setNpc(true);
            npc.setSceneCulled(false);
            npc.setInvisible(false);
            npc.setAlphaAndTarget(1.0f);

            testNpc = npc;
            visMaintActive = true;
            resetRenderTrace();
            resetSqRenderTrace();
            System.out.println("[MyNPCBuddy] Visibility maintenance started for test NPC");

            String classInfo = npc.getClass().getName();
            String objId = Integer.toHexString(System.identityHashCode(npc));
            String msg = "Spawn NPC Body: OK at (" + spawnX + "," + spawnY + "," + spawnZ
                + ") class=" + classInfo + " obj=0x" + objId + " npc=true sceneCulled=false forcedAlpha=true";
            System.out.println("[MyNPCBuddy] " + msg);
            return msg;

        } catch (Exception e) {
            String msg = "Spawn NPC Body ERROR: " + e.getMessage();
            System.out.println("[MyNPCBuddy] " + msg);
            ExceptionLogger.logException(e);
            return msg;
        }
    }

    public static String despawnTestNpc() {
        try {
            if (testNpc == null) {
                String msg = "Despawn NPC Body: no test NPC to despawn";
                System.out.println("[MyNPCBuddy] " + msg);
                return msg;
            }

            String objId = Integer.toHexString(System.identityHashCode(testNpc));
            System.out.println("[MyNPCBuddy] Despawn NPC Body: removing obj=0x" + objId + " from world");

            if (visMaintActive) {
                visMaintActive = false;
                System.out.println("[MyNPCBuddy] Visibility maintenance stopped (despawn)");
            }
            testNpc.removeFromWorld();
            testNpc.removeFromSquare();
            testNpc = null;
            resetRenderTrace();
            resetSqRenderTrace();

            String msg = "Despawn NPC Body: OK, obj=0x" + objId + " removed and reference cleared";
            System.out.println("[MyNPCBuddy] " + msg);
            return msg;

        } catch (Exception e) {
            String msg = "Despawn NPC Body ERROR: " + e.getMessage();
            System.out.println("[MyNPCBuddy] " + msg);
            ExceptionLogger.logException(e);
            testNpc = null;
            return msg;
        }
    }

    public static void cleanupTestNpc() {
        if (testNpc == null) return;
        try {
            String objId = Integer.toHexString(System.identityHashCode(testNpc));
            if (visMaintActive) {
                visMaintActive = false;
                System.out.println("[MyNPCBuddy] Visibility maintenance stopped (cleanup)");
            }
            System.out.println("[MyNPCBuddy] Cleanup: removing test NPC obj=0x" + objId + " from world");
            testNpc.removeFromWorld();
            testNpc.removeFromSquare();
            testNpc = null;
            resetRenderTrace();
            resetSqRenderTrace();
            System.out.println("[MyNPCBuddy] Cleanup: test NPC removed OK");
        } catch (Exception e) {
            System.out.println("[MyNPCBuddy] Cleanup: test NPC removal error: " + e.getMessage());
            ExceptionLogger.logException(e);
            testNpc = null;
        }
    }

    // ============ Spotted-block diagnostic (target-acquisition proof) ============

    private static volatile int spottedBlockCount = 0;
    private static volatile boolean spottedBlockLogged = false;

    public static void onSpottedBlocked(String methodName) {
        spottedBlockCount++;
        if (!spottedBlockLogged) {
            spottedBlockLogged = true;
            System.out.println("[MyNPCBuddy] Target acquisition blocked via " + methodName
                + " — marked zombie identified, MyNPCBuddyTestZombie=true");
        }
    }

    public static int getSpottedBlockCount() {
        return spottedBlockCount;
    }

    public static void resetSpottedBlockCount() {
        spottedBlockCount = 0;
        spottedBlockLogged = false;
    }
}
