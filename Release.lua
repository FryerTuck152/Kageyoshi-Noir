--===========================================================================
--  NEON PINK MENU  ::  Release (skeleton + all functions from beta3.lua + scroll fix)
--===========================================================================

--== PROTECTED BACKEND =======================================================
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
local LocalPlayer      = Players.LocalPlayer   -- DO NOT clone (crashes require)

-- Random name for GUI (avoid leaking a fixed name)
local function rnd(len)
	local c = "abcdefghijklmnopqrstuvwxyz0123456789"
	local t = {}
	for i = 1, (len or math.random(9, 14)) do
		local n = math.random(1, #c); t[i] = c:sub(n, n)
	end
	return table.concat(t)
end

-- Per-run randomized identifiers for runtime instances (movers / gyros /
-- attachments / plate / overlay-GUI). Fresh each launch.
local RN = {
	FlyMover  = rnd(), FlyAtt = rnd(), FlyGyro = rnd(),
	GoldMover = rnd(), GoldAtt = rnd(), GoldGyro = rnd(),
	Gui = rnd(), CursorGui = rnd(), StatsGui = rnd(), Plate = rnd(),
}

-- Single store for cleaning up the previous run
local KEY = "\0__np_" .. tostring(game.PlaceId % 997)
getgenv()[KEY] = getgenv()[KEY] or {}
local G = getgenv()[KEY]
for k, v in pairs(G) do
	if typeof(v) == "RBXScriptConnection" then pcall(function() v:Disconnect() end); G[k] = nil
	elseif typeof(v) == "Instance" then pcall(function() v:Destroy() end); G[k] = nil end
end
G.shutdown = false

-- Protected parent
local function hiddenParent(obj)
	pcall(function() if syn and syn.protect_gui then syn.protect_gui(obj) end end)
	obj.Parent = CoreGui
end

-- Cleanup stale ESP cache from previous runs
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
local espCache = G.espCache
local _SIZE_OFFSET = Vector3.new(0.05, 0.05, 0.05)

-- Reset state flags
G.gold = false; G.goldClaim = false; G.autoFort = false
G.slapple = false; G.spoofMask = false; G.antirag = false

-- State tables
local ESP = { Enabled = false, ShowTeam = true, Mode = "Cubes", ChamsTransparency = 0.5, Hue = 0.5, Shade = 0.5, Color = Color3.fromRGB(95, 205, 228), Radius = 10000 }
local PlayerMods = { SpeedEnabled = false, SpeedValue = 16, JumpEnabled = false, JumpValue = 50, FlyEnabled = false, FlySpeed = 50, NoclipEnabled = false, WallWalkEnabled = false, InfJumpEnabled = false, AntiKnockback = false }

local Aim = {
	Enabled = false,
	ActivationKey = Enum.KeyCode.E,     -- можно сменить на менее конфликтную клавишу
	ActivationInput = nil,              -- если задан UserInputType (напр. ПКМ) — используется он
	TeamCheck = false,
	FOV_Radius = 250,
	ShowFOV = true,
	AimPart = "Head",                 -- Head / HumanoidRootPart / UpperTorso
	Smoothing = 5,                    -- 1 = мгновенно, больше = плавнее
	MaxDistance = 500,
	WallCheck = true,
	PredictionEnabled = false,
	PredictionStrength = 0.12,
}

local Crosshair = {
	Enabled = false,
	Left = true, Right = true, Top = true, Bottom = true,  -- по дефолту все палочки вкл
	Length = 10, Width = 2, Gap = 4,
	DotEnabled = false,               -- точка по дефолту ВЫКЛ
	DotThickness = 2,
	Color = Color3.fromRGB(255, 75, 150),  -- THEME.NEON
}

-- Cached character parts for noclip loop
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

-----------------------------------
-- THEME
-----------------------------------
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

-----------------------------------
-- MOUSE FIX (адаптивный, отдаёт управление игре при закрытии)
-----------------------------------
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

-- Определить, находится ли игрок сейчас в режиме, где камера хочет залочить курсор
-- (first person или включён shift lock). Используется, чтобы НЕ мешать игре при закрытом меню.
local function gameWantsLock()
	-- shift lock включён в настройках
	if isShiftLockOptionEnabled() then return true end
	-- first person: расстояние от камеры до точки фокуса очень мало
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

-- Пока меню открыто: держим курсор свободным. Работает даже в "залипающих" играх (TC2),
-- т.к. каждый кадр возвращаем Default, если игра снова залочила (но не мешаем ПКМ-повороту камеры).
G.openCursorLoop = RunService.RenderStepped:Connect(function()
	if G.shutdown or not menuIsOpen then return end
	if rmbHeld then return end   -- пока крутят камеру ПКМ — не вмешиваемся
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	if not UserInputService.MouseIconEnabled then
		UserInputService.MouseIconEnabled = true
	end
end)

-- Когда меню ЗАКРЫТО: НЕ навязываем режим. Отдаём управление игре.
-- Единственное вмешательство — аварийное: курсор завис в LockCenter, но игра его НЕ хочет
-- (не first-person, не shift-lock, не зажата ПКМ) → отпускаем.
G.closedCursorLoop = RunService.RenderStepped:Connect(function()
	if G.shutdown or menuIsOpen then return end
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then return end
	if rmbHeld or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end
	if gameWantsLock() then return end   -- игра легитимно хочет lock — не трогаем
	pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)
end)

-----------------------------------
-- SCREEN GUI
-----------------------------------
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

local TabList = Instance.new("Frame")
TabList.Size = UDim2.new(1, 0, 1, -50)
TabList.Position = UDim2.new(0, 0, 0, 10)
TabList.BackgroundTransparency = 1
TabList.Parent = SideBar
do
	local l = Instance.new("UIListLayout", TabList)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.Padding = UDim.new(0, 4)
end

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
local TAB_NAMES = { "ESP", "Player", "Aim", "Babft", "Movement", "Slap Battles", "Performance", "Integration", "Crosshair", "Etc" }

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
		b.Size = UDim2.new(0.31, 0, 1, 0)
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
	espRow = createCheckbox("Toggle ESP", false, "Toggle ESP", nil, function(on)
		ESP.Enabled = on
		setChildrenEnabled(espRow, on)
		if not on then
			for _, p in pairs(Players:GetPlayers()) do clearESP(p) end
		end
	end)

	createCheckbox("Show teammates", true, "Show teammates", espRow, function(on)
		ESP.ShowTeam = on
		if not on then
			for _, p in pairs(Players:GetPlayers()) do
				if p.Team == LocalPlayer.Team then clearESP(p) end
			end
		end
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
	local _, _g = createSlider("Shade", 0.5, "Shade ESP", false, true, function(v)
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

	createSlider("Hue", 0.5, "Hue ESP", true, false, function(v)
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

	-- Fly + Fly Speed / Noclip / WallWalk (sub-options)
	local flyRow
	flyRow = createCheckbox("Fly", false, "Fly", nil, function(on)
		PlayerMods.FlyEnabled = on
		setChildrenEnabled(flyRow, on)
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
	createCheckbox("Wall Walk", false, "Wall Walk", flyRow, function(on)
		PlayerMods.WallWalkEnabled = on
		if not on then _restoreCollision() end
	end)

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

	local function _setStatsMode(mode)
		if _statsConn then _statsConn:Disconnect(); _statsConn = nil end
		if _statsGui then _statsGui:Destroy(); _statsGui = nil; G.statsGui = nil end
		_statsMode = mode
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

	local function _updateStatsBtns()
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

	createButton("Kill Infinity Yield", "Kill Infinity Yield", function()
		if _G.IY_LOADED then _G.IY_LOADED = false end
		if getgenv().IY_LOADED then getgenv().IY_LOADED = false end
		for _, v in pairs(CoreGui:GetChildren()) do
			if v:IsA("ScreenGui") and v.Name ~= RN.Gui and not v.Name:match("Roblox") then
				pcall(function() v:Destroy() end)
			end
		end
	end)

	createSubcategoryHeader("Simple Spy")

	createButton("Simple Spy", "Launch Simple Spy", function()
		loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/78n/SimpleSpy/main/SimpleSpyBeta.lua"))()
	end)

	createButton("Terminate Simple Spy", "Terminate Simple Spy", function()
		local iyNames = {"Infinite Yield", "InfiniteYield", "IY"}
		local function isIY(name)
			for _, n in pairs(iyNames) do
				if name == n then return true end
			end
			return false
		end
		for _, v in pairs(CoreGui:GetChildren()) do
			if v:IsA("ScreenGui")
				and v.Name ~= RN.Gui
				and not v.Name:match("Roblox")
				and not isIY(v.Name)
			then
				pcall(function() v:Destroy() end)
			end
		end
		pcall(function()
			if getgenv().SS then getgenv().SS = nil end
			if getgenv().SimpleSpy then getgenv().SimpleSpy = nil end
			if _G.SimpleSpy then _G.SimpleSpy = nil end
			if _G.SS then _G.SS = nil end
			if getgenv().SimpleSpyActive then getgenv().SimpleSpyActive = false end
		end)
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

	createButton("Terminate Hydroxide", "Terminate Hydroxide", function()
		local protectedNames = {RN.Gui, "Infinite Yield", "InfiniteYield", "IY"}
		local spyNames = {"SimpleSpy", "SimpleSpyGui", "SSpy", "Simple Spy"}
		local function isProtected(name)
			if name:match("Roblox") then return true end
			for _, n in pairs(protectedNames) do
				if name == n then return true end
			end
			for _, n in pairs(spyNames) do
				if name == n then return true end
			end
			return false
		end
		for _, v in pairs(CoreGui:GetChildren()) do
			if v:IsA("ScreenGui") and not isProtected(v.Name) then
				pcall(function() v:Destroy() end)
			end
		end
		pcall(function()
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
	local c = player.Character
	if not c then return false end
	local h = c:FindFirstChildOfClass("Humanoid")
	if not h or h.Health <= 0 then return false end
	return c:FindFirstChild("HumanoidRootPart") ~= nil
end

local function aimIsTeammate(player)
	if not Aim.TeamCheck then return false end
	if LocalPlayer.Team == nil then return false end
	return player.Team == LocalPlayer.Team
end

local function aimIsVisible(targetPart)
	if not Aim.WallCheck then return true end
	local lc = LocalPlayer.Character
	if not lc then return true end
	local head = lc:FindFirstChild("Head")
	if not head then return true end
	local origin = head.Position
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
	local closest, closestDist = nil, Aim.FOV_Radius
	local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and not aimIsTeammate(player) and aimIsAlive(player) then
			local char = player.Character
			local part = char:FindFirstChild(Aim.AimPart)
			if part then
				local lc = LocalPlayer.Character
				local ok = true
				if lc and lc:FindFirstChild("HumanoidRootPart") then
					if (part.Position - lc.HumanoidRootPart.Position).Magnitude > Aim.MaxDistance then
						ok = false
					end
				end
				if ok then
					local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
					if onScreen then
						local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
						if d < closestDist and aimIsVisible(part) then
							closestDist = d
							closest = player
						end
					end
				end
			end
		end
	end
	return closest
end

local function aimAt(player)
	local char = player.Character
	if not char then return end
	local part = char:FindFirstChild(Aim.AimPart)
	if not part then return end
	local pos = part.Position
	if Aim.PredictionEnabled then
		local hrp = char:FindFirstChild("HumanoidRootPart")
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
	if not aimTarget then
		aimTarget = aimGetClosest()
	else
		local char = aimTarget.Character
		local part = char and char:FindFirstChild(Aim.AimPart)
		if not part then
			aimTarget = aimGetClosest()
		else
			local _, onScreen = Camera:WorldToViewportPoint(part.Position)
			if not onScreen then aimTarget = aimGetClosest() end
		end
	end
	if aimTarget then aimAt(aimTarget) end
end)

--===========================================================================
-- ESP RENDER LOOP
--===========================================================================
local _cachedPlayers = {}
local _playersLastUpdate = 0
G.espLoop = RunService.RenderStepped:Connect(function()
	if G.shutdown then return end
	if not ESP.Enabled then return end
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

		local char = player.Character
		local hum = char and char:FindFirstChild("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")

		if not char or not hum or hum.Health <= 0 or not hrp then
			clearESP(player); continue
		end

		local dist = (hrp.Position - Camera.CFrame.Position).Magnitude
		local inRange = (ESP.Radius >= 10000) or (dist <= ESP.Radius)

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
			continue
		end

		if ESP.Mode == "Cubes" then
			local activeParts = {}
			if not cache._cubes then cache._cubes = {} end
			local cubes = cache._cubes
			for _, part in pairs(char:GetChildren()) do
				if part:IsA("BasePart") and part.Transparency < 1 and part.Name ~= "HumanoidRootPart" then
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
					if cubes[id].Color3 ~= ESP.Color then
						cubes[id].Color3 = ESP.Color
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
			hl.FillColor = ESP.Color
			hl.OutlineColor = ESP.Color
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
				cache.Box.Color = ESP.Color
				cache.Box.Visible = true
			else
				cache.Box.Visible = false
			end
		end
	end
end)

G.espRemoveConn = Players.PlayerRemoving:Connect(clearESP)

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
	for _, p in pairs(Players:GetPlayers()) do clearESP(p) end
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
	-- Destroy GUI
	pcall(function() ScreenGui:Destroy() end)
	getgenv()[KEY] = nil
end)

--===========================================================================
-- FINAL SCROLL INITIALIZATION
--===========================================================================
task.defer(function()
	for _, def in ipairs(TAB_DEFS) do
		refreshScroll(def)
	end
	refreshScroll(ACTIVE_TAB)
end)
