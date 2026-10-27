--[[
    Novrax Hub - Blox Fruits (sıfırdan yazıldı)
    Modüller: Server Hop / Fruit Finder, ESP, FPS Boost, UI
    Not: Auto-Hop'un yeni sunucuda devam edebilmesi için ScriptURL'yi doldur.
]]

-- Tekrar çalıştırma koruması
if getgenv().NovraxHubUnload then pcall(getgenv().NovraxHubUnload) end

if not game:IsLoaded() then game.Loaded:Wait() end

------------------------------------------------------------------
-- AYARLAR
------------------------------------------------------------------
local Config = {
    ScriptURL   = "",                       -- Scriptin raw linki (queue_on_teleport için)
    TikTokURL   = "https://www.tiktok.com/@novrax",  -- Kendi linkinle değiştir
    ScanDelay   = 6,                        -- Yeni sunucuda tarama öncesi bekleme (sn)
    HopCooldown = 1800,                     -- Ziyaret edilen sunucuyu tekrar seçmeme süresi (sn)
    MaxPages    = 5,                        -- Sunucu listesinde taranacak sayfa
    ESPInterval = 0.4,                      -- ESP yenileme aralığı (sn)
    FileName    = "NovraxHub/data.json",
}

------------------------------------------------------------------
-- SERVİSLER
------------------------------------------------------------------
local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local RunService      = game:GetService("RunService")
local UserInput       = game:GetService("UserInputService")
local Lighting        = game:GetService("Lighting")
local Workspace       = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Connections = {}
local function track(c) table.insert(Connections, c); return c end

------------------------------------------------------------------
-- YARDIMCILAR
------------------------------------------------------------------
local httpRequest = (syn and syn.request) or http_request or request or (fluxus and fluxus.request)
local queueTp     = queue_on_teleport or (syn and syn.queue_on_teleport)

local function httpGet(url)
    if httpRequest then
        local ok, res = pcall(httpRequest, {Url = url, Method = "GET"})
        if ok and res and res.StatusCode == 200 then return res.Body end
    end
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok then return body end
end

local function getRoot()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

------------------------------------------------------------------
-- VERİ (ziyaret edilen sunucular, fruit logu, auto durumu)
------------------------------------------------------------------
local Data = {visited = {}, log = {}, auto = false}

local function saveData()
    if not (writefile and makefolder) then return end
    pcall(function()
        if isfolder and not isfolder("NovraxHub") then makefolder("NovraxHub") end
        writefile(Config.FileName, HttpService:JSONEncode(Data))
    end)
end

local function loadData()
    if not (readfile and isfile) then return end
    pcall(function()
        if isfile(Config.FileName) then
            local d = HttpService:JSONDecode(readfile(Config.FileName))
            if type(d) == "table" then
                Data.visited = d.visited or {}
                Data.log     = d.log or {}
                Data.auto    = d.auto == true
            end
        end
    end)
end
loadData()

-- Eski kayıtları temizle
do
    local now = os.time()
    for id, t in pairs(Data.visited) do
        if now - t > Config.HopCooldown then Data.visited[id] = nil end
    end
    while #Data.log > 40 do table.remove(Data.log, 1) end
end

------------------------------------------------------------------
-- FRUIT TARAMA
------------------------------------------------------------------
local function scanFruits()
    local found = {}
    for _, o in ipairs(Workspace:GetChildren()) do
        if (o:IsA("Tool") or o:IsA("Model")) and o.Name:find("Fruit") then
            local part = o:FindFirstChild("Handle") or o.PrimaryPart or o:FindFirstChildWhichIsA("BasePart", true)
            if part then table.insert(found, {name = o.Name, part = part, obj = o}) end
        end
    end
    return found
end

local function scanChests()
    local found = {}
    local folder = Workspace:FindFirstChild("ChestModels")
    if folder then
        for _, o in ipairs(folder:GetChildren()) do
            local part = o:IsA("BasePart") and o or o:FindFirstChildWhichIsA("BasePart", true)
            if part then table.insert(found, {name = "Chest", part = part, obj = o}) end
        end
    end
    return found
end

local function logCurrentServer()
    local names = {}
    for _, f in ipairs(scanFruits()) do table.insert(names, f.name) end
    -- aynı sunucu için eski kaydı güncelle
    for i = #Data.log, 1, -1 do
        if Data.log[i].job == game.JobId then table.remove(Data.log, i) end
    end
    table.insert(Data.log, {job = game.JobId, place = game.PlaceId, fruits = names, time = os.time()})
    saveData()
    return names
end

------------------------------------------------------------------
-- SERVER HOP (773 dostu: aynı PlaceId + public sunucu listesi)
------------------------------------------------------------------
local Status = function(_) end
local hopping = false
local lastTpError

track(TeleportService.TeleportInitFailed:Connect(function(plr, result, msg)
    if plr == LocalPlayer then lastTpError = tostring(result) .. " | " .. tostring(msg) end
end))

local function fetchPage(cursor)
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100"):format(game.PlaceId)
    if cursor then url = url .. "&cursor=" .. cursor end
    local body = httpGet(url)
    if not body then return end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if ok then return data end
end

local function collectCandidates()
    local list, cursor = {}, nil
    for _ = 1, Config.MaxPages do
        local page = fetchPage(cursor)
        if not page or not page.data then break end
        for _, s in ipairs(page.data) do
            if s.id ~= game.JobId
                and not Data.visited[s.id]
                and s.playing and s.maxPlayers
                and s.playing < s.maxPlayers - 1 then
                table.insert(list, s.id)
            end
        end
        cursor = page.nextPageCursor
        if not cursor then break end
        task.wait(0.4)
    end
    return list
end

local function persistOnTeleport()
    if not queueTp then return end
    if Config.ScriptURL == "" then return end
    queueTp(('loadstring(game:HttpGet("%s"))()'):format(Config.ScriptURL))
end

local function teleportTo(jobId)
    lastTpError = nil
    Data.visited[jobId] = os.time()
    saveData()
    persistOnTeleport()
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, LocalPlayer)
    end)
    if not ok then lastTpError = tostring(err) end
    local t = 0
    while t < 12 and not lastTpError do task.wait(0.5); t = t + 0.5 end
    return lastTpError == nil
end

local function serverHop()
    if hopping then return end
    hopping = true
    task.spawn(function()
        for attempt = 1, 4 do
            Status("Sunucu aranıyor... (" .. attempt .. "/4)")
            local list = collectCandidates()
            if #list == 0 then
                Data.visited = {}
                Status("Uygun sunucu yok, liste sıfırlandı.")
                task.wait(2)
            else
                local id = list[math.random(1, #list)]
                Status("Işınlanıyor...")
                if teleportTo(id) then hopping = false return end
                Status("Hata: " .. tostring(lastTpError):sub(1, 40))
                task.wait(1.5)
            end
        end
        Status("Hop başarısız, tekrar dene.")
        hopping = false
    end)
end

------------------------------------------------------------------
-- ESP
------------------------------------------------------------------
local ESP = {fruit = false, chest = false, items = {}}

local function parentGui()
    if gethui then local ok, h = pcall(gethui); if ok and h then return h end end
    local ok = pcall(function() return game:GetService("CoreGui").Name end)
    return ok and game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")
end

local espFolder = Instance.new("Folder")
espFolder.Name = "NovraxESP"
espFolder.Parent = parentGui()

local function clearESP(kind)
    for obj, e in pairs(ESP.items) do
        if not kind or e.kind == kind then
            e.gui:Destroy(); e.hl:Destroy()
            ESP.items[obj] = nil
        end
    end
end

local function makeESP(entry, kind, color)
    local gui = Instance.new("BillboardGui")
    gui.Adornee = entry.part
    gui.AlwaysOnTop = true
    gui.Size = UDim2.fromOffset(120, 36)
    gui.StudsOffset = Vector3.new(0, 3, 0)
    gui.Parent = espFolder

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.TextColor3 = color
    lbl.TextStrokeTransparency = 0.3
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 13
    lbl.Parent = gui

    local hl = Instance.new("Highlight")
    hl.Adornee = entry.obj
    hl.FillColor = color
    hl.FillTransparency = 0.6
    hl.OutlineColor = color
    hl.Parent = espFolder

    ESP.items[entry.obj] = {gui = gui, hl = hl, lbl = lbl, part = entry.part, name = entry.name, kind = kind}
end

local function updateESP()
    local root = getRoot()
    local seen = {}

    local function handle(list, kind, color)
        for _, e in ipairs(list) do
            seen[e.obj] = true
            if not ESP.items[e.obj] then makeESP(e, kind, color) end
        end
    end
    if ESP.fruit then handle(scanFruits(), "fruit", Color3.fromRGB(255, 90, 160)) end
    if ESP.chest then handle(scanChests(), "chest", Color3.fromRGB(255, 220, 80)) end

    for obj, e in pairs(ESP.items) do
        if not seen[obj] or not obj.Parent or not e.part.Parent then
            e.gui:Destroy(); e.hl:Destroy(); ESP.items[obj] = nil
        elseif root then
            local d = math.floor((e.part.Position - root.Position).Magnitude)
            e.lbl.Text = ("%s\n[%dm]"):format(e.name, d)
        end
    end
end

task.spawn(function()
    while getgenv().NovraxHubLoaded do
        if ESP.fruit or ESP.chest or next(ESP.items) then pcall(updateESP) end
        task.wait(Config.ESPInterval)
    end
end)

------------------------------------------------------------------
-- FPS BOOST (mobil dostu, parça parça işler)
------------------------------------------------------------------
local fpsBoosted = false
local function fpsBoost()
    if fpsBoosted then return end
    fpsBoosted = true
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    pcall(function() Lighting.GlobalShadows = false; Lighting.FogEnd = 9e9; Lighting.Brightness = 1 end)
    for _, v in ipairs(Lighting:GetChildren()) do
        if v:IsA("BlurEffect") or v:IsA("SunRaysEffect") or v:IsA("BloomEffect")
            or v:IsA("ColorCorrectionEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("Atmosphere") then
            v.Enabled = v:IsA("Atmosphere") and v.Enabled or false
            if v:IsA("Atmosphere") then v.Density = 0 end
        end
    end
    if setfpscap then pcall(setfpscap, 60) end

    task.spawn(function()
        local n = 0
        for _, o in ipairs(Workspace:GetDescendants()) do
            if o:IsA("BasePart") then
                o.Material = Enum.Material.SmoothPlastic
                o.CastShadow = false
            elseif o:IsA("ParticleEmitter") or o:IsA("Trail") or o:IsA("Smoke")
                or o:IsA("Fire") or o:IsA("Sparkles") then
                o.Enabled = false
            elseif o:IsA("Decal") or o:IsA("Texture") then
                o.Transparency = 1
            end
            n = n + 1
            if n % 400 == 0 then task.wait() end -- donmayı önler
        end
        Status("FPS Boost uygulandı.")
    end)
end

------------------------------------------------------------------
-- ARAYÜZ
------------------------------------------------------------------
local function new(class, props, parent)
    local i = Instance.new(class)
    for k, v in pairs(props) do i[k] = v end
    i.Parent = parent
    return i
end

local C = {
    bg = Color3.fromRGB(18, 18, 24), bar = Color3.fromRGB(28, 28, 38),
    item = Color3.fromRGB(38, 38, 52), accent = Color3.fromRGB(120, 90, 255),
    text = Color3.fromRGB(235, 235, 245), sub = Color3.fromRGB(150, 150, 170),
}

local Gui = new("ScreenGui", {Name = "NovraxHub", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, parentGui())
local Main = new("Frame", {
    Size = UDim2.fromOffset(330, 360), Position = UDim2.new(0.5, -165, 0.5, -180),
    BackgroundColor3 = C.bg, BorderSizePixel = 0, ClipsDescendants = true,
}, Gui)
new("UICorner", {CornerRadius = UDim.new(0, 10)}, Main)

-- Üst bar
local Bar = new("Frame", {Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = C.bar, BorderSizePixel = 0}, Main)
new("TextLabel", {
    Text = "NOVRAX HUB", Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = C.text,
    BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -120, 1, 0),
    TextXAlignment = Enum.TextXAlignment.Left,
}, Bar)

local function barButton(text, offsetX, color)
    local b = new("TextButton", {
        Text = text, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.text,
        BackgroundColor3 = color, Size = UDim2.fromOffset(28, 26),
        Position = UDim2.new(1, offsetX, 0, 5), AutoButtonColor = true,
    }, Bar)
    new("UICorner", {CornerRadius = UDim.new(0, 6)}, b)
    return b
end

-- TikTok ikonu (ikon asset ID'n varsa Text yerine ImageLabel kullanabilirsin)
local tikBtn = barButton("♪", -104, Color3.fromRGB(0, 0, 0))
new("UIStroke", {Color = Color3.fromRGB(37, 244, 238), Thickness = 1.5}, tikBtn)
tikBtn.TextColor3 = Color3.fromRGB(254, 44, 85)
local minBtn   = barButton("–", -70, C.item)
local closeBtn = barButton("X", -36, Color3.fromRGB(190, 60, 70))

-- Sürükleme
do
    local dragging, startPos, startInput
    track(Bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, startPos, startInput = true, Main.Position, i.Position
        end
    end))
    track(UserInput.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startInput
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    track(UserInput.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
end

-- Durum çubuğu
local StatusLbl = new("TextLabel", {
    Text = "Hazır.", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.sub,
    BackgroundTransparency = 1, Position = UDim2.new(0, 10, 1, -22), Size = UDim2.new(1, -20, 0, 18),
    TextXAlignment = Enum.TextXAlignment.Left,
}, Main)
Status = function(t) StatusLbl.Text = tostring(t) end

-- Sekmeler
local TabRow = new("Frame", {Position = UDim2.fromOffset(8, 42), Size = UDim2.new(1, -16, 0, 28), BackgroundTransparency = 1}, Main)
new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6)}, TabRow)

local Pages, TabButtons = {}, {}
local function addTab(name)
    local btn = new("TextButton", {
        Text = name, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.text,
        BackgroundColor3 = C.item, Size = UDim2.fromOffset(72, 28),
    }, TabRow)
    new("UICorner", {CornerRadius = UDim.new(0, 6)}, btn)

    local page = new("ScrollingFrame", {
        Position = UDim2.fromOffset(8, 76), Size = UDim2.new(1, -16, 1, -102),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Visible = false,
    }, Main)
    new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, page)

    Pages[name], TabButtons[name] = page, btn
    btn.MouseButton1Click:Connect(function()
        for n, p in pairs(Pages) do
            p.Visible = (n == name)
            TabButtons[n].BackgroundColor3 = (n == name) and C.accent or C.item
        end
    end)
    return page
end

local function addButton(page, text, cb)
    local b = new("TextButton", {
        Text = text, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.text,
        BackgroundColor3 = C.item, Size = UDim2.new(1, -4, 0, 34),
    }, page)
    new("UICorner", {CornerRadius = UDim.new(0, 8)}, b)
    b.MouseButton1Click:Connect(cb)
    return b
end

local function addToggle(page, text, default, cb)
    local state = default
    local b = new("TextButton", {
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.text,
        BackgroundColor3 = C.item, Size = UDim2.new(1, -4, 0, 34),
    }, page)
    new("UICorner", {CornerRadius = UDim.new(0, 8)}, b)
    local function render()
        b.Text = text .. ":  " .. (state and "AÇIK" or "KAPALI")
        b.BackgroundColor3 = state and C.accent or C.item
    end
    render()
    b.MouseButton1Click:Connect(function() state = not state; render(); cb(state) end)
    return b
end

local function addLabel(page, text)
    return new("TextLabel", {
        Text = text, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.sub, TextWrapped = true,
        BackgroundTransparency = 1, Size = UDim2.new(1, -4, 0, 30), TextXAlignment = Enum.TextXAlignment.Left,
    }, page)
end

-- SEKME: SERVER
local pServer = addTab("Server")
addButton(pServer, "Server Hop", serverHop)
addButton(pServer, "Bu Sunucuyu Tara", function()
    local names = logCurrentServer()
    Status(#names > 0 and ("Bulundu: " .. table.concat(names, ", ")) or "Bu sunucuda meyve yok.")
    if _G.NovraxRefreshLog then _G.NovraxRefreshLog() end
end)

local autoToggle
autoToggle = addToggle(pServer, "Auto Hop + Fruit Finder", Data.auto, function(on)
    Data.auto = on; saveData()
    if on then
        if Config.ScriptURL == "" then Status("Uyarı: ScriptURL boş, yeni sunucuda devam etmez.") end
        task.spawn(function()
            local names = logCurrentServer()
            if #names > 0 then
                Data.auto = false; saveData(); ESP.fruit = true
                Status("Meyve bulundu: " .. table.concat(names, ", "))
            else serverHop() end
        end)
    end
end)

addLabel(pServer, "Sunucu Kayıtları (gezdiğin sunucular):")
local LogHolder = new("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y}, pServer)
new("UIListLayout", {Padding = UDim.new(0, 4)}, LogHolder)

local function refreshLog()
    for _, c in ipairs(LogHolder:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    for i = #Data.log, 1, -1 do
        local e = Data.log[i]
        local row = new("Frame", {BackgroundColor3 = C.item, Size = UDim2.new(1, 0, 0, 44)}, LogHolder)
        new("UICorner", {CornerRadius = UDim.new(0, 6)}, row)
        local fr = #e.fruits > 0 and table.concat(e.fruits, ", ") or "Meyve yok"
        new("TextLabel", {
            Text = tostring(e.job):sub(1, 8) .. "…  " .. fr, Font = Enum.Font.Gotham, TextSize = 11,
            TextColor3 = #e.fruits > 0 and Color3.fromRGB(255, 130, 180) or C.sub, TextWrapped = true,
            BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -70, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)
        local j = new("TextButton", {
            Text = "Katıl", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.text,
            BackgroundColor3 = C.accent, Size = UDim2.fromOffset(52, 28), Position = UDim2.new(1, -58, 0.5, -14),
        }, row)
        new("UICorner", {CornerRadius = UDim.new(0, 6)}, j)
        j.MouseButton1Click:Connect(function()
            Status("Kayıtlı sunucuya gidiliyor...")
            task.spawn(function()
                if not teleportTo(e.job) then Status("Katılamadı (dolu/kapanmış olabilir).") end
            end)
        end)
    end
end
_G.NovraxRefreshLog = refreshLog
refreshLog()

-- SEKME: ESP
local pESP = addTab("ESP")
addToggle(pESP, "Meyve ESP", false, function(v) ESP.fruit = v; if not v then clearESP("fruit") end end)
addToggle(pESP, "Sandık ESP", false, function(v) ESP.chest = v; if not v then clearESP("chest") end end)
addLabel(pESP, "Mesafe ve isim ekranda gösterilir.")

-- SEKME: FPS
local pFPS = addTab("FPS")
addButton(pFPS, "FPS Boost Uygula", fpsBoost)
addToggle(pFPS, "3D Render Kapat (AFK)", false, function(v)
    pcall(function() RunService:Set3dRenderingEnabled(not v) end)
end)
addLabel(pFPS, "Gölge, parçacık, doku ve efektleri azaltır.")

-- SEKME: INFO
local pInfo = addTab("Bilgi")
addLabel(pInfo, "Novrax Hub\nPlaceId: " .. game.PlaceId)
addButton(pInfo, "TikTok Linkini Kopyala", function()
    if setclipboard then setclipboard(Config.TikTokURL); Status("Link kopyalandı.") else Status(Config.TikTokURL) end
end)

tikBtn.MouseButton1Click:Connect(function()
    if setclipboard then setclipboard(Config.TikTokURL); Status("TikTok linki kopyalandı.") end
end)

-- Küçült / Kapat
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    Main.Size = minimized and UDim2.fromOffset(330, 36) or UDim2.fromOffset(330, 360)
end)

local function unload()
    getgenv().NovraxHubLoaded = false
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    clearESP()
    espFolder:Destroy()
    Gui:Destroy()
end
getgenv().NovraxHubUnload = unload
getgenv().NovraxHubLoaded = true
closeBtn.MouseButton1Click:Connect(unload)

-- İlk sekme
TabButtons["Server"].BackgroundColor3 = C.accent
Pages["Server"].Visible = true

------------------------------------------------------------------
-- AUTO MOD: yeni sunucuda devam et
------------------------------------------------------------------
if Data.auto then
    task.spawn(function()
        if not LocalPlayer.Character then LocalPlayer.CharacterAdded:Wait() end
        Status("Auto mod: sunucu yükleniyor...")
        task.wait(Config.ScanDelay)
        if not getgenv().NovraxHubLoaded then return end
        local names = logCurrentServer()
        refreshLog()
        if #names > 0 then
            Data.auto = false; saveData()
            ESP.fruit = true
            Status("Meyve bulundu: " .. table.concat(names, ", "))
        else
            Status("Meyve yok, sonraki sunucu...")
            task.wait(1.5)
            serverHop()
        end
    end)
end

Status("Novrax Hub yüklendi.")
