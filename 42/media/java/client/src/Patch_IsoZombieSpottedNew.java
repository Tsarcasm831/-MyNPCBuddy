package com.lordtsarcasm.mynpcbuddy;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.IsoZombie;
import se.krka.kahlua.vm.KahluaTable;

/**
 * Proof patch: blocks target acquisition for MyNPCBuddy-marked companion zombies.
 * Uses @Patch.OnEnter(skipOn = true) to short-circuit spottedNew when the zombie
 * carries the ModData marker "MyNPCBuddyTestZombie = true".
 * Unmarked zombies are completely unaffected (return false → original method runs).
 */
@Patch(className = "zombie.characters.IsoZombie", methodName = "spottedNew")
public class Patch_IsoZombieSpottedNew {

    @Patch.OnEnter(skipOn = true)
    public static boolean onEnter(@Patch.This IsoZombie self) {
        try {
            if (!self.hasModData()) return false;
            KahluaTable md = self.getModData();
            if (md == null) return false;
            Object val = md.rawget("MyNPCBuddyTestZombie");
            if (val instanceof Boolean && (Boolean) val) {
                DebugBridge.onSpottedBlocked("spottedNew");
                return true;
            }
        } catch (Exception e) {
            // Safe fallback: don't skip
        }
        return false;
    }
}
