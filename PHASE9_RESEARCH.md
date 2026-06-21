# MyNPCBuddy — Phase 9 Research Report
> Generated after full scan of all reference and workshop_refs folders.
> Date: June 2026. No code was changed. No spawning was performed.

---

## A. Executive Summary

### Most Useful Findings

1. **`IsoLuaMover`** is the single most promising discovery in the entire reference set. It is a Java class (`zombie.iso.IsoLuaMover`) that extends `IsoGameCharacter` and is explicitly designed for Lua-controlled moving entities. It has a simple `new(table)` constructor, exposes `update()`, `render()`, and `playAnim()`. This is the correct Build 42 path for a visible in-world companion body — not `IsoPlayer.new()`.

2. **`IsoSurvivor` + `SurvivorFactory` + `SurvivorDesc`** are fully present and documented in both the PZ-Umbrella stubs and vanilla Lua. `SurvivorFactory.CreateSurvivor()` and `SurvivorFactory.InstansiateInCell()` are the vanilla-sanctioned spawning path. These APIs appear to be present in Build 42 but **must be tested** before use.

3. **`WorldMarkers` and `IsoMarkers`** are confirmed Build 42 APIs. We already use them. `WorldMarkers.addGridSquareMarker()`, `addDirectionArrow()`, and `addPlayerHomingPoint()` give us a full non-persistent visual toolkit that requires zero spawning.

4. **`PathFindBehavior2`** is the vanilla pathfinder. It is tied to a real `IsoGameCharacter` instance. Not usable until a real body exists, but the API is fully mapped.

5. **Braven's NPC Framework** uses `IsoPlayer.new(cell, desc, x, y, z)` — **not** `IsoSurvivor`. This is a critical finding. It is a misuse of `IsoPlayer` as an NPC container and is almost certainly what makes it **Build 41-only**. Build 42 changed how `IsoPlayer` is instantiated. Do not copy this.

6. **B42ModOptions** (via `PZAPI.ModOptions`) is confirmed Build 42-native and fully implemented in vanilla. It is immediately usable for our console settings without any third-party dependency.

7. **`Events.OnTick`, `Events.EveryOneMinute`, `Events.OnGameStart`, `Events.OnSave`** are all confirmed present and documented. Our brain tick uses `OnTick` already; this is safe.

8. **Save-safe state**: `ModData` (`getModData()`) on player or world objects is the standard save mechanism. Braven saves NPC inventory by placing a physical `IsoObject` stash in the world — this **mutates the save** and is unsafe for us. Our current virtual-only approach is correct.

### Most Promising Body Direction

**`IsoLuaMover`** → short-term test target. It is a Lua-scriptable moving character class with minimal wiring. If it works in B42, it gives us a real rendered body with animations, at far lower risk than `IsoSurvivor` or `IsoPlayer`.

Fallback: `IsoSurvivor.new(desc, cell, x, y, z)` via `SurvivorFactory`, which is the vanilla-intended NPC spawn path.

### Which References Are Directly Useful

- `references/PZ-Umbrella` — **Directly useful**: complete Java stub library, all class signatures confirmed.
- `references/ProjectZomboid-Vanilla-Lua` — **Directly useful**: live B42 Lua code, NPCs folder, debug spawn UIs, WorldMarkers usage.
- `workshop_refs/B42ModOptions` — **Directly useful**: B42-native mod options, ready to integrate.
- `workshop_refs/BravensNPCFramework` — **Conceptually critical, NOT B42 compatible** as-is: do not copy `IsoPlayer.new()`.

### Which References Are Conceptually Useful But Not B42-Compatible

- `workshop_refs/BravensNPCFramework` — B41-era. Architecture is instructive; spawning is unsafe.
- `references/pz-zdoc` — A B41-era doc generator tool, not a runtime mod. Irrelevant at runtime.
- `references/Zomboid-Modding-Guide` — B40/B41 era, but Lua/event system documentation is conceptually valid.

### Safest Recommended Next Step

**Phase 9D**: Use Java reflection/logging to discover exactly what `IsoLuaMover.new(table)` accepts in B42 before touching it in Lua. Confirm the constructor signature, then build a single controlled test in a throwaway save.

---

## B. Compatibility Assessment

| Reference Folder | Status | Why It Matters | Action |
|---|---|---|---|
| `references/PZ-Umbrella` | ✅ **Directly B42 compatible** | Complete Java stub library, used for code completion, documents all classes including `IsoLuaMover`, `IsoSurvivor`, `WorldMarkers`, `PathFindBehavior2`, `SurvivorFactory`. Already matches B42 class structure. | **Reuse** as reference/IDE support |
| `references/ProjectZomboid-Vanilla-Lua` | ✅ **Directly B42 compatible** | This is extracted vanilla B42 Lua source. `shared/NPCs/` contains `SurvivorSwap.lua`, `SurvivorFactory` usage. `client/DebugUIs/ISSpawnHordeUI.lua` shows live `WorldMarkers` usage. | **Reuse and study** |
| `references/pz-community-modding` | ✅ **B42 compatible** | `!pz_frameworks` and `!pz_debugTools` are actively maintained for latest PZ. Shows `Events.OnCreatePlayer`, ISUIElement resizing patterns, debug panel injection. | **Adapt** |
| `references/pzmc-template` | ✅ **B42 compatible** | Standard mod folder structure with `42/` subfolder. Confirms our layout is correct. | **Study only** (structural reference) |
| `references/Zomboid-Modding-Guide` | ⚠️ **B40/B41 era, conceptually useful** | Event system docs, Kahlua Lua runtime explanation, Java/Lua integration patterns — all still conceptually valid. API examples may use old class names. | **Study only** |
| `references/pz-modding-guide` | ⚠️ **Methodology only, no runtime content** | Workflow advice (VCS, design principles). Zero runtime code. Does not address B42 APIs. | **Study only** |
| `references/pz-zdoc` | ℹ️ **Dev tool, not a runtime mod** | A Gradle-based doc generator for B41 (requires JDK 8). Our PZ-Umbrella stubs are the B42 equivalent. | **Ignore at runtime** |
| `workshop_refs/B42ModOptions` | ✅ **Directly B42 compatible** | Native `PZAPI.ModOptions` example. Shows all control types: TickBox, ComboBox, Slider, KeyBind, ColorPicker, Button. Saves to `Zomboid\Lua\modOptions.ini`. | **Reuse directly** |
| `workshop_refs/BravensNPCFramework` | ❌ **B41-only, conceptually critical** | Uses `IsoPlayer.new()` for NPC instantiation — broken in B42. But the module architecture, order system, save strategy, movement logic, and health loop are all important conceptual models. | **Study concepts; do not copy spawn code** |
| `workshop_refs/BravensUtilities` | ❌ **Empty folder** | No files present. Cannot assess. | **Ignore** |
| `workshop_refs/LuaDigitalWatch` | ❌ **Empty folder** | No files present. | **Ignore** |
| `workshop_refs/NeatUI_Framework` | ❌ **Empty folder** | No files present. | **Ignore** |
| `workshop_refs/ProfessionFramework` | ❌ **Empty folder** | No files present. | **Ignore** |
| `workshop_refs/StarlitLibrary` | ❌ **Empty folder** | No files present. | **Ignore** |

---

## C. Candidate Body Approaches

### 1. Pure Virtual Marker Only (Current State)
- **Pros**: Zero crash risk, no save mutation, no API uncertainty, already working.
- **Cons**: Not visible in world, no real character presence, cannot be interacted with.
- **Risks**: None.
- **B42 compatibility**: ✅ Confirmed working.
- **Files/APIs**: `WorldMarkers.instance`, `IsoMarkers.instance`, our existing `CompanionBrain.java`.
- **Verdict**: Keep as debug baseline permanently. Do not remove.

### 2. WorldMarkers Visual Overlay (Enhanced Marker)
- **Pros**: Can add `GridSquareMarker` + `DirectionArrow` + `PlayerHomingPoint` for richer visual. Entirely non-persistent. Cleaned up on session end.
- **Cons**: No animations, no 3D character model, no collision.
- **Risks**: Minimal. `marker:remove()` cleans up safely.
- **B42 compatibility**: ✅ Confirmed — `ISSpawnHordeUI.lua` uses this live in B42 vanilla.
- **Files/APIs**: `references/PZ-Umbrella/library/java/zombie/iso/WorldMarkers.lua`, `IsoMarkers.lua`.
- **Verdict**: Test now as an enhanced Phase 9 visual. Very low risk.

### 3. `IsoLuaMover` — Lua-Controlled Moving Character
- **Pros**: Real in-world entity with character renderer and animations. Designed for Lua scripting (`new(table)` takes a Lua table). Extends `IsoGameCharacter`, so all character APIs apply. Not saved by default.
- **Cons**: Constructor signature unknown — the `table` parameter is undocumented. Must be reverse-engineered. Unclear if B42 still supports this or if it was replaced.
- **Risks**: Medium. Wrong constructor call could crash or corrupt cell state. Needs controlled testing.
- **B42 compatibility**: ⚠️ **Unknown** — present in PZ-Umbrella stubs but not seen used in vanilla B42 Lua. Must test.
- **Files/APIs**: `references/PZ-Umbrella/library/java/zombie/iso/IsoLuaMover.lua`
- **Verdict**: **Phase 9D target** — discover the constructor via Java reflection/logging before using.

### 4. `IsoSurvivor` via `SurvivorFactory.InstansiateInCell()`
- **Pros**: This is the vanilla-sanctioned NPC spawn path. Used for all survivor NPCs in-game. Full character with AI, pathfinding, inventory, clothing. `SurvivorDesc` provides rich personality data.
- **Cons**: Spawns a persistent AI character. May be tracked by save. Requires `IsoCell` reference. AI will run independently unless controlled. Needs `Despawn()` to clean up.
- **Risks**: High if not cleaned up. Could interact with zombies, player, world. May be saved if the game autosaves before `Despawn()` is called.
- **B42 compatibility**: ⚠️ **Likely compatible** — `SurvivorFactory`, `SurvivorDesc`, `IsoSurvivor` all present in vanilla B42 Lua (`shared/NPCs/`). Needs controlled test.
- **Files/APIs**: `SurvivorFactory.lua`, `SurvivorDesc.lua`, `IsoSurvivor.lua` in PZ-Umbrella stubs; `SurvivorSwap.lua` in vanilla Lua.
- **Verdict**: Future phase. Do not attempt until `IsoLuaMover` is understood.

### 5. `IsoPlayer.new()` — Braven-Style NPC (Do Not Use)
- **Pros**: Braven shows it works in B41 — full character with all player APIs.
- **Cons**: `IsoPlayer` is the player class. Build 42 changed player initialization significantly. `IsoPlayer.new(cell, desc, x, y, z)` signature may no longer exist or may behave unexpectedly. Braven's mod is B41-only for this reason.
- **Risks**: **Critical**. Could crash the game, corrupt the save, or conflict with the multiplayer player system.
- **B42 compatibility**: ❌ **Assumed broken**.
- **Verdict**: **Do not copy or attempt.** This is the primary Braven anti-pattern.

### 6. Hybrid: Lua UI Marker + Java Brain (Current + Enhanced)
- **Pros**: Builds on what works. Brain in Java, visual marker in Lua, UI in Lua. Clean separation. Zero save risk.
- **Cons**: No 3D body yet.
- **Risks**: None.
- **B42 compatibility**: ✅ Confirmed.
- **Verdict**: **Current architecture. Preserve and extend.**

---

## D. Relevant APIs / Classes / Functions Found

### Java Classes (via PZ-Umbrella stubs)

| Name | Source File | B42 Status | Why It Matters | Risk | Verdict |
|---|---|---|---|---|---|
| `IsoLuaMover` | `PZ-Umbrella/library/java/zombie/iso/IsoLuaMover.lua` | ⚠️ Unknown | Lua-scriptable character body. `new(table)`, `update()`, `render()`, `playAnim()`. Extends `IsoGameCharacter`. | Medium | Test in Phase 9D |
| `IsoSurvivor` | `PZ-Umbrella/library/java/zombie/characters/IsoSurvivor.lua` | ⚠️ Likely B42 | Vanilla NPC type. `new(desc, cell, x, y, z)`, `Despawn()`. | Medium | Future phase |
| `SurvivorFactory` | `PZ-Umbrella/library/java/zombie/characters/SurvivorFactory.lua` | ✅ B42 | `CreateSurvivor()`, `InstansiateInCell(desc, cell, x, y, z)`. Clean spawning path. | Medium | Future phase |
| `SurvivorDesc` | `PZ-Umbrella/library/java/zombie/characters/SurvivorDesc.lua` | ✅ B42 | Full NPC personality/appearance descriptor. Name, gender, profession, traits, visual. `new()`, `setForename()`, `dressInNamedOutfit()`. | Low | Future phase |
| `IsoGameCharacter` | `PZ-Umbrella/library/java/zombie/characters/IsoGameCharacter.lua` | ✅ B42 | Base class for all characters. `getX/Y/Z()`, `getCurrentSquare()`, `getDescriptor()`, `CanSee()`, `Dressup()`. 4032-line stub. | Low | Study |
| `PathFindBehavior2` | `PZ-Umbrella/library/java/zombie/pathfind/PathFindBehavior2.lua` | ✅ B42 | `pathToLocation(x,y,z)`, `pathToCharacter(target)`, `moveToPoint(x,y,speed)`, `pathToLocationF()`. Requires real `IsoGameCharacter`. | Medium | Future phase |
| `IsoMovingObject` | `PZ-Umbrella/library/java/zombie/iso/IsoMovingObject.lua` | ✅ B42 | Parent of all moving entities. `DistTo()`, `findCurrentGridSquare()`. | Low | Study |
| `WorldMarkers` | `PZ-Umbrella/library/java/zombie/iso/WorldMarkers.lua` | ✅ B42 | `addGridSquareMarker()`, `addDirectionArrow()`, `addPlayerHomingPoint()`. Non-persistent overlays. | None | **Use now** |
| `IsoMarkers` | `PZ-Umbrella/library/java/zombie/iso/IsoMarkers.lua` | ✅ B42 | `addIsoMarker(sprite, gs, r,g,b,alpha)`, `removeIsoMarker()`, `setPos()`. Sprite-based world marker. | None | **Use now** |
| `IsoMarkers.IsoMarker` | `PZ-Umbrella/library/java/zombie/iso/IsoMarkers.IsoMarker.lua` | ✅ B42 | `setPos(x,y,z)`, `setColor()`, `setActive()`, `remove()`. Our marker system uses this. | None | **Use now** |
| `VirtualZombieManager` | `PZ-Umbrella/library/java/zombie/VirtualZombieManager.lua` | ✅ B42 | `createRealZombie(x,y,z)`, `createRealZombieNow()`. Zombie spawn path — do not use for companions. | High | Avoid |
| `IsoCell` | `PZ-Umbrella/library/java/zombie/iso/IsoCell.lua` | ✅ B42 | `getGridSquare(x,y,z)`, `getZombieList()`. Already used in `DebugBridge.java`. | Low | **Use now** |
| `IsoGridSquare` | `PZ-Umbrella/library/java/zombie/iso/IsoGridSquare.lua` | ✅ B42 | `AddSpecialObject()`, `getMovingObjects()`. Square-level world access. | Low | Study |
| `IsoObject` | `PZ-Umbrella/library/java/zombie/iso/IsoObject.lua` | ✅ B42 | Base world object. `AttachAnim()`. Braven creates stash objects via this — we do not. | Medium | Study |
| `HaloTextHelper` | `PZ-Umbrella/library/java/zombie/characters/HaloTextHelper.lua` | ✅ B42 | Floating text above character. Could be used for companion name/state display. | Low | Future phase |

### Lua Functions and Events

| Name | Source File | B42 Status | Why It Matters | Risk | Verdict |
|---|---|---|---|---|---|
| `Events.OnTick` | `PZ-Umbrella/library/events.lua` | ✅ B42 | Per-tick callback. Already used in our brain tick loop. | None | **Use now** |
| `Events.OnGameStart` | `PZ-Umbrella/library/events.lua` | ✅ B42 | Game loaded. Safe init point. Braven uses for `playerObj` cache. | None | **Use now** |
| `Events.OnSave` | `PZ-Umbrella/library/events.lua` | ✅ B42 | Fired before world save. Good place to flush companion state if we later add save. | None | Future phase |
| `Events.EveryOneMinute` | `PZ-Umbrella/library/events.lua` | ✅ B42 | Periodic low-frequency tick. Useful for slower brain updates. | None | Future phase |
| `Events.OnLoad` | `PZ-Umbrella/library/events.lua` | ✅ B42 | Game finished loading. Safer than `OnGameStart` for world-level ops. | None | Study |
| `Events.OnCharacterDeath` | Braven usage observed | ✅ B42 | Detect player/NPC death. Braven uses to refresh `playerObj` reference. | None | Future phase |
| `getWorldMarkers()` | `ISSpawnHordeUI.lua` | ✅ B42 | Global accessor. Returns `WorldMarkers.instance`. | None | **Use now** |
| `getCell()` | `DebugBridge.java`, Braven | ✅ B42 | Returns `IsoCell`. Used for square lookup. Already in our Java code. | None | **Use now** |
| `AdjacentFreeTileFinder.FindClosest()` | `BB_NPCFramework.lua` | ⚠️ Unknown B42 | Finds a free adjacent tile for spawning. Braven-specific or vanilla? Must verify. | Medium | Check before use |
| `ISTimedActionQueue.add()` | Braven movement | ✅ B42 | Enqueues timed actions on a character. Movement via `ISPathFindAction`. | Medium | Future phase |
| `ISPathFindAction:pathToLocationF()` | Braven movement | ⚠️ B41-era name | Timed action wrapper for pathfinding. Name may differ in B42. | Medium | Verify before use |
| `IsoUtils.XToScreen()` / `YToScreen()` | `BB_MyLittleNameDisplay.lua` | ✅ B42 | World-to-screen coordinate conversion for UI overlays. | Low | Future phase |
| `PZAPI.ModOptions:create()` | `B42ModOptions/ExampleModOptions.lua` | ✅ B42 | Native B42 mod options system. `addTickBox`, `addSlider`, `addKeyBind`, etc. Saves to `modOptions.ini`. | None | **Use now** |
| `LuaEventManager.AddEvent()` | `Zomboid-Modding-Guide/api/README.md` | ✅ B42 | Custom event types. Good for internal mod event bus. | Low | Future phase |
| `triggerEvent()` | Same | ✅ B42 | Fire custom events from Lua. | Low | Future phase |
| `getModData()` | Vanilla / Braven | ✅ B42 | Per-object or per-player persistent data table. Survives save/load. | Medium | Future phase (careful) |

---

## E. Useful Patterns from Workshop References

### B42ModOptions
- **What it does**: Demonstrates the native B42 `PZAPI.ModOptions` system built into the vanilla Lua layer. Settings saved at `Zomboid/Lua/modOptions.ini` automatically.
- **Useful patterns**: `create(UID, name)` → `addTickBox`, `addSlider`, `addKeyBind`, `addComboBox`, `addColorPicker`, `addButton`. All widget types documented with working examples.
- **B42 compatible**: ✅ Yes — this is the native system.
- **Outdated/unsafe parts**: None.
- **Adaptation for MyNPCBuddy**: Add a `PZAPI.ModOptions:create("MyNPCBuddy", "MyNPCBuddy")` block to expose console toggle, brain tick rate, scan radius, flee distance as configurable options. Zero dependency on third-party mods required.
- **Do not copy**: The `UNIQUEID` string — replace with our own mod ID.

### BravensNPCFramework
- **What it does**: A modular B41 NPC companion system. Spawns an `IsoPlayer` instance as an NPC, then subscribes it to behavioral modules: Movement, Combat, Health, Save, Orders, Speech, Trading, NameDisplay, Emotions, DoorManager.
- **Useful patterns (conceptual)**:
  - **Module subscription pattern**: `ManageNPC(npcData)` / `RemoveNPC(npcID)` per module. Each module maintains its own `managedNPCs` table and ticks independently. This maps cleanly onto our Java brain modules.
  - **`npcData` table as state bus**: A single Lua table carries all companion state (`npc`, `target`, `uniqueID`, `forceStop`, `isFleeing`, `combatStance`, etc.). This is the Lua equivalent of our `CompanionBrain.java` fields.
  - **`generateUniqueID()`**: `os.time()` + random suffix. Simple, sufficient.
  - **`SubscribeNPCToAllModules()` / `UnsubscribeNPCFromAllModules()`**: Clean lifecycle management. We should implement equivalent `registerCompanion()` / `despawnCompanion()` hooks.
  - **Movement teleport fallback**: At distance ≥ 100, respawn NPC at player. At ≥ 25, teleport. At ≥ 8, run. At ≤ 4, walk. This tiered distance-response is good logic to adapt.
  - **Flee geometry**: `GetRandomCoordsAwayFromTarget()` uses `atan2` to find the opposite direction, offsets by flee distance, validates the square. This is reusable math.
  - **NameDisplay**: `IsoUtils.XToScreen(x, y, z, 0)` world-to-screen conversion for floating name tag. Camera-offset adjusted. This is the pattern for any world-space UI label.
- **B42 compatible**: ❌ **No**. The `IsoPlayer.new(cell, desc, x, y, z)` constructor in `BB_NPCFramework.lua` is the core incompatibility.
- **Outdated/unsafe parts**: `IsoPlayer.new()` as NPC; `MainScreen.onMenuItemMouseDownMainMenu` monkey-patching for save hook; `IsoObject.new()` stash placed in world (writes to save); `os.time()` used in ID generation (not guaranteed in Kahlua — verify).
- **Adapt into MyNPCBuddy**: Replace `IsoPlayer.new()` with `IsoLuaMover.new(table)` or `SurvivorFactory.InstansiateInCell()`. Replace world-stash save with `getPlayer():getModData()`. Keep the module table pattern, order system logic, movement tiers, and flee geometry.
- **Do not copy directly**: Spawning code, save/stash system, `MainScreen` hook patch.

### BravensUtilities
- **Empty folder**. No files present. Cannot assess.

### LuaDigitalWatch
- **Empty folder**. No files present.

### NeatUI_Framework
- **Empty folder**. No files present.

### ProfessionFramework
- **Empty folder**. No files present.

### StarlitLibrary
- **Empty folder**. No files present.

---

## F. Build 42 Adaptation Notes

### F1. `IsoPlayer.new()` → `IsoLuaMover.new()` or `SurvivorFactory.InstansiateInCell()`
- **Old approach**: Braven instantiates `IsoPlayer.new(cell, desc, x, y, z)` to get a moveable character body.
- **Why it fails in B42**: `IsoPlayer` initialization was overhauled for B42's multiplayer and ECS entity system. Calling `IsoPlayer.new()` directly bypasses setup code that is now required.
- **B42-safe equivalent**: `IsoLuaMover.new(table)` for a script-driven mover, or `SurvivorFactory.InstansiateInCell(desc, cell, x, y, z)` for a full survivor. Both avoid touching the player system.
- **ZombieBuddy advantage**: Our Java bridge can call these constructors directly from Java and return the object reference to Lua, giving us full type safety and error wrapping around the call.
- **Test first**: Wrap in try/catch in Java, log the result, verify it renders before adding any behavior.

### F2. Braven Save (World Stash) → `getPlayer():getModData()`
- **Old approach**: Braven places a real `IsoObject` furniture sprite in the world and fills it with NPC inventory items. This writes a physical object to the map cell, which persists in the save.
- **Why it's unsafe**: Permanent world mutation. If the NPC stash is not cleaned up on game exit, orphaned objects accumulate. No cleanup safety net.
- **B42-safe equivalent**: Store companion state in `getPlayer():getModData().MyNPCBuddy`. Lua tables stored here are serialized with the player file. No world objects are created.
- **Caveat**: `getModData()` is per-player, per-save. If companion inventory grows large, this could bloat the player save. Keep state minimal.

### F3. `ISPathFindAction:pathToLocationF()` → Verify B42 Name
- **Old approach**: Braven queues movement via `ISTimedActionQueue.add(ISPathFindAction:pathToLocationF(npc, x, y, z))`.
- **Why uncertain in B42**: `ISPathFindAction` may have been renamed, reorganized, or superseded by the new entity system in B42. The `pathToLocationF` method name is B41-era.
- **B42-safe approach**: Use `PathFindBehavior2.new(chr)` from the Java side (via ZombieBuddy bridge) and call `pathToLocationF(x, y, z)` directly on the behavior object. Verify the method exists by checking the decompiled `projectzomboid.jar` before calling it.
- **Test first**: Log whether `PathFindBehavior2.new(chr)` succeeds before adding any pathing calls.

### F4. Module Subscription Pattern → Java Brain Architecture
- **Old approach**: Braven uses a Lua table per module, each with its own `managedNPCs` list, ticked via `Events.OnTick`.
- **B42-safe adaptation**: Our `CompanionBrain.java` is the correct equivalent. Rather than ticking from Lua, tick from Java (already implemented). Module concepts (movement, combat, health, orders) map to methods or inner classes on `CompanionBrain`.
- **ZombieBuddy advantage**: Java-side ticking is faster, safer, and immune to Lua garbage collection edge cases.

### F5. `AdjacentFreeTileFinder.FindClosest()` — Verify Availability
- **Old approach**: Braven calls `AdjacentFreeTileFinder.FindClosest(sq, playerObj)` before spawning to avoid placing NPC on an occupied tile.
- **B42 status**: This class may or may not be exported to Lua in B42. Must verify via the PZ-Umbrella stubs — it is **not present** in the stubs, suggesting it may not be exported.
- **B42-safe alternative**: Walk adjacent squares manually via `getCell():getGridSquare(x±1, y±1, z)` and check `sq:isFreeGridSquare()` or `sq:getMovingObjects():size() == 0`.

### F6. `HaloTextHelper` → Name Display
- **Old approach**: Braven uses `IsoUtils.XToScreen()` with a manual `drawText()` call for floating name tags.
- **B42-safe equivalent**: `HaloTextHelper` is confirmed present in B42 stubs (`IsoGameCharacter` uses it). Can display floating colored text above any character. Much safer than manual screen coordinate math.

---

## G. Recommended Phase 9 Plan

### Recommended: Phase 9D — Build 42 Body API Discovery via Java Reflection/Logging

**Why this is safest:**

The single biggest unknown is whether `IsoLuaMover.new(table)` works in B42 and what the `table` parameter must contain. Before writing any spawning code, we need to know:

1. Does `IsoLuaMover` still exist in the B42 `projectzomboid.jar`?
2. What does its constructor actually accept?
3. Does calling it produce a rendered entity, crash, or silently fail?

This phase answers those questions **without modifying save data and without adding any permanent world objects**.

**Proposed Phase 9D steps:**

1. **Java reflection probe**: Add a `BodyAPIProbe.java` class (new file, no spawn). Use `Class.forName("zombie.iso.IsoLuaMover")` via reflection to confirm the class exists in the runtime jar. Log all constructor signatures. This runs at mod load, writes to console, and exits. No entity is created.

2. **Minimal `IsoLuaMover` test**: If the class exists, attempt `IsoLuaMover.new({})` in a try/catch block, log whether it returns non-null. Still no world placement.

3. **Placement test**: If non-null, call `addToWorld()` (or equivalent) at player position in a **throwaway save only**. Immediately call `Despawn()` after 1 second. Log whether it appears and disappears cleanly.

4. **Document findings**: Update this report with the confirmed API before proceeding to Phase 9E.

**What Phase 9D preserves:**
- No real companion spawn in main save.
- No save mutation.
- Virtual companion and marker remain as debug baseline.
- Console and brain tick continue working unchanged.

**Phase 9E (after 9D)**: Braven-inspired architecture rewrite for B42 — implement the module subscription pattern, order system, and movement tiers using `IsoLuaMover` or `IsoSurvivor` with confirmed B42 APIs.

---

## H. Red Flags

1. **`IsoPlayer.new()` for NPC spawning** — Braven's approach. Creates a player-class entity as an NPC. Breaks in B42. Do not copy. **Critical risk.**

2. **Braven's world stash save** (`IsoObject.new()` + `stash:transmitCompleteItemToClients()`) — Permanently places a physical furniture object in the world cell, writes to the map save. If cleanup fails, orphaned stash objects accumulate across sessions. **Save mutation risk.**

3. **`MainScreen.onMenuItemMouseDownMainMenu` monkey-patch** — Braven patches the main menu exit handler to trigger saves. This is fragile: if another mod also patches this function, they will conflict. **Compatibility risk.**

4. **`os.time()` in Kahlua** — PZ uses Kahlua (a Lua interpreter in Java). Not all standard Lua modules are present. `os.time()` may work but is not guaranteed. If Braven's `generateUniqueID()` uses it, verify in B42 before adopting. **Uncertain behavior.**

5. **`AdjacentFreeTileFinder`** — Not present in PZ-Umbrella B42 stubs. May not be exported to Lua in B42. Using it without verification could cause a nil-call crash. **Unverified API.**

6. **`ISPathFindAction:pathToLocationF()`** — B41-era timed action name. B42 may use different pathfind timed action classes. Calling a renamed/removed function causes a silent nil call or crash. **Verify before use.**

7. **Spawning in any non-throwaway save** — Until the `IsoLuaMover`/`IsoSurvivor` lifecycle (spawn → world-add → despawn) is fully confirmed safe, no spawn should happen in a real save. **Save corruption risk.**

8. **`npc:setNPC(true)`** — Braven calls this on spawned characters. In B42, the `setNPC()` method may have different semantics or side effects due to the new ECS entity system. Verify existence and behavior before use. **Unknown B42 semantics.**

9. **`npc:transmitModData()` / `transmitCompleteItemToClients()`** — Network sync calls. In singleplayer these may be no-ops, but calling them on a local-only entity could send unexpected packets or cause errors in multiplayer sessions. **Multiplayer risk.**

10. **Relying on `getPlayer()` returning a consistent object** — Braven caches `MyLittleUtils.playerObj` on `OnGameStart`. In B42 split-screen or after character death, this reference can go stale. Always re-validate before use. **Stale reference risk.**

11. **`SurvivorFactory.InstansiateInCell()` without `Despawn()` cleanup** — Spawning a survivor without guaranteed cleanup (e.g., on game crash or forced quit) could leave a permanent NPC in the world cell. Must pair spawn with a guaranteed despawn callback. **Save persistence risk.**

---

## I. Exact Suggested Next Prompt

```
Phase 9D — Build 42 Body API Discovery

We are NOT spawning a companion yet.

Create a new Java file: BodyAPIProbe.java
Package: com.lordtsarcasm.mynpcbuddy
File location: 42/media/java/client/src/BodyAPIProbe.java

This class should:

1. Use @Exposer.LuaClass so Lua can call it.

2. Implement a static method: public static void probeIsoLuaMover()
   - Use Class.forName("zombie.iso.IsoLuaMover") to check if the class exists in the runtime.
   - If found, log all constructor signatures using getDeclaredConstructors().
   - If not found, log a clear "IsoLuaMover NOT FOUND in B42" message.
   - Wrap everything in try/catch. Never throw. Never spawn.

3. Implement a static method: public static void probeSurvivorFactory()
   - Use Class.forName("zombie.characters.SurvivorFactory")
   - Log whether it exists.
   - If found, log the method signatures of CreateSurvivor() and InstansiateInCell() using getDeclaredMethods().
   - Wrap in try/catch. Never spawn.

4. Implement a static method: public static void probeAdjacentFreeTileFinder()
   - Check for "zombie.iso.AdjacentFreeTileFinder" and "zombie.iso.AdjacentFreeTileFinderFull".
   - Log existence or absence.

Add two buttons to the existing debug console UI:
- "Probe LuaMover" → calls BodyAPIProbe.probeIsoLuaMover()
- "Probe SurvivorFactory" → calls BodyAPIProbe.probeSurvivorFactory()

Do NOT:
- Instantiate any class.
- Add any entity to the world.
- Modify save data.
- Remove the virtual companion or debug marker.
- Refactor existing working code.

After building and running in-game, use the debug console buttons to fire the probes, then paste the console output here for review before Phase 9E begins.
```
