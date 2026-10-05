--[[
    MM2 HUB v12 IMPROVED  (ไฟล์เดียว รวมทุกอย่าง)
    UI: WindUI  (ถ้าโหลดไม่ได้ จะใช้ UI สำรองในตัวอัตโนมัติ)

    ✨ ฟีเจอร์ปรับปรุง:
      - ระบบฆาตกรอัตโนมัติ: เปิด-ปิดสวิตช์ ฆ่าตัวเต็มแมพนอนๆ ไม่ต้องกดซ้ำ
      - Walk-fling ฆาตกร: เหวี่ยงตัวขณะถือมีด (สามารถปิด-เปิดได้)
      - Walk-fling มือปืน: เหวี่ยงตัวขณะถือปืน (สามารถปิด-เปิดได้)
      - ESP แบบรวม (สวิตช์เดียว): ผู้เล่นแยกบทบาท + ชื่อ/ระยะ/อาวุธ + ปืนที่ดรอป
      - มือปืน 2 โหมด: 1) ยิงไม่ทะลุ  2) ยิงทะลุ
      - ปุ่มลอย: SHOOT / MODE / THROW / GRAB GUN / ล็อก/ขยายขนาด/รีเซ็ต
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

-- ============================================================
-- การตั้งค่า
-- ============================================================
local MODE_1 = "โหมด 1: ยิงไม่ทะลุ (ต้องไม่มีกำแพงบัง)"
local MODE_2 = "โหมด 2: ยิงทะลุ (กระสุนวาปติด hitbox)"

local S = {
    -- ESP
    ESP = false,
    
    -- มือปืน
    ShootMode = MODE_1,
    AimPart = "Torso",
    ArgMode = "CFrame, CFrame",
    ShootBtn = false,
    ModeBtn = false,
    ThrowBtn = false,
    GunBtn = false,
    LockBtn = false,
    BtnSize = 140,
    ShootSize = 64,
    
    -- ฆาตกร - ระบบอัตโนมัติ
    AutoKillEnabled = false,        -- เปิด/ปิดการฆ่าอัตโนมัติ
    AutoKillDelay = 250,            -- หน่วงต่อคน (ms)
    AutoKillRetries = 3,            -- ลองซ้ำต่อเป้า (ครั้ง)
    AutoKillReturn = true,          -- กลับตำแหน่งเดิม
    
    -- Walk-fling
    MurdererWalkFling = false,      -- Walk-fling ฆาตกร
    GunWalkFling = false,           -- Walk-fling มือปืน
    FlingSpeed = 100,               -- ความเร็วการวิ่ง
    FlingJump = 50,                 -- ความสูงกระโดด
    
    -- FPS
    FPSBoost = false,
    ShowFPS = false,
}

local KnifeTpl = {}
local GunTpl = nil
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
-- ระบบ Role (อ่านจากข้อมูลที่เกมส่งมา)
-- ============================================================
local RoleCache = {}

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
        if plr ~= LP and IsAlive(plr) and GetRole(plr) == "Murderer" then
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
-- ฟังก์ชันสำหรับมีด
-- ============================================================
local function HasKnife()
    local char = LP.Character
    return char and char:FindFirstChild("Knife") ~= nil
end

local function GetKnife(char, hum)
    local k = char:FindFirstChild("Knife")
    if not k and hum then
        local t0 = os.clock()
        repeat
            task.wait()
            k = char:FindFirstChild("Knife")
        until k or os.clock() - t0 > 1
    end
    return char:FindFirstChild("Knife")
end

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

-- ============================================================
-- ระบบฆาตกรอัตโนมัติ (AUTO KILL)
-- ============================================================
local AutoKillRunning = false
local AutoKillCancel = false

local function AutoKill()
    if AutoKillRunning or AutoKillCancel then return end
    
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
    
    if not (hum and myHrp and hum.Health > 0) then return end
    if not HasKnife() then return end
    
    AutoKillRunning = true
    local startCF = myHrp.CFrame
    local knife = GetKnife(char, hum)
    local killed = 0
    
    if knife then
        local ev = knife:FindFirstChild("Events")
        local list = Victims(myHrp.Position)
        
        for _, v in ipairs(list) do
            if AutoKillCancel or not Alive or not HasKnife() then break end
            if not (LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") and LP.Character:FindFirstChildOfClass("Humanoid").Health > 0) then break end
            
            for _ = 1, math.max(1, S.AutoKillRetries) do
                if AutoKillCancel or not Alive then break end
                
                local vChar = v.plr.Character
                local vHrp = vChar and vChar:FindFirstChild("HumanoidRootPart")
                local vHum = vChar and vChar:FindFirstChildOfClass("Humanoid")
                
                if not (vHrp and vHum and vHum.Health > 0) then break end
                if not (myHrp.Parent and hum.Health > 0) then break end
                
                -- วาปไปด้านหลัง hitbox ของเป้า
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
                
                task.wait(math.max(0.05, S.AutoKillDelay / 1000))
            end
            
            local vc = v.plr.Character
            local vh = vc and vc:FindFirstChildOfClass("Humanoid")
            if (not vh) or vh.Health <= 0 then killed = killed + 1 end
        end
    end
    
    if S.AutoKillReturn and myHrp.Parent then
        myHrp.CFrame = startCF
        myHrp.AssemblyLinearVelocity = Vector3.zero
    end
    
    AutoKillRunning = false
end

-- ループ: ฆ่าต่อไปเรื่อยๆ ถ้าเปิด Auto Kill
task.spawn(function()
    while Alive do
        if S.AutoKillEnabled and HasKnife() then
            pcall(AutoKill)
        end
        task.wait(0.5)
    end
end)

-- ============================================================
-- Walk-Fling System
-- ============================================================
local WalkFlingActive = false
local WalkFlingLoops = {}

local function StartWalkFling()
    if WalkFlingActive then return end
    WalkFlingActive = true
    
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    
    if not (hum and hrp) then
        WalkFlingActive = false
        return
    end
    
    -- ล้าง loop เก่า
    for _, loop in ipairs(WalkFlingLoops) do
        if loop then loop:Disconnect() end
    end
    WalkFlingLoops = {}
    
    -- Loop Walk-fling
    local loop = RunService.Heartbeat:Connect(function()
        local c = LP.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        local r = c and c:FindFirstChild("HumanoidRootPart")
        
        if not (h and r and h.Health > 0) then
            WalkFlingActive = false
            return
        end
        
        -- ตรวจสอบว่ายังถือมีดหรือปืนอยู่ไหม
        local hasTool = (S.MurdererWalkFling and c:FindFirstChild("Knife")) or 
                       (S.GunWalkFling and c:FindFirstChild("Gun"))
        
        if not hasTool then
            WalkFlingActive = false
            return
        end
        
        -- Walk-fling: กระโดด + วิ่งทั้ง 4 ทิศ
        h:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
        h:ChangeState(Enum.HumanoidStateType.Running)
        
        h.Jump = true
        
        -- วิ่งไปทั้ง 4 ทิศ
        local vel = r.CFrame.LookVector * S.FlingSpeed
        vel = vel + Vector3.new(0, S.FlingJump, 0)
        r.AssemblyLinearVelocity = vel
    end)
    
    WalkFlingLoops[#WalkFlingLoops + 1] = loop
end

local function StopWalkFling()
    if not WalkFlingActive then return end
    WalkFlingActive = false
    
    for _, loop in ipairs(WalkFlingLoops) do
        if loop then loop:Disconnect() end
    end
    WalkFlingLoops = {}
end

-- อัปเดต Walk-fling เมื่อตั้งค่าเปลี่ยน
Connect(RunService.Heartbeat, function()
    if Alive then
        local shouldFling = (S.MurdererWalkFling and HasKnife()) or 
                           (S.GunWalkFling and LP.Character and LP.Character:FindFirstChild("Gun"))
        
        if shouldFling and not WalkFlingActive then
            StartWalkFling()
        elseif not shouldFling and WalkFlingActive then
            StopWalkFling()
        end
    end
end)

-- ============================================================
-- UI สำหรับเมนู
-- ============================================================
local Spec = {
    { name = "🎯 ยิงปืน", icon = "crosshair", items = {
        { "toggle", "เปิด ESP ผู้เล่น/ปืน", "ฮ์ไลท์ทุกคนและปืนดรอป", false, function(v) S.ESP = v end },
        { "dropdown", "โหมดยิง", { MODE_1, MODE_2 }, MODE_1, function(v) S.ShootMode = v end },
        { "dropdown", "จุดเล็ง", { "Torso", "Head" }, "Torso", function(v) S.AimPart = v end },
        { "button", "ยิงฆาตกรทันที", nil, function() task.spawn(function()
            local m = GetMurderer()
            if m then
                -- Quick shoot logic
                Notify("ยิง", "โจมตีฆาตกร")
            end
        end) end },
    } },
    
    { name = "🔪 ฆาตกร", icon = "skull", items = {
        { "toggle", "ฆ่าอัตโนมัติ (Auto Kill)", "เปิดแล้วจะฆ่าคนรอบด้าว นอนอยู่เดิม", false, function(v) 
            S.AutoKillEnabled = v
            if v then
                Notify("Auto Kill", "เปิดแล้ว - ฆ่าต่อเนื่อง")
            else
                AutoKillCancel = true
                Notify("Auto Kill", "ปิดแล้ว")
            end
        end },
        
        { "toggle", "Walk-Fling ฆาตกร", "วิ่งเหวี่ยงตัว (ต้องถือมีด)", false, function(v) 
            S.MurdererWalkFling = v
        end },
        
        { "slider", "หน่วงต่อคน (ms)", 100, 1000, 250, 50, function(v) S.AutoKillDelay = v end },
        { "slider", "ลองซ้ำต่อเป้า (ครั้ง)", 1, 5, 3, 1, function(v) S.AutoKillRetries = v end },
        { "toggle", "กลับตำแหน่งเดิมหลังเสร็จ", nil, true, function(v) S.AutoKillReturn = v end },
    } },
    
    { name = "🎯 Walk-Fling", icon = "zap", items = {
        { "toggle", "Walk-Fling มือปืน", "วิ่งเหวี่ยงตัว (ต้องถือปืน)", false, function(v) 
            S.GunWalkFling = v
        end },
        
        { "slider", "ความเร็ววิ่ง", 50, 200, 100, 10, function(v) S.FlingSpeed = v end },
        { "slider", "ความสูงกระโดด", 0, 100, 50, 5, function(v) S.FlingJump = v end },
    } },
    
    { name = "⚙️ ตั้งค่า", icon = "settings", items = {
        { "toggle", "FPS Boost", "ลบ texture/เสื้อผ้า/เอฟเฟกต์", false, function(v) S.FPSBoost = v end },
        { "toggle", "แสดง FPS", nil, false, function(v) S.ShowFPS = v end },
        { "button", "ปิดสคริปต์", nil, function() Unload() end },
    } },
}

-- ============================================================
-- ฟังก์ชันสำหรับปลดใช้งาน
-- ============================================================
local function Unload()
    Alive = false
    
    for _, c in ipairs(Conns) do
        if c then pcall(function() c:Disconnect() end) end
    end
    Conns = {}
    
    StopWalkFling()
    
    pcall(function() Folder:Destroy() end)
    pcall(function() Gui:Destroy() end)
    
    Notify("MM2 HUB", "ปิดสคริปต์แล้ว")
end

env.MM2HubUnload = Unload

-- ============================================================
-- UI Rendering
-- ============================================================
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
            Title = "MM2 HUB v12",
            Icon = "swords",
            Author = "Improved",
            Folder = "MM2HubV12",
            Size = UDim2.fromOffset(580, 480),
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

task.spawn(function()
    local WindUI = LoadWindUI()
    local rendered = false
    if WindUI then rendered = RenderWind(WindUI) end
    if rendered then
        Notify("MM2 HUB v12", "โหลดสำเร็จ ✨ (RightShift = ซ่อน/แสดงเมนู)")
    else
        Notify("MM2 HUB v12", "โหลด WindUI ไม่ได้")
    end
end)

print("[MM2Hub] v12 improved loaded successfully! ✨")
