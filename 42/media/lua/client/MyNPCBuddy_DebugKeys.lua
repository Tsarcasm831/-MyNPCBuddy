-- MyNPCBuddy Phase 8B: polished virtual companion debug marker overlay
-- Press F9 to toggle the console panel and probe player position.

local KEY_F9 = Keyboard.KEY_F9
local MAX_LINES = 200
local BRAIN_TICK_INTERVAL = 1000 -- 1 second in ms

-- Brain Tick timer state (module-level to persist across console recreations)
local brainTickTimer = nil
local brainTickRunning = false

-- Companion state (module-level to persist across console recreations)
local companionEnabled = false
local currentOrder = "FOLLOW"

-- Marker state
local markerEnabled = false
local markerDetail = "BASIC"  -- "BASIC" or "FULL"

-- Active test mover (Phase 9F-C: one-tick world placement test)
local activeTestMover = nil

-- Active test zombie NPC (Phase 9F: Bandit-style IsoZombie body test)
local testZombieNpc = nil
local zombiePassivityLogged = false
local bumpTypeIdleEnabled = false
local bumpTypeFirstLogged = false
local bumpTypeExitPending = false
local bumpTypeExitStartedAt = 0
local bumpTypeExitLogged = false

-- Walk Test state (SP-only test)
local walkTestActive = false
local walkTestTarget = nil
local walkTestStartedAt = 0
local walkTestPhase = "idle"
local walkTestFirstLogged = false
local hostileInterceptLogged = false
local walkPathReissueNeeded = false
local walkPathReissueLogged = false
local walkTypeDiagnosticLogged = false

-- Idle-suspension state for walk-test (releases MNB_Idle bump during locomotion)
local idleSuspensionActive = false
local idleSuspensionStartedAt = 0
local idleSuspensionExitLogged = false

-- State-transition diagnostics (Phase: pumpkin-shamble investigation)
local stateDiagActive = false
local stateDiagPrev = {}
local stateDiagChangeCount = 0

-- Master debug flag for verbose state-transition diagnostics (StateDiag, walk-type, first-tick)
local STATE_DIAG_DEBUG = false

-- Console size (persisted within the session)
local consoleW = 680
local consoleH = 500
local CONSOLE_MIN_W = 580
local CONSOLE_MIN_H = 400

-- Button layout constants
local BTN_H       = 20   -- button height
local BTN_GAP     = 5    -- horizontal gap between buttons
local ROW_GAP     = 6    -- vertical gap between rows
local BTN_PAD_BOT = 24   -- padding below last row (clears ISCollapsableWindow resize grip)
local BTN_PAD_TOP = 2    -- padding above first row (between log and buttons)
local TITLE_H     = 20   -- ISCollapsableWindow title bar height
local NUM_ROWS    = 10   -- total button rows

-- Compute the total height consumed by the button area
local function btnAreaHeight()
    return (BTN_H * NUM_ROWS)
        + (ROW_GAP * (NUM_ROWS - 1))
        + BTN_PAD_BOT
        + BTN_PAD_TOP
end

-- Compute per-row Y position (row 1 = topmost, row NUM_ROWS = bottommost)
-- windowH is self.height
local function rowY(windowH, row)
    local bottomOfLastRow = windowH - BTN_PAD_BOT - BTN_H
    return bottomOfLastRow - (NUM_ROWS - row) * (BTN_H + ROW_GAP)
end

-- Compute the listbox height given window height
local function listboxH(windowH)
    local h = windowH - TITLE_H - 4 - btnAreaHeight()
    if h < 40 then h = 40 end
    return h
end

-- ── Console window ────────────────────────────────────────────────────────────

-- Helper: creates and registers a button, returns it.
-- Does NOT set position — reflowRows() does that.
local function makeBtn(parent, label, handler, borderCol)
    local btn = ISButton:new(0, 0, 0, BTN_H, label, parent, handler)
    if borderCol then btn.borderColor = borderCol end
    parent:addChild(btn)
    return btn
end

MyNPCConsole = ISCollapsableWindow:derive("MyNPCConsole")

function MyNPCConsole:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.title       = "MyNPCBuddy Console"
    o.resizable   = true
    o.lines       = {}
    o.scrollIndex = 1
    o.lineHeight  = 16
    o.padX        = 6
    setmetatable(o, self)
    self.__index = self
    return o
end

function MyNPCConsole:initialise()
    ISCollapsableWindow.initialise(self)
end

-- ── Marker overlay (ISPanel-based, uses verified PZ render API) ──────────────

NPCMarkerOverlay = ISPanel:derive("NPCMarkerOverlay")

local markerRenderErrorLogged = false

function NPCMarkerOverlay:new()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local o = ISPanel.new(self, 0, 0, sw, sh)
    o.background = false
    o.anchorLeft   = true
    o.anchorRight  = false
    o.anchorTop    = true
    o.anchorBottom = false
    setmetatable(o, self)
    self.__index = self
    return o
end

function NPCMarkerOverlay:initialise()
    ISPanel.initialise(self)
end

function NPCMarkerOverlay:isWantMouseEvents()
    return false
end

function NPCMarkerOverlay:prerender()
    -- keep fullscreen in case of resolution change
    self:setWidth(getCore():getScreenWidth())
    self:setHeight(getCore():getScreenHeight())
end

function NPCMarkerOverlay:render()
    if not markerEnabled then return end

    local ok, err = pcall(function()
        if not DebugBridge then return end
        if not DebugBridge.companionHasVirtualPos() then return end

        local wx = DebugBridge.companionGetVirtualX()
        local wy = DebugBridge.companionGetVirtualY()
        local wz = DebugBridge.companionGetVirtualZ()
        if wx == nil or wy == nil then return end

        local playerNum = 0
        local sx = isoToScreenX(playerNum, wx, wy, wz) - getPlayerScreenLeft(playerNum)
        local sy = isoToScreenY(playerNum, wx, wy, wz) - getPlayerScreenTop(playerNum)
        if sx == nil or sy == nil then return end

        -- Fetch state from bridge
        local action = "FOLLOW_PLAYER"
        local ok2, act = pcall(function() return DebugBridge.companionGetDesiredAction() end)
        if ok2 and act then action = act end

        local order = "FOLLOW"
        local ok3, ord = pcall(function() return DebugBridge.companionGetCurrentOrder() end)
        if ok3 and ord then order = ord end

        local danger = "SAFE"
        local ok4, dng = pcall(function() return DebugBridge.companionGetDangerState() end)
        if ok4 and dng then danger = dng end

        local dist = 0.0
        local ok5, d = pcall(function() return DebugBridge.companionDistToPlayer() end)
        if ok5 and d then dist = d end

        -- Color by action
        local r, g, b = 0.2, 1.0, 0.2   -- green  = FOLLOW_PLAYER
        if action == "HOLD_POSITION" then
            r, g, b = 1.0, 0.85, 0.1    -- yellow = STAY
        elseif action == "SCOUT_AREA" then
            r, g, b = 0.7, 0.2, 1.0     -- purple = SCOUT
        elseif action == "FLEE" then
            r, g, b = 1.0, 0.2, 0.2     -- red    = FLEE
        elseif action == "WAIT_NO_PLAYER" then
            r, g, b = 0.5, 0.5, 0.5     -- grey   = waiting
        end

        -- Danger tints the border
        local br, bg, bb = r, g, b
        if danger == "CAUTION" then
            br, bg, bb = 1.0, 0.6, 0.0  -- orange border
        elseif danger == "DANGER" then
            br, bg, bb = 1.0, 0.0, 0.0  -- red border
        end

        local sq = 14
        local half = sq / 2
        local lx = sx - half
        local ly = sy - half

        -- Player-to-marker direction line (thin 1px rect strips)
        local player = getSpecificPlayer(0)
        if player ~= nil then
            local px = isoToScreenX(playerNum, player:getX(), player:getY(), player:getZ()) - getPlayerScreenLeft(playerNum)
            local py = isoToScreenY(playerNum, player:getX(), player:getY(), player:getZ()) - getPlayerScreenTop(playerNum)
            if px ~= nil and py ~= nil then
                -- Draw dashed line as small squares spaced 6px apart
                local dx = sx - px
                local dy = sy - py
                local len = math.sqrt(dx*dx + dy*dy)
                if len > 1 then
                    local steps = math.floor(len / 6)
                    local ux = dx / len
                    local uy = dy / len
                    for i = 1, steps - 1 do
                        local dotx = px + ux * i * 6 - 1
                        local doty = py + uy * i * 6 - 1
                        self:drawRect(dotx, doty, 2, 2, 0.45, r, g, b)
                    end
                end
            end
        end

        -- Dark shadow (1px halo)
        self:drawRect(lx - 1, ly - 1, sq + 2, sq + 2, 0.75, 0.0, 0.0, 0.0)
        -- Filled color square
        self:drawRect(lx, ly, sq, sq, 0.85, r, g, b)
        -- Danger-tinted border
        self:drawRectBorder(lx, ly, sq, sq, 1.0, br, bg, bb)
        -- Extra outer border when DANGER
        if danger == "DANGER" then
            self:drawRectBorder(lx - 1, ly - 1, sq + 2, sq + 2, 0.6, 1.0, 0.0, 0.0)
        end

        -- Label
        local label
        if markerDetail == "FULL" then
            -- Line 1: order + action
            local line1 = order .. " > " .. action
            -- Line 2: dist + danger
            local line2 = string.format("dist=%.1f  %s", dist, danger)
            local lh = getTextManager():getFontHeight(UIFont.Small)
            self:drawText(line1, lx - 4, ly - lh * 2 - 2, r, g, b, 1.0, UIFont.Small)
            self:drawText(line2, lx - 4, ly - lh - 1, br, bg, bb, 1.0, UIFont.Small)
        else
            -- BASIC: compact single line
            local shortAction = action
            if action == "FOLLOW_PLAYER"  then shortAction = "FOLLOW"
            elseif action == "HOLD_POSITION" then shortAction = "STAY"
            elseif action == "SCOUT_AREA"    then shortAction = "SCOUT"
            elseif action == "WAIT_NO_PLAYER" then shortAction = "WAIT" end
            label = string.format("NPC %s dist=%.1f %s", shortAction, dist, danger)
            local lh = getTextManager():getFontHeight(UIFont.Small)
            self:drawText(label, lx - 4, ly - lh - 2, r, g, b, 1.0, UIFont.Small)
        end
    end)

    if not ok and not markerRenderErrorLogged then
        markerRenderErrorLogged = true
        print("[MyNPCBuddy] Marker render error (logged once): " .. tostring(err))
    end
end

-- Module-level overlay instance (created once on load)
local markerOverlay = nil

local function getOrCreateMarkerOverlay()
    if markerOverlay ~= nil and not markerOverlay.removed then
        return markerOverlay
    end
    markerOverlay = NPCMarkerOverlay:new()
    markerOverlay:initialise()
    markerOverlay:instantiate()
    markerOverlay:addToUIManager()
    markerOverlay:setVisible(false)
    return markerOverlay
end

Events.OnGameStart.Add(function()
    getOrCreateMarkerOverlay()
end)

-- ── Console window ────────────────────────────────────────────────────────────

-- Place buttons in a row: returns { btn, nextX } tracking state.
-- Usage: cursor = self:startRow(rowNum)  then  cursor = self:placeBtn(cursor, btn, width)
function MyNPCConsole:startRow(rowNum)
    return { x = self.padX, y = rowY(self.height, rowNum) }
end

function MyNPCConsole:placeBtn(cursor, btn, w)
    btn:setX(cursor.x)
    btn:setY(cursor.y)
    btn:setWidth(w)
    return { x = cursor.x + w + BTN_GAP, y = cursor.y }
end

-- Full reflow: resize listbox + reposition every button row.
function MyNPCConsole:reflowRows()
    local lh = listboxH(self.height)
    if self.listbox then
        self.listbox:setWidth(self.width - self.padX * 2)
        self.listbox:setHeight(lh)
    end

    local c

    -- Row 6 (bottom): Debug basics
    c = self:startRow(6)
    c = self:placeBtn(c, self.btnProbe,     80)
    c = self:placeBtn(c, self.btnClear,     50)
    c = self:placeBtn(c, self.btnScan,      76)
    c = self:placeBtn(c, self.btnBrainTick, 96)

    -- Row 5: Companion / Marker tools
    c = self:startRow(5)
    c = self:placeBtn(c, self.btnCompanion,       100)
    c = self:placeBtn(c, self.btnCompanionStatus,  110)
    c = self:placeBtn(c, self.btnResetVirtualPos,  116)
    c = self:placeBtn(c, self.btnMarker,            82)
    c = self:placeBtn(c, self.btnMarkerDetail,      86)

    -- Row 4: Orders
    c = self:startRow(4)
    c = self:placeBtn(c, self.btnOrderFollow, 90)
    c = self:placeBtn(c, self.btnOrderStay,   82)
    c = self:placeBtn(c, self.btnOrderScout,  82)

    -- Row 3: API probes
    c = self:startRow(3)
    c = self:placeBtn(c, self.btnProbeLuaMover,        96)
    c = self:placeBtn(c, self.btnProbeSurvivorFactory,  96)
    c = self:placeBtn(c, self.btnProbeIsoSurvivor,      96)
    c = self:placeBtn(c, self.btnProbePathfind,         86)
    c = self:placeBtn(c, self.btnProbeTileFinder,       86)

    -- Row 2: Body constructor tests
    c = self:startRow(2)
    c = self:placeBtn(c, self.btnTestNewOnly,    108)
    c = self:placeBtn(c, self.btnTestNewDespawn, 128)

    -- Row 1 (top of button area): Body live world tests
    c = self:startRow(1)
    c = self:placeBtn(c, self.btnPlace1Tick,     116)
    c = self:placeBtn(c, self.btnPlace1Sec,      108)
    c = self:placeBtn(c, self.btnVisible3Sec,    114)
    c = self:placeBtn(c, self.btnCleanupMover,   124)

    -- Row 7: NPC body tests
    c = self:startRow(7)
    c = self:placeBtn(c, self.btnSpawnNpc,       140)
    c = self:placeBtn(c, self.btnDespawnNpc,     150)
    c = self:placeBtn(c, self.btnNpcStatus,      120)
    c = self:placeBtn(c, self.btnNpcModelStatus, 140)

    -- Row 8: render-trace proof readouts (Test A / Test B)
    c = self:startRow(8)
    c = self:placeBtn(c, self.btnNpcRenderTrace,   150)
    c = self:placeBtn(c, self.btnNpcSqRenderTrace, 160)

    -- Row 9 (bottom): Zombie NPC body test (Phase 9F)
    c = self:startRow(9)
    c = self:placeBtn(c, self.btnSpawnZombieNpc,   170)
    c = self:placeBtn(c, self.btnDespawnZombieNpc, 180)
    c = self:placeBtn(c, self.btnZombieNpcStatus,  160)
    c = self:placeBtn(c, self.btnBumpTypeIdle,    140)

    -- Row 10: Walk Test
    c = self:startRow(10)
    c = self:placeBtn(c, self.btnWalkTest, 160)
end

function MyNPCConsole:createChildren()
    ISCollapsableWindow.createChildren(self)

    -- Scrollable log area
    self.listbox = ISScrollingListBox:new(
        self.padX, TITLE_H + 4,
        self.width - self.padX * 2, listboxH(self.height)
    )
    self.listbox.font             = UIFont.Small
    self.listbox.itemheight       = getTextManager():getFontHeight(UIFont.Small) + 4
    self.listbox.backgroundColor  = {r=0.05, g=0.05, b=0.05, a=0.95}
    self:addChild(self.listbox)

    -- Row 5: Debug basics
    local cyan   = {r=0.4, g=0.9, b=0.4, a=1}
    local red    = {r=0.9, g=0.4, b=0.4, a=1}
    local orange = {r=0.9, g=0.6, b=0.2, a=1}
    self.btnProbe     = makeBtn(self, "Probe Pos",      MyNPCConsole.onProbe,          cyan)
    self.btnClear     = makeBtn(self, "Clear",          MyNPCConsole.onClear,          nil)
    self.btnScan      = makeBtn(self, "Scan Area",      MyNPCConsole.onScan,           red)
    self.btnBrainTick = makeBtn(self, "Brain Tick: OFF",MyNPCConsole.onBrainTickToggle,orange)
    if brainTickRunning then
        self.btnBrainTick:setTitle("Brain Tick: ON")
        self:startBrainTickTimer()
    end

    -- Row 4: Companion / Marker tools
    local blue   = {r=0.4, g=0.7, b=0.9, a=1}
    local lblue  = {r=0.5, g=0.8, b=1.0, a=1}
    local teal   = {r=0.3, g=1.0, b=0.8, a=1}
    local skyb   = {r=0.3, g=0.8, b=1.0, a=1}
    self.btnCompanion        = makeBtn(self, "Companion: OFF",   MyNPCConsole.onCompanionToggle,      blue)
    self.btnCompanionStatus  = makeBtn(self, "Companion Status", MyNPCConsole.onCompanionStatus,     lblue)
    self.btnResetVirtualPos  = makeBtn(self, "Reset Virtual Pos",MyNPCConsole.onResetVirtualPos,     {r=1.0,g=0.5,b=0.2,a=1})
    self.btnMarker           = makeBtn(self, "Marker: OFF",      MyNPCConsole.onMarkerToggle,        teal)
    self.btnMarkerDetail     = makeBtn(self, "Detail: BASIC",    MyNPCConsole.onMarkerDetailToggle,  skyb)
    if companionEnabled then self.btnCompanion:setTitle("Companion: ON") end
    if markerEnabled    then self.btnMarker:setTitle("Marker: ON") end
    if markerDetail == "FULL" then self.btnMarkerDetail:setTitle("Detail: FULL") end

    -- Row 3: Orders
    local green  = {r=0.3, g=1.0, b=0.3, a=1}
    local yellow = {r=1.0, g=0.8, b=0.2, a=1}
    local purple = {r=0.8, g=0.4, b=1.0, a=1}
    self.btnOrderFollow = makeBtn(self, "Order: Follow", MyNPCConsole.onOrderFollow, green)
    self.btnOrderStay   = makeBtn(self, "Order: Stay",   MyNPCConsole.onOrderStay,   yellow)
    self.btnOrderScout  = makeBtn(self, "Order: Scout",  MyNPCConsole.onOrderScout,  purple)
    self:updateOrderButtons()

    -- Row 2: API probes
    local probeCol = {r=0.4, g=0.8, b=1.0, a=1}
    self.btnProbeLuaMover        = makeBtn(self, "Probe LuaMover",   MyNPCConsole.onProbeLuaMover,        probeCol)
    self.btnProbeSurvivorFactory = makeBtn(self, "Probe SrvFactory", MyNPCConsole.onProbeSurvivorFactory, probeCol)
    self.btnProbeIsoSurvivor     = makeBtn(self, "Probe IsoSurvivor",MyNPCConsole.onProbeIsoSurvivor,     probeCol)
    self.btnProbePathfind        = makeBtn(self, "Probe Pathfind",   MyNPCConsole.onProbePathfind,        probeCol)
    self.btnProbeTileFinder      = makeBtn(self, "Probe TileFinder", MyNPCConsole.onProbeTileFinder,      probeCol)

    -- Row 2: Body constructor tests
    local testCol = {r=0.5, g=1.0, b=0.6, a=1}
    self.btnTestNewOnly    = makeBtn(self, "Test: New Only",    MyNPCConsole.onTestNewOnly,    testCol)
    self.btnTestNewDespawn = makeBtn(self, "Test: New+Despawn", MyNPCConsole.onTestNewDespawn, testCol)

    -- Row 1: Body live world tests
    local liveCol  = {r=1.0, g=0.7, b=0.2, a=1}
    local visCol   = {r=0.8, g=1.0, b=0.3, a=1}
    self.btnPlace1Tick   = makeBtn(self, "Test: Place 1 Tick",  MyNPCConsole.onPlace1Tick,   liveCol)
    self.btnPlace1Sec    = makeBtn(self, "Test: Place 1 Sec",   MyNPCConsole.onPlace1Sec,    liveCol)
    self.btnVisible3Sec  = makeBtn(self, "Test: Visible 3 Sec", MyNPCConsole.onVisible3Sec,  visCol)
    self.btnCleanupMover = makeBtn(self, "Cleanup Test Mover",  MyNPCConsole.onCleanupMover, {r=1.0,g=0.3,b=0.3,a=1})

    -- Row 7: NPC body tests
    local npcCol   = {r=0.9, g=0.5, b=1.0, a=1}
    local despwCol = {r=1.0, g=0.4, b=0.4, a=1}
    self.btnSpawnNpc   = makeBtn(self, "Spawn NPC Body",   MyNPCConsole.onSpawnNpc,   npcCol)
    self.btnDespawnNpc = makeBtn(self, "Despawn NPC Body", MyNPCConsole.onDespawnNpc, despwCol)
    self.btnNpcStatus        = makeBtn(self, "NPC Status",        MyNPCConsole.onNpcStatus,        {r=0.5, g=0.8, b=1.0, a=1})
    self.btnNpcModelStatus   = makeBtn(self, "NPC Model Status",   MyNPCConsole.onNpcModelStatus,   {r=0.6, g=0.9, b=0.6, a=1})
    self.btnNpcRenderTrace   = makeBtn(self, "NPC Render Trace",   MyNPCConsole.onNpcRenderTrace,   {r=0.9, g=0.7, b=0.3, a=1})
    self.btnNpcSqRenderTrace = makeBtn(self, "NPC Sq Render Trace", MyNPCConsole.onNpcSqRenderTrace, {r=0.8, g=0.6, b=0.9, a=1})

    -- Row 9: Zombie NPC body test (Phase 9F)
    local zombCol  = {r=0.6, g=1.0, b=0.6, a=1}
    local zdespCol = {r=1.0, g=0.4, b=0.4, a=1}
    local zstatCol = {r=0.5, g=0.9, b=0.7, a=1}
    self.btnSpawnZombieNpc   = makeBtn(self, "Spawn Zombie NPC Body",   MyNPCConsole.onSpawnZombieNpc,   zombCol)
    self.btnDespawnZombieNpc = makeBtn(self, "Despawn Zombie NPC Body", MyNPCConsole.onDespawnZombieNpc, zdespCol)
    self.btnZombieNpcStatus  = makeBtn(self, "Zombie NPC Status",       MyNPCConsole.onZombieNpcStatus,  zstatCol)
    self.btnBumpTypeIdle     = makeBtn(self, "Human Idle: OFF",         MyNPCConsole.onBumpTypeIdleToggle, {r=0.9, g=0.8, b=0.3, a=1})

    -- Row 10: Walk Test
    self.btnWalkTest         = makeBtn(self, "Walk Test: OFF",           MyNPCConsole.onWalkTestToggle,    {r=0.8, g=0.9, b=1.0, a=1})

    self:reflowRows()
end

function MyNPCConsole:onResize()
    if self.width  < CONSOLE_MIN_W then self.width  = CONSOLE_MIN_W end
    if self.height < CONSOLE_MIN_H then self.height = CONSOLE_MIN_H end
    consoleW = self.width
    consoleH = self.height
    self:reflowRows()
end

function MyNPCConsole:addLineSilent(text, r, g, b)
    r = r or 0.85; g = g or 0.85; b = b or 0.85
    local item = {text = text, r = r, g = g, b = b}
    table.insert(self.lines, item)
    if #self.lines > MAX_LINES then
        table.remove(self.lines, 1)
    end
    self.listbox:clear()
    for _, v in ipairs(self.lines) do
        local entry = self.listbox:addItem(v.text, v)
        entry.textColor = {r=v.r, g=v.g, b=v.b, a=1}
    end
    -- scroll to bottom
    local totalH = #self.lines * self.listbox.itemheight
    if totalH > self.listbox.height then
        self.listbox:setYScroll(-(totalH - self.listbox.height))
    end
end

function MyNPCConsole:addLine(text, r, g, b)
    self:addLineSilent(text, r, g, b)
    print("[MyNPCBuddy] " .. text)
end

function MyNPCConsole:onProbe()
    local ok, err = pcall(function()
        DebugBridge.printPlayerPosition()
    end)
    if not ok then
        self:addLine("ERROR: " .. tostring(err), 1, 0.3, 0.3)
        return
    end
    local player = getSpecificPlayer(0)
    if player == nil then
        self:addLine("no player found", 1, 0.8, 0.2)
    else
        local x = string.format("%.1f", player:getX())
        local y = string.format("%.1f", player:getY())
        local z = string.format("%.0f", player:getZ())
        self:addLineSilent("pos  x=" .. x .. "  y=" .. y .. "  z=" .. z, 0.3, 1, 0.3)
    end

    -- Diagnostic readout: FBORenderCell.renderMovingObjects() dispatch proof count.
    local okFbo, fboCount = pcall(function() return DebugBridge.getFboMovingObjectsProofCount() end)
    if okFbo and fboCount ~= nil then
        self:addLineSilent("FBO renderMovingObjects proof count = " .. tostring(fboCount), 1.0, 0.85, 0.2)
    else
        self:addLineSilent("FBO renderMovingObjects proof count = <unavailable>", 1, 0.4, 0.4)
    end
end

function MyNPCConsole:onClear()
    self.lines = {}
    self.listbox:clear()
end

function MyNPCConsole:onScan()
    local ok, err = pcall(function()
        DebugBridge.scanAreaForZombies()
    end)
    if not ok then
        self:addLine("ERROR: " .. tostring(err), 1, 0.3, 0.3)
        return
    end

    local player = getSpecificPlayer(0)
    if player == nil then
        self:addLine("no player found", 1, 0.8, 0.2)
        return
    end

    local x = string.format("%.1f", player:getX())
    local y = string.format("%.1f", player:getY())
    local z = string.format("%.0f", player:getZ())
    self:addLineSilent("Scan: player at x=" .. x .. " y=" .. y .. " z=" .. z, 0.5, 0.8, 1)
    self:addLineSilent("Check console.txt for full zombie scan results", 0.6, 0.6, 0.6)
end

function MyNPCConsole:onBrainTickToggle()
    if brainTickRunning then
        -- Stop the timer
        self:stopBrainTickTimer()
        brainTickRunning = false
        self.btnBrainTick:setTitle("Brain Tick: OFF")
        self:addLine("Brain Tick stopped", 0.9, 0.6, 0.2)
    else
        -- Start the timer
        brainTickRunning = true
        self.btnBrainTick:setTitle("Brain Tick: ON")
        self:addLine("Brain Tick started (1 sec interval)", 0.3, 1, 0.3)
        self:doBrainTick() -- run immediately
        self:startBrainTickTimer()
    end
end

function MyNPCConsole:startBrainTickTimer()
    -- Avoid duplicate timers
    if brainTickTimer ~= nil then
        Events.OnTick.Remove(self.updateBrainTickTimer)
    end
    brainTickTimer = { lastTime = getTimestampMs(), console = self }
    Events.OnTick.Add(self.updateBrainTickTimer)
end

function MyNPCConsole:stopBrainTickTimer()
    if brainTickTimer ~= nil then
        Events.OnTick.Remove(self.updateBrainTickTimer)
        brainTickTimer = nil
    end
end

function MyNPCConsole.updateBrainTickTimer()
    if brainTickTimer == nil then return end
    local now = getTimestampMs()
    if now - brainTickTimer.lastTime >= BRAIN_TICK_INTERVAL then
        brainTickTimer.lastTime = now
        if brainTickTimer.console and not brainTickTimer.console.removed then
            brainTickTimer.console:doBrainTick()
        end
    end
end

function MyNPCConsole:doBrainTick()
    local ok, result = pcall(function()
        -- If companion is enabled, use the combined brain tick
        if companionEnabled then
            return DebugBridge.brainTickWithCompanion()
        else
            return DebugBridge.brainTick()
        end
    end)
    if not ok then
        self:addLine("BrainTick ERROR: " .. tostring(result), 1, 0.3, 0.3)
        return
    end
    self:addLine(tostring(result), 0.3, 0.9, 1)
end

-- Order button helpers

function MyNPCConsole:updateOrderButtons()
    local activeColor  = {r=1.0, g=1.0, b=1.0, a=1}
    local followColor  = {r=0.3, g=1.0, b=0.3, a=1}
    local stayColor    = {r=1.0, g=0.8, b=0.2, a=1}
    local scoutColor   = {r=0.8, g=0.4, b=1.0, a=1}

    if self.btnOrderFollow then
        self.btnOrderFollow.borderColor = (currentOrder == "FOLLOW") and activeColor or followColor
    end
    if self.btnOrderStay then
        self.btnOrderStay.borderColor = (currentOrder == "STAY") and activeColor or stayColor
    end
    if self.btnOrderScout then
        self.btnOrderScout.borderColor = (currentOrder == "SCOUT") and activeColor or scoutColor
    end
end

function MyNPCConsole:setOrder(order)
    currentOrder = order
    local ok, err = pcall(function()
        DebugBridge.companionSetOrderWithInit(order)
    end)
    if not ok then
        self:addLine("Order set error: " .. tostring(err), 1, 0.3, 0.3)
        self:updateOrderButtons()
        return
    end

    if order == "STAY" then
        local hasPos = pcall(function() return DebugBridge.companionHasVirtualPos() end)
        local vx = string.format("%.1f", DebugBridge.companionGetVirtualX())
        local vy = string.format("%.1f", DebugBridge.companionGetVirtualY())
        local vz = string.format("%.0f", DebugBridge.companionGetVirtualZ())
        self:addLineSilent("Order set: STAY, holding vpos=(" .. vx .. "," .. vy .. "," .. vz .. ")", 1.0, 0.85, 0.2)
    elseif order == "SCOUT" then
        local ok2 = pcall(function() return DebugBridge.companionHasScoutAnchor() end)
        local ax = string.format("%.1f", DebugBridge.companionGetScoutAnchorX())
        local ay = string.format("%.1f", DebugBridge.companionGetScoutAnchorY())
        local az = string.format("%.0f", DebugBridge.companionGetScoutAnchorZ())
        self:addLineSilent("Order set: SCOUT, anchor=(" .. ax .. "," .. ay .. "," .. az .. ")", 0.8, 0.4, 1.0)
    else
        self:addLineSilent("Order set: " .. order, 0.3, 1, 0.5)
    end

    self:updateOrderButtons()
end

function MyNPCConsole:onOrderFollow()
    self:setOrder("FOLLOW")
end

function MyNPCConsole:onOrderStay()
    self:setOrder("STAY")
end

function MyNPCConsole:onOrderScout()
    self:setOrder("SCOUT")
end

-- Marker toggle / detail toggle

function MyNPCConsole:onMarkerDetailToggle()
    markerDetail = (markerDetail == "BASIC") and "FULL" or "BASIC"
    if self.btnMarkerDetail then
        self.btnMarkerDetail:setTitle("Detail: " .. markerDetail)
    end
    self:addLineSilent("Marker detail: " .. markerDetail, 0.3, 0.8, 1.0)
end

function MyNPCConsole:onMarkerToggle()
    markerEnabled = not markerEnabled
    if self.btnMarker then
        self.btnMarker:setTitle(markerEnabled and "Marker: ON" or "Marker: OFF")
    end

    local overlay = getOrCreateMarkerOverlay()
    overlay:setVisible(markerEnabled)
    if markerEnabled then
        overlay:bringToTop()
    end

    self:addLine(
        markerEnabled and "Marker ON - debug overlay active" or "Marker OFF",
        0.3, 1.0, 0.8
    )
end

-- Companion button handlers

function MyNPCConsole:onResetVirtualPos()
    local ok, err = pcall(function()
        DebugBridge.companionResetVirtualPos()
    end)
    if not ok then
        self:addLine("Reset Virtual Pos ERROR: " .. tostring(err), 1, 0.3, 0.3)
        return
    end

    local ok2, result = pcall(function()
        return DebugBridge.companionHasVirtualPos()
    end)
    if ok2 and result then
        local x = string.format("%.1f", DebugBridge.companionGetVirtualX())
        local y = string.format("%.1f", DebugBridge.companionGetVirtualY())
        local z = string.format("%.0f", DebugBridge.companionGetVirtualZ())
        self:addLineSilent("Virtual companion pos reset: x=" .. x .. " y=" .. y .. " z=" .. z, 1.0, 0.6, 0.2)
    else
        self:addLine("Reset Virtual Pos: no player found", 1, 0.8, 0.2)
    end
end

function MyNPCConsole:onCompanionToggle()
    if companionEnabled then
        -- Disable companion
        companionEnabled = false
        self.btnCompanion:setTitle("Companion: OFF")
        self:addLine("Companion disabled", 0.9, 0.4, 0.4)
    else
        -- Enable companion
        companionEnabled = true
        self.btnCompanion:setTitle("Companion: ON")
        self:addLine("Companion enabled (virtual brain active)", 0.4, 0.9, 0.4)
    end

    -- Update Java side
    local ok, err = pcall(function()
        DebugBridge.companionSetEnabled(companionEnabled)
    end)
    if not ok then
        self:addLine("Companion toggle error: " .. tostring(err), 1, 0.3, 0.3)
    end
end

function MyNPCConsole:onCompanionStatus()
    local ok, result = pcall(function()
        return DebugBridge.companionGetFullStatus()
    end)
    if not ok then
        self:addLine("Companion status error: " .. tostring(result), 1, 0.3, 0.3)
        return
    end

    -- Print each line of the multi-line status
    if result then
        for line in string.gmatch(tostring(result), "[^\n]+") do
            self:addLine(line, 0.5, 0.8, 1.0)
        end
    end
end

-- ── API probe button handlers ────────────────────────────────────────────────

local function printProbeResult(console, result, label)
    if result == nil then
        console:addLineSilent(label .. ": nil result", 1, 0.4, 0.4)
        return
    end
    for line in string.gmatch(tostring(result), "[^\n]+") do
        console:addLineSilent(line, 0.6, 0.9, 1.0)
    end
end

function MyNPCConsole:onProbeLuaMover()
    local ok, result = pcall(function() return BodyAPIProbe.probeIsoLuaMover() end)
    if not ok then
        self:addLine("Probe LuaMover ERROR: " .. tostring(result), 1, 0.3, 0.3)
        return
    end
    printProbeResult(self, result, "Probe LuaMover")
end

function MyNPCConsole:onProbeSurvivorFactory()
    local ok, result = pcall(function() return BodyAPIProbe.probeSurvivorFactory() end)
    if not ok then
        self:addLine("Probe SurvivorFactory ERROR: " .. tostring(result), 1, 0.3, 0.3)
        return
    end
    printProbeResult(self, result, "Probe SurvivorFactory")
end

function MyNPCConsole:onProbeIsoSurvivor()
    local ok, result = pcall(function() return BodyAPIProbe.probeIsoSurvivor() end)
    if not ok then
        self:addLine("Probe IsoSurvivor ERROR: " .. tostring(result), 1, 0.3, 0.3)
        return
    end
    printProbeResult(self, result, "Probe IsoSurvivor")
end

function MyNPCConsole:onProbePathfind()
    local ok, result = pcall(function() return BodyAPIProbe.probePathFindBehavior2() end)
    if not ok then
        self:addLine("Probe Pathfind ERROR: " .. tostring(result), 1, 0.3, 0.3)
        return
    end
    printProbeResult(self, result, "Probe Pathfind")
end

function MyNPCConsole:onProbeTileFinder()
    local ok, result = pcall(function() return BodyAPIProbe.probeAdjacentFreeTileFinder() end)
    if not ok then
        self:addLine("Probe TileFinder ERROR: " .. tostring(result), 1, 0.3, 0.3)
        return
    end
    printProbeResult(self, result, "Probe TileFinder")
end

-- ── Body test handlers ────────────────────────────────────────────────────────

function MyNPCConsole:onTestNewOnly()
    local ok, result = pcall(function()
        local t = {}
        local mover = IsoLuaMover.new(t)
        if mover ~= nil then
            return "IsoLuaMover.new({}) OK, obj=" .. tostring(mover)
        else
            return "IsoLuaMover.new({}) returned nil"
        end
    end)
    if not ok then
        self:addLine("TestNewOnly ERROR: " .. tostring(result), 1, 0.3, 0.3)
    else
        self:addLine(result, 0.3, 1, 0.5)
    end
end

function MyNPCConsole:onTestNewDespawn()
    local lines = {}
    local ok, err = pcall(function()
        local t = {}
        local mover = IsoLuaMover.new(t)
        if mover == nil then
            table.insert(lines, "IsoLuaMover.new({}) returned nil")
            return
        end
        table.insert(lines, "IsoLuaMover.new({}) OK")
        mover:Despawn()
        table.insert(lines, "Despawn on un-added IsoLuaMover OK")
    end)
    if not ok then
        self:addLine("TestNewDespawn ERROR: " .. tostring(err), 1, 0.3, 0.3)
        return
    end
    for _, l in ipairs(lines) do
        self:addLine(l, 0.3, 1, 0.5)
    end
end

function MyNPCConsole:onMouseDown(x, y)
    self:bringToTop()
    return ISCollapsableWindow.onMouseDown(self, x, y)
end

function MyNPCConsole:close()
    ISCollapsableWindow.close(self)
    -- Don't stop timer on close, keep running in background if desired
    -- Or optionally stop: self:stopBrainTickTimer()
end

-- ── Singleton management ──────────────────────────────────────────────────────

local consoleWindow = nil

local function getOrCreateConsole()
    if consoleWindow ~= nil and not consoleWindow.removed then
        return consoleWindow
    end
    local sw = getCore():getScreenWidth()
    consoleWindow = MyNPCConsole:new(sw - consoleW - 20, 60, consoleW, consoleH)
    consoleWindow:initialise()
    consoleWindow:addToUIManager()
    consoleWindow:addLineSilent("MyNPCBuddy console ready — press F9 or click Probe Pos", 0.5, 0.8, 1)
    return consoleWindow
end

-- ── Key handler ───────────────────────────────────────────────────────────────

local function onKeyPressed(key)
    if key ~= KEY_F9 then return end

    local con = getOrCreateConsole()
    if con:isVisible() then
        -- toggle: if already visible just probe
        con:onProbe()
        con:bringToTop()
    else
        con:setVisible(true)
        con:onProbe()
        con:bringToTop()
    end
end

Events.OnKeyPressed.Add(onKeyPressed)

-- ── Active test mover handlers (Phase 9F-C) ──────────────────────────────────

local function despawnActiveTestMover(logFn)
    if activeTestMover == nil then return end
    local ok, err = pcall(function()
        activeTestMover:Despawn()
    end)
    activeTestMover = nil
    if logFn then
        if ok then
            logFn("IsoLuaMover despawned OK", 0.3, 1, 0.5)
        else
            logFn("IsoLuaMover Despawn error: " .. tostring(err), 1, 0.4, 0.4)
        end
    end
end

function MyNPCConsole:onPlace1Sec()
    if activeTestMover ~= nil then
        self:addLine("Active test mover already exists; cleanup first.", 1, 0.7, 0.2)
        return
    end

    local console = self
    local ok, err = pcall(function()
        local player = getSpecificPlayer(0)
        if player == nil then
            console:addLine("Place 1 Sec: no player found", 1, 0.8, 0.2)
            return
        end

        local t = {}
        t.update     = function(self) end
        t.postrender = function(self, col, bDoAttached) end

        local mover = IsoLuaMover.new(t)
        if mover == nil then
            console:addLine("Place 1 Sec: IsoLuaMover.new() returned nil", 1, 0.3, 0.3)
            return
        end

        local px = player:getX() + 2
        local py = player:getY()
        local pz = player:getZ()
        console:addLine(string.format("Place 1 Sec: pos=(%.1f,%.1f,%.1f)", px, py, pz), 0.7, 0.7, 0.7)

        activeTestMover = mover
        mover:setPosition(px, py, pz)
        mover:addToWorld()
        console:addLine("IsoLuaMover added to world for one second", 0.3, 1, 0.5)

        local startMs = getTimestampMs()
        local tickHandler
        tickHandler = function()
            if (getTimestampMs() - startMs) < 1000 then return end
            Events.OnTick.Remove(tickHandler)

            local despawnOk = true
            local despawnErr = ""
            if activeTestMover ~= nil then
                local ok2, err2 = pcall(function() activeTestMover:Despawn() end)
                activeTestMover = nil
                if not ok2 then
                    despawnOk = false
                    despawnErr = tostring(err2)
                end
            end
            if consoleWindow ~= nil and not consoleWindow.removed then
                if despawnOk then
                    consoleWindow:addLine("IsoLuaMover despawned after one second", 0.3, 1, 0.5)
                else
                    consoleWindow:addLine("IsoLuaMover Despawn error (1sec): " .. despawnErr, 1, 0.3, 0.3)
                end
            end
        end
        Events.OnTick.Add(tickHandler)
    end)

    if not ok then
        self:addLine("Place 1 Sec ERROR: " .. tostring(err), 1, 0.3, 0.3)
        activeTestMover = nil
    end
end

function MyNPCConsole:onVisible3Sec()
    if activeTestMover ~= nil then
        self:addLine("Active test mover already exists; cleanup first.", 1, 0.7, 0.2)
        return
    end

    local console = self
    local ok, err = pcall(function()
        local player = getSpecificPlayer(0)
        if player == nil then
            console:addLine("Visible 3 Sec: no player found", 1, 0.8, 0.2)
            return
        end

        local t = {}
        t.update     = function(self) end
        t.postrender = function(self, col, bDoAttached) end

        local mover = IsoLuaMover.new(t)
        if mover == nil then
            console:addLine("Visible 3 Sec: IsoLuaMover.new() returned nil", 1, 0.3, 0.3)
            return
        end

        local px = player:getX() + 2
        local py = player:getY()
        local pz = player:getZ()
        console:addLine(string.format("Visible 3 Sec: pos=(%.1f,%.1f,%.1f)", px, py, pz), 0.7, 0.7, 0.7)

        -- Attempt A: IsoGameCharacter.PlayAnim (capital P — high-level character animator)
        local animOk, animErr = pcall(function()
            mover:PlayAnim("Idle")
        end)
        if animOk then
            console:addLine("PlayAnim(\"Idle\") OK", 0.5, 1, 0.5)
        else
            console:addLine("PlayAnim(\"Idle\") failed: " .. tostring(animErr), 1, 0.6, 0.2)
            -- Attempt B: IsoLuaMover.playAnim (lowercase — drives IsoSprite directly)
            -- NOTE: sprite is blank so currentAnim will be nil; wrap tightly
            local paOk, paErr = pcall(function()
                mover:playAnim("Idle", 1.0, true, true)
            end)
            if paOk then
                console:addLine("playAnim(\"Idle\",1,true,true) OK", 0.5, 1, 0.5)
            else
                console:addLine("playAnim(\"Idle\") also failed: " .. tostring(paErr), 1, 0.5, 0.2)
                console:addLine("Mover will be invisible (blank sprite) — lifecycle test continues", 0.7, 0.7, 0.4)
            end
        end

        activeTestMover = mover
        mover:setPosition(px, py, pz)
        mover:addToWorld()
        console:addLine("IsoLuaMover visible test added to world for 3 seconds", 0.3, 1, 0.5)

        local startMs = getTimestampMs()
        local tickHandler
        tickHandler = function()
            if (getTimestampMs() - startMs) < 3000 then return end
            Events.OnTick.Remove(tickHandler)

            local despawnOk = true
            local despawnErr = ""
            if activeTestMover ~= nil then
                local ok2, err2 = pcall(function() activeTestMover:Despawn() end)
                activeTestMover = nil
                if not ok2 then
                    despawnOk = false
                    despawnErr = tostring(err2)
                end
            end
            if consoleWindow ~= nil and not consoleWindow.removed then
                if despawnOk then
                    consoleWindow:addLine("IsoLuaMover visible test despawned", 0.3, 1, 0.5)
                else
                    consoleWindow:addLine("IsoLuaMover Despawn error (3sec): " .. despawnErr, 1, 0.3, 0.3)
                end
            end
        end
        Events.OnTick.Add(tickHandler)
    end)

    if not ok then
        self:addLine("Visible 3 Sec ERROR: " .. tostring(err), 1, 0.3, 0.3)
        activeTestMover = nil
    end
end

function MyNPCConsole:onCleanupMover()
    if activeTestMover == nil then
        self:addLine("Cleanup: no active test mover", 0.7, 0.7, 0.7)
        return
    end
    despawnActiveTestMover(function(msg, r, g, b)
        self:addLine(msg, r, g, b)
    end)
end

function MyNPCConsole:onPlace1Tick()
    if activeTestMover ~= nil then
        self:addLine("Active test mover already exists; cleanup first.", 1, 0.7, 0.2)
        return
    end

    local console = self
    local ok, err = pcall(function()
        local player = getSpecificPlayer(0)
        if player == nil then
            console:addLine("Place 1 Tick: no player found", 1, 0.8, 0.2)
            return
        end

        local t = {}
        t.update     = function(self) end
        t.postrender = function(self, col, bDoAttached) end

        local mover = IsoLuaMover.new(t)
        if mover == nil then
            console:addLine("Place 1 Tick: IsoLuaMover.new() returned nil", 1, 0.3, 0.3)
            return
        end

        activeTestMover = mover
        mover:setPosition(player:getX() + 2, player:getY(), player:getZ())
        mover:addToWorld()
        console:addLine("IsoLuaMover added to world for one tick", 0.3, 1, 0.5)

        local tickHandler
        tickHandler = function()
            Events.OnTick.Remove(tickHandler)
            local despawnOk = true
            local despawnErr = ""
            if activeTestMover ~= nil then
                local ok2, err2 = pcall(function() activeTestMover:Despawn() end)
                activeTestMover = nil
                if not ok2 then
                    despawnOk = false
                    despawnErr = tostring(err2)
                end
            end
            if consoleWindow ~= nil and not consoleWindow.removed then
                if despawnOk then
                    consoleWindow:addLine("IsoLuaMover despawned after one tick", 0.3, 1, 0.5)
                else
                    consoleWindow:addLine("IsoLuaMover Despawn error (tick): " .. despawnErr, 1, 0.3, 0.3)
                end
            end
        end
        Events.OnTick.Add(tickHandler)
    end)

    if not ok then
        self:addLine("Place 1 Tick ERROR: " .. tostring(err), 1, 0.3, 0.3)
        activeTestMover = nil
    end
end

-- ── NPC body test handlers ──────────────────────────────────────────────────

function MyNPCConsole:onSpawnNpc()
    local ok, result = pcall(function()
        return DebugBridge.spawnTestNpc()
    end)
    if not ok then
        self:addLine("Spawn NPC Body ERROR: " .. tostring(result), 1, 0.3, 0.3)
        return
    end
    if result == nil then
        self:addLine("Spawn NPC Body: nil result", 1, 0.5, 0.2)
        return
    end
    if string.find(tostring(result), "already exists") then
        self:addLine(tostring(result), 1, 0.7, 0.2)
    else
        self:addLine(tostring(result), 0.7, 0.5, 1.0)
    end
end

function MyNPCConsole:onNpcStatus()
    local ok, result = pcall(function()
        return DebugBridge.npcStatus()
    end)
    if not ok then
        self:addLine("NPC Status ERROR: " .. tostring(result), 1, 0.3, 0.3)
        return
    end
    if result == nil then
        self:addLine("NPC Status: nil result", 1, 0.5, 0.2)
        return
    end
    for line in tostring(result):gmatch("[^\n]+") do
        if string.find(line, "ERROR") then
            self:addLine(line, 1, 0.3, 0.3)
        elseif string.find(line, "no test NPC") then
            self:addLine(line, 1, 0.7, 0.2)
        else
            self:addLine(line, 0.5, 0.8, 1.0)
        end
    end
end

function MyNPCConsole:onNpcModelStatus()
    local ok, result = pcall(function()
        return DebugBridge.npcModelStatus()
    end)
    if not ok then
        self:addLine("NPC Model Status ERROR: " .. tostring(result), 1, 0.3, 0.3)
        return
    end
    if result == nil then
        self:addLine("NPC Model Status: nil result", 1, 0.5, 0.2)
        return
    end
    for line in tostring(result):gmatch("[^\n]+") do
        if string.find(line, "ERROR") then
            self:addLine(line, 1, 0.3, 0.3)
        elseif string.find(line, "no test NPC") then
            self:addLine(line, 1, 0.7, 0.2)
        else
            self:addLine(line, 0.5, 0.9, 0.5)
        end
    end
end

function MyNPCConsole:onNpcRenderTrace()
    local ok, result = pcall(function()
        return DebugBridge.npcRenderTrace()
    end)
    if not ok then
        self:addLine("NPC Render Trace ERROR: " .. tostring(result), 1, 0.3, 0.3)
        return
    end
    if result == nil then
        self:addLine("NPC Render Trace: nil result", 1, 0.5, 0.2)
        return
    end
    for line in tostring(result):gmatch("[^\n]+") do
        if string.find(line, "ERROR") then
            self:addLine(line, 1, 0.3, 0.3)
        elseif string.find(line, "NEVER") then
            self:addLine(line, 1, 0.5, 0.2)
        else
            self:addLine(line, 0.9, 0.7, 0.3)
        end
    end
end

function MyNPCConsole:onNpcSqRenderTrace()
    local ok, result = pcall(function()
        return DebugBridge.npcSquareRenderTrace()
    end)
    if not ok then
        self:addLine("NPC Sq Render Trace ERROR: " .. tostring(result), 1, 0.3, 0.3)
        return
    end
    if result == nil then
        self:addLine("NPC Sq Render Trace: nil result", 1, 0.5, 0.2)
        return
    end
    for line in tostring(result):gmatch("[^\n]+") do
        if string.find(line, "ERROR") then
            self:addLine(line, 1, 0.3, 0.3)
        elseif string.find(line, "NEVER") then
            self:addLine(line, 1, 0.5, 0.2)
        elseif string.find(line, "skipReason") and string.find(line, "sprite") then
            self:addLine(line, 1, 0.6, 0.3)
        else
            self:addLine(line, 0.8, 0.6, 0.9)
        end
    end
end

function MyNPCConsole:onDespawnNpc()
    local ok, result = pcall(function()
        return DebugBridge.despawnTestNpc()
    end)
    if not ok then
        self:addLine("Despawn NPC Body ERROR: " .. tostring(result), 1, 0.3, 0.3)
        return
    end
    if result == nil then
        self:addLine("Despawn NPC Body: nil result", 1, 0.5, 0.2)
        return
    end
    if string.find(tostring(result), "ERROR") then
        self:addLine(tostring(result), 1, 0.3, 0.3)
    else
        self:addLine(tostring(result), 0.5, 1.0, 0.5)
    end
end

-- ── Zombie NPC body test handlers (Phase 9F) ────────────────────────────────

local function resetStateDiag()
    stateDiagActive = false
    stateDiagPrev = {}
    stateDiagChangeCount = 0
end

local function diagValue(value)
    if value == nil then return "<nil>" end
    return tostring(value)
end

local function logStateDiag(zombie)
    if not stateDiagActive then return end
    if zombie == nil then return end

    local ok, err = pcall(function()
        local asn = "<unavailable>"
        local csn = "<unavailable>"
        local wt = "<unavailable>"
        local zwt = "<unavailable>"
        local bt = "<unavailable>"
        local tgtStr = "nil"
        local pathStr = "no"

        pcall(function() asn = tostring(zombie:getActionStateName()) end)
        pcall(function() csn = tostring(zombie:getCurrentStateName()) end)
        pcall(function() wt = tostring(zombie:getWalkType()) end)
        pcall(function() zwt = tostring(zombie:GetVariable("zombieWalkType")) end)
        pcall(function() bt = tostring(zombie:getBumpType()) end)

        local tgt = nil
        pcall(function() tgt = zombie:getTarget() end)
        if tgt ~= nil then
            local isPlayer = false
            pcall(function() isPlayer = (tgt == getSpecificPlayer(0)) end)
            tgtStr = isPlayer and "player" or "other"
        end

        local hasPath = false
        pcall(function() hasPath = (zombie:getPathFindBehavior2() ~= nil) end)
        pathStr = hasPath and "yes" or "no"

        local isFirst = (stateDiagChangeCount == 0 and stateDiagPrev.initialized ~= true)

        if isFirst then
            stateDiagPrev.initialized = true
            stateDiagChangeCount = 1
            local elapsed = getTimestampMs() - walkTestStartedAt
            local line = string.format("[MyNPCBuddy] StateDiag #1 +%dms: BASELINE | asn=%s csn=%s walkType=%s zombieWalkType=%s bumpType=%s target=%s path=%s",
                elapsed, diagValue(asn), diagValue(csn), diagValue(wt), diagValue(zwt), diagValue(bt), tgtStr, pathStr)
            print(line)
            stateDiagPrev.asn = asn
            stateDiagPrev.csn = csn
            stateDiagPrev.wt = wt
            stateDiagPrev.zwt = zwt
            stateDiagPrev.bt = bt
            stateDiagPrev.tgt = tgtStr
            stateDiagPrev.path = pathStr
            return
        end

        local changed = false
        local parts = {}

        if asn ~= stateDiagPrev.asn then
            table.insert(parts, "asn:" .. diagValue(stateDiagPrev.asn) .. "->" .. diagValue(asn))
            changed = true
        end
        if csn ~= stateDiagPrev.csn then
            table.insert(parts, "csn:" .. diagValue(stateDiagPrev.csn) .. "->" .. diagValue(csn))
            changed = true
        end
        if wt ~= stateDiagPrev.wt then
            table.insert(parts, "walkType:" .. diagValue(stateDiagPrev.wt) .. "->" .. diagValue(wt))
            changed = true
        end
        if zwt ~= stateDiagPrev.zwt then
            table.insert(parts, "zombieWalkType:" .. diagValue(stateDiagPrev.zwt) .. "->" .. diagValue(zwt))
            changed = true
        end
        if bt ~= stateDiagPrev.bt then
            table.insert(parts, "bumpType:" .. diagValue(stateDiagPrev.bt) .. "->" .. diagValue(bt))
            changed = true
        end
        if tgtStr ~= stateDiagPrev.tgt then
            table.insert(parts, "target:" .. diagValue(stateDiagPrev.tgt) .. "->" .. diagValue(tgtStr))
            changed = true
        end
        if pathStr ~= stateDiagPrev.path then
            table.insert(parts, "path:" .. diagValue(stateDiagPrev.path) .. "->" .. diagValue(pathStr))
            changed = true
        end

        if changed then
            stateDiagChangeCount = stateDiagChangeCount + 1
            local elapsed = getTimestampMs() - walkTestStartedAt
            local line = string.format("[MyNPCBuddy] StateDiag #%d +%dms: %s | asn=%s csn=%s walkType=%s zombieWalkType=%s bumpType=%s target=%s path=%s",
                stateDiagChangeCount, elapsed, table.concat(parts, ", "), diagValue(asn), diagValue(csn), diagValue(wt), diagValue(zwt), diagValue(bt), tgtStr, pathStr)
            print(line)
        end

        stateDiagPrev.asn = asn
        stateDiagPrev.csn = csn
        stateDiagPrev.wt = wt
        stateDiagPrev.zwt = zwt
        stateDiagPrev.bt = bt
        stateDiagPrev.tgt = tgtStr
        stateDiagPrev.path = pathStr
    end)

    if not ok then
        stateDiagActive = false
        print("[MyNPCBuddy] StateDiag: internal error — diagnostics disabled for this walk: " .. tostring(err))
        if consoleWindow ~= nil and not consoleWindow.removed then
            consoleWindow:addLine("StateDiag: error — disabled for this walk", 1, 0.4, 0.2)
        end
    end
end

local function despawnTestZombieNpc(logFn)
    if testZombieNpc == nil then return end
    local z = testZombieNpc
    testZombieNpc = nil
    zombiePassivityLogged = false
    bumpTypeIdleEnabled = false
    bumpTypeFirstLogged = false
    bumpTypeExitPending = false
    bumpTypeExitStartedAt = 0
    bumpTypeExitLogged = false
    -- Cancel any active walk test path before removing the zombie
    if walkTestActive then
        pcall(function() z:getPathFindBehavior2():cancel() end)
        pcall(function() z:getPathFindBehavior2():reset() end)
    end
    walkTestActive = false
    walkTestTarget = nil
    walkTestPhase = "idle"
    walkTestFirstLogged = false
    hostileInterceptLogged = false
    walkPathReissueNeeded = false
    walkPathReissueLogged = false
    walkTypeDiagnosticLogged = false
    idleSuspensionActive = false
    resetStateDiag()
    local ok, err = pcall(function()
        z:removeFromWorld()
        z:removeFromSquare()
    end)
    if logFn then
        if ok then
            logFn("Zombie NPC Body despawned OK", 0.3, 1, 0.5)
        else
            logFn("Zombie NPC Body despawn error: " .. tostring(err), 1, 0.4, 0.4)
        end
    end
    print("[MyNPCBuddy] Zombie NPC Body despawn: " .. (ok and "OK" or ("ERROR: " .. tostring(err))))
end

function MyNPCConsole:onSpawnZombieNpc()
    if testZombieNpc ~= nil then
        self:addLine("Zombie NPC Body already exists; despawn first.", 1, 0.7, 0.2)
        return
    end

    local console = self
    local ok, err = pcall(function()
        local player = getSpecificPlayer(0)
        if player == nil then
            console:addLine("Spawn Zombie NPC Body: no player found", 1, 0.8, 0.2)
            return
        end

        local px = math.floor(player:getX()) + 3
        local py = math.floor(player:getY())
        local pz = math.floor(player:getZ())

        local outfit = "Naked" .. tostring(1 + ZombRand(101))
        local femaleChance = 0

        console:addLine(string.format("Spawn Zombie NPC Body: pos=(%d,%d,%d) outfit=%s", px, py, pz, outfit), 0.7, 0.7, 0.7)

        local zombieList = addZombiesInOutfit(px, py, pz, 1, outfit, femaleChance,
                                               false, false, false, false,
                                               true, false, 100)

        if zombieList == nil or zombieList:size() == 0 then
            console:addLine("Spawn Zombie NPC Body: addZombiesInOutfit returned empty list", 1, 0.3, 0.3)
            return
        end

        local zombie = zombieList:get(0)
        if zombie == nil then
            console:addLine("Spawn Zombie NPC Body: zombieList:get(0) returned nil", 1, 0.3, 0.3)
            return
        end

        testZombieNpc = zombie

        -- Mark in ModData
        zombie:getModData().MyNPCBuddyTestZombie = true

        -- Make harmless/passive (from Bandits Banditize, BanditUpdate.lua:158-206)
        zombie:setNoTeeth(true)
        zombie:setVariable("Bandit", true)
        zombie:setVariable("NoLungeTarget", true)
        zombie:setVariable("ZombieHitReaction", "Chainsaw")
        local origWalkType = ""
        pcall(function() origWalkType = tostring(zombie:getWalkType()) end)
        zombie:getModData().MyNPCBuddyOriginalWalkType = origWalkType
        zombie:setWalkType("Walk")
        zombie:setPrimaryHandItem(nil)
        zombie:setSecondaryHandItem(nil)
        zombie:resetEquippedHandsModels()
        zombie:clearAttachedItems()

        -- Suppress turn-alerted trigger threshold (BanditUpdate.lua:198)
        local tavOk = pcall(function() zombie:setTurnAlertedValues(-5, 5) end)
        if not tavOk then
            print("[MyNPCBuddy] Spawn: setTurnAlertedValues unavailable on this build")
        end

        -- Stop vocalizations (BanditUpdate.lua:190)
        pcall(function() zombie:getEmitter():stopAll() end)

        -- Apply human visuals (from Bandits Bandit.ApplyVisuals, Bandit.lua:79-281)
        local visuals = zombie:getHumanVisual()
        if visuals then
            -- Clean zombie gore
            pcall(function() visuals:removeDirt() end)
            pcall(function() visuals:removeBlood() end)
            local maxIdx = BloodBodyPartType.MAX:index()
            for i = 0, maxIdx - 1 do
                local part = BloodBodyPartType.FromIndex(i)
                pcall(function() visuals:setBlood(part, 0) end)
                pcall(function() visuals:setDirt(part, 0) end)
            end

            -- Human skin (Bandit.GetSkinTexture(false, 1) -> "MaleBody01a")
            pcall(function() visuals:setSkinTextureName("MaleBody01a") end)
            -- Normal hair (Bandit.maleHairStyles)
            pcall(function() visuals:setHairModel("Short") end)
            -- Clean shaven (Bandit.beardStyles[1] = "")
            pcall(function() visuals:setBeardModel("") end)
        end

        -- Clear zombie clothing visuals (Bandit.lua:87-91)
        pcall(function() zombie:getItemVisuals():clear() end)
        pcall(function() zombie:getWornItems():clear() end)

        -- Apply model changes (Bandit.lua:280-281)
        zombie:resetModelNextFrame()
        zombie:resetModel()

        local classInfo = "IsoZombie"
        console:addLine("Spawn Zombie NPC Body: OK class=" .. classInfo .. " noTeeth=true invulnerable=true", 0.3, 1, 0.5)
        print("[MyNPCBuddy] Spawn Zombie NPC Body: OK at (" .. px .. "," .. py .. "," .. pz .. ") class=" .. classInfo)
    end)

    if not ok then
        self:addLine("Spawn Zombie NPC Body ERROR: " .. tostring(err), 1, 0.3, 0.3)
        testZombieNpc = nil
    end
end

function MyNPCConsole:onDespawnZombieNpc()
    if testZombieNpc == nil then
        self:addLine("Despawn Zombie NPC Body: no test zombie to despawn", 0.7, 0.7, 0.7)
        return
    end
    despawnTestZombieNpc(function(msg, r, g, b)
        self:addLine(msg, r, g, b)
    end)
end

function MyNPCConsole:onZombieNpcStatus()
    if testZombieNpc == nil then
        self:addLine("Zombie NPC Status: no test zombie exists", 1, 0.7, 0.2)
        return
    end

    local z = testZombieNpc
    local lines = {}

    local classInfo = "IsoZombie"
    table.insert(lines, "Zombie NPC Status: class=" .. classInfo)

    local x, y, zz
    pcall(function() x = z:getX(); y = z:getY(); zz = z:getZ() end)
    table.insert(lines, string.format("  pos: (%.1f, %.1f, %d)", x or 0, y or 0, zz or 0))

    local sq
    pcall(function() sq = z:getCurrentSquare() end)
    if sq then
        table.insert(lines, string.format("  square: (%d, %d, %d)", sq:getX(), sq:getY(), sq:getZ()))
    else
        table.insert(lines, "  square: NULL")
    end

    local isDead = false
    pcall(function() isDead = z:isDead() end)
    table.insert(lines, "  isDead: " .. tostring(isDead))

    local isOnFloor = false
    pcall(function() isOnFloor = z:isOnFloor() end)
    table.insert(lines, "  isOnFloor: " .. tostring(isOnFloor))

    local isInvisible = false
    pcall(function() isInvisible = z:isInvisible() end)
    table.insert(lines, "  isInvisible: " .. tostring(isInvisible))

    local alpha0, targetAlpha0
    pcall(function() alpha0 = z:getAlpha(0) end)
    pcall(function() targetAlpha0 = z:getTargetAlpha(0) end)
    table.insert(lines, "  alpha[0]: " .. tostring(alpha0))
    table.insert(lines, "  targetAlpha[0]: " .. tostring(targetAlpha0))

    local hasFlag = false
    pcall(function() hasFlag = (z:getModData().MyNPCBuddyTestZombie == true) end)
    table.insert(lines, "  ModData test flag: " .. tostring(hasFlag))

    local inZombieList = false
    pcall(function()
        local cell = getCell()
        if cell then
            local zlist = cell:getZombieList()
            if zlist then
                inZombieList = zlist:contains(z)
            end
        end
    end)
    table.insert(lines, "  in cell:getZombieList(): " .. tostring(inZombieList))

    table.insert(lines, "  vanilla zombie pipeline: " .. (inZombieList and "YES (managed by engine)" or "NO (not in zombie list)"))

    for _, line in ipairs(lines) do
        if string.find(line, "ERROR") then
            self:addLine(line, 1, 0.3, 0.3)
        elseif string.find(line, "NO ") then
            self:addLine(line, 1, 0.6, 0.2)
        else
            self:addLine(line, 0.5, 0.9, 0.7)
        end
    end
    print("[MyNPCBuddy] " .. table.concat(lines, " | "))
end

-- ── Zombie NPC passivity handler (Phase 9F) ──────────────────────────────────
-- Per-tick suppression of hostile behavior for the test zombie only.
-- APIs reused from Bandits: BanditUpdate.lua lines 324-355, 429-431, 1480, 2041, 2044
-- and BanditCompatibility.lua lines 224-242.

local function onZombieUpdatePassivity(zombie)
    if testZombieNpc == nil then return end
    if zombie ~= testZombieNpc then return end

    local isWalking = (walkTestPhase == "walking")

    -- Safety calls: always run regardless of walk state
    pcall(function() zombie:setTarget(nil) end)
    pcall(function() zombie:clearAggroList() end)
    pcall(function() zombie:setNoTeeth(true) end)
    pcall(function() zombie:setVariable("NoLungeTarget", true) end)

    -- Mode-specific engine controls
    if isWalking then
        pcall(function() zombie:setUseless(false) end)
        pcall(function() zombie:setSpeedMod(1) end)
        if bumpTypeIdleEnabled then
            pcall(function() zombie:setWalkType("Walk") end)
        else
            local origWt = zombie:getModData().MyNPCBuddyOriginalWalkType
            if origWt and origWt ~= "" then
                pcall(function() zombie:setWalkType(origWt) end)
            end
        end
    else
        pcall(function() zombie:setUseless(true) end)
        pcall(function() zombie:setPath2(nil) end)
        pcall(function() zombie:setSpeedMod(0) end)
    end

    -- Hostile-state interceptor (runs in both idle and walking)
    -- BanditUpdate.lua:324-327 (turnalerted), 352-356 (lunge)
    local asn = ""
    pcall(function() asn = zombie:getActionStateName() end)
    if asn == "turnalerted" or asn == "lunge" then
        pcall(function() zombie:setTarget(nil) end)
        pcall(function() zombie:clearAggroList() end)
        pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
        if isWalking then
            walkPathReissueNeeded = true
        end
        if not hostileInterceptLogged then
            hostileInterceptLogged = true
            if consoleWindow ~= nil and not consoleWindow.removed then
                consoleWindow:addLine("Hostile state intercepted: " .. asn .. " — forcing ZombieIdle" .. (isWalking and " + path reissue" or ""), 1, 0.6, 0.2)
            end
        end
    end

    -- Reissue walk path on the next tick after interception (not same call)
    if walkPathReissueNeeded and isWalking and walkTestTarget ~= nil then
        walkPathReissueNeeded = false
        pcall(function() zombie:pathToLocationF(walkTestTarget.x, walkTestTarget.y, walkTestTarget.z) end)
        if not walkPathReissueLogged then
            walkPathReissueLogged = true
            if consoleWindow ~= nil and not consoleWindow.removed then
                consoleWindow:addLine("Walk path reissued after hostile interception", 0.9, 0.6, 0.2)
            end
        end
    end

    -- Suppress zombie vocalizations — always run (BanditCompatibility.lua:228, 232-237)
    pcall(function()
        local desc = zombie:getDescriptor()
        desc:setVoicePrefix("NotAZombie")
    end)
    pcall(function()
        local emitter = zombie:getEmitter()
        emitter:stopSoundByName("MaleZombieVoiceA")
        emitter:stopSoundByName("MaleZombieVoiceB")
        emitter:stopSoundByName("MaleZombieVoiceC")
        emitter:stopSoundByName("FemaleZombieVoiceA")
        emitter:stopSoundByName("FemaleZombieVoiceB")
        emitter:stopSoundByName("FemaleZombieVoiceC")
    end)

    -- Log first suppression only
    if not zombiePassivityLogged then
        zombiePassivityLogged = true
        if consoleWindow ~= nil and not consoleWindow.removed then
            consoleWindow:addLine("Zombie NPC passivity: target/aggro suppressed, mode=" .. (isWalking and "walking" or "idle"), 0.3, 1, 0.5)
        end
    end
end

Events.OnZombieUpdate.Add(onZombieUpdatePassivity)

-- ── BumpType Idle handler (Bob_Idle experiment) ─────────────────────────────
-- Re-asserts setBumpType("MNB_Idle") on the test zombie only while enabled.
-- Separate from passivity handler; does not modify any existing behavior.

local function onZombieUpdateBumpTypeIdle(zombie)
    if testZombieNpc == nil then return end
    if zombie ~= testZombieNpc then return end

    -- Handle idle-suspension exit detection (walk-test releasing MNB_Idle)
    if idleSuspensionActive then
        local bt = ""
        local asn = ""
        pcall(function() bt = tostring(zombie:getBumpType()) end)
        pcall(function() asn = tostring(zombie:getActionStateName()) end)
        if bt == "" or bt == "nil" then
            idleSuspensionActive = false
            if not idleSuspensionExitLogged then
                idleSuspensionExitLogged = true
                local elapsed = getTimestampMs() - idleSuspensionStartedAt
                if consoleWindow ~= nil and not consoleWindow.removed then
                    consoleWindow:addLine("Walk Test: bumped exit completed after " .. elapsed .. "ms", 0.3, 1, 0.5)
                end
            end
        end
        return
    end

    -- Handle pending exit from looped MNB_Idle
    if bumpTypeExitPending then
        local bt = ""
        local asn = ""
        pcall(function() bt = tostring(zombie:getBumpType()) end)
        pcall(function() asn = tostring(zombie:getActionStateName()) end)

        if bt == "" or bt == "nil" then
            -- Engine naturally cleared bump type — transition fired
            bumpTypeExitPending = false
            if not bumpTypeExitLogged then
                bumpTypeExitLogged = true
                if consoleWindow ~= nil and not consoleWindow.removed then
                    consoleWindow:addLine("Human Idle: OFF — returned to normal idle (asn=" .. asn .. ")", 0.3, 1, 0.5)
                end
            end
            return
        end

        -- Fallback: force clear after 1 second timeout
        local elapsed = getTimestampMs() - bumpTypeExitStartedAt
        if elapsed > 1000 then
            bumpTypeExitPending = false
            pcall(function() zombie:setBumpType("") end)
            pcall(function() zombie:setBumpDone(true) end)
            if consoleWindow ~= nil and not consoleWindow.removed then
                consoleWindow:addLine("Human Idle: OFF — fallback timeout (force-cleared after " .. elapsed .. "ms)", 1, 0.6, 0.2)
            end
        end
        return
    end

    -- Normal reassertion (only when enabled and not walking)
    if not bumpTypeIdleEnabled then return end

    -- Skip reassertion while walking — walk handler controls BumpType during movement
    if walkTestPhase == "walking" then return end

    pcall(function() zombie:setBumpType("MNB_Idle") end)

    if not bumpTypeFirstLogged then
        bumpTypeFirstLogged = true
        if STATE_DIAG_DEBUG then
            local bt = ""
            pcall(function() bt = tostring(zombie:getBumpType()) end)
            print("[MyNPCBuddy] BumpType Idle: first activation — bumpType=" .. bt .. " enabled=true")
        end
    end
end

Events.OnZombieUpdate.Add(onZombieUpdateBumpTypeIdle)

-- ── BumpType Idle toggle handler ─────────────────────────────────────────────

function MyNPCConsole:onBumpTypeIdleToggle()
    if testZombieNpc == nil then
        self:addLine("Human Idle: no test zombie spawned", 1, 0.7, 0.2)
        return
    end

    bumpTypeIdleEnabled = not bumpTypeIdleEnabled

    if bumpTypeIdleEnabled then
        bumpTypeFirstLogged = false
        bumpTypeExitPending = false
        bumpTypeExitLogged = false
        self.btnBumpTypeIdle:setTitle("Human Idle: ON")
        self:addLine("Human Idle: ON — re-asserting Bob_Idle via MNB_Idle bump type", 0.3, 1, 0.5)
    else
        -- Disable flag first so onZombieUpdateBumpTypeIdle cannot reassert MNB_Idle
        bumpTypeIdleEnabled = false
        bumpTypeExitPending = true
        bumpTypeExitStartedAt = getTimestampMs()
        bumpTypeExitLogged = false
        self.btnBumpTypeIdle:setTitle("Human Idle: OFF")
        -- Arm the action-group transition: BumpAnimFinished=true triggers bumped→idle
        -- Do NOT clear BumpType or changeState here — let BumpedState.exit() handle it
        pcall(function() testZombieNpc:setVariable("BumpAnimFinished", true) end)
        pcall(function() testZombieNpc:setBumpDone(true) end)
        self:addLine("Human Idle: OFF — armed BumpAnimFinished, waiting for engine transition", 0.9, 0.6, 0.2)
    end
end

-- ── Walk Test handler (SP-only) ──────────────────────────────────────────────
-- Moves the harmless test zombie 3-5 tiles on flat open ground using vanilla B42
-- pathfinding, playing Bob_Walk upright animation. Remains harmless throughout.

local function distToTarget(zombie, target)
    if not target then return 999 end
    local dx = zombie:getX() - target.x
    local dy = zombie:getY() - target.y
    return math.sqrt(dx * dx + dy * dy)
end

local function findWalkTarget(zombie)
    local zx = math.floor(zombie:getX())
    local zy = math.floor(zombie:getY())
    local zz = zombie:getZ()
    local cell = zombie:getCell()

    -- Try north first, then east, in 3-5 tile range
    local candidates = {}
    for dist = 5, 3, -1 do
        table.insert(candidates, {x = zx,     y = zy - dist, z = zz})
        table.insert(candidates, {x = zx + dist, y = zy,     z = zz})
    end

    for _, t in ipairs(candidates) do
        local sq = cell:getGridSquare(t.x, t.y, t.z)
        if sq and sq:isFree(false) and not sq:isSomethingTo(zombie:getSquare()) then
            return t
        end
    end
    return nil
end

local function cancelWalkTest(logFn)
    if testZombieNpc ~= nil then
        pcall(function() testZombieNpc:setPath2(nil) end)
    end
    walkTestActive = false
    walkTestTarget = nil
    walkTestPhase = "idle"
    walkTestFirstLogged = false
    idleSuspensionActive = false
    resetStateDiag()
    if consoleWindow ~= nil and not consoleWindow.removed then
        consoleWindow.btnWalkTest:setTitle("Walk Test: OFF")
    end
    if logFn then logFn() end
end

local function onZombieUpdateWalkTest(zombie)
    if not walkTestActive then return end
    if testZombieNpc == nil then return end
    if zombie ~= testZombieNpc then return end

    if walkTestPhase == "walking" then
        -- Engine controls (useless/speedMod/walkType) now handled by passivity handler

        -- pathToLocationF handles movement internally — just check distance for arrival
        local d = distToTarget(zombie, walkTestTarget)

        if not walkTestFirstLogged then
            walkTestFirstLogged = true
            local bt = ""
            local wt = ""
            local tgt = nil
            local useless = false
            pcall(function() bt = tostring(zombie:getBumpType()) end)
            pcall(function() wt = tostring(zombie:getWalkType()) end)
            pcall(function() tgt = zombie:getTarget() end)
            pcall(function() useless = zombie:isUseless() end)
            local tgtStr = "nil"
            if tgt ~= nil then tgtStr = tostring(tgt) end
            if STATE_DIAG_DEBUG then
                print("[MyNPCBuddy] Walk Test: first tick — bumpType=" .. bt .. " walkType=" .. wt .. " target=" .. tgtStr .. " isUseless=" .. tostring(useless) .. " distToTarget=" .. string.format("%.2f", d))

                if not walkTypeDiagnosticLogged then
                    walkTypeDiagnosticLogged = true
                    local origWt = ""
                    pcall(function() origWt = tostring(zombie:getModData().MyNPCBuddyOriginalWalkType) end)
                    local reqWt = bumpTypeIdleEnabled and "Walk" or (origWt ~= "" and origWt or "Walk")
                    print("[MyNPCBuddy] Walk Type Diagnostic: original=" .. origWt .. " requested=" .. reqWt .. " humanIdle=" .. tostring(bumpTypeIdleEnabled))
                end
            end
            if consoleWindow ~= nil and not consoleWindow.removed then
                consoleWindow:addLine("Walk Test: moving to (" .. walkTestTarget.x .. "," .. walkTestTarget.y .. ") dist=" .. string.format("%.2f", d) .. " [SP-only]", 0.3, 1, 0.5)
            end
        end

        -- State-transition diagnostics (gated by STATE_DIAG_DEBUG — logs only on value change)
        if STATE_DIAG_DEBUG then
            logStateDiag(zombie)
        end

        -- Arrival: distance < 1.0
        local arrived = (d < 1.0)

        -- Failure: timeout (10 seconds)
        local elapsed = getTimestampMs() - walkTestStartedAt
        local failed = (elapsed > 10000)

        if arrived then
            walkTestPhase = "arrived"
            pcall(function() zombie:setPath2(nil) end)

            -- Final state-diag snapshot before reset
            if STATE_DIAG_DEBUG then
                logStateDiag(zombie)
            end
            resetStateDiag()

            -- Passivity handler will restore useless=true/speedMod=0 on next tick

            -- Resume MNB_Idle if Human Idle is enabled, else arm transition
            idleSuspensionActive = false
            if bumpTypeIdleEnabled then
                pcall(function() zombie:setBumpType("MNB_Idle") end)
                if consoleWindow ~= nil and not consoleWindow.removed then
                    consoleWindow:addLine("Walk Test: resuming MNB_Idle at arrival", 0.3, 1, 0.5)
                end
            else
                bumpTypeExitPending = true
                bumpTypeExitStartedAt = getTimestampMs()
                bumpTypeExitLogged = false
                pcall(function() zombie:setVariable("BumpAnimFinished", true) end)
                pcall(function() zombie:setBumpDone(true) end)
            end

            local fx, fy = zombie:getX(), zombie:getY()
            if consoleWindow ~= nil and not consoleWindow.removed then
                consoleWindow:addLine("Walk Test: arrived at (" .. string.format("%.1f", fx) .. "," .. string.format("%.1f", fy) .. ")", 0.3, 1, 0.5)
                consoleWindow.btnWalkTest:setTitle("Walk Test: OFF")
            end
            walkTestActive = false
            walkTestTarget = nil
            walkTestPhase = "idle"
            walkTestFirstLogged = false

        elseif failed then
            walkTestPhase = "failed"
            pcall(function() zombie:setPath2(nil) end)

            -- Final state-diag snapshot before reset
            if STATE_DIAG_DEBUG then
                logStateDiag(zombie)
            end
            resetStateDiag()

            -- Passivity handler will restore useless=true/speedMod=0 on next tick

            idleSuspensionActive = false
            if bumpTypeIdleEnabled then
                pcall(function() zombie:setBumpType("MNB_Idle") end)
            else
                bumpTypeExitPending = true
                bumpTypeExitStartedAt = getTimestampMs()
                bumpTypeExitLogged = false
                pcall(function() zombie:setVariable("BumpAnimFinished", true) end)
                pcall(function() zombie:setBumpDone(true) end)
            end

            local fx, fy = zombie:getX(), zombie:getY()
            local reason = "path failed"
            if elapsed > 10000 then reason = "timeout" end
            if consoleWindow ~= nil and not consoleWindow.removed then
                consoleWindow:addLine("Walk Test: " .. reason .. " at (" .. string.format("%.1f", fx) .. "," .. string.format("%.1f", fy) .. ")", 1, 0.6, 0.2)
                consoleWindow.btnWalkTest:setTitle("Walk Test: OFF")
            end
            walkTestActive = false
            walkTestTarget = nil
            walkTestPhase = "idle"
            walkTestFirstLogged = false
        end
    end
end

Events.OnZombieUpdate.Add(onZombieUpdateWalkTest)

-- ── Walk Test toggle handler ──────────────────────────────────────────────────

function MyNPCConsole:onWalkTestToggle()
    if testZombieNpc == nil then
        self:addLine("Walk Test: no test zombie spawned", 1, 0.7, 0.2)
        return
    end

    if walkTestActive then
        -- Cancel ongoing walk
        cancelWalkTest(function()
            self:addLine("Walk Test: cancelled, restoring passivity", 0.9, 0.6, 0.2)
        end)
        -- Restore passivity immediately
        pcall(function() testZombieNpc:setUseless(true) end)
        pcall(function() testZombieNpc:setSpeedMod(0) end)
        idleSuspensionActive = false
        if bumpTypeIdleEnabled then
            pcall(function() testZombieNpc:setBumpType("MNB_Idle") end)
        else
            bumpTypeExitPending = true
            bumpTypeExitStartedAt = getTimestampMs()
            bumpTypeExitLogged = false
            pcall(function() testZombieNpc:setVariable("BumpAnimFinished", true) end)
            pcall(function() testZombieNpc:setBumpDone(true) end)
        end
        return
    end

    -- Start new walk test
    local target = findWalkTarget(testZombieNpc)
    if target == nil then
        self:addLine("Walk Test: no reachable open tile found 3-5 tiles away", 1, 0.6, 0.2)
        return
    end

    walkTestTarget = target
    walkTestActive = true
    walkTestPhase = "walking"
    walkTestFirstLogged = false
    walkTestStartedAt = getTimestampMs()
    hostileInterceptLogged = false
    walkPathReissueNeeded = false
    walkPathReissueLogged = false
    walkTypeDiagnosticLogged = false

    -- Activate state-transition diagnostics (gated by STATE_DIAG_DEBUG)
    resetStateDiag()
    stateDiagActive = STATE_DIAG_DEBUG

    -- Suspend MNB_Idle for locomotion if Human Idle is active
    if bumpTypeIdleEnabled then
        idleSuspensionActive = true
        idleSuspensionStartedAt = getTimestampMs()
        idleSuspensionExitLogged = false
        pcall(function() testZombieNpc:setVariable("BumpAnimFinished", true) end)
        pcall(function() testZombieNpc:setBumpDone(true) end)
        if consoleWindow ~= nil and not consoleWindow.removed then
            consoleWindow:addLine("Walk Test: releasing MNB_Idle for locomotion", 0.9, 0.7, 0.3)
        end
    end

    -- Issue path command once (ZAGoTo.lua:42 pattern — pathToLocationF avoids WalkTowardState/path2 conflict)
    pcall(function() testZombieNpc:pathToLocationF(target.x, target.y, target.z) end)

    self.btnWalkTest:setTitle("Walk Test: ON")
    self:addLine("Walk Test: pathing to (" .. target.x .. "," .. target.y .. ") [SP-only]", 0.3, 1, 0.5)
end

local function onSaveCleanup()
    if activeTestMover ~= nil then
        print("[MyNPCBuddy] OnSave: despawning active test mover before save")
        despawnActiveTestMover(nil)
        if consoleWindow ~= nil and not consoleWindow.removed then
            consoleWindow:addLine("OnSave: test mover removed before save", 1, 0.8, 0.2)
        end
    end
    -- Also cleanup test NPC before save
    local hasNpc = false
    pcall(function() hasNpc = DebugBridge.hasTestNpc() end)
    if hasNpc then
        print("[MyNPCBuddy] OnSave: removing test NPC before save")
        pcall(function() DebugBridge.cleanupTestNpc() end)
        if consoleWindow ~= nil and not consoleWindow.removed then
            consoleWindow:addLine("OnSave: test NPC removed before save", 1, 0.8, 0.2)
        end
    end
    -- Cleanup test zombie NPC before save
    if testZombieNpc ~= nil then
        print("[MyNPCBuddy] OnSave: removing test zombie NPC before save")
        despawnTestZombieNpc(nil)
        if consoleWindow ~= nil and not consoleWindow.removed then
            consoleWindow:addLine("OnSave: test zombie NPC removed before save", 1, 0.8, 0.2)
        end
    end
end

local function onMainMenuCleanup()
    if activeTestMover ~= nil then
        print("[MyNPCBuddy] OnMainMenu: despawning active test mover")
        despawnActiveTestMover(nil)
        activeTestMover = nil
    end
    -- Also cleanup test NPC on main menu
    local hasNpc = false
    pcall(function() hasNpc = DebugBridge.hasTestNpc() end)
    if hasNpc then
        print("[MyNPCBuddy] OnMainMenu: removing test NPC")
        pcall(function() DebugBridge.cleanupTestNpc() end)
    end
    -- Cleanup test zombie NPC on main menu
    if testZombieNpc ~= nil then
        print("[MyNPCBuddy] OnMainMenu: removing test zombie NPC")
        despawnTestZombieNpc(nil)
    end
end

-- ── NPC visibility maintenance (separate from companion brain) ───────────────

local function onTickNpcVisibility()
    local hasNpc = false
    pcall(function() hasNpc = DebugBridge.hasTestNpc() end)
    if hasNpc then
        pcall(function() DebugBridge.maintainTestNpcVisibility() end)
    end
end
Events.OnTick.Add(onTickNpcVisibility)

Events.OnSave.Add(onSaveCleanup)
Events.OnMainMenuEnter.Add(onMainMenuCleanup)
