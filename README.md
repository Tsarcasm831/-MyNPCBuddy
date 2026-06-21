# MyNPCBuddy

A Project Zomboid mod built on [ZombieBuddy](https://github.com/zed-0xff/ZombieBuddy). Phase 1 confirms the Java mod loads by rendering "MyNPCBuddy loaded" on the main menu screen.

## What It Does

Draws "MyNPCBuddy loaded" (green text) in the top-left corner of the main menu by patching `MainScreenState.renderBackground()`. No NPC behaviour is implemented in Phase 1.

## Features

- **Patches-only mod**: No Main class required — ZombieBuddy auto-discovers `@Patch` classes from `javaPkgName`
- **Load confirmation**: Green "MyNPCBuddy loaded" text on main menu
- **Safe**: Does not spawn anything, does not touch save data, does not modify game files

## Prerequisites

[ZombieBuddy](https://github.com/zed-0xff/ZombieBuddy) must be installed and enabled.

## mod.info

```ini
require=\ZombieBuddy
ZBVersionMin=1.6.0
javaJarFile=media/java/client/build/libs/client.jar
javaPkgName=com.anton.mynpcbuddy
```

## The Patch

```java
package com.anton.mynpcbuddy;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.ui.TextManager;
import zombie.ui.UIFont;

@Patch(className = "zombie.gameStates.MainScreenState", methodName = "renderBackground")
public class Patch_MainScreenState {
    @Patch.OnExit
    public static void exit() {
        TextManager.instance.DrawString(UIFont.Medium, 0, 0, "MyNPCBuddy loaded", 0.0, 1.0, 0.0, 1.0);
    }
}
```

## Building (Windows)

**Requirements:** JDK 17, Gradle 8+, Project Zomboid installed via Steam.

1. Open a terminal (PowerShell or cmd) and navigate to the Gradle project:

   ```pwsh
   cd mods\MyNPCBuddy\42\media\java\client
   ```

2. Build (replace paths if your PZ install differs):

   ```pwsh
   gradle build -PZVersion=42
   ```

   Override jar locations if needed:
   ```pwsh
   gradle build -PZVersion=42 `
     -PPZ_DIR="C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid" `
     -PZB_JAR="C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\ZombieBuddy.jar"
   ```

3. Output JAR: `42\media\java\client\build\libs\client.jar`

   This path matches `javaJarFile` in `mod.info` — no copy step needed.

## Project Structure

```
MyNPCBuddy/
├── common/
│   └── mod.info
├── 42/
│   └── media/
│       ├── java/
│       │   └── client/          ← Gradle project root
│       │       ├── build.gradle
│       │       ├── gradle.properties
│       │       ├── src/
│       │       │   └── Patch_MainScreenState.java
│       │       └── build/
│       │           └── libs/
│       │               └── client.jar   ← loaded by ZombieBuddy
│       └── lua/
│           └── client/
└── README.md
```

## License

See [LICENSE](LICENSE) file for details.
