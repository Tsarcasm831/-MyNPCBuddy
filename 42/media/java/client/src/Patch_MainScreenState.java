package com.lordtsarcasm.mynpcbuddy;

import me.zed_0xff.zombie_buddy.Patch;

import zombie.ui.TextManager;
import zombie.ui.UIFont;

/**
 * Patch the main menu background rendering to confirm MyNPCBuddy loaded.
 */
@Patch(className = "zombie.gameStates.MainScreenState", methodName = "renderBackground")
public class Patch_MainScreenState {
    @Patch.OnExit
    public static void exit() {
        TextManager.instance.DrawString(UIFont.Medium, 0, 0, "MyNPCBuddy loaded", 0.0, 1.0, 0.0, 1.0);
    }
}
