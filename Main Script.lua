local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/optimized/Whoa-lib/refs/heads/main/WhoaUI_lib.lua"))()

UI.Setup({
    Keys        = {"obby"},
    KeyURL      = "https://discord.gg/Q9xJ5s5RFg",
    KeyPersist  = false,
    Name        = "whoa obby",
    Version     = "v1",
    Icon        = "rbxassetid://134387754737125",
    SectionIcon = "rbxassetid://134387754737125",
    Snow        = true,
})

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")

local player = Players.LocalPlayer

local logging = false
local function dbg(msg)
    if logging then print("[AutoWin] " .. tostring(msg)) end
end

local ObbyRemotes, MapInfoRemote, PlayerWonRemote, RoundProgressRemote = nil, nil, nil, nil
task.spawn(function()
    ObbyRemotes         = RS:WaitForChild("ObbyRemotes", 15)
    MapInfoRemote       = ObbyRemotes and ObbyRemotes:WaitForChild("MapInfo",             8)
    PlayerWonRemote     = ObbyRemotes and ObbyRemotes:WaitForChild("PlayerWon",           8)
    RoundProgressRemote = ObbyRemotes and ObbyRemotes:WaitForChild("RoundProgressUpdate", 8)
end)

local CFG = {
    WIN_DELAY_MIN = 0.5,
    WIN_DELAY_MAX = 1.0,
    RETURN_DELAY  = 1.5,
    TOUCH_OFFSET  = Vector3.new(0, 3, 0),
    NOTIFICATIONS = true,
}

local autoWin       = false
local autoReturn    = true
local winAfterFirst = false
local ghostDuringWin = true
local currentMap    = nil
local roundActive   = false
local wonThisRound  = false
local winThread     = nil
local savedCFrame   = nil
local waitingWAF    = false

local function getChar() return player.Character end
local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function notify(title, msg, kind, dur)
    if CFG.NOTIFICATIONS then
        pcall(UI.Notify, title, msg, kind or "Info", dur or 3)
    end
end

local function safeCancel(t)
    if t then pcall(task.cancel, t) end
end
local function stopAll()
    safeCancel(winThread); winThread = nil
end

local function getWinpad(mapName)
    if not mapName then return nil end
    local folder = workspace:FindFirstChild(mapName)
    if not folder then return nil end
    return folder:FindFirstChild("winpad")
end

local function fireTouchWin(winpad)
    local hrp = getHRP()
    if not hrp or not winpad then return false end
    local ti = nil
    for _, child in ipairs(winpad:GetChildren()) do
        if child.ClassName == "TouchTransmitter" or child.ClassName == "TouchInterest" then
            ti = child; break
        end
    end
    if not ti then return false end
    pcall(firetouchinterest, hrp, ti, 0)
    task.wait(0.05)
    pcall(firetouchinterest, hrp, ti, 1)
    return true
end

local function setCharInvis(char, invisible)
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
            p.Transparency = invisible and 1 or 0
            pcall(function() p.LocalTransparencyModifier = invisible and 1 or 0 end)
            pcall(sethiddenproperty, p, "Transparency", invisible and 1 or 0)
        end
        if p:IsA("Decal") or p:IsA("Texture") then
            p.Transparency = invisible and 1 or 0
        end
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() hum.DisplayDistanceType = invisible and Enum.HumanoidDisplayDistanceType.None or Enum.HumanoidDisplayDistanceType.Subject end)
    end
end

local function doWinSequence(mapName, skipDelay)
    if not skipDelay then
        local delay = CFG.WIN_DELAY_MIN + math.random() * (CFG.WIN_DELAY_MAX - CFG.WIN_DELAY_MIN)
        task.wait(delay)
    end
    if not autoWin or wonThisRound then return end

    local hrp = getHRP()
    if not hrp then return end

    local winpad = getWinpad(mapName)
    if not winpad then
        notify("Auto Win", "winpad not found: " .. tostring(mapName), "Warning", 3)
        return
    end

    local char = getChar()
    local partTransps = {}

    if ghostDuringWin and char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                partTransps[p] = p.Transparency
            end
        end
        setCharInvis(char, true)
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end

    local startPos = hrp.CFrame
    local endPos   = CFrame.new(winpad.Position + CFG.TOUCH_OFFSET)
    local steps    = 6
    for i = 1, steps do
        hrp.CFrame = startPos:Lerp(endPos, i / steps)
        task.wait(0.02)
    end

    task.wait(0.08)

    local ok = fireTouchWin(winpad)
    if not ok then
        hrp.CFrame = CFrame.new(winpad.Position)
        task.wait(0.05)
        fireTouchWin(winpad)
    end

    task.wait(CFG.RETURN_DELAY)
    if not wonThisRound then
        fireTouchWin(winpad)
        task.wait(0.1)
    end

    if ghostDuringWin and char then
        setCharInvis(char, false)
        for p, t in pairs(partTransps) do
            pcall(function() p.Transparency = t end)
        end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end
end

local function startRound(mapName)
    currentMap   = mapName
    roundActive  = true
    wonThisRound = false
    waitingWAF   = false
    stopAll()
    local hrp = getHRP()
    if hrp then savedCFrame = hrp.CFrame end
    dbg("round started: " .. tostring(mapName))
    if autoWin then
        winThread = task.spawn(doWinSequence, mapName, false)
    end
end

local function endRound()
    roundActive  = false
    currentMap   = nil
    wonThisRound = false
    waitingWAF   = false
    stopAll()
end

local function scanForActiveRound()
    for _, child in ipairs(workspace:GetChildren()) do
        if child:FindFirstChild("winpad") then
            startRound(child.Name)
            return true
        end
    end
    return false
end

workspace.ChildAdded:Connect(function(child)
    task.wait(0.3)
    if child:FindFirstChild("winpad") then
        startRound(child.Name)
    end
end)

workspace.ChildRemoved:Connect(function(child)
    if child.Name == currentMap then
        endRound()
    end
end)

task.spawn(function()
    while true do
        task.wait(5)
        if not roundActive then
            scanForActiveRound()
        end
    end
end)

if MapInfoRemote then
    MapInfoRemote.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        if data.phase == "round" then
            startRound(data.mapName)
        elseif data.phase == "intermission" then
            endRound()
        end
    end)
end

if RoundProgressRemote then
    RoundProgressRemote.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        if winAfterFirst and autoWin and not wonThisRound and not waitingWAF and currentMap then
            if data.firstWinner ~= nil or (type(data.completed) == "number" and data.completed >= 1) then
                waitingWAF = true
                stopAll()
                notify("Auto Win", "someone won, rushing!", "Info", 2)
                winThread = task.spawn(function()
                    doWinSequence(currentMap, true)
                    waitingWAF = false
                end)
            end
        end
    end)
end

if PlayerWonRemote then
    PlayerWonRemote.OnClientEvent:Connect(function(place, coins)
        dbg("PlayerWonRemote fired | place=" .. tostring(place))
        wonThisRound = true
        waitingWAF   = false
        stopAll()
        if autoReturn and savedCFrame then
            task.spawn(function()
                task.wait(0.5)
                local hrp = getHRP()
                if hrp and savedCFrame then
                    hrp.CFrame = savedCFrame
                    notify("Auto Win", "round won! returned to position.", "Success", 3)
                end
            end)
        end
    end)
end

player.CharacterRemoving:Connect(function()
    stopAll()
    savedCFrame  = nil
    wonThisRound = false
    waitingWAF   = false
end)

task.spawn(scanForActiveRound)

local afkThread = nil

local function startAntiAfk()
    if afkThread then return end
    afkThread = task.spawn(function()
        while afkThread ~= nil do
            task.wait(55)
            pcall(function()
                local hrp = getHRP()
                if hrp then
                    local saved = hrp.CFrame
                    hrp.CFrame = saved * CFrame.new(0, 0.01, 0)
                    task.wait(0.05)
                    hrp.CFrame = saved
                end
            end)
            pcall(function()
                game:GetService("VirtualInputManager"):SendKeyEvent(true,  "Space", false, game)
                task.wait(0.1)
                game:GetService("VirtualInputManager"):SendKeyEvent(false, "Space", false, game)
            end)
            dbg("anti-afk ping")
        end
    end)
end

local function stopAntiAfk()
    if afkThread then
        pcall(task.cancel, afkThread)
        afkThread = nil
    end
end

local hatEnabled  = true
local hatId       = 215718515
local hatOffX, hatOffY, hatOffZ = 0, 0, 0
local hatInstance = nil
local hatWeld     = nil

local function removeHat()
    pcall(function()
        if hatInstance and hatInstance.Parent then hatInstance:Destroy() end
    end)
    hatInstance = nil
    hatWeld     = nil
end

local function updateHatWeld()
    if not hatWeld or not hatWeld.Parent then return end
    local char = getChar(); if not char then return end
    local head = char:FindFirstChild("Head"); if not head then return end
    local handle = hatWeld.Part1; if not handle then return end
    local att     = handle:FindFirstChildOfClass("Attachment")
    local headAtt = head:FindFirstChild("HatAttachment")
    if att and headAtt then
        hatWeld.C0 = headAtt.CFrame * CFrame.new(hatOffX, hatOffY, hatOffZ)
        hatWeld.C1 = att.CFrame
    else
        hatWeld.C0 = CFrame.new(hatOffX, hatOffY, hatOffZ)
        hatWeld.C1 = CFrame.new(0, 0, 0)
    end
end

local function applyHat()
    removeHat()
    if not hatEnabled then return end
    local char = getChar(); if not char then return end
    local head = char:FindFirstChild("Head"); if not head then return end

    local success, accessory = pcall(function()
        return game:GetObjects("rbxassetid://" .. tostring(hatId))[1]
    end)
    if not success or not accessory or not accessory:IsA("Accessory") then
        notify("Hat", "failed to load id: " .. tostring(hatId), "Warning", 3); return
    end

    local handle = accessory:FindFirstChild("Handle")
    if not handle then return end

    handle.CanCollide = false; handle.CanTouch = false
    handle.CanQuery   = false; handle.Massless  = true

    for _, w in pairs(handle:GetChildren()) do
        if w:IsA("Weld") or w:IsA("WeldConstraint") then w:Destroy() end
    end

    accessory.Parent = char

    local weld = Instance.new("Weld")
    weld.Part0 = head; weld.Part1 = handle

    local att     = handle:FindFirstChildOfClass("Attachment")
    local headAtt = head:FindFirstChild("HatAttachment")
    if att and headAtt then
        weld.C0 = headAtt.CFrame * CFrame.new(hatOffX, hatOffY, hatOffZ)
        weld.C1 = att.CFrame
    else
        weld.C0 = CFrame.new(hatOffX, hatOffY, hatOffZ)
        weld.C1 = CFrame.new(0, 0, 0)
    end
    weld.Parent = handle
    hatInstance = accessory; hatWeld = weld
    notify("Hat", "applied! id: " .. tostring(hatId), "Success", 2)
end

player.CharacterAdded:Connect(function()
    task.wait(0.5)
    if hatEnabled then applyHat() end
end)

local noclipConn = nil
local speedConn  = nil
local flyConn    = nil
local invisConn  = nil
local invisHL    = nil

local function startNoclip()
    if noclipConn then return end
    noclipConn = RunService.Stepped:Connect(function()
        if not UI.Flags["nc"] then return end
        local c = getChar(); if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end)
end
local function stopNoclip()
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    pcall(function()
        local c = getChar(); if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end)
end

local function startSpeed()
    if speedConn then return end
    speedConn = RunService.Heartbeat:Connect(function(dt)
        if not UI.Flags["spd"] then return end
        local c = getChar(); if not c then return end
        local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return end
        local spd  = UI.Flags["spdval"] or 80
        local move = Vector3.zero
        if UIS:IsKeyDown(Enum.KeyCode.W) then move += Vector3.new(0, 0, -1) end
        if UIS:IsKeyDown(Enum.KeyCode.S) then move += Vector3.new(0, 0,  1) end
        if UIS:IsKeyDown(Enum.KeyCode.A) then move += Vector3.new(-1, 0, 0) end
        if UIS:IsKeyDown(Enum.KeyCode.D) then move += Vector3.new( 1, 0, 0) end
        if move == Vector3.zero then return end
        local cam  = workspace.CurrentCamera
        local flat = CFrame.new(Vector3.zero, Vector3.new(
            cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z))
        hrp.CFrame = hrp.CFrame + flat:VectorToWorldSpace(move.Unit) * spd * dt
    end)
end
local function stopSpeed()
    if speedConn then speedConn:Disconnect(); speedConn = nil end
end

local function startFly()
    if flyConn then return end
    pcall(function() local hum = getHum(); if hum then hum.PlatformStand = true end end)
    flyConn = RunService.Heartbeat:Connect(function(dt)
        if not UI.Flags["fly"] then return end
        local c = getChar(); if not c then return end
        local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return end
        local spd  = UI.Flags["flyspd"] or 60
        local move = Vector3.zero
        local cam  = workspace.CurrentCamera
        if UIS:IsKeyDown(Enum.KeyCode.W)           then move += cam.CFrame.LookVector  end
        if UIS:IsKeyDown(Enum.KeyCode.S)           then move -= cam.CFrame.LookVector  end
        if UIS:IsKeyDown(Enum.KeyCode.A)           then move -= cam.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.D)           then move += cam.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space)       then move += Vector3.new(0, 1, 0)   end
        if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0, 1, 0)   end
        if move.Magnitude > 0 then
            hrp.CFrame = hrp.CFrame + move.Unit * spd * dt
        end
    end)
end
local function stopFly()
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    pcall(function() local hum = getHum(); if hum then hum.PlatformStand = false end end)
end

local function startInvis()
    local char = getChar(); if not char then return end
    setCharInvis(char, true)
    pcall(function()
        if invisHL then invisHL:Destroy() end
        local hl = Instance.new("Highlight")
        hl.Adornee             = char
        hl.FillColor           = Color3.fromRGB(255, 182, 215)
        hl.FillTransparency    = 0.5
        hl.OutlineColor        = Color3.fromRGB(255, 255, 255)
        hl.OutlineTransparency = 0
        hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent              = player.PlayerGui
        invisHL = hl
    end)
    if invisConn then invisConn:Disconnect() end
    invisConn = char.DescendantAdded:Connect(function(p)
        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
            task.wait()
            p.Transparency = 1
            pcall(sethiddenproperty, p, "Transparency", 1)
        end
    end)
end

local function stopInvis()
    if invisConn then invisConn:Disconnect(); invisConn = nil end
    pcall(function() if invisHL then invisHL:Destroy(); invisHL = nil end end)
    pcall(function()
        local char = getChar(); if not char then return end
        setCharInvis(char, false)
    end)
end

player.CharacterAdded:Connect(function()
    task.wait(0.3)
    if UI.Flags["nc"]  then startNoclip() end
    if UI.Flags["spd"] then startSpeed()  end
    if UI.Flags["fly"] then startFly()    end
    if UI.Flags["inv"] then task.wait(0.5); startInvis() end
    pcall(function()
        local hum = getHum(); if not hum then return end
        if UI.Flags["ws"] then hum.WalkSpeed = UI.Flags["ws"] end
        if UI.Flags["jp"] then hum.JumpPower  = UI.Flags["jp"] end
    end)
end)

local aL, aR, aTab, aSwitch = UI.AddTab("Auto Win")

local ctrlSec = UI.MakeSection(aL, "Control")
ctrlSec._tabName(aTab, aSwitch)

ctrlSec:AddCheckbox({
    Name = "Auto Win", Flag = "aw_on", Default = false,
    Callback = function(v)
        autoWin = v
        if not v then stopAll() end
        if v and roundActive and currentMap and not wonThisRound then
            winThread = task.spawn(doWinSequence, currentMap, false)
        end
        notify("Auto Win", v and "enabled" or "disabled", v and "Success" or "Warning", 2)
    end,
})

ctrlSec:AddCheckbox({
    Name = "Auto Return After Win", Flag = "aw_ret_en", Default = true,
    Callback = function(v)
        autoReturn = v
        notify("Auto Return", v and "enabled" or "disabled", v and "Success" or "Warning", 2)
    end,
})

ctrlSec:AddCheckbox({
    Name = "Win After First Place", Flag = "aw_waf", Default = false,
    Callback = function(v)
        winAfterFirst = v
        notify("Win After First", v and "on, will rush when someone wins" or "off", v and "Info" or "Warning", 3)
    end,
})

ctrlSec:AddCheckbox({
    Name = "Ghost During Win", Flag = "aw_ghost", Default = true,
    Callback = function(v)
        ghostDuringWin = v
        if not v then
            local char = getChar()
            if char then setCharInvis(char, false) end
        end
        notify("Ghost Mode", v and "on during win" or "off", v and "Info" or "Warning", 2)
    end,
})

ctrlSec:AddCheckbox({
    Name = "Anti-AFK", Flag = "aafk", Default = false,
    Callback = function(v)
        if v then startAntiAfk() else stopAntiAfk() end
        notify("Anti-AFK", v and "on" or "off", v and "Success" or "Warning", 2)
    end,
})

ctrlSec:AddDivider()

ctrlSec:AddButton({
    Name = "Win Now",
    Callback = function()
        if not currentMap then
            for _, child in ipairs(workspace:GetChildren()) do
                if child:FindFirstChild("winpad") then
                    currentMap = child.Name; roundActive = true; break
                end
            end
        end
        if not currentMap then notify("Auto Win", "no active map found", "Warning", 2); return end
        stopAll(); wonThisRound = false
        winThread = task.spawn(function()
            local winpad = getWinpad(currentMap)
            if not winpad then notify("Auto Win", "winpad not found", "Warning", 2); return end
            doWinSequence(currentMap, true)
            notify("Auto Win", "done!", "Success", 2)
        end)
    end,
})

ctrlSec:AddButton({
    Name = "Stop / Return",
    Callback = function()
        stopAll()
        local char = getChar()
        if char then setCharInvis(char, false) end
        local hrp = getHRP()
        if hrp and savedCFrame then
            hrp.CFrame = savedCFrame
            notify("Auto Win", "returned to position", "Info", 2)
        else
            notify("Auto Win", "stopped", "Warning", 2)
        end
    end,
})

ctrlSec:AddButton({
    Name = "Scan Workspace",
    Callback = function()
        local found = {}
        for _, child in ipairs(workspace:GetChildren()) do
            if child:FindFirstChild("winpad") then table.insert(found, child.Name) end
        end
        local r = #found > 0 and table.concat(found, ", ") or "none"
        print("[AutoWin] maps with winpad: " .. r)
        notify("Scan", r, #found > 0 and "Success" or "Warning", 4)
        if #found > 0 then startRound(found[1]) end
    end,
})

local timeSec = UI.MakeSection(aR, "Timing")
timeSec._tabName(aTab, aSwitch)

timeSec:AddSlider({
    Name = "Win delay min (s)", Flag = "aw_dmin",
    Min = 0, Max = 20, Default = 0.5, Decimals = 1,
    Callback = function(v) CFG.WIN_DELAY_MIN = math.min(v, CFG.WIN_DELAY_MAX) end,
})
timeSec:AddSlider({
    Name = "Win delay max (s)", Flag = "aw_dmax",
    Min = 0, Max = 25, Default = 1.0, Decimals = 1,
    Callback = function(v) CFG.WIN_DELAY_MAX = math.max(v, CFG.WIN_DELAY_MIN) end,
})
timeSec:AddSlider({
    Name = "Return delay (s)", Flag = "aw_retd",
    Min = 0, Max = 10, Default = 1.5, Decimals = 1,
    Callback = function(v) CFG.RETURN_DELAY = v end,
})

local eL, eR, eTab, eSwitch = UI.AddTab("Extras")

local hatSec = UI.MakeSection(eL, "Hat Customizer")
hatSec._tabName(eTab, eSwitch)

hatSec:AddCheckbox({
    Name = "Enable Hat", Flag = "hat_on", Default = true,
    Callback = function(v)
        hatEnabled = v
        if not v then removeHat() end
        notify("Hat", v and "enabled (click apply)" or "disabled / removed", v and "Info" or "Warning", 2)
    end,
})

hatSec:AddTextBox({
    Name        = "Hat Asset ID",
    Flag        = "hat_id",
    Default     = "215718515",
    Placeholder = "e.g. 215718515",
    Callback    = function(v)
        local n = tonumber(v)
        if n then hatId = n end
    end,
})

hatSec:AddButton({
    Name = "Apply Hat",
    Callback = function()
        local n = tonumber(UI.Flags["hat_id"] or "215718515")
        if n then hatId = n end
        if hatEnabled then
            applyHat()
        else
            notify("Hat", "enable hat first", "Warning", 2)
        end
    end,
})

hatSec:AddButton({
    Name = "Remove Hat",
    Callback = function()
        removeHat()
        notify("Hat", "hat removed", "Warning", 2)
    end,
})

hatSec:AddDivider()

hatSec:AddSlider({
    Name = "Offset X", Flag = "hat_ox",
    Min = -3, Max = 3, Default = 0, Decimals = 2,
    Callback = function(v) hatOffX = v; updateHatWeld() end,
})
hatSec:AddSlider({
    Name = "Offset Y", Flag = "hat_oy",
    Min = -3, Max = 3, Default = 0, Decimals = 2,
    Callback = function(v) hatOffY = v; updateHatWeld() end,
})
hatSec:AddSlider({
    Name = "Offset Z", Flag = "hat_oz",
    Min = -3, Max = 3, Default = 0, Decimals = 2,
    Callback = function(v) hatOffZ = v; updateHatWeld() end,
})

local movSec = UI.MakeSection(eR, "Movement")
movSec._tabName(eTab, eSwitch)

movSec:AddCheckbox({
    Name = "Speed Hack", Flag = "spd", Default = false,
    Callback = function(v)
        if v then startSpeed() else stopSpeed() end
        notify("Speed", v and "on" or "off", v and "Success" or "Warning", 2)
    end,
})
movSec:AddSlider({
    Name = "Speed", Flag = "spdval",
    Min = 16, Max = 500, Default = 80, Decimals = 0,
    Callback = function(_) end,
})

movSec:AddDivider()

movSec:AddCheckbox({
    Name = "Fly", Flag = "fly", Default = false,
    Callback = function(v)
        if v then startFly() else stopFly() end
        notify("Fly", v and "on" or "off", v and "Success" or "Warning", 2)
    end,
})
movSec:AddSlider({
    Name = "Fly Speed", Flag = "flyspd",
    Min = 10, Max = 300, Default = 60, Decimals = 0,
    Callback = function(_) end,
})

movSec:AddDivider()

movSec:AddCheckbox({
    Name = "Noclip", Flag = "nc", Default = false,
    Callback = function(v)
        if v then startNoclip() else stopNoclip() end
        notify("Noclip", v and "on" or "off", v and "Success" or "Warning", 2)
    end,
})

movSec:AddDivider()

movSec:AddCheckbox({
    Name = "Invisible (experimental)", Flag = "inv", Default = false,
    Callback = function(v)
        if v then startInvis() else stopInvis() end
        notify("Invis", v and "on, pink silhouette = you" or "off", v and "Info" or "Warning", 3)
    end,
})

local statExSec = UI.MakeSection(eR, "Character")
statExSec._tabName(eTab, eSwitch)

statExSec:AddSlider({
    Name = "WalkSpeed", Flag = "ws",
    Min = 0, Max = 500, Default = 16, Decimals = 0,
    Callback = function(v)
        pcall(function() local hum = getHum(); if hum then hum.WalkSpeed = v end end)
    end,
})
statExSec:AddSlider({
    Name = "JumpPower", Flag = "jp",
    Min = 0, Max = 500, Default = 50, Decimals = 0,
    Callback = function(v)
        pcall(function() local hum = getHum(); if hum then hum.JumpPower = v end end)
    end,
})

local sL, sR, sTab, sSwitch = UI.AddTab("Settings")

local uiSec = UI.MakeSection(sL, "UI")
uiSec._tabName(sTab, sSwitch)

uiSec:AddKeybind({
    Name    = "Toggle UI",
    Flag    = "RightShift",
    Default = Enum.KeyCode.RightShift,
    Callback = function(_) end,
})

uiSec:AddCheckbox({
    Name    = "Notifications",
    Flag    = "notifs",
    Default = true,
    Callback = function(v) CFG.NOTIFICATIONS = v end,
})

uiSec:AddCheckbox({
    Name    = "Watermark",
    Flag    = "wm_show",
    Default = true,
    Callback = function(v)
        pcall(function() UI.wmFrame.Visible = v end)
    end,
})

uiSec:AddCheckbox({
    Name    = "Snow/Background",
    Flag    = "snow_fx",
    Default = true,
    Callback = function(v)
        if v then UI.StartSnow() else UI.StopSnow() end
    end,
})

local themeSec = UI.MakeSection(sR, "Theme")
themeSec._tabName(sTab, sSwitch)

themeSec:AddColorPicker({
    Name    = "Accent Color",
    Flag    = "accent",
    Default = Color3.fromRGB(255, 182, 215),
    Callback = function(c) UI.SetAccent(c) end,
})

themeSec:AddButton({
    Name = "Reset Accent",
    Callback = function()
        UI.SetAccent(Color3.fromRGB(255, 182, 215))
        notify("Theme", "accent reset", "Success", 2)
    end,
})

local dbgSec = UI.MakeSection(sL, "Debug")
dbgSec._tabName(sTab, sSwitch)

dbgSec:AddCheckbox({
    Name    = "Console Logging",
    Flag    = "aw_log",
    Default = false,
    Callback = function(v)
        logging = v
        if v then print("[AutoWin] logging enabled") end
    end,
})

dbgSec:AddButton({
    Name = "Print Status",
    Callback = function()
        print(string.format(
            "[AutoWin] map=%s | round=%s | won=%s | autowin=%s | saved=%s",
            tostring(currentMap), tostring(roundActive),
            tostring(wonThisRound), tostring(autoWin),
            savedCFrame and tostring(savedCFrame.Position) or "none"
        ))
        notify("Debug", currentMap or "no map", "Info", 3)
    end,
})

notify("whoa obby v11", "loaded! auto win ready.", "Success", 4)
