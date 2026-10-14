--[[
    DOORS ESP Hub   (UI: Rayfield)

    หมวดหมู่ (แท็บ)
      1) Ghost ESP         : ESP ผีทุกตัวในเกม (สีแดง) เลือกเปิดทุกตัวหรือเลือกเป็นตัวๆ ได้
      2) Key/Door/Book ESP : ESP กุญแจ, สมุด (ห้อง 50 ห้องสมุด / หายเมื่อเก็บแล้ว), ประตูที่ถูกต้อง
      3) ปุ่มลอย           : ปุ่มลอย ESP ผี/ประตู/สมุด/กุญแจ ลากย้าย ปรับขนาด ล็อกทุกปุ่มได้
      4) Graphics          : Low Graphics (ลบกราฟิก/เอฟเฟกต์ทั้งหมด) + ปุ่มสว่าง (กดครั้งเดียว)
      5) Misc              : จุดเริ่มเส้น, ระยะ ESP สูงสุด, ปิดสคริปต์

    ทุก ESP แยกสวิตช์ / เส้น / สี ของตัวเอง และสแกนอัตโนมัติตลอดเวลา

    หมายเหตุ: ประตู/กุญแจ/สมุดอ่านจาก Workspace.CurrentRooms ของ DOORS
      - กุญแจ    = Model/Part ชื่อ KeyObtain (หรือ Key)
      - สมุด     = Model ชื่อ LiveHintBook (ห้อง 50 ห้องสมุด)
      - ประตู    = Model ชื่อ Door (ลูกตรงของห้อง) / DoorFake (ประตูปลอม)
]]

local env = (getgenv and getgenv()) or _G
if env.GhostHubUnload then pcall(env.GhostHubUnload) end

-- ============================================================
-- Services / พื้นฐาน
-- ============================================================
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Lighting          = game:GetService("Lighting")
local UIS               = game:GetService("UserInputService")
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
    return "GH_" .. tostring(math.random(100000, 999999))
end

local function SafeParent()
    local ok, parent = pcall(function()
        if gethui then return gethui() end
        return game:GetService("CoreGui")
    end)
    if ok and parent then return parent end
    return LP:WaitForChild("PlayerGui")
end

-- ตั้งค่าแต่ละหมวด ESP (แยกกันชัดเจน)
local Cfg = {
    ghost = { on = true, line = true, color = Color3.fromRGB(255, 30, 30),
              all = true, sel = {} },
    key   = { on = false, line = true, color = Color3.fromRGB(255, 215, 0) },
    door  = { on = false, line = true, color = Color3.fromRGB(70, 255, 120),
              showFake = false, fakeColor = Color3.fromRGB(255, 70, 70) },
    book  = { on = true, line = true, color = Color3.fromRGB(255, 170, 60), only50 = true },
}
local S = { LineOrigin = "Bottom", MaxDist = 0 }
local LabelOffset = { ghost = 3, key = 1.5, door = 3, book = 1.5 }
local BOOK_ROOM = 50   -- ห้องสมุด (Library) ของ DOORS

local Folder = Instance.new("Folder")
Folder.Name = RName()
Folder.Parent = SafeParent()

local Gui = Instance.new("ScreenGui")
Gui.Name = RName()
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.DisplayOrder = 10
Gui.Parent = SafeParent()

local RayfieldRef = nil
local function Notify(title, content)
    if RayfieldRef then
        local ok = pcall(function()
            RayfieldRef:Notify({ Title = title, Content = content, Duration = 4 })
        end)
        if ok then return end
    end
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = title, Text = content, Duration = 4 })
    end)
end

-- ============================================================
-- ผี: ตรวจจากชื่อ Model / Part
-- ============================================================
local BaseKeywords = {
    "ghost", "spirit", "phantom", "specter", "spectre",
    "wraith", "poltergeist", "banshee", "apparition", "haunt",
}

-- เอนทิตี้ทั้งหมดของ DOORS (ชื่อ Model ต้องขึ้นต้นด้วย key เช่น "RushMoving", "AmbushMoving",
-- "BackdoorRush") ตัวอักษรถัดจากชื่อต้องไม่ใช่ตัวพิมพ์เล็ก กันชื่ออื่นที่บังเอิญขึ้นต้นเหมือนกัน
local Entities = {
    { key = "rush", title = "Rush" },       { key = "ambush", title = "Ambush" },
    { key = "a60", title = "A-60" },        { key = "a120", title = "A-120" },
    { key = "eyes", title = "Eyes" },       { key = "halt", title = "Halt" },
    { key = "screech", title = "Screech" }, { key = "seek", title = "Seek" },
    { key = "figure", title = "Figure" },   { key = "dupe", title = "Dupe" },
    { key = "timothy", title = "Timothy" }, { key = "jeff", title = "Jeff" },
    { key = "giggle", title = "Giggle" },   { key = "grumble", title = "Grumble" },
    { key = "snare", title = "Snare" },     { key = "dread", title = "Dread" },
    { key = "glitch", title = "Glitch" },   { key = "void", title = "Void" },
    { key = "shadow", title = "Shadow" },   { key = "lookman", title = "Lookman" },
    { key = "bob", title = "Bob" },         { key = "sally", title = "Sally" },
    { key = "jack", title = "Jack" },       { key = "surge", title = "Surge" },
    { key = "sorrow", title = "Sorrow" },   { key = "haste", title = "Haste" },
    { key = "hide", title = "Hide" },
}
local EntityOptions = {}
for _, e in ipairs(Entities) do EntityOptions[#EntityOptions + 1] = e.title end
EntityOptions[#EntityOptions + 1] = "Other"
for _, t in ipairs(EntityOptions) do Cfg.ghost.sel[t] = true end

local function EntityOf(name)
    local n = (string.gsub(name, "^Backdoor", ""))
    local l = string.lower(n)
    for _, e in ipairs(Entities) do
        local k = e.key
        if string.sub(l, 1, #k) == k then
            local nxt = string.sub(n, #k + 1, #k + 1)
            if nxt == "" or not string.find(nxt, "%l") then return e end
        end
    end
    return nil
end

-- ผลตรวจชื่อ (เก็บแคช ไม่ต้องคำนวณซ้ำ): entity table / "other" (ชื่อคล้ายผี) / false
local NameCache = {}
local function GhostInfo(name)
    local c = NameCache[name]
    if c ~= nil then return c end
    local r = false
    local e = EntityOf(name)
    if e then
        r = e
    else
        local l = string.lower(name)
        for _, k in ipairs(BaseKeywords) do
            if string.find(l, k, 1, true) then r = "other"; break end
        end
    end
    NameCache[name] = r
    return r
end

local function GhostNameMatches(name)
    return GhostInfo(name) ~= false
end

-- ชื่อที่โชว์บน ESP: ถ้าเป็นเอนทิตี้ที่รู้จักจะโชว์ชื่อสั้น (RushMoving -> Rush)
local function DisplayName(name)
    local i = GhostInfo(name)
    return type(i) == "table" and i.title or name
end

-- ไม่นับของที่อยู่ในตัวละครผู้เล่น / กล้อง
local function Excluded(inst)
    local a = inst.Parent
    while a and a ~= Workspace do
        if a.Parent == Workspace then
            if a:IsA("Camera") then return true end
            if Players:GetPlayerFromCharacter(a) then return true end
        end
        a = a.Parent
    end
    return false
end

-- ============================================================
-- ประตู / กุญแจ: อ่านจาก Workspace.CurrentRooms
-- ============================================================
local function RoomsFolder()
    return Workspace:FindFirstChild("CurrentRooms")
end

-- โมเดลห้อง (ลูกตรงของ CurrentRooms) ที่ inst อยู่ข้างใน
local function RoomOf(inst, cr)
    local a = inst
    while a and a.Parent ~= cr do a = a.Parent end
    return a
end

-- เลขบนป้ายประตู (อ่านเฉพาะข้อความที่เป็นตัวเลขล้วน ข้อความที่ถูกสลับ/ขีดฆ่าจะข้าม)
local function DoorNumber(door)
    for _, d in ipairs(door:GetDescendants()) do
        if d:IsA("TextLabel") then
            local t = d.Text
            if string.match(t, "^%s*%d+%s*$") then return tonumber(t) end
        end
    end
    return nil
end

-- คืน kind ("real" / "fake"), เลขบนป้าย, เลขห้อง
--   1) ตั้งต้นจากชื่อ: DoorFake = ปลอม, อย่างอื่น = จริง
--   2) ถ้าห้องมีประตูหลายบานและอ่านเลขได้ จะเทียบเลขป้ายกับห้องถัดไป (เลขห้อง + 1)
--      ใช้ตัดสินก็ต่อเมื่อมีประตู "บานเดียว" ที่ตรง ไม่งั้นยึดตามชื่อ (กันตัดสินผิด)
local function DoorKind(inst, cr)
    local byName = string.find(string.lower(inst.Name), "fake", 1, true) and "fake" or "real"
    local num = DoorNumber(inst)
    local room = cr and RoomOf(inst, cr)
    local idx = room and tonumber(room.Name)
    if not idx then return byName, num, nil end

    local cands = {}
    for _, d in ipairs(room:GetDescendants()) do
        if d:IsA("Model") and (d.Name == "Door" or d.Name == "DoorFake") then
            cands[#cands + 1] = d
        end
    end
    if #cands < 2 then return byName, num, idx end

    local match, other, mine = 0, 0, nil
    for _, d in ipairs(cands) do
        local n = DoorNumber(d)
        if n then
            if n == idx + 1 then
                match = match + 1
                if d == inst then mine = "real" end
            else
                other = other + 1
                if d == inst then mine = "fake" end
            end
        end
    end
    if match == 1 and other >= 1 and mine then return mine, num, idx end
    return byName, num, idx
end

local function LatestRoom()
    local gd = ReplicatedStorage:FindFirstChild("GameData")
    local v = gd and gd:FindFirstChild("LatestRoom")
    if v and v:IsA("ValueBase") then return tonumber(v.Value) end
    return nil
end

-- ============================================================
-- จัดหมวด: ผี / กุญแจ / ประตู
-- ============================================================
local function Classify(inst)
    local isModel = inst:IsA("Model")
    if not (isModel or inst:IsA("BasePart")) then return nil end
    if inst:IsA("Terrain") then return nil end
    local name = inst.Name

    local cr = RoomsFolder()
    if cr and inst:IsDescendantOf(cr) then
        if isModel then
            if name == "Door" and inst.Parent and inst.Parent.Parent == cr then return "door" end
            if name == "DoorFake" then return "door" end
            if name == "LiveHintBook" or string.find(string.lower(name), "hintbook", 1, true) then return "book" end
        end
        if name == "KeyObtain" or name == "Key" then return "key" end
    end

    -- ผี: ตรวจเฉพาะ Model (หรือ Part ที่อยู่ใน Workspace โดยตรง) เพื่อไม่ให้สแกนหนัก
    if isModel or inst.Parent == Workspace then
        if GhostNameMatches(name) then
            if isModel and Players:GetPlayerFromCharacter(inst) then return nil end
            if Excluded(inst) then return nil end
            return "ghost"
        end
    end
    return nil
end

-- ============================================================
-- วัตถุ ESP
-- ============================================================
local Tracked = {}   -- [inst] = { cat, kind, num, room, kindAt, shown, hl, bb, tl, line, conn }

local function ColorFor(o)
    local c = Cfg[o.cat]
    if o.cat == "door" and o.kind == "fake" then return c.fakeColor end
    return c.color
end

local function Recolor(o)
    local col = ColorFor(o)
    pcall(function()
        o.hl.FillColor = col
        o.hl.OutlineColor = col
        o.tl.TextColor3 = col
        o.line.BackgroundColor3 = col
    end)
end

local function RecolorCat(cat)
    for _, o in pairs(Tracked) do
        if o.cat == cat then Recolor(o) end
    end
end

local function Untrack(inst)
    local o = Tracked[inst]
    if not o then return end
    Tracked[inst] = nil
    pcall(function() o.conn:Disconnect() end)
    if o.pconn then pcall(function() o.pconn:Disconnect() end) end
    pcall(function() o.hl:Destroy() end)
    pcall(function() o.bb:Destroy() end)
    pcall(function() o.line:Destroy() end)
end

-- สมุดที่ถูกเก็บแล้ว: เลิกติดตามถาวร (ไม่กลับมาโชว์อีก)
local Collected = setmetatable({}, { __mode = "k" })
local function MarkCollected(inst)
    Collected[inst] = true
    Untrack(inst)
end

local function FindAdornee(inst)
    if inst:IsA("BasePart") then return inst end
    return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
end

local function LabelFor(inst, o)
    if o.cat == "ghost" then return DisplayName(inst.Name) end
    if o.cat == "key" then return "Key" end
    if o.cat == "book" then return "Book" end
    if o.kind == "fake" then return "FAKE Door (Dupe)" end
    if o.num then return "Door " .. o.num end
    return "Door"
end

local function Track(inst)
    if not Alive or Tracked[inst] then return end
    if Collected[inst] then return end
    local cat = Classify(inst)
    if not cat then return end
    for c in pairs(Collected) do
        if c:IsAncestorOf(inst) then return end
    end

    -- ตัวแม่หมวดเดียวกันถูกติดตามอยู่แล้ว ไม่ต้องทำซ้ำ / ถ้าตัวลูกถูกติดตามอยู่ ให้เลิกตัวลูก
    for t, o in pairs(Tracked) do
        if o.cat == cat and t:IsAncestorOf(inst) then return end
    end
    for t, o in pairs(Tracked) do
        if o.cat == cat and inst:IsAncestorOf(t) then Untrack(t) end
    end

    local rec = { cat = cat, kind = "real", num = nil, room = nil, kindAt = 0, shown = false }
    if cat == "ghost" then
        local info = GhostInfo(inst.Name)
        rec.ent = type(info) == "table" and info.title or "Other"
    elseif cat == "book" then
        -- จับตาปุ่มเก็บ (ProximityPrompt): ถ้าเราเก็บ / ปุ่มหาย / ปิดใช้งาน = สมุดถูกเก็บแล้ว
        local pr = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
        if pr then
            rec.prompt, rec.hadPrompt = pr, true
            rec.pconn = pr.Triggered:Connect(function(plr)
                if plr == LP then MarkCollected(inst) end
            end)
        end
    end
    local col = ColorFor(rec)

    local hl = Instance.new("Highlight")
    hl.Name = RName()
    hl.Adornee = inst
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillColor = col
    hl.OutlineColor = col
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.Enabled = false
    hl.Parent = Folder

    local bb = Instance.new("BillboardGui")
    bb.Name = RName()
    bb.Adornee = FindAdornee(inst)
    bb.AlwaysOnTop = true
    bb.Size = UDim2.fromOffset(170, 38)
    bb.StudsOffset = Vector3.new(0, LabelOffset[cat] or 3, 0)
    bb.Enabled = false
    bb.Parent = Folder

    local tl = Instance.new("TextLabel")
    tl.BackgroundTransparency = 1
    tl.Size = UDim2.fromScale(1, 1)
    tl.Font = Enum.Font.GothamBold
    tl.TextSize = 14
    tl.TextColor3 = col
    tl.TextStrokeTransparency = 0.3
    tl.Text = LabelFor(inst, rec)
    tl.Parent = bb

    local line = Instance.new("Frame")
    line.Name = RName()
    line.AnchorPoint = Vector2.new(0.5, 0.5)
    line.BorderSizePixel = 0
    line.BackgroundColor3 = col
    line.Visible = false
    line.Parent = Gui

    rec.hl, rec.bb, rec.tl, rec.line = hl, bb, tl, line
    rec.conn = inst.AncestryChanged:Connect(function()
        if not inst:IsDescendantOf(Workspace) then Untrack(inst) end
    end)
    Tracked[inst] = rec
end

-- ============================================================
-- สแกนอัตโนมัติ (ผี / กุญแจ / สมุด / ประตู)
--   1) ของที่เกิดใหม่ใน Workspace ถูกจับทันที (DescendantAdded)
--   2) สแกนซ้ำทุก ~4 วินาทีเป็นตาข่ายนิรภัย: ของที่อยู่ใน Workspace โดยตรง + Model ในห้อง
--      (ไม่ไล่ทุกชิ้นส่วนของแมพ จึงไม่ทำให้ FPS ตก)
-- ============================================================
local function ScanOnce()
    for _, d in ipairs(Workspace:GetChildren()) do
        if not Alive then return end
        Track(d)
    end
    local cr = RoomsFolder()
    if not cr then return end
    local list = cr:GetDescendants()
    for i, d in ipairs(list) do
        if not Alive then return end
        if d:IsA("Model") or d.Name == "KeyObtain" or d.Name == "Key" then Track(d) end
        if i % 2500 == 0 then task.wait() end
    end
end

Connect(Workspace.DescendantAdded, function(d)
    task.defer(Track, d)
end)

task.spawn(function()
    while Alive do
        pcall(ScanOnce)
        task.wait(4)
    end
end)

-- ============================================================
-- วาด ESP ทุกเฟรม: เปิด/ปิดแยกหมวด, ระยะ, เส้น
-- ============================================================
local function WantShown(o, latest)
    local c = Cfg[o.cat]
    if not c.on then return false end
    if o.cat ~= "door" and S.MaxDist > 0 and o.dist and o.dist > S.MaxDist then return false end
    if o.cat == "ghost" then
        if not c.all and not c.sel[o.ent or "Other"] then return false end
    elseif o.cat == "door" then
        if o.kind == "fake" and not c.showFake then return false end
        -- โชว์เฉพาะประตูของห้องปัจจุบันและห้องถัดๆ ไป (ประตูห้องที่ผ่านมาแล้วซ่อน)
        if latest and o.room and o.room < latest then return false end
    elseif o.cat == "book" then
        -- สมุดอยู่ที่ห้อง 50 (ห้องสมุด) เท่านั้น (ถ้าอ่านเลขห้องไม่ได้ ก็แสดงไว้ก่อน)
        if c.only50 and o.room and o.room ~= BOOK_ROOM then return false end
    end
    return true
end

-- สมุดถูกเก็บแล้วหรือยัง (ดูจากปุ่มเก็บ + ความโปร่งใสของตัวสมุด)
local function BookCollected(inst, o)
    local pr = o.prompt
    if not pr or not pr:IsDescendantOf(inst) then
        pr = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
        o.prompt = pr
        if pr then o.hadPrompt = true end
    end
    if o.hadPrompt and not pr then return true end          -- ปุ่มเก็บหายไป
    if pr then
        if pr.Enabled then o.off = 0 else o.off = (o.off or 0) + 1 end
        if o.off >= 2 then return true end                   -- ปุ่มถูกปิดต่อเนื่อง
    end
    local anyPart, anyVisible = false, false
    if inst:IsA("BasePart") then
        anyPart, anyVisible = true, inst.Transparency < 0.99
    else
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") then
                anyPart = true
                if d.Transparency < 0.99 then anyVisible = true; break end
            end
        end
    end
    return anyPart and not anyVisible                         -- ทุกชิ้นโปร่งใส = ถูกเก็บ/ซ่อน
end

local lastStep = 0
local latestRoom = nil
Connect(RunService.RenderStepped, function()
    if not Alive then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end

    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local origin
    if S.LineOrigin == "Top" then
        origin = Vector2.new(vp.X / 2, 0)
    elseif S.LineOrigin == "Center" then
        origin = center
    else
        origin = Vector2.new(vp.X / 2, vp.Y)
    end

    local myChar = LP.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myPos = myRoot and myRoot.Position or cam.CFrame.Position

    local now = os.clock()
    local doStep = (now - lastStep) > 0.1
    if doStep then
        lastStep = now
        latestRoom = LatestRoom()
    end
    local cr = RoomsFolder()

    for inst, o in pairs(Tracked) do
        local ok = inst:IsDescendantOf(Workspace)
        if ok and o.cat ~= "ghost" and not (cr and inst:IsDescendantOf(cr)) then ok = false end

        if not ok then
            Untrack(inst)
        else
            local keep = true

            -- ประตู: ตรวจจริง/ปลอมซ้ำทุก ~1 วินาที (ป้ายเลขอาจถูกสลับทีหลัง)
            if o.cat == "door" and (now - o.kindAt) > 1 then
                o.kindAt = now
                local k, n, r = DoorKind(inst, cr)
                o.room = r
                if k ~= o.kind or n ~= o.num then
                    o.kind, o.num = k, n
                    Recolor(o)
                end
            end

            -- สมุด: อ่านเลขห้อง + เช็คว่าถูกเก็บแล้วหรือยัง ทุก ~1 วินาที
            if o.cat == "book" and (now - o.kindAt) > 1 then
                o.kindAt = now
                local rm = cr and RoomOf(inst, cr)
                o.room = rm and tonumber(rm.Name) or nil
                if BookCollected(inst, o) then
                    keep = false
                    MarkCollected(inst)
                end
            end

            if keep then
                -- ตำแหน่ง/ระยะ อัปเดตทุกเฟรม (ผีวิ่งเร็ว เส้นจะได้ไม่หน่วง)
                local okP, cf = pcall(inst.GetPivot, inst)
                if okP and cf then
                    o.pos = cf.Position
                    o.dist = (o.pos - myPos).Magnitude
                end

                local want = WantShown(o, latestRoom)
                if o.shown ~= want then
                    o.shown = want
                    o.hl.Enabled = want
                    o.bb.Enabled = want
                end

                if not want or not o.pos then
                    if o.line.Visible then o.line.Visible = false end
                else
                    if doStep then
                        if not o.bb.Adornee or not o.bb.Adornee:IsDescendantOf(Workspace) then
                            o.bb.Adornee = FindAdornee(inst)
                        end
                        o.tl.Text = string.format("%s\n%d studs", LabelFor(inst, o), math.floor(o.dist + 0.5))
                    end

                    if Cfg[o.cat].line then
                        local v = cam:WorldToViewportPoint(o.pos)
                        local pt = Vector2.new(v.X, v.Y)
                        if v.Z < 0 then pt = center * 2 - pt end   -- อยู่ด้านหลัง: ชี้ไปทางตรงข้าม
                        pt = Vector2.new(math.clamp(pt.X, 8, vp.X - 8), math.clamp(pt.Y, 8, vp.Y - 8))
                        local diff = pt - origin
                        local len = diff.Magnitude
                        if len < 1 then
                            o.line.Visible = false
                        else
                            o.line.Size = UDim2.fromOffset(len, 2)
                            o.line.Position = UDim2.fromOffset(origin.X + diff.X / 2, origin.Y + diff.Y / 2)
                            o.line.Rotation = math.deg(math.atan2(diff.Y, diff.X))
                            o.line.Visible = true
                        end
                    elseif o.line.Visible then
                        o.line.Visible = false
                    end
                end
            end
        end
    end
end)

-- ============================================================
-- Low Graphics (กดครั้งเดียว ไม่ใช่สวิตช์) ลบกราฟิก/เอฟเฟกต์ทั้งหมด
--   - กราฟิก : วัสดุเป็น SmoothPlastic ทุกชิ้น (คงเฉพาะ Neon), ลบ Decal/Texture/SurfaceAppearance,
--              ล้างรูปบน MeshPart/SpecialMesh, MeshPart detail ต่ำสุด, ปิดเงาและความเงาทั้งหมด
--   - เอฟเฟกต์: ปิด Particle / Trail / Beam / Smoke / Fire / Sparkles / Explosion / Highlight ของเกม
--   - แสง/จอ : ปิด PostEffect ทุกตัว (Bloom, Blur, DoF, SunRays, ColorCorrection), หมอก Atmosphere,
--              เงาโลก, Environment lighting, น้ำ/หญ้า/เมฆ, Quality ต่ำสุด, Lighting แบบ Compatibility
--              (ไม่ปิดตัวไฟ เพื่อให้ยังมองเห็นในเกมมืดได้)
--   - ตัวละครผู้เล่น: ปิดเงากับเอฟเฟกต์ แต่ไม่แตะสีและเครื่องแต่งตัว
--   - หลังกดครั้งแรก ของที่เกิดใหม่ (เช่น ห้องใหม่) จะถูกลดให้อัตโนมัติจนกว่าจะ rejoin
-- ============================================================
local LowBusy = false
local LowHooked = false
local LowDone = setmetatable({}, { __mode = "k" })
local KeepMaterial = { [Enum.Material.Neon] = true }

-- ผู้เล่น: ตัวละครอยู่ใน Workspace โดยตรง
local function InCharacter(d)
    local a = d
    while a.Parent and a.Parent ~= Workspace do a = a.Parent end
    return Players:GetPlayerFromCharacter(a) ~= nil
end

local function LowProcess(d, inChar)
    if LowDone[d] then return end
    LowDone[d] = true

    if d:IsA("BasePart") then
        if d:IsA("Terrain") then return end
        d.CastShadow = false
        if inChar then return end
        d.Reflectance = 0
        if not KeepMaterial[d.Material] then
            d.Material = Enum.Material.SmoothPlastic
        end
        if d:IsA("MeshPart") then
            d.RenderFidelity = Enum.RenderFidelity.Performance
            d.TextureID = ""
        end
    elseif d:IsA("ParticleEmitter") then
        d.Rate = 0
        d.Enabled = false
    elseif d:IsA("Trail") or d:IsA("Beam") or d:IsA("Smoke") or d:IsA("Fire")
        or d:IsA("Sparkles") or d:IsA("Highlight") then
        d.Enabled = false
    elseif d:IsA("Explosion") or d:IsA("ForceField") then
        d.Visible = false
    elseif d:IsA("Light") then
        d.Shadows = false
    elseif inChar then
        return
    elseif d:IsA("Decal") or d:IsA("SurfaceAppearance") then   -- Decal รวม Texture
        d:Destroy()
    elseif d:IsA("SpecialMesh") then
        d.TextureId = ""
    end
end

local function LowPost(e)
    if e:IsA("PostEffect") then
        e.Enabled = false
    elseif e:IsA("Atmosphere") then
        e.Density = 0
        e.Haze = 0
    end
end

local function ApplyGlobalLow()
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    pcall(function() settings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04 end)
    pcall(function() Lighting.GlobalShadows = false end)
    pcall(function() Lighting.ShadowSoftness = 0 end)
    pcall(function() Lighting.EnvironmentDiffuseScale = 0 end)
    pcall(function() Lighting.EnvironmentSpecularScale = 0 end)
    for _, e in ipairs(Lighting:GetChildren()) do pcall(LowPost, e) end
    local cam = Workspace.CurrentCamera
    if cam then
        for _, e in ipairs(cam:GetChildren()) do pcall(LowPost, e) end
    end
end

local function HookLow()
    if LowHooked then return end
    LowHooked = true
    Connect(Workspace.DescendantAdded, function(d)
        task.defer(function()
            if not Alive or not d.Parent then return end
            pcall(LowProcess, d, InCharacter(d))
        end)
    end)
    Connect(Lighting.DescendantAdded, function(e) pcall(LowPost, e) end)
    -- เกมอาจเปิดเอฟเฟกต์หน้าจอกลับมา (เช่น ตอน Screech) จึงย้ำซ้ำทุก 2 วินาที
    task.spawn(function()
        while Alive do
            task.wait(2)
            pcall(ApplyGlobalLow)
        end
    end)
end

local function LowGraphics()
    if LowBusy then
        Notify("Graphics", "กำลังทำงานอยู่ รอสักครู่")
        return
    end
    LowBusy = true
    Notify("Graphics", "กำลังลบกราฟิกและเอฟเฟกต์ทั้งหมด...")
    HookLow()

    task.spawn(function()
        local count = 0

        ApplyGlobalLow()
        -- Lighting แบบ Compatibility (เบาที่สุด) ใช้ได้เฉพาะ executor ที่มี sethiddenproperty
        pcall(function()
            if sethiddenproperty then
                sethiddenproperty(Lighting, "Technology", Enum.Technology.Compatibility)
            end
        end)

        -- น้ำ / หญ้า / เมฆ
        local terrain = Workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            pcall(function() terrain.WaterWaveSize = 0 end)
            pcall(function() terrain.WaterWaveSpeed = 0 end)
            pcall(function() terrain.WaterReflectance = 0 end)
            pcall(function() terrain.Decoration = false end)
            pcall(function()
                local clouds = terrain:FindFirstChildOfClass("Clouds")
                if clouds then clouds.Enabled = false end
            end)
        end

        -- ของใน Workspace ทั้งหมด (ตัวละครผู้เล่นแตะเฉพาะเงา/เอฟเฟกต์)
        for _, child in ipairs(Workspace:GetChildren()) do
            if not Alive then break end
            if not child:IsA("Terrain") and not child:IsA("Camera") then
                local inChar = Players:GetPlayerFromCharacter(child) ~= nil
                pcall(LowProcess, child, inChar)
                for _, d in ipairs(child:GetDescendants()) do
                    if not Alive then break end
                    pcall(LowProcess, d, inChar)
                    count = count + 1
                    if count % 2500 == 0 then task.wait() end
                end
            end
        end

        LowBusy = false
        Notify("Graphics", "Low Graphics เสร็จแล้ว (ปรับ " .. count .. " ชิ้น)")
    end)
end

-- ============================================================
-- สว่าง (กดครั้งเดียว ไม่ใช่สวิตช์): ทำให้ทั้งแมพสว่าง ไม่มีหมอก
--   หลังกด จะย้ำค่าให้ทุก 1 วินาที (เกมชอบรีเซ็ตแสง) จนกว่าจะกด "คืนค่าแสงเดิม" หรือ rejoin
-- ============================================================
local BrightSaved = nil
local BrightLoop = false
local BRIGHT_AMB = Color3.fromRGB(200, 200, 200)

local function ApplyBright()
    pcall(function() Lighting.Brightness = 2 end)
    pcall(function() Lighting.Ambient = BRIGHT_AMB end)
    pcall(function() Lighting.OutdoorAmbient = BRIGHT_AMB end)
    pcall(function() Lighting.FogStart = 100000 end)
    pcall(function() Lighting.FogEnd = 1000000 end)
    pcall(function() Lighting.GlobalShadows = false end)
    for _, e in ipairs(Lighting:GetChildren()) do
        pcall(function()
            if e:IsA("Atmosphere") then e.Density = 0; e.Haze = 0 end
        end)
    end
end

local function BrightPress()
    if not BrightSaved then
        BrightSaved = {
            Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient, FogStart = Lighting.FogStart,
            FogEnd = Lighting.FogEnd, GlobalShadows = Lighting.GlobalShadows,
        }
    end
    ApplyBright()
    if not BrightLoop then
        BrightLoop = true
        task.spawn(function()
            while Alive and BrightLoop do
                task.wait(1)
                ApplyBright()
            end
        end)
    end
    Notify("สว่าง", "ปรับแสงให้สว่างแล้ว")
end

local function BrightRestore()
    BrightLoop = false
    if BrightSaved then
        local sv = BrightSaved
        BrightSaved = nil
        for prop, val in pairs(sv) do
            pcall(function() Lighting[prop] = val end)
        end
        Notify("สว่าง", "คืนค่าแสงเดิมแล้ว (หมอก Atmosphere ที่ปิดไปจะกลับมาเมื่อเกมตั้งค่าใหม่)")
    end
end

-- ============================================================
-- ปุ่มลอย ESP (ผี / ประตู / สมุด / กุญแจ)
--   ลากย้ายได้ / กดเพื่อเปิด-ปิด / ปรับขนาดแยกปุ่ม / ล็อกทุกปุ่มพร้อมกัน
-- ============================================================
local FloatOrder = { "ghost", "door", "book", "key" }
local FloatInfo = {
    ghost = { title = "GHOST ESP", y = 0.28, show = true },
    door  = { title = "DOOR ESP",  y = 0.40, show = true },
    book  = { title = "BOOK ESP",  y = 0.52, show = false },
    key   = { title = "KEY ESP",   y = 0.64, show = false },
}
local FLOAT_W = 104
local Floats = {}
local FloatLock = false
local Toggles = {}       -- สวิตช์ใน Rayfield ของแต่ละหมวด (ใช้ซิงก์กับปุ่มลอย)

local function FloatH(w)
    return math.clamp(math.floor(w * 0.46), 34, 72)
end

local function RefreshFloat(cat)
    local fl = Floats[cat]
    if not fl then return end
    local on = Cfg[cat].on
    local col = Cfg[cat].color
    fl.btn.Size = UDim2.fromOffset(fl.w, FloatH(fl.w))
    fl.btn.TextSize = math.clamp(math.floor(fl.w * 0.13), 10, 22)
    fl.btn.Text = FloatInfo[cat].title .. "\n" .. (on and "ON" or "OFF")
    fl.btn.TextColor3 = on and col or Color3.fromRGB(235, 235, 235)
    fl.stroke.Color = on and col or Color3.fromRGB(200, 200, 200)
    fl.lock.Visible = FloatLock
end

local function RefreshAllFloats()
    for _, cat in ipairs(FloatOrder) do RefreshFloat(cat) end
end

-- เปิด/ปิด ESP ของหมวด (ใช้ร่วมกันทั้งปุ่มลอยและสวิตช์ใน UI)
local function ApplyCat(cat, v)
    Cfg[cat].on = v and true or false
    RefreshFloat(cat)
end

do
    -- เก็บการกดแยกตาม "นิ้ว/เมาส์" แต่ละอัน (key = input object)
    -- กันนิ้วที่ใช้เดิน (จอยสติ๊ก) ไปปนกับนิ้วที่กดปุ่ม จึงเดินไปกดไปได้พร้อมกัน
    local drags = {}   -- [input] = { cat, start, startBtn, moved }

    for _, cat in ipairs(FloatOrder) do
        local info = FloatInfo[cat]
        local btn = Instance.new("TextButton")
        btn.Name = RName()
        btn.AutoButtonColor = false
        btn.AnchorPoint = Vector2.new(0, 0)
        btn.Size = UDim2.fromOffset(FLOAT_W, FloatH(FLOAT_W))
        btn.Position = UDim2.new(1, -(FLOAT_W + 16), info.y, 0)
        btn.BackgroundColor3 = Color3.new(0, 0, 0)
        btn.BackgroundTransparency = 0.15
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 14
        btn.TextColor3 = Color3.fromRGB(235, 235, 235)
        btn.Text = info.title .. "\nOFF"
        btn.ZIndex = 5
        btn.Visible = info.show
        btn.Parent = Gui

        local stroke = Instance.new("UIStroke")
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Thickness = 2
        stroke.Color = Color3.fromRGB(200, 200, 200)
        stroke.Parent = btn

        local lock = Instance.new("TextLabel")
        lock.BackgroundTransparency = 1
        lock.Size = UDim2.new(1, 0, 0, 12)
        lock.Position = UDim2.new(0, 0, 1, -13)
        lock.Font = Enum.Font.GothamBold
        lock.TextSize = 9
        lock.TextColor3 = Color3.fromRGB(80, 255, 120)
        lock.Text = "LOCKED"
        lock.Visible = false
        lock.ZIndex = 6
        lock.Parent = btn

        Floats[cat] = { btn = btn, stroke = stroke, lock = lock, w = FLOAT_W, defaultPos = btn.Position }

        Connect(btn.InputBegan, function(input)
            local t = input.UserInputType
            if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
                drags[input] = { cat = cat, start = input.Position, startBtn = btn.Position, moved = false }
            end
        end)
    end

    local function DragMove(d, pos)
        local delta = pos - d.start
        if delta.Magnitude > 8 then d.moved = true end
        if d.moved and not FloatLock then
            local sb = d.startBtn
            Floats[d.cat].btn.Position = UDim2.new(
                sb.X.Scale, sb.X.Offset + delta.X, sb.Y.Scale, sb.Y.Offset + delta.Y)
        end
    end

    Connect(UIS.InputChanged, function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.Touch then
            -- ใช้เฉพาะนิ้วที่กดปุ่มนี้เท่านั้น นิ้วอื่น (เช่น จอยเดิน) ไม่เกี่ยว
            local d = drags[input]
            if d then DragMove(d, input.Position) end
        elseif t == Enum.UserInputType.MouseMovement then
            for inp, d in pairs(drags) do
                if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                    DragMove(d, input.Position)
                end
            end
        end
    end)

    Connect(UIS.InputEnded, function(input)
        local d = drags[input]
        if not d then return end            -- ไม่ใช่นิ้ว/เมาส์ที่กดปุ่ม = ไม่ทำอะไร
        drags[input] = nil
        if not d.moved then
            local cat = d.cat
            local nv = not Cfg[cat].on
            ApplyCat(cat, nv)
            local tg = Toggles[cat]
            if tg then pcall(function() tg:Set(nv) end) end
        end
    end)
end

RefreshAllFloats()

-- ============================================================
-- Unload
-- ============================================================
local function Unload()
    if not Alive then return end
    Alive = false
    for _, c in ipairs(Conns) do
        pcall(function() c:Disconnect() end)
    end
    Conns = {}
    for inst in pairs(Tracked) do Untrack(inst) end
    pcall(function() Folder:Destroy() end)
    pcall(function() Gui:Destroy() end)
    pcall(function() if RayfieldRef then RayfieldRef:Destroy() end end)
    if env.GhostHubUnload == Unload then env.GhostHubUnload = nil end
end
env.GhostHubUnload = Unload

-- ============================================================
-- Rayfield UI
-- ============================================================
local Rayfield
do
    local ok, lib = pcall(function()
        return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    end)
    if ok and type(lib) == "table" then Rayfield = lib end
end

if not Rayfield then
    Notify("DOORS ESP Hub", "โหลด Rayfield ไม่ได้ (เช็คเน็ต/executor) สคริปต์ถูกปิด")
    Unload()
    return
end
RayfieldRef = Rayfield

local Window = Rayfield:CreateWindow({
    Name = "DOORS ESP Hub",
    LoadingTitle = "DOORS ESP Hub",
    LoadingSubtitle = "Rayfield UI",
    ConfigurationSaving = { Enabled = false },
    Discord = { Enabled = false },
    KeySystem = false,
})

local function MakeTab(name, icon)
    local ok, tab = pcall(function() return Window:CreateTab(name, icon) end)
    if ok and tab then return tab end
    return Window:CreateTab(name)
end

-- สีของหมวดเปลี่ยน -> วาดสี ESP + ปุ่มลอยใหม่
local function OnColor(cat, key, c)
    Cfg[cat][key] = c
    RecolorCat(cat)
    RefreshFloat(cat)
end

-- ---------- หมวด 1: Ghost ESP ----------
local GhostTab = MakeTab("Ghost ESP", "ghost")
GhostTab:CreateSection("ESP ผี")
Toggles.ghost = GhostTab:CreateToggle({
    Name = "ESP ผี (เปิด/ปิด)",
    CurrentValue = Cfg.ghost.on,
    Callback = function(v) ApplyCat("ghost", v) end,
})
GhostTab:CreateToggle({
    Name = "แสดงผีทุกตัวในเกม",
    CurrentValue = true,
    Callback = function(v) Cfg.ghost.all = v end,
})
GhostTab:CreateDropdown({
    Name = "เลือกผีที่จะแสดง (ใช้เมื่อปิด 'ผีทุกตัว')",
    Options = EntityOptions,
    CurrentOption = EntityOptions,
    MultipleOptions = true,
    Callback = function(opt)
        local sel = {}
        if type(opt) == "table" then
            for _, v in ipairs(opt) do sel[v] = true end
        elseif type(opt) == "string" then
            sel[opt] = true
        end
        Cfg.ghost.sel = sel
    end,
})
GhostTab:CreateToggle({
    Name = "เส้นชี้ไปหาผี",
    CurrentValue = true,
    Callback = function(v) Cfg.ghost.line = v end,
})
GhostTab:CreateColorPicker({
    Name = "สี ESP ผี (ค่าเริ่มต้น: แดง)",
    Color = Cfg.ghost.color,
    Callback = function(c) OnColor("ghost", "color", c) end,
})
GhostTab:CreateSection("สถานะ")
local GhostStatus = GhostTab:CreateLabel("ผีที่พบตอนนี้: 0")
GhostTab:CreateParagraph({
    Title = "ผีที่ครอบคลุม",
    Content = "Rush, Ambush, A-60, A-120, Eyes, Halt, Screech, Seek, Figure, Dupe, Timothy, Jeff, Giggle, Grumble, Snare, Dread, Glitch, Void, Shadow, Lookman, Bob, Sally, Jack, Surge, Sorrow, Haste, Hide (รวมเวอร์ชัน Backdoor) และผีทั่วไปที่ชื่อคล้ายผี สแกนให้เองตลอดเวลา ESP ขึ้นทันทีที่เกิด",
})

-- ---------- หมวด 2: Key / Door / Book ESP ----------
local KDTab = MakeTab("Key/Door/Book ESP", "key")
KDTab:CreateSection("กุญแจ")
Toggles.key = KDTab:CreateToggle({
    Name = "ESP กุญแจ",
    CurrentValue = false,
    Callback = function(v) ApplyCat("key", v) end,
})
KDTab:CreateToggle({
    Name = "เส้นชี้ไปหากุญแจ",
    CurrentValue = true,
    Callback = function(v) Cfg.key.line = v end,
})
KDTab:CreateColorPicker({
    Name = "สี ESP กุญแจ",
    Color = Cfg.key.color,
    Callback = function(c) OnColor("key", "color", c) end,
})

KDTab:CreateSection("สมุด (Book) ห้อง 50")
Toggles.book = KDTab:CreateToggle({
    Name = "ESP สมุด (ห้อง 50 ห้องสมุด)",
    CurrentValue = Cfg.book.on,
    Callback = function(v) ApplyCat("book", v) end,
})
KDTab:CreateToggle({
    Name = "เส้นชี้ไปหาสมุด",
    CurrentValue = true,
    Callback = function(v) Cfg.book.line = v end,
})
KDTab:CreateToggle({
    Name = "เฉพาะห้อง 50 (ปิด = แสดงสมุดทุกห้อง)",
    CurrentValue = true,
    Callback = function(v) Cfg.book.only50 = v end,
})
KDTab:CreateColorPicker({
    Name = "สี ESP สมุด",
    Color = Cfg.book.color,
    Callback = function(c) OnColor("book", "color", c) end,
})

KDTab:CreateSection("ประตู")
Toggles.door = KDTab:CreateToggle({
    Name = "ESP ประตูที่ถูกต้อง",
    CurrentValue = false,
    Callback = function(v) ApplyCat("door", v) end,
})
KDTab:CreateToggle({
    Name = "เส้นชี้ไปหาประตู",
    CurrentValue = true,
    Callback = function(v) Cfg.door.line = v end,
})
KDTab:CreateToggle({
    Name = "แสดงประตูปลอม (Dupe) ด้วย",
    CurrentValue = false,
    Callback = function(v) Cfg.door.showFake = v end,
})
KDTab:CreateColorPicker({
    Name = "สี ESP ประตูที่ถูกต้อง",
    Color = Cfg.door.color,
    Callback = function(c) OnColor("door", "color", c) end,
})
KDTab:CreateColorPicker({
    Name = "สี ESP ประตูปลอม",
    Color = Cfg.door.fakeColor,
    Callback = function(c) OnColor("door", "fakeColor", c) end,
})

KDTab:CreateSection("สถานะ")
local KeyStatus = KDTab:CreateLabel("กุญแจที่พบ: 0")
local BookStatus = KDTab:CreateLabel("สมุดที่พบ: 0")
local DoorStatus = KDTab:CreateLabel("ประตูที่ถูกต้อง: 0 | ประตูปลอม: 0")
KDTab:CreateParagraph({
    Title = "การทำงาน",
    Content = "ประตู: อ่านจาก Workspace.CurrentRooms ชื่อ DoorFake = ปลอม ถ้าห้องมีประตูหลายบานจะเทียบเลขบนป้ายกับห้องถัดไปด้วย ซ่อนประตูห้องที่ผ่านแล้วอัตโนมัติ / สมุด: เมื่อเก็บแล้ว ESP ของสมุดเล่มนั้นจะหายและไม่กลับมาอีก",
})

-- ---------- หมวด 3: ปุ่มลอย ----------
local FloatTab = MakeTab("ปุ่มลอย", "mouse-pointer-click")
local FloatNames = { ghost = "ESP ผี", door = "ESP ประตู", book = "ESP สมุด", key = "ESP กุญแจ" }
local SizeSliders = {}

FloatTab:CreateSection("ทุกปุ่ม")
FloatTab:CreateToggle({
    Name = "ล็อกปุ่มลอยทุกปุ่ม (กันลากโดน)",
    CurrentValue = false,
    Callback = function(v)
        FloatLock = v
        RefreshAllFloats()
    end,
})
FloatTab:CreateSlider({
    Name = "ขนาดปุ่มทุกปุ่ม",
    Range = { 70, 200 },
    Increment = 2,
    Suffix = " px",
    CurrentValue = FLOAT_W,
    Callback = function(v)
        for _, cat in ipairs(FloatOrder) do
            Floats[cat].w = v
            RefreshFloat(cat)
            local sl = SizeSliders[cat]
            if sl then pcall(function() sl:Set(v) end) end
        end
    end,
})
FloatTab:CreateButton({
    Name = "รีเซ็ตตำแหน่งและขนาดปุ่ม",
    Callback = function()
        for _, cat in ipairs(FloatOrder) do
            Floats[cat].btn.Position = Floats[cat].defaultPos
            Floats[cat].w = FLOAT_W
            RefreshFloat(cat)
            local sl = SizeSliders[cat]
            if sl then pcall(function() sl:Set(FLOAT_W) end) end
        end
    end,
})

for _, cat in ipairs(FloatOrder) do
    FloatTab:CreateSection("ปุ่ม " .. FloatNames[cat])
    FloatTab:CreateToggle({
        Name = "แสดงปุ่มลอย " .. FloatNames[cat],
        CurrentValue = FloatInfo[cat].show,
        Callback = function(v) Floats[cat].btn.Visible = v end,
    })
    SizeSliders[cat] = FloatTab:CreateSlider({
        Name = "ขนาดปุ่ม " .. FloatNames[cat],
        Range = { 70, 200 },
        Increment = 2,
        Suffix = " px",
        CurrentValue = FLOAT_W,
        Callback = function(v)
            Floats[cat].w = v
            RefreshFloat(cat)
        end,
    })
end
FloatTab:CreateParagraph({
    Title = "วิธีใช้",
    Content = "กดปุ่มเพื่อเปิด/ปิด ESP (ซิงก์กับสวิตช์ในเมนู) ลากเพื่อย้ายตำแหน่ง เปิดล็อกแล้วปุ่มจะขึ้นป้าย LOCKED และลากไม่ได้ แต่ยังกดใช้งานได้ปกติ",
})

-- ---------- หมวด 4: Graphics ----------
local GfxTab = MakeTab("Graphics", "monitor")
GfxTab:CreateSection("ลดกราฟิก")
GfxTab:CreateButton({
    Name = "Low Graphics (ลบกราฟิก/เอฟเฟกต์ทั้งหมด กดครั้งเดียว)",
    Callback = LowGraphics,
})
GfxTab:CreateParagraph({
    Title = "ปุ่มนี้ทำอะไร",
    Content = "ลบ texture/Decal/ลายทั้งหมด วัสดุเรียบทุกชิ้น ปิดพาร์ติเคิลและเอฟเฟกต์ทุกชนิด (Trail/Beam/Smoke/Fire/Sparkles/Explosion/Highlight ของเกม) ปิดเงา/ความเงา ปิด PostEffect ทุกตัว หมอก น้ำ/หญ้า/เมฆ Quality ต่ำสุด และ Lighting แบบ Compatibility (ถ้า executor รองรับ) คงตัวไฟไว้เพื่อให้ยังมองเห็นในที่มืด เป็นปุ่มกด ไม่ใช่สวิตช์ หลังกดแล้วห้องใหม่จะถูกลดให้เองจนกว่าจะ rejoin",
})
GfxTab:CreateSection("แสง")
GfxTab:CreateButton({
    Name = "สว่าง (กดครั้งเดียว)",
    Callback = BrightPress,
})
GfxTab:CreateButton({
    Name = "คืนค่าแสงเดิม",
    Callback = BrightRestore,
})
GfxTab:CreateParagraph({
    Title = "ปุ่มสว่าง",
    Content = "ปรับแสงรอบตัวให้สว่างทั้งแมพและเอาหมอกออก เป็นปุ่มกด ไม่ใช่สวิตช์ หลังกดจะย้ำค่าให้ทุก 1 วินาทีเพราะเกมชอบรีเซ็ตแสง กด 'คืนค่าแสงเดิม' เพื่อหยุด",
})

-- ---------- หมวด 5: Misc ----------
local MiscTab = MakeTab("Misc", "settings")
MiscTab:CreateSection("เส้น / ระยะ ESP")
MiscTab:CreateDropdown({
    Name = "จุดเริ่มต้นของเส้น (ใช้กับทุก ESP)",
    Options = { "Bottom", "Center", "Top" },
    CurrentOption = { "Bottom" },
    MultipleOptions = false,
    Callback = function(opt)
        local v = (type(opt) == "table") and opt[1] or opt
        if v then S.LineOrigin = v end
    end,
})
MiscTab:CreateSlider({
    Name = "ระยะ ESP สูงสุด (0 = ไม่จำกัด, ไม่รวมประตู)",
    Range = { 0, 1000 },
    Increment = 10,
    Suffix = " studs",
    CurrentValue = 0,
    Callback = function(v) S.MaxDist = v end,
})
MiscTab:CreateSection("ระบบ")
MiscTab:CreateButton({
    Name = "ปิดสคริปต์ (Unload)",
    Callback = Unload,
})

-- อัปเดตตัวเลขสถานะ
task.spawn(function()
    while Alive do
        local g, k, bk, dr, df = 0, 0, 0, 0, 0
        for _, o in pairs(Tracked) do
            if o.cat == "ghost" then
                g = g + 1
            elseif o.cat == "key" then
                k = k + 1
            elseif o.cat == "book" then
                bk = bk + 1
            elseif o.kind == "fake" then
                df = df + 1
            else
                dr = dr + 1
            end
        end
        pcall(function() GhostStatus:Set("ผีที่พบตอนนี้: " .. g) end)
        pcall(function() KeyStatus:Set("กุญแจที่พบ: " .. k) end)
        pcall(function() BookStatus:Set("สมุดที่พบ: " .. bk) end)
        pcall(function() DoorStatus:Set("ประตูที่ถูกต้อง: " .. dr .. " | ประตูปลอม: " .. df) end)
        task.wait(1)
    end
end)

Notify("DOORS ESP Hub", "โหลดสำเร็จ")
