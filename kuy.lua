-- Team ESP (multi-map version)
-- Works on maps with teams, maps without teams, custom characters, respawns, and games with many players.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Teams = game:GetService("Teams")
local RunService = game:GetService("RunService")

local lp = Players.LocalPlayer
if not lp then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	lp = Players.LocalPlayer
end

local env = (getgenv and getgenv()) or _G
if env.TeamESPUnload then pcall(env.TeamESPUnload) end   -- remove the previous copy when re-running

local settings = {
	Enabled = true, ShowAlly = true, ShowEnemy = true, AllyEnemy = false, Transparency = 0.5,
	-- Aimbot
	Aimbot = false, AimEnemies = true, AimHead = true, ShowFov = true,
	AimWall = true,     -- true = lock through walls, false = only lock targets with a clear line of sight
	AimFov = 150,       -- FOV circle radius in pixels (0 - 500)
	AimStrength = 50,   -- lock strength % (0 = no pull, 100 = instant lock)
}
local FALLBACK_COLOR = Color3.fromRGB(255, 70, 70)  -- color used when the map has no teams
local MAX_HIGHLIGHTS = 30                           -- Roblox renders at most ~31 Highlights; extra players use boxes

local alive = true
local conns = {}
local function connect(sig, fn)
	local c = sig:Connect(fn)
	table.insert(conns, c)
	return c
end

-- ===== Safe parent (works in executors and in plain Studio scripts) =====
local function getGuiParent()
	local ok, r = pcall(function() return gethui and gethui() end)
	if ok and r then return r end

	local okCore, core = pcall(function() return game:GetService("CoreGui") end)
	if okCore and core then
		local probe = Instance.new("Folder")
		local okSet = pcall(function() probe.Parent = core end)
		local writable = okSet and probe.Parent == core
		pcall(function() probe:Destroy() end)
		if writable then return core end
	end

	return lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui", 10)
end

local guiParent = getGuiParent()

-- Folder that holds every ESP object (so maps that clear character children can't delete them)
local container = Instance.new("Folder")
container.Name = "TeamESPObjects"
pcall(function() container.Parent = guiParent end)

-- ===== ESP =====
local esp = {}   -- [player] = { obj = Instance, kind = "hl" | "box", char = Model }

local function hasTeams()
	local ok, n = pcall(function() return #Teams:GetTeams() end)
	return ok and n > 0
end

-- Distinct color per team: use the real TeamColor, but when two teams share the same
-- (or a washed-out) color, give each team its own color from a palette so they can be told apart.
local PALETTE = {
	Color3.fromRGB(255, 70, 70),   -- red
	Color3.fromRGB(70, 140, 255),  -- blue
	Color3.fromRGB(70, 220, 90),   -- green
	Color3.fromRGB(255, 200, 40),  -- yellow
	Color3.fromRGB(190, 90, 255),  -- purple
	Color3.fromRGB(255, 140, 40),  -- orange
	Color3.fromRGB(60, 220, 220),  -- cyan
	Color3.fromRGB(255, 100, 190), -- pink
}
local NEUTRAL_COLOR = Color3.fromRGB(200, 200, 200)   -- players with no team on maps that have teams
local ALLY_COLOR = Color3.fromRGB(70, 220, 90)
local ENEMY_COLOR = Color3.fromRGB(255, 70, 70)

local teamColors = {}   -- [Team] = Color3

local function colorKey(c)
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function rebuildTeamColors()
	local list = {}
	local ok = pcall(function() list = Teams:GetTeams() end)
	if not ok then return end
	table.sort(list, function(a, b) return a.Name < b.Name end)

	local used, result = {}, {}
	-- pass 1: real colors that are unique and not washed out
	for _, t in ipairs(list) do
		local c = t.TeamColor.Color
		local h, sat = Color3.toHSV(c)
		local key = colorKey(c)
		if sat >= 0.25 and not used[key] then
			used[key] = true
			result[t] = c
		end
	end
	-- pass 2: duplicates / gray teams get the next free palette color
	local pi = 1
	for _, t in ipairs(list) do
		if not result[t] then
			local c
			while pi <= #PALETTE do
				local cand = PALETTE[pi]
				pi = pi + 1
				if not used[colorKey(cand)] then c = cand break end
			end
			c = c or PALETTE[((#list - 1) % #PALETTE) + 1]
			used[colorKey(c)] = true
			result[t] = c
		end
	end
	teamColors = result
end


-- ===== Team detection for maps like "Defusal" (CT vs T) =====
-- Tries, in order: Roblox Team -> Attribute -> Value object -> leaderstats -> parent folder of the character.
local TEAM_KEYS = { "Team", "TeamName", "Side", "Faction", "Squad", "Group" }

-- Known names get fixed, easy-to-separate colors (Counter-Terrorists blue / Terrorists orange)
local CANON = {
	ct = "CT", counter = "CT", counterterrorist = "CT", counterterrorists = "CT", swat = "CT", police = "CT",
	t = "T", terrorist = "T", terrorists = "T", attackers = "T",
}
local CANON_COLOR = {
	CT = Color3.fromRGB(70, 140, 255),
	T = Color3.fromRGB(255, 140, 40),
}
local dynColors = {}   -- [key] = Color3 for teams we have not seen named before

local function canonical(name)
	local k = string.lower(tostring(name)):gsub("[%s%-%_]", "")
	return CANON[k] or tostring(name)
end

local function valueToName(v)
	if v == nil then return nil end
	if typeof(v) == "Instance" then return v.Name end
	if typeof(v) == "BrickColor" then return v.Name end
	if typeof(v) == "Color3" then return nil end
	local str = tostring(v)
	if str == "" then return nil end
	return str
end

-- Returns: key (string or nil), method (string), Team object (only for Roblox teams)
local function resolveTeam(plr)
	if plr.Team then return canonical(plr.Team.Name), "Team", plr.Team end

	local char = plr.Character
	for _, holder in ipairs({ plr, char }) do
		if holder then
			for _, k in ipairs(TEAM_KEYS) do
				local ok, a = pcall(function() return holder:GetAttribute(k) end)
				local name = ok and valueToName(a)
				if name then return canonical(name), "Attribute " .. k, nil end
			end
			for _, k in ipairs(TEAM_KEYS) do
				local obj = holder:FindFirstChild(k)
				if obj and obj:IsA("ValueBase") then
					local name = valueToName(obj.Value)
					if name then return canonical(name), "Value " .. k, nil end
				end
			end
		end
	end

	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		for _, k in ipairs(TEAM_KEYS) do
			local obj = ls:FindFirstChild(k)
			if obj and obj:IsA("ValueBase") then
				local name = valueToName(obj.Value)
				if name then return canonical(name), "leaderstats " .. k, nil end
			end
		end
	end

	-- Character grouped inside a folder per team (e.g. workspace.CT / workspace.Terrorists)
	if char and char.Parent and char.Parent ~= workspace and (char.Parent:IsA("Folder") or char.Parent:IsA("Model")) then
		local pname = char.Parent.Name
		if CANON[string.lower(pname):gsub("[%s%-%_]", "")] then
			return canonical(pname), "Folder " .. pname, nil
		end
	end
	return nil, "none", nil
end

local function colorForKey(key)
	if CANON_COLOR[key] then return CANON_COLOR[key] end
	if not dynColors[key] then
		local used = {}
		for _, c in pairs(CANON_COLOR) do used[colorKey(c)] = true end
		for _, c in pairs(dynColors) do used[colorKey(c)] = true end
		local pick
		for _, cand in ipairs(PALETTE) do
			if not used[colorKey(cand)] then pick = cand break end
		end
		dynColors[key] = pick or PALETTE[1]
	end
	return dynColors[key]
end

-- ===== Team cache =====
-- Looking up a team is the expensive part (many attribute / child lookups), so it is done once per
-- player and cached. Everything else (colors, filters, watchdog) only reads the cache.
local teamInfo = {}          -- [player] = { key, method, obj }
local teamsPresent = false   -- true when the map has Roblox teams or any player has a detected team

-- returns true when this player's team changed
local function recomputeTeam(plr)
	local key, method, obj = resolveTeam(plr)
	local old = teamInfo[plr]
	teamInfo[plr] = { key = key, method = method, obj = obj }
	return (not old) or old.key ~= key or old.obj ~= obj
end

-- returns the list of players whose team changed
local function recomputeAllTeams()
	local changed, anyKey = {}, false
	for _, p in ipairs(Players:GetPlayers()) do
		if recomputeTeam(p) then changed[#changed + 1] = p end
		if teamInfo[p].key then anyKey = true end
	end
	teamsPresent = hasTeams() or anyKey
	return changed
end

local function teamColorOf(plr)
	local info = teamInfo[plr]
	local key = info and info.key
	local teamObj = info and info.obj
	if settings.AllyEnemy then
		local mine = teamInfo[lp]
		local myKey = mine and mine.key
		if key and myKey and key == myKey then return ALLY_COLOR end
		return ENEMY_COLOR
	end
	if key then
		if CANON_COLOR[key] then return CANON_COLOR[key] end            -- Defusal: CT blue / T orange
		if teamObj then return teamColors[teamObj] or teamObj.TeamColor.Color end
		return colorForKey(key)
	end
	if teamsPresent then return NEUTRAL_COLOR end
	return FALLBACK_COLOR
end

-- Teammates / Enemy toggles. When our own team is unknown we cannot tell sides apart, so show everyone.
local function shouldShow(plr)
	if not settings.Enabled or plr == lp then return false end
	local mine = teamInfo[lp]
	local myKey = mine and mine.key
	if myKey then
		local info = teamInfo[plr]
		local same = info ~= nil and info.key == myKey
		if same and not settings.ShowAlly then return false end
		if (not same) and not settings.ShowEnemy then return false end
	end
	return true
end

local function getRoot(char)
	return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildWhichIsA("BasePart")
end

local hlCount = 0   -- number of Highlights currently alive (cheaper than counting every time)

local function destroyEsp(plr)
	local e = esp[plr]
	if e then
		if e.kind == "hl" then hlCount = hlCount - 1 end
		pcall(function() e.obj:Destroy() end)
		esp[plr] = nil
	end
end

-- only touches the object when the color / transparency really changed (no needless re-render)
local function paint(e, color)
	if e.color == color and e.transp == settings.Transparency then return end
	e.color = color
	e.transp = settings.Transparency
	pcall(function()
		if e.kind == "hl" then
			e.obj.FillColor = color
			e.obj.FillTransparency = settings.Transparency
		else
			e.obj.Color3 = color
			e.obj.Transparency = settings.Transparency
		end
	end)
end

-- slider: repaint existing ESP only (no team lookups)
local function paintAll()
	for _, e in pairs(esp) do
		if e.color then paint(e, e.color) end
	end
end

-- is this ESP object still attached to the player's current character?
local function espValid(e, char)
	local ad = e.obj.Adornee
	return e.obj.Parent ~= nil and e.char == char and ad ~= nil and (ad == char or ad:IsDescendantOf(char))
end

local function applyEsp(plr)
	local char = plr.Character
	if not (char and char.Parent and shouldShow(plr)) then
		destroyEsp(plr)
		return
	end
	local root = getRoot(char)
	if not root then
		destroyEsp(plr)
		return
	end

	local color = teamColorOf(plr)
	local e = esp[plr]
	if e and espValid(e, char) then   -- still valid: only update the look (and only if it changed)
		paint(e, color)
		return
	end

	destroyEsp(plr)
	local kind, obj = "hl", nil
	if hlCount < MAX_HIGHLIGHTS then
		obj = Instance.new("Highlight")
		obj.OutlineColor = Color3.new(1, 1, 1)
		obj.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		obj.Adornee = char
	else
		kind = "box"
		obj = Instance.new("BoxHandleAdornment")
		obj.Size = Vector3.new(4, 6, 2)
		obj.AlwaysOnTop = true
		obj.ZIndex = 5
		obj.Adornee = root
	end
	obj.Name = "TeamESP"

	local okParent = pcall(function() obj.Parent = container end)
	if not (okParent and obj.Parent) then
		pcall(function() obj.Parent = char end)     -- fallback: inside the character
	end
	if not obj.Parent then return end

	if kind == "hl" then hlCount = hlCount + 1 end
	local entry = { obj = obj, kind = kind, char = char }
	esp[plr] = entry
	paint(entry, color)
end

local function refreshAll()
	for _, p in ipairs(Players:GetPlayers()) do
		applyEsp(p)
	end
end

local function clearAll()
	for plr in pairs(esp) do
		destroyEsp(plr)
	end
end

local function onTeamChanged(plr)
	recomputeTeam(plr)
	if plr == lp then refreshAll() else applyEsp(plr) end
end

local function track(plr)
	local function onChar(char)
		task.spawn(function()
			char:WaitForChild("HumanoidRootPart", 5)   -- some maps spawn characters slowly
			if alive then
				recomputeTeam(plr)                      -- team may depend on the character (attributes / folder)
				applyEsp(plr)
			end
		end)
	end
	connect(plr.CharacterAdded, onChar)
	connect(plr.CharacterRemoving, function() destroyEsp(plr) end)
	connect(plr:GetPropertyChangedSignal("Team"), function() onTeamChanged(plr) end)
	connect(plr:GetPropertyChangedSignal("TeamColor"), function() onTeamChanged(plr) end)
	for _, k in ipairs(TEAM_KEYS) do                   -- instant reaction when a map sets a team attribute
		connect(plr:GetAttributeChangedSignal(k), function() onTeamChanged(plr) end)
	end
	if plr.Character then onChar(plr.Character) end
end

recomputeAllTeams()
for _, p in ipairs(Players:GetPlayers()) do track(p) end
connect(Players.PlayerAdded, track)
connect(Players.PlayerRemoving, function(p)
	destroyEsp(p)
	teamInfo[p] = nil
end)

-- Team list changes (maps that create/remove teams during the round)
local legendRefresh = function() end
local function onTeamsChanged()
	rebuildTeamColors()
	recomputeAllTeams()
	refreshAll()
	legendRefresh()
end
connect(Teams.ChildAdded, function(t)
	pcall(function() connect(t:GetPropertyChangedSignal("TeamColor"), onTeamsChanged) end)
	onTeamsChanged()
end)
connect(Teams.ChildRemoved, onTeamsChanged)
for _, t in ipairs(Teams:GetTeams()) do
	pcall(function() connect(t:GetPropertyChangedSignal("TeamColor"), onTeamsChanged) end)
end
rebuildTeamColors()

-- Light watchdog (every 2s, no team lookups): only restores ESP that vanished
-- (removed by a map script, character replaced without events, ...) so it stays visible all the time.
task.spawn(function()
	while alive do
		task.wait(2)
		if not alive then break end
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= lp then
				local char = p.Character
				local e = esp[p]
				if e then
					if not (char and espValid(e, char)) then pcall(applyEsp, p) end
				elseif char and settings.Enabled then
					pcall(applyEsp, p)      -- should be visible but is missing
				end
			end
		end
	end
end)

-- Team lookup loop (the expensive part): once every 3s for everyone, only changed players are re-applied
task.spawn(function()
	local lastPresent = teamsPresent
	while alive do
		task.wait(3)
		if not alive then break end
		local ok, changed = pcall(recomputeAllTeams)
		if ok and changed then
			local lpChanged = false
			for _, p in ipairs(changed) do
				if p == lp then lpChanged = true end
			end
			if lpChanged or teamsPresent ~= lastPresent then
				refreshAll()
			else
				for _, p in ipairs(changed) do pcall(applyEsp, p) end
			end
			lastPresent = teamsPresent
			if #changed > 0 then legendRefresh() end
		end
	end
end)

-- ===== UI =====
local old = guiParent and guiParent:FindFirstChild("TeamESPMenu")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "TeamESPMenu"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = guiParent

local function corner(o, r) local c = Instance.new("UICorner", o) c.CornerRadius = UDim.new(0, r) end

local ACCENT = Color3.fromRGB(88, 101, 242)
local OFF = Color3.fromRGB(60, 60, 70)
local PANEL = Color3.fromRGB(35, 35, 42)

local main = Instance.new("Frame", gui)
main.Size = UDim2.fromOffset(260, 410)
main.Position = UDim2.new(0.5, -130, 0.5, -205)
main.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
main.BorderSizePixel = 0
corner(main, 10)

local top = Instance.new("Frame", main)
top.Size = UDim2.new(1, 0, 0, 32)
top.BackgroundColor3 = PANEL
top.BorderSizePixel = 0
corner(top, 10)

local title = Instance.new("TextLabel", top)
title.Size = UDim2.new(1, -48, 1, 0)
title.Position = UDim2.fromOffset(12, 0)
title.BackgroundTransparency = 1
title.Text = "Team ESP / Aimbot"
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.new(1, 1, 1)
title.TextXAlignment = Enum.TextXAlignment.Left

local closeBtn = Instance.new("TextButton", top)
closeBtn.Size = UDim2.fromOffset(24, 24)
closeBtn.Position = UDim2.new(1, -30, 0.5, -12)
closeBtn.BackgroundColor3 = OFF
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.TextColor3 = Color3.new(1, 1, 1)
corner(closeBtn, 8)

-- Tabs: ESP / Aimbot (each tab is its own page)
local tabBar = Instance.new("Frame", main)
tabBar.Size = UDim2.new(1, -20, 0, 26)
tabBar.Position = UDim2.fromOffset(10, 36)
tabBar.BackgroundTransparency = 1

local function makePage()
	local page = Instance.new("Frame", main)
	page.Size = UDim2.new(1, -20, 1, -72)
	page.Position = UDim2.fromOffset(10, 66)
	page.BackgroundTransparency = 1
	Instance.new("UIListLayout", page).Padding = UDim.new(0, 5)
	return page
end
local espContent = makePage()
local aimContent = makePage()
local content = espContent   -- default page for the add* helpers below

local tabBtns = {}
local function selectTab(name)
	espContent.Visible = (name == "ESP")
	aimContent.Visible = (name == "Aimbot")
	for n, b in pairs(tabBtns) do b.BackgroundColor3 = (n == name) and ACCENT or PANEL end
end
local function addTab(name, xScale, xOffset)
	local b = Instance.new("TextButton", tabBar)
	b.Size = UDim2.new(0.5, -2, 1, 0)
	b.Position = UDim2.new(xScale, xOffset, 0, 0)
	b.BackgroundColor3 = PANEL
	b.Text = name
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = Color3.new(1, 1, 1)
	corner(b, 8)
	b.MouseButton1Click:Connect(function() selectTab(name) end)
	tabBtns[name] = b
end
addTab("ESP", 0, 0)
addTab("Aimbot", 0.5, 2)
selectTab("ESP")

-- Floating open/close button
local fab = Instance.new("TextButton", gui)
fab.Size = UDim2.fromOffset(42, 42)
fab.Position = UDim2.new(0, 10, 0.5, -21)
fab.BackgroundColor3 = ACCENT
fab.Text = "ESP"
fab.Font = Enum.Font.GothamBold
fab.TextSize = 12
fab.TextColor3 = Color3.new(1, 1, 1)
corner(fab, 21)

local function setMenu(v) main.Visible = v end
fab.MouseButton1Click:Connect(function() setMenu(not main.Visible) end)
closeBtn.MouseButton1Click:Connect(function() setMenu(false) end)
connect(UIS.InputBegan, function(i, gp)
	if not gp and i.KeyCode == Enum.KeyCode.RightShift then setMenu(not main.Visible) end
end)

-- Drag the window
do
	local dragging, startPos, startInput
	top.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, startPos, startInput = true, main.Position, i.Position
		end
	end)
	connect(UIS.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - startInput
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	connect(UIS.InputEnded, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
end

local function addToggle(text, key, parent, onChange)
	local row = Instance.new("TextButton", parent or content)
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundColor3 = PANEL
	row.AutoButtonColor = false
	row.Text = ""
	corner(row, 8)

	local lbl = Instance.new("TextLabel", row)
	lbl.Size = UDim2.new(1, -56, 1, 0)
	lbl.Position = UDim2.fromOffset(10, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 13
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextXAlignment = Enum.TextXAlignment.Left

	local sw = Instance.new("Frame", row)
	sw.Size = UDim2.fromOffset(34, 18)
	sw.Position = UDim2.new(1, -44, 0.5, -9)
	corner(sw, 9)
	local knob = Instance.new("Frame", sw)
	knob.Size = UDim2.fromOffset(14, 14)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	corner(knob, 7)

	local function render()
		local on = settings[key]
		sw.BackgroundColor3 = on and ACCENT or OFF
		knob.Position = on and UDim2.fromOffset(18, 2) or UDim2.fromOffset(2, 2)
	end
	render()

	row.MouseButton1Click:Connect(function()
		settings[key] = not settings[key]
		render()
		if onChange then
			onChange()
		else
			refreshAll()
			legendRefresh()
		end
	end)
end

local function addSlider(text, key, min, max, parent, fmt, onChange)
	local row = Instance.new("Frame", parent or content)
	row.Size = UDim2.new(1, 0, 0, 46)
	row.BackgroundColor3 = PANEL
	corner(row, 8)

	local lbl = Instance.new("TextLabel", row)
	lbl.Size = UDim2.new(1, -20, 0, 20)
	lbl.Position = UDim2.fromOffset(10, 3)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 13
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextXAlignment = Enum.TextXAlignment.Left

	local bar = Instance.new("TextButton", row)
	bar.Size = UDim2.new(1, -20, 0, 7)
	bar.Position = UDim2.new(0, 10, 0, 31)
	bar.BackgroundColor3 = OFF
	bar.AutoButtonColor = false
	bar.Text = ""
	corner(bar, 4)
	local fill = Instance.new("Frame", bar)
	fill.BackgroundColor3 = ACCENT
	fill.BorderSizePixel = 0
	corner(fill, 4)

	local function render(rel)
		fill.Size = UDim2.fromScale(rel, 1)
		lbl.Text = string.format("%s: " .. (fmt or "%.2f"), text, settings[key])
	end
	local lastPaint = 0
	local function set(x)
		local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		local v = min + (max - min) * rel
		if fmt == "%d" then v = math.floor(v + 0.5) end
		settings[key] = v
		render(rel)
		local now = os.clock()
		if now - lastPaint > 0.06 then    -- throttled: repaint existing ESP only, no team lookups
			lastPaint = now
			;(onChange or paintAll)()
		end
	end
	render((settings[key] - min) / (max - min))

	local dragging = false
	bar.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			set(i.Position.X)
		end
	end)
	connect(UIS.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			set(i.Position.X)
		end
	end)
	connect(UIS.InputEnded, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			if dragging then (onChange or paintAll)() end   -- apply the final value
			dragging = false
		end
	end)
end

local function addButton(text, callback)
	local b = Instance.new("TextButton", content)
	b.Size = UDim2.new(1, 0, 0, 30)
	b.BackgroundColor3 = Color3.fromRGB(150, 50, 60)
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = Color3.new(1, 1, 1)
	corner(b, 8)
	b.MouseButton1Click:Connect(callback)
end

-- ===== Aimbot =====
-- Locks the camera onto the closest valid target that is inside the FOV circle (circle = screen center).
--   FOV size    0 - 500 px   (0 = never locks anyone)
--   Lock strength 0 - 100 %  (0 = no pull, 100 = instant lock; lower = smoother, frame-rate independent)
local function noop() end
local AIM_BIND = "TeamESPAim"

local fovGui = Instance.new("ScreenGui")
fovGui.Name = "TeamESPAimFov"
fovGui.ResetOnSpawn = false
fovGui.IgnoreGuiInset = true      -- same space as WorldToViewportPoint, so the circle is exactly at the screen center
fovGui.DisplayOrder = 998
fovGui.Parent = guiParent

local fovCircle = Instance.new("Frame", fovGui)
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.Position = UDim2.fromScale(0.5, 0.5)
fovCircle.BackgroundTransparency = 1
fovCircle.BorderSizePixel = 0
fovCircle.Visible = false
corner(fovCircle, 1000)
local fovStroke = Instance.new("UIStroke", fovCircle)
fovStroke.Thickness = 1.5
fovStroke.Color = Color3.new(1, 1, 1)
fovStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local function aimPartOf(char)
	if settings.AimHead then
		return char:FindFirstChild("Head") or getRoot(char)
	end
	return getRoot(char)
end

-- ===== Team check for the aimbot =====
-- Uses a LIVE lookup (not the 3s cache) so a teammate is never targeted right after a respawn / team switch.
local myTeamCache, myTeamAt = { key = nil, obj = nil }, 0
local function myTeam()
	local now = os.clock()
	if now - myTeamAt > 0.25 then
		myTeamAt = now
		local ok, key, _, obj = pcall(resolveTeam, lp)
		myTeamCache = { key = ok and key or nil, obj = ok and obj or nil }
	end
	return myTeamCache
end

local function isTeammate(plr)
	local me = myTeam()
	local ok, key, _, obj = pcall(resolveTeam, plr)
	if not ok then key, obj = nil, nil end
	if me.obj and obj then return me.obj == obj end        -- same Roblox Team
	if me.key and key then return me.key == key end        -- same detected side (CT / T / attribute / value ...)
	-- last resort: identical TeamColor while both players really are on a team
	local okC, same = pcall(function()
		return (not lp.Neutral) and (not plr.Neutral) and lp.TeamColor == plr.TeamColor
	end)
	return okC and same == true
end

-- true when nothing solid is between the camera and the part (walls only, characters are ignored)
local function hasLineOfSight(cam, part, excl)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excl
	params.RespectCanCollide = true
	local origin = cam.CFrame.Position
	return workspace:Raycast(origin, part.Position - origin, params) == nil
end

-- closest valid player to the screen center, inside the circle
--   Team check ON  -> teammates are never picked
--   Through walls OFF -> only targets with a clear line of sight are picked
local function pickTarget(cam, center, radius)
	local cands = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= lp then
			local char = p.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				local part = aimPartOf(char)
				if part then
					local sp = cam:WorldToViewportPoint(part.Position)
					if sp.Z > 0 then
						local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
						if d <= radius then cands[#cands + 1] = { p = p, part = part, d = d } end
					end
				end
			end
		end
	end
	if #cands == 0 then return nil end
	table.sort(cands, function(a, b) return a.d < b.d end)

	local excl
	if not settings.AimWall then
		excl = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then excl[#excl + 1] = p.Character end
		end
	end

	for _, c in ipairs(cands) do
		local blocked = settings.AimEnemies and isTeammate(c.p)
		if not blocked and (settings.AimWall or hasLineOfSight(cam, c.part, excl)) then
			return c.part
		end
	end
	return nil
end

local lastFov, lastLocked = nil, nil
local function aimStep(dt)
	local cam = workspace.CurrentCamera
	if not cam then return end

	-- FOV circle (only touched when something changed)
	local radius = settings.AimFov
	local show = settings.Aimbot and settings.ShowFov and radius > 0
	if fovCircle.Visible ~= show then fovCircle.Visible = show end
	if show and lastFov ~= radius then
		lastFov = radius
		fovCircle.Size = UDim2.fromOffset(radius * 2, radius * 2)
	end

	local part = nil
	if settings.Aimbot and radius > 0 and settings.AimStrength > 0 then
		local vp = cam.ViewportSize
		part = pickTarget(cam, Vector2.new(vp.X / 2, vp.Y / 2), radius)
	end

	local locked = part ~= nil
	if locked ~= lastLocked then                 -- circle turns green while a target is locked
		lastLocked = locked
		fovStroke.Color = locked and Color3.fromRGB(70, 220, 90) or Color3.new(1, 1, 1)
	end
	if not part then return end

	local pos = cam.CFrame.Position
	if (part.Position - pos).Magnitude < 0.5 then return end
	local strength = settings.AimStrength / 100
	local alpha = 1 - (1 - strength) ^ (math.min(dt, 0.1) * 60)   -- 100% = 1 (instant), 0% = 0
	cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(pos, part.Position), alpha)
end

pcall(function() RunService:UnbindFromRenderStep(AIM_BIND) end)
RunService:BindToRenderStep(AIM_BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
	if alive then pcall(aimStep, dt) end
end)

-- ===== Unload =====
local function unload()
	if not alive then return end
	alive = false
	settings.Enabled = false
	clearAll()
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	conns = {}
	pcall(function() container:Destroy() end)
	pcall(function() RunService:UnbindFromRenderStep(AIM_BIND) end)
	pcall(function() fovGui:Destroy() end)
	pcall(function() gui:Destroy() end)
	if env.TeamESPUnload == unload then env.TeamESPUnload = nil end
end
env.TeamESPUnload = unload

-- Legend: each team with its ESP color and player count
local function addLegend()
	local box = Instance.new("ScrollingFrame", content)
	box.Size = UDim2.new(1, 0, 0, 76)
	box.BackgroundColor3 = PANEL
	box.BorderSizePixel = 0
	box.ScrollBarThickness = 4
	box.CanvasSize = UDim2.new(0, 0, 0, 0)
	box.AutomaticCanvasSize = Enum.AutomaticSize.Y
	corner(box, 8)
	local layout = Instance.new("UIListLayout", box)
	layout.Padding = UDim.new(0, 2)
	local pad = Instance.new("UIPadding", box)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 6)

	local function row(color, text)
		local r = Instance.new("Frame", box)
		r.Size = UDim2.new(1, -14, 0, 18)
		r.BackgroundTransparency = 1
		local sw = Instance.new("Frame", r)
		sw.Size = UDim2.fromOffset(12, 12)
		sw.Position = UDim2.fromOffset(0, 3)
		sw.BackgroundColor3 = color
		sw.BorderSizePixel = 0
		corner(sw, 4)
		local l = Instance.new("TextLabel", r)
		l.Size = UDim2.new(1, -20, 1, 0)
		l.Position = UDim2.fromOffset(20, 0)
		l.BackgroundTransparency = 1
		l.Text = text
		l.Font = Enum.Font.Gotham
		l.TextSize = 12
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextXAlignment = Enum.TextXAlignment.Left
	end

	local legendSig = nil
	legendRefresh = function()
		-- compute from the team cache (cheap) and rebuild the rows only when something changed
		local counts, methods, order, none = {}, {}, {}, 0
		if not settings.AllyEnemy then
			for _, p in ipairs(Players:GetPlayers()) do
				local info = teamInfo[p]
				local key = info and info.key
				if key then
					if not counts[key] then counts[key] = 0; methods[key] = info.method; order[#order + 1] = key end
					counts[key] = counts[key] + 1
				else
					none = none + 1
				end
			end
			table.sort(order)
		end
		local parts = { settings.AllyEnemy and "AE" or "TEAMS" }
		for _, key in ipairs(order) do parts[#parts + 1] = key .. ":" .. counts[key] .. ":" .. methods[key] end
		parts[#parts + 1] = "none:" .. none
		local sig = table.concat(parts, "|")
		if sig == legendSig then return end
		legendSig = sig

		for _, c in ipairs(box:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		if settings.AllyEnemy then
			row(ALLY_COLOR, "Ally (your team)")
			row(ENEMY_COLOR, "Enemy")
			return
		end
		if #order == 0 then
			row(FALLBACK_COLOR, "No teams detected")
			return
		end
		for _, key in ipairs(order) do
			local color = CANON_COLOR[key] or colorForKey(key)
			for _, t in ipairs(Teams:GetTeams()) do
				if canonical(t.Name) == key and not CANON_COLOR[key] then color = teamColors[t] or t.TeamColor.Color end
			end
			row(color, string.format("%s (%d)  [%s]", key, counts[key], methods[key]))
		end
		if none > 0 then row(NEUTRAL_COLOR, string.format("No team (%d)", none)) end
	end
	legendRefresh()
end

addToggle("ESP On", "Enabled")
addToggle("Teammates ESP", "ShowAlly")
addToggle("Enemy ESP (opposite side)", "ShowEnemy")
addToggle("Ally / Enemy colors", "AllyEnemy")
addSlider("Transparency", "Transparency", 0, 1)
addLegend()

-- Debug: dumps where each player's team could be read from (paste it back to improve detection)
addButton("Copy Team Debug Info", function()
	local lines = {}
	for i, p in ipairs(Players:GetPlayers()) do
		if i > 8 then break end
		local key, method = resolveTeam(p)
		local bits = { p.Name .. " -> " .. tostring(key) .. " [" .. method .. "]" }
		bits[#bits + 1] = "  Team=" .. tostring(p.Team and p.Team.Name)
		local okA, attrs = pcall(function() return p:GetAttributes() end)
		if okA then for k, v in pairs(attrs) do bits[#bits + 1] = "  plrAttr " .. k .. "=" .. tostring(v) end end
		if p.Character then
			local okC, cattrs = pcall(function() return p.Character:GetAttributes() end)
			if okC then for k, v in pairs(cattrs) do bits[#bits + 1] = "  charAttr " .. k .. "=" .. tostring(v) end end
			bits[#bits + 1] = "  charParent=" .. tostring(p.Character.Parent and p.Character.Parent.Name)
		end
		for _, c in ipairs(p:GetChildren()) do
			if c:IsA("ValueBase") then bits[#bits + 1] = "  plrValue " .. c.Name .. "=" .. tostring(c.Value) end
		end
		local ls = p:FindFirstChild("leaderstats")
		if ls then
			for _, c in ipairs(ls:GetChildren()) do bits[#bits + 1] = "  leaderstats " .. c.Name .. "=" .. tostring(c.Value) end
		end
		lines[#lines + 1] = table.concat(bits, "\n")
	end
	local text = table.concat(lines, "\n")
	if setclipboard then pcall(setclipboard, text) end
	print("[TeamESP debug]\n" .. text)
end)
addButton("Unload Script", unload)

-- Aimbot page
addToggle("Aimbot On", "Aimbot", aimContent, noop)
addToggle("Team check (skip teammates)", "AimEnemies", aimContent, noop)
addToggle("Lock through walls", "AimWall", aimContent, noop)
addToggle("Aim at head", "AimHead", aimContent, noop)
addToggle("Show FOV circle", "ShowFov", aimContent, noop)
addSlider("FOV circle size", "AimFov", 0, 500, aimContent, "%d", noop)
addSlider("Lock strength %", "AimStrength", 0, 100, aimContent, "%d", noop)

-- keep the legend counts fresh when players change team
connect(Players.PlayerAdded, function() legendRefresh() end)
connect(Players.PlayerRemoving, function() task.defer(legendRefresh) end)
refreshAll()
