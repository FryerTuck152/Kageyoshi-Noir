local function getService(name)
	local ok, svc = pcall(function()
		if cloneref then return cloneref(game:GetService(name)) end
		return game:GetService(name)
	end)
	if ok and svc then return svc end
	return game:GetService(name)
end

if not game:IsLoaded() then repeat task.wait() until game:IsLoaded() end

local Players          = getService("Players")
local RunService       = getService("RunService")
local UserInputService = getService("UserInputService")
local TweenService     = getService("TweenService")
local CoreGui          = (gethui and gethui()) or getService("CoreGui")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer   -- don't clone — crashes require

local function rnd(len)
	local c = "abcdefghijklmnopqrstuvwxyz0123456789"
	local t = {}
	for i = 1, (len or math.random(9, 14)) do
		local n = math.random(1, #c); t[i] = c:sub(n, n)
	end
	return table.concat(t)
end

-- randomized inst names per launch, so they can't be sniffed by fixed names
local RN = {
	FlyMover  = rnd(), FlyAtt = rnd(), FlyGyro = rnd(),
	GoldMover = rnd(), GoldAtt = rnd(), GoldGyro = rnd(),
	Gui = rnd(), CursorGui = rnd(), StatsGui = rnd(), Plate = rnd(),
}

-- one key for everything — to clean up the previous run
local KEY = "\0__np_" .. tostring(game.PlaceId % 997)
getgenv()[KEY] = getgenv()[KEY] or {}
local G = getgenv()[KEY]
for k, v in pairs(G) do
	if typeof(v) == "RBXScriptConnection" then pcall(function() v:Disconnect() end); G[k] = nil
	elseif typeof(v) == "Instance" then pcall(function() v:Destroy() end); G[k] = nil end
end
G.shutdown = false

local function hiddenParent(obj)
	pcall(function() if syn and syn.protect_gui then syn.protect_gui(obj) end end)
	obj.Parent = CoreGui
end

-- residue cleanup from the previous ESP
if G.espCache then
	for _, playerCache in pairs(G.espCache) do
		for k, obj in pairs(playerCache) do
			if typeof(obj) == "Instance" then
				pcall(function() obj:Destroy() end)
			elseif type(obj) == "table" and obj.Remove then
				pcall(function() obj:Remove() end)
			end
		end
	end
end
G.espCache = {}
-- cleanup leftover Hitbox adornments from the previous run
if G.hitboxCache then
	for _, adorn in pairs(G.hitboxCache) do
		if typeof(adorn) == "Instance" then pcall(function() adorn:Destroy() end) end
	end
end
G.hitboxCache = {}
local espCache = G.espCache
local _SIZE_OFFSET = Vector3.new(0.05, 0.05, 0.05)

G.gold = false; G.goldClaim = false; G.autoFort = false
G.slapple = false; G.spoofMask = false; G.antirag = false

local ESP = { Enabled = false, ShowTeam = true, Mode = "Cubes", ChamsTransparency = 0.5, Hue = 0.5, Shade = 0.5, Color = Color3.fromRGB(95, 205, 228), Radius = 10000, PFMode = false, ShowNames = false, ShowHealth = false, ShowDistance = false, ShowHealthBar = false, MM2Mode = false }
local PlayerMods = { SpeedEnabled = false, SpeedValue = 16, JumpEnabled = false, JumpValue = 50, FlyEnabled = false, FlySpeed = 50, NoclipEnabled = false, WallWalkEnabled = false, InfJumpEnabled = false, AntiKnockback = false }

local Aim = {
	Enabled = false,
	ActivationKey = Enum.KeyCode.E,
	ActivationInput = nil,  -- UserInputType (e.g. RMB) takes precedence if set
	TeamCheck = false,
	FOV_Radius = 250,
	ShowFOV = true,
	AimPart = "Head",
	Smoothing = 5,  -- 1 = snap, higher = smoother
	MaxDistance = 500,
	WallCheck = true,
	PredictionEnabled = false,
	PredictionStrength = 0.12,
	TargetMode = "Closest to Crosshair",
	AimLock = false,
}

local Crosshair = {
	Enabled = false,
	Left = true, Right = true, Top = true, Bottom = true,
	Length = 10, Width = 2, Gap = 4,
	DotEnabled = false,
	DotThickness = 2,
	Color = Color3.fromRGB(255, 75, 150),
}

local _charParts = {}
local _charPartsFor = nil
local function _rebuildParts()
	local char = LocalPlayer.Character
	_charPartsFor = char
	local t = {}
	if char then
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") then t[#t+1] = d end
		end
	end
	_charParts = t
end
local function _ensureParts()
	local char = LocalPlayer.Character
	if char ~= _charPartsFor then _rebuildParts() end
end
local function _restoreCollision()
	_ensureParts()
	for _, p in ipairs(_charParts) do
		if p.Parent then p.CanCollide = true end
	end
end

local function updateColor()
	local h = ESP.Hue
	local s, v = 1, 1
	if ESP.Shade < 0.5 then
		v = ESP.Shade * 2; s = 1
	else
		v = 1; s = 1 - ((ESP.Shade - 0.5) * 2)
	end
	ESP.Color = Color3.fromHSV(h, s, v)
end

local function clearESP(player)
	if espCache[player] then
		local cache = espCache[player]
		if cache._cubes then
			for _, obj in pairs(cache._cubes) do
				if typeof(obj) == "Instance" then pcall(function() obj:Destroy() end) end
			end
		end
		for k, obj in pairs(cache) do
			if k ~= "Character" and k ~= "lastMode" and k ~= "_cubes" then
				if typeof(obj) == "Instance" then pcall(function() obj:Destroy() end)
				else pcall(function() obj:Remove() end) end
			end
		end
		espCache[player] = nil
	end
end

-- forward declaration; реализация ниже, рядом с resolveCharacter
local _pfEspClear, _pfMyTeamCached, _pfAnalyzeTeams

local THEME = {
	BG_MAIN   = Color3.fromRGB(12, 12, 14),
	BG_SIDE   = Color3.fromRGB(18, 18, 22),
	BG_TOP    = Color3.fromRGB(18, 18, 22),
	NEON      = Color3.fromRGB(255, 75, 150),
	DIM_NEON  = Color3.fromRGB(60, 30, 50),
	TEXT_MAIN = Color3.fromRGB(245, 245, 250),
	TEXT_DIM  = Color3.fromRGB(180, 180, 195),
	UI_ELEM   = Color3.fromRGB(25, 25, 30),
	KILL      = Color3.fromRGB(255, 30, 50),
}

local function glowStroke(obj, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = THEME.NEON
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0.3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

-- adaptive mouse fix — gives control back to the game when menu is closed
local menuIsOpen = true
local menuToken = 0
local rmbHeld = false

local function isShiftLockOptionEnabled()
	local ok, res = pcall(function()
		return UserSettings():GetService("UserGameSettings").ControlMode
			== Enum.ControlMode.MouseLockSwitch
	end)
	return ok and res or false
end

-- is the player in a mode where the camera wants to lock the cursor?
-- (first person or shift lock on). used to not interfere while menu is closed.
local function gameWantsLock()
	if isShiftLockOptionEnabled() then return true end
	-- first person: camera-to-focus distance is tiny
	local ok, dist = pcall(function()
		return (Camera.CFrame.Position - Camera.Focus.Position).Magnitude
	end)
	if ok and dist and dist <= 1.5 then return true end
	return false
end

G.rmbBegan = UserInputService.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton2 then rmbHeld = true end
end)
G.rmbEnded = UserInputService.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton2 then rmbHeld = false end
end)

-- while menu open: keep the cursor free. works even on "sticky" games (TC2),
-- since each frame we revert to Default if the game re-locked (but don't break RMB camera turn).
G.openCursorLoop = RunService.RenderStepped:Connect(function()
	if G.shutdown or not menuIsOpen then return end
	if rmbHeld then return end  -- turning camera with RMB — don't interfere
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	if not UserInputService.MouseIconEnabled then
		UserInputService.MouseIconEnabled = true
	end
end)

-- while menu CLOSED: don't force a mode. hand control to the game.
-- only emergency: cursor stuck in LockCenter but the game doesn't want it
-- (not first-person, not shift-lock, RMB not held) -> release.
G.closedCursorLoop = RunService.RenderStepped:Connect(function()
	if G.shutdown or menuIsOpen then return end
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then return end
	if rmbHeld or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end
	if gameWantsLock() then return end  -- game legitimately wants lock — leave it
	pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = RN.Gui
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hiddenParent(ScreenGui)
G.gui = ScreenGui

local function onMenuToggle(isOpening)
	menuToken = menuToken + 1
	local myToken = menuToken
	if isOpening then
		hiddenParent(ScreenGui)
		menuIsOpen = true
		-- Импульс: сразу освобождаем курсор (для залипающих игр вроде TC2)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		-- Подстраховка на несколько кадров: если игра тут же залочит — вернём Default
		task.spawn(function()
			for _ = 1, 6 do
				if menuToken ~= myToken or not menuIsOpen then return end
				if not rmbHeld and UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
					UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				end
				UserInputService.MouseIconEnabled = true
				RunService.RenderStepped:Wait()
			end
		end)
	else
		menuIsOpen = false
		ScreenGui.Parent = nil
		-- НЕ навязываем режим. Даём игре кадр, чтобы её контроллер камеры выставил
		-- корректный MouseBehavior (LockCenter для FP/shiftlock, Default иначе).
		-- closedCursorLoop подстрахует от ложного зависания в центре.
	end
end
onMenuToggle(true)

-----------------------------------
-- MAIN FRAME
-----------------------------------
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 720, 0, 460)
MainFrame.Position = UDim2.new(0.5, -360, 0.5, -230)
MainFrame.BackgroundColor3 = THEME.BG_MAIN
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
do
	local og = Instance.new("UIStroke", MainFrame)
	og.Color = THEME.NEON; og.Thickness = 1.5; og.Transparency = 0.4
end

-----------------------------------
-- TOP HEADER
-----------------------------------
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 44)
Header.BackgroundColor3 = THEME.BG_TOP
Header.BorderSizePixel = 0
Header.Parent = MainFrame
Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 10)
do
	local cover = Instance.new("Frame", Header)
	cover.Size = UDim2.new(1, 0, 0, 12)
	cover.Position = UDim2.new(0, 0, 1, -12)
	cover.BackgroundColor3 = THEME.BG_TOP
	cover.BorderSizePixel = 0
end

local GreetingLabel = Instance.new("TextLabel")
GreetingLabel.Size = UDim2.new(0, 110, 1, 0)
GreetingLabel.Position = UDim2.new(0, 14, 0, 0)
GreetingLabel.BackgroundTransparency = 1
GreetingLabel.Text = utf8.char(0x3053, 0x3093, 0x306B, 0x3061, 0x306F) -- konnichiwa
GreetingLabel.TextColor3 = THEME.TEXT_MAIN
GreetingLabel.Font = Enum.Font.GothamBold
GreetingLabel.TextSize = 16
GreetingLabel.TextXAlignment = Enum.TextXAlignment.Left
GreetingLabel.Parent = Header

local SearchBox = Instance.new("TextBox")
SearchBox.Size = UDim2.new(1, -380, 0, 28)
SearchBox.Position = UDim2.new(0, 130, 0.5, -14)
SearchBox.BackgroundColor3 = THEME.UI_ELEM
SearchBox.TextColor3 = THEME.TEXT_MAIN
SearchBox.PlaceholderText = "Search functions..."
SearchBox.PlaceholderColor3 = THEME.TEXT_DIM
SearchBox.Text = ""
SearchBox.Font = Enum.Font.Gotham
SearchBox.TextSize = 13
SearchBox.TextXAlignment = Enum.TextXAlignment.Left
SearchBox.ClearTextOnFocus = false
SearchBox.Parent = Header
Instance.new("UICorner", SearchBox).CornerRadius = UDim.new(0, 6)
glowStroke(SearchBox, 0.6, 0.7)
do local p = Instance.new("UIPadding", SearchBox); p.PaddingLeft = UDim.new(0, 10) end

local ClockLabel = Instance.new("TextLabel")
ClockLabel.Size = UDim2.new(0, 80, 1, 0)
ClockLabel.Position = UDim2.new(1, -260, 0, 0)
ClockLabel.BackgroundTransparency = 1
ClockLabel.Text = "--:--:--"
ClockLabel.TextColor3 = THEME.TEXT_MAIN
ClockLabel.Font = Enum.Font.GothamBold
ClockLabel.TextSize = 14
ClockLabel.Parent = Header

local StatsLabel = Instance.new("TextLabel")
StatsLabel.Size = UDim2.new(0, 120, 1, 0)
StatsLabel.Position = UDim2.new(1, -130, 0, 0)
StatsLabel.BackgroundTransparency = 1
StatsLabel.Text = "FPS 0 | Ping 0"
StatsLabel.TextColor3 = THEME.NEON
StatsLabel.Font = Enum.Font.GothamBold
StatsLabel.TextSize = 13
StatsLabel.Parent = Header

-----------------------------------
-- SIDEBAR
-----------------------------------
local SideBar = Instance.new("Frame")
SideBar.Size = UDim2.new(0, 130, 1, -44)
SideBar.Position = UDim2.new(0, 0, 0, 44)
SideBar.BackgroundColor3 = THEME.BG_SIDE
SideBar.BorderSizePixel = 0
SideBar.Parent = MainFrame
Instance.new("UICorner", SideBar).CornerRadius = UDim.new(0, 10)

local TabList = Instance.new("ScrollingFrame")
TabList.Size = UDim2.new(1, 0, 1, -50)
TabList.Position = UDim2.new(0, 0, 0, 10)
TabList.BackgroundTransparency = 1
TabList.BorderSizePixel = 0
TabList.ScrollBarThickness = 4
TabList.ScrollBarImageColor3 = THEME.NEON
TabList.ScrollBarImageTransparency = 0.5
TabList.AutomaticCanvasSize = Enum.AutomaticSize.Y
TabList.CanvasSize = UDim2.new(0, 0, 0, 0)
TabList.ScrollingEnabled = true
TabList.CanvasPosition = Vector2.new(0, 0)
TabList.Parent = SideBar
do
	local l = Instance.new("UIListLayout", TabList)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Top
	l.Padding = UDim.new(0, 4)
end
local _tabListPad = Instance.new("UIPadding", TabList)
_tabListPad.PaddingBottom = UDim.new(0, 8)

local KillBtn = Instance.new("TextButton")
KillBtn.Size = UDim2.new(1, -16, 0, 36)
KillBtn.Position = UDim2.new(0, 8, 1, -46)
KillBtn.BackgroundColor3 = THEME.KILL
KillBtn.Text = "KILL"
KillBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
KillBtn.Font = Enum.Font.GothamBold
KillBtn.TextSize = 14
KillBtn.Parent = SideBar
Instance.new("UICorner", KillBtn).CornerRadius = UDim.new(0, 8)
glowStroke(KillBtn, 1, 0.3)

-----------------------------------
-- CONTENT AREA + TABS
-----------------------------------
local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -130, 1, -44)
ContentArea.Position = UDim2.new(0, 130, 0, 44)
ContentArea.BackgroundTransparency = 1
ContentArea.Parent = MainFrame

local TAB_DEFS = {}
local ACTIVE_TAB = nil

--==== PART A: SMART PER-TAB SCROLLING ==========================
-- createTabContainer: ScrollingFrame with AutomaticCanvasSize=Y, CanvasSize=0,
--   ScrollingEnabled=false by default. RETURNS (container, layout).
local function createTabContainer()
	local c = Instance.new("ScrollingFrame")
	c.Size = UDim2.new(1, -20, 1, -20)
	c.Position = UDim2.new(0, 10, 0, 10)
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.ScrollBarThickness = 4
	c.ScrollBarImageColor3 = THEME.NEON
	c.ScrollBarImageTransparency = 0.5
	c.AutomaticCanvasSize = Enum.AutomaticSize.Y
	c.CanvasSize = UDim2.new(0, 0, 0, 0)
	c.ScrollingEnabled = false
	c.Visible = false
	c.Parent = ContentArea
	local l = Instance.new("UIListLayout", c)
	l.Padding = UDim.new(0, 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	local p = Instance.new("UIPadding", c)
	p.PaddingTop = UDim.new(0, 2); p.PaddingBottom = UDim.new(0, 8)
	return c, l
end

-- refreshScroll: enables scrolling ONLY when content exceeds the area height
local function refreshScroll(def)
	if not def then return end
	-- Force a recompute of AutomaticCanvasSize: re-assign the property
	local c = def.container
	local auto = c.AutomaticCanvasSize
	c.AutomaticCanvasSize = Enum.AutomaticSize.None
	c.AutomaticCanvasSize = auto
	local content = def.layout.AbsoluteContentSize.Y
	local view = c.AbsoluteSize.Y
	c.ScrollingEnabled = (content > view + 2)
end

-- ==== TAB LIST =================================================
local TAB_NAMES = { "ESP", "Player", "Aim", "Babft", "Movement", "Slap Battles", "Performance", "Integration", "Crosshair", "Debug", "Etc" }

for _, name in ipairs(TAB_NAMES) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -16, 0, 32)
	btn.BackgroundColor3 = THEME.UI_ELEM
	btn.Text = "  " .. name
	btn.TextColor3 = THEME.TEXT_DIM
	btn.Font = Enum.Font.Gotham
	btn.TextSize = 13
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.Parent = TabList
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	local container, layout = createTabContainer()
	local def = { name = name, btn = btn, container = container, layout = layout, rows = {} }
	table.insert(TAB_DEFS, def)
	-- Connect the AbsoluteContentSize change signal for each tab
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if def.container.Visible then
			task.defer(function() refreshScroll(def) end)
		end
	end)
end

ACTIVE_TAB = TAB_DEFS[1]
ACTIVE_TAB.btn.TextColor3 = THEME.NEON
ACTIVE_TAB.btn.BackgroundColor3 = THEME.DIM_NEON
ACTIVE_TAB.container.Visible = true

local function switchTab(targetBtn)
	for _, def in ipairs(TAB_DEFS) do
		local on = def.btn == targetBtn
		def.btn.TextColor3 = on and THEME.NEON or THEME.TEXT_DIM
		def.btn.BackgroundColor3 = on and THEME.DIM_NEON or THEME.UI_ELEM
		def.container.Visible = on
		if on then ACTIVE_TAB = def end
	end
	-- Refresh scroll for the active tab
	task.defer(function() refreshScroll(ACTIVE_TAB) end)
end
for _, def in ipairs(TAB_DEFS) do
	def.btn.MouseButton1Click:Connect(function() switchTab(def.btn) end)
end

-----------------------------------
-- ROW SYSTEM (rows + sub-options + search)
-----------------------------------
-- Each row: { frame, searchKey, parentRow, children, enabledByParent, visibleBySearch, visibleExtra }
-- Visibility = visibleBySearch AND enabledByParent AND visibleExtra (if defined)

local function updateRow(row)
	local vs = row.visibleBySearch; if vs == nil then vs = true end
	local ep = row.enabledByParent; if ep == nil then ep = true end
	local ve = row.visibleExtra
	if ve == nil then ve = true
	elseif type(ve) == "function" then ve = ve(row) end
	row.frame.Visible = (vs and ep and ve) and true or false
end

local function registerRow(frame, searchKey, parentRow)
	frame.Parent = ACTIVE_TAB.container
	local row = {
		frame = frame,
		searchKey = searchKey or "",
		parentRow = parentRow,
		children = {},
		enabledByParent = (parentRow == nil), -- sub-rows hidden while parent is off
		visibleBySearch = true,
		visibleExtra = nil, -- nil = true; otherwise bool or function(row)->bool
	}
	frame.LayoutOrder = #ACTIVE_TAB.rows + 1
	table.insert(ACTIVE_TAB.rows, row)
	if parentRow and parentRow.children then table.insert(parentRow.children, row) end
	updateRow(row)
	return row
end

-- Show/hide sub-options when toggling the parent
local function setChildrenEnabled(parentRow, enabled)
	if not parentRow then return end
	if parentRow.children then
		for _, child in ipairs(parentRow.children) do
			child.enabledByParent = enabled
			updateRow(child)
		end
	end
	-- Refresh scroll for the active tab after a visibility change.
	-- Wait a frame so UIListLayout finishes recomputing AbsoluteContentSize.
	task.spawn(function()
		RunService.Heartbeat:Wait()
		RunService.Heartbeat:Wait()
		refreshScroll(ACTIVE_TAB)
	end)
end

-- Search: filters rows by searchKey
SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
	local q = string.lower(SearchBox.Text or "")
	for _, def in ipairs(TAB_DEFS) do
		for _, row in ipairs(def.rows) do
			row.visibleBySearch = (q == "")
				or (string.find(string.lower(row.searchKey), q, 1, true) ~= nil)
			updateRow(row)
		end
	end
	-- Refresh scroll for the active tab after searching
	task.defer(function() refreshScroll(ACTIVE_TAB) end)
end)

-----------------------------------
-- SLIDER REGISTRY (one loop for all sliders)
-----------------------------------
local _sliders = {}
local _dragging = false
G.sliderLoop = RunService.RenderStepped:Connect(function()
	if G.shutdown or not _dragging then return end
	_dragging = false
	for _, s in ipairs(_sliders) do
		if s.dragging then
			_dragging = true
			local mx = UserInputService:GetMouseLocation().X
			local rel = math.clamp((mx - s.bg.AbsolutePosition.X) / s.bg.AbsoluteSize.X, 0, 1)
			s.fill.Size = UDim2.new(rel, 0, 1, 0)
			s.marker.Position = UDim2.new(rel, -3, 0, -3)
			if s.minVal and s.maxVal then
				local val = math.floor(s.minVal + (s.maxVal - s.minVal) * rel)
				if s.vbox then s.vbox.Text = tostring(val) end
				s.cb(val)
			else
				s.cb(rel)
			end
		end
	end
end)
G.sliderEnd = UserInputService.InputEnded:Connect(function(i)
	if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	for _, s in ipairs(_sliders) do s.dragging = false end
	_dragging = false
end)

local function findScroller(o)
	while o do
		if o:IsA("ScrollingFrame") then return o end
		o = o.Parent
	end
end

--===========================================================================
--  ELEMENT FACTORIES
--===========================================================================

-- SQUARE NEON CHECKBOX. parentRow = parent (for sub-option), or nil.
local function createCheckbox(label, defaultState, searchKey, parentRow, callback)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 30)
	row.BackgroundTransparency = 1
	local rec = registerRow(row, searchKey or label, parentRow)

	local box = Instance.new("TextButton")
	box.Size = UDim2.new(0, 22, 0, 22)
	box.Position = UDim2.new(0, 0, 0.5, -11)
	box.BackgroundColor3 = THEME.UI_ELEM
	box.Text = ""
	box.AutoButtonColor = false
	box.Parent = row
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
	glowStroke(box, 0.5, 0.7)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, -6, 1, -6)
	fill.Position = UDim2.new(0, 3, 0, 3)
	fill.BackgroundColor3 = THEME.NEON
	fill.Visible = defaultState and true or false
	fill.Parent = box
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 2)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -32, 1, 0)
	lbl.Position = UDim2.new(0, 30, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = label
	lbl.TextColor3 = THEME.TEXT_MAIN
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 13
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local state = defaultState
	local function setState(v, skipCb)
		state = v
		fill.Visible = v
		if not skipCb and callback then callback(v) end
	end
	box.MouseButton1Click:Connect(function() setState(not state) end)
	return rec, box, state, setState
end

-- SLIDER. parentRow optional (sub-option).
local function createSlider(name, default, searchKey, isColor, isShade, callback, minVal, maxVal, parentRow)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -10, 0, 40)
	frame.BackgroundTransparency = 1
	local rec = registerRow(frame, searchKey or name, parentRow)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 18)
	lbl.BackgroundTransparency = 1
	lbl.Text = name
	lbl.TextColor3 = THEME.TEXT_DIM
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = frame

	local bg = Instance.new("TextButton")
	bg.Size = UDim2.new(1, (minVal and maxVal) and -60 or 0, 0, 10)
	bg.Position = UDim2.new(0, 0, 0, 22)
	bg.BackgroundColor3 = THEME.UI_ELEM
	bg.Text = ""
	bg.Parent = frame
	Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)

	if isColor then
		local g = Instance.new("UIGradient", bg)
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255,0,0)),
			ColorSequenceKeypoint.new(0.16, Color3.fromRGB(255,255,0)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0,255,0)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0,255,255)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(0,0,255)),
			ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255,0,255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255,0,0)),
		})
		bg.BackgroundColor3 = Color3.fromRGB(255,255,255)
	end
	local shadeGrad
	if isShade then
		shadeGrad = Instance.new("UIGradient", bg)
		shadeGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0,0,0)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255,75,150)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255,255,255)),
		})
		bg.BackgroundColor3 = Color3.fromRGB(255,255,255)
	end

	local startRel = default
	if minVal and maxVal then startRel = (default - minVal) / (maxVal - minVal) end

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(startRel, 0, 1, 0)
	fill.BackgroundColor3 = THEME.NEON
	fill.BackgroundTransparency = (isColor or isShade) and 1 or 0
	fill.Parent = bg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local marker = Instance.new("Frame")
	marker.Size = UDim2.new(0, 6, 1, 6)
	marker.Position = UDim2.new(startRel, -3, 0, -3)
	marker.BackgroundColor3 = Color3.fromRGB(255,255,255)
	marker.Parent = bg
	Instance.new("UICorner", marker).CornerRadius = UDim.new(1, 0)
	glowStroke(marker, 0.5, 0.7)

	local vbox
	if minVal and maxVal then
		vbox = Instance.new("TextBox")
		vbox.Size = UDim2.new(0, 50, 0, 22)
		vbox.Position = UDim2.new(1, -50, 0, 17)
		vbox.BackgroundColor3 = THEME.UI_ELEM
		vbox.TextColor3 = THEME.TEXT_MAIN
		vbox.Font = Enum.Font.Gotham
		vbox.TextSize = 12
		vbox.Text = tostring(default)
		vbox.Parent = frame
		Instance.new("UICorner", vbox).CornerRadius = UDim.new(0, 4)
	end

	local s = { dragging=false, bg=bg, fill=fill, marker=marker,
		minVal=minVal, maxVal=maxVal, vbox=vbox, cb=callback }
	table.insert(_sliders, s)
	bg.MouseButton1Down:Connect(function()
		s.dragging = true; _dragging = true
		local sc = findScroller(bg); if sc then sc.ScrollingEnabled = true end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			local sc = findScroller(bg); if sc then refreshScroll(ACTIVE_TAB) end
		end
	end)
	if vbox then
		vbox.FocusLost:Connect(function()
			local n = tonumber(string.match(vbox.Text, "%-?%d+"))
			if n then
				n = math.clamp(n, minVal, maxVal)
				local rel = (n - minVal) / (maxVal - minVal)
				fill.Size = UDim2.new(rel, 0, 1, 0)
				marker.Position = UDim2.new(rel, -3, 0, -3)
				vbox.Text = tostring(n)
				callback(n)
			end
		end)
	end
	return rec, shadeGrad
end

-- ACTION BUTTON (single click).
local function createButton(label, searchKey, callback)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -10, 0, 32)
	btn.BackgroundColor3 = THEME.NEON
	btn.Text = label
	btn.TextColor3 = Color3.fromRGB(255,255,255)
	btn.Font = Enum.Font.Gotham
	btn.TextSize = 13
	local rec = registerRow(btn, searchKey or label, nil)
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	glowStroke(btn, 0.6, 0.6)
	btn.MouseButton1Click:Connect(callback)
	return rec, btn
end

-- TOGGLE BUTTON (neon when off, red when on).
local function createToggleButton(label, searchKey, callback)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -10, 0, 32)
	btn.BackgroundColor3 = THEME.NEON
	btn.Text = label
	btn.TextColor3 = Color3.fromRGB(255,255,255)
	btn.Font = Enum.Font.Gotham
	btn.TextSize = 13
	local rec = registerRow(btn, searchKey or label, nil)
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	glowStroke(btn, 0.6, 0.6)
	local on = false
	btn.MouseButton1Click:Connect(function()
		on = not on
		btn.BackgroundColor3 = on and Color3.fromRGB(200,50,50) or THEME.NEON
		btn.Text = on and (label .. " [ON]") or label
		callback(on)
	end)
	return rec, btn
end

-- SUBCATEGORY HEADER (pink + line).
local function createSubcategoryHeader(name)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -10, 0, 22)
	frame.BackgroundTransparency = 1
	local rec = registerRow(frame, name, nil)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 14)
	lbl.BackgroundTransparency = 1
	lbl.Text = name
	lbl.TextColor3 = THEME.NEON
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = frame
	local line = Instance.new("Frame", frame)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.Position = UDim2.new(0, 0, 1, -1)
	line.BackgroundColor3 = THEME.NEON
	line.BackgroundTransparency = 0.6
	line.BorderSizePixel = 0
	return rec
end

-- OUTPUT row (button + field, click field = copy).
local function createFunctionWithOutput(btnLabel, outputDefault, searchKey, onClick)
	local wrap = Instance.new("Frame")
	wrap.Size = UDim2.new(1, -10, 0, 32)
	wrap.BackgroundTransparency = 1
	local rec = registerRow(wrap, searchKey or btnLabel, nil)
	local l = Instance.new("UIListLayout", wrap)
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder

	local actionBtn = Instance.new("TextButton")
	actionBtn.Size = UDim2.new(0.5, -3, 1, 0)
	actionBtn.BackgroundColor3 = THEME.NEON
	actionBtn.Text = btnLabel
	actionBtn.TextColor3 = Color3.fromRGB(255,255,255)
	actionBtn.Font = Enum.Font.Gotham
	actionBtn.TextSize = 12
	actionBtn.LayoutOrder = 1
	actionBtn.Parent = wrap
	Instance.new("UICorner", actionBtn).CornerRadius = UDim.new(0, 6)

	local outBox = Instance.new("TextButton")
	outBox.Size = UDim2.new(0.5, -3, 1, 0)
	outBox.BackgroundColor3 = THEME.UI_ELEM
	outBox.Text = outputDefault or "(output)"
	outBox.TextColor3 = THEME.TEXT_MAIN
	outBox.Font = Enum.Font.Gotham
	outBox.TextSize = 12
	outBox.LayoutOrder = 2
	outBox.Parent = wrap
	Instance.new("UICorner", outBox).CornerRadius = UDim.new(0, 6)

	actionBtn.MouseButton1Click:Connect(function()
		if onClick then onClick(outBox) end
	end)
	outBox.MouseButton1Click:Connect(function()
		pcall(function() setclipboard(outBox.Text) end)
		local prev = outBox.TextColor3
		outBox.TextColor3 = THEME.NEON
		task.wait(0.6)
		outBox.TextColor3 = prev
	end)
	return rec, actionBtn, outBox
end

-- DROPDOWN (for ESP Mode)
local function createDropdown(label, options, defaultOption, searchKey, callback, parentRow)
	local wrap = Instance.new("Frame")
	wrap.Size = UDim2.new(1, -10, 0, 35)
	wrap.BackgroundColor3 = THEME.UI_ELEM
	wrap.ClipsDescendants = true
	local rec = registerRow(wrap, searchKey or label, parentRow)
	Instance.new("UICorner", wrap).CornerRadius = UDim.new(0, 6)

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 35)
	btn.BackgroundTransparency = 1
	btn.Text = "  " .. label .. ": " .. defaultOption
	btn.TextColor3 = THEME.TEXT_MAIN
	btn.Font = Enum.Font.Gotham
	btn.TextSize = 13
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.Parent = wrap

	local list = Instance.new("Frame")
	list.Size = UDim2.new(1, 0, 1, -35)
	list.Position = UDim2.new(0, 0, 0, 35)
	list.BackgroundTransparency = 1
	list.Parent = wrap
	Instance.new("UIListLayout", list)

	local isOpen = false
	btn.MouseButton1Click:Connect(function()
		isOpen = not isOpen
		local targetSize = isOpen and UDim2.new(1, -10, 0, 35 + (#options * 30)) or UDim2.new(1, -10, 0, 35)
		TweenService:Create(wrap, TweenInfo.new(0.2), {Size = targetSize}):Play()
		task.defer(function() refreshScroll(ACTIVE_TAB) end)
	end)

	for _, opt in ipairs(options) do
		local item = Instance.new("TextButton")
		item.Size = UDim2.new(1, 0, 0, 30)
		item.BackgroundColor3 = THEME.BG_MAIN
		item.Text = "  " .. opt
		item.TextColor3 = THEME.TEXT_MAIN
		item.Font = Enum.Font.Gotham
		item.TextSize = 13
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.Parent = list
		item.MouseButton1Click:Connect(function()
			btn.Text = "  " .. label .. ": " .. opt
			isOpen = false
			TweenService:Create(wrap, TweenInfo.new(0.2), {Size = UDim2.new(1, -10, 0, 35)}):Play()
			if callback then callback(opt) end
			task.defer(function() refreshScroll(ACTIVE_TAB) end)
		end)
	end
	return rec, wrap
end

-- XYZ INPUT ROW
local function createXYZInputs(searchKey, parentRow)
	local wrap = Instance.new("Frame")
	wrap.Size = UDim2.new(1, -10, 0, 30)
	wrap.BackgroundTransparency = 1
	local rec = registerRow(wrap, searchKey or "XYZ", parentRow)
	local l = Instance.new("UIListLayout", wrap)
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder

	local function mkBox(ph, order)
		local b = Instance.new("TextBox")
		b.Size = UDim2.new(1/3, -4, 1, 0)
		b.BackgroundColor3 = THEME.UI_ELEM
		b.TextColor3 = THEME.TEXT_MAIN
		b.Font = Enum.Font.Gotham
		b.TextSize = 13
		b.PlaceholderText = ph
		b.Text = ""
		b.LayoutOrder = order
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
		b.Parent = wrap
		return b
	end
	return rec, mkBox("X", 1), mkBox("Y", 2), mkBox("Z", 3)
end

-- INPUT + BUTTONS ROW (for FPS limiter, autoclicker)
local function createInputWithButtons(label, placeholder, btnLabels, searchKey, onButton)
	local wrap = Instance.new("Frame")
	wrap.Size = UDim2.new(1, -10, 0, 32)
	wrap.BackgroundTransparency = 1
	local rec = registerRow(wrap, searchKey or label, nil)
	local l = Instance.new("UIListLayout", wrap)
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.VerticalAlignment = Enum.VerticalAlignment.Center

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0.45, 0, 1, 0)
	box.BackgroundColor3 = THEME.UI_ELEM
	box.TextColor3 = THEME.TEXT_MAIN
	box.PlaceholderText = placeholder
	box.Text = ""
	box.Font = Enum.Font.Gotham
	box.TextSize = 12
	box.LayoutOrder = 1
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
	box.Parent = wrap

	local btns = {}
	for i, btnLabel in ipairs(btnLabels) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.3, -2, 1, 0)
		b.BackgroundColor3 = THEME.NEON
		b.Text = btnLabel
		b.TextColor3 = Color3.fromRGB(255,255,255)
		b.Font = Enum.Font.Gotham
		b.TextSize = 12
		b.LayoutOrder = i + 1
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
		b.Parent = wrap
		b.MouseButton1Click:Connect(function()
			if onButton then onButton(i, box, b) end
		end)
		btns[i] = b
	end

	return rec, box, btns
end

-----------------------------------
-- HELPERS
-----------------------------------
local function getTabDef(name)
	for _, d in ipairs(TAB_DEFS) do if d.name == name then return d end end
end
local function setActive(name)
	local d = getTabDef(name); if d then ACTIVE_TAB = d end
end

-- Превратить уже созданную строку (rec) в под-опцию parentRow.
local function makeChild(rec, parentRow)
	if not rec or not parentRow then return end
	rec.parentRow = parentRow
	rec.enabledByParent = false          -- скрыта, пока родитель не включён
	table.insert(parentRow.children, rec)
	updateRow(rec)
end

--===========================================================================
--  ============  ALL TABS AND FUNCTIONS FROM beta3.lua  =======================
--===========================================================================

--==== TAB: ESP ==========================================================
do
	setActive("ESP")
	createSubcategoryHeader("ESP")

	local espRow
	local shadeRec, hueRec   -- MM2: ссылки на строки слайдеров цвета/тени, чтобы прятать их
	espRow = createCheckbox("Toggle ESP", false, "Toggle ESP", nil, function(on)
		ESP.Enabled = on
		setChildrenEnabled(espRow, on)
		if not on then
			for _, p in pairs(Players:GetPlayers()) do clearESP(p) end
		end
	end)

	createCheckbox("Show teammates", true, "Show teammates", espRow, function(on)
		ESP.ShowTeam = on
		_pfMyTeamCached = nil  -- пересчёт команды нужен сразу
		-- переанализ команд PF при любом переключении
		if ESP.PFMode and _pfAnalyzeTeams then _pfAnalyzeTeams() end
		if not on then
			for _, p in pairs(Players:GetPlayers()) do
				if p.Team == LocalPlayer.Team then clearESP(p) end
			end
		end
	end)

	createCheckbox("Phantom Forces Mode", false, "Phantom Forces Mode ESP", espRow, function(on)
		ESP.PFMode = on
		-- смена провайдера: чистим оба кэша
		for _, p in pairs(Players:GetPlayers()) do clearESP(p) end
		_pfEspClear()
		if _pfAnalyzeTeams then _pfAnalyzeTeams() end
	end)

	local chamsSliderRow
	createDropdown("Mode", {"Cubes", "Outline", "Chams", "Boxes"}, "Cubes", "Mode ESP", function(opt)
		ESP.Mode = opt
		-- Recompute visibility of all rows in the tab (chams slider depends on Mode)
		task.defer(function()
			for _, r in ipairs(ACTIVE_TAB.rows) do updateRow(r) end
			refreshScroll(ACTIVE_TAB)
		end)
	end, espRow)

	createSlider("Distance", 10000, "Distance ESP", false, false, function(v)
		ESP.Radius = v
	end, 0, 10000, espRow)

	chamsSliderRow = createSlider("Chams Transparency", 0.5, "Chams Transparency ESP", false, false, function(v)
		ESP.ChamsTransparency = v
	end, 0, 1, espRow)
	chamsSliderRow.visibleExtra = function() return ESP.Mode == "Chams" end
	updateRow(chamsSliderRow)

	local shadeGradient
	local _g
	shadeRec, _g = createSlider("Shade", 0.5, "Shade ESP", false, true, function(v)
		ESP.Shade = v; updateColor()
		if shadeGradient then
			shadeGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 0, 0)),
				ColorSequenceKeypoint.new(0.5, Color3.fromHSV(ESP.Hue, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
			})
		end
	end, nil, nil, espRow)
	shadeGradient = _g

	hueRec = createSlider("Hue", 0.5, "Hue ESP", true, false, function(v)
		ESP.Hue = v
		updateColor()
		if shadeGradient then
			shadeGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 0, 0)),
				ColorSequenceKeypoint.new(0.5, Color3.fromHSV(ESP.Hue, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
			})
		end
	end, nil, nil, espRow)

	-- MM2: слайдеры Shade/Hue прячутся, когда включены MM2-роли
	shadeRec.visibleExtra = function() return not ESP.MM2Mode end
	updateRow(shadeRec)
	hueRec.visibleExtra = function() return not ESP.MM2Mode end
	updateRow(hueRec)

	-- MM2 роли: Sheriff=синий, Murderer=красный, Innocent=розовый (цвет меню)
	createCheckbox("Show MM2 roles", false, "Show MM2 roles ESP", espRow, function(on)
		ESP.MM2Mode = on
		if shadeRec then updateRow(shadeRec) end
		if hueRec then updateRow(hueRec) end
		task.defer(function() refreshScroll(ACTIVE_TAB) end)
	end)

	createCheckbox("Show Names", false, "Show Names ESP", espRow, function(on) ESP.ShowNames = on end)
	createCheckbox("Show Health", false, "Show Health ESP", espRow, function(on) ESP.ShowHealth = on end)
	createCheckbox("Show Distance", false, "Show Distance ESP", espRow, function(on) ESP.ShowDistance = on end)
	createCheckbox("Show Health Bar", false, "Show Health Bar ESP", espRow, function(on) ESP.ShowHealthBar = on end)
end

--==== TAB: Player =======================================================
do
	setActive("Player")
	createSubcategoryHeader("Player")

	-- WalkSpeed + Speed Value (sub-option)
	local wsRow
	wsRow = createCheckbox("WalkSpeed", false, "WalkSpeed", nil, function(on)
		PlayerMods.SpeedEnabled = on
		setChildrenEnabled(wsRow, on)
	end)
	createSlider("Speed Value", 16, "Speed Value Player", false, false, function(v)
		PlayerMods.SpeedValue = v
	end, 16, 250, wsRow)

	-- JumpPower + Jump Value (sub-option)
	local jpRow
	jpRow = createCheckbox("JumpPower", false, "JumpPower", nil, function(on)
		PlayerMods.JumpEnabled = on
		setChildrenEnabled(jpRow, on)
	end)
	createSlider("Jump Value", 50, "Jump Value Player", false, false, function(v)
		PlayerMods.JumpValue = v
	end, 50, 500, jpRow)

	-- forward-decl для независимого Wall Walk (создаётся ниже)
	local wallWalkRec, wallWalkSetState

	-- Fly + Fly Speed / Noclip (sub-options)
	local flyRow
	flyRow = createCheckbox("Fly", false, "Fly", nil, function(on)
		PlayerMods.FlyEnabled = on
		setChildrenEnabled(flyRow, on)
		-- Fly и Wall Walk конфликтуют: при включении Fly принудительно выключаем Wall Walk
		if on and PlayerMods.WallWalkEnabled then
			PlayerMods.WallWalkEnabled = false
			if wallWalkSetState then wallWalkSetState(false, true) end
			_restoreCollision()
		end
		-- пересчитать видимость строки Wall Walk (прячется, пока Fly включён)
		if wallWalkRec then updateRow(wallWalkRec) end
		task.defer(function() refreshScroll(ACTIVE_TAB) end)
		local char = LocalPlayer.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			local hrp = char.HumanoidRootPart
			local hum = char:FindFirstChild("Humanoid")
			if not on then
				local _m = hrp:FindFirstChild(RN.FlyMover); if _m then _m:Destroy() end
				local _g = hrp:FindFirstChild(RN.FlyGyro);  if _g then _g:Destroy() end
				local _a = hrp:FindFirstChild(RN.FlyAtt);   if _a then _a:Destroy() end
				if hum then
					if hum:GetState() == Enum.HumanoidStateType.Physics then
						hum:ChangeState(Enum.HumanoidStateType.Freefall)
					end
					local rx, ry, rz = hrp.CFrame:ToOrientation()
					hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, ry, 0)
				end
			end
		end
	end)
	createSlider("Fly Speed", 50, "Fly Speed Player", false, false, function(v)
		PlayerMods.FlySpeed = v
	end, 10, 500, flyRow)
	createCheckbox("Noclip", false, "Noclip", flyRow, function(on)
		PlayerMods.NoclipEnabled = on
		if not on then _restoreCollision() end
	end)

	-- Wall Walk — независимая функция верхнего уровня.
	-- Скрывается, пока включён Fly (конфликт коллизий с Fly/Noclip).
	wallWalkRec, _, _, wallWalkSetState = createCheckbox("Wall Walk", false, "Wall Walk", nil, function(on)
		PlayerMods.WallWalkEnabled = on
		if not on then _restoreCollision() end
	end)
	wallWalkRec.visibleExtra = function() return not PlayerMods.FlyEnabled end
	updateRow(wallWalkRec)

	-- Infinite Jump
	createCheckbox("Infinite Jump", false, "Infinite Jump", nil, function(on)
		PlayerMods.InfJumpEnabled = on
	end)

	-- Anti-Knockback
	createCheckbox("Anti-Knockback", false, "Anti-Knockback", nil, function(on)
		PlayerMods.AntiKnockback = on
	end)
end

--==== TAB: Aim =========================================================
do
	setActive("Aim")
	createSubcategoryHeader("Aimbot")

	-- Мастер-переключатель. Все остальные строки — его под-опции.
	local aimRow
	aimRow = createCheckbox("Enable Aimbot", false, "Enable Aimbot", nil, function(on)
		Aim.Enabled = on
		setChildrenEnabled(aimRow, on)
	end)

	-- Клавиша активации (удержание). Поддерживает клавиатуру и кнопки мыши.
	local keyWaiting = false
	local keyConn = nil
	local keyRec, keyBtn = createButton("Aim key: " .. Aim.ActivationKey.Name .. " (hold)", "Aim key", function() end)
	makeChild(keyRec, aimRow)

	local function stopKeyCapture()
		if keyConn then pcall(function() keyConn:Disconnect() end); keyConn = nil end
		keyWaiting = false
	end

	keyBtn.MouseButton1Click:Connect(function()
		if keyWaiting then
			-- повторный клик = отмена ожидания
			stopKeyCapture()
			keyBtn.Text = "Aim key: " .. Aim.ActivationKey.Name .. " (hold)"
			return
		end
		keyWaiting = true
		keyBtn.Text = "Press any key / mouse btn..."
		-- НЕ фильтруем по gameProcessed здесь — иначе игровой bind не даст назначить клавишу
		keyConn = UserInputService.InputBegan:Connect(function(input)
			local kc = input.KeyCode
			local ut = input.UserInputType
			-- Клавиатура
			if ut == Enum.UserInputType.Keyboard and kc ~= Enum.KeyCode.Unknown then
				-- игнорируем клавиши, которыми управляется меню/движение, чтобы не залочить себя
				if kc == Enum.KeyCode.Delete or kc == Enum.KeyCode.Escape then return end
				Aim.ActivationKey = kc
				Aim.ActivationInput = nil
				keyBtn.Text = "Aim key: " .. kc.Name .. " (hold)"
				stopKeyCapture()
			-- Кнопки мыши (ПКМ/боковые). MouseButton1 не биндим — это ЛКМ меню.
			elseif ut == Enum.UserInputType.MouseButton2
				or ut == Enum.UserInputType.MouseButton3 then
				Aim.ActivationInput = ut       -- запоминаем как UserInputType
				Aim.ActivationKey = Enum.KeyCode.Unknown
				keyBtn.Text = "Aim key: " .. ut.Name .. " (hold)"
				stopKeyCapture()
			end
		end)
		-- таймаут: если за 5 сек ничего не нажали — отменить
		task.delay(5, function()
			if keyWaiting then
				stopKeyCapture()
				keyBtn.Text = "Aim key: " .. Aim.ActivationKey.Name .. " (hold)"
			end
		end)
	end)

	createDropdown("Aim Part", {"Head", "HumanoidRootPart", "UpperTorso"}, "Head", "Aim Part", function(opt)
		Aim.AimPart = opt
	end, aimRow)

	createSlider("FOV Radius", 250, "FOV Radius", false, false, function(v)
		Aim.FOV_Radius = v
	end, 10, 1000, aimRow)

	createCheckbox("Show FOV", true, "Show FOV", aimRow, function(on)
		Aim.ShowFOV = on
	end)

	createCheckbox("Team Check", false, "Team Check", aimRow, function(on)
		Aim.TeamCheck = on
	end)

	createCheckbox("Wall Check", true, "Wall Check", aimRow, function(on)
		Aim.WallCheck = on
	end)

	createSlider("Smoothing", 5, "Smoothing", false, false, function(v)
		Aim.Smoothing = v
	end, 1, 20, aimRow)

	createSlider("Max Distance", 500, "Max Distance", false, false, function(v)
		Aim.MaxDistance = v
	end, 50, 2000, aimRow)

	-- Prediction + сила предсказания (под-опция, видна только когда Prediction ВКЛ)
	local predStrengthRow
	createCheckbox("Prediction", false, "Prediction", aimRow, function(on)
		Aim.PredictionEnabled = on
		if predStrengthRow then updateRow(predStrengthRow) end
		task.defer(function() refreshScroll(ACTIVE_TAB) end)
	end)
	predStrengthRow = createSlider("Prediction Strength", 12, "Prediction Strength", false, false, function(v)
		Aim.PredictionStrength = v / 100     -- слайдер 0..100 => 0.0..1.0
	end, 0, 100, aimRow)
	predStrengthRow.visibleExtra = function() return Aim.PredictionEnabled end
	updateRow(predStrengthRow)

	createDropdown("Target", {"Closest to Crosshair", "Closest Distance", "Lowest Health"}, "Closest to Crosshair", "Aim Target Mode", function(opt)
		Aim.TargetMode = opt
	end, aimRow)

	createCheckbox("Aim Lock", false, "Aim Lock", aimRow, function(on)
		Aim.AimLock = on
	end)
end

--==== TAB: Babft ========================================================
do
	setActive("Babft")
	createSubcategoryHeader("Autofarm")

	local SPEED = 450
	G.gold = false
	G.goldClaim = false

	local goldRow = createToggleButton("Gold Autofarm", "Gold Autofarm", function(on)
		if on then
			G.gold = true
			G.goldClaim = true
			task.spawn(function()
				while G.goldClaim do
					pcall(function()
						workspace:WaitForChild("ClaimRiverResultsGold"):FireServer()
					end)
					task.wait(5 + math.random() * 1.5)
				end
			end)
			task.spawn(function()
				while G.gold do
					if G.shutdown then return end
					local char = LocalPlayer.Character
					if char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Humanoid") then
						local hrp = char.HumanoidRootPart
						local hum = char.Humanoid
						-- Stepped teleport (not a single-frame jump)
						hrp.CFrame = CFrame.new(-55, 75, 1000)
						task.wait(0.3)

						local att = Instance.new("Attachment")
						att.Name = RN.GoldAtt
						att.Parent = hrp

						local mover = Instance.new("LinearVelocity")
						mover.Name = RN.GoldMover
						mover.Attachment0 = att
						mover.MaxForce = math.random(80000, 120000)
						mover.VectorVelocity = Vector3.zero
						mover.RelativeTo = Enum.ActuatorRelativeTo.World
						mover.Parent = hrp

						local gyro = Instance.new("AlignOrientation")
						gyro.Name = RN.GoldGyro
						gyro.Attachment0 = att
						gyro.RigidityEnabled = false
						gyro.MaxTorque = math.random(80000, 120000)
						gyro.Responsiveness = 40
						gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
						gyro.Parent = hrp
						if hum:GetState() ~= Enum.HumanoidStateType.Physics then
							hum:ChangeState(Enum.HumanoidStateType.Physics)
						end

						local function isAlive()
							return G.gold and hrp.Parent and hum.Health > 0
						end

						local forwardLook = CFrame.new(hrp.Position, hrp.Position + Vector3.new(0, 0, 1))
						mover.VectorVelocity = Vector3.new(0, 0, SPEED)
						gyro.CFrame = forwardLook
						while isAlive() and hrp.Position.Z < 8700 do task.wait() end

						if isAlive() then
							mover.VectorVelocity = Vector3.new(0, -SPEED, 0)
							gyro.CFrame = forwardLook
							while isAlive() and hrp.Position.Y > -235 do task.wait() end
						end

						if isAlive() then
							mover.VectorVelocity = Vector3.new(0, 0, SPEED)
							while isAlive() and hrp.Position.Z < 9495 do task.wait() end
						end

						pcall(function() mover:Destroy() end)
						pcall(function() gyro:Destroy() end)
						pcall(function() att:Destroy() end)
						if hum:GetState() == Enum.HumanoidStateType.Physics then
							pcall(function() hum:ChangeState(Enum.HumanoidStateType.Freefall) end)
						end

						while G.gold and char.Parent and hum.Health > 0 do task.wait() end
					end

					while G.gold do
						if G.shutdown then return end
						local c = LocalPlayer.Character
						if c and c:FindFirstChild("HumanoidRootPart") and c:FindFirstChild("Humanoid") and c.Humanoid.Health > 0 then
							break
						end
						task.wait()
					end
					task.wait(1)
				end

				local fc = LocalPlayer.Character
				local fhrp = fc and fc:FindFirstChild("HumanoidRootPart")
				if fhrp then
					local _fm = fhrp:FindFirstChild(RN.GoldMover); if _fm then _fm:Destroy() end
					local _fg = fhrp:FindFirstChild(RN.GoldGyro);  if _fg then _fg:Destroy() end
					local _fa = fhrp:FindFirstChild(RN.GoldAtt);  if _fa then _fa:Destroy() end
				end
				local fhum = fc and fc:FindFirstChild("Humanoid")
				if fhum and fhum:GetState() == Enum.HumanoidStateType.Physics then
					pcall(function() fhum:ChangeState(Enum.HumanoidStateType.Freefall) end)
				end
			end)
		else
			G.gold = false
			G.goldClaim = false
			local char = LocalPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local _hm = hrp:FindFirstChild(RN.GoldMover); if _hm then _hm:Destroy() end
				local _hg = hrp:FindFirstChild(RN.GoldGyro);  if _hg then _hg:Destroy() end
				local _ha = hrp:FindFirstChild(RN.GoldAtt);   if _ha then _ha:Destroy() end
			end
			local hum = char and char:FindFirstChild("Humanoid")
			if hum and hum:GetState() == Enum.HumanoidStateType.Physics then
				pcall(function() hum:ChangeState(Enum.HumanoidStateType.Freefall) end)
			end
		end
	end)
end

--==== TAB: Movement =====================================================
do
	setActive("Movement")
	createSubcategoryHeader("Teleport")

	local _, tbX, tbY, tbZ = createXYZInputs("Teleport XYZ")
	createButton("Teleport to:", "Teleport to", function()
		local x = tonumber(tbX.Text)
		local y = tonumber(tbY.Text)
		local z = tonumber(tbZ.Text)
		if x and y and z then
			local char = LocalPlayer.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				char.HumanoidRootPart.CFrame = CFrame.new(x, y, z)
			end
		end
	end)
	createButton("Tween Teleport to:", "Tween Teleport to", function()
		local x = tonumber(tbX.Text)
		local y = tonumber(tbY.Text)
		local z = tonumber(tbZ.Text)
		if x and y and z and G.tweenTeleportXYZ then
			G.tweenTeleportXYZ(x, y, z)
		end
	end)

	local privatePlate = nil
	createButton("Go to Baseplate", "Go to Baseplate", function()
		local PLATE_X, PLATE_Y, PLATE_Z = 100000, -10, 100000
		if not privatePlate or not privatePlate.Parent then
			privatePlate = Instance.new("Part")
			privatePlate.Name = RN.Plate
			privatePlate.Size = Vector3.new(2048, 20, 2048)
			privatePlate.Position = Vector3.new(PLATE_X, PLATE_Y, PLATE_Z)
			privatePlate.Anchored = true
			privatePlate.Locked = true
			privatePlate.Material = Enum.Material.SmoothPlastic
			privatePlate.BrickColor = BrickColor.new("Medium stone grey")
			privatePlate.CastShadow = false
			privatePlate.Parent = workspace
		end
		local char = LocalPlayer.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			char.HumanoidRootPart.CFrame = CFrame.new(PLATE_X, PLATE_Y + 15, PLATE_Z)
		end
	end)

	createSubcategoryHeader("Saved Coordinates")

	local moveTabDef = ACTIVE_TAB
	local moveContainer = ACTIVE_TAB.container

	local function addSavedCoord(x, y, z)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -10, 0, 30)
		row.BackgroundTransparency = 1
		local l = Instance.new("UIListLayout", row)
		l.FillDirection = Enum.FillDirection.Horizontal
		l.Padding = UDim.new(0, 6)
		l.SortOrder = Enum.SortOrder.LayoutOrder

		local coordStr = string.format("%.1f, %.1f, %.1f", x, y, z)

		local tpBtn = Instance.new("TextButton")
		tpBtn.Size = UDim2.new(1, 0, 1, 0)
		tpBtn.BackgroundColor3 = THEME.UI_ELEM
		tpBtn.Text = "TP: " .. coordStr
		tpBtn.TextColor3 = THEME.TEXT_MAIN
		tpBtn.Font = Enum.Font.Gotham
		tpBtn.TextSize = 12
		tpBtn.LayoutOrder = 1
		Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0, 6)
		glowStroke(tpBtn, 0.5, 0.7)
		tpBtn.Parent = row

		local copyBtn = Instance.new("TextButton")
		copyBtn.Size = UDim2.new(0, 40, 1, 0)
		copyBtn.BackgroundColor3 = THEME.NEON
		copyBtn.Text = "Copy"
		copyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		copyBtn.Font = Enum.Font.Gotham
		copyBtn.TextSize = 11
		copyBtn.LayoutOrder = 2
		Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(0, 6)
		copyBtn.Parent = row

		local delBtn = Instance.new("TextButton")
		delBtn.Size = UDim2.new(0, 40, 1, 0)
		delBtn.BackgroundColor3 = THEME.NEON
		delBtn.Text = "Del"
		delBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		delBtn.Font = Enum.Font.Gotham
		delBtn.TextSize = 11
		delBtn.LayoutOrder = 3
		Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0, 6)
		delBtn.Parent = row

		tpBtn.MouseButton1Click:Connect(function()
			local char = LocalPlayer.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				char.HumanoidRootPart.CFrame = CFrame.new(x, y, z)
			end
		end)
		tpBtn.MouseButton2Click:Connect(function()
			if G.tweenTeleportXYZ then G.tweenTeleportXYZ(x, y, z) end
		end)
		copyBtn.MouseButton1Click:Connect(function()
			pcall(function() setclipboard(coordStr) end)
			local prev = copyBtn.Text
			copyBtn.Text = "OK"
			task.delay(0.6, function() if copyBtn.Parent then copyBtn.Text = prev end end)
		end)
		delBtn.MouseButton1Click:Connect(function()
			row:Destroy()
			for i, r in ipairs(moveTabDef.rows) do
				if r.frame == row then
					table.remove(moveTabDef.rows, i)
					break
				end
			end
			task.defer(function() refreshScroll(moveTabDef) end)
		end)

		row.Parent = moveContainer
		row.LayoutOrder = 1000 + #moveTabDef.rows
		local rec = {
			frame = row, searchKey = "saved coord " .. coordStr, parentRow = nil,
			children = {}, enabledByParent = true, visibleBySearch = true, visibleExtra = nil,
		}
		table.insert(moveTabDef.rows, rec)
		updateRow(rec)
		task.defer(function() refreshScroll(moveTabDef) end)
	end

	createButton("Save Coordinates", "Save Coordinates", function()
		local x = tonumber(tbX.Text)
		local y = tonumber(tbY.Text)
		local z = tonumber(tbZ.Text)
		if x and y and z then addSavedCoord(x, y, z) end
	end)

	createButton("Save Current Coordinates", "Save Current Coordinates", function()
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local p = hrp.Position
			addSavedCoord(p.X, p.Y, p.Z)
		end
	end)
end

--==== TAB: Slap Battles =================================================
do
	setActive("Slap Battles")
	createSubcategoryHeader("Teleport")

	createButton("Get in Elude", "Get in Elude", function()
		local TeleportService = getService("TeleportService")
		TeleportService:Teleport(11828384869)
	end)

	createButton("Get in Frostbite", "Get in Frostbite", function()
		local TeleportService = getService("TeleportService")
		TeleportService:Teleport(17290438723)
	end)

	createButton("Teleport to Frostbite Glove", "Teleport to Frostbite Glove", function()
		local char = LocalPlayer.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			char.HumanoidRootPart.CFrame = CFrame.new(-550, 178, 58)
		end
	end)

	createSubcategoryHeader("Get")

	createButton("Get Iceskate", "Get Iceskate", function()
		local ReplicatedStorage = getService("ReplicatedStorage")
		local args = { "Freeze" }
		ReplicatedStorage:WaitForChild("IceSkate"):FireServer(unpack(args))
	end)

	createButton("Get Elude+Counter", "Get Elude Counter", function()
		task.spawn(function()
			local root = LocalPlayer.Character:WaitForChild("HumanoidRootPart")
			-- 1. Click the Counter lever
			if workspace:FindFirstChild("CounterLever") then
				fireclickdetector(workspace.CounterLever.ClickDetector)
			end
			-- 2. Teleport into the sky and hold position
			local holdPos = Vector3.new(0, 100, 0)
			root.CFrame = CFrame.new(holdPos)
			task.wait(0.2)
			local holdAtt = Instance.new("Attachment")
			holdAtt.Name = rnd()
			holdAtt.Parent = root

			local hold = Instance.new("AlignPosition")
			hold.Name = rnd()
			hold.Attachment0 = holdAtt
			hold.Mode = Enum.PositionAlignmentMode.OneAttachment
			hold.Position = holdPos
			hold.MaxForce = math.random(900000, 1100000)
			hold.Responsiveness = 50
			hold.Parent = root

			local holdGyro = Instance.new("AlignOrientation")
			holdGyro.Name = rnd()
			holdGyro.Attachment0 = holdAtt
			holdGyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
			holdGyro.RigidityEnabled = false
			holdGyro.MaxTorque = math.random(900000, 1100000)
			holdGyro.Responsiveness = 40
			holdGyro.CFrame = root.CFrame
			holdGyro.Parent = root

			-- Wait ~121 seconds (jittered)
			local waitTarget = 121 + math.random(-2, 2)
			local waited = 0
			while waited < waitTarget do
				if G.shutdown then return end
				task.wait(1)
				waited = waited + 1
			end

			-- 3. Release the hold
			pcall(function() hold:Destroy() end)
			pcall(function() holdGyro:Destroy() end)
			pcall(function() holdAtt:Destroy() end)
			task.wait(0.5)

			-- 4. Touch the Elude glove
			if workspace:FindFirstChild("Ruins") and workspace.Ruins.Elude:FindFirstChild("Glove") then
				firetouchinterest(root, workspace.Ruins.Elude.Glove, 0)
				firetouchinterest(root, workspace.Ruins.Elude.Glove, 1)
			end

			-- 5. Collect all hidden items in the maze
			if workspace:FindFirstChild("Maze") then
				for _, v in pairs(workspace.Maze:GetDescendants()) do
					if v:IsA("ClickDetector") then
						fireclickdetector(v)
					end
				end
			end
		end)
	end)

	createButton("Get Lamp", "Get Lamp", function()
		if LocalPlayer.leaderstats and LocalPlayer.leaderstats.Glove and LocalPlayer.leaderstats.Glove.Value == "ZZZZZZZ" then
			task.spawn(function()
				local ReplicatedStorage = getService("ReplicatedStorage")
				local BadgeService = getService("BadgeService")
				repeat task.wait(0.1)
					ReplicatedStorage.nightmare:FireServer("LightBroken")
				until BadgeService:UserHasBadgeAsync(LocalPlayer.UserId, 490455814138437)
			end)
		end
	end)

	createButton("Get Plank", "Get Plank", function()
		if LocalPlayer.leaderstats and LocalPlayer.leaderstats.Glove and LocalPlayer.leaderstats.Glove.Value == "Fort" then
			local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = CFrame.new(-392, 50, -42)
				task.wait(0.3)
				local ReplicatedStorage = getService("ReplicatedStorage")
				ReplicatedStorage.FortSkill:FireServer()
				task.wait(0.2)
				for _, v in ipairs(workspace:GetDescendants()) do
					if v.ClassName == "ProximityPrompt" then
						fireproximityprompt(v)
					end
				end
			end
		end
	end)

	createSubcategoryHeader("Etc")

	-- Auto Fort (toggle)
	G.autoFort = false
	createToggleButton("Auto Fort", "Auto Fort", function(on)
		G.autoFort = on
		if on then
			task.spawn(function()
				local ReplicatedStorage = getService("ReplicatedStorage")
				while G.autoFort do
					if G.shutdown then return end
					pcall(function()
						ReplicatedStorage:WaitForChild("Fortlol"):FireServer()
					end)
					task.wait(3.5 + math.random() * 1.5)
				end
			end)
		end
	end)

	-- Autofarm Slapples (toggle)
	G.slapple = false
	createToggleButton("Autofarm Slapples", "Autofarm Slapples", function(on)
		G.slapple = on
		if on then
			task.spawn(function()
				while G.slapple do
					if G.shutdown then return end
					pcall(function()
						local char = LocalPlayer.Character
						if char and char:FindFirstChild("entered") then
							local hrp = char:FindFirstChild("HumanoidRootPart")
							for _, v in pairs(workspace.Arena.island5.Slapples:GetChildren()) do
								if hrp and char:FindFirstChild("entered") and
									(v.Name == "Slapple" or v.Name == "GoldenSlapple") and
									v:FindFirstChild("Glove") and
									v.Glove:FindFirstChildWhichIsA("TouchTransmitter")
								then
									firetouchinterest(hrp, v.Glove, 0)
									firetouchinterest(hrp, v.Glove, 1)
								end
							end
						end
					end)
					task.wait(0.08 + math.random() * 0.14)
				end
			end)
		end
	end)

	-- Anti-Ragdoll (toggle)
	G.antirag = false
	createCheckbox("Anti-Ragdoll", false, "Anti-Ragdoll", nil, function(on)
		G.antirag = on
		if on then
			task.spawn(function()
				while G.antirag do
					if G.shutdown then return end
					local char = LocalPlayer.Character
					if char and char:FindFirstChild("HumanoidRootPart") then
						local ragdolled = char:FindFirstChild("Ragdolled")
						if ragdolled and ragdolled.Value == true then
							local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
							if torso then
								local holdAtt = Instance.new("Attachment")
								holdAtt.Name = rnd()
								holdAtt.Parent = torso

								local hold = Instance.new("AlignPosition")
								hold.Name = rnd()
								hold.Attachment0 = holdAtt
								hold.Mode = Enum.PositionAlignmentMode.OneAttachment
								hold.Position = torso.Position
								hold.MaxForce = math.random(900000, 1100000)
								hold.Responsiveness = 50
								hold.Parent = torso

								repeat task.wait()
								until not ragdolled.Value or not G.antirag

								pcall(function() hold:Destroy() end)
								pcall(function() holdAtt:Destroy() end)
							end
						end
					end
					task.wait()
				end
			end)
		else
			local char = LocalPlayer.Character
			if char then
				local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
				if torso then torso.Anchored = false end
			end
		end
	end)

	-- Hide Nicknames (toggle)
	createSubcategoryHeader("Spoof")
	do
		local originalTexts = {}
		local loopThread = nil

		local function buildNameSet()
			local names = {}
			for _, plr in ipairs(Players:GetPlayers()) do
				names[plr.Name] = true
				names[plr.DisplayName] = true
			end
			return names
		end

		local function maskElement(obj, nameSet, isOverhead)
			if not (obj:IsA("TextLabel") or obj:IsA("TextButton")) then return end
			local txt = obj.Text
			if not txt or txt == "---" or txt == "" then return end

			local shouldMask = false
			if isOverhead then
				if nameSet[txt] then shouldMask = true end
			else
				if nameSet[txt] then
					shouldMask = true
				else
					local cleaned = txt:gsub("[,%s]", "")
					local numericPart = cleaned:gsub("[kMBy%+]$", "")
					if tonumber(numericPart) ~= nil then shouldMask = true end
				end
			end

			if shouldMask then
				if not originalTexts[obj] then
					originalTexts[obj] = txt
				end
				obj.Text = "---"
			end
		end

		createCheckbox("Hide Nicknames", false, "Hide Nicknames", nil, function(on)
			if on then
				G.spoofMask = true
				loopThread = task.spawn(function()
					while G.spoofMask do
						if G.shutdown then return end
						local nameSet = buildNameSet()

						local playerList = CoreGui:FindFirstChild("PlayerList")
						if not playerList then
							local robloxGui = CoreGui:FindFirstChild("RobloxGui")
							playerList = robloxGui and robloxGui:FindFirstChild("PlayerList")
						end
						if playerList then
							for _, d in ipairs(playerList:GetDescendants()) do
								if not G.spoofMask then break end
								maskElement(d, nameSet, false)
							end
						end

						for _, plr in ipairs(Players:GetPlayers()) do
							if not G.spoofMask then break end
							local char = plr.Character
							if char then
								local head = char:FindFirstChild("Head")
								if head then
									for _, d in ipairs(head:GetDescendants()) do
										if not G.spoofMask then break end
										maskElement(d, nameSet, true)
									end
								end
							end
						end

						local stillValid = {}
						for obj, orig in pairs(originalTexts) do
							if obj and obj.Parent then
								stillValid[obj] = orig
							end
						end
						originalTexts = stillValid

						task.wait(0.5)
					end
				end)
			else
				G.spoofMask = false
				if loopThread then pcall(function() task.cancel(loopThread) end); loopThread = nil end
				for obj, orig in pairs(originalTexts) do
					pcall(function() obj.Text = orig end)
				end
				originalTexts = {}
			end
		end)
	end
end

--==== TAB: Performance ==================================================
do
	setActive("Performance")
	createSubcategoryHeader("Stats Overlay")

	-- FPS+Ping / FPS / Ping (mutually exclusive)
	local _statsMode = nil
	local _statsGui = nil
	local _statsConn = nil
	local _statsBtnFpsPing, _statsBtnFps, _statsBtnPing
	local _updateStatsBtns  -- forward declaration; реализация ниже

	local function _setStatsMode(mode)
		if _statsConn then pcall(function() _statsConn:Disconnect() end); _statsConn = nil end
		if G.statsConn then pcall(function() G.statsConn:Disconnect() end); G.statsConn = nil end
		if _statsGui then pcall(function() _statsGui:Destroy() end); _statsGui = nil; G.statsGui = nil end
		_statsMode = mode
		if _updateStatsBtns then _updateStatsBtns() end  -- сразу обновить подсветку кнопок (в т.ч. при выключении)
		if not mode then return end

		_statsGui = Instance.new("ScreenGui")
		_statsGui.Name = RN.StatsGui
		_statsGui.ResetOnSpawn = false
		_statsGui.DisplayOrder = 15
		_statsGui.IgnoreGuiInset = false
		hiddenParent(_statsGui)
		G.statsGui = _statsGui

		local vp = workspace.CurrentCamera.ViewportSize
		local yPos = 73 / 1440
		local fontSize = math.max(11, math.floor(vp.Y / 105))

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = THEME.TEXT_DIM
		lbl.TextStrokeTransparency = 0.3
		lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = fontSize
		lbl.Size = UDim2.new(0.25, 0, 0, fontSize + 8)
		lbl.Position = UDim2.new(0, 20, yPos, 0)
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextYAlignment = Enum.TextYAlignment.Center
		lbl.Parent = _statsGui

		local fpsAccum, fpsSamples, updateTimer = 0, 0, 0
		_statsConn = RunService.Heartbeat:Connect(function(dt)
			if G.shutdown then return end
			fpsAccum = fpsAccum + dt
			fpsSamples = fpsSamples + 1
			updateTimer = updateTimer + dt
			if updateTimer < 0.5 then return end
			updateTimer = 0
			local fps = math.floor(fpsSamples / fpsAccum)
			fpsAccum = 0; fpsSamples = 0
			local ping = math.floor((LocalPlayer:GetNetworkPing() or 0) * 1000)
			if _statsMode == "both" then lbl.Text = fps .. " FPS  " .. ping .. " ms"
			elseif _statsMode == "fps" then lbl.Text = fps .. " FPS"
			elseif _statsMode == "ping" then lbl.Text = ping .. " ms"
			end
		end)
		G.statsConn = _statsConn
	end

	_updateStatsBtns = function()
		local on = Color3.fromRGB(200, 50, 50)
		local off = THEME.NEON
		if _statsBtnFpsPing then _statsBtnFpsPing.BackgroundColor3 = (_statsMode == "both") and on or off end
		if _statsBtnFps then _statsBtnFps.BackgroundColor3 = (_statsMode == "fps") and on or off end
		if _statsBtnPing then _statsBtnPing.BackgroundColor3 = (_statsMode == "ping") and on or off end
	end

	local function _makeStatsBtn(label, mode)
		local rec, btn = createButton(label, label, function()
			-- Same mode -> disable (nil), different -> switch
			local newMode = (_statsMode == mode) and nil or mode
			_setStatsMode(newMode)
			_updateStatsBtns()
		end)
		return rec, btn
	end

	local _, fpsPingBtn = _makeStatsBtn("Show FPS+Ping", "both")
	_statsBtnFpsPing = fpsPingBtn
	local _, fpsBtn = _makeStatsBtn("Show FPS", "fps")
	_statsBtnFps = fpsBtn
	local _, pingBtn = _makeStatsBtn("Show Ping", "ping")
	_statsBtnPing = pingBtn

	createSubcategoryHeader("FPS Limiter")

	-- FPS Limiter: input + Set + Reset
	createInputWithButtons("FPS Limiter", "FPS cap (e.g. 60)", {"Set FPS", "Reset"}, "FPS Limiter", function(idx, box, btn)
		if idx == 1 then
			-- Set FPS
			local cap = tonumber(box.Text)
			if cap and cap > 0 and cap <= 999 then
				pcall(setfpscap, cap)
				btn.Text = cap .. " FPS OK"
				task.wait(1.2)
				btn.Text = "Set FPS"
			end
		elseif idx == 2 then
			-- Reset
			pcall(setfpscap, 0)
			box.Text = ""
			btn.Text = "Reset OK"
			task.wait(1)
			btn.Text = "Reset"
		end
	end)

	createSubcategoryHeader("Rendering & AFK")

	-- Disable 3D Rendering (toggle)
	local renderingDisabled = false
	local savedState = nil
	local Lighting = getService("Lighting")

	createToggleButton("Disable 3D Rendering", "Disable 3D Rendering", function(on)
		renderingDisabled = on
		if on then
			savedState = {
				QualityLevel = settings().Rendering.QualityLevel,
				GlobalShadows = Lighting.GlobalShadows,
				FogEnd = Lighting.FogEnd,
				FogStart = Lighting.FogStart,
				FogColor = Lighting.FogColor,
				Brightness = Lighting.Brightness,
				postEffects = {},
			}
			for _, v in pairs(Lighting:GetChildren()) do
				if v:IsA("PostEffect") or v:IsA("Sky") or v:IsA("Atmosphere") then
					table.insert(savedState.postEffects, {obj = v, enabled = v.Enabled})
					pcall(function() v.Enabled = false end)
				end
			end
			pcall(function()
				settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
			end)
			Lighting.GlobalShadows = false
			Lighting.FogStart = 0
			Lighting.FogEnd = 250
			Lighting.FogColor = Color3.fromRGB(0, 0, 0)
			Lighting.Brightness = 0
		else
			if savedState then
				pcall(function()
					settings().Rendering.QualityLevel = savedState.QualityLevel
				end)
				Lighting.GlobalShadows = savedState.GlobalShadows
				Lighting.FogStart = savedState.FogStart
				Lighting.FogEnd = savedState.FogEnd
				Lighting.FogColor = savedState.FogColor
				Lighting.Brightness = savedState.Brightness
				for _, entry in pairs(savedState.postEffects) do
					pcall(function() entry.obj.Enabled = entry.enabled end)
				end
				savedState = nil
			end
		end
	end)

	-- Anti-AFK (via LocalPlayer.Idled — not detectable)
	local afkConn = nil
	createToggleButton("Anti-AFK", "Anti-AFK", function(on)
		if on then
			afkConn = LocalPlayer.Idled:Connect(function()
				if G.shutdown then return end
				-- Defensive nudge via lazy getService VirtualUser in pcall
				pcall(function()
					local ok, vu = pcall(function()
						if cloneref then return cloneref(getService("VirtualUser")) end
						return getService("VirtualUser")
					end)
					if ok and vu then
						vu:CaptureController()
					end
				end)
			end)
			G.afkConn = afkConn
		else
			if afkConn then
				pcall(function() afkConn:Disconnect() end)
				afkConn = nil
			end
			G.afkConn = nil
		end
	end)
end

--==== TAB: Integration =================================================
do
	setActive("Integration")
	createSubcategoryHeader("Infinity Yield")

	createButton("Launch Infinity Yield", "Launch Infinity Yield", function()
		loadstring(game:HttpGet('https://raw.githubusercontent.com/DarkNetworks/Infinite-Yield/main/latest.lua'))()
	end)

	createSubcategoryHeader("Simple Spy")

	createButton("Simple Spy", "Launch Simple Spy", function()
		loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/78n/SimpleSpy/main/SimpleSpyBeta.lua"))()
	end)

	createSubcategoryHeader("Hydroxide")

	createButton("Hydroxide", "Launch Hydroxide", function()
		local owner = "Upbolt"
		local branch = "revision"
		local function webImport(file)
			return loadstring(game:HttpGetAsync(("https://raw.githubusercontent.com/%s/Hydroxide/%s/%s.lua"):format(owner, branch, file)), file .. '.lua')()
		end
		webImport("init")
		webImport("ui/main")
	end)

	createSubcategoryHeader("Terminate")

	createButton("Terminate All", "Terminate All External", function()
		local ownInstances = { ScreenGui, G.crosshairGui, G.statsGui, G.cursorGui }
		for _, v in pairs(CoreGui:GetChildren()) do
			if v:IsA("ScreenGui") then
				local isOwn = false
				for _, o in ipairs(ownInstances) do
					if o and v == o then isOwn = true break end
				end
				if not isOwn and v.Name ~= RN.Gui and not v.Name:match("Roblox") then
					pcall(function() v:Destroy() end)
				end
			end
		end
		pcall(function()
			if getgenv().IY_LOADED then getgenv().IY_LOADED = false end
			if _G.IY_LOADED then _G.IY_LOADED = false end
			if getgenv().SimpleSpy then getgenv().SimpleSpy = nil end
			if getgenv().SS then getgenv().SS = nil end
			if _G.SimpleSpy then _G.SimpleSpy = nil end
			if _G.SS then _G.SS = nil end
			if getgenv().Hydroxide then getgenv().Hydroxide = nil end
			if _G.Hydroxide then _G.Hydroxide = nil end
		end)
	end)
end

--===========================================================================
-- CROSSHAIR (рендер + превью)
--===========================================================================
local CrosshairGui, chFrames, previewFrames

-- Панель превью справа от меню (появляется при включении прицела)
local previewPanel = Instance.new("Frame")
previewPanel.Size = UDim2.new(0, 150, 0, 170)
previewPanel.Position = UDim2.new(1, 12, 0, 44)   -- справа от MainFrame
previewPanel.BackgroundColor3 = THEME.BG_MAIN
previewPanel.BorderSizePixel = 0
previewPanel.Visible = false
previewPanel.Parent = MainFrame
Instance.new("UICorner", previewPanel).CornerRadius = UDim.new(0, 10)
do local og = Instance.new("UIStroke", previewPanel); og.Color = THEME.NEON; og.Thickness = 1.5; og.Transparency = 0.4 end

local previewTitle = Instance.new("TextLabel")
previewTitle.Size = UDim2.new(1, 0, 0, 22)
previewTitle.BackgroundTransparency = 1
previewTitle.Text = "Preview"
previewTitle.TextColor3 = THEME.NEON
previewTitle.Font = Enum.Font.GothamBold
previewTitle.TextSize = 12
previewTitle.Parent = previewPanel

local previewCanvas = Instance.new("Frame")   -- квадрат, в центре которого рисуем прицел
previewCanvas.Size = UDim2.new(0, 130, 0, 130)
previewCanvas.Position = UDim2.new(0.5, -65, 0, 30)
previewCanvas.BackgroundColor3 = THEME.BG_SIDE
previewCanvas.BorderSizePixel = 0
previewCanvas.ClipsDescendants = true
previewCanvas.Parent = previewPanel
Instance.new("UICorner", previewCanvas).CornerRadius = UDim.new(0, 6)

local function mkFrame(parent)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Crosshair.Color
	f.Visible = false
	f.Parent = parent
	return f
end

local function buildCrosshairGui()
	if CrosshairGui then return end
	CrosshairGui = Instance.new("ScreenGui")
	CrosshairGui.Name = rnd()
	CrosshairGui.IgnoreGuiInset = true
	CrosshairGui.DisplayOrder = 20
	CrosshairGui.ResetOnSpawn = false
	hiddenParent(CrosshairGui)
	G.crosshairGui = CrosshairGui
	chFrames = { top = mkFrame(CrosshairGui), bottom = mkFrame(CrosshairGui),
	             left = mkFrame(CrosshairGui), right = mkFrame(CrosshairGui), dot = mkFrame(CrosshairGui) }
	previewFrames = { top = mkFrame(previewCanvas), bottom = mkFrame(previewCanvas),
	                  left = mkFrame(previewCanvas), right = mkFrame(previewCanvas), dot = mkFrame(previewCanvas) }
end

-- Разложить 5 фреймов относительно ЦЕНТРА их родителя (0.5, 0.5).
-- Работает и для экрана, и для превью-канвы, т.к. всё в scale-центре.
local function applyCrosshair(fr)
	if not fr then return end
	local en = Crosshair.Enabled
	local L, W, GAP = Crosshair.Length, Crosshair.Width, Crosshair.Gap
	local off = GAP + L / 2
	-- top
	fr.top.Size = UDim2.new(0, W, 0, L)
	fr.top.Position = UDim2.new(0.5, 0, 0.5, -off)
	fr.top.BackgroundColor3 = Crosshair.Color
	fr.top.Visible = en and Crosshair.Top
	-- bottom
	fr.bottom.Size = UDim2.new(0, W, 0, L)
	fr.bottom.Position = UDim2.new(0.5, 0, 0.5, off)
	fr.bottom.BackgroundColor3 = Crosshair.Color
	fr.bottom.Visible = en and Crosshair.Bottom
	-- left
	fr.left.Size = UDim2.new(0, L, 0, W)
	fr.left.Position = UDim2.new(0.5, -off, 0.5, 0)
	fr.left.BackgroundColor3 = Crosshair.Color
	fr.left.Visible = en and Crosshair.Left
	-- right
	fr.right.Size = UDim2.new(0, L, 0, W)
	fr.right.Position = UDim2.new(0.5, off, 0.5, 0)
	fr.right.BackgroundColor3 = Crosshair.Color
	fr.right.Visible = en and Crosshair.Right
	-- dot
	fr.dot.Size = UDim2.new(0, Crosshair.DotThickness, 0, Crosshair.DotThickness)
	fr.dot.Position = UDim2.new(0.5, 0, 0.5, 0)
	fr.dot.BackgroundColor3 = Crosshair.Color
	fr.dot.Visible = en and Crosshair.DotEnabled
end

local function updateCrosshair()
	if not CrosshairGui then buildCrosshairGui() end
	applyCrosshair(chFrames)
	applyCrosshair(previewFrames)
end

--==== TAB: Crosshair ===================================================
do
	setActive("Crosshair")
	createSubcategoryHeader("Crosshair")

	-- (1) Мастер-переключатель прицела. Всё остальное — под-опции.
	local chRow
	chRow = createCheckbox("Enable Crosshair", false, "Enable Crosshair", nil, function(on)
		Crosshair.Enabled = on
		setChildrenEnabled(chRow, on)   -- (правило) пока прицел выкл — остальные скрыты
		previewPanel.Visible = on        -- (2) окно превью справа появляется при включении
		updateCrosshair()
	end)

	-- Заранее объявляем строки, к которым обращаемся из колбэков
	local widthRow, lengthRow, dotThickRow

	-- (3) 4 палочки, все ВКЛ по дефолту. При переключении обновляем слайдеры ширины/длины.
	local function refreshSticks()
		if widthRow then updateRow(widthRow) end
		if lengthRow then updateRow(lengthRow) end
		updateCrosshair()
		task.defer(function() refreshScroll(ACTIVE_TAB) end)
	end
	createCheckbox("Left stick",   true, "Left stick",   chRow, function(on) Crosshair.Left = on;   refreshSticks() end)
	createCheckbox("Right stick",  true, "Right stick",  chRow, function(on) Crosshair.Right = on;  refreshSticks() end)
	createCheckbox("Top stick",    true, "Top stick",    chRow, function(on) Crosshair.Top = on;    refreshSticks() end)
	createCheckbox("Bottom stick", true, "Bottom stick", chRow, function(on) Crosshair.Bottom = on; refreshSticks() end)

	-- (4) Ползунки ширины и длины палочек. Видны только когда ВКЛючена хотя бы 1 палочка.
	local anyStick = function() return Crosshair.Left or Crosshair.Right or Crosshair.Top or Crosshair.Bottom end
	widthRow = createSlider("Stick Width", 2, "Stick Width", false, false, function(v)
		Crosshair.Width = v; updateCrosshair()
	end, 1, 20, chRow)
	widthRow.visibleExtra = anyStick
	updateRow(widthRow)

	lengthRow = createSlider("Stick Length", 10, "Stick Length", false, false, function(v)
		Crosshair.Length = v; updateCrosshair()
	end, 1, 100, chRow)
	lengthRow.visibleExtra = anyStick
	updateRow(lengthRow)

	-- (5) Точка (по дефолту ВЫКЛ). (6) Толщина точки видна только когда точка ВКЛ.
	createCheckbox("Dot", false, "Dot", chRow, function(on)
		Crosshair.DotEnabled = on
		if dotThickRow then updateRow(dotThickRow) end
		updateCrosshair()
		task.defer(function() refreshScroll(ACTIVE_TAB) end)
	end)
	dotThickRow = createSlider("Dot Thickness", 2, "Dot Thickness", false, false, function(v)
		Crosshair.DotThickness = v; updateCrosshair()
	end, 1, 20, chRow)
	dotThickRow.visibleExtra = function() return Crosshair.DotEnabled end
	updateRow(dotThickRow)
end

--==== TAB: Etc ==========================================================
do
	setActive("Etc")
	createSubcategoryHeader("Cursor Tracker")

	local CursorGui = nil
	local CursorLabel = nil
	local CursorConn = nil

	local function startCursorTracker()
		if CursorGui then return end
		CursorGui = Instance.new("ScreenGui")
		CursorGui.Name = RN.CursorGui
		hiddenParent(CursorGui)
		G.cursorGui = CursorGui

		CursorLabel = Instance.new("TextLabel")
		CursorLabel.Size = UDim2.new(0, 300, 0, 50)
		CursorLabel.Position = UDim2.new(0.5, -150, 0, 20)
		CursorLabel.BackgroundColor3 = THEME.BG_MAIN
		CursorLabel.TextColor3 = THEME.TEXT_DIM
		CursorLabel.Font = Enum.Font.GothamBold
		CursorLabel.TextSize = 16
		CursorLabel.Text = "Tap screen (Terminate via menu)"
		Instance.new("UICorner", CursorLabel).CornerRadius = UDim.new(0, 6)
		CursorLabel.Parent = CursorGui

		CursorConn = UserInputService.InputBegan:Connect(function(input, gp)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				local mousePos = UserInputService:GetMouseLocation()
				CursorLabel.Text = string.format("X: %d | Y: %d", mousePos.X, mousePos.Y)
			end
		end)
		G.cursor = CursorConn
	end

	local function stopCursorTracker()
		if CursorConn then CursorConn:Disconnect(); CursorConn = nil end
		if CursorGui then CursorGui:Destroy(); CursorGui = nil end
		G.cursorGui = nil
		if G.cursor then G.cursor:Disconnect(); G.cursor = nil end
	end

	createButton("Get cursor coordinates", "Get cursor coordinates", startCursorTracker)
	createButton("Terminate cursor tracker", "Terminate cursor tracker", stopCursorTracker)

	createSubcategoryHeader("Position")

	-- Player coordinates
	local coordsRow = createFunctionWithOutput("Get player coordinates", "Coordinates: None", "Get player coordinates", function(outBox)
		local char = LocalPlayer.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			local pos = char.HumanoidRootPart.Position
			outBox.Text = string.format("X: %.1f | Y: %.1f | Z: %.1f", pos.X, pos.Y, pos.Z)
		else
			outBox.Text = "Character not found"
		end
	end)

	-- PlaceID
	createFunctionWithOutput("Get PlaceID", "Click button above to get ID", "Get PlaceID", function(outBox)
		local id = tostring(game.PlaceId)
		outBox.Text = "PlaceID: " .. id .. " (click to copy)"
	end)

	createSubcategoryHeader("Autoclick")

	-- Autoclicker state
	local acXYEnabled = false
	local acCursorEnabled = false
	local acRunning = false
	local acKey = nil
	local acSpeedMs = 100
	local acLastClick = 0
	local acXY_X = nil
	local acXY_Y = nil

	-- Key binding button
	local keyBtnRec, keyBtn = createButton("Key to enable/disable autoclicker", "Key bind autoclicker", function() end)
	local keyBtnWaiting = false
	keyBtn.MouseButton1Click:Connect(function()
		if keyBtnWaiting then return end
		keyBtnWaiting = true
		keyBtn.Text = "Press any key..."
		keyBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
		local forbidden = {
			[Enum.KeyCode.Insert] = true, [Enum.KeyCode.Delete] = true,
			[Enum.KeyCode.Escape] = true, [Enum.KeyCode.W] = true,
			[Enum.KeyCode.A] = true, [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true,
			[Enum.KeyCode.LeftControl] = true, [Enum.KeyCode.LeftShift] = true,
			[Enum.KeyCode.Tab] = true,
		}
		local conn
		conn = UserInputService.InputBegan:Connect(function(input, gp)
			if gp then return end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			if forbidden[input.KeyCode] then return end
			acKey = input.KeyCode
			keyBtn.Text = "Key: " .. input.KeyCode.Name
			keyBtn.BackgroundColor3 = THEME.NEON
			keyBtnWaiting = false
			conn:Disconnect()
		end)
	end)

	-- Cursor autoclicker toggle (mutually exclusive with XY)
	-- setState functions are forward-declared so each handler can reset
	-- the OTHER checkbox visually without re-entering its own callback.
	local acCursorSetState, acXYSetState
	local acCursorRow, _, _, state1 = createCheckbox("Autoclicker", false, "Autoclicker cursor", nil, function(on)
		acCursorEnabled = on
		if on then
			if acXYEnabled then
				acXYEnabled = false
				acRunning = false
				if acXYSetState then acXYSetState(false, true) end
			end
		else
			if not acXYEnabled then acRunning = false end
		end
	end)
	acCursorSetState = state1

	-- XY autoclicker toggle (mutually exclusive with cursor)
	local acXYRow
	acXYRow, _, _, state2 = createCheckbox("Auto Clicker for XY", false, "Auto Clicker XY", nil, function(on)
		acXYEnabled = on
		setChildrenEnabled(acXYRow, on)
		if on then
			if acCursorEnabled then
				acCursorEnabled = false
				acRunning = false
				if acCursorSetState then acCursorSetState(false, true) end
			end
		else
			if not acCursorEnabled then acRunning = false end
		end
	end)
	acXYSetState = state2

	-- Now that acXYRow is defined, attach children (X/Y inputs + speed slider)

	-- X/Y input row (sub-option XY)
	local xyRow = Instance.new("Frame")
	xyRow.Size = UDim2.new(1, -10, 0, 28)
	xyRow.BackgroundTransparency = 1
	local xyRec = registerRow(xyRow, "XY inputs autoclicker", acXYRow)
	local xyLayout = Instance.new("UIListLayout", xyRow)
	xyLayout.FillDirection = Enum.FillDirection.Horizontal
	xyLayout.Padding = UDim.new(0, 6)
	xyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	xyLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	local acXBox = Instance.new("TextBox")
	acXBox.Size = UDim2.new(0.48, 0, 1, 0)
	acXBox.BackgroundColor3 = THEME.UI_ELEM
	acXBox.TextColor3 = THEME.TEXT_MAIN
	acXBox.PlaceholderText = "X"
	acXBox.Text = ""
	acXBox.Font = Enum.Font.Gotham
	acXBox.TextSize = 13
	acXBox.LayoutOrder = 1
	Instance.new("UICorner", acXBox).CornerRadius = UDim.new(0, 6)
	acXBox.Parent = xyRow

	local acYBox = Instance.new("TextBox")
	acYBox.Size = UDim2.new(0.48, 0, 1, 0)
	acYBox.BackgroundColor3 = THEME.UI_ELEM
	acYBox.TextColor3 = THEME.TEXT_MAIN
	acYBox.PlaceholderText = "Y"
	acYBox.Text = ""
	acYBox.Font = Enum.Font.Gotham
	acYBox.TextSize = 13
	acYBox.LayoutOrder = 2
	Instance.new("UICorner", acYBox).CornerRadius = UDim.new(0, 6)
	acYBox.Parent = xyRow

	acXBox.FocusLost:Connect(function() acXY_X = tonumber(acXBox.Text) end)
	acYBox.FocusLost:Connect(function() acXY_Y = tonumber(acYBox.Text) end)

	-- Autoclicker speed slider (standalone — needed for both modes)
	createSlider("Autoclicker Speed (ms)", 100, "Autoclicker Speed", false, false, function(v)
		acSpeedMs = v
	end, 10, 2000, nil)

	-- Global Heartbeat: one connection for all click modes
	G.autoClicker = RunService.Heartbeat:Connect(function()
		if G.shutdown then return end
		if not acRunning then return end
		local now = tick()
		if (now - acLastClick) < (acSpeedMs / 1000) then return end
		acLastClick = now
		if acXYEnabled and acXY_X and acXY_Y then
			pcall(function() mousemoveabs(acXY_X, acXY_Y) end)
			task.wait(0.01)
			pcall(mouse1press)
			task.delay(math.random(50, 150) / 1000, function()
				if G.shutdown then return end
				pcall(mouse1release)
			end)
		elseif acCursorEnabled then
			pcall(mouse1press)
			task.delay(math.random(50, 150) / 1000, function()
				if G.shutdown then return end
				pcall(mouse1release)
			end)
		end
	end)

	-- Key activation listener
	G.autoClickerKey = UserInputService.InputBegan:Connect(function(input, gp)
		if G.shutdown then return end
		if gp then return end
		if acKey and input.KeyCode == acKey then
			if acXYEnabled or acCursorEnabled then
				acRunning = not acRunning
			end
		end
	end)
end

--===========================================================================
-- CLOCK + FPS/PING IN HEADER
--===========================================================================
G.clockLoop = task.spawn(function()
	while not G.shutdown and menuIsOpen do
		local t = os.date("*t")
		ClockLabel.Text = string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
		task.wait(1)
	end
end)

do
	local acc, samp, timer = 0, 0, 0
	G.headerStats = RunService.Heartbeat:Connect(function(dt)
		if G.shutdown then return end
		acc, samp, timer = acc + dt, samp + 1, timer + dt
		if timer < 0.5 then return end
		timer = 0
		local fps = math.floor(samp / acc)
		local ping = math.floor((LocalPlayer:GetNetworkPing() or 0) * 1000)
		StatsLabel.Text = "FPS " .. fps .. " | Ping " .. ping
		acc, samp = 0, 0
	end)
end

--===========================================================================
-- УНИВЕРСАЛЬНЫЙ РЕЗОЛВЕР ПЕРСОНАЖА (ESP + Aim, любая игра)
-- Кэшируется, чтобы не делать тяжёлый поиск каждый кадр (защита от фризов).
--===========================================================================
local ROOT_NAMES = { "HumanoidRootPart", "Torso", "UpperTorso", "Root", "LowerTorso", "Head" }
local AIM_PART_FALLBACKS = { "Head", "HumanoidRootPart", "Torso", "UpperTorso", "Root" }

-- корневая часть без опоры на Humanoid
local function resolveRoot(model)
	if not model then return nil end
	for _, name in ipairs(ROOT_NAMES) do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then return p end
	end
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

-- прицельная часть с фолбэком (для Aim и Boxes)
local function resolveAimPart(model, preferred)
	if not model then return nil end
	if preferred then
		local p = model:FindFirstChild(preferred)
		if p and p:IsA("BasePart") then return p end
	end
	for _, name in ipairs(AIM_PART_FALLBACKS) do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then return p end
	end
	return resolveRoot(model)
end

-- жив ли (без жёсткой опоры на Humanoid.Health)
local function resolveAlive(model)
	if not model or not model.Parent then return false end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then return hum.Health > 0 end
	return resolveRoot(model) ~= nil
end

-- КЭШ модели персонажа на игрока (обновляется по таймеру, а не каждый кадр)
local _charResolveCache = {}   -- [player] = { model = Model, t = tick() }
local _CHAR_RESOLVE_TTL = 1.0  -- секунда; тела не пересоздаются каждый кадр

local function _deepFindPlayerModel(player)
	-- 1) стандартный путь
	local c = player.Character
	if c and resolveRoot(c) then return c end
	-- 2) кастомные контейнеры (динамически — тела пересоздаются на респавне)
	local containers = {
		workspace:FindFirstChild("Players"),
		workspace:FindFirstChild("Characters"),
		workspace:FindFirstChild("Ignore"),
		workspace:FindFirstChild("Living"),
		workspace:FindFirstChild("Alive"),
	}
	for _, cont in ipairs(containers) do
		if cont then
			local m = cont:FindFirstChild(player.Name)
			if m and m:IsA("Model") and resolveRoot(m) then return m end
		end
	end
	-- 3) прямой ребёнок workspace с именем игрока
	local direct = workspace:FindFirstChild(player.Name)
	if direct and direct:IsA("Model") and resolveRoot(direct) then return direct end
	return nil
end

local function resolveCharacter(player)
	local entry = _charResolveCache[player]
	local now = tick()
	if entry and entry.model and entry.model.Parent and (now - entry.t) < _CHAR_RESOLVE_TTL then
		-- быстрый путь: проверяем только валидность кэша
		if resolveRoot(entry.model) then return entry.model end
	end
	local model = _deepFindPlayerModel(player)
	_charResolveCache[player] = { model = model, t = now }
	return model
end

--===========================================================================
-- PHANTOM FORCES ESP PROVIDER (PlaceId 292439477)
-- В PF у игроков player.Character = nil: тела лежат в workspace.Players/<teamFolder>/<model>.
-- Имена моделей зашифрованы и меняются; PrimaryPart = nil; Humanoid отсутствует.
-- Ник игрока лежит в model.NameTagGui.PlayerTag (TextLabel); ХП — в model.NameTagGui.Health (Frame).
--===========================================================================
local _pfCache = {}  -- [Model] = { Highlight=..., Box=..., lastMode=... }

_pfEspClear = function(model)
	if model then
		local c = _pfCache[model]
		if c then
			if c._cubes then
				for _, obj in pairs(c._cubes) do
					if typeof(obj) == "Instance" then pcall(function() obj:Destroy() end) end
				end
			end
			for k, obj in pairs(c) do
				if k ~= "_cubes" then
					if typeof(obj) == "Instance" then pcall(function() obj:Destroy() end)
					elseif type(obj) ~= "string" then pcall(function() obj:Remove() end) end
				end
			end
			_pfCache[model] = nil
		end
	else
		for m in pairs(_pfCache) do _pfEspClear(m) end
		_pfCache = {}
	end
end

-- крупная часть тела для бокса/дистанции (не оружие);
-- части вложены в подпапки модели → обходим через GetDescendants
local function _pfBodyRoot(model)
	local best, bestVol = nil, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local s = d.Size
			-- крупные части тела (>0.4 по всем осям); мелочь/детали оружия пропускаем
			if s.X > 0.4 and s.Y > 0.4 and s.Z > 0.4 then
				local vol = s.X * s.Y * s.Z
				if vol > bestVol then bestVol = vol; best = d end
			end
		end
	end
	return best
end

-- ник игрока из NameTagGui (рекурсивно, т.к. может быть вложен глубже модели)
local function _pfName(model)
	local gui = model:FindFirstChild("NameTagGui", true)
	if gui then
		local tag = gui:FindFirstChild("PlayerTag", true)
		if tag and tag:IsA("TextLabel") then return tag.Text end
	end
	return nil
end

-- Кэш анализа команд PF: [Model] = "ally"/"enemy"/nil
local _pfTeamMap = {}
local _pfAllyColor = nil   -- Color3 союзной команды (определяется анализом)
local _pfEnemyColor = nil

-- цвет ника модели (маркер команды в PF)
local function _pfTagColor(model)
	local gui = model:FindFirstChild("NameTagGui", true)
	if not gui then return nil end
	local tag = gui:FindFirstChild("PlayerTag", true)
	if not (tag and tag:IsA("TextLabel")) then return nil end
	return tag.TextColor3
end

-- сравнение цветов с допуском
local function _pfColorEq(a, b)
	if not a or not b then return false end
	return math.abs(a.R-b.R) < 0.15 and math.abs(a.G-b.G) < 0.15 and math.abs(a.B-b.B) < 0.15
end

-- классификация одного цвета: циан/зелёный = ally, красный = enemy
local function _pfClassifyColor(c)
	if not c then return nil end
	if c.G > 0.5 and c.R < 0.5 then return "ally"
	elseif c.R > 0.5 and c.G < 0.5 then return "enemy" end
	return nil
end

-- Полный анализ структуры: собирает цвета, группирует, логирует.
-- Вызывается при переключении Show teammates и включении PF Mode.
_pfAnalyzeTeams = function()
	local pf = workspace:FindFirstChild("Players")
	_pfTeamMap = {}
	_pfAllyColor, _pfEnemyColor = nil, nil
	if not pf then
		warn("[ESP PF] workspace.Players не найден — анализ невозможен")
		return
	end
	-- собрать уникальные цвета и посчитать модели
	local groups = {}  -- { {color=Color3, count=n, folder=name} , ... }
	local total = 0
	for _, folder in ipairs(pf:GetChildren()) do
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") then
				total = total + 1
				local col = _pfTagColor(m)
				if col then
					local matched
					for _, g in ipairs(groups) do
						if _pfColorEq(g.color, col) then matched = g; break end
					end
					if matched then
						matched.count = matched.count + 1
					else
						groups[#groups+1] = { color = col, count = 1, folder = folder.Name }
					end
					local cls = _pfClassifyColor(col)
					_pfTeamMap[m] = cls
					if cls == "ally" and not _pfAllyColor then _pfAllyColor = col end
					if cls == "enemy" and not _pfEnemyColor then _pfEnemyColor = col end
				else
					_pfTeamMap[m] = nil  -- цвет не прочитан → показываем
				end
			end
		end
	end
	-- лог
	print("=== [ESP PF] Team analysis ===")
	print("  Всего моделей:", total, "| цветовых групп:", #groups)
	for i, g in ipairs(groups) do
		print(string.format("  Группа %d: color=(%.2f,%.2f,%.2f) count=%d class=%s folder=%s",
			i, g.color.R, g.color.G, g.color.B, g.count,
			tostring(_pfClassifyColor(g.color)), tostring(g.folder)))
	end
	if #groups > 2 then
		warn("[ESP PF] Обнаружено >2 цветовых групп — фильтр может работать неточно")
	elseif #groups < 2 then
		warn("[ESP PF] <2 групп — все игроки одного цвета? Фильтр покажет всех")
	end
	print("  Ally color:", tostring(_pfAllyColor), "| Enemy color:", tostring(_pfEnemyColor))
	print("==============================")
end

-- определить свою команду: папка, в которой лежит собственная модель LocalPlayer.
-- Сначала через resolveCharacter (надёжно: работает и в PF), затем fallback по нику
-- из NameTagGui (с нормализацией: trim + strip rich-text-обёрток).
local function _pfNormalizeName(s)
	if not s then return nil end
	s = s:gsub("%s+", " "):match("^%s*(.-)%s*$")  -- trim
	return s
end

local function _pfMyTeamFolder(pf)
	-- 1) через resolveCharacter — находит модель LocalPlayer любыми способами
	local myModel = resolveCharacter(LocalPlayer)
	if myModel then
		local parent = myModel.Parent
		if parent and parent:IsA("Folder") and parent.Parent == pf then
			return parent
		end
	end
	-- 2) fallback: сравнение нормализованного ника из NameTagGui
	local myDisplay = _pfNormalizeName(LocalPlayer.DisplayName)
	local myName = _pfNormalizeName(LocalPlayer.Name)
	for _, team in ipairs(pf:GetChildren()) do
		for _, m in ipairs(team:GetChildren()) do
			if m:IsA("Model") then
				local nm = _pfNormalizeName(_pfName(m))
				if nm and (nm == myDisplay or nm == myName) then
					return team
				end
			end
		end
	end
	return nil
end

-- _pfMyTeamCached — forward-объявленная (сбрасывается из колбэка Show teammates); оставлена для совместимости
_pfMyTeamCached = nil

-- собрать все тела: при hideTeam прячем только уверенно определённых союзников
local function _pfGetBodies()
	local list = {}
	local pf = workspace:FindFirstChild("Players")
	if not pf then return list end
	local hideTeam = (not ESP.ShowTeam)
	for _, folder in ipairs(pf:GetChildren()) do
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") then
				if hideTeam then
					-- прячем только уверенно определённых союзников; остальных показываем
					local cls = _pfTeamMap[m]
					if cls == nil then
						-- модель появилась после анализа — классифицируем на лету
						cls = _pfClassifyColor(_pfTagColor(m))
						_pfTeamMap[m] = cls
					end
					if cls ~= "ally" then
						list[#list+1] = m
					end
				else
					list[#list+1] = m
				end
			end
		end
	end
	return list
end

local function _pfRunEsp()
	-- убрать кэш для исчезнувших моделей
	for model in pairs(_pfCache) do
		if not model.Parent then _pfEspClear(model) end
	end

	local bodies = _pfGetBodies()
	local seen = {}
	local camPos = Camera.CFrame.Position

	for _, model in ipairs(bodies) do
		seen[model] = true
		local root = _pfBodyRoot(model)
		if root then
			-- дистанция
			local inRange = true
			if ESP.Radius < 10000 then
				local d = root.Position - camPos
				inRange = (d:Dot(d) <= ESP.Radius * ESP.Radius)
			end

			local cache = _pfCache[model]
			if not cache or cache.lastMode ~= ESP.Mode then
				_pfEspClear(model)
				_pfCache[model] = { lastMode = ESP.Mode }
				cache = _pfCache[model]
			end

			if not inRange then
				if cache.Highlight then cache.Highlight.Enabled = false end
				if cache.Box then cache.Box.Visible = false end
				if cache._cubes then
					for _, v in pairs(cache._cubes) do v.Visible = false end
				end
			elseif ESP.Mode == "Cubes" then
				-- PF: кубик по каждой крупной части тела (части вложены в подпапки → GetDescendants)
				if cache.Highlight then cache.Highlight.Enabled = false end
				if not cache._cubes then cache._cubes = {} end
				local cubes = cache._cubes
				local active = {}
				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") and part.Transparency < 1 then
						local s = part.Size
						-- крупные части тела (>0.4 по всем осям), мелочь/оружие пропускаем
						if s.X > 0.4 and s.Y > 0.4 and s.Z > 0.4 then
							active[part] = true
							if not cubes[part] then
								local box = Instance.new("BoxHandleAdornment")
								box.Name = rnd()
								box.Size = s + _SIZE_OFFSET
								box.AlwaysOnTop = true
								box.ZIndex = 5
								box.Transparency = 0.6
								hiddenParent(box)
								box.Adornee = part
								cubes[part] = box
							end
							cubes[part].Visible = true
							if cubes[part].Color3 ~= ESP.Color then
								cubes[part].Color3 = ESP.Color
							end
							local newSize = s + _SIZE_OFFSET
							if cubes[part].Size ~= newSize then
								cubes[part].Size = newSize
							end
						end
					end
				end
				for p, obj in pairs(cubes) do
					if not active[p] then
						if typeof(obj) == "Instance" then pcall(function() obj:Destroy() end) end
						cubes[p] = nil
					end
				end
			elseif ESP.Mode == "Outline" or ESP.Mode == "Chams" then
				if cache._cubes then
					for _, obj in pairs(cache._cubes) do
						if typeof(obj) == "Instance" then pcall(function() obj:Destroy() end) end
					end
					cache._cubes = nil
				end
				if not cache.Highlight then
					local hl = Instance.new("Highlight")
					hl.Name = rnd()
					hl.Adornee = model
					hiddenParent(hl)
					cache.Highlight = hl
				end
				local hl = cache.Highlight
				hl.Enabled = true
				if hl.FillColor ~= ESP.Color then hl.FillColor = ESP.Color end
				if hl.OutlineColor ~= ESP.Color then hl.OutlineColor = ESP.Color end
				if ESP.Mode == "Chams" then
					if hl.FillTransparency ~= ESP.ChamsTransparency then hl.FillTransparency = ESP.ChamsTransparency end
					if hl.OutlineTransparency ~= 1 then hl.OutlineTransparency = 1 end
				else
					if hl.FillTransparency ~= 1 then hl.FillTransparency = 1 end
					if hl.OutlineTransparency ~= 0 then hl.OutlineTransparency = 0 end
				end
			elseif ESP.Mode == "Boxes" and Drawing then
				-- при переходе из Outline/Cubes/Chams — гасим старый Highlight
				if cache.Highlight then cache.Highlight.Enabled = false end
				if cache._cubes then
					for _, obj in pairs(cache._cubes) do
						if typeof(obj) == "Instance" then pcall(function() obj:Destroy() end) end
					end
					cache._cubes = nil
				end
				if not cache.Box then
					cache.Box = Drawing.new("Square")
					cache.Box.Thickness = 2
					cache.Box.Filled = false
				end
				local pos, onScreen = Camera:WorldToViewportPoint(root.Position)
				if onScreen and pos.Z > 0.1 then
					local w = math.clamp(1000 / pos.Z, 5, 2000)
					local h = math.clamp(1500 / pos.Z, 5, 3000)
					if cache.Box.Size ~= Vector2.new(w, h) then cache.Box.Size = Vector2.new(w, h) end
					local newPos = Vector2.new(pos.X - w/2, pos.Y - h/2)
					if cache.Box.Position ~= newPos then cache.Box.Position = newPos end
					if cache.Box.Color ~= ESP.Color then cache.Box.Color = ESP.Color end
					cache.Box.Visible = true
				else
					cache.Box.Visible = false
				end
			end
		end
	end

	-- очистить кэш моделей, которых больше нет в списке
	for model in pairs(_pfCache) do
		if not seen[model] then _pfEspClear(model) end
	end
end

--===========================================================================
-- AIMBOT (перенос из aim.lua, управляется таблицей Aim)
--===========================================================================
local aimHolding = false
local aimTarget = nil
local aimFov = nil

local function aimEnsureFov()
	if aimFov or not Drawing then return end
	aimFov = Drawing.new("Circle")
	aimFov.Thickness = 1.5
	aimFov.Filled = false
	aimFov.Transparency = 0.6
	aimFov.Color = Color3.fromRGB(255, 255, 255)
	aimFov.NumSides = 64
	aimFov.Visible = false
end
local function aimRemoveFov()
	if aimFov then pcall(function() aimFov:Remove() end); aimFov = nil end
end
G.aimRemoveFov = aimRemoveFov

local function aimIsAlive(player)
	local c = resolveCharacter(player)
	return c ~= nil and resolveAlive(c)
end

local function aimIsTeammate(player)
	if not Aim.TeamCheck then return false end
	if LocalPlayer.Team == nil then return false end
	return player.Team == LocalPlayer.Team
end

local function aimIsVisible(targetPart)
	if not Aim.WallCheck then return true end
	local lc = resolveCharacter(LocalPlayer)
	if not lc then return true end
	local origin = resolveRoot(lc)
	if not origin then return true end
	origin = origin.Position
	local dir = (targetPart.Position - origin)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { lc }
	local res = workspace:Raycast(origin, dir, rp)
	if res then
		local hit = res.Instance
		if hit and hit:IsDescendantOf(targetPart.Parent) then return true end
		return false
	end
	return true
end

local function aimGetClosest()
	local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
	local best, bestScore = nil, nil
	local lc = resolveCharacter(LocalPlayer)
	local lcRoot = lc and resolveRoot(lc)
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and not aimIsTeammate(player) and aimIsAlive(player) then
			local char = resolveCharacter(player)
			local part = char and resolveAimPart(char, Aim.AimPart)
			if part then
				local ok = true
				if lcRoot then
					local diff = part.Position - lcRoot.Position
					if diff:Dot(diff) > Aim.MaxDistance * Aim.MaxDistance then ok = false end
				end
				if ok then
					local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
					if onScreen then
						local screenDist = (Vector2.new(sp.X, sp.Y) - center).Magnitude
						if screenDist <= Aim.FOV_Radius and aimIsVisible(part) then
							local score
							if Aim.TargetMode == "Closest Distance" then
								score = lcRoot and (part.Position - lcRoot.Position).Magnitude or screenDist
							elseif Aim.TargetMode == "Lowest Health" then
								local hum = char:FindFirstChildOfClass("Humanoid")
								score = hum and hum.Health or math.huge
							else -- "Closest to Crosshair" (по умолчанию)
								score = screenDist
							end
							if not bestScore or score < bestScore then
								bestScore = score
								best = player
							end
						end
					end
				end
			end
		end
	end
	return best
end

local function aimAt(player)
	local char = resolveCharacter(player)
	if not char then return end
	local part = resolveAimPart(char, Aim.AimPart)
	if not part then return end
	local pos = part.Position
	if Aim.PredictionEnabled then
		local hrp = resolveRoot(char)
		if hrp then pos = pos + (hrp.AssemblyLinearVelocity * Aim.PredictionStrength) end
	end
	local cur = Camera.CFrame
	local target = CFrame.lookAt(cur.Position, pos)
	if Aim.Smoothing > 1 then
		Camera.CFrame = cur:Lerp(target, 1 / Aim.Smoothing)
	else
		Camera.CFrame = target
	end
end

-- Возвращает true, если клавиша/кнопка активации сейчас удерживается.
-- Работает даже если игра пометила InputBegan как gameProcessed (bind), т.к. опрашиваем состояние.
local function aimKeyHeld()
	-- Кнопка мыши (если забиндена)
	if Aim.ActivationInput then
		return UserInputService:IsMouseButtonPressed(Aim.ActivationInput)
	end
	-- Клавиатура
	if Aim.ActivationKey and Aim.ActivationKey ~= Enum.KeyCode.Unknown then
		return UserInputService:IsKeyDown(Aim.ActivationKey)
	end
	return false
end

G.aimLoop = RunService.RenderStepped:Connect(function()
	if G.shutdown then return end
	if not Aim.Enabled then
		if aimFov then aimFov.Visible = false end
		aimTarget = nil
		return
	end
	aimEnsureFov()
	if aimFov then
		aimFov.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
		aimFov.Radius = Aim.FOV_Radius
		aimFov.Visible = Aim.ShowFOV
	end
	if not aimKeyHeld() then aimTarget = nil; return end
	if aimTarget and not aimIsAlive(aimTarget) then aimTarget = nil end

	if Aim.AimLock then
		if aimTarget then
			local char = resolveCharacter(aimTarget)
			local part = char and resolveAimPart(char, Aim.AimPart)
			local valid = false
			if part then
				local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
				if onScreen then
					local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
					local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
					if d <= Aim.FOV_Radius then valid = true end
				end
			end
			if not valid then aimTarget = nil end
		end
		if not aimTarget then aimTarget = aimGetClosest() end
	else
		aimTarget = aimGetClosest()
	end

	if aimTarget then aimAt(aimTarget) end
end)

--===========================================================================
-- MM2 ROLE COLORING (Sheriff/Murderer/Innocent)
--===========================================================================
local MM2_SHERIFF  = Color3.fromRGB(40, 120, 255)  -- синий
local MM2_MURDERER = Color3.fromRGB(255, 25, 25)    -- красный
-- Innocent = THEME.NEON (розовый цвет меню)

local function getMM2Role(player)
	local char = resolveCharacter(player)
	if char then
		if char:FindFirstChild("Knife") then return "Murderer" end
		if char:FindFirstChild("Gun") then return "Sheriff" end
	end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then
		if bp:FindFirstChild("Knife") then return "Murderer" end
		if bp:FindFirstChild("Gun") then return "Sheriff" end
	end
	return "Innocent"
end

-- цвет ESP для конкретного игрока: по роли (если MM2Mode), иначе общий ESP.Color
local function getEspColor(player)
	if ESP.MM2Mode then
		local role = getMM2Role(player)
		if role == "Sheriff" then return MM2_SHERIFF
		elseif role == "Murderer" then return MM2_MURDERER
		else return THEME.NEON end
	end
	return ESP.Color
end

--===========================================================================
-- ESP RENDER LOOP
--===========================================================================
local _cachedPlayers = {}
local _playersLastUpdate = 0

local function _espEnsureText(cache, key)
	if not cache[key] then
		local t = Drawing.new("Text")
		t.Size = 17
		t.Center = true       -- центрирование по горизонтали относительно Position
		t.Outline = true
		t.Font = 0            -- UI-шрифт: при мелком размере самый плотный/читаемый из доступных
		cache[key] = t
	end
	return cache[key]
end
local function _espEnsureSquare(cache, key)
	if not cache[key] then
		local s = Drawing.new("Square")
		s.Filled = true
		cache[key] = s
	end
	return cache[key]
end

G.espLoop = RunService.RenderStepped:Connect(function(dt)
	if G.shutdown then return end
	if not ESP.Enabled then return end

	-- троттлинг: обновляем визуал ESP не чаще, чем раз в ~1/30 сек (30 Гц достаточно)
	G._espAccum = (G._espAccum or 0) + dt
	local INTERVAL = 1 / 30
	if G._espAccum < INTERVAL then return end
	G._espAccum = 0

	-- PF-провайдер: совсем другой путь обхода моделей (вместо Players:GetPlayers)
	if ESP.PFMode then
		_pfRunEsp()
		return
	end

	local now = tick()
	if now - _playersLastUpdate > 0.5 then
		_cachedPlayers = Players:GetPlayers()
		_playersLastUpdate = now
	end
	for _, player in ipairs(_cachedPlayers) do
		if player == LocalPlayer then continue end
		if not ESP.ShowTeam and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then
			clearESP(player); continue
		end

		local char = resolveCharacter(player)
		local hrp  = char and resolveRoot(char)

		if not char or not hrp or not resolveAlive(char) then
			clearESP(player); continue
		end

		local inRange
		if ESP.Radius >= 10000 then
			inRange = true
		else
			local d = hrp.Position - Camera.CFrame.Position
			inRange = (d:Dot(d) <= ESP.Radius * ESP.Radius)
		end

		if not espCache[player] then espCache[player] = {} end
		local cache = espCache[player]

		if cache.Character ~= char or cache.lastMode ~= ESP.Mode then
			clearESP(player)
			espCache[player] = {Character = char, lastMode = ESP.Mode}
			cache = espCache[player]
		end

		if not inRange then
			if cache.Highlight then cache.Highlight.Enabled = false end
			if cache.Box then cache.Box.Visible = false end
			if cache._cubes then
				for _, v in pairs(cache._cubes) do v.Visible = false end
			end
			for _, k in ipairs({"NameText","HealthText","DistText","HPBarBG","HPBarFill"}) do
				if cache[k] then cache[k].Visible = false end
			end
			continue
		end

		local espColor = getEspColor(player)

		if ESP.Mode == "Cubes" then
			local activeParts = {}
			if not cache._cubes then cache._cubes = {} end
			local cubes = cache._cubes
			local _rootName = hrp.Name
			for _, part in pairs(char:GetChildren()) do
				if part:IsA("BasePart") and part.Transparency < 1 and part.Name ~= _rootName then
					local id = "Cube_" .. part.Name
					activeParts[id] = true
					if not cubes[id] then
						local box = Instance.new("BoxHandleAdornment")
						box.Name = rnd()
						box.Size = part.Size + _SIZE_OFFSET
						box.AlwaysOnTop = true
						box.ZIndex = 5
						box.Transparency = 0.6
						hiddenParent(box)
						box.Adornee = part
						cubes[id] = box
					end
					cubes[id].Visible = true
					if cubes[id].Color3 ~= espColor then
						cubes[id].Color3 = espColor
					end
					local newSize = part.Size + _SIZE_OFFSET
					if cubes[id].Size ~= newSize then
						cubes[id].Size = newSize
					end
				end
			end
			for k, obj in pairs(cubes) do
				if not activeParts[k] then
					if typeof(obj) == "Instance" then pcall(function() obj:Destroy() end) end
					cubes[k] = nil
				end
			end

		elseif ESP.Mode == "Outline" or ESP.Mode == "Chams" then
			if not cache.Highlight then
				local hl = Instance.new("Highlight")
				hl.Name = rnd()
				hl.Adornee = char
				hiddenParent(hl)
				cache.Highlight = hl
			end
			local hl = cache.Highlight
			hl.Enabled = true
			hl.FillColor = espColor
			hl.OutlineColor = espColor
			if ESP.Mode == "Chams" then
				hl.FillTransparency = ESP.ChamsTransparency
				hl.OutlineTransparency = 1
			else
				hl.FillTransparency = 1
				hl.OutlineTransparency = 0
			end

		elseif ESP.Mode == "Boxes" and Drawing then
			if not cache.Box then
				cache.Box = Drawing.new("Square")
				cache.Box.Thickness = 2
				cache.Box.Filled = false
			end
			local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
			if onScreen and pos.Z > 0.1 then
				local width = math.clamp(1000 / pos.Z, 5, 2000)
				local height = math.clamp(1500 / pos.Z, 5, 3000)
				local size = Vector2.new(width, height)
				cache.Box.Size = size
				cache.Box.Position = Vector2.new(pos.X - size.X / 2, pos.Y - size.Y / 2)
				cache.Box.Color = espColor
				cache.Box.Visible = true
			else
				cache.Box.Visible = false
			end
		end
		-- текстовой/бар-overlay рендерится отдельным лупом G.textOverlayLoop (без троттлинга)
	end
end)

G.espRemoveConn = Players.PlayerRemoving:Connect(function(plr)
	clearESP(plr)
	_charResolveCache[plr] = nil
end)

--===========================================================================
-- ESP TEXT/HBAR OVERLAY LOOP (отдельный луп без троттлинга 30 Гц,
-- чтобы надписи/бар следовали за персонажем на полном FPS без рваности)
--===========================================================================
-- FIX: скрывает ВСЕ overlay-объекты (текст + HP-бар) у всех игроков, чтобы
-- Drawing-объекты не "зависали" в воздухе при выключении всех подписей.
local _ESP_OVERLAY_KEYS = {"NameText", "HealthText", "DistText", "HPBarBG", "HPBarFill"}
local function hideAllEspOverlays()
	for _, cache in pairs(espCache) do
		if type(cache) == "table" then
			for _, k in ipairs(_ESP_OVERLAY_KEYS) do
				if cache[k] then cache[k].Visible = false end
			end
		end
	end
end
G.textOverlayLoop = RunService.RenderStepped:Connect(function()
	if G.shutdown then return end
	if not ESP.Enabled or ESP.PFMode or not Drawing then return end
	if not (ESP.ShowNames or ESP.ShowHealth or ESP.ShowDistance or ESP.ShowHealthBar) then
		hideAllEspOverlays()
		return
	end

	local now = tick()
	if now - _playersLastUpdate > 0.5 then
		_cachedPlayers = Players:GetPlayers()
		_playersLastUpdate = now
	end

	local camPos = Camera.CFrame.Position
	local lineH = 18

	for _, player in ipairs(_cachedPlayers) do
		if player ~= LocalPlayer then
			if not (ESP.ShowTeam == false and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team) then
				local char = resolveCharacter(player)
				local hrp  = char and resolveRoot(char)
				if char and hrp and resolveAlive(char) then
					local inRange
					if ESP.Radius >= 10000 then
						inRange = true
					else
						local d = hrp.Position - camPos
						inRange = (d:Dot(d) <= ESP.Radius * ESP.Radius)
					end
					if inRange then
						local cache = espCache[player]
						-- кэш создаётся/чистится только основным espLoop; тут лишь обновляем позиции текста
						if cache then
							local hum = char:FindFirstChildOfClass("Humanoid")
							local head = char:FindFirstChild("Head") or hrp
							local headHalf = (head and head:IsA("BasePart") and head.Size.Y / 2) or 0.5
							local anchorWorld = head.Position + Vector3.new(0, headHalf + 2.0, 0)
							local sp, onScreen = Camera:WorldToViewportPoint(anchorWorld)

							local entries = {}
							if ESP.ShowNames then
								entries[#entries+1] = {key = "NameText", text = player.DisplayName}
							end
							if ESP.ShowHealth and hum then
								entries[#entries+1] = {key = "HealthText", text = math.floor(hum.Health) .. " HP"}
							end
							if ESP.ShowDistance then
								local d = (hrp.Position - camPos).Magnitude
								entries[#entries+1] = {key = "DistText", text = math.floor(d) .. "m"}
							end

							for _, k in ipairs({"NameText","HealthText","DistText"}) do
								local used = false
								for _, e in ipairs(entries) do if e.key == k then used = true break end end
								if not used and cache[k] then cache[k].Visible = false end
							end

							local wantBar = ESP.ShowHealthBar and hum and hum.MaxHealth > 0

							if onScreen and sp.Z > 0 then
								for i, e in ipairs(entries) do
									local t = _espEnsureText(cache, e.key)
									t.Text = e.text
									t.Color = ESP.Color
									t.Position = Vector2.new(sp.X, sp.Y - (#entries - i + 1) * lineH - 6)
									t.Visible = true
								end
								if wantBar then
									local frac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
									local barW, barH = 50, 3
									local bx = sp.X - barW / 2
									local by = sp.Y
									local bg = _espEnsureSquare(cache, "HPBarBG")
									bg.Size = Vector2.new(barW, barH)
									bg.Position = Vector2.new(bx, by)
									bg.Color = Color3.fromRGB(0, 0, 0)
									bg.Visible = true
									local fill = _espEnsureSquare(cache, "HPBarFill")
									fill.Size = Vector2.new(barW * frac, barH)
									fill.Position = Vector2.new(bx, by)
									fill.Color = Color3.fromRGB(255, 0, 0):Lerp(Color3.fromRGB(0, 255, 0), frac)
									fill.Visible = true
								else
									if cache.HPBarBG then cache.HPBarBG.Visible = false end
									if cache.HPBarFill then cache.HPBarFill.Visible = false end
								end
							else
								for _, k in ipairs({"NameText","HealthText","DistText","HPBarBG","HPBarFill"}) do
									if cache[k] then cache[k].Visible = false end
								end
							end
						end
					end
				end
			end
		end
	end
end)

--===========================================================================
-- PLAYER LOGIC LOOPS
--===========================================================================
local CtrlHeld = false
local SpaceHeld = false

G.heartbeat = RunService.Heartbeat:Connect(function(dt)
	if G.shutdown then return end
	local char = LocalPlayer.Character
	if not char or not char.Parent then return end
	local hum = char:FindFirstChild("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")

	if hum and hrp and hum.Health > 0 then
		-- WalkSpeed
		if PlayerMods.SpeedEnabled and PlayerMods.SpeedValue > 16 then
			if hum.MoveDirection.Magnitude > 0 then
				local extraSpeed = PlayerMods.SpeedValue - 16
				hrp.CFrame = hrp.CFrame + (hum.MoveDirection * extraSpeed * dt)
			end
		end

		-- Fly (LinearVelocity + AlignOrientation + Attachment)
		if PlayerMods.FlyEnabled then
			local mover = hrp:FindFirstChild(RN.FlyMover)
			local gyro = hrp:FindFirstChild(RN.FlyGyro)
			local att = hrp:FindFirstChild(RN.FlyAtt)

			if not mover then
				att = Instance.new("Attachment")
				att.Name = RN.FlyAtt
				att.Parent = hrp

				mover = Instance.new("LinearVelocity")
				mover.Name = RN.FlyMover
				mover.Attachment0 = att
				mover.MaxForce = math.random(80000, 120000)
				mover.VectorVelocity = Vector3.zero
				mover.RelativeTo = Enum.ActuatorRelativeTo.World
				mover.Parent = hrp

				gyro = Instance.new("AlignOrientation")
				gyro.Name = RN.FlyGyro
				gyro.Attachment0 = att
				gyro.RigidityEnabled = false
				gyro.MaxTorque = math.random(80000, 120000)
				gyro.Responsiveness = 40
				gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
				gyro.Parent = hrp
			end

			local moveDir = hum.MoveDirection
			local flySpeed = PlayerMods.FlySpeed or 50
			local yVelocity = 0
			if SpaceHeld then yVelocity = flySpeed end
			if CtrlHeld then yVelocity = -flySpeed end
			mover.VectorVelocity = (moveDir * flySpeed) + Vector3.new(0, yVelocity, 0)
			gyro.CFrame = Camera.CFrame
			if hum:GetState() ~= Enum.HumanoidStateType.Physics then
				hum:ChangeState(Enum.HumanoidStateType.Physics)
			end
		end

		-- Anti-Knockback
		if PlayerMods.AntiKnockback and not PlayerMods.FlyEnabled then
			if hum.MoveDirection.Magnitude == 0 then
				hrp.Velocity = Vector3.new(0, hrp.Velocity.Y, 0)
				hrp.RotVelocity = Vector3.new(0, 0, 0)
			end
		end
	end
end)

G.stepped = RunService.Stepped:Connect(function()
	if G.shutdown then return end
	if not PlayerMods.NoclipEnabled and not PlayerMods.WallWalkEnabled then return end
	_ensureParts()
	if PlayerMods.NoclipEnabled then
		for _, part in ipairs(_charParts) do
			if part.Parent then part.CanCollide = false end
		end
	else
		-- Wall Walk: disable collision except on legs/feet
		for _, part in ipairs(_charParts) do
			if part.Parent then
				local n = part.Name
				if not string.find(n, "Leg") and not string.find(n, "Foot") then
					part.CanCollide = false
				end
			end
		end
	end
end)

G.inputBegan = UserInputService.InputBegan:Connect(function(input, gp)
	if G.shutdown then return end
	if gp then return end
	if input.KeyCode == Enum.KeyCode.Space then
		SpaceHeld = true
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChild("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hum and hrp and PlayerMods.JumpEnabled and not PlayerMods.FlyEnabled then
			if hum.FloorMaterial ~= Enum.Material.Air or PlayerMods.InfJumpEnabled then
				hrp.Velocity = Vector3.new(hrp.Velocity.X, PlayerMods.JumpValue, hrp.Velocity.Z)
			end
		end
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		CtrlHeld = true
	end
end)

G.inputEndConn = UserInputService.InputEnded:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.Space then SpaceHeld = false
	elseif input.KeyCode == Enum.KeyCode.LeftControl then CtrlHeld = false end
end)

-- Infinite Jump (rate-limited)
local _lastInfJump = 0
G.jumpReq = UserInputService.JumpRequest:Connect(function()
	if G.shutdown then return end
	if not PlayerMods.InfJumpEnabled then return end
	local now = tick()
	if (now - _lastInfJump) < 0.25 then return end
	local char = LocalPlayer.Character
	if not char then return end
	local hum = char:FindFirstChild("Humanoid")
	if not hum or hum.Health <= 0 then return end
	if hum.FloorMaterial == Enum.Material.Air then
		_lastInfJump = now
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

--===========================================================================
-- TOGGLE MENU BY KEY (Delete)
--===========================================================================
G.menuKey = UserInputService.InputBegan:Connect(function(i, gp)
	if gp or G.shutdown then return end
	if i.KeyCode == Enum.KeyCode.Delete then
		onMenuToggle(not menuIsOpen)
	end
end)

--===========================================================================
-- KILL BUTTON
--===========================================================================
KillBtn.MouseButton1Click:Connect(function()
	G.shutdown = true
	menuIsOpen = false
	onMenuToggle(false)
	-- Cleanup fly / gold movers
	local char = LocalPlayer.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		local hrp = char.HumanoidRootPart
		local _cm = hrp:FindFirstChild(RN.FlyMover); if _cm then _cm:Destroy() end
		local _cg = hrp:FindFirstChild(RN.FlyGyro);  if _cg then _cg:Destroy() end
		local _ca = hrp:FindFirstChild(RN.FlyAtt);   if _ca then _ca:Destroy() end
		local _gm = hrp:FindFirstChild(RN.GoldMover); if _gm then _gm:Destroy() end
		local _gg = hrp:FindFirstChild(RN.GoldGyro);  if _gg then _gg:Destroy() end
		local _ga = hrp:FindFirstChild(RN.GoldAtt);  if _ga then _ga:Destroy() end
		local hum = char:FindFirstChild("Humanoid")
		if hum and hum:GetState() == Enum.HumanoidStateType.Physics then
			hum:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		_restoreCollision()
	end
	-- Cleanup ESP
	ESP.Enabled = false
	ESP.PFMode = false
	for _, p in pairs(Players:GetPlayers()) do clearESP(p) end
	_pfEspClear()
	-- Cleanup character resolver cache
	_charResolveCache = {}
	-- Stop state loops
	G.gold = false; G.goldClaim = false; G.autoFort = false
	G.slapple = false; G.spoofMask = false; G.antirag = false
	-- Cleanup stats overlay
	if G.statsConn then G.statsConn:Disconnect(); G.statsConn = nil end
	-- Disconnect all hot-loop connections
	for k, v in pairs(G) do
		if typeof(v) == "RBXScriptConnection" then pcall(function() v:Disconnect() end) end
	end
	-- Cleanup cursor tracker
	if G.cursorGui then pcall(function() G.cursorGui:Destroy() end); G.cursorGui = nil end
	-- Cleanup stats gui
	if G.statsGui then pcall(function() G.statsGui:Destroy() end); G.statsGui = nil end
	-- Aim cleanup
	Aim.Enabled = false
	if G.aimRemoveFov then G.aimRemoveFov() end
	-- Crosshair cleanup
	Crosshair.Enabled = false
	if G.crosshairGui then pcall(function() G.crosshairGui:Destroy() end); G.crosshairGui = nil end
	-- Cleanup new features
	if G.hitboxCache then
		for plr, adorn in pairs(G.hitboxCache) do
			pcall(function() adorn:Destroy() end)
		end
		G.hitboxCache = {}
	end
	G.nameSpoof = false
	G.antifling = false
	PlayerMods.FOVEnabled = false
	if G.fovDefault then
		pcall(function()
			if workspace.CurrentCamera then workspace.CurrentCamera.FieldOfView = G.fovDefault end
		end)
	end
	if G._tweenActive then pcall(function() G._tweenActive:Cancel() end); G._tweenActive = nil end
	-- Destroy GUI
	pcall(function() ScreenGui:Destroy() end)
	getgenv()[KEY] = nil
end)

--===========================================================================
-- ===================== TWEEN TELEPORT HELPER + SPEED (Movement) =====================
do
	setActive("Movement")
	G.tweenSpeed = G.tweenSpeed or 80
	G.tweenTeleportXYZ = function(x, y, z)
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		if G._tweenActive then pcall(function() G._tweenActive:Cancel() end); G._tweenActive = nil end
		local target = CFrame.new(x, y, z)
		local dist = (hrp.Position - target.Position).Magnitude
		local dur = math.clamp(dist / math.max(G.tweenSpeed, 1), 0.05, 60)
		G._tweenActive = TweenService:Create(hrp, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = target })
		G._tweenActive:Play()
	end
	createSlider("Tween Speed", 80, "Tween Speed", false, false, function(v)
		G.tweenSpeed = v
	end, 10, 500, nil)
end

--===========================================================================
-- ===================== MOVEMENT: CLICK TP =====================
do
	setActive("Movement")
	local ctpHeaderRec = createSubcategoryHeader("Click TP")

	-- состояние тумблера (единственная переменная, которую трогает колбэк)
	local clickTPEnabled = false

	local ctpRec = createCheckbox("Click TP", false, "Click TP Movement", nil, function(on)
		clickTPEnabled = on
	end)

	-- Поднимаем Click TP в самый верх вкладки Movement.
	-- LayoutOrder < 0 сортируется раньше всех остальных строк (у них >= 1).
	ctpHeaderRec.frame.LayoutOrder = -2
	ctpRec.frame.LayoutOrder = -1

	-- ОДНО соединение на всё время жизни скрипта. Лежит в G -> очистится при KILL/рестарте.
	G.clickTP = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if G.shutdown then return end
		if not clickTPEnabled then return end
		if gameProcessed then return end                       -- клик по меню/UI игнорируем
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		-- луч от камеры через текущую позицию курсора
		local cam = workspace.CurrentCamera
		if not cam then return end
		local mouseLoc = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)

		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { char }               -- не попадать в самого себя
		local result = workspace:Raycast(ray.Origin, ray.Direction * 5000, rp)

		if result then
			-- тот же механизм, что и в "Teleport to:" — прямая установка CFrame.
			-- +3 по Y, чтобы не провалиться в поверхность.
			hrp.CFrame = CFrame.new(result.Position + Vector3.new(0, 3, 0))
		end
	end)
end

-- ===================== PLAYER: CUSTOM FOV =====================
do
	setActive("Player")
	createSubcategoryHeader("Camera")
	G.fovDefault = G.fovDefault or (workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView) or 70
	PlayerMods.FOVValue = PlayerMods.FOVValue or 70
	PlayerMods.FOVEnabled = false

	local fovRow
	fovRow = createCheckbox("Custom FOV", false, "Custom FOV", nil, function(on)
		PlayerMods.FOVEnabled = on
		setChildrenEnabled(fovRow, on)
		local cam = workspace.CurrentCamera
		if cam then
			if on then cam.FieldOfView = PlayerMods.FOVValue
			else cam.FieldOfView = G.fovDefault end
		end
	end)

	createSlider("FOV Value", 70, "FOV Value", false, false, function(v)
		PlayerMods.FOVValue = v
		if PlayerMods.FOVEnabled then
			local cam = workspace.CurrentCamera
			if cam then cam.FieldOfView = v end
		end
	end, 1, 180, fovRow)

	G.fovLoop = RunService.RenderStepped:Connect(function()
		if G.shutdown then return end
		if not PlayerMods.FOVEnabled then return end
		local cam = workspace.CurrentCamera
		if cam and cam.FieldOfView ~= PlayerMods.FOVValue then
			cam.FieldOfView = PlayerMods.FOVValue
		end
	end)
end

-- ===================== ETC: NAME SPOOF =====================
do
	setActive("Etc")
	createSubcategoryHeader("Name Spoof")

	local orig = {}
	local function restoreAll()
		for obj, t in pairs(orig) do pcall(function() obj.Text = t end) end
		orig = {}
	end
	local function setText(obj, newText)
		if orig[obj] == nil then orig[obj] = obj.Text end
		pcall(function() obj.Text = newText end)
	end
	local function isStatValue(txt)
		if not txt or txt == "" or txt == "-" then return false end
		local cleaned = txt:gsub("[,%s]", "")
		local numericPart = cleaned:gsub("[kKmMbByY%+%%]+$", "")
		return tonumber(numericPart) ~= nil
	end
	local function findPlayerList()
		local pl = CoreGui:FindFirstChild("PlayerList")
		if pl then return pl end
		local rg = CoreGui:FindFirstChild("RobloxGui")
		if rg then return rg:FindFirstChild("PlayerList") end
		return nil
	end
	local function maskRowStats(anchorLabel)
		local candidates = { anchorLabel.Parent }
		if anchorLabel.Parent then candidates[2] = anchorLabel.Parent.Parent end
		for _, container in ipairs(candidates) do
			if container then
				local texts = {}
				for _, sib in ipairs(container:GetDescendants()) do
					if sib:IsA("TextLabel") or sib:IsA("TextButton") then
						texts[#texts+1] = sib
					end
				end
				if #texts <= 12 then
					for _, sib in ipairs(texts) do
						if sib ~= anchorLabel and isStatValue(sib.Text) then
							setText(sib, "-")
						end
					end
				end
			end
		end
	end

	createCheckbox("Name Spoof (my name + stats)", false, "Name Spoof", nil, function(on)
		G.nameSpoof = on
		if on then
			task.spawn(function()
				while G.nameSpoof do
					if G.shutdown then G.nameSpoof = false; break end
					local myName = LocalPlayer.Name
					local myDisplay = LocalPlayer.DisplayName

					local char = LocalPlayer.Character
					if char then
						local head = char:FindFirstChild("Head")
						if head then
							for _, d in ipairs(head:GetDescendants()) do
								if d:IsA("TextLabel") or d:IsA("TextButton") then
									local t = d.Text
									if t == myName or t == myDisplay then setText(d, "---") end
								end
							end
						end
					end

					local pl = findPlayerList()
					if pl then
						for _, d in ipairs(pl:GetDescendants()) do
							if (d:IsA("TextLabel") or d:IsA("TextButton")) then
								local t = d.Text
								if t == myName or t == myDisplay then
									setText(d, "---")
									maskRowStats(d)
								end
							end
						end
					end

					local valid = {}
					for obj, t in pairs(orig) do
						if obj and obj.Parent then valid[obj] = t end
					end
					orig = valid

					task.wait(0.5)
				end
				restoreAll()
			end)
		else
			G.nameSpoof = false
			restoreAll()
		end
	end)
end

-- ===================== ETC: FLING DEFENSE =====================
do
	setActive("Etc")
	createSubcategoryHeader("Protection")

	createCheckbox("Fling Defense", false, "Fling Defense", nil, function(on)
		G.antifling = on
		if on then
			if not G.antiflingLoop then
				G.antiflingLoop = RunService.Stepped:Connect(function()
					if G.shutdown or not G.antifling then return end
					local char = LocalPlayer.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					if not hrp then return end
					local av = hrp.AssemblyAngularVelocity
					if av.Magnitude > 30 then
						hrp.AssemblyAngularVelocity = Vector3.zero
					end
					local lv = hrp.AssemblyLinearVelocity
					local horiz = Vector3.new(lv.X, 0, lv.Z)
					if horiz.Magnitude > 500 then
						hrp.AssemblyLinearVelocity = Vector3.new(0, lv.Y, 0)
					end
				end)
			end
		else
			if G.antiflingLoop then pcall(function() G.antiflingLoop:Disconnect() end); G.antiflingLoop = nil end
		end
	end)
end

-- ===================== ETC: COPY SERVER JOIN =====================
do
	setActive("Etc")
	createSubcategoryHeader("Server Join")

	local _, joinScriptBtn = createButton("Copy Join Script", "Copy Join Script", function() end)
	joinScriptBtn.MouseButton1Click:Connect(function()
		local s = string.format(
			'game:GetService("TeleportService"):TeleportToPlaceInstance(%d, "%s", game:GetService("Players").LocalPlayer)',
			game.PlaceId, game.JobId
		)
		pcall(function() setclipboard(s) end)
		local prev = joinScriptBtn.Text
		joinScriptBtn.Text = "Copied!"
		task.delay(0.8, function() if joinScriptBtn.Parent then joinScriptBtn.Text = prev end end)
	end)

	local _, joinLinkBtn = createButton("Copy Browser Join Link", "Copy Browser Join Link", function() end)
	joinLinkBtn.MouseButton1Click:Connect(function()
		local link = string.format(
			"https://www.roblox.com/games/start?placeId=%d&gameInstanceId=%s",
			game.PlaceId, game.JobId
		)
		pcall(function() setclipboard(link) end)
		local prev = joinLinkBtn.Text
		joinLinkBtn.Text = "Copied!"
		task.delay(0.8, function() if joinLinkBtn.Parent then joinLinkBtn.Text = prev end end)
	end)
end

-- ===================== DEBUG TAB =====================
do
	setActive("Debug")
	local Stats = getService("Stats")
	local debugTabDef = getTabDef("Debug")

	task.spawn(function()
		local reg = "Unknown"
		pcall(function()
			local LS = getService("LocalizationService")
			reg = LS:GetCountryRegionForPlayerAsync(LocalPlayer)
		end)
		G.serverRegion = reg
	end)

	-- ---------- HITBOX SHOWER (with Hue/Shade/Transparency like ESP) ----------
	createSubcategoryHeader("Hitbox Shower")

	local Hitbox = { Enabled = false, Hue = 0.5, Shade = 0.5, Transparency = 0.5, Color = Color3.fromRGB(95, 205, 228) }
	local function updateHitboxColor()
		local h = Hitbox.Hue
		local s, v = 1, 1
		if Hitbox.Shade < 0.5 then v = Hitbox.Shade * 2; s = 1
		else v = 1; s = 1 - ((Hitbox.Shade - 0.5) * 2) end
		Hitbox.Color = Color3.fromHSV(h, s, v)
	end

	G.hitboxCache = G.hitboxCache or {}

	local hbRow
	hbRow = createCheckbox("Show Hitboxes", false, "Show Hitboxes", nil, function(on)
		Hitbox.Enabled = on
		setChildrenEnabled(hbRow, on)
		if not on then
			for plr, adorn in pairs(G.hitboxCache) do
				pcall(function() adorn:Destroy() end)
				G.hitboxCache[plr] = nil
			end
		end
	end)

	local hbShadeGradient
	local _, _hg = createSlider("Shade", 0.5, "Shade Hitbox", false, true, function(v)
		Hitbox.Shade = v; updateHitboxColor()
		if hbShadeGradient then
			hbShadeGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 0, 0)),
				ColorSequenceKeypoint.new(0.5, Color3.fromHSV(Hitbox.Hue, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
			})
		end
	end, nil, nil, hbRow)
	hbShadeGradient = _hg

	createSlider("Hue", 0.5, "Hue Hitbox", true, false, function(v)
		Hitbox.Hue = v; updateHitboxColor()
		if hbShadeGradient then
			hbShadeGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 0, 0)),
				ColorSequenceKeypoint.new(0.5, Color3.fromHSV(Hitbox.Hue, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
			})
		end
	end, nil, nil, hbRow)

	createSlider("Transparency", 0.5, "Transparency Hitbox", false, false, function(v)
		Hitbox.Transparency = v
	end, nil, nil, hbRow)

	G.hitboxLoop = RunService.RenderStepped:Connect(function(dt)
		if G.shutdown then return end
		if not Hitbox.Enabled then return end
		G._hbAccum = (G._hbAccum or 0) + dt
		if G._hbAccum < (1/30) then return end
		G._hbAccum = 0
		local seen = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer then
				local char = plr.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hrp then
					seen[plr] = true
					local adorn = G.hitboxCache[plr]
					if not adorn then
						adorn = Instance.new("BoxHandleAdornment")
						adorn.Name = rnd()
						adorn.AlwaysOnTop = true
						adorn.ZIndex = 4
						hiddenParent(adorn)
						G.hitboxCache[plr] = adorn
					end
					adorn.Adornee = hrp
					if adorn.Size ~= hrp.Size then adorn.Size = hrp.Size end
					if adorn.Color3 ~= Hitbox.Color then adorn.Color3 = Hitbox.Color end
					adorn.Transparency = Hitbox.Transparency
					adorn.Visible = true
				end
			end
		end
		for plr, adorn in pairs(G.hitboxCache) do
			if not seen[plr] then
				pcall(function() adorn:Destroy() end)
				G.hitboxCache[plr] = nil
			end
		end
	end)

	-- ---------- HELPER: info row ----------
	local function makeInfoRow(defaultText, searchKey)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, -10, 0, 24)
		frame.BackgroundTransparency = 1
		registerRow(frame, searchKey or defaultText, nil)
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = defaultText
		lbl.TextColor3 = THEME.TEXT_MAIN
		lbl.Font = Enum.Font.Gotham
		lbl.TextSize = 13
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = frame
		return lbl
	end

	-- ---------- SYSTEM (Memory / CPU / GPU) ----------
	createSubcategoryHeader("System")
	local memLbl = makeInfoRow("Memory: ... MB", "Memory usage")
	local cpuLbl = makeInfoRow("CPU (frame): ... ms", "CPU usage")
	local gpuLbl = makeInfoRow("GPU (render): ... ms", "GPU usage")

	-- ---------- NETWORK ----------
	createSubcategoryHeader("Network")
	local netLbl = makeInfoRow("Net In: ...  |  Out: ...", "Network stats in out")

	-- ---------- SERVER ----------
	createSubcategoryHeader("Server")
	local uptimeLbl = makeInfoRow("Server uptime: --:--:--", "Server live time uptime")
	local pingLbl = makeInfoRow("Ping: ... ms  |  Region: ...", "Server ping region")

	G.debugFrameConn = RunService.RenderStepped:Connect(function(dt)
		if G.shutdown then return end
		if not (debugTabDef and debugTabDef.container.Visible and menuIsOpen) then return end
		G._dbgFrames = (G._dbgFrames or 0) + 1
		G._dbgDt = (G._dbgDt or 0) + dt
	end)

	G.debugThread = task.spawn(function()
		local wasVisible = false
		while true do
			if G.shutdown then return end
			task.wait(0.1)
			if G.shutdown then return end

			local visible = debugTabDef and debugTabDef.container.Visible and menuIsOpen
			if not visible then
				wasVisible = false
			else
				wasVisible = true

				local memMb = 0
				pcall(function() memMb = Stats:GetTotalMemoryUsageMb() end)
				memLbl.Text = string.format("Memory: %d MB", math.floor(memMb))

				local frames = G._dbgFrames or 0
				local elapsed = G._dbgDt or 0
				G._dbgFrames = 0; G._dbgDt = 0
				local fps = (elapsed > 0) and math.floor(frames / elapsed) or 0
				local frameMs = (fps > 0) and (1000 / fps) or 0
				cpuLbl.Text = string.format("CPU (frame): %.1f ms  |  FPS: %d", frameMs, fps)
				gpuLbl.Text = string.format("GPU (render): %.1f ms", frameMs)

				local inK, outK = 0, 0
				pcall(function() inK = Stats.DataReceiveKbps end)
				pcall(function() outK = Stats.DataSendKbps end)
				netLbl.Text = string.format("Net In: %.1f kb/s  |  Out: %.1f kb/s", inK, outK)

				local up = 0
				pcall(function() up = workspace.DistributedGameTime end)
				local hh = math.floor(up / 3600)
				local mm = math.floor((up % 3600) / 60)
				local ss = math.floor(up % 60)
				uptimeLbl.Text = string.format("Server uptime: %02d:%02d:%02d", hh, mm, ss)

				local ping = 0
				pcall(function() ping = math.floor(LocalPlayer:GetNetworkPing() * 1000) end)
				pingLbl.Text = "Ping: " .. ping .. " ms  |  Region: " .. (G.serverRegion or "...")
			end
		end
	end)
end

--===========================================================================
-- FINAL SCROLL INITIALIZATION
--===========================================================================
task.defer(function()
	for _, def in ipairs(TAB_DEFS) do
		refreshScroll(def)
	end
	refreshScroll(ACTIVE_TAB)
end)
