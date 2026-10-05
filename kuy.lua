--[[
    MM2 HUB v8  (ไฟล์เดียว รวมทุกอย่าง)
    UI: WindUI  (ถ้าโหลดไม่ได้ จะใช้ UI สำรองในตัวอัตโนมัติ)

    ฟีเจอร์
      - ESP แบ่งบทบาท + ESP ปืนที่ดรอป
      - มือปืน 2 โหมด:  1) ยิงไม่ทะลุ (ต้องไม่มีกำแพงบัง)
                         2) ยิงทะลุ (กระสุนวาปติด hitbox ฆาตกร)
      - ฆาตกร: ฆ่าทั้งแมพ วาปไปหา hitbox ทีละคน (ปุ่มลอย / ออโต้)
      - ปุ่มลอย 3 ปุ่ม: SHOOT / KILL ALL / GUN (วาปไปเก็บปืนที่ดรอป)
        ล็อกตำแหน่ง ปรับขนาด รีเซ็ตตำแหน่งได้
      - FPS Boost แบบเน้นผลจริง (2 สวิตช์ + FPS Cap)
]]

local env = (getgenv and getgenv()) or _G
if env.MM2HubUnload then pcall(env.MM2HubUnload) end

-- ============================================================
-- Services / พื้นฐาน
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
    return "MM2_" .. tostring(math.random(100000, 999999))
end

local function SafeParent()
    local ok, parent = pcall(function()
        if gethui then return gethui() end
        return game:GetService("CoreGui")
    end)
    if ok and parent then return parent end
    return LP:WaitForChild("PlayerGui")
end

-- โหมดยิงของมือปืน
local MODE_1 = "โหมด 1: ยิงไม่ทะลุ (ต้องไม่มีกำแพงบัง)"
local MODE_2 = "โหมด 2: ยิงทะลุ (กระสุนวาปติด hitbox)"

local S = {
    ESP = false, Tracer = false,
    ShowMurderer = true, ShowSheriff = true, ShowInnocent = true, ShowUnknown = true,
    ShowName = true, ShowDist = true, ESPMax = 2000,
    DropESP = false,
    -- มือปืน
    SilentAim = false, ShootMode = MODE_1, AimPart = "Torso", PredictMs = 80,
    ArgMode = "CFrame, CFrame",
    -- ปุ่มลอย
    ShootBtn = false, ModeBtn = false, KillBtn = false, GunBtn = false, LockBtn = false, BtnSize = 140, ShootSize = 64,
    -- ฆาตกร
    AutoKill = false, KillDelay = 250, KillRetries = 3, KillReturn = true,
    -- เก็บปืน
    GrabReturn = true, GrabTeleport = false,
    Debug = false,
    GunTpl = nil,     -- args ที่เกมใช้ยิงปืนจริง (จับอัตโนมัติ)
}
local KnifeTpl = {}   -- args ที่เกมใช้กับ Knife.Events.* (จับอัตโนมัติ)

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
-- ระบบ Role (อ่านจากข้อมูลที่เกมส่งมา ไม่ใช่เดาจาก Backpack)
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
-- ESP ผู้เล่น
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

local function RoleVisible(role)
    if role == "Murderer" then return S.ShowMurderer end
    if role == "Sheriff" or role == "Hero" then return S.ShowSheriff end
    if role == "Innocent" then return S.ShowInnocent end
    return S.ShowUnknown
end

local KeyRole = { Murderer = true, Sheriff = true, Hero = true }   -- เห็นตลอดไม่จำกัดระยะ

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
        bb.Size = UDim2.fromOffset(170, 64)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.Parent = Folder

        -- ข้อความ (ชื่อ / role+อาวุธ / ระยะ) ชิดล่าง วางเหนือแถบเลือด
        local tl = Instance.new("TextLabel")
        tl.BackgroundTransparency = 1
        tl.Size = UDim2.new(1, 0, 0, 52)
        tl.Font = Enum.Font.GothamBold
        tl.TextSize = 13
        tl.TextYAlignment = Enum.TextYAlignment.Bottom
        tl.TextStrokeTransparency = 0.3
        tl.TextColor3 = Color3.new(1, 1, 1)
        tl.Parent = bb

        -- แถบเลือด
        local bar = Instance.new("Frame")
        bar.AnchorPoint = Vector2.new(0.5, 0)
        bar.Position = UDim2.new(0.5, 0, 0, 56)
        bar.Size = UDim2.fromOffset(64, 5)
        bar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        bar.BorderSizePixel = 0
        bar.Parent = bb
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(1, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(80, 255, 80)
        fill.BorderSizePixel = 0
        fill.Parent = bar

        o = { hl = hl, bb = bb, tl = tl, fill = fill, char = char }
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
            local show = hrp and head and hum and hum.Health > 0 and role ~= "Dead"
                and RoleVisible(role) and (key or dist <= S.ESPMax)
            if show then
                local o = EnsureESP(plr, char, head)
                local col = RoleColor[role] or RoleColor.Unknown
                o.hl.Enabled = true
                o.bb.Enabled = true
                o.hl.FillColor = col
                o.hl.OutlineColor = col
                -- ตัวสำคัญเข้มกว่า คนทั่วไปจางกว่า
                o.hl.FillTransparency = (role == "Murderer" and 0.4) or (key and 0.5) or 0.78
                o.tl.TextColor3 = col
                o.tl.TextTransparency = key and 0 or math.clamp((dist - 250) / 1200, 0, 0.55)

                local lines = {}
                if S.ShowName then lines[#lines + 1] = plr.DisplayName end
                local roleLine = RoleLabel[role] or "?"
                local item = HeldItem(char)
                if item then roleLine = roleLine .. "  (" .. item .. ")" end
                lines[#lines + 1] = roleLine
                if S.ShowDist and myHrp then lines[#lines + 1] = string.format("%d m", dist) end
                o.tl.Text = table.concat(lines, "\n")

                local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                o.fill.Size = UDim2.new(frac, 0, 1, 0)
                o.fill.BackgroundColor3 = Color3.fromHSV(frac * 0.33, 0.9, 1)
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

-- เส้นนำทาง (Tracer) ไปหา Murderer / Sheriff / Hero  ใช้ Drawing API (ถ้า executor รองรับ)
local DrawOK = false
pcall(function()
    local l = Drawing.new("Line")
    l:Remove()
    DrawOK = true
end)
local Tracers = {}

local function ClearTracers()
    for plr, ln in pairs(Tracers) do
        pcall(function() ln:Remove() end)
        Tracers[plr] = nil
    end
end

Connect(RunService.RenderStepped, function()
    if not (S.Tracer and DrawOK) then
        if next(Tracers) then ClearTracers() end
        return
    end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local vp = cam.ViewportSize
    local from = Vector2.new(vp.X / 2, vp.Y)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local role = GetRole(plr)
            local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            local ln = Tracers[plr]
            if hrp and KeyRole[role] and RoleVisible(role) and IsAlive(plr) then
                if not ln then
                    ln = Drawing.new("Line")
                    ln.Thickness = 1.5
                    ln.Transparency = 1
                    Tracers[plr] = ln
                end
                local pos = cam:WorldToViewportPoint(hrp.Position)
                if pos.Z > 0 then
                    ln.From = from
                    ln.To = Vector2.new(pos.X, pos.Y)
                    ln.Color = RoleColor[role]
                    ln.Visible = true
                else
                    ln.Visible = false
                end
            elseif ln then
                ln.Visible = false
            end
        end
    end
end)

Connect(Players.PlayerRemoving, function(plr)
    DestroyESP(plr)
    RoleCache[plr.Name] = nil
    local ln = Tracers[plr]
    if ln then pcall(function() ln:Remove() end); Tracers[plr] = nil end
end)

-- ============================================================
-- ปืนที่ดรอป (GunDrop): ติดตามตลอด + ESP (เปิด/ปิดได้) + ใช้กับปุ่มวาปเก็บปืน
-- ============================================================
local DropInsts = {}   -- [inst] = true
local DropObjs  = {}   -- [inst] = {hl, bb}  (เฉพาะตอนเปิด ESP)

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
    if S.DropESP then task.defer(AddDropESP, inst) end
end

local function ShowDropESP()
    for inst in pairs(DropInsts) do AddDropESP(inst) end
end

-- อัปเดตระยะบนป้าย GUN DROP
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
-- มือปืน: 2 โหมด
-- ============================================================
local function IsSpatial(v)
    local t = typeof(v)
    return t == "CFrame" or t == "Vector3"
end

-- เปลี่ยนตำแหน่งปลายทาง (ตำแหน่งตัวสุดท้ายใน args) เป็นเป้า
-- ถ้าให้ origin มาและมีตำแหน่ง >= 2 ตัว จะเปลี่ยนตัวแรกเป็นต้นทางกระสุน
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
    if S.ArgMode == "Vector3 (เป้า)" then
        return table.pack(target)
    elseif S.ArgMode == "Vector3 (ต้นทาง, เป้า)" then
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

-- ชดเชยการเคลื่อนที่ของเป้า (ยืนบนพื้นให้ตัดแกน Y ทิ้ง / ถูกวาปหรือเหวี่ยงแรงๆ ไม่ชดเชย)
local function PredictOffset(char, ms)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return Vector3.zero end
    local v = hrp.AssemblyLinearVelocity
    if v.Magnitude > 80 then return Vector3.zero end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.FloorMaterial ~= Enum.Material.Air then
        v = Vector3.new(v.X, 0, v.Z)
    end
    return v * (ms / 1000)
end

-- โหมด 1: เช็คว่ามีกำแพง/วัตถุแมพบังระหว่างเรากับเป้าไหม (ไม่นับตัวผู้เล่น)
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

-- โหมด 2: วางต้นทางกระสุนห่างจาก hitbox แค่ ~2.5 studs (ไม่มีอะไรมาคั่น)
local function NearOrigin(myPos, targetPos)
    local dir = myPos - targetPos
    if dir.Magnitude < 3 then return myPos end
    return targetPos + dir.Unit * 2.5
end

-- คำนวณการยิง: คืน origin, point  (origin = nil แปลว่าใช้ต้นทางเดิมของเกม)
--   โหมด 1: ลองเล็ง ลำตัว/หัว/ช่วงล่าง ตามลำดับ เลือกจุดแรกที่ "มองเห็นจริง" ไม่มีกำแพงบัง
--   โหมด 2: เล็งกลาง hitbox ตรงๆ ไม่ชดเชย และวางต้นทางกระสุนติด hitbox (ทะลุกำแพง)
--   ถ้าโหมด 1 ถูกบังทุกจุดจะคืน nil, nil, "blocked"
local function ComputeShot(target, myHrp)
    local char = target.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil, "nochar" end
    local head = char:FindFirstChild("Head")
    local lower = char:FindFirstChild("LowerTorso")

    if S.ShootMode == MODE_2 then
        local p = (S.AimPart == "Head" and head and head.Position) or hrp.Position
        return NearOrigin(myHrp.Position, p), p
    end

    local off = PredictOffset(char, S.PredictMs)
    local cands = {}
    if S.AimPart == "Head" and head then cands[#cands + 1] = head.Position end
    cands[#cands + 1] = hrp.Position
    if head and S.AimPart ~= "Head" then cands[#cands + 1] = head.Position end
    if lower then cands[#cands + 1] = lower.Position end

    local myHead = LP.Character and LP.Character:FindFirstChild("Head")
    local eye = myHead and myHead.Position or myHrp.Position
    for _, c in ipairs(cands) do
        local p = c + off
        if HasLineOfSight(eye, p) then return nil, p end
    end
    return nil, nil, "blocked"
end

local lastShot = 0
local function ShootMurderer()
    if os.clock() - lastShot < 0.25 then return end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and myHrp and hum.Health > 0) then return end

    local target = GetMurderer()
    if not target then
        Notify("ยิงไม่ได้", "ไม่พบฆาตกร (อาจยังไม่เริ่มรอบ)")
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
        Notify("ยิงไม่ได้", "คุณไม่มีปืน (ต้องเป็น Sheriff / Hero)")
        return
    end

    local shoot = gun:FindFirstChild("Shoot")
    if not (shoot and shoot:IsA("RemoteEvent")) then
        Notify("ยิงไม่ได้", "ไม่พบ Remote 'Shoot' ในปืน")
        return
    end

    local origin, p, why = ComputeShot(target, myHrp)
    if not p then
        if why == "blocked" then
            Notify("ยิงไม่ได้ (โหมด 1)", "มีกำแพงบังทุกจุดของฆาตกร สลับเป็นโหมด 2 ถ้าต้องการยิงทะลุ")
        end
        return
    end

    lastShot = os.clock()
    local args = BuildShotArgs(origin or myHrp.Position, p)
    shoot:FireServer(unpack(args, 1, args.n))

    -- แจ้งผลหลังยิง
    task.spawn(function()
        task.wait(0.45)
        local c = target.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        if (not h) or h.Health <= 0 or GetRole(target) == "Dead" then
            Notify("ยิงโดน", "ฆาตกรตายแล้ว")
        end
    end)
end

-- ============================================================
-- วาปไปเก็บปืนที่ดรอป
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
        Notify("เก็บปืน", "คุณมีปืนอยู่แล้ว")
        return
    end
    local part = NearestDropPart(myHrp.Position)
    if not part then
        Notify("เก็บปืน", "ไม่พบปืนที่ดรอป (ยังไม่มีใครตาย หรือยังไม่เริ่มรอบ)")
        return
    end
    if not firetouchinterest and not S.GrabTeleport then
        Notify("เก็บปืนไม่ได้", "executor นี้ไม่รองรับ firetouchinterest (ต้องใช้ส่ง hitbox ไปแตะปืน)")
        return
    end

    Grabbing = true
    local t0 = os.clock()
    local done = false
    local links = {}

    -- รู้ทันทีที่ปืนเข้ากระเป๋า/ตัว
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then
        links[#links + 1] = bp.ChildAdded:Connect(function(c) if c.Name == "Gun" then done = true end end)
    end
    links[#links + 1] = char.ChildAdded:Connect(function(c) if c.Name == "Gun" then done = true end end)

    local bodyParts = {}
    for _, d in ipairs(char:GetChildren()) do
        if d:IsA("BasePart") then bodyParts[#bodyParts + 1] = d end
    end

    -- ส่ง "hitbox" (ชิ้นส่วนตัวละคร) ไปแตะปืน โดยตัวละครอยู่กับที่
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
        touchAll()   -- เฟรมแรก
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

    -- (ตัวเลือก ปิดไว้เป็นค่าเริ่มต้น) ถ้า hitbox แตะแล้วเซิร์ฟเวอร์ไม่รับ ให้วาปตัวละครไปช่วย
    if not (done or HasGun()) and S.GrabTeleport and part and part.Parent then
        local startCF = myHrp.CFrame
        local t1 = os.clock()
        pcall(function()
            while not done and Alive and os.clock() - t1 < 0.5 do
                myHrp.CFrame = part.CFrame
                myHrp.AssemblyLinearVelocity = Vector3.zero
                touchAll()
                RunService.Heartbeat:Wait()
                if done or HasGun() or not part.Parent then break end
            end
        end)
        if myHrp.Parent then
            myHrp.CFrame = startCF
            myHrp.AssemblyLinearVelocity = Vector3.zero
        end
    end

    local got = done or HasGun()
    for _, l in ipairs(links) do pcall(function() l:Disconnect() end) end
    Grabbing = false
    if got then
        Notify("เก็บปืน", string.format("เก็บปืนสำเร็จ (%.2f วิ)", os.clock() - t0))
    else
        Notify("เก็บปืน", "ส่ง hitbox ไปแตะแล้วแต่เซิร์ฟเวอร์ไม่รับ (เกมอาจเช็คระยะ) เปิด 'วาปตัวละครช่วย' ได้")
    end
end

-- ============================================================
-- ฆาตกร: ฆ่าทั้งแมพ วาปไปหา hitbox
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

-- เปลี่ยน args ที่เกมเคยใช้กับมีด ให้ชี้ไปที่เหยื่อ
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
        if not silent then Notify("ฆ่าไม่ได้", "คุณไม่มีมีด (ต้องเป็น Murderer)") end
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

                -- วาปไปด้านหลัง hitbox ของเป้า (ห่าง 2 studs หันหน้าเข้าหา)
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
        Notify("Kill All", string.format("เสร็จแล้ว: %d / %d", killed, total))
    end
end

task.spawn(function()
    while Alive do
        if S.AutoKill and not KillRunning and HasKnife() then
            pcall(KillAll, true)
        end
        task.wait(0.5)
    end
end)

-- ============================================================
-- Hook: จับรูปแบบ args จริงของเกม + Silent Aim
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
                        end
                    end)

                    if kind == "gun" then
                        local args = table.pack(...)
                        S.GunTpl = table.pack(...)
                        if S.Debug then
                            local t = {}
                            for i = 1, args.n do t[i] = typeof(args[i]) end
                            print("[MM2Hub] Gun.Shoot args: " .. table.concat(t, ", "))
                        end
                        if S.SilentAim then
                            local newArgs = nil
                            pcall(function()
                                local tgt = GetMurderer()
                                local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                                if tgt and myHrp then
                                    local origin, p = ComputeShot(tgt, myHrp)
                                    if p then newArgs = Retarget(args, origin, p) end
                                end
                            end)
                            if newArgs then
                                if setnamecallmethod then setnamecallmethod(method) end
                                return old(self, unpack(newArgs, 1, newArgs.n))
                            end
                        end
                    elseif kind == "knife" then
                        KnifeTpl[rname] = table.pack(...)
                        if S.Debug then
                            local a = table.pack(...)
                            local t = {}
                            for i = 1, a.n do t[i] = typeof(a[i]) end
                            print("[MM2Hub] Knife." .. rname .. " args: " .. table.concat(t, ", "))
                        end
                    end
                end
                if setnamecallmethod then setnamecallmethod(method) end
                return old(self, ...)
            end))
        end)
    end
end

-- ============================================================
-- ปุ่มลอย (สี่เหลี่ยมสีดำ / ลากได้ / ล็อกตำแหน่งได้ / ปรับความยาวได้)
--   ขอบปุ่มใช้ UIStroke แบบ Border จึงไม่ทำให้ตัวหนังสือเรืองแสง
-- ============================================================
local FloatList = {}
local ModeFloat = nil

local function ModeText()
    return S.ShootMode == MODE_2 and "MODE 2: WALL" or "MODE 1: NORMAL"
end

local function ToggleShootMode()
    S.ShootMode = (S.ShootMode == MODE_1) and MODE_2 or MODE_1
    if ModeFloat then ModeFloat.btn.Text = ModeText() end
    Notify("โหมดยิง", S.ShootMode)
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
    st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border   -- ขอบปุ่มเท่านั้น ไม่แตะตัวอักษร
    st.Parent = b
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 7); pad.PaddingRight = UDim.new(0, 7)
    pad.PaddingTop = UDim.new(0, 5); pad.PaddingBottom = UDim.new(0, 5)
    pad.Parent = b
    local tsc = Instance.new("UITextSizeConstraint")
    tsc.MaxTextSize = 14; tsc.MinTextSize = 6
    tsc.Parent = b

    -- ป้าย LOCKED เล็กๆ มุมขวาบน (ไม่แตะข้อความหลักของปุ่ม)
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

-- ปุ่มยิงเล็กลงเล็กน้อย / ปุ่มอื่นสั้นลง  เรียงลงมาทางขวาของจอ
local ShootFloat = MakeFloat("SHOOT", 1.00, UDim2.new(1, -12, 0.30, 0), ShootMurderer, true)
ModeFloat        = MakeFloat(ModeText(),       0.90, UDim2.new(1, -12, 0.42, 0), ToggleShootMode)
local KillFloat  = MakeFloat("KILL ALL",       0.90, UDim2.new(1, -12, 0.54, 0), function() KillAll(false) end)
local GunFloat   = MakeFloat("GRAB GUN",       0.90, UDim2.new(1, -12, 0.66, 0), GrabGun)
RefreshFloat()

-- ============================================================
-- FPS Boost (สวิตช์เดียว ลดทุกอย่างที่กิน FPS ในครั้งเดียว)
--   แมพ     : วัสดุเรียบ, ปิดเงา, ซ่อน Decal/Texture, ล้างเท็กซ์เจอร์ Mesh,
--             RenderFidelity ต่ำสุด, ปิด Particle/Trail/Beam และไฟ (Point/Spot/Surface)
--   แสงโลก  : ปิดเงาโลก, ปิด PostEffect ทุกตัว, หมอก/เมฆ/หญ้า/คลื่นน้ำ, แสงสะท้อนสิ่งแวดล้อม
--   ผู้เล่น : ซ่อนหมวก/เครื่องแต่งตัวและเงาของผู้เล่นอื่น (ESP ยังเห็นปกติ)
--   เรนเดอร์: Quality ต่ำสุด, MeshPart detail ต่ำสุด, ปลดล็อก FPS cap
-- ============================================================
local FPS = {
    on = false,
    orig = setmetatable({}, { __mode = "k" }),   -- ค่าเดิมของแต่ละ Instance
    light = {},                                   -- ค่าเดิมของ Lighting/Terrain/อื่นๆ
    render = nil,
    token = 0,
    conn = nil,
}

-- คืนผู้เล่นเจ้าของตัวละครที่ inst อยู่ข้างใน (ถ้าไม่ใช่ส่วนของตัวละครคืน nil)
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

local function ApplyInst(inst)
    if not FPS.on then return end

    -- เอฟเฟกต์และไฟ: กินแรงที่สุด
    if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Smoke") or inst:IsA("Fire") or inst:IsA("Sparkles")
        or inst:IsA("Light") or inst:IsA("Highlight")
        or inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
        RSet(inst, "Enabled", false)
        return
    end

    -- เอฟเฟกต์เล็กๆ: ระเบิด / โล่ ForceField / กรอบเลือกของเกม
    if inst:IsA("Explosion") or inst:IsA("ForceField")
        or inst:IsA("SelectionBox") or inst:IsA("SelectionSphere") then
        RSet(inst, "Visible", false)
        return
    end

    if inst:IsA("Decal") or inst:IsA("Texture") then
        if CharOwner(inst) ~= LP then RSet(inst, "Transparency", 1) end
        return
    end

    if inst:IsA("SpecialMesh") then
        if CharOwner(inst) ~= LP then RSet(inst, "TextureId", "") end
        return
    end

    if inst:IsA("BasePart") then
        local owner = CharOwner(inst)
        if owner then
            -- ผู้เล่นคนอื่น: ปิดเงา + ซ่อนเครื่องแต่งตัว (ตัวเราไม่แตะ)
            if owner ~= LP then
                RSet(inst, "CastShadow", false)
                if inst.Parent and inst.Parent:IsA("Accessory") then
                    RSet(inst, "Transparency", 1)
                end
            end
            return
        end
        if inst:IsA("Terrain") then return end
        RSet(inst, "Material", Enum.Material.SmoothPlastic)
        RSet(inst, "Reflectance", 0)
        RSet(inst, "CastShadow", false)
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

-- ค่าระดับโลก (Lighting / Terrain / Atmosphere / Rendering)
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
    if setfpscap then
        pcall(setfpscap, 999)
        if FPS.render then FPS.render.cap = true end
    end
end

local function RestoreRender()
    if FPS.render then
        local saved = FPS.render
        FPS.render = nil
        pcall(function() settings().Rendering.QualityLevel = saved.q end)
        if saved.m ~= nil then
            pcall(function() settings().Rendering.MeshPartDetailLevel = saved.m end)
        end
        if saved.cap and setfpscap then pcall(setfpscap, 60) end
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
                -- รอให้ตัวละครผูกกับผู้เล่นก่อน จะได้แยกของผู้เล่นออกจากแมพถูก
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
    S.SilentAim, S.ESP, S.DropESP, S.AutoKill = false, false, false, false
    for _, c in ipairs(Conns) do pcall(function() c:Disconnect() end) end
    DestroyAllESP()
    ClearTracers()
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
    env.MM2HubUnload = nil
end
env.MM2HubUnload = Unload

-- ============================================================
-- UI (ประกาศเป็นข้อมูลครั้งเดียว แล้วแสดงด้วย WindUI หรือ UI สำรอง)
-- ============================================================
local function Diag()
    local gun = LP.Character and LP.Character:FindFirstChild("Gun")
    local drops = 0
    for _ in pairs(DropInsts) do drops = drops + 1 end
    return string.format(
        "roles: %s | hook: %s | args ปืน: %s | args มีด: %s | Gun.Shoot: %s | มีด: %s | GunDrop: %d",
        RoleSource, HookOK and "ok" or "ไม่รองรับ",
        S.GunTpl and "มี" or "ยังไม่มี",
        next(KnifeTpl) and "มี" or "ยังไม่มี",
        (gun and gun:FindFirstChild("Shoot")) and "พบ" or "ไม่ได้ถือปืน",
        HasKnife() and "มี" or "ไม่มี",
        drops)
end

local Spec = {
    { name = "ESP", icon = "eye", items = {
        { "toggle", "ESP ผู้เล่น (แบ่งบทบาท)", "เห็นทะลุกำแพง แยกสีตาม role", false, function(v) S.ESP = v; if not v then DestroyAllESP() end end },
        { "toggle", "แสดง Murderer", nil, true, function(v) S.ShowMurderer = v end },
        { "toggle", "แสดง Sheriff / Hero", nil, true, function(v) S.ShowSheriff = v end },
        { "toggle", "แสดง Innocent", nil, true, function(v) S.ShowInnocent = v end },
        { "toggle", "แสดงชื่อ", nil, true, function(v) S.ShowName = v end },
        { "toggle", "แสดงระยะ", nil, true, function(v) S.ShowDist = v end },
        { "slider", "ระยะ ESP คนทั่วไป (studs)", 100, 3000, 2000, 50, function(v) S.ESPMax = v end },
        { "toggle", "เส้นนำทางไปหา Murderer / Sheriff", "เส้นจากกลางล่างจอไปหาตัวสำคัญ (ต้องใช้ executor ที่รองรับ Drawing)", false, function(v)
            S.Tracer = v
            if v and not DrawOK then Notify("Tracer", "executor นี้ไม่รองรับ Drawing") end
        end },
        { "toggle", "ESP ปืนที่ดรอป", "ไฮไลต์ GunDrop ให้เห็นทั่วแมพ", false, function(v)
            S.DropESP = v
            if v then ShowDropESP() else ClearDropESP() end
        end },
    } },
    { name = "มือปืน", icon = "crosshair", items = {
        { "button", "สลับโหมดยิง (โหมด 1 / โหมด 2)", "โหมด 1 ยิงไม่ทะลุ (ต้องไม่มีกำแพงบัง) / โหมด 2 ยิงทะลุกำแพง", ToggleShootMode },
        { "toggle", "Silent Aim (ปุ่มยิงปกติของเกม)", "กดยิงตามปกติ กระสุนถูกเปลี่ยนไปที่ hitbox ฆาตกร", false, function(v) S.SilentAim = v end },
        { "dropdown", "จุดเล็ง", { "Torso", "Head" }, "Torso", function(v) S.AimPart = v end },
        { "slider", "ชดเชยการเคลื่อนที่ (ms)", 0, 300, 80, 10, function(v) S.PredictMs = v end },
        { "dropdown", "รูปแบบ args (ใช้เมื่อยังไม่เคยยิงเอง)", { "CFrame, CFrame", "Vector3 (เป้า)", "Vector3 (ต้นทาง, เป้า)" }, "CFrame, CFrame", function(v) S.ArgMode = v end },
        { "button", "ยิงฆาตกรทันที", nil, function() task.spawn(ShootMurderer) end },
    } },
    { name = "ฆาตกร", icon = "skull", items = {
        { "button", "ฆ่าทั้งแมพ (วาปไปหา hitbox)", "วาปไปทีละคน ใกล้สุดก่อน", function() task.spawn(KillAll, false) end },
        { "toggle", "ฆ่าอัตโนมัติ (วนซ้ำ)", "เริ่มเองทุกครั้งที่ถือมีดและมีคนรอด", false, function(v) S.AutoKill = v end },
        { "button", "หยุดฆ่า", nil, function() KillCancel = true end },
        { "slider", "หน่วงต่อครั้ง (ms)", 100, 1000, 250, 50, function(v) S.KillDelay = v end },
        { "slider", "ลองซ้ำต่อเป้า (ครั้ง)", 1, 5, 3, 1, function(v) S.KillRetries = v end },
        { "toggle", "กลับตำแหน่งเดิมหลังเสร็จ", nil, true, function(v) S.KillReturn = v end },
    } },
    { name = "ปุ่มลอย", icon = "mouse-pointer-click", items = {
        { "toggle", "ปุ่มลอย SHOOT (สี่เหลี่ยมเล็ก)", "กดแล้วยิงฆาตกรทันที", false, function(v) S.ShootBtn = v; ShootFloat.btn.Visible = v end },
        { "toggle", "ปุ่มลอย MODE (สลับโหมดยิง)", "กดสลับ MODE 1: NORMAL / MODE 2: WALL ข้อความบนปุ่มบอกโหมดปัจจุบัน", false, function(v) S.ModeBtn = v; ModeFloat.btn.Visible = v end },
        { "toggle", "ปุ่มลอย KILL ALL", nil, false, function(v) S.KillBtn = v; KillFloat.btn.Visible = v end },
        { "toggle", "ปุ่มลอย GRAB GUN", "ส่ง hitbox ไปแตะปืนดรอปที่ใกล้สุด ตัวละครไม่วาป", false, function(v) S.GunBtn = v; GunFloat.btn.Visible = v end },
        { "toggle", "ถ้าไม่ติด ให้วาปตัวละครไปช่วย", "ปิดไว้เป็นค่าเริ่มต้น: ปกติส่งแค่ hitbox ไปแตะปืน ตัวละครไม่ขยับ", false, function(v) S.GrabTeleport = v end },
        { "toggle", "ล็อกตำแหน่งปุ่มลอย", "กันลากโดนตอนกด (ขอบปุ่มเป็นสีเขียวและขึ้นป้าย LOCKED)", false, function(v) S.LockBtn = v; RefreshFloat() end },
        { "slider", "ขนาดปุ่มยิง (สี่เหลี่ยม)", 36, 110, 64, 2, function(v) S.ShootSize = v; RefreshFloat() end },
        { "slider", "ความยาวปุ่มอื่น", 90, 240, 140, 10, function(v) S.BtnSize = v; RefreshFloat() end },
        { "button", "รีเซ็ตตำแหน่งปุ่ม", nil, function()
            for _, e in ipairs(FloatList) do e.btn.Position = e.defaultPos end
        end },
    } },
    { name = "FPS", icon = "zap", items = {
        { "toggle", "FPS Boost (สุดแรง)", "รวมทุกอย่างในสวิตช์เดียว: ลดกราฟิกแมพ ปิดเงา/แสง/เอฟเฟกต์ ซ่อนเครื่องแต่งตัวผู้เล่นอื่น ปลดล็อก FPS", false, function(v) FPS.on = v; RefreshFPS() end },
        { "toggle", "แสดงตัวเลข FPS", nil, false, function(v) FpsLabel.Visible = v end },
    } },
    { name = "อื่นๆ", icon = "settings", items = {
        { "toggle", "Debug: พิมพ์ args ที่เกมยิง/แทง (F9)", "ยิงหรือแทงเองสักครั้ง สคริปต์จะเรียนรู้รูปแบบ args", false, function(v) S.Debug = v end },
        { "button", "ตรวจสอบระบบ", "ดูว่า role / hook / args / GunDrop ใช้งานได้ไหม", function() Notify("สถานะระบบ", Diag() .. " | โหมดยิง: " .. S.ShootMode) end },
        { "button", "ปิดสคริปต์ (Unload)", "ล้างทุกอย่างและคืนค่ากราฟิก", function() Unload() end },
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
            Title = "MM2 HUB",
            Icon = "swords",
            Author = "v8",
            Folder = "MM2HubV8",
            Size = UDim2.fromOffset(580, 460),
            Theme = "Dark",
            Resizable = true,
            HideSearchBar = true,
        })
    end)
    if not ok or not Window then return false end
    WindowObj, WindRef = Window, WindUI
    pcall(function() Window:SetToggleKey(Enum.KeyCode.RightShift) end)
    pcall(function()
        Window:EditOpenButton({
            Title = "MM2 HUB", Icon = "swords", CornerRadius = UDim.new(0, 16),
            StrokeThickness = 2, Draggable = true,
            Color = ColorSequence.new(Color3.fromRGB(48, 255, 106), Color3.fromRGB(231, 255, 47)),
        })
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

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundTransparency = 1
    title.Text = "MM2 HUB (UI สำรอง) - ลากเพื่อย้าย"
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
        Notify("MM2 HUB", "โหลด WindUI ไม่ได้ ใช้ UI สำรองแทน")
    else
        Notify("MM2 HUB v8", "โหลดสำเร็จ (RightShift = ซ่อน/แสดงเมนู)")
    end
end)

print("[MM2Hub] v8 loaded | hook: " .. (HookOK and "ok" or "unsupported"))
