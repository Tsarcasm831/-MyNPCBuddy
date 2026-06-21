package me.zed_0xff.zb_hello_world;

import me.zed_0xff.zombie_buddy.Patch;

import zombie.ui.TextManager;
import zombie.ui.UIFont;

/**
 * Patch the main menu background rendering to draw our Hello World text
 */
@Patch(className = "zombie.gameStates.MainScreenState", methodName = "renderBackground")
public class Patch_MainScreenState {
    @Patch.OnExit
    public static void exit() {
        TextManager.instance.DrawString(UIFont.Medium, 0, 0, "Hello World from ZBHelloWorld!", 1.0, 1.0, 1.0, 1.0);
    }
}
