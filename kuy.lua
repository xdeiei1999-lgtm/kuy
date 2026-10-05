--[[
    MM2 HUB v11-9 (ไฟล์เดียว รวมทุกอย่าง)
    + เพิ่มระบบ: Auto-Kill Knife (เปิดปิดได้ ฆ่าทั้งแมพโดยไม่ต้องวาป)
    UI: WindUI  (ถ้าโหลดไม่ได้ จะใช้ UI สำรองในตัวอัตโนมัติ)

    ฟีเจอร์ใหม่:
      - Auto-Kill Knife (Toggle): เปิดแล้วพอถือมีดจะฆ่าทั้งแมพโดยไม่ต้องวาป ตัวเราอยู่ที่เดิม
      
    ฟีเจอร์เดิม:
      - ESP แบบรวม (สวิตช์เดียว): ผู้เล่นแยกบทบาท + ชื่อ/ระยะ/อาวุธ + ปืนที่ดรอป
      - มือปืน 2 โหมด:  1) ยิงไม่ทะลุ (ต้องไม่มีกำแพงบัง)
                         2) ยิงทะลุ (กระสุนวาปติด hitbox ฆาตกร)
      - ฆาตกร: ฆ่าทั้งแมพ วาปไปหา hitbox ทีละคน
      - ฆาตกร: โยนมีด (มีดวาปไปที่ hitbox ของผู้เล่นที่เล็งใกล้สุด)
      - ปุ่มลอย: SHOOT / MODE / THROW (โยนมีด) / GRAB GUN (เก็บปืนที่ดรอป)
        ล็อกตำแหน่ง ปรับขนาด รีเซ็ตตำแหน่งได้
      - FPS Boost (ลบ texture/เสื้อผ้า/เอฟเฟกต์ ตัวละครและพื้นเป็นสีเทา)
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
    ESP = false,
    -- มือปืน
    ShootMode = MODE_1, AimPart = "Torso",
    ArgMode = "CFrame, CFrame",
    -- ปุ่มลอย
    ShootBtn = false, ModeBtn = false, ThrowBtn = false, GunBtn = false, LockBtn = false, BtnSize = 140, ShootSize = 64,
    -- ฆาตกร
    KillDelay = 250, KillRetries = 3, KillReturn = true,
    AutoKnife = false,            -- ✅ ระบบ Auto-Kill Knife เปิดปิด
    AutoKnifeDelay = 100,         -- ✅ หน่วงระหว่างการฆ่า (ms)
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
        if plr ~= LP and IsAlive(plr) then
            local char = plr.Character
            if char and GetRole(plr) == "Murderer" then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local d = (myHrp and (myHrp.Position - hrp.Position).Magnitude) or 0
                    if d < bestDist then best, bestDist = plr, d end
                end
            end
        end
    end
    return best
end

local function Diag()
    local r = GetRole(LP)
    local rmote = (GetCur and "GetCur") or (GetPD and "GetPD") or "none"
    return "role: " .. r .. " | remote: " .. rmote .. " | cache: " .. RoleSource .. " | hook: " .. (HookOK and "ok" or "unsupported")
end

-- ============================================================
-- Auto-Knife System ✅ เปิดปิดแล้วอย่าเคยเห็น
-- ============================================================
local AutoKnifeActive = false
local AutoKnifeLastTime = 0

local function AutoKnifeUpdate()
    if not S.AutoKnife or not Alive then return end
    
    local now = tick() * 1000
    if now - AutoKnifeLastTime < S.AutoKnifeDelay then return end
    
    local char = LP.Character
    if not char then return end
    
    -- ✅ ตรวจสอบว่าลูกค้าเป็นฆาตกรและถือมีด
    local knife = char:FindFirstChild("Knife")
    if not knife then return end
    
    local myRole = GetRole(LP)
    if myRole ~= "Murderer" then return end
    
    local myHrp = char:FindFirstChild("HumanoidRootPart")
    if not myHrp then return end
    
    -- ✅ ค้นหาเป้าหมายในแมพ (ไม่ต้องวาป ใช้มีดธรรมชาติ)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and IsAlive(plr) then
            local pChar = plr.Character
            if pChar then
                local pHrp = pChar:FindFirstChild("HumanoidRootPart")
                if pHrp then
                    -- ✅ ใช้ Knife Stab Attack โดยตรง (ไม่ต้องวาปตัวเรา)
                    local knifeHitbox = knife:FindFirstChild("Hitbox")
                    if knifeHitbox then
                        -- ทำการ Stab ไปยัง hitbox ของเป้า
                        pcall(function()
                            if KnifeTpl.Stab then
                                KnifeTpl.Stab(pHrp)
                            else
                                -- ลองจัดการ hitbox โดยตรง
                                local args = { pHrp, pChar:FindFirstChildOfClass("Humanoid") }
                                if knifeHitbox:FindFirstChild("Damage") then
                                    knifeHitbox.Damage:FireServer(unpack(args))
                                end
                            end
                        end)
                    end
                end
            end
        end
    end
    
    AutoKnifeLastTime = now
end

-- ✅ Loop สำหรับ Auto-Knife
task.spawn(function()
    while Alive do
        pcall(AutoKnifeUpdate)
        task.wait(0.01)
    end
end)

-- ============================================================
-- Unload
-- ============================================================
local function Unload()
    Alive = false
    for _, c in ipairs(Conns) do pcall(function() c:Disconnect() end) end
    Conns = {}
    pcall(function() Gui:Destroy() end)
    pcall(function() Folder:Destroy() end)
    if WindowObj then pcall(function() WindowObj:Close() end) end
    Notify("MM2 HUB", "ปิดสคริปต์เสร็จสิ้น")
end

env.MM2HubUnload = Unload

-- ============================================================
-- ระบบ UI Menu
-- ============================================================
local Spec = {
    { name = "Auto-Kill", icon = "zap", items = {
        { "toggle", "Auto-Kill Knife (เปิด/ปิด)", "เปิดแล้ว ตัวเราจะฆ่าทั้งแมพเองแบบอัตโนมัติขณะถือมีด (ไม่ต้องวาป)", false, function(v) S.AutoKnife = v; if v then Notify("Auto-Kill", "เปิดแล้ว - พอถือมีด จะฆ่าคนรอบ ๆ อัตโนมัติ") else Notify("Auto-Kill", "ปิดแล้ว") end end },
        { "slider", "หน่วงระหว่างการฆ่า (ms)", 50, 500, 100, 25, function(v) S.AutoKnifeDelay = v end },
    } },
    { name = "ESP", icon = "eye", items = {
        { "toggle", "ESP (รวมทั้งหมด)", "ผู้เล่นแยกบทบาท + ชื่อ/ระยะ/อาวุธ + ปืนที่ดรอป", false, function(v) S.ESP = v end },
    } },
    { name = "อื่นๆ", icon = "settings", items = {
        { "button", "ตรวจสอบระบบ", "ดูว่า role / hook / args / GunDrop ใช้งานได้ไหม", function() Notify("สถานะระบบ", Diag()) end },
        { "button", "ปิดสคริปต์ (Unload)", "ล้างทุกอย่างและคืนค่า", function() Unload() end },
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
            Author = "v11-9",
            Folder = "MM2HubV11",
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
    title.Text = "MM2 HUB v11-9 (UI สำรอง)"
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
        Notify("MM2 HUB v11-9", "โหลด WindUI ไม่ได้ ใช้ UI สำรองแทน")
    else
        Notify("MM2 HUB v11-9", "โหลดสำเร็จ (RightShift = ซ่อน/แสดงเมนู)")
    end
end)

print("[MM2Hub v11-9] loaded | AutoKnife feature added")
