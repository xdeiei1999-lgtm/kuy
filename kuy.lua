--[[
    NGO PORN HUB V1  (single file, everything included)
    UI: WindUI  (automatically falls back to a built-in UI if it fails to load)

    Features
      - Unified ESP (single switch): players by role + name/distance/weapon + dropped gun
      - Sheriff, 2 modes:  1) Normal shot (no wall in the way)
                         2) Wall shot (bullet teleports onto the murderer's hitbox)
      - Murderer: Kill All, teleport to each hitbox one by one
      - Murderer: Throw Knife (knife teleports to the hitbox of the player you aim at most closely)
      - Floating buttons: SHOOT / MODE / THROW (throw knife) / GRAB GUN (pick up dropped gun)
        Lock position, resize, reset position
      - FPS Boost (removes textures/clothes/effects; characters and floor turn gray)
]]

local env = (getgenv and getgenv()) or _G
if env.NGOPornHubUnload then pcall(env.NGOPornHubUnload) end

-- ============================================================
-- Services / basics
-- ============================================================
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UIS               = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")
local StarterGui        = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local LP                = Players.LocalPlayer

local Alive = true
local Conns = {}
local function Connect(signal, fn)
    local c = signal:Connect(fn)
    Conns[#Conns + 1] = c
    return c
end

local function RName()
    return "NGO_" .. tostring(math.random(100000, 999999))
end

local function SafeParent()
    local ok, parent = pcall(function()
        if gethui then return gethui() end
        return game:GetService("CoreGui")
    end)
    if ok and parent then return parent end
    return LP:WaitForChild("PlayerGui")
end

-- Sheriff shot modes
local MODE_1 = "Mode 1: Normal (no wall in the way)"
local MODE_2 = "Mode 2: Wall shot (bullet teleports onto hitbox)"

local S = {
    ESP = false,
    -- Sheriff
    ShootMode = MODE_1, AimPart = "Torso",
    ArgMode = "CFrame, CFrame",
    -- Floating buttons
    ShootBtn = false, ModeBtn = false, ThrowBtn = false, GunBtn = false, LockBtn = false, BtnSize = 140, ShootSize = 64,
    -- Murderer
    KillDelay = 250, KillRetries = 3, KillReturn = true,
    AutoKill = false,   -- auto kill while holding the knife (no teleport)
    FlingMurd = false, FlingSheriff = false, FlingAll = false,   -- Walkfling
    AimbotOn = false, AimbotPart = "Head", AimbotPower = 60,
    AimbotNeedGun = true,   -- Aimbot
    GunTpl = nil,     -- args the game really uses to shoot the gun (captured automatically)
}
local KnifeTpl = {}   -- args the game uses with Knife.Events.* (captured automatically)

local Folder = Instance.new("Folder")
Folder.Name = RName()
Folder.Parent = SafeParent()

local Gui = Instance.new("ScreenGui")
Gui.Name = RName()
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.Parent = SafeParent()

local WindRef, WindowObj = nil, nil
local function Notify(title, content)
    if WindRef then
        local ok = pcall(function()
            WindRef:Notify({ Title = title, Content = content, Duration = 3 })
        end)
        if ok then return end
    end
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = title, Text = content, Duration = 3 })
    end)
end

-- ============================================================
-- Role system (read from data the game sends, not guessed from the Backpack)
-- ============================================================
local RoleCache = {}
local RoleSource = "tools only"

local function NormRole(r)
    local l = string.lower(tostring(r))
    if l == "murderer" then return "Murderer" end
    if l == "sheriff" then return "Sheriff" end
    if l == "hero" then return "Hero" end
    if l == "innocent" then return "Innocent" end
    return "Unknown"
end

local function ParseRoles(data)
    local out, n = {}, 0
    if typeof(data) ~= "table" then return out, 0 end
    for k, v in pairs(data) do
        local name = nil
        if typeof(k) == "Instance" then name = k.Name
        elseif typeof(k) == "string" then name = k end
        if name and typeof(v) == "table" and typeof(v.Role) == "string" then
            out[name] = { Role = NormRole(v.Role), Dead = (v.Dead == true) or (v.Killed == true) }
            n = n + 1
        end
    end
    return out, n
end

local GetCur, GetPD
local pdConnected = false
local function ResolveRemotes()
    local R = ReplicatedStorage:FindFirstChild("Remotes")
    if not R then return end
    local G = R:FindFirstChild("Gameplay")
    local E = R:FindFirstChild("Extras")
    GetCur = G and G:FindFirstChild("GetCurrentPlayerData")
    GetPD = E and E:FindFirstChild("GetPlayerData")
    local ev = G and G:FindFirstChild("PlayerDataChanged")
    if ev and ev:IsA("RemoteEvent") and not pdConnected then
        pdConnected = true
        Connect(ev.OnClientEvent, function(data)
            local out, n = ParseRoles(data)
            if n > 0 then
                for k, v in pairs(out) do RoleCache[k] = v end
                RoleSource = "PlayerDataChanged"
            end
        end)
    end
end

local fetching = false
local function FetchRoles()
    if fetching then return end
    fetching = true
    task.spawn(function()
        for _, info in ipairs({ { GetCur, "GetCurrentPlayerData" }, { GetPD, "GetPlayerData" } }) do
            local remote, label = info[1], info[2]
            if remote and remote:IsA("RemoteFunction") then
                local ok, data = pcall(function() return remote:InvokeServer() end)
                if ok then
                    local out, n = ParseRoles(data)
                    if n > 0 then
                        RoleCache = out
                        RoleSource = label
                        break
                    end
                end
            end
        end
        fetching = false
    end)
end

task.spawn(function()
    while Alive do
        pcall(ResolveRemotes)
        FetchRoles()
        task.wait(3)
    end
end)

local function GetRole(plr)
    local c = RoleCache[plr.Name]
    if c then
        if c.Dead then return "Dead" end
        return c.Role
    end
    local char = plr.Character
    if char then
        if char:FindFirstChild("Knife") then return "Murderer" end
        if char:FindFirstChild("Gun") then return "Sheriff" end
    end
    return "Unknown"
end

local function IsAlive(plr)
    local char = plr.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function GetMurderer()
    local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local best, bestDist = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and GetRole(plr) == "Murderer" and IsAlive(plr) then
            local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local d = myHrp and (hrp.Position - myHrp.Position).Magnitude or 0
                if d < bestDist then best, bestDist = plr, d end
            end
        end
    end
    return best
end

-- ============================================================
-- Player ESP
-- ============================================================
local RoleColor = {
    Murderer = Color3.fromRGB(255, 50, 50),
    Sheriff  = Color3.fromRGB(60, 140, 255),
    Hero     = Color3.fromRGB(255, 220, 60),
    Innocent = Color3.fromRGB(70, 255, 120),
    Unknown  = Color3.fromRGB(220, 220, 220),
}
local RoleLabel = {
    Murderer = "[ MURDERER ]", Sheriff = "[ SHERIFF ]", Hero = "[ HERO ]",
    Innocent = "Innocent", Unknown = "?",
}

local KeyRole = { Murderer = true, Sheriff = true, Hero = true }   -- key roles: always prominent and clear

local ESPObjs = {}

local function DestroyESP(plr)
    local o = ESPObjs[plr]
    if o then
        pcall(function() o.hl:Destroy() end)
        pcall(function() o.bb:Destroy() end)
        ESPObjs[plr] = nil
    end
end

local function DestroyAllESP()
    for plr in pairs(ESPObjs) do DestroyESP(plr) end
end

local function EnsureESP(plr, char, head)
    local o = ESPObjs[plr]
    if o and (o.char ~= char or not o.hl.Parent) then
        DestroyESP(plr)
        o = nil
    end
    if not o then
        local hl = Instance.new("Highlight")
        hl.Name = RName()
        hl.Adornee = char
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillTransparency = 0.6
        hl.OutlineTransparency = 0
        hl.Parent = Folder

        local bb = Instance.new("BillboardGui")
        bb.Name = RName()
        bb.Adornee = head
        bb.AlwaysOnTop = true
        bb.Size = UDim2.fromOffset(190, 38)
        bb.StudsOffset = Vector3.new(0, 2.6, 0)
        bb.Parent = Folder

        -- Top line: role + held weapon
        local l1 = Instance.new("TextLabel")
        l1.BackgroundTransparency = 1
        l1.Size = UDim2.new(1, 0, 0, 20)
        l1.Font = Enum.Font.GothamBlack
        l1.TextSize = 14
        l1.TextStrokeTransparency = 0.25
        l1.Parent = bb

        -- Bottom line: name | distance
        local l2 = Instance.new("TextLabel")
        l2.BackgroundTransparency = 1
        l2.Position = UDim2.new(0, 0, 0, 20)
        l2.Size = UDim2.new(1, 0, 0, 16)
        l2.Font = Enum.Font.GothamMedium
        l2.TextSize = 12
        l2.TextColor3 = Color3.fromRGB(240, 240, 240)
        l2.TextStrokeTransparency = 0.4
        l2.Parent = bb

        o = { hl = hl, bb = bb, l1 = l1, l2 = l2, char = char, role = "", t1 = "", t2 = "", sz = 0 }
        ESPObjs[plr] = o
    end
    return o
end

local function HeldItem(char)
    local tool = char:FindFirstChildOfClass("Tool")
    if tool and (tool.Name == "Knife" or tool.Name == "Gun") then return tool.Name end
    return nil
end

local function UpdateESP()
    if not S.ESP then
        if next(ESPObjs) then DestroyAllESP() end
        return
    end
    local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local head = char and char:FindFirstChild("Head")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local role = GetRole(plr)
            local key = KeyRole[role] == true
            local dist = (myHrp and hrp) and (hrp.Position - myHrp.Position).Magnitude or 0
            if hrp and head and hum and hum.Health > 0 and role ~= "Dead" then
                local o = EnsureESP(plr, char, head)
                o.hl.Enabled = true
                o.bb.Enabled = true

                -- Set color only when the role changes (less work per cycle)
                if o.role ~= role then
                    o.role = role
                    local col = RoleColor[role] or RoleColor.Unknown
                    o.hl.FillColor = col
                    o.hl.OutlineColor = col
                    o.l1.TextColor3 = col
                    o.hl.FillTransparency = (role == "Murderer" and 0.4) or (key and 0.5) or 0.78
                end

                -- Regular players far away fade and shrink; key roles always stay clear
                local fade = key and 0 or math.clamp((dist - 250) / 1200, 0, 0.55)
                o.l1.TextTransparency = fade
                o.l2.TextTransparency = fade
                local sz = key and 15 or ((dist > 400) and 11 or 13)
                if o.sz ~= sz then
                    o.sz = sz
                    o.l1.TextSize = sz + 1
                    o.l2.TextSize = sz - 1
                end

                local t1 = RoleLabel[role] or "?"
                local item = HeldItem(char)
                if item then t1 = t1 .. "  (" .. item .. ")" end
                local t2 = plr.DisplayName
                if myHrp then t2 = t2 .. "  |  " .. string.format("%d m", dist) end
                if o.t1 ~= t1 then o.t1 = t1; o.l1.Text = t1 end
                if o.t2 ~= t2 then o.t2 = t2; o.l2.Text = t2 end
            else
                local o = ESPObjs[plr]
                if o then
                    o.hl.Enabled = false
                    o.bb.Enabled = false
                end
            end
        end
    end
end

task.spawn(function()
    while Alive do
        pcall(UpdateESP)
        task.wait(0.1)
    end
end)

Connect(Players.PlayerRemoving, function(plr)
    DestroyESP(plr)
    RoleCache[plr.Name] = nil
end)

-- ============================================================
-- Dropped gun (GunDrop): tracked at all times + ESP (toggleable) + used by the grab-gun button
-- ============================================================
local DropInsts = {}   -- [inst] = true
local DropObjs  = {}   -- [inst] = {hl, bb}  (only while ESP is on)

local function RemoveDropESP(inst)
    local o = DropObjs[inst]
    if o then
        pcall(function() o.hl:Destroy() end)
        pcall(function() o.bb:Destroy() end)
        DropObjs[inst] = nil
    end
end

local function AddDropESP(inst)
    if DropObjs[inst] or not inst.Parent then return end
    local adornee = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
    if not adornee then return end

    local hl = Instance.new("Highlight")
    hl.Name = RName()
    hl.Adornee = inst
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillColor = Color3.fromRGB(255, 200, 0)
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.3
    hl.Parent = Folder

    local bb = Instance.new("BillboardGui")
    bb.Name = RName()
    bb.Adornee = adornee
    bb.AlwaysOnTop = true
    bb.Size = UDim2.fromOffset(120, 36)
    bb.StudsOffset = Vector3.new(0, 2, 0)
    bb.Parent = Folder

    local tl = Instance.new("TextLabel")
    tl.BackgroundTransparency = 1
    tl.Size = UDim2.fromScale(1, 1)
    tl.Font = Enum.Font.GothamBold
    tl.TextSize = 14
    tl.Text = "GUN DROP"
    tl.TextColor3 = Color3.fromRGB(255, 220, 60)
    tl.TextStrokeTransparency = 0
    tl.Parent = bb

    DropObjs[inst] = { hl = hl, bb = bb, tl = tl, part = adornee }
end

local function ClearDropESP()
    for inst in pairs(DropObjs) do RemoveDropESP(inst) end
end

local function RegisterDrop(inst)
    if DropInsts[inst] then return end
    DropInsts[inst] = true
    inst.AncestryChanged:Connect(function(_, parent)
        if not parent then
            DropInsts[inst] = nil
            RemoveDropESP(inst)
        end
    end)
    if S.ESP then task.defer(AddDropESP, inst) end
end

local function ShowDropESP()
    for inst in pairs(DropInsts) do AddDropESP(inst) end
end

-- Update the distance on the GUN DROP tag
task.spawn(function()
    while Alive do
        local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if myHrp then
            for _, o in pairs(DropObjs) do
                if o.part and o.part.Parent and o.tl then
                    o.tl.Text = string.format("GUN DROP\n%d m", (o.part.Position - myHrp.Position).Magnitude)
                end
            end
        end
        task.wait(0.2)
    end
end)

Connect(Workspace.DescendantAdded, function(d)
    if d.Name == "GunDrop" then task.defer(RegisterDrop, d) end
end)

task.spawn(function()
    local list = Workspace:GetDescendants()
    for i, d in ipairs(list) do
        if not Alive then return end
        if d.Name == "GunDrop" then RegisterDrop(d) end
        if i % 3000 == 0 then task.wait() end
    end
end)

-- ============================================================
-- Sheriff: 2 modes
-- ============================================================
local function IsSpatial(v)
    local t = typeof(v)
    return t == "CFrame" or t == "Vector3"
end

-- Replace the destination position (the last position in args) with the target
-- If an origin is given and there are >= 2 positions, the first one becomes the bullet origin
local function Retarget(args, origin, target)
    local idx = {}
    for i = 1, args.n do
        if IsSpatial(args[i]) then idx[#idx + 1] = i end
    end
    if #idx == 0 then return nil end

    local last = idx[#idx]
    if typeof(args[last]) == "CFrame" then
        args[last] = CFrame.new(target)
    else
        args[last] = target
    end

    if origin and #idx >= 2 then
        local first = idx[1]
        if typeof(args[first]) == "CFrame" then
            if (origin - target).Magnitude > 0.05 then
                args[first] = CFrame.lookAt(origin, target)
            else
                args[first] = CFrame.new(origin)
            end
        else
            args[first] = origin
        end
    end
    return args
end

local function DefaultArgs(origin, target)
    if S.ArgMode == "Vector3 (target)" then
        return table.pack(target)
    elseif S.ArgMode == "Vector3 (origin, target)" then
        return table.pack(origin, target)
    end
    return table.pack(CFrame.lookAt(origin, target), CFrame.new(target))
end

local function BuildShotArgs(origin, target)
    if S.GunTpl then
        local copy = table.pack(unpack(S.GunTpl, 1, S.GunTpl.n))
        local r = Retarget(copy, origin, target)
        if r then return r end
    end
    return DefaultArgs(origin, target)
end

-- Measure the target's speed ourselves from real positions every frame (more accurate than other characters' AssemblyLinearVelocity)
local VelTrack = setmetatable({}, { __mode = "k" })   -- [plr] = { pos, vel }

Connect(RunService.Heartbeat, function(dt)
    if dt <= 0 then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local pos = hrp.Position
                local rec = VelTrack[plr]
                if rec then
                    local v = (pos - rec.pos) / dt
                    if v.Magnitude > 120 then v = Vector3.zero end   -- teleport / respawn
                    rec.vel = rec.vel:Lerp(v, 0.6)
                    rec.pos = pos
                else
                    VelTrack[plr] = { pos = pos, vel = Vector3.zero }
                end
            else
                VelTrack[plr] = nil
            end
        end
    end
end)

-- Network latency (seconds), used to compensate for the server-side target position being ahead of what we see
local function PingLead()
    local ok, ping = pcall(function() return LP:GetNetworkPing() end)
    if not ok or type(ping) ~= "number" then return 0 end
    return math.clamp(ping, 0, 0.25)
end

-- Returns how far the target will move in `lead` seconds (capped at maxDist so the aim doesn't leave the target)
-- Standing on the ground drops the Y axis / if teleported or flung, no compensation
local function PredictOffset(plr, char, lead, maxDist)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return Vector3.zero end
    local rec = VelTrack[plr]
    local v = rec and rec.vel or hrp.AssemblyLinearVelocity
    if v.Magnitude < 0.5 then v = hrp.AssemblyLinearVelocity end
    if v.Magnitude > 80 then return Vector3.zero end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.FloorMaterial ~= Enum.Material.Air then
        v = Vector3.new(v.X, 0, v.Z)
    end
    local off = v * lead
    if off.Magnitude > maxDist then off = off.Unit * maxDist end
    return off
end

-- Mode 1: check whether a wall/map object blocks us from the target (players don't count)
local function HasLineOfSight(fromPos, toPos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ex = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character then ex[#ex + 1] = plr.Character end
    end
    params.FilterDescendantsInstances = ex
    params.RespectCanCollide = true
    local result = Workspace:Raycast(fromPos, toPos - fromPos, params)
    return result == nil
end

-- Check whether a bullet from -> to would hit another player (not the murderer / not us)
-- Also covers the origin or aim point being inside another player
local ShotTry = 0   -- which shot of this press (used to rotate the aim point on a miss)

local function HitsOthers(fromPos, toPos, murdererChar)
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        local c = plr.Character
        if plr ~= LP and c and c ~= murdererChar then list[#list + 1] = c end
    end
    if #list == 0 then return false end

    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Include
    rp.FilterDescendantsInstances = list
    local dir = toPos - fromPos
    if dir.Magnitude > 0.01 then
        -- Spherecast radius 0.3 gives some margin around the bullet line (falls back to Raycast if unsupported)
        local done, hit = pcall(function() return Workspace:Spherecast(fromPos, 0.3, dir, rp) end)
        if not done then hit = Workspace:Raycast(fromPos, dir, rp) end
        if hit then return true end
    end

    local op = OverlapParams.new()
    op.FilterType = Enum.RaycastFilterType.Include
    op.FilterDescendantsInstances = list
    local okA, a = pcall(function() return Workspace:GetPartBoundsInRadius(fromPos, 0.8, op) end)
    if okA and #a > 0 then return true end
    local okB, b = pcall(function() return Workspace:GetPartBoundsInRadius(toPos, 0.5, op) end)
    if okB and #b > 0 then return true end
    return false
end

-- Mode 2: place the bullet origin only ~2 studs from the hitbox (nothing in between)
local function NearOrigin(myPos, targetPos)
    local dir = myPos - targetPos
    if dir.Magnitude < 3 then return myPos end
    return targetPos + dir.Unit * 1.5
end

-- Compute the shot: returns origin, point  (origin = nil means use the game's original origin)
--   Mode 1: try torso/head/lower body in order, pick the first point that is truly visible with no wall
--   Mode 2: aim at the hitbox center (ping compensation capped at 1 stud) and put the bullet origin on the hitbox (through walls)
--   If every point is blocked in mode 1, returns nil, nil, "blocked"
local function ComputeShot(target, myHrp)
    local char = target.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil, "nochar" end
    local head = char:FindFirstChild("Head")
    local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    local lower = char:FindFirstChild("LowerTorso")
    local ping = PingLead()

    if S.ShootMode == MODE_2 then
        -- Wall shot: aim at the hitbox center + ping compensation, capped at 1 stud so the point always stays inside the target
        local off2 = PredictOffset(target, char, ping + 0.05, 1.8)
        local pts = {}
        if S.AimPart == "Head" and head then pts[#pts + 1] = head.Position end
        pts[#pts + 1] = hrp.Position
        if torso then pts[#pts + 1] = torso.Position end
        if lower then pts[#pts + 1] = lower.Position end
        if head and S.AimPart ~= "Head" then pts[#pts + 1] = head.Position end

        -- If the previous shot missed, rotate the main aim point (center/torso/lower) so we don't repeat the same line
        local n = math.min(#pts, 3)
        local rot = ShotTry % n
        if rot > 0 then
            local r = {}
            for i = 1, n do r[i] = pts[(i - 1 + rot) % n + 1] end
            for i = n + 1, #pts do r[i] = pts[i] end
            pts = r
        end

        -- Bullet teleports onto the murderer's hitbox: try origins from very close outward in steps (0.5 -> 2.5 studs)
        -- in several directions around the aim point; pick the first set where the bullet line + origin + aim point touch no hitbox except the murderer's
        local cf = hrp.CFrame
        local dists = { 0.5, 1.0, 1.6, 2.5 }
        for _, base in ipairs(pts) do
            local p = base + off2
            local toMe = myHrp.Position - p
            local dirs = {}
            if toMe.Magnitude > 0.1 then dirs[#dirs + 1] = toMe.Unit end
            dirs[#dirs + 1] = Vector3.yAxis
            dirs[#dirs + 1] = cf.LookVector
            dirs[#dirs + 1] = -cf.LookVector
            dirs[#dirs + 1] = cf.RightVector
            dirs[#dirs + 1] = -cf.RightVector
            dirs[#dirs + 1] = (Vector3.yAxis + cf.LookVector).Unit
            dirs[#dirs + 1] = (Vector3.yAxis - cf.LookVector).Unit
            dirs[#dirs + 1] = -Vector3.yAxis
            for _, d in ipairs(dists) do
                for _, dir in ipairs(dirs) do
                    local o = p + dir * d
                    if not HitsOthers(o, p, char) then return o, p end
                end
            end
        end
        return nil, nil, "crowded"
    end

    -- Mode 1: try different body points, pick the first with no wall in the way (start with the part with the largest hitbox)
    local off = PredictOffset(target, char, ping + 0.06, 4)
    local cands = {}
    if S.AimPart == "Head" and head then cands[#cands + 1] = head.Position end
    cands[#cands + 1] = hrp.Position
    if torso then cands[#cands + 1] = torso.Position end
    if lower then cands[#cands + 1] = lower.Position end
    if head and S.AimPart ~= "Head" then cands[#cands + 1] = head.Position end

    local myHead = LP.Character and LP.Character:FindFirstChild("Head")
    local eye = myHead and myHead.Position or myHrp.Position
    for _, c in ipairs(cands) do
        local p = c + off
        if HasLineOfSight(eye, p) and not HitsOthers(eye, p, char) then return nil, p end
    end
    return nil, nil, "blocked"
end

local lastShot = 0

-- Recompute from the latest position, then fire 1 shot
local function FireShotOnce(shoot, target, myHrp)
    local origin, p, why = ComputeShot(target, myHrp)
    if not p then return false, why end
    lastShot = os.clock()
    local args = BuildShotArgs(origin or myHrp.Position, p)
    shoot:FireServer(unpack(args, 1, args.n))
    return true
end

local function ShootMurderer()
    if os.clock() - lastShot < 0.25 then return end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and myHrp and hum.Health > 0) then return end

    local target = GetMurderer()
    if not target then
        Notify("Cannot shoot", "Murderer not found (the round may not have started)")
        return
    end

    local gun = char:FindFirstChild("Gun")
    if not gun then
        local bp = LP:FindFirstChildOfClass("Backpack")
        local g = bp and bp:FindFirstChild("Gun")
        if g then
            hum:EquipTool(g)
            local t0 = os.clock()
            repeat
                task.wait()
                gun = char:FindFirstChild("Gun")
            until gun or os.clock() - t0 > 1
        end
    end
    if not gun then
        Notify("Cannot shoot", "You do not have a gun (must be Sheriff / Hero)")
        return
    end

    local shoot = gun:FindFirstChild("Shoot")
    if not (shoot and shoot:IsA("RemoteEvent")) then
        Notify("Cannot shoot", "'Shoot' remote not found in the gun")
        return
    end

    ShotTry = 0
    local ok, why = FireShotOnce(shoot, target, myHrp)
    if not ok then
        if why == "blocked" then
            Notify("Cannot shoot (Mode 1)", "A wall or another player blocks every part of the murderer. Switch to Mode 2 to shoot through walls")
        elseif why == "crowded" then
            Notify("Cannot shoot (Mode 2)", "Other players around the murderer make a murderer-only shot impossible. Try again")
        end
        return
    end

    -- Check the result: if not dead within 0.5s, shoot again from the latest position (up to 2 times, if the gun is still in hand)
    task.spawn(function()
        for _ = 1, 5 do
            task.wait(0.4)
            if not Alive then return end
            local c = target.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            if (not h) or h.Health <= 0 or GetRole(target) == "Dead" then
                Notify("Hit", "The murderer is dead")
                return
            end
            if _ == 5 then return end
            local ch = LP.Character
            local mh = ch and ch:FindFirstChild("HumanoidRootPart")
            local hm = ch and ch:FindFirstChildOfClass("Humanoid")
            local g = ch and ch:FindFirstChild("Gun")
            local sh = g and g:FindFirstChild("Shoot")
            if not (mh and hm and hm.Health > 0 and sh) then return end
            ShotTry = ShotTry + 1
            FireShotOnce(sh, target, mh)
        end
    end)
end

-- ============================================================
-- Teleport to pick up the dropped gun
-- ============================================================
local Grabbing = false

local function HasGun()
    local char = LP.Character
    if char and char:FindFirstChild("Gun") then return true end
    local bp = LP:FindFirstChildOfClass("Backpack")
    return bp ~= nil and bp:FindFirstChild("Gun") ~= nil
end

local function NearestDropPart(myPos)
    local best, bestD = nil, math.huge
    for inst in pairs(DropInsts) do
        if inst.Parent then
            local part = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
            if part then
                local d = (part.Position - myPos).Magnitude
                if d < bestD then best, bestD = part, d end
            end
        end
    end
    return best
end

local function GrabGun()
    if Grabbing then return end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and myHrp and hum.Health > 0) then return end
    if HasGun() then
        Notify("Grab gun", "You already have a gun")
        return
    end
    local part = NearestDropPart(myHrp.Position)
    if not part then
        Notify("Grab gun", "No dropped gun found (nobody has died yet, or the round has not started)")
        return
    end
    if not firetouchinterest then
        Notify("Cannot grab gun", "This executor does not support firetouchinterest (needed to send the hitbox to touch the gun)")
        return
    end

    Grabbing = true
    local t0 = os.clock()
    local done = false
    local links = {}

    -- Know immediately when the gun enters the backpack/character
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then
        links[#links + 1] = bp.ChildAdded:Connect(function(c) if c.Name == "Gun" then done = true end end)
    end
    links[#links + 1] = char.ChildAdded:Connect(function(c) if c.Name == "Gun" then done = true end end)

    local bodyParts = {}
    for _, d in ipairs(char:GetChildren()) do
        if d:IsA("BasePart") then bodyParts[#bodyParts + 1] = d end
    end

    -- Send the "hitbox" (character part) to touch the gun while the character stays in place
    local function touchAll()
        if firetouchinterest then
            for _, bpart in ipairs(bodyParts) do
                pcall(firetouchinterest, bpart, part, 0)
                pcall(firetouchinterest, bpart, part, 1)
            end
            pcall(firetouchinterest, part, myHrp, 0)
            pcall(firetouchinterest, part, myHrp, 1)
        end
        local prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt and fireproximityprompt then pcall(fireproximityprompt, prompt) end
        local cd = part:FindFirstChildWhichIsA("ClickDetector", true)
        if cd and fireclickdetector then pcall(fireclickdetector, cd) end
    end

    pcall(function()
        touchAll()   -- first frame
        local frame = 0
        while not done and Alive and os.clock() - t0 < 0.6 do
            RunService.Heartbeat:Wait()
            if done or HasGun() then break end
            if not (part and part.Parent) then
                part = NearestDropPart(myHrp.Position)
                if not part then break end
            end
            frame = frame + 1
            if frame % 2 == 0 then touchAll() end
        end
    end)

    local got = done or HasGun()
    for _, l in ipairs(links) do pcall(function() l:Disconnect() end) end
    Grabbing = false
    if got then
        Notify("Grab gun", string.format("Gun grabbed (%.2f s)", os.clock() - t0))
    else
        Notify("Grab gun", "Hitbox touched the gun but the server did not accept it (the game may check distance)")
    end
end

-- ============================================================
-- Murderer: Kill All, teleport to each hitbox
-- ============================================================
local KillRunning, KillCancel = false, false

local function HasKnife()
    local char = LP.Character
    if char and char:FindFirstChild("Knife") then return true end
    local bp = LP:FindFirstChildOfClass("Backpack")
    return bp ~= nil and bp:FindFirstChild("Knife") ~= nil
end

local function GetKnife(char, hum)
    local k = char:FindFirstChild("Knife")
    if k then return k end
    local bp = LP:FindFirstChildOfClass("Backpack")
    k = bp and bp:FindFirstChild("Knife")
    if k then
        hum:EquipTool(k)
        local t0 = os.clock()
        repeat
            task.wait()
            k = char:FindFirstChild("Knife")
        until k or os.clock() - t0 > 1
    end
    return char:FindFirstChild("Knife")
end

-- Redirect the args the game once used with the knife to point at the victim
local function RetargetKnife(args, vChar, vPart)
    for i = 1, args.n do
        local v = args[i]
        local t = typeof(v)
        if t == "Instance" then
            if v:IsA("BasePart") then
                args[i] = vPart
            elseif v:IsA("Model") then
                args[i] = vChar
            elseif v:IsA("Humanoid") then
                args[i] = vChar:FindFirstChildOfClass("Humanoid") or v
            end
        elseif t == "Vector3" then
            args[i] = vPart.Position
        elseif t == "CFrame" then
            args[i] = vPart.CFrame
        end
    end
    return args
end

local function FireKnife(ev, name, vChar, vPart)
    local remote = ev and ev:FindFirstChild(name)
    if not (remote and remote:IsA("RemoteEvent")) then return end
    local args
    local tpl = KnifeTpl[name]
    if tpl then
        args = RetargetKnife(table.pack(unpack(tpl, 1, tpl.n)), vChar, vPart)
    elseif name == "HandleTouched" then
        args = table.pack(vPart)
    else
        args = table.pack()
    end
    remote:FireServer(unpack(args, 1, args.n))
end

local function Victims(myPos)
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and IsAlive(plr) and GetRole(plr) ~= "Dead" then
            local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                list[#list + 1] = { plr = plr, d = (hrp.Position - myPos).Magnitude }
            end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    return list
end

local function KillAll(silent)
    if KillRunning then return end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and myHrp and hum.Health > 0) then return end
    if not HasKnife() then
        if not silent then Notify("Cannot kill", "You do not have a knife (must be Murderer)") end
        return
    end

    KillRunning, KillCancel = true, false
    local startCF = myHrp.CFrame
    local killed, total = 0, 0
    local knife = GetKnife(char, hum)

    if knife then
        local ev = knife:FindFirstChild("Events")
        local list = Victims(myHrp.Position)
        total = #list
        for _, v in ipairs(list) do
            if KillCancel or not Alive then break end
            for _ = 1, math.max(1, S.KillRetries) do
                if KillCancel or not Alive then break end
                local vChar = v.plr.Character
                local vHrp = vChar and vChar:FindFirstChild("HumanoidRootPart")
                local vHum = vChar and vChar:FindFirstChildOfClass("Humanoid")
                if not (vHrp and vHum and vHum.Health > 0) then break end
                if not (myHrp.Parent and hum.Health > 0) then break end

                -- Teleport behind the target's hitbox (2 studs away, facing it)
                local behind = (vHrp.CFrame * CFrame.new(0, 0, 2)).Position
                myHrp.CFrame = CFrame.lookAt(behind, vHrp.Position)
                myHrp.AssemblyLinearVelocity = Vector3.zero

                if not char:FindFirstChild("Knife") then knife = GetKnife(char, hum) end
                if knife then
                    ev = knife:FindFirstChild("Events") or ev
                    pcall(FireKnife, ev, "KnifeStabbed", vChar, vHrp)
                    pcall(FireKnife, ev, "HandleTouched", vChar, vHrp)
                    local handle = knife:FindFirstChild("Handle")
                    if firetouchinterest and handle then
                        pcall(function()
                            firetouchinterest(handle, vHrp, 0)
                            firetouchinterest(handle, vHrp, 1)
                        end)
                    end
                end
                task.wait(math.max(0.05, S.KillDelay / 1000))
            end
            local vc = v.plr.Character
            local vh = vc and vc:FindFirstChildOfClass("Humanoid")
            if (not vh) or vh.Health <= 0 then killed = killed + 1 end
        end
    end

    if S.KillReturn and myHrp.Parent then
        myHrp.CFrame = startCF
        myHrp.AssemblyLinearVelocity = Vector3.zero
    end
    KillRunning = false
    if not silent or killed > 0 then
        Notify("Kill All", string.format("Done: %d / %d", killed, total))
    end
end

-- Throw knife: pick the player closest to the camera line, then send the knife to the hitbox
local ThrowBusy = false
local ThrowLock = nil      -- locked target player (every knife goes to this player until they die/leave/unlock)
local ThrowFloat = nil

local function UpdateThrowText()
    if ThrowFloat then
        ThrowFloat.btn.Text = ThrowLock and ("THROW > " .. ThrowLock.Name) or "THROW KNIFE"
    end
end

local function SetThrowLock(plr)
    ThrowLock = plr
    UpdateThrowText()
end
local function PickThrowTarget(myPos)
    local cam = Workspace.CurrentCamera
    local look = cam and cam.CFrame.LookVector
    local best, bestScore = nil, -math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and IsAlive(plr) and GetRole(plr) ~= "Dead" then
            local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dir = hrp.Position - (cam and cam.CFrame.Position or myPos)
                local score = look and dir.Magnitude > 0 and look:Dot(dir.Unit) or -dir.Magnitude
                if score > bestScore then best, bestScore = plr, score end
            end
        end
    end
    return best
end

local function ThrowKnife()
    if ThrowBusy or KillRunning then return end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and myHrp and hum.Health > 0) then return end
    if not HasKnife() then
        Notify("Cannot throw knife", "You do not have a knife (must be Murderer)")
        return
    end
    ThrowBusy = true

    -- Target lock: if a locked target is still present and alive, keep them; otherwise pick a new one and lock
    if ThrowLock and not (ThrowLock.Parent and IsAlive(ThrowLock) and GetRole(ThrowLock) ~= "Dead") then
        SetThrowLock(nil)
    end
    if not ThrowLock then SetThrowLock(PickThrowTarget(myHrp.Position)) end
    local plr = ThrowLock
    local vChar = plr and plr.Character
    local vHrp = vChar and vChar:FindFirstChild("HumanoidRootPart")
    local knife = GetKnife(char, hum)
    if not (vHrp and knife) then
        Notify("Cannot throw knife", vHrp and "Cannot equip the knife" or "Target player not found")
        ThrowBusy = false
        return
    end

    local ev = knife:FindFirstChild("Events")
    local handle = knife:FindFirstChild("Handle")

    -- The game's knife-throw remote: Knife.Events.KnifeThrown (args: origin CFrame, target CFrame)
    local remote = ev and ev:FindFirstChild("KnifeThrown")
    if not (remote and remote:IsA("RemoteEvent")) then
        remote = nil
        for _, d in ipairs(knife:GetDescendants()) do
            if d:IsA("RemoteEvent") and string.find(string.lower(d.Name), "throw", 1, true) then
                remote = d
                break
            end
        end
    end
    if not remote then
        Notify("Cannot throw knife", "Knife throw remote (KnifeThrown) not found")
        ThrowBusy = false
        return
    end

    -- Collect the knife the game creates when thrown (projectile) to teleport it onto the target's hitbox (our character doesn't teleport)
    local projs = {}
    local pc = Workspace.DescendantAdded:Connect(function(d)
        pcall(function()
            if d:IsA("BasePart") and string.find(string.lower(d.Name), "knife", 1, true) then
                local m = d:FindFirstAncestorOfClass("Model")
                if not (m and Players:GetPlayerFromCharacter(m)) then projs[#projs + 1] = d end
            end
        end)
    end)

    -- Throw knife: the knife origin sits right on the target's hitbox (only ~1.5 studs away, nothing in between)
    -- The target is the hitbox center; our character stays where it is
    local function FireThrow()
        if not vHrp.Parent then return end
        local target = vHrp.Position
        local origin = (vHrp.CFrame * CFrame.new(0, 0.5, 1.5)).Position
        local tpl = KnifeTpl["KnifeThrown"] or KnifeTpl["ThrowRemote"] or KnifeTpl[remote.Name]
        local args
        if tpl then
            args = Retarget(table.pack(unpack(tpl, 1, tpl.n)), origin, target)
        end
        if not args then
            args = table.pack(CFrame.lookAt(origin, target), CFrame.new(target))
        end
        pcall(function() remote:FireServer(unpack(args, 1, args.n)) end)
    end
    FireThrow()

    -- Follow the target for a short time: pull the thrown knife onto the hitbox every step and touch the hitbox again
    local vHum = vChar:FindFirstChildOfClass("Humanoid")
    for step = 1, 10 do
        if not Alive or not vHrp.Parent then break end
        if vHum and vHum.Health <= 0 then break end
        for _, part in ipairs(projs) do
            if part.Parent then
                pcall(function()
                    part.CanCollide = false
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.CFrame = vHrp.CFrame
                end)
            end
        end
        if step == 5 then FireThrow() end
        if step % 3 == 1 then
            pcall(FireKnife, ev, "KnifeStabbed", vChar, vHrp)
            pcall(FireKnife, ev, "HandleTouched", vChar, vHrp)
        end
        if firetouchinterest and handle then
            pcall(function()
                firetouchinterest(handle, vHrp, 0)
                firetouchinterest(handle, vHrp, 1)
            end)
        end
        task.wait(0.07)
    end
    pc:Disconnect()

    if (not vHum) or vHum.Health <= 0 then
        Notify("Throw knife", "Hit " .. plr.Name)
        SetThrowLock(nil)
    else
        Notify("Throw knife", "Locked on " .. plr.Name .. " (press again to throw again)")
    end
    task.wait(0.1)
    ThrowBusy = false
end

-- ============================================================
-- Auto kill (toggle): whenever you hold the knife, everyone alive is attacked instantly
--   Our character stays in place, no teleport; stab/touch/throw commands are sent to each player's hitbox
--   You must be "holding the knife in hand" (the script will not equip it for you)
-- ============================================================
local AutoKillStats = { last = 0, count = 0 }

local function AutoKillStep()
    if KillRunning or ThrowBusy then return end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and myHrp and hum.Health > 0) then return end

    local knife = char:FindFirstChild("Knife")        -- must be held in hand
    if not (knife and knife:IsA("Tool")) then return end
    local ev = knife:FindFirstChild("Events")
    local handle = knife:FindFirstChild("Handle")
    local throwRemote = ev and ev:FindFirstChild("KnifeThrown")
    if not (ev or handle) then return end

    local n = 0
    for _, plr in ipairs(Players:GetPlayers()) do
        if not (S.AutoKill and Alive) then return end
        if plr ~= LP and IsAlive(plr) and GetRole(plr) ~= "Dead" then
            local vChar = plr.Character
            local vHrp = vChar and vChar:FindFirstChild("HumanoidRootPart")
            local vHum = vChar and vChar:FindFirstChildOfClass("Humanoid")
            if vHrp and vHum and vHum.Health > 0 then
                n = n + 1
                -- 1) Stab / touch through the knife's commands
                pcall(FireKnife, ev, "KnifeStabbed", vChar, vHrp)
                pcall(FireKnife, ev, "HandleTouched", vChar, vHrp)
                -- 2) Make the knife touch the target's hitbox directly
                if firetouchinterest and handle then
                    pcall(function()
                        firetouchinterest(handle, vHrp, 0)
                        firetouchinterest(handle, vHrp, 1)
                    end)
                end
                -- 3) Throw the knife with the origin right on the target's hitbox
                if throwRemote and throwRemote:IsA("RemoteEvent") then
                    pcall(function()
                        local target = vHrp.Position
                        local origin = (vHrp.CFrame * CFrame.new(0, 0.5, 1.5)).Position
                        local tpl = KnifeTpl["KnifeThrown"]
                        local args
                        if tpl then args = Retarget(table.pack(unpack(tpl, 1, tpl.n)), origin, target) end
                        if not args then args = table.pack(CFrame.lookAt(origin, target), CFrame.new(target)) end
                        throwRemote:FireServer(unpack(args, 1, args.n))
                    end)
                end
            end
        end
    end
    AutoKillStats.count = n
end

task.spawn(function()
    while Alive do
        if S.AutoKill then
            pcall(AutoKillStep)
            task.wait(0.25)
        else
            task.wait(0.3)
        end
    end
end)

-- ============================================================
-- Walkfling (separate toggles): Murderer / Sheriff / whole server
--   Teleport to kick each target one by one, charging through the target with massive force, then teleport back at the end of the round
--   Turning all switches off stops it immediately (our character gets teleported around while it runs)
-- ============================================================
local function FlingOn() return S.FlingMurd or S.FlingSheriff or S.FlingAll end

local function FlingTargets()
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and IsAlive(plr) then
            local role = GetRole(plr)
            if role ~= "Dead" and (S.FlingAll
                or (S.FlingMurd and role == "Murderer")
                or (S.FlingSheriff and (role == "Sheriff" or role == "Hero"))) then
                local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                if hrp then list[#list + 1] = { plr = plr, hrp = hrp } end
            end
        end
    end
    return list
end

local FlingSt = { char = nil, saved = {} }

-- Make ourselves as heavy as possible so the impact force transfers to the target the most
local function FlingRestore()
    for d, props in pairs(FlingSt.saved) do
        pcall(function() d.CustomPhysicalProperties = props end)
    end
    FlingSt.saved = {}
    FlingSt.char = nil
    if FlingSt.size and FlingSt.hrp then
        pcall(function() FlingSt.hrp.Size = FlingSt.size end)
    end
    FlingSt.size, FlingSt.hrp = nil, nil
end

local function FlingHeavy(char)
    FlingRestore()
    FlingSt.char = char
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            FlingSt.saved[d] = d.CustomPhysicalProperties
            pcall(function() d.CustomPhysicalProperties = PhysicalProperties.new(math.huge, 0.3, 0.5) end)
        end
    end
end

-- Teleport to kick 1 target: approach from the direction we came from, charge through the target every frame with massive force (kick direction = toward the target)
-- until the target is flung far (> 150 studs or very fast) or time runs out
local function FlingOne(t, myHrp, char, home)
    local hum = char:FindFirstChildOfClass("Humanoid")
    local startPos = t.hrp.Position
    local t0 = os.clock()
    local i = 0
    local lunge = { -1.6, -0.6, 0.4, -1.0 }       -- lunge distances along the kick direction, alternating so we hit for sure
    local thrust = Instance.new("BodyThrust")
    thrust.Force = Vector3.new(9e8, 9e8, 9e8)
    thrust.Location = myHrp.Position
    thrust.Parent = myHrp
    if hum then hum.PlatformStand = true end

    -- Enlarge the hitbox (HumanoidRootPart) while kicking so it connects more easily (restored at the end)
    if not FlingSt.size then
        FlingSt.hrp, FlingSt.size = myHrp, myHrp.Size
    end
    pcall(function() myHrp.Size = Vector3.new(7, 7, 7) end)

    while Alive and FlingOn() and os.clock() - t0 < 1.8 do
        local hrp = t.hrp
        if not (hrp.Parent and myHrp.Parent) then break end
        if (hrp.Position - startPos).Magnitude > 150 or hrp.AssemblyLinearVelocity.Magnitude > 500 then break end
        if hum and hum.Health <= 0 then break end

        -- Kick direction: from our start point toward the target (horizontal), based on the latest target position
        local dir = hrp.Position - home.Position
        dir = Vector3.new(dir.X, 0, dir.Z)
        if dir.Magnitude < 0.1 then dir = hrp.CFrame.LookVector end
        dir = dir.Unit

        i = i % #lunge + 1
        local pos = hrp.Position + dir * lunge[i]
        -- Teleport the whole character (every part) together with the hitbox
        char:PivotTo(CFrame.lookAt(pos, pos + dir))
        myHrp.CanCollide = true
        for _, d in ipairs(char:GetChildren()) do
            if d:IsA("BasePart") and d ~= myHrp then d.CanCollide = false end
        end
        myHrp.AssemblyLinearVelocity = dir * 1e5 + Vector3.new(0, 3e4, 0)
        myHrp.AssemblyAngularVelocity = Vector3.new(9e8, 9e8, 9e8)
        RunService.Heartbeat:Wait()
        RunService.Stepped:Wait()
    end

    pcall(function() thrust:Destroy() end)
    if hum then hum.PlatformStand = false end
    if FlingSt.size then
        pcall(function() myHrp.Size = FlingSt.size end)
        FlingSt.size, FlingSt.hrp = nil, nil
    end
    myHrp.AssemblyLinearVelocity = Vector3.zero
    myHrp.AssemblyAngularVelocity = Vector3.zero
end

task.spawn(function()
    while Alive do
        if FlingOn() then
            local char = LP.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local myHrp = char and char:FindFirstChild("HumanoidRootPart")
            if hum and myHrp and hum.Health > 0 then
                local list = FlingTargets()
                if #list > 0 then
                    if FlingSt.char ~= char then FlingHeavy(char) end   -- make us as heavy as possible
                    local home = myHrp.CFrame
                    for _, t in ipairs(list) do
                        if not (Alive and FlingOn()) then break end
                        pcall(FlingOne, t, myHrp, char, home)
                    end
                    -- Go back: re-apply the position for several frames so we don't drift from leftover force
                    for _ = 1, 8 do
                        if not myHrp.Parent then break end
                        myHrp.AssemblyLinearVelocity = Vector3.zero
                        myHrp.AssemblyAngularVelocity = Vector3.zero
                        char:PivotTo(home)      -- teleport the whole character back with the hitbox
                        RunService.Heartbeat:Wait()
                    end
                    task.wait(0.15)
                else
                    task.wait(0.4)
                end
            else
                task.wait(0.4)
            end
        else
            if FlingSt.char then FlingRestore() end
            task.wait(0.3)
        end
    end
    FlingRestore()
end)

-- ============================================================
-- Aimbot (Sheriff): locks the camera onto the murderer only (never locks anyone else)
-- ============================================================
local AIMBOT_BIND = "NGOPornHubAimbot"

local function AimbotStep(dt)
    if not (S.AimbotOn and Alive) then return end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hum and hum.Health > 0) then return end
    if S.AimbotNeedGun and not char:FindFirstChild("Gun") then return end

    local cam = Workspace.CurrentCamera
    if not cam then return end

    local plr = GetMurderer()                       -- lock the murderer only
    local tChar = plr and plr.Character
    local hrp = tChar and tChar:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local part
    if S.AimbotPart == "Head" then
        part = tChar:FindFirstChild("Head")
    else
        part = tChar:FindFirstChild("UpperTorso") or tChar:FindFirstChild("Torso")
    end
    part = part or hrp

    local camPos = cam.CFrame.Position
    local goal = CFrame.lookAt(camPos, part.Position)
    local p = math.clamp((S.AimbotPower or 60) / 100, 0.05, 1)
    cam.CFrame = (p >= 1) and goal or cam.CFrame:Lerp(goal, p)
end

pcall(function() RunService:UnbindFromRenderStep(AIMBOT_BIND) end)
RunService:BindToRenderStep(AIMBOT_BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
    pcall(AimbotStep, dt)
end)

-- ============================================================
-- Hook: capture the game's real args format
-- ============================================================
local HookOK = false
do
    if hookmetamethod and newcclosure and getnamecallmethod and checkcaller then
        HookOK = pcall(function()
            local old
            old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                local method = getnamecallmethod()
                if method == "FireServer" and Alive and not checkcaller() then
                    local kind, rname = nil, nil
                    pcall(function()
                        local nm, par = self.Name, self.Parent
                        if nm == "Shoot" and par and par.Name == "Gun" then
                            kind = "gun"
                        elseif par and par.Name == "Events" and par.Parent and par.Parent.Name == "Knife" then
                            kind, rname = "knife", nm
                        elseif string.find(string.lower(nm), "throw", 1, true) and self:IsA("RemoteEvent")
                            and (par and (par.Name == "Knife" or (par.Parent and par.Parent.Name == "Knife"))) then
                            kind, rname = "knife", "ThrowRemote"
                        end
                    end)

                    if kind == "gun" then
                        S.GunTpl = table.pack(...)
                    elseif kind == "knife" then
                        KnifeTpl[rname] = table.pack(...)
                    end
                end
                if setnamecallmethod then setnamecallmethod(method) end
                return old(self, ...)
            end))
        end)
    end
end

-- ============================================================
-- Floating buttons (black squares / draggable / lockable position / adjustable length)
--   The button border uses a Border-mode UIStroke, so the text doesn't glow
-- ============================================================
local FloatList = {}
local ModeFloat = nil

local function ModeText()
    return S.ShootMode == MODE_2 and "MODE 2: WALL" or "MODE 1: NORMAL"
end

local function ToggleShootMode()
    S.ShootMode = (S.ShootMode == MODE_1) and MODE_2 or MODE_1
    if ModeFloat then ModeFloat.btn.Text = ModeText() end
    Notify("Shoot mode", S.ShootMode)
end

local function BtnHeight()
    return math.clamp(math.floor(S.BtnSize * 0.28), 30, 50)
end

local function RefreshFloat()
    local h = BtnHeight()
    for _, e in ipairs(FloatList) do
        if e.square then
            e.btn.Size = UDim2.fromOffset(S.ShootSize, S.ShootSize)
        else
            e.btn.Size = UDim2.fromOffset(math.floor(S.BtnSize * e.wMul), h)
        end
        e.stroke.Color = S.LockBtn and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(200, 200, 200)
        e.lockTag.Visible = S.LockBtn
    end
end

local BTN_IDLE  = Color3.new(0, 0, 0)
local BTN_PRESS = Color3.fromRGB(45, 45, 45)

local function MakeFloat(text, wMul, defaultPos, onClick, square)
    local b = Instance.new("TextButton")
    b.Name = RName()
    b.AnchorPoint = Vector2.new(1, 0)
    b.BackgroundColor3 = BTN_IDLE
    b.BackgroundTransparency = 0.05
    b.AutoButtonColor = false
    b.TextColor3 = Color3.fromRGB(235, 235, 235)
    b.TextStrokeTransparency = 1
    b.Font = Enum.Font.GothamBold
    b.TextScaled = true
    b.Text = text
    b.Position = defaultPos
    b.Visible = false
    b.ZIndex = 50
    b.Parent = Gui

    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 5); c.Parent = b
    local st = Instance.new("UIStroke")
    st.Thickness = 1.5
    st.Color = Color3.fromRGB(200, 200, 200)
    st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border   -- button border only, does not touch the text
    st.Parent = b
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 7); pad.PaddingRight = UDim.new(0, 7)
    pad.PaddingTop = UDim.new(0, 5); pad.PaddingBottom = UDim.new(0, 5)
    pad.Parent = b
    local tsc = Instance.new("UITextSizeConstraint")
    tsc.MaxTextSize = 14; tsc.MinTextSize = 6
    tsc.Parent = b

    -- Small LOCKED tag in the top-right corner (doesn't touch the button's main text)
    local tag = Instance.new("TextLabel")
    tag.BackgroundTransparency = 1
    tag.AnchorPoint = Vector2.new(1, 0)
    tag.Position = UDim2.new(1, -3, 0, 0)
    tag.Size = UDim2.fromOffset(46, 9)
    tag.Font = Enum.Font.GothamBold
    tag.TextSize = 8
    tag.TextXAlignment = Enum.TextXAlignment.Right
    tag.TextColor3 = Color3.fromRGB(80, 255, 120)
    tag.Text = "LOCKED"
    tag.Visible = false
    tag.ZIndex = 51
    tag.Parent = b

    local entry = { btn = b, wMul = wMul, square = square, stroke = st, lockTag = tag, defaultPos = defaultPos }
    FloatList[#FloatList + 1] = entry

    local dragging, moved = false, false
    local dragStart, startPos

    Connect(b.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            dragStart, startPos = input.Position, b.Position
            b.BackgroundColor3 = BTN_PRESS
            local ch
            ch = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    ch:Disconnect()
                    dragging = false
                    b.BackgroundColor3 = BTN_IDLE
                    if not moved then task.spawn(onClick) end
                end
            end)
        end
    end)

    Connect(UIS.InputChanged, function(input)
        if dragging and not S.LockBtn
            and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            if delta.Magnitude > 8 then moved = true end
            if moved then
                b.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end)

    return entry
end

-- Shoot button slightly smaller / other buttons shorter, stacked down the right side of the screen
local ShootFloat = MakeFloat("SHOOT", 1.00, UDim2.new(1, -12, 0.30, 0), ShootMurderer, true)
ModeFloat        = MakeFloat(ModeText(),       0.90, UDim2.new(1, -12, 0.42, 0), ToggleShootMode)
ThrowFloat = MakeFloat("THROW KNIFE",     0.90, UDim2.new(1, -12, 0.54, 0), ThrowKnife)
local GunFloat   = MakeFloat("GRAB GUN",       0.90, UDim2.new(1, -12, 0.66, 0), GrabGun)
RefreshFloat()

-- ============================================================
-- FPS Boost (single switch)
--   Map     : smooth material, shadows off, remove Decal/Texture/SurfaceAppearance/Mesh texture,
--             turn off Particle/Trail/Beam/lights/Highlight and all effects
--   Floor   : map floor + Terrain turn gray
--   Characters: everyone (including us) has no clothes/accessories/face and a fully gray body
--   World lighting: global shadows off, all PostEffects off, fog/clouds/grass/water waves
--   Rendering: lowest Quality, lowest MeshPart detail
-- ============================================================
local GRAY = Color3.fromRGB(128, 128, 128)
local GRAY_FLOOR = Color3.fromRGB(110, 110, 110)

local FPS = {
    on = false,
    orig = setmetatable({}, { __mode = "k" }),   -- original values of each Instance
    light = {},                                   -- original values of Lighting/Terrain/others
    terrain = nil,                                -- original Terrain material colors
    render = nil,
    token = 0,
    conn = nil,
}

-- Returns the player who owns the character that inst is inside (nil if it isn't part of a character)
local function CharOwner(inst)
    local p = inst.Parent
    while p and p ~= Workspace do
        if p:IsA("Model") then
            local plr = Players:GetPlayerFromCharacter(p)
            if plr then return plr end
        end
        p = p.Parent
    end
    return nil
end

local function Rec(inst)
    local r = FPS.orig[inst]
    if not r then r = {}; FPS.orig[inst] = r end
    return r
end

local function RSet(inst, prop, val)
    local ok, cur = pcall(function() return inst[prop] end)
    if not ok then return end
    local r = Rec(inst)
    if r[prop] == nil then r[prop] = cur end
    pcall(function() inst[prop] = val end)
end

local function IsFloorPart(inst)
    local sz = inst.Size
    local flat = math.min(sz.X, sz.Z)
    return sz.Y <= 6 and flat >= 6 and sz.Y <= flat * 0.5
end

local function ApplyInst(inst)
    if not FPS.on then return end

    -- All effects + lights
    if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Smoke") or inst:IsA("Fire") or inst:IsA("Sparkles")
        or inst:IsA("Light") or inst:IsA("Highlight")
        or inst:IsA("BillboardGui") or inst:IsA("SurfaceGui")
        or inst:IsA("PostEffect") or inst:IsA("Atmosphere") then
        RSet(inst, "Enabled", false)
        return
    end

    if inst:IsA("Explosion") or inst:IsA("ForceField")
        or inst:IsA("SelectionBox") or inst:IsA("SelectionSphere") then
        RSet(inst, "Visible", false)
        return
    end

    -- Character clothes and accessories
    if inst:IsA("Shirt") then RSet(inst, "ShirtTemplate", ""); return end
    if inst:IsA("Pants") then RSet(inst, "PantsTemplate", ""); return end
    if inst:IsA("ShirtGraphic") then RSet(inst, "Graphic", ""); return end
    if inst:IsA("CharacterMesh") then RSet(inst, "MeshId", ""); RSet(inst, "OverlayTextureId", ""); return end
    if inst:IsA("BodyColors") then
        for _, prop in ipairs({ "HeadColor3", "TorsoColor3", "LeftArmColor3", "RightArmColor3", "LeftLegColor3", "RightLegColor3" }) do
            RSet(inst, prop, GRAY)
        end
        return
    end

    -- Every kind of Texture
    if inst:IsA("Decal") or inst:IsA("Texture") then
        RSet(inst, "Transparency", 1)
        return
    end
    if inst:IsA("SurfaceAppearance") then
        RSet(inst, "ColorMap", ""); RSet(inst, "NormalMap", "")
        RSet(inst, "MetalnessMap", ""); RSet(inst, "RoughnessMap", "")
        return
    end
    if inst:IsA("SpecialMesh") then
        RSet(inst, "TextureId", "")
        return
    end

    if inst:IsA("BasePart") then
        if inst:IsA("Terrain") then return end
        local owner = CharOwner(inst)
        if owner then
            -- Every character: gray, no shadow, hide accessories
            RSet(inst, "CastShadow", false)
            RSet(inst, "Material", Enum.Material.SmoothPlastic)
            RSet(inst, "Reflectance", 0)
            if inst.Parent and inst.Parent:IsA("Accessory") then
                RSet(inst, "Transparency", 1)
            else
                RSet(inst, "Color", GRAY)
            end
            if inst:IsA("MeshPart") then
                RSet(inst, "TextureID", "")
                RSet(inst, "RenderFidelity", Enum.RenderFidelity.Performance)
            end
            return
        end
        RSet(inst, "Material", Enum.Material.SmoothPlastic)
        RSet(inst, "Reflectance", 0)
        RSet(inst, "CastShadow", false)
        if IsFloorPart(inst) then RSet(inst, "Color", GRAY_FLOOR) end
        if inst:IsA("MeshPart") then
            RSet(inst, "RenderFidelity", Enum.RenderFidelity.Performance)
            RSet(inst, "TextureID", "")
        end
    end
end

local function ChunkEach(list, token, fn)
    for i, inst in ipairs(list) do
        if FPS.token ~= token or not Alive then return end
        pcall(fn, inst)
        if i % 3000 == 0 then task.wait() end
    end
end

local function RestoreRecords()
    local items = {}
    for inst, rec in pairs(FPS.orig) do items[#items + 1] = { inst, rec } end
    for _, it in ipairs(items) do
        local inst, rec = it[1], it[2]
        if inst and inst.Parent then
            for prop, val in pairs(rec) do
                pcall(function() inst[prop] = val end)
            end
        end
        FPS.orig[inst] = nil
    end
end

-- Global settings (Lighting / Terrain / Atmosphere / Rendering)
local function LSet(obj, prop, val)
    local ok, cur = pcall(function() return obj[prop] end)
    if not ok then return end
    local rec = FPS.light[obj]
    if not rec then rec = {}; FPS.light[obj] = rec end
    if rec[prop] == nil then rec[prop] = cur end
    pcall(function() obj[prop] = val end)
end

local function LRestore()
    for obj, rec in pairs(FPS.light) do
        for prop, val in pairs(rec) do
            pcall(function() obj[prop] = val end)
        end
    end
    FPS.light = {}
    if FPS.terrain then
        local terrain = Workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            for m, c in pairs(FPS.terrain) do
                pcall(function() terrain:SetMaterialColor(m, c) end)
            end
        end
        FPS.terrain = nil
    end
end

local function ApplyRender()
    pcall(function()
        local r = settings().Rendering
        if not FPS.render then FPS.render = { q = r.QualityLevel } end
        r.QualityLevel = Enum.QualityLevel.Level01
    end)
    pcall(function()
        local r = settings().Rendering
        if FPS.render and FPS.render.m == nil then FPS.render.m = r.MeshPartDetailLevel end
        r.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04
    end)
end

local function RestoreRender()
    if FPS.render then
        local saved = FPS.render
        FPS.render = nil
        pcall(function() settings().Rendering.QualityLevel = saved.q end)
        if saved.m ~= nil then
            pcall(function() settings().Rendering.MeshPartDetailLevel = saved.m end)
        end
    end
end

local function ApplyGlobal()
    LSet(Lighting, "GlobalShadows", false)
    LSet(Lighting, "ShadowSoftness", 0)
    LSet(Lighting, "EnvironmentDiffuseScale", 0)
    LSet(Lighting, "EnvironmentSpecularScale", 0)

    for _, e in ipairs(Lighting:GetChildren()) do
        if e:IsA("PostEffect") then
            LSet(e, "Enabled", false)
        elseif e:IsA("Atmosphere") then
            LSet(e, "Density", 0)
            LSet(e, "Haze", 0)
        end
    end

    local cam = Workspace.CurrentCamera
    if cam then
        for _, e in ipairs(cam:GetChildren()) do
            if e:IsA("PostEffect") then LSet(e, "Enabled", false) end
        end
    end

    local terrain = Workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        LSet(terrain, "Decoration", false)
        LSet(terrain, "WaterWaveSize", 0)
        LSet(terrain, "WaterWaveSpeed", 0)
        LSet(terrain, "WaterReflectance", 0)
        local clouds = terrain:FindFirstChildOfClass("Clouds")
        if clouds then LSet(clouds, "Enabled", false) end
        -- Terrain floor turns gray
        if not FPS.terrain then
            FPS.terrain = {}
            for _, m in ipairs(Enum.Material:GetEnumItems()) do
                pcall(function()
                    FPS.terrain[m] = terrain:GetMaterialColor(m)
                    terrain:SetMaterialColor(m, GRAY_FLOOR)
                end)
            end
        end
    end

    ApplyRender()
end

local function RefreshFPS()
    FPS.token = FPS.token + 1
    local my = FPS.token
    task.spawn(function()
        RestoreRecords()
        LRestore()
        RestoreRender()
        if FPS.conn then FPS.conn:Disconnect(); FPS.conn = nil end
        if FPS.on then
            ApplyGlobal()
            FPS.conn = Workspace.DescendantAdded:Connect(function(d)
                -- Wait for the character to be bound to a player first, so player parts can be told apart from the map
                if Alive then task.delay(0.3, function() pcall(ApplyInst, d) end) end
            end)
            ChunkEach(Workspace:GetDescendants(), my, ApplyInst)
        end
    end)
end

local FpsLabel = Instance.new("TextLabel")
FpsLabel.Name = RName()
FpsLabel.BackgroundTransparency = 0.4
FpsLabel.BackgroundColor3 = Color3.new(0, 0, 0)
FpsLabel.Size = UDim2.fromOffset(86, 24)
FpsLabel.Position = UDim2.fromOffset(8, 8)
FpsLabel.TextColor3 = Color3.fromRGB(80, 255, 120)
FpsLabel.Font = Enum.Font.GothamBold
FpsLabel.TextSize = 14
FpsLabel.Text = "FPS: --"
FpsLabel.Visible = false
FpsLabel.Parent = Gui

do
    local frames, last = 0, os.clock()
    Connect(RunService.RenderStepped, function()
        frames = frames + 1
        local now = os.clock()
        if now - last >= 0.5 then
            if FpsLabel.Visible then
                FpsLabel.Text = "FPS: " .. tostring(math.floor(frames / (now - last) + 0.5))
            end
            frames, last = 0, now
        end
    end)
end

-- ============================================================
-- Unload
-- ============================================================
local function Unload()
    Alive = false
    KillCancel = true
    S.ESP = false
    S.AutoKill = false
    S.FlingMurd, S.FlingSheriff, S.FlingAll = false, false, false
    pcall(FlingRestore)
    S.AimbotOn = false
    pcall(function() RunService:UnbindFromRenderStep(AIMBOT_BIND) end)
    for _, c in ipairs(Conns) do pcall(function() c:Disconnect() end) end
    DestroyAllESP()
    ClearDropESP()
    FPS.on = false
    FPS.token = FPS.token + 1
    if FPS.conn then FPS.conn:Disconnect(); FPS.conn = nil end
    RestoreRecords()
    LRestore()
    RestoreRender()
    pcall(function() Folder:Destroy() end)
    pcall(function() Gui:Destroy() end)
    if WindowObj then pcall(function() WindowObj:Destroy() end) end
    env.NGOPornHubUnload = nil
end
env.NGOPornHubUnload = Unload

-- ============================================================
-- UI (declared once as data, then shown with WindUI or the fallback UI)
-- ============================================================
local function Diag()
    local gun = LP.Character and LP.Character:FindFirstChild("Gun")
    local drops = 0
    for _ in pairs(DropInsts) do drops = drops + 1 end
    return string.format(
        "roles: %s | hook: %s | gun args: %s | knife args: %s | Gun.Shoot: %s | knife: %s | GunDrop: %d",
        RoleSource, HookOK and "ok" or "unsupported",
        S.GunTpl and "yes" or "not yet",
        next(KnifeTpl) and "yes" or "not yet",
        (gun and gun:FindFirstChild("Shoot")) and "found" or "gun not held",
        HasKnife() and "yes" or "no",
        drops)
end

-- ============================================================
-- Menu background: 3 images (selectable in the Others tab)
-- ============================================================
-- Background 1 = Texture 14751314324 (usable directly as an image)
-- Background 2 = Asset (Decal) 14751314303 (must be converted to the real image first, otherwise it will not show)
local BG_TEXTURE_ID = 14751314324
local BG_ASSET_ID = 14751314303
-- Background 3 = Texture 130393160784262 (used directly); Asset (Decal) 134393565381500 is the fallback
--   if the texture fails to load (the Decal is converted to its real image)
local BG3_TEXTURE_ID = 130393160784262
local BG3_ASSET_ID = 134393565381500
local BG_IDS = { "rbxassetid://" .. BG_TEXTURE_ID, "rbxassetid://" .. BG_ASSET_ID, "rbxassetid://" .. BG3_TEXTURE_ID }
local BgAssetResolved = false
local Bg3Checked = false
local BG_ALPHA = 0.5          -- image transparency (0 = clearest, 1 = invisible)
local BgIndex = 1
local FallbackBgImg = nil     -- ImageLabel of the fallback menu (set when the fallback menu is built)

-- Convert a Decal asset into the real image id (read the Decal's Texture via GetObjects)
local function ResolveDecalImage(assetId)
    local ok, res = pcall(function()
        local objs = game:GetObjects("rbxassetid://" .. assetId)
        for _, o in ipairs(objs) do
            if o:IsA("Decal") or o:IsA("Texture") then return o.Texture end
            local d = o:FindFirstChildWhichIsA("Decal", true) or o:FindFirstChildWhichIsA("Texture", true)
            if d then return d.Texture end
        end
        return nil
    end)
    if ok and type(res) == "string" and res ~= "" then
        local num = string.match(res, "id=(%d+)") or string.match(res, "rbxassetid://(%d+)")
        if num then return "rbxassetid://" .. num end
        return res
    end
    return nil
end

-- Check whether an image url really loads
local function ImageLoads(url)
    local ok, ready = pcall(function()
        local img = Instance.new("ImageLabel")
        img.Image = url
        local result
        game:GetService("ContentProvider"):PreloadAsync({ img }, function(_, status) result = status end)
        pcall(function() img:Destroy() end)
        return result == Enum.AssetFetchStatus.Success
    end)
    return ok and ready == true
end

local function ApplyBackground(idx)
    BgIndex = idx
    -- Background 3: use the texture; if it does not load, fall back to converting the asset (Decal)
    if idx == 3 and not Bg3Checked then
        Bg3Checked = true
        task.spawn(function()
            if not ImageLoads(BG_IDS[3]) then
                -- 1) convert the Decal asset to its real image  2) otherwise try the asset id directly
                local img = ResolveDecalImage(BG3_ASSET_ID)
                if img then
                    BG_IDS[3] = img
                elseif ImageLoads("rbxassetid://" .. BG3_ASSET_ID) then
                    BG_IDS[3] = "rbxassetid://" .. BG3_ASSET_ID
                end
            end
            if BgIndex == 3 then ApplyBackground(3) end
        end)
    end
    -- Background 2 (Asset): convert to the real image the first time it's selected, then set the image
    if idx == 2 and not BgAssetResolved then
        BgAssetResolved = true
        task.spawn(function()
            local img = ResolveDecalImage(BG_ASSET_ID)
            if img then BG_IDS[2] = img end
            if BgIndex == 2 then ApplyBackground(2) end
        end)
    end
    local id = BG_IDS[idx]
    if not id then return end
    if WindowObj then
        pcall(function() WindowObj:SetBackgroundImage(id) end)
        pcall(function() WindowObj:SetBackgroundImageTransparency(BG_ALPHA) end)
    end
    if FallbackBgImg then pcall(function() FallbackBgImg.Image = id end) end
end

local Spec = {
    { name = "ESP", icon = "eye", items = {
        { "toggle", "ESP (everything)", "Players split by role Murderer / Sheriff / Hero / Innocent with name, distance, held weapon + dropped gun", false, function(v)
            S.ESP = v
            if v then
                ShowDropESP()
            else
                DestroyAllESP()
                ClearDropESP()
            end
        end },
    } },
    { name = "Sheriff", icon = "crosshair", items = {
        { "button", "Switch shoot mode (Mode 1 / Mode 2)", "Mode 1 normal shot (no wall in the way) / Mode 2 shoots through walls", ToggleShootMode },
        { "dropdown", "Aim point", { "Torso", "Head" }, "Torso", function(v) S.AimPart = v end },
        { "dropdown", "Args format (used until you have shot manually once)", { "CFrame, CFrame", "Vector3 (target)", "Vector3 (origin, target)" }, "CFrame, CFrame", function(v) S.ArgMode = v end },
    } },
    { name = "Aimbot", icon = "target", items = {
        { "toggle", "Aimbot (lock murderer)", "Locks the camera onto the murderer only, never other players", false, function(v) S.AimbotOn = v end },
        { "dropdown", "Lock point", { "Head", "Torso" }, "Head", function(v) S.AimbotPart = v end },
        { "slider", "Lock strength (%) 100 = instant lock", 5, 100, 60, 5, function(v) S.AimbotPower = v end },
        { "toggle", "Lock only while holding the gun", nil, true, function(v) S.AimbotNeedGun = v end },
    } },
    { name = "Murderer", icon = "skull", items = {
        { "button", "Kill All (teleport to hitboxes)", "Teleports to one player at a time, nearest first", function() task.spawn(KillAll, false) end },
        { "toggle", "Auto Kill (hold the knife and everyone dies, no teleport)", "Turn on, then hold the knife in hand. The script attacks everyone alive instantly while you stay in place", false, function(v) S.AutoKill = v end },
        { "slider", "Delay per attempt (ms)", 100, 1000, 250, 50, function(v) S.KillDelay = v end },
        { "slider", "Retries per target", 1, 5, 3, 1, function(v) S.KillRetries = v end },
        { "toggle", "Return to original position when done", nil, true, function(v) S.KillReturn = v end },
    } },
    { name = "Floating Buttons", icon = "mouse-pointer-click", items = {
        { "toggle", "SHOOT floating button (small square)", "Press to shoot the murderer instantly", false, function(v) S.ShootBtn = v; ShootFloat.btn.Visible = v end },
        { "toggle", "MODE floating button (switch shoot mode)", "Press to switch MODE 1: NORMAL / MODE 2: WALL. The button text shows the current mode", false, function(v) S.ModeBtn = v; ModeFloat.btn.Visible = v end },
        { "toggle", "THROW KNIFE floating button", "Press to lock the closest player you aim at; the knife teleports to the hitbox and your character stays put (Murderer only)", false, function(v) S.ThrowBtn = v; ThrowFloat.btn.Visible = v end },
        { "toggle", "GRAB GUN floating button", "Sends your hitbox to touch the nearest dropped gun; your character stays put", false, function(v) S.GunBtn = v; GunFloat.btn.Visible = v end },
        { "toggle", "Lock floating button position", "Prevents accidental dragging while pressing (button border turns green and shows a LOCKED tag)", false, function(v) S.LockBtn = v; RefreshFloat() end },
        { "slider", "Shoot button size (square)", 36, 110, 64, 2, function(v) S.ShootSize = v; RefreshFloat() end },
        { "slider", "Other buttons length", 90, 240, 140, 10, function(v) S.BtnSize = v; RefreshFloat() end },
        { "button", "Reset button positions", nil, function()
            for _, e in ipairs(FloatList) do e.btn.Position = e.defaultPos end
        end },
    } },
    { name = "FPS", icon = "zap", items = {
        { "toggle", "FPS Boost (maximum)", "Removes all textures/clothes/effects; every character and the floor turn gray; shadows/lighting off", false, function(v) FPS.on = v; RefreshFPS() end },
        { "toggle", "Show FPS counter", nil, false, function(v) FpsLabel.Visible = v end },
    } },
    { name = "Fling", icon = "wind", items = {
        { "label", "Warning: still buggy", "Hard to use. Walkfling is still being improved" },
        { "toggle", "Walkfling Murderer", "Teleports your whole character and hitbox to kick the murderer far away, then returns to your original spot", false, function(v) S.FlingMurd = v end },
        { "toggle", "Walkfling Sheriff", "Teleports your whole character and hitbox to kick whoever holds the gun (Sheriff / Hero)", false, function(v) S.FlingSheriff = v end },
        { "toggle", "Walkfling Whole Server", "Teleports your whole character and hitbox to kick everyone alive, one at a time", false, function(v) S.FlingAll = v end },
    } },
    { name = "Others", icon = "settings", items = {
        { "dropdown", "Menu background", { "Background 1", "Background 2", "Background 3" }, "Background 1", function(v) ApplyBackground(v == "Background 3" and 3 or (v == "Background 2" and 2 or 1)) end },
        { "button", "System check", "Check whether role / hook / args / GunDrop are working", function() Notify("System status", Diag() .. " | Shoot mode: " .. S.ShootMode) end },
        { "button", "Unload script", "Clears everything and restores graphics", function() Unload() end },
    } },
}

local function LoadWindUI()
    local urls = {
        "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua",
        "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua",
    }
    for _, u in ipairs(urls) do
        local ok, lib = pcall(function() return loadstring(game:HttpGet(u))() end)
        if ok and type(lib) == "table" then return lib end
    end
    return nil
end

local function RenderWind(WindUI)
    local ok, Window = pcall(function()
        return WindUI:CreateWindow({
            Title = "NGO PORN HUB",
            Icon = "swords",
            Author = "V1",
            Folder = "NGOPornHubV1",
            Size = UDim2.fromOffset(580, 460),
            Theme = "Dark",
            Background = BG_IDS[1],
            BackgroundImageTransparency = BG_ALPHA,
            Resizable = true,
            HideSearchBar = true,
        })
    end)
    if not ok or not Window then return false end
    WindowObj, WindRef = Window, WindUI
    pcall(function() Window:SetToggleKey(Enum.KeyCode.RightShift) end)
    -- Open button: rainbow colors that keep cycling
    local function RainbowSeq(off)
        local pts = {}
        for i = 0, 5 do
            local t = i / 5
            pts[#pts + 1] = ColorSequenceKeypoint.new(t, Color3.fromHSV((off + t) % 1, 1, 1))
        end
        return ColorSequence.new(pts)
    end
    local function EditBtn(off)
        pcall(function()
            Window:EditOpenButton({
                Title = "NGO PORN HUB", Icon = "swords", CornerRadius = UDim.new(0, 16),
                StrokeThickness = 2, Draggable = true,
                Color = RainbowSeq(off),
            })
        end)
    end
    EditBtn(0)
    task.spawn(function()
        local off = 0
        while Alive and WindowObj == Window do
            off = (off + 0.03) % 1
            EditBtn(off)
            task.wait(0.12)
        end
    end)

    for _, tabSpec in ipairs(Spec) do
        local okT, Tab = pcall(function() return Window:Tab({ Title = tabSpec.name, Icon = tabSpec.icon }) end)
        if okT and Tab then
            for _, it in ipairs(tabSpec.items) do
                local kind = it[1]
                pcall(function()
                    if kind == "toggle" then
                        Tab:Toggle({ Title = it[2], Desc = it[3], Default = it[4], Value = it[4], Callback = it[5] })
                    elseif kind == "slider" then
                        Tab:Slider({ Title = it[2], Step = it[6], Value = { Min = it[3], Max = it[4], Default = it[5] }, Callback = it[7] })
                    elseif kind == "dropdown" then
                        Tab:Dropdown({ Title = it[2], Values = it[3], Value = it[4], Callback = it[5] })
                    elseif kind == "button" then
                        Tab:Button({ Title = it[2], Desc = it[3], Callback = it[4] })
                    elseif kind == "label" then
                        Tab:Paragraph({ Title = it[2], Desc = it[3] })
                    end
                end)
            end
        end
    end
    return true
end

local function RenderFallback()
    local main = Instance.new("Frame")
    main.Name = RName()
    main.Size = UDim2.fromOffset(310, 400)
    main.Position = UDim2.new(0, 16, 0.5, -200)
    main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    main.Active = true
    main.Draggable = true
    main.Parent = Gui
    local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 10); mc.Parent = main

    -- Fallback menu background image (behind all buttons)
    local bgImg = Instance.new("ImageLabel")
    bgImg.Name = "Bg"
    bgImg.Size = UDim2.fromScale(1, 1)
    bgImg.BackgroundTransparency = 1
    bgImg.Image = BG_IDS[BgIndex]
    bgImg.ImageTransparency = BG_ALPHA
    bgImg.ScaleType = Enum.ScaleType.Crop
    bgImg.ZIndex = 0
    bgImg.Parent = main
    local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 10); bc.Parent = bgImg
    FallbackBgImg = bgImg

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundTransparency = 1
    title.Text = "NGO PORN HUB (fallback UI) - drag to move"
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.Parent = main

    local list = Instance.new("ScrollingFrame")
    list.Position = UDim2.fromOffset(0, 32)
    list.Size = UDim2.new(1, 0, 1, -32)
    list.BackgroundTransparency = 1
    list.ScrollBarThickness = 4
    list.CanvasSize = UDim2.new()
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.Parent = main
    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 4)
    lay.Parent = list

    local function mk(class, props)
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        o.Parent = list
        return o
    end
    local function btn(text)
        return mk("TextButton", {
            Size = UDim2.new(1, -10, 0, 28), BackgroundColor3 = Color3.fromRGB(45, 45, 56),
            TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.Gotham, TextSize = 13, Text = text,
        })
    end

    for _, tabSpec in ipairs(Spec) do
        mk("TextLabel", {
            Size = UDim2.new(1, -10, 0, 22), BackgroundTransparency = 1, Text = "== " .. tabSpec.name .. " ==",
            TextColor3 = Color3.fromRGB(255, 220, 80), Font = Enum.Font.GothamBold, TextSize = 13,
        })
        for _, it in ipairs(tabSpec.items) do
            local kind = it[1]
            if kind == "toggle" then
                local state = it[4]
                local b = btn((state and "[ON]  " or "[OFF] ") .. it[2])
                b.MouseButton1Click:Connect(function()
                    state = not state
                    b.Text = (state and "[ON]  " or "[OFF] ") .. it[2]
                    it[5](state)
                end)
            elseif kind == "slider" then
                local b = mk("TextBox", {
                    Size = UDim2.new(1, -10, 0, 28), BackgroundColor3 = Color3.fromRGB(45, 45, 56),
                    TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.Gotham, TextSize = 13,
                    PlaceholderText = it[2] .. " (" .. it[3] .. "-" .. it[4] .. ")",
                    Text = tostring(it[5]), ClearTextOnFocus = false,
                })
                b.FocusLost:Connect(function()
                    local n = tonumber(b.Text)
                    if n then
                        n = math.clamp(n, it[3], it[4])
                        b.Text = tostring(n)
                        it[7](n)
                    end
                end)
            elseif kind == "dropdown" then
                local values, i = it[3], 1
                for k, v in ipairs(values) do if v == it[4] then i = k end end
                local b = btn(it[2] .. ": " .. values[i])
                b.MouseButton1Click:Connect(function()
                    i = i % #values + 1
                    b.Text = it[2] .. ": " .. values[i]
                    it[5](values[i])
                end)
            elseif kind == "button" then
                local b = btn(it[2])
                b.MouseButton1Click:Connect(it[4])
            elseif kind == "label" then
                mk("TextLabel", {
                    Size = UDim2.new(1, -10, 0, 34), BackgroundTransparency = 1,
                    Text = it[2] .. (it[3] and ("\n" .. it[3]) or ""), TextWrapped = true,
                    TextColor3 = Color3.fromRGB(255, 120, 120), Font = Enum.Font.GothamBold, TextSize = 12,
                })
            end
        end
    end
end

task.spawn(function()
    local WindUI = LoadWindUI()
    local rendered = false
    if WindUI then rendered = RenderWind(WindUI) end
    if not rendered then
        RenderFallback()
        Notify("NGO PORN HUB", "Could not load WindUI, using the fallback UI instead")
    else
        Notify("NGO PORN HUB V1", "Loaded successfully (RightShift = hide/show menu)")
    end
end)

print("[NGOPornHub] V1 loaded | hook: " .. (HookOK and "ok" or "unsupported"))
