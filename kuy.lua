--[[
    NGO PORN HUB V1  (ไฟล์เดียว รวมทุกอย่าง)
    UI: WindUI  (ถ้าโหลดไม่ได้จะสลับไปใช้ UI สำรองในตัวอัตโนมัติ)

    ฟีเจอร์
      - ESP แบบรวม (สวิตช์เดียว): ผู้เล่นแยกบทบาท + ชื่อ/ระยะ/อาวุธ + ปืนที่ดรอป
      - มือปืน 2 โหมด:  1) ยิงปกติ (ไม่มีกำแพงบัง)
                         2) ยิงทะลุกำแพง (กระสุนวาปไปติด hitbox ฆาตกร)
      - ฆาตกร: ฆ่าทั้งแมพ วาปไปหา hitbox ทีละคน
      - ฆาตกร: โยนมีด (มีดวาปไปที่ hitbox ของผู้เล่นที่ใกล้เส้นเล็งที่สุด)
      - ปุ่มลอย: ยิง / โหมด / โยนมีด / เก็บปืน (เก็บปืนที่ดรอป)
        ล็อกตำแหน่ง ปรับขนาด รีเซ็ตตำแหน่ง
      - FPS Boost (ลบเท็กซ์เจอร์/เสื้อผ้า/เอฟเฟกต์ ตัวละครและพื้นเป็นสีเทา)
]]

local env = (getgenv and getgenv()) or _G
if env.NGOPornHubUnload then pcall(env.NGOPornHubUnload) end

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

-- โหมดยิงของมือปืน
local MODE_1 = "โหมด 1: ปกติ (ไม่มีกำแพงบัง)"
local MODE_2 = "โหมด 2: ยิงทะลุกำแพง (กระสุนวาปไปติด hitbox)"

local S = {
    ESP = false,
    -- มือปืน
    ShootMode = MODE_1, AimPart = "Torso",
    ArgMode = "CFrame, CFrame",
    -- ปุ่มลอย
    ShootBtn = false, ModeBtn = false, ThrowBtn = false, GunBtn = false, LockBtn = false, BtnSize = 140, ShootSize = 64,
    -- ฆาตกร
    KillDelay = 250, KillRetries = 3, KillReturn = true,
    AutoKill = false,   -- ฆ่าอัตโนมัติขณะถือมีด (ไม่วาป)
    FlingMurd = false, FlingSheriff = false, FlingAll = false,   -- Walkfling
    AimbotOn = false, AimbotPart = "Head", AimbotPower = 60,
    AimbotNeedGun = true,   -- Aimbot
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
-- ระบบ Role (อ่านจากข้อมูลที่เกมส่งมา ไม่ได้เดาจาก Backpack)
-- ============================================================
local RoleCache = {}
local RoleSource = "ดูจากของที่ถือ"

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
    Murderer = "[ ฆาตกร ]", Sheriff = "[ มือปืน ]", Hero = "[ ฮีโร่ ]",
    Innocent = "ผู้บริสุทธิ์", Unknown = "?",
}

local KeyRole = { Murderer = true, Sheriff = true, Hero = true }   -- ตัวสำคัญ: เด่นและชัดเสมอ

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

        -- บรรทัดบน: role + อาวุธที่ถือ
        local l1 = Instance.new("TextLabel")
        l1.BackgroundTransparency = 1
        l1.Size = UDim2.new(1, 0, 0, 20)
        l1.Font = Enum.Font.GothamBlack
        l1.TextSize = 14
        l1.TextStrokeTransparency = 0.25
        l1.Parent = bb

        -- บรรทัดล่าง: ชื่อ | ระยะ
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

                -- ตั้งสีเฉพาะตอน role เปลี่ยน (ลดงานต่อรอบ)
                if o.role ~= role then
                    o.role = role
                    local col = RoleColor[role] or RoleColor.Unknown
                    o.hl.FillColor = col
                    o.hl.OutlineColor = col
                    o.l1.TextColor3 = col
                    o.hl.FillTransparency = (role == "Murderer" and 0.4) or (key and 0.5) or 0.78
                end

                -- คนทั่วไปที่อยู่ไกลจะจางและเล็กลง ตัวสำคัญชัดเสมอ
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
                if item then t1 = t1 .. "  (" .. (item == "Knife" and "มีด" or "ปืน") .. ")" end
                local t2 = plr.DisplayName
                if myHrp then t2 = t2 .. "  |  " .. string.format("%d ม.", dist) end
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
-- ปืนที่ดรอป (GunDrop): ติดตามตลอด + ESP (เปิด/ปิดได้) + ใช้กับปุ่มเก็บปืน
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
    tl.Text = "ปืนดรอป"
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

-- อัปเดตระยะบนป้ายปืนดรอป
task.spawn(function()
    while Alive do
        local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if myHrp then
            for _, o in pairs(DropObjs) do
                if o.part and o.part.Parent and o.tl then
                    o.tl.Text = string.format("ปืนดรอป\n%d ม.", (o.part.Position - myHrp.Position).Magnitude)
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

-- เปลี่ยนตำแหน่งปลายทาง (ตำแหน่งตัวสุดท้ายใน args) ให้เป็นเป้า
-- ถ้ามี origin และมีตำแหน่ง >= 2 ตัว ตัวแรกจะกลายเป็นต้นทางกระสุน
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

-- วัดความเร็วเป้าเองจากตำแหน่งจริงทุกเฟรม (แม่นกว่า AssemblyLinearVelocity ของตัวละครคนอื่น)
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
                    if v.Magnitude > 120 then v = Vector3.zero end   -- วาป / รีสปอว์น
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

-- ความหน่วงเน็ต (วินาที) ใช้ชดเชยที่เซิร์ฟเวอร์เห็นเป้าล้ำหน้ากว่าที่เราเห็น
local function PingLead()
    local ok, ping = pcall(function() return LP:GetNetworkPing() end)
    if not ok or type(ping) ~= "number" then return 0 end
    return math.clamp(ping, 0, 0.25)
end

-- คืนระยะที่เป้าจะเคลื่อนไปใน `lead` วินาที (จำกัดไม่เกิน maxDist เพื่อไม่ให้จุดเล็งหลุดตัวเป้า)
-- ยืนบนพื้นให้ตัดแกน Y / ถ้าถูกวาปหรือถูกเหวี่ยง ไม่ชดเชย
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

-- โหมด 1: เช็คว่ามีกำแพง/วัตถุในแมพบังระหว่างเรากับเป้าไหม (ผู้เล่นไม่นับ)
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

-- เช็คว่ากระสุนจาก from -> to จะโดนผู้เล่นคนอื่นไหม (ที่ไม่ใช่ฆาตกร / ไม่ใช่เรา)
-- ครอบคลุมกรณีต้นทางหรือจุดเล็งอยู่ในตัวผู้เล่นคนอื่นด้วย
local ShotTry = 0   -- นัดที่เท่าไรของการกดครั้งนี้ (ใช้สลับจุดเล็งเมื่อพลาด)

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
        -- Spherecast รัศมี 0.3 เผื่อระยะรอบเส้นกระสุน (ถ้าไม่รองรับจะใช้ Raycast แทน)
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

-- โหมด 2: วางต้นทางกระสุนห่างจาก hitbox แค่ ~2 studs (ไม่มีอะไรมาคั่น)
local function NearOrigin(myPos, targetPos)
    local dir = myPos - targetPos
    if dir.Magnitude < 3 then return myPos end
    return targetPos + dir.Unit * 1.5
end

-- คำนวณการยิง: คืน origin, point  (origin = nil แปลว่าใช้ต้นทางเดิมของเกม)
--   โหมด 1: ลองลำตัว/หัว/ช่วงล่างตามลำดับ เลือกจุดแรกที่มองเห็นจริงและไม่มีกำแพงบัง
--   โหมด 2: เล็งกลาง hitbox (ชดเชย ping จำกัด 1 stud) และวางต้นทางกระสุนบน hitbox (ทะลุกำแพง)
--   ถ้าโหมด 1 ถูกบังทุกจุด จะคืน nil, nil, "blocked"
local function ComputeShot(target, myHrp)
    local char = target.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil, "nochar" end
    local head = char:FindFirstChild("Head")
    local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    local lower = char:FindFirstChild("LowerTorso")
    local ping = PingLead()

    if S.ShootMode == MODE_2 then
        -- ยิงทะลุ: เล็งกลาง hitbox + ชดเชย ping จำกัดไม่เกิน 1 stud ให้จุดเล็งอยู่ในตัวเป้าเสมอ
        local off2 = PredictOffset(target, char, ping + 0.05, 1.8)
        local pts = {}
        if S.AimPart == "Head" and head then pts[#pts + 1] = head.Position end
        pts[#pts + 1] = hrp.Position
        if torso then pts[#pts + 1] = torso.Position end
        if lower then pts[#pts + 1] = lower.Position end
        if head and S.AimPart ~= "Head" then pts[#pts + 1] = head.Position end

        -- ถ้านัดก่อนพลาด ให้สลับจุดเล็งหลัก (กลาง/อก/ช่วงล่าง) จะได้ไม่ยิงเส้นเดิมซ้ำ
        local n = math.min(#pts, 3)
        local rot = ShotTry % n
        if rot > 0 then
            local r = {}
            for i = 1, n do r[i] = pts[(i - 1 + rot) % n + 1] end
            for i = n + 1, #pts do r[i] = pts[i] end
            pts = r
        end

        -- กระสุนวาปไปที่ hitbox ฆาตกร: ลองต้นทางจากใกล้สุดแล้วไล่ออกไปเป็นขั้นๆ (0.5 -> 2.5 studs)
        -- หลายทิศรอบจุดเล็ง เลือกชุดแรกที่เส้นกระสุน + ต้นทาง + จุดเล็ง ไม่แตะ hitbox ของใครนอกจากฆาตกร
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

    -- โหมด 1: ลองจุดต่างๆ ของตัว เลือกจุดแรกที่ไม่มีกำแพงบัง (เริ่มจากส่วนที่ hitbox ใหญ่สุด)
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

-- คำนวณใหม่จากตำแหน่งล่าสุดแล้วยิง 1 นัด
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
        Notify("ยิงไม่ได้", "คุณไม่มีปืน (ต้องเป็นมือปืน / ฮีโร่)")
        return
    end

    local shoot = gun:FindFirstChild("Shoot")
    if not (shoot and shoot:IsA("RemoteEvent")) then
        Notify("ยิงไม่ได้", "ไม่พบ Remote 'Shoot' ในปืน")
        return
    end

    ShotTry = 0
    local ok, why = FireShotOnce(shoot, target, myHrp)
    if not ok then
        if why == "blocked" then
            Notify("ยิงไม่ได้ (โหมด 1)", "มีกำแพงหรือผู้เล่นคนอื่นบังทุกจุดของฆาตกร สลับเป็นโหมด 2 ถ้าต้องการยิงทะลุกำแพง")
        elseif why == "crowded" then
            Notify("ยิงไม่ได้ (โหมด 2)", "มีผู้เล่นคนอื่นอยู่รอบฆาตกร ทำให้ยิงเฉพาะฆาตกรไม่ได้ ลองอีกครั้ง")
        end
        return
    end

    -- เช็คผล: ถ้ายังไม่ตายใน 0.5 วิ ให้ยิงซ้ำจากตำแหน่งล่าสุด (สูงสุด 2 ครั้ง ถ้าปืนยังอยู่ในมือ)
    task.spawn(function()
        for _ = 1, 5 do
            task.wait(0.4)
            if not Alive then return end
            local c = target.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            if (not h) or h.Health <= 0 or GetRole(target) == "Dead" then
                Notify("ยิงโดน", "ฆาตกรตายแล้ว")
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
    if not firetouchinterest then
        Notify("เก็บปืนไม่ได้", "executor นี้ไม่รองรับ firetouchinterest (ต้องใช้ส่ง hitbox ไปแตะปืน)")
        return
    end

    Grabbing = true
    local t0 = os.clock()
    local done = false
    local links = {}

    -- รู้ทันทีเมื่อปืนเข้ากระเป๋า/ตัวละคร
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

    local got = done or HasGun()
    for _, l in ipairs(links) do pcall(function() l:Disconnect() end) end
    Grabbing = false
    if got then
        Notify("เก็บปืน", string.format("เก็บปืนสำเร็จ (%.2f วิ)", os.clock() - t0))
    else
        Notify("เก็บปืน", "ส่ง hitbox ไปแตะปืนแล้วแต่เซิร์ฟเวอร์ไม่รับ (เกมอาจเช็คระยะ)")
    end
end

-- ============================================================
-- ฆาตกร: ฆ่าทั้งแมพ วาปไปหา hitbox ทีละคน
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
        if not silent then Notify("ฆ่าไม่ได้", "คุณไม่มีมีด (ต้องเป็นฆาตกร)") end
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
        Notify("ฆ่าทั้งแมพ", string.format("เสร็จแล้ว: %d / %d", killed, total))
    end
end

-- โยนมีด: เลือกผู้เล่นที่ใกล้เส้นกล้องที่สุด แล้วส่งมีดไปที่ hitbox
local ThrowBusy = false
local ThrowLock = nil      -- ผู้เล่นเป้าที่ล็อกไว้ (มีดทุกเล่มพุ่งไปหาคนนี้จนกว่าจะตาย/ออก/ปลดล็อก)
local ThrowFloat = nil

local function UpdateThrowText()
    if ThrowFloat then
        ThrowFloat.btn.Text = ThrowLock and ("โยน > " .. ThrowLock.Name) or "โยนมีด"
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
        Notify("โยนมีดไม่ได้", "คุณไม่มีมีด (ต้องเป็นฆาตกร)")
        return
    end
    ThrowBusy = true

    -- ล็อกเป้า: ถ้าเป้าที่ล็อกไว้ยังอยู่และยังไม่ตาย ให้ใช้คนเดิม ไม่งั้นเลือกคนใหม่แล้วล็อก
    if ThrowLock and not (ThrowLock.Parent and IsAlive(ThrowLock) and GetRole(ThrowLock) ~= "Dead") then
        SetThrowLock(nil)
    end
    if not ThrowLock then SetThrowLock(PickThrowTarget(myHrp.Position)) end
    local plr = ThrowLock
    local vChar = plr and plr.Character
    local vHrp = vChar and vChar:FindFirstChild("HumanoidRootPart")
    local knife = GetKnife(char, hum)
    if not (vHrp and knife) then
        Notify("โยนมีดไม่ได้", vHrp and "ถือมีดไม่ได้" or "ไม่พบผู้เล่นเป้าหมาย")
        ThrowBusy = false
        return
    end

    local ev = knife:FindFirstChild("Events")
    local handle = knife:FindFirstChild("Handle")

    -- Remote โยนมีดของเกม: Knife.Events.KnifeThrown (args: origin CFrame, target CFrame)
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
        Notify("โยนมีดไม่ได้", "ไม่พบ Remote โยนมีด (KnifeThrown)")
        ThrowBusy = false
        return
    end

    -- เก็บลูกมีดที่เกมสร้างตอนโยน (projectile) เพื่อวาปไปที่ hitbox เป้า (ตัวละครเราไม่วาป)
    local projs = {}
    local pc = Workspace.DescendantAdded:Connect(function(d)
        pcall(function()
            if d:IsA("BasePart") and string.find(string.lower(d.Name), "knife", 1, true) then
                local m = d:FindFirstAncestorOfClass("Model")
                if not (m and Players:GetPlayerFromCharacter(m)) then projs[#projs + 1] = d end
            end
        end)
    end)

    -- โยนมีด: ต้นทางมีดอยู่ติด hitbox เป้า (ห่างแค่ ~1.5 studs ไม่มีอะไรคั่น)
    -- เป้าคือกลาง hitbox ส่วนตัวละครเราอยู่ที่เดิม
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

    -- ตามเป้าช่วงสั้นๆ: ดึงลูกมีดไปที่ hitbox ทุกก้าวและแตะ hitbox ซ้ำ
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
        Notify("โยนมีด", "โดน " .. plr.Name)
        SetThrowLock(nil)
    else
        Notify("โยนมีด", "ล็อกเป้า " .. plr.Name .. " (กดอีกครั้งเพื่อโยนซ้ำ)")
    end
    task.wait(0.1)
    ThrowBusy = false
end

-- ============================================================
-- ฆ่าอัตโนมัติ (สวิตช์): ขณะถือมีด ทุกคนที่ยังรอดจะถูกโจมตีทันที
--   ตัวละครเราอยู่ที่เดิม ไม่วาป ส่งคำสั่งแทง/แตะ/โยนไปที่ hitbox ของแต่ละคน
--   ต้อง "ถือมีดอยู่ในมือ" (สคริปต์จะไม่ถือให้)
-- ============================================================
local AutoKillStats = { last = 0, count = 0 }

local function AutoKillStep()
    if KillRunning or ThrowBusy then return end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and myHrp and hum.Health > 0) then return end

    local knife = char:FindFirstChild("Knife")        -- ต้องถืออยู่ในมือ
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
                -- 1) แทง / แตะ ผ่านคำสั่งของมีด
                pcall(FireKnife, ev, "KnifeStabbed", vChar, vHrp)
                pcall(FireKnife, ev, "HandleTouched", vChar, vHrp)
                -- 2) ให้มีดแตะ hitbox ของเป้าโดยตรง
                if firetouchinterest and handle then
                    pcall(function()
                        firetouchinterest(handle, vHrp, 0)
                        firetouchinterest(handle, vHrp, 1)
                    end)
                end
                -- 3) โยนมีดโดยให้ต้นทางอยู่ติด hitbox ของเป้า
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
-- Walkfling (สวิตช์แยก): ฆาตกร / มือปืน / ทั้งเซิร์ฟ
--   วาปไปเตะทีละเป้า พุ่งทะลุตัวเป้าด้วยแรงมหาศาล แล้ววาปกลับตอนจบรอบ
--   ปิดทุกสวิตช์จะหยุดทันที (ตัวละครเราจะถูกวาปไปมาระหว่างทำงาน)
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

-- ทำให้ตัวเราหนักที่สุดเท่าที่ทำได้ เพื่อให้แรงชนส่งไปที่เป้ามากที่สุด
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

-- วาปไปเตะ 1 เป้า: เข้าจากทิศที่เราเดินมา พุ่งทะลุตัวเป้าทุกเฟรมด้วยแรงมหาศาล (ทิศเตะ = พุ่งเข้าหาเป้า)
-- จนกว่าเป้าจะกระเด็นไกล (> 150 studs หรือเร็วมาก) หรือหมดเวลา
local function FlingOne(t, myHrp, char, home)
    local hum = char:FindFirstChildOfClass("Humanoid")
    local startPos = t.hrp.Position
    local t0 = os.clock()
    local i = 0
    local lunge = { -1.6, -0.6, 0.4, -1.0 }       -- ระยะพุ่งตามทิศเตะ สลับไปมาให้ชนแน่ๆ
    local thrust = Instance.new("BodyThrust")
    thrust.Force = Vector3.new(9e8, 9e8, 9e8)
    thrust.Location = myHrp.Position
    thrust.Parent = myHrp
    if hum then hum.PlatformStand = true end

    -- ขยาย hitbox (HumanoidRootPart) ระหว่างเตะให้ชนง่ายขึ้น (คืนค่าตอนจบ)
    if not FlingSt.size then
        FlingSt.hrp, FlingSt.size = myHrp, myHrp.Size
    end
    pcall(function() myHrp.Size = Vector3.new(7, 7, 7) end)

    while Alive and FlingOn() and os.clock() - t0 < 1.8 do
        local hrp = t.hrp
        if not (hrp.Parent and myHrp.Parent) then break end
        if (hrp.Position - startPos).Magnitude > 150 or hrp.AssemblyLinearVelocity.Magnitude > 500 then break end
        if hum and hum.Health <= 0 then break end

        -- ทิศเตะ: จากจุดเริ่มของเราไปหาเป้า (แนวราบ) อิงตำแหน่งล่าสุดของเป้า
        local dir = hrp.Position - home.Position
        dir = Vector3.new(dir.X, 0, dir.Z)
        if dir.Magnitude < 0.1 then dir = hrp.CFrame.LookVector end
        dir = dir.Unit

        i = i % #lunge + 1
        local pos = hrp.Position + dir * lunge[i]
        -- วาปทั้งตัวละคร (ทุกชิ้นส่วน) พร้อม hitbox
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
                    if FlingSt.char ~= char then FlingHeavy(char) end   -- ทำให้ตัวเราหนักที่สุด
                    local home = myHrp.CFrame
                    for _, t in ipairs(list) do
                        if not (Alive and FlingOn()) then break end
                        pcall(FlingOne, t, myHrp, char, home)
                    end
                    -- กลับที่เดิม: ตั้งตำแหน่งซ้ำหลายเฟรม กันตัวไหลจากแรงที่ค้าง
                    for _ = 1, 8 do
                        if not myHrp.Parent then break end
                        myHrp.AssemblyLinearVelocity = Vector3.zero
                        myHrp.AssemblyAngularVelocity = Vector3.zero
                        char:PivotTo(home)      -- วาปทั้งตัวละครกลับพร้อม hitbox
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
-- Aimbot (มือปืน): ล็อกกล้องไปที่ฆาตกรเท่านั้น (ไม่ล็อกคนอื่น)
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

    local plr = GetMurderer()                       -- ล็อกฆาตกรเท่านั้น
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
-- Hook: จับรูปแบบ args จริงของเกม
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
-- ปุ่มลอย (สี่เหลี่ยมสีดำ / ลากได้ / ล็อกตำแหน่งได้ / ปรับความยาวได้)
--   ขอบปุ่มใช้ UIStroke แบบ Border ตัวหนังสือจึงไม่เรืองแสง
-- ============================================================
local FloatList = {}
local ModeFloat = nil

local function ModeText()
    return S.ShootMode == MODE_2 and "โหมด 2: ทะลุ" or "โหมด 1: ปกติ"
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
    st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border   -- เฉพาะขอบปุ่ม ไม่แตะตัวหนังสือ
    st.Parent = b
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 7); pad.PaddingRight = UDim.new(0, 7)
    pad.PaddingTop = UDim.new(0, 5); pad.PaddingBottom = UDim.new(0, 5)
    pad.Parent = b
    local tsc = Instance.new("UITextSizeConstraint")
    tsc.MaxTextSize = 14; tsc.MinTextSize = 6
    tsc.Parent = b

    -- ป้ายล็อกเล็กๆ มุมขวาบน (ไม่แตะข้อความหลักของปุ่ม)
    local tag = Instance.new("TextLabel")
    tag.BackgroundTransparency = 1
    tag.AnchorPoint = Vector2.new(1, 0)
    tag.Position = UDim2.new(1, -3, 0, 0)
    tag.Size = UDim2.fromOffset(46, 9)
    tag.Font = Enum.Font.GothamBold
    tag.TextSize = 8
    tag.TextXAlignment = Enum.TextXAlignment.Right
    tag.TextColor3 = Color3.fromRGB(80, 255, 120)
    tag.Text = "ล็อกแล้ว"
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

-- ปุ่มยิงเล็กลงเล็กน้อย / ปุ่มอื่นสั้นลง เรียงลงมาทางขวาของจอ
local ShootFloat = MakeFloat("ยิง", 1.00, UDim2.new(1, -12, 0.30, 0), ShootMurderer, true)
ModeFloat        = MakeFloat(ModeText(),       0.90, UDim2.new(1, -12, 0.42, 0), ToggleShootMode)
ThrowFloat = MakeFloat("โยนมีด",     0.90, UDim2.new(1, -12, 0.54, 0), ThrowKnife)
local GunFloat   = MakeFloat("เก็บปืน",       0.90, UDim2.new(1, -12, 0.66, 0), GrabGun)
RefreshFloat()

-- ============================================================
-- FPS Boost (สวิตช์เดียว)
--   แมพ     : วัสดุเรียบ ปิดเงา ลบ Decal/Texture/SurfaceAppearance/เท็กซ์เจอร์ Mesh
--             ปิด Particle/Trail/Beam/ไฟ/Highlight และเอฟเฟกต์ทั้งหมด
--   พื้น    : พื้นแมพ + Terrain เป็นสีเทา
--   ตัวละคร : ทุกคน (รวมเรา) ไม่มีเสื้อผ้า/เครื่องแต่งตัว/ใบหน้า และตัวเป็นสีเทาล้วน
--   แสงโลก  : ปิดเงาโลก ปิด PostEffect ทั้งหมด หมอก/เมฆ/หญ้า/คลื่นน้ำ
--   เรนเดอร์: Quality ต่ำสุด รายละเอียด MeshPart ต่ำสุด
-- ============================================================
local GRAY = Color3.fromRGB(128, 128, 128)
local GRAY_FLOOR = Color3.fromRGB(110, 110, 110)

local FPS = {
    on = false,
    orig = setmetatable({}, { __mode = "k" }),   -- ค่าเดิมของแต่ละ Instance
    light = {},                                   -- ค่าเดิมของ Lighting/Terrain/อื่นๆ
    terrain = nil,                                -- สีวัสดุเดิมของ Terrain
    render = nil,
    token = 0,
    conn = nil,
}

-- คืนผู้เล่นเจ้าของตัวละครที่ inst อยู่ข้างใน (nil ถ้าไม่ใช่ส่วนของตัวละคร)
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

    -- เอฟเฟกต์ + ไฟทั้งหมด
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

    -- เสื้อผ้าและเครื่องแต่งตัวของตัวละคร
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

    -- Texture ทุกชนิด
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
            -- ตัวละครทุกคน: เป็นสีเทา ไม่มีเงา ซ่อนเครื่องแต่งตัว
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
        -- พื้น Terrain เป็นสีเทา
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
                -- รอให้ตัวละครผูกกับผู้เล่นก่อน จะได้แยกชิ้นส่วนของผู้เล่นออกจากแมพได้ถูก
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
-- UI (ประกาศเป็นข้อมูลครั้งเดียว แล้วแสดงด้วย WindUI หรือ UI สำรอง)
-- ============================================================
local function Diag()
    local gun = LP.Character and LP.Character:FindFirstChild("Gun")
    local drops = 0
    for _ in pairs(DropInsts) do drops = drops + 1 end
    return string.format(
        "บทบาท: %s | hook: %s | args ปืน: %s | args มีด: %s | Gun.Shoot: %s | มีด: %s | GunDrop: %d",
        RoleSource, HookOK and "ปกติ" or "ไม่รองรับ",
        S.GunTpl and "มี" or "ยังไม่มี",
        next(KnifeTpl) and "มี" or "ยังไม่มี",
        (gun and gun:FindFirstChild("Shoot")) and "พบ" or "ไม่ได้ถือปืน",
        HasKnife() and "มี" or "ไม่มี",
        drops)
end

-- ============================================================
-- พื้นหลังเมนู: 4 รูป (เลือกได้ในแท็บ อื่นๆ)
-- ============================================================
-- พื้นหลัง 1 = Texture 14751314324 (ใช้เป็นรูปได้ตรงๆ)
-- พื้นหลัง 2 = Asset (Decal) 14751314303 (ต้องแปลงเป็นรูปจริงก่อน ไม่งั้นจะไม่ขึ้น)
local BG_TEXTURE_ID = 14751314324
local BG_ASSET_ID = 14751314303
-- พื้นหลัง 3 และ 4: ลองหลาย url แล้วใช้อันแรกที่โหลดขึ้นจริง
--   texture -> asset -> Decal แปลงเป็นรูปจริง -> thumbnail rbxthumb (asset / texture)
--   เก็บ id เป็น string เพื่อไม่ให้เลขยาวกลายเป็นรูปแบบ scientific
local BG_EXTRA = {
    [3] = { tex = "130393160784262", asset = "134393565381500", state = "idle" },
    [4] = { tex = "90431130411810",  asset = "76524641175461",  state = "idle" },
}
local BG_IDS = {
    "rbxassetid://" .. BG_TEXTURE_ID, "rbxassetid://" .. BG_ASSET_ID,
    "rbxassetid://" .. BG_EXTRA[3].tex, "rbxassetid://" .. BG_EXTRA[4].tex,
}
local BG_NAMES = { ["พื้นหลัง 1"] = 1, ["พื้นหลัง 2"] = 2, ["พื้นหลัง 3"] = 3, ["พื้นหลัง 4"] = 4 }
local BgAssetResolved = false
local BG_ALPHA = 0.5          -- ความโปร่งใสของรูป (0 = ชัดสุด, 1 = มองไม่เห็น)
local BgIndex = 1
local FallbackBgImg = nil     -- ImageLabel ของเมนูสำรอง (ตั้งตอนสร้างเมนูสำรอง)

-- แปลง Decal asset เป็น image id จริง (อ่าน Texture ของ Decal ผ่าน GetObjects)
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

-- เช็คว่า url รูปโหลดขึ้นจริงไหม (รอได้สูงสุด `timeout` วินาที)
--   สำเร็จ = PreloadAsync รายงาน Success หรือ ImageLabel รายงาน IsLoaded
local function ImageLoads(url, timeout)
    local img = Instance.new("ImageLabel")
    img.Image = url
    local status = nil
    task.spawn(function()
        pcall(function()
            game:GetService("ContentProvider"):PreloadAsync({ img }, function(_, st) status = st end)
        end)
    end)
    local ok = false
    local t0 = os.clock()
    while os.clock() - t0 < (timeout or 6) do
        if status == Enum.AssetFetchStatus.Success then ok = true; break end
        if status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut then break end
        local loaded = false
        pcall(function() loaded = img.IsLoaded end)
        if loaded then ok = true; break end
        task.wait(0.1)
    end
    pcall(function() img:Destroy() end)
    return ok
end

local function SetBackgroundNow(id)
    if not id then return end
    if WindowObj then
        pcall(function() WindowObj:SetBackgroundImage(id) end)
        pcall(function() WindowObj:SetBackgroundImageTransparency(BG_ALPHA) end)
    end
    if FallbackBgImg then pcall(function() FallbackBgImg.Image = id end) end
end

-- พื้นหลัง 3 / 4: หา url ที่โหลดขึ้น ถ้าไม่มีอันไหนขึ้นให้คงพื้นหลังเดิม
local function ResolveExtraBackground(idx)
    local ex = BG_EXTRA[idx]
    ex.state = "loading"
    task.spawn(function()
        local candidates = {
            function() return "rbxassetid://" .. ex.tex end,
            function() return "rbxassetid://" .. ex.asset end,
            function() return ResolveDecalImage(ex.asset) end,
            function() return ResolveDecalImage(ex.tex) end,
            function() return "rbxthumb://type=Asset&id=" .. ex.asset .. "&w=420&h=420" end,
            function() return "rbxthumb://type=Asset&id=" .. ex.tex .. "&w=420&h=420" end,
        }
        local tried, found = {}, nil
        for _, getUrl in ipairs(candidates) do
            local ok, url = pcall(getUrl)
            if ok and type(url) == "string" and url ~= "" and not tried[url] then
                tried[url] = true
                if ImageLoads(url, 6) then found = url; break end
            end
        end
        if found then
            BG_IDS[idx] = found
            ex.state = "done"
            if BgIndex == idx then SetBackgroundNow(found) end
        else
            ex.state = "idle"   -- เลือกซ้ำอีกครั้งเพื่อลองใหม่
            Notify("พื้นหลัง " .. idx, "โหลดรูปไม่ได้ (รูปอาจเป็นส่วนตัว ถูกลบ หรือไม่ใช่ Image ID) คงพื้นหลังเดิมไว้")
        end
    end)
end

local function ApplyBackground(idx)
    BgIndex = idx
    local ex = BG_EXTRA[idx]
    if ex then
        if ex.state == "done" then
            SetBackgroundNow(BG_IDS[idx])
        elseif ex.state == "idle" then
            ResolveExtraBackground(idx)
        end
        return
    end
    -- พื้นหลัง 2 (Asset): แปลงเป็นรูปจริงตอนเลือกครั้งแรก แล้วค่อยตั้งรูป
    if idx == 2 and not BgAssetResolved then
        BgAssetResolved = true
        task.spawn(function()
            local img = ResolveDecalImage(BG_ASSET_ID)
            if img then BG_IDS[2] = img end
            if BgIndex == 2 then ApplyBackground(2) end
        end)
    end
    SetBackgroundNow(BG_IDS[idx])
end

local Spec = {
    { name = "ESP", icon = "eye", items = {
        { "toggle", "ESP (รวมทุกอย่าง)", "ผู้เล่นแยกบทบาท ฆาตกร / มือปืน / ฮีโร่ / ผู้บริสุทธิ์ พร้อมชื่อ ระยะ อาวุธที่ถือ + ปืนที่ดรอป", false, function(v)
            S.ESP = v
            if v then
                ShowDropESP()
            else
                DestroyAllESP()
                ClearDropESP()
            end
        end },
    } },
    { name = "มือปืน", icon = "crosshair", items = {
        { "button", "สลับโหมดยิง (โหมด 1 / โหมด 2)", "โหมด 1 ยิงปกติ (ไม่มีกำแพงบัง) / โหมด 2 ยิงทะลุกำแพง", ToggleShootMode },
        { "dropdown", "จุดเล็ง", { "ลำตัว", "หัว" }, "ลำตัว", function(v) S.AimPart = (v == "หัว") and "Head" or "Torso" end },
        { "dropdown", "รูปแบบ args (ใช้จนกว่าคุณจะยิงเองสักครั้ง)", { "CFrame, CFrame", "Vector3 (เป้า)", "Vector3 (ต้นทาง, เป้า)" }, "CFrame, CFrame", function(v) S.ArgMode = v end },
    } },
    { name = "เล็งอัตโนมัติ", icon = "target", items = {
        { "toggle", "Aimbot (ล็อกฆาตกร)", "ล็อกกล้องไปที่ฆาตกรเท่านั้น ไม่ล็อกผู้เล่นคนอื่น", false, function(v) S.AimbotOn = v end },
        { "dropdown", "จุดที่ล็อก", { "หัว", "ลำตัว" }, "หัว", function(v) S.AimbotPart = (v == "หัว") and "Head" or "Torso" end },
        { "slider", "ความแรงล็อก (%) 100 = ล็อกทันที", 5, 100, 60, 5, function(v) S.AimbotPower = v end },
        { "toggle", "ล็อกเฉพาะตอนถือปืน", nil, true, function(v) S.AimbotNeedGun = v end },
    } },
    { name = "ฆาตกร", icon = "skull", items = {
        { "button", "ฆ่าทั้งแมพ (วาปไปหา hitbox)", "วาปไปทีละคน เริ่มจากคนที่ใกล้สุด", function() task.spawn(KillAll, false) end },
        { "toggle", "ฆ่าอัตโนมัติ (ถือมีดแล้วทุกคนตาย ไม่วาป)", "เปิดสวิตช์แล้วถือมีดไว้ในมือ สคริปต์จะโจมตีทุกคนที่ยังรอดทันทีโดยที่คุณอยู่กับที่", false, function(v) S.AutoKill = v end },
        { "slider", "หน่วงต่อครั้ง (ms)", 100, 1000, 250, 50, function(v) S.KillDelay = v end },
        { "slider", "ลองซ้ำต่อเป้า (ครั้ง)", 1, 5, 3, 1, function(v) S.KillRetries = v end },
        { "toggle", "กลับตำแหน่งเดิมหลังเสร็จ", nil, true, function(v) S.KillReturn = v end },
    } },
    { name = "ปุ่มลอย", icon = "mouse-pointer-click", items = {
        { "toggle", "ปุ่มลอยยิง (สี่เหลี่ยมเล็ก)", "กดแล้วยิงฆาตกรทันที", false, function(v) S.ShootBtn = v; ShootFloat.btn.Visible = v end },
        { "toggle", "ปุ่มลอยโหมด (สลับโหมดยิง)", "กดสลับ โหมด 1: ปกติ / โหมด 2: ทะลุ ข้อความบนปุ่มบอกโหมดปัจจุบัน", false, function(v) S.ModeBtn = v; ModeFloat.btn.Visible = v end },
        { "toggle", "ปุ่มลอยโยนมีด", "กดเพื่อล็อกผู้เล่นที่ใกล้เส้นเล็งที่สุด มีดจะวาปไปที่ hitbox ส่วนตัวละครของคุณอยู่กับที่ (ฆาตกรเท่านั้น)", false, function(v) S.ThrowBtn = v; ThrowFloat.btn.Visible = v end },
        { "toggle", "ปุ่มลอยเก็บปืน", "ส่ง hitbox ของคุณไปแตะปืนที่ดรอปใกล้สุด ตัวละครของคุณอยู่กับที่", false, function(v) S.GunBtn = v; GunFloat.btn.Visible = v end },
        { "toggle", "ล็อกตำแหน่งปุ่มลอย", "กันลากโดนตอนกด (ขอบปุ่มเป็นสีเขียวและขึ้นป้าย ล็อกแล้ว)", false, function(v) S.LockBtn = v; RefreshFloat() end },
        { "slider", "ขนาดปุ่มยิง (สี่เหลี่ยม)", 36, 110, 64, 2, function(v) S.ShootSize = v; RefreshFloat() end },
        { "slider", "ความยาวปุ่มอื่น", 90, 240, 140, 10, function(v) S.BtnSize = v; RefreshFloat() end },
        { "button", "รีเซ็ตตำแหน่งปุ่ม", nil, function()
            for _, e in ipairs(FloatList) do e.btn.Position = e.defaultPos end
        end },
    } },
    { name = "FPS", icon = "zap", items = {
        { "toggle", "FPS Boost (สุดแรง)", "ลบเท็กซ์เจอร์/เสื้อผ้า/เอฟเฟกต์ทั้งหมด ตัวละครทุกคนและพื้นเป็นสีเทา ปิดเงา/แสง", false, function(v) FPS.on = v; RefreshFPS() end },
        { "toggle", "แสดงตัวเลข FPS", nil, false, function(v) FpsLabel.Visible = v end },
    } },
    { name = "เหวี่ยง (Fling)", icon = "wind", items = {
        { "label", "คำเตือน: ยังมีบัก", "ใช้งานยาก Walkfling ยังอยู่ระหว่างปรับปรุง" },
        { "toggle", "Walkfling ฆาตกร", "วาปทั้งตัวละครพร้อม hitbox ไปเตะฆาตกรให้กระเด็นไกล แล้วกลับที่เดิม", false, function(v) S.FlingMurd = v end },
        { "toggle", "Walkfling มือปืน", "วาปทั้งตัวละครพร้อม hitbox ไปเตะคนที่ถือปืน (มือปืน / ฮีโร่)", false, function(v) S.FlingSheriff = v end },
        { "toggle", "Walkfling ทั้งเซิร์ฟเวอร์", "วาปทั้งตัวละครพร้อม hitbox ไปเตะทุกคนที่ยังรอดทีละคน", false, function(v) S.FlingAll = v end },
    } },
    { name = "อื่นๆ", icon = "settings", items = {
        { "dropdown", "พื้นหลังเมนู", { "พื้นหลัง 1", "พื้นหลัง 2", "พื้นหลัง 3", "พื้นหลัง 4" }, "พื้นหลัง 1", function(v) ApplyBackground(BG_NAMES[v] or 1) end },
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
    -- ปุ่มเปิดเมนู: สีรุ้งที่วนเปลี่ยนไปเรื่อยๆ
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

    -- รูปพื้นหลังของเมนูสำรอง (อยู่หลังปุ่มทั้งหมด)
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
    title.Text = "NGO PORN HUB (UI สำรอง) - ลากเพื่อย้าย"
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
                local b = btn((state and "[เปิด] " or "[ปิด]  ") .. it[2])
                b.MouseButton1Click:Connect(function()
                    state = not state
                    b.Text = (state and "[เปิด] " or "[ปิด]  ") .. it[2]
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
        Notify("NGO PORN HUB", "โหลด WindUI ไม่ได้ ใช้ UI สำรองแทน")
    else
        Notify("NGO PORN HUB V1", "โหลดสำเร็จ (RightShift = ซ่อน/แสดงเมนู)")
    end
end)

print("[NGOPornHub] V1 โหลดแล้ว | hook: " .. (HookOK and "ปกติ" or "ไม่รองรับ"))
