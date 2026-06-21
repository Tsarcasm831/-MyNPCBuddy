# Phase 9E — IsoLuaMover Constructor Table Discovery Report
> Source: javap -verbose decompile of zombie/iso/IsoLuaMover.class from
> E:\SteamLibrary\steamapps\common\ProjectZomboid\projectzomboid.jar
> Class file major version: 69 (Java 25 / Build 42 runtime)
> No code was changed. No class was instantiated. No world objects created.

---

## A. IsoLuaMover Constructor Findings

### Constructor Signature (confirmed from bytecode)

```java
public IsoLuaMover(se.krka.kahlua.vm.KahluaTable table)
```

Internally it calls:
```java
super(null, 0f, 0f, 0f);  // IsoGameCharacter(IsoCell=null, x=0, y=0, z=0)
```

This is the **full constructor body** reconstructed from bytecode (lines 234–255 of verbose output):

```java
public IsoLuaMover(KahluaTable table) {
    super(null, 0f, 0f, 0f);                           // IsoGameCharacter init: cell=null, pos=0,0,0
    this.sprite = IsoSprite.CreateSprite(IsoSpriteManager.instance);  // blank sprite
    this.luaMoverTable = table;                        // stores the entire table
    if (this.def == null) {
        this.def = IsoSpriteInstance.get(this.sprite); // sprite instance
    }
}
```

### What the KahluaTable is NOT used for in the constructor

**The constructor does NOT call `rawget` on the table at all.**
The table is stored verbatim as `this.luaMoverTable` and only used later:
- In `update()`: `rawget("update")` → calls `table.update(self)` via `pcallvoid`
- In `render()`: `rawget("postrender")` → calls `table.postrender(self, col, bDoAttached)` via `pcallvoid`

### Table Keys Read (confirmed from bytecode constant pool)

| Key String | Where Used | Required? |
|---|---|---|
| `"update"` | `update()` method, every game tick | Optional — missing key is silently skipped |
| `"postrender"` | `render()` method, every render frame | Optional — missing key is silently skipped |

**That is the complete list. Only two keys are ever rawget'd from the table.**

### Required vs Optional Fields

| Item | Required? | Notes |
|---|---|---|
| `table.update` | **Optional** | Called per tick. If nil, silently skipped (pcallvoid with null fn = no-op) |
| `table.postrender` | **Optional** | Called per render. If nil, silently skipped |
| `table.x/y/z` | **Not used** | Position is NOT read from the table. Position is set separately via `setX/setY/setZ` or `setPosition()` inherited from `IsoMovingObject` |
| `table.cell` | **Not used** | Cell is passed as `null` to the superclass constructor |
| `table.sprite` | **Not used** | Sprite is created internally by `IsoSprite.CreateSprite(IsoSpriteManager.instance)` |

### Minimum Valid Table

```lua
local moverTable = {}
-- completely empty table is valid
local mover = IsoLuaMover.new(moverTable)
```

The constructor will **not crash with an empty table**. It creates a blank sprite and stores the table reference. No table keys are required.

### Callbacks Invoked by the Java Side

These are the **only two Lua callbacks** Java will call back into:

```lua
moverTable.update = function(self)
    -- called every tick by IsoGameCharacter.update()
end

moverTable.postrender = function(self, col, bDoAttached)
    -- called every render pass, after the sprite is drawn
    -- col is ColorInfo, bDoAttached is boolean
end
```

Both are caught in `try/catch(Exception)` on the Java side — Lua errors inside them will be logged but **will not crash the game**.

---

## B. Lifecycle Findings

### How to Create

From Lua, using the ZombieBuddy Lua bridge (since `KahluaTable` = Lua table):

```lua
local moverTable = {}
local mover = IsoLuaMover.new(moverTable)
-- mover is now a Java IsoLuaMover instance
-- position is 0,0,0 — cell is null — NOT in world yet
```

From Java (e.g. a new `BodyFactory.java`), reflectively confirmed:
```java
// constructor: IsoLuaMover(KahluaTable table)
// table can be any KahluaTable instance, even empty
```

### How to Place in World

`IsoLuaMover` inherits the full `IsoObject` → `IsoMovingObject` → `IsoGameCharacter` chain.

Confirmed methods from decompiled superclasses:

```java
// Set position BEFORE addToWorld (from IsoMovingObject)
mover.setPosition(float x, float y, float z);
// OR
mover.setX(float x); mover.setY(float y); mover.setZ(float z);

// Add to world (from IsoObject)
mover.addToWorld();
// This registers the object with the cell and makes it visible/rendered
```

From Lua:
```lua
mover:setPosition(x, y, z)
mover:addToWorld()
```

**Important**: The constructor passes `cell=null` and `x=y=z=0` to `IsoGameCharacter`. You MUST call `setPosition()` and `addToWorld()` explicitly. The object is not in the world after construction.

### How to Remove Safely

Three options confirmed from decompiled bytecode, in order of preference:

```lua
-- Option 1: cleanest, removes from world and all tracking lists
mover:Despawn()              -- inherited from IsoMovingObject (confirmed present)

-- Option 2: removes from cell/world but may leave tracking state
mover:removeFromWorld()      -- inherited from IsoObject (confirmed present)

-- Option 3: removes from square only (not full world removal)
mover:removeFromSquare()     -- inherited from IsoMovingObject
```

**Prefer `Despawn()`** — it is the safe lifecycle exit intended for NPC-type objects.

### Persistence / Save Risk

**`IsoLuaMover` is NOT save-safe by default.**

`IsoGameCharacter` (the superclass) has standard character save serialization. Whether the game saves `IsoLuaMover` instances depends on whether the cell's character list is serialized. **This is unknown and must be tested.**

**Mitigation**: Always call `Despawn()` in:
- `Events.OnSave` (before save happens)
- `Events.OnMainMenuEnter` / game exit
- A `defer`-style cleanup on any error path

**The current virtual companion + marker does not spawn anything, so there is zero save risk today.**

### Sprite / Rendering Notes

- The sprite starts as a blank `IsoSprite` (no texture loaded).
- To show something visible, you must call `playAnim(name, seconds, looped, playing)` to set an animation, OR load a sprite by name into the internal `sprite` field.
- Without a valid animation, the object renders as invisible (blank sprite).
- `render()` applies hard-coded offsets: `offsetY - 100f`, `offsetX - 34f` — these are the standard isometric character render offsets.
- `getObjectName()` returns the string `"IsoLuaMover"`.

---

## C. ISBaseMover — The Lua Wrapper System

The PZ-Umbrella stubs document `ISBaseMover` as the **Lua-side wrapper class** for `IsoLuaMover`. Key confirmed findings:

- `ISBaseMover.javaObject` holds the `IsoLuaMover` Java instance
- `ISBaseMover:placeInWorld(x, y, z)` is the intended Lua API for world placement (wraps `setPosition` + `addToWorld`)
- `ISBaseMover:removeFromWorld()` is the Lua-side cleanup
- `ISBaseMover:playAnim(name, seconds, looped, animate)` wraps the Java `playAnim()`
- `ISBaseMover:new()` creates the wrapper and constructs the `IsoLuaMover`

**Critical finding**: `ISBaseMover` is **not present in B42's live Lua files** (`E:\SteamLibrary\steamapps\common\ProjectZomboid\media\lua\`). It exists only in the PZ-Umbrella stubs (doc/type stubs, not runtime code). The `Rabbit` class (subclass of `ISBaseMover`) is also absent from the live Lua tree.

**Interpretation**: Either `ISBaseMover` was removed in B42 or was never deployed to the live game (it may be an internal TIS test/dev file that appears in the stubs from decompilation). The Java class `IsoLuaMover.class` **is** present in the runtime jar (confirmed by Phase 9D probe), but there is no corresponding Lua wrapper in use.

**Consequence**: We cannot `require "ISBaseMover"` — it doesn't exist at runtime in B42. We must either write our own Lua wrapper (straightforward given the bytecode analysis) or call `IsoLuaMover` from Java via ZombieBuddy.

---

## D. Red Flags

1. **`ISBaseMover` / `Rabbit` are absent from B42 live Lua.** These classes appear in PZ-Umbrella stubs but have zero corresponding `.lua` files in the actual B42 install. `IsoLuaMover` may be a stub/legacy class kept in the jar but no longer actively used by TIS in B42. **Risk: medium — class is present but may be untested in B42's entity system.**

2. **`IsoGameCharacter` superclass with `cell=null`.** The constructor explicitly passes `null` for `IsoCell`. This means the object starts orphaned — no cell reference. Calling world-interaction methods before `addToWorld()` could NPE internally. **Risk: low if sequence is respected (construct → setPosition → addToWorld).**

3. **Save persistence unknown.** `IsoGameCharacter` has save serialization hooks. If the game cell serializes all `IsoGameCharacter` instances on its lists, a `IsoLuaMover` left in the world across a save cycle could corrupt the save (no matching serializer for this type). **Risk: high if not cleaned up before save. Mitigation: always `Despawn()` in `OnSave`.**

4. **No `Despawn()` defined on `IsoLuaMover` itself** — it inherits from `IsoMovingObject`. The inherited `Despawn()` may not clean up `IsoGameCharacter`-specific state (AI states, body damage, etc.) that gets initialized during `addToWorld()`. **Risk: low-medium — test Despawn cleanup carefully.**

5. **Blank sprite = invisible but not absent.** The mover renders as invisible if no anim is loaded — but it still exists in the world's object list. This could cause pathfinding or AI queries to interact with an invisible entity. **Risk: low — set `setInvisible(true)` explicitly until a sprite is loaded.**

6. **`update()` calls `IsoGameCharacter.update()` unconditionally** (bytecode line 385). This means the full character AI/behavior update runs on every tick once the mover is in world. In B42 with the ECS-based character system, this may trigger state machines expecting a fully initialized character. **Risk: medium — test in a throwaway save, watch for NPEs in console.txt.**

7. **No vanilla B42 usage example exists.** `IsoLuaMover` is used in zero B42 Lua files. We are in uncharted territory. Every step must be tested in a throwaway save with console monitoring. **Risk: medium-high for instability, low for data loss if cleanup is correct.**

8. **`IsoSpriteManager.instance` must be non-null at construction time.** If `IsoLuaMover.new()` is called too early (before the sprite manager is initialized), the constructor will NPE at `IsoSprite.CreateSprite(IsoSpriteManager.instance)`. Must only construct inside `OnGameStart` or later. **Risk: low if construction is gated behind `OnGameStart`.**

---

## E. Recommended Phase 9F Test

**The smallest safe test that produces useful data:**

### Phase 9F-A — Instantiate Only (No World Placement)

Goal: confirm the constructor does not crash, confirm the Java object is non-null, log it.

```java
// In BodyAPIProbe.java — new method: testInstantiateOnly()
// DO NOT call addToWorld. DO NOT call setPosition.
// Wrap in try/catch. Log result. Return string to Lua.
public static String testInstantiateOnly() {
    try {
        // Construct with empty Kahlua table
        // This requires creating a KahluaTable — see note below
        // If that's not available from Java, do this from Lua instead
        return "instantiate test: see Lua version";
    } catch (Exception e) {
        return "EXCEPTION: " + e.getMessage();
    }
}
```

**Easier path — do this from Lua** (ZombieBuddy already bridges `IsoLuaMover` to Lua):

```lua
-- Lua-side Phase 9F-A button handler (new console button: "Test: New Only")
function MyNPCConsole:onTestNewOnly()
    local ok, result = pcall(function()
        local t = {}
        local mover = IsoLuaMover.new(t)
        if mover ~= nil then
            return "IsoLuaMover.new() OK, obj=" .. tostring(mover)
        else
            return "IsoLuaMover.new() returned nil"
        end
        -- DO NOT call addToWorld. mover is now garbage-collected when t goes out of scope.
    end)
    if not ok then
        self:addLine("TestNewOnly ERROR: " .. tostring(result), 1, 0.3, 0.3)
    else
        self:addLine(result, 0.3, 1, 0.5)
    end
end
```

This is **zero risk**: if `addToWorld()` is never called, the object never enters any cell list and cannot be saved or interact with the world. When `t` goes out of scope, Kahlua GC will clean it up.

### Phase 9F-B — Instantiate + Immediate Despawn (if 9F-A succeeds)

```lua
local t = {}
local mover = IsoLuaMover.new(t)
if mover ~= nil then
    mover:Despawn()   -- call Despawn on an un-added object — should be a no-op
    self:addLine("Despawn on un-added mover: OK", 0.3, 1, 0.5)
end
```

### Phase 9F-C — Throwaway Save: Place + Immediate Remove (only after 9F-A and 9F-B pass)

```lua
local player = getSpecificPlayer(0)
local x, y, z = player:getX(), player:getY(), player:getZ()
local t = {}
t.update = function(self) end   -- no-op update
local mover = IsoLuaMover.new(t)
mover:setPosition(x + 2, y, z)
mover:addToWorld()
-- Schedule removal 1 tick later via Events.OnTick
local removeNext
removeNext = function()
    Events.OnTick.Remove(removeNext)
    pcall(function() mover:Despawn() end)
    console:addLine("Mover despawned", 0.3, 1, 0.5)
end
Events.OnTick.Add(removeNext)
```

**Only run Phase 9F-C in a throwaway save** with console.txt monitoring open.

### Alternative if IsoLuaMover Proves Unstable

Use enhanced `WorldMarkers` overlays with `IsoMarkers.addIsoMarker(sprite, gs, r, g, b, a)` for a visible sprite-based world marker. Zero character AI, zero save risk. Confirmed B42-stable.

---

## F. Summary Table

| Question | Answer | Source |
|---|---|---|
| What fields does IsoLuaMover read from the KahluaTable? | Only `"update"` and `"postrender"` function keys, lazily at tick/render time | bytecode rawget constants |
| Does the table need x/y/z? | No — position set separately via setPosition() | constructor bytecode |
| Does the table need callbacks? | No — both are optional, missing = silently skipped | pcallvoid pattern |
| Does it require a cell or square? | No — constructor passes cell=null | bytecode line 235 |
| Does it automatically add itself to the world? | No — must call addToWorld() explicitly | IsoObject.addToWorld() |
| Does it inherit addToWorld/removeFromWorld? | Yes — from IsoObject | javap -p IsoObject.class |
| Is there a safe remove/despawn method? | Yes — Despawn() from IsoMovingObject | javap -p IsoMovingObject.class |
| Is there vanilla Lua code demonstrating usage? | No — ISBaseMover/Rabbit absent from B42 live files | live Lua tree search |
| Is IsoLuaMover for visible movers or test only? | Designed for real visible movers (render() draws sprite, update() runs AI) but currently unused in B42 live code | bytecode + live file search |
