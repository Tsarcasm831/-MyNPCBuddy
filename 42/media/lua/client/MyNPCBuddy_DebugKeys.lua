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
local NUM_ROWS    = 6    -- total button rows

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
        print("[ZB] Marker render error (logged once): " .. tostring(err))
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

    self:reflowRows()
end

function MyNPCConsole:onResize()
    if self.width  < CONSOLE_MIN_W then self.width  = CONSOLE_MIN_W end
    if self.height < CONSOLE_MIN_H then self.height = CONSOLE_MIN_H end
    consoleW = self.width
    consoleH = self.height
    self:reflowRows()
end

function MyNPCConsole:addLine(text, r, g, b)
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
        self:addLine("pos  x=" .. x .. "  y=" .. y .. "  z=" .. z, 0.3, 1, 0.3)
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
    self:addLine("Scan: player at x=" .. x .. " y=" .. y .. " z=" .. z, 0.5, 0.8, 1)
    self:addLine("Check console.txt for full zombie scan results", 0.6, 0.6, 0.6)
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
        self:addLine("Order set: STAY, holding vpos=(" .. vx .. "," .. vy .. "," .. vz .. ")", 1.0, 0.85, 0.2)
    elseif order == "SCOUT" then
        local ok2 = pcall(function() return DebugBridge.companionHasScoutAnchor() end)
        local ax = string.format("%.1f", DebugBridge.companionGetScoutAnchorX())
        local ay = string.format("%.1f", DebugBridge.companionGetScoutAnchorY())
        local az = string.format("%.0f", DebugBridge.companionGetScoutAnchorZ())
        self:addLine("Order set: SCOUT, anchor=(" .. ax .. "," .. ay .. "," .. az .. ")", 0.8, 0.4, 1.0)
    else
        self:addLine("Order set: " .. order, 0.3, 1, 0.5)
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
    self:addLine("Marker detail: " .. markerDetail, 0.3, 0.8, 1.0)
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
        markerEnabled and "Marker ON — debug overlay active" or "Marker OFF",
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
        self:addLine("Virtual companion pos reset: x=" .. x .. " y=" .. y .. " z=" .. z, 1.0, 0.6, 0.2)
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
        console:addLine(label .. ": nil result", 1, 0.4, 0.4)
        return
    end
    for line in string.gmatch(tostring(result), "[^\n]+") do
        console:addLine(line, 0.6, 0.9, 1.0)
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
    consoleWindow:addLine("MyNPCBuddy console ready — press F9 or click Probe Pos", 0.5, 0.8, 1)
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

-- ── Safety cleanup on save and main menu ─────────────────────────────────────

local function onSaveCleanup()
    if activeTestMover ~= nil then
        print("[ZB] OnSave: despawning active test mover before save")
        despawnActiveTestMover(nil)
        if consoleWindow ~= nil and not consoleWindow.removed then
            consoleWindow:addLine("OnSave: test mover removed before save", 1, 0.8, 0.2)
        end
    end
end

local function onMainMenuCleanup()
    if activeTestMover ~= nil then
        print("[ZB] OnMainMenu: despawning active test mover")
        despawnActiveTestMover(nil)
        activeTestMover = nil
    end
end

Events.OnSave.Add(onSaveCleanup)
Events.OnMainMenuEnter.Add(onMainMenuCleanup)
