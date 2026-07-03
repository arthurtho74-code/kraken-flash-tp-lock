task.wait(2)

-- ==========================================
-- SERVICES
-- ==========================================
local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Stats             = game:GetService("Stats")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui        = game:GetService("StarterGui")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService        = game:GetService("GuiService")
local CoreGui           = game:GetService("CoreGui")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ==========================================
-- SYSTEME DE PURGE ET RE-EXECUTION SECURISEE
-- ==========================================
if _G.Formega_Script_Purge then
    pcall(function() _G.Formega_Script_Purge() end)
    task.wait(0.2)
end

local ActiveConnections = {}
local thisScriptStopped = false

-- ==========================================
-- VARIABLES ANTI-RAGDOLL
-- ==========================================
local AntiRagdollConns = {}
local lastRagdollClean = 0
local antiRagdollEnabled = false

-- ==========================================
-- SAVE / LOAD SETTINGS
-- ==========================================
local SETTINGS_FILE = "rares_script_settings.json"

local function loadSettings()
    local ok, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(readfile(SETTINGS_FILE))
    end)
    if ok and type(data) == "table" then return data end
    return {}
end

local function saveSettings()
    pcall(function()
        writefile(SETTINGS_FILE, game:GetService("HttpService"):JSONEncode({
            AutoResetOnBalloon = _G.AutoResetOnBalloon,
            AutoGiant          = _G.AutoGiant,
            AutoBlock          = _G.AutoBlock,
            AntiRagdoll        = antiRagdollEnabled,
        }))
    end)
end

local savedSettings = loadSettings()

if savedSettings.AutoResetOnBalloon ~= nil then _G.AutoResetOnBalloon = savedSettings.AutoResetOnBalloon
elseif _G.AutoResetOnBalloon == nil then _G.AutoResetOnBalloon = true end

if savedSettings.AutoGiant ~= nil then _G.AutoGiant = savedSettings.AutoGiant
elseif _G.AutoGiant == nil then _G.AutoGiant = false end

if savedSettings.AutoBlock ~= nil then _G.AutoBlock = savedSettings.AutoBlock
elseif _G.AutoBlock == nil then _G.AutoBlock = false end

if savedSettings.AntiRagdoll ~= nil then antiRagdollEnabled = savedSettings.AntiRagdoll
else antiRagdollEnabled = false end

-- ==========================================
-- CHARACTER
-- ==========================================
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid  = Character:WaitForChild("Humanoid")
local Root      = Character:WaitForChild("HumanoidRootPart")
local Camera    = Workspace.CurrentCamera

local autoStealEnabled  = false
local stealDelay        = 1.30
local isStealing        = false
local currentMovement   = nil
local selectedPrompt    = nil
local selectedSlotNumber= nil

-- ==========================================
-- ANTI-RAGDOLL
-- ==========================================
local player = LocalPlayer
local maxVelocity  = 40
local clampVelocity= 25
local maxClamp     = 15

-- Connecte l'anti-ragdoll sur UN character prÃ©cis
local function connectAntiRagdollToChar(c)
    local humanoid = c:WaitForChild("Humanoid")
    local root     = c:WaitForChild("HumanoidRootPart")
    local animator = humanoid:WaitForChild("Animator")
    local lastVelocity = Vector3.new(0,0,0)
    local isRag = false

    local function IsRagdollState()
        local state = humanoid:GetState()
        return state == Enum.HumanoidStateType.Physics
            or state == Enum.HumanoidStateType.Ragdoll
            or state == Enum.HumanoidStateType.FallingDown
            or state == Enum.HumanoidStateType.GettingUp
    end

    local function CleanRagdollEffects()
        local now = tick()
        if now - lastRagdollClean < 0.15 then return end
        lastRagdollClean = now
        for _, obj in pairs(c:GetDescendants()) do
            if obj:IsA("BallSocketConstraint") or obj:IsA("NoCollisionConstraint") or obj:IsA("HingeConstraint")
                or (obj:IsA("Attachment") and (obj.Name == "A" or obj.Name == "B")) then
                obj:Destroy()
            elseif obj:IsA("BodyVelocity") or obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then
                obj:Destroy()
            elseif obj:IsA("Motor6D") then
                obj.Enabled = true
            end
        end
        for _, track in pairs(animator:GetPlayingAnimationTracks()) do
            local animName = track.Animation and track.Animation.Name:lower() or ""
            if animName:find("rag") or animName:find("fall") or animName:find("hurt") or animName:find("down") then
                track:Stop(0)
            end
        end
    end

    local function ReEnableControls()
        pcall(function()
            require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls():Enable()
        end)
    end

    table.insert(ActiveConnections, humanoid.StateChanged:Connect(function(_, newState)
        if not antiRagdollEnabled then return end
        if IsRagdollState() then
            isRag = true
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
            CleanRagdollEffects()
            workspace.CurrentCamera.CameraSubject = humanoid
            ReEnableControls()
        else
            isRag = false
        end
    end))

    table.insert(ActiveConnections, RunService.Heartbeat:Connect(function()
        if not antiRagdollEnabled then return end
        if isRag then
            CleanRagdollEffects()
            local vel = root.AssemblyLinearVelocity
            if (vel - lastVelocity).Magnitude > maxVelocity and vel.Magnitude > clampVelocity then
                root.AssemblyLinearVelocity = vel.Unit * math.min(vel.Magnitude, maxClamp)
            end
            lastVelocity = vel
        end
    end))

    table.insert(ActiveConnections, c.DescendantAdded:Connect(function()
        if antiRagdollEnabled and isRag then CleanRagdollEffects() end
    end))

    ReEnableControls()
    CleanRagdollEffects()
end

local function startAntiRagdoll()
    for _, conn in pairs(AntiRagdollConns) do pcall(function() conn:Disconnect() end) end
    AntiRagdollConns = {}
    local c = player.Character or player.CharacterAdded:Wait()
    connectAntiRagdollToChar(c)
end

local function stopAntiRagdoll()
    for _, conn in pairs(AntiRagdollConns) do pcall(function() conn:Disconnect() end) end
    AntiRagdollConns = {}
end

local arCharConn = player.CharacterAdded:Connect(function(newChar)
    if not antiRagdollEnabled then return end
    for _, conn in pairs(AntiRagdollConns) do pcall(function() conn:Disconnect() end) end
    AntiRagdollConns = {}
    task.spawn(function()
        connectAntiRagdollToChar(newChar)
    end)
end)
table.insert(ActiveConnections, arCharConn)

if antiRagdollEnabled then task.spawn(startAntiRagdoll) end

-- ==========================================
-- FAST CONFIRM
-- ==========================================
local function FastConfirm()
    local res = GuiService:GetScreenResolution()
    local x = res.X * 0.5
    local y = res.Y * 0.58
    for i = 1, 10 do
        if thisScriptStopped then break end
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        task.wait(0.01)
    end
end

-- ==========================================
-- GET NEAREST PLAYER
-- ==========================================
local function getNearestPlayer()
    local hrp = Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local closest, dist = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
            local d = (plr.Character.HumanoidRootPart.Position - hrp.Position).Magnitude
            if d < dist then dist = d closest = plr end
        end
    end
    return closest
end

-- ==========================================
-- WAIT FOR STEAL PROMPT
-- ==========================================
local function waitForStealPrompt()
    for _, v in ipairs(CoreGui:GetDescendants()) do
        if v:IsA("TextLabel") and v.Text and string.find(v.Text, "Steal") then return true end
    end
    local found = false
    local connection
    connection = CoreGui.DescendantAdded:Connect(function(v)
        if v:IsA("TextLabel") and v.Text and string.find(v.Text, "Steal") then found = true end
    end)
    table.insert(ActiveConnections, connection)
    while not found and not thisScriptStopped do task.wait(0.05) end
    if connection then pcall(function() connection:Disconnect() end) end
    return true
end

-- ==========================================
-- CHARACTER ADDED
-- ==========================================
local charAddedConn = LocalPlayer.CharacterAdded:Connect(function(newChar)
    if currentMovement then pcall(function() currentMovement:Disconnect() end) currentMovement = nil end
    Character = newChar
    Humanoid  = newChar:WaitForChild("Humanoid")
    Root      = newChar:WaitForChild("HumanoidRootPart")
    Camera    = Workspace.CurrentCamera
    autoStealEnabled = false isStealing = false
    task.wait()
    if Root then
        local oldVelocity = Root:FindFirstChild("LinearVelocity")
        if oldVelocity then oldVelocity:Destroy() end
        local oldAttachment = Root:FindFirstChild("Attachment")
        if oldAttachment then oldAttachment:Destroy() end
    end
end)
table.insert(ActiveConnections, charAddedConn)

-- ==========================================
-- SLOTS CONFIG
-- ==========================================
local SlotsConfig = {
    [1]  = { Positions = { Vector3.new(-345.4766,-6.0291,1.5014) }, CamOffset = Vector3.new(-354.1492,4.0350,9.3823)-Vector3.new(-345.4766,-6.0291,1.5014), CamAngles = {-0.827500,-0.640100,-0.576243} },
    [2]  = { Positions = { Vector3.new(-349.9259,-6.2791,-1.5767) }, CamOffset = Vector3.new(-363.2081,2.9403,3.3074)-Vector3.new(-349.9259,-6.2791,-1.5767), CamAngles = {-1.007271,-0.967909,-0.916433} },
    [3]  = { Positions = { Vector3.new(-349.9259,-6.2791,-1.5758) }, CamOffset = Vector3.new(-367.7556,4.3232,3.4983)-Vector3.new(-349.9259,-6.2791,-1.5758), CamAngles = {-1.062718,-1.041500,-0.997864} },
    [4]  = { Positions = { Vector3.new(-343.4199,-5.9197,10.5505) }, CamOffset = Vector3.new(-359.0885,4.0544,21.0001)-Vector3.new(-343.4199,-5.9197,10.5505), CamAngles = {-0.681953,-0.861073,-0.551998} },
    [5]  = { Positions = { Vector3.new(-343.7608,-6.3272,-9.7994) }, CamOffset = Vector3.new(-363.9226,-0.3924,-9.1459)-Vector3.new(-343.7608,-6.3272,-9.7994), CamAngles = {-1.424811,-1.351549,-1.421283} },
    [6]  = { Positions = { Vector3.new(-311.6442,-6.4281,52.8030), Vector3.new(-300.8487,-6.4281,36.7761) }, CamOffset = Vector3.new(-300.4433,6.4394,48.1955)-Vector3.new(-300.8487,-6.4281,36.7761), CamAngles = {-0.783560,0.025146,0.025045} },
    [7]  = { Positions = { Vector3.new(-344.4383,-6.4281,41.8672) }, CamOffset = Vector3.new(-362.8094,-3.2299,51.1552)-Vector3.new(-344.4383,-6.4281,41.8672), CamAngles = {-0.181885,-1.095968,-0.162135} },
    [8]  = { Positions = { Vector3.new(-348.5228,-6.4281,48.1022) }, CamOffset = Vector3.new(-369.4075,-0.1123,63.3763)-Vector3.new(-348.5228,-6.4281,48.1022), CamAngles = {-0.306020,-0.916511,-0.245634} },
    [9]  = { Positions = { Vector3.new(-339.6349,-6.4281,60.4164) }, CamOffset = Vector3.new(-349.9293,-1.6218,84.4119)-Vector3.new(-339.6349,-6.4281,60.4164), CamAngles = {-0.137335,-0.401849,-0.054002} },
    [10] = { Positions = { Vector3.new(-355.3322,-6.4281,25.3526) }, CamOffset = Vector3.new(-377.7117,8.9106,25.7208)-Vector3.new(-355.3322,-6.4281,25.3526), CamAngles = {-1.544218,-1.016502,-1.539540} },
    [11] = { Positions = { Vector3.new(-354.9932,-6.4281,-47.3879), Vector3.new(-331.5262,-6.4281,-47.3607) }, CamOffset = Vector3.new(-333.2372,-9.9613,-64.2099)-Vector3.new(-331.5262,-6.4281,-47.3607), CamAngles = {2.851853,-0.097011,3.112724} },
    [12] = { Positions = { Vector3.new(-354.9584,-6.4208,-42.6520), Vector3.new(-338.7290,-6.4281,-43.4713) }, CamOffset = Vector3.new(-346.9807,-9.9578,-60.5865)-Vector3.new(-338.7290,-6.4281,-43.4713), CamAngles = {2.856299,-0.433315,3.019061} },
    [13] = { Positions = { Vector3.new(-354.8862,-6.2793,-37.9787), Vector3.new(-334.5183,-6.4281,-41.6819) }, CamOffset = Vector3.new(-343.9747,-9.9590,-57.3332)-Vector3.new(-334.5183,-6.4281,-41.6819), CamAngles = {2.831168,-0.522070,2.982964} },
    [14] = { Positions = { Vector3.new(-351.8463,-6.5022,-37.0529), Vector3.new(-319.8298,-6.4281,-45.1476) }, CamOffset = Vector3.new(-325.1408,-9.9618,-60.9837)-Vector3.new(-319.8298,-6.4281,-45.1476), CamAngles = {2.834406,-0.309406,3.045298} },
    [15] = { Positions = { Vector3.new(-351.0894,-6.2833,-32.7751), Vector3.new(-317.9170,-6.4281,-41.9999) }, CamOffset = Vector3.new(-327.9996,-9.9581,-57.8876)-Vector3.new(-317.9170,-6.4281,-41.9999), CamAngles = {2.835549,-0.544183,2.979445} },
    [16] = { Positions = { Vector3.new(-338.2857,-6.4281,57.2060) }, CamOffset = Vector3.new(-341.5551,-9.9642,72.3530)-Vector3.new(-338.2857,-6.4281,57.2060), CamAngles = {0.320392,-0.202067,0.066497} },
    [17] = { Positions = { Vector3.new(-337.9285,-6.4281,55.1757) }, CamOffset = Vector3.new(-344.4950,-9.9637,69.4787)-Vector3.new(-337.9285,-6.4281,55.1757), CamAngles = {0.337895,-0.408747,0.138758} },
    [18] = { Positions = { Vector3.new(-332.1088,-6.4281,53.1675) }, CamOffset = Vector3.new(-338.8290,-9.9674,65.6692)-Vector3.new(-332.1088,-6.4281,53.1675), CamAngles = {0.382481,-0.462609,0.177644} },
    [19] = { Positions = { Vector3.new(-347.9923,-6.2933,-34.0232), Vector3.new(-328.5790,-6.4281,-35.0857) }, CamOffset = Vector3.new(-328.6130,-10.0174,-40.4923)-Vector3.new(-328.5790,-6.4281,-35.0857), CamAngles = {2.387391,-0.004579,3.137291} },
    [20] = { Positions = { Vector3.new(-355.0801,-6.4404,-33.2302), Vector3.new(-321.5783,-6.4281,-33.5778) }, CamOffset = Vector3.new(-321.6123,-10.0174,-38.9844)-Vector3.new(-321.5783,-6.4281,-33.5778), CamAngles = {2.387391,-0.004579,3.137291} },
    [21] = { Positions = { Vector3.new(-351.5396,-7.5033,-41.797), Vector3.new(-314.088,-7.5033,-32.1806) }, CamOffset = Vector3.new(-314.1147,-10.0174,-36.4214)-Vector3.new(-314.088,-7.5033,-32.1806), CamAngles = {2.387391,-0.004579,3.137291}, NeedJump = true },
    [22] = { Positions = { Vector3.new(-351.5396,-7.5033,-41.797), Vector3.new(-306.8919,-7.5033,-33.9124) }, CamOffset = Vector3.new(-306.923,-10.008,-38.86)-Vector3.new(-306.8919,-7.5033,-33.9124), CamAngles = {2.4648,-0.004898,3.137657}, NeedJump = true },
    [23] = { Positions = { Vector3.new(-351.5396,-7.5033,-41.797), Vector3.new(-300.2759,-7.5033,-32.7047) }, CamOffset = Vector3.new(-300.4669,-10.016,-37.044)-Vector3.new(-300.2759,-7.5033,-32.7047), CamAngles = {2.399014,-0.032413,3.111857}, NeedJump = true },
    [24] = { Positions = { Vector3.new(-348.2407,-7.5033,74.3719), Vector3.new(-330.0484,-7.5033,48.183) }, CamOffset = Vector3.new(-330.1124,-10.0063,53.2779)-Vector3.new(-330.0484,-7.5033,48.183), CamAngles = {0.662308,-0.00991,0.007727}, NeedJump = true },
    [25] = { Positions = { Vector3.new(-348.2407,-7.5033,74.3719), Vector3.new(-325.4576,-7.5033,46.8182) }, CamOffset = Vector3.new(-326.0541,-10.0104,51.5397)-Vector3.new(-325.4576,-7.5033,46.8182), CamAngles = {0.700033,-0.09632,0.080833}, NeedJump = true },
    [26] = { Positions = { Vector3.new(-348.2407,-7.5033,74.3719), Vector3.new(-324.6721,-7.5033,47.2033) }, CamOffset = Vector3.new(-326.6859,-10.0057,51.9385)-Vector3.new(-324.6721,-7.5033,47.2033), CamAngles = {0.698024,-0.314979,0.254268}, NeedJump = true },
    [27] = { Positions = { Vector3.new(-348.2407,-7.5033,74.3719), Vector3.new(-320.4196,-7.5033,44.1) }, CamOffset = Vector3.new(-322.9213,-10.0122,49.5157)-Vector3.new(-320.4196,-7.5033,44.1), CamAngles = {0.876985,-0.422603,0.397417} },
}

-- ==========================================
-- UTILITAIRES
-- ==========================================
local function findTool(name)
    if not Character then return nil end
    for _, tool in ipairs(Character:GetChildren()) do
        if tool:IsA("Tool") and tool.Name:lower():find(name:lower()) then return tool end
    end
    for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if tool:IsA("Tool") and tool.Name:lower():find(name:lower()) then return tool end
    end
    return nil
end

local function isMyPlot(plot)
    if not plot then return false end
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yourBase = sign:FindFirstChild("YourBase")
        if yourBase and yourBase:IsA("BillboardGui") and yourBase.Enabled then return true end
    end
    return false
end

local function isValidStealPrompt(prompt)
    if not prompt or not prompt.Parent or not prompt.Enabled then return false end
    local state      = prompt:GetAttribute("State")
    local actionText = prompt.ActionText
    if state == "Steal" or state == "Grab" or actionText == "Steal" or actionText == "Grab" then return true end
    return false
end

local function firePromptConnections(prompt, signalName)
    if not getconnections then return end
    local connections = getconnections(prompt[signalName])
    for _, conn in ipairs(connections) do
        if conn.Function then task.spawn(conn.Function) end
    end
end

local function executeSteal(prompt)
    if isStealing or not prompt or not prompt.Parent then return end
    isStealing = true
    firePromptConnections(prompt, "PromptButtonHoldBegan")
    task.wait(stealDelay)
    if prompt and prompt.Parent and prompt.Enabled and not thisScriptStopped then
        firePromptConnections(prompt, "Triggered")
    end
    isStealing = false
end

local STOP_DIST = 5
local SLOW_DIST = 20

-- ==========================================
-- DO RESET
-- ==========================================
local function doReset()
    local lp  = Players.LocalPlayer
    local Net = ReplicatedStorage:WaitForChild("Packages", 2):WaitForChild("Net", 2)
    local remote
    local childs = Net:GetChildren()
    for i = 1, #childs - 1 do
        if childs[i] and childs[i+1] and childs[i].Name:find("Tools/Cooldown") then
            remote = childs[i+1]; break
        end
    end
    if not remote then
        local h = lp.Character and lp.Character:FindFirstChildWhichIsA("Humanoid")
        if h then h.Health = 0 end
        return
    end
    local saved = {}
    local char  = lp.Character
    local bp    = lp:FindFirstChild("Backpack")
    if char then
        local h = char:FindFirstChildOfClass("Humanoid")
        if h then pcall(function() h:UnequipTools() end) end
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then table.insert(saved, t); t.Parent = nil end
        end
    end
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then table.insert(saved, t); t.Parent = nil end
        end
    end
    lp.Character = nil
    local sending  = true
    local throttle = 0
    local loop
    loop = RunService.Heartbeat:Connect(function(dt)
        if thisScriptStopped then pcall(function() loop:Disconnect() end) return end
        if not sending then return end
        throttle = throttle + dt
        if throttle >= 0.1 then
            throttle = 0
            pcall(function() remote:FireServer("f888ee6e-c86d-46e1-93d7-0639d6635d42", lp, "balloon") end)
        end
        if lp.Character then lp.Character = nil end
    end)
    table.insert(ActiveConnections, loop)
    local conn
    conn = lp.CharacterAdded:Connect(function()
        sending = false
        pcall(function() loop:Disconnect() end)
        pcall(function() conn:Disconnect() end)
        task.spawn(function()
            local newBp = lp:WaitForChild("Backpack", 3)
            if newBp then for _, t in ipairs(saved) do if t then t.Parent = newBp end end end
        end)
    end)
    table.insert(ActiveConnections, conn)
    task.delay(4, function()
        sending = false
        pcall(function() loop:Disconnect() end)
        local curBp = lp:FindFirstChild("Backpack")
        if curBp then for _, t in ipairs(saved) do if t then t.Parent = curBp end end end
    end)
end

-- ==========================================
-- AUTO RESET ON BALLOON
-- ==========================================
local balloonConnection
balloonConnection = LocalPlayer:GetAttributeChangedSignal("Balloon"):Connect(function()
    if thisScriptStopped then pcall(function() balloonConnection:Disconnect() end) return end
    if _G.AutoResetOnBalloon == true and LocalPlayer:GetAttribute("Balloon") == true then doReset() end
end)
table.insert(ActiveConnections, balloonConnection)

-- ==========================================
-- START TRIP TO PET SLOT (FLASH TP)
-- ==========================================
local function startTripToPetSlot(prompt, slotNumber)
    local config          = SlotsConfig[slotNumber] or SlotsConfig[1]
    local targetPositions = config.Positions or { config.Position }
    local needJump        = config.NeedJump == true
    if slotNumber >= 19 and slotNumber <= 27 then needJump = true end

    if currentMovement then pcall(function() currentMovement:Disconnect() end) currentMovement = nil end
    if not Root or not Humanoid then return end

    autoStealEnabled = true
    local Speed            = 200
    local grabStartDistance= 60
    local grabStarted      = false

    local carpet = findTool("flying carpet")
    if carpet then Humanoid:UnequipTools() task.wait(0.03) Humanoid:EquipTool(carpet) end

    if Root:FindFirstChild("LinearVelocity") then Root.LinearVelocity:Destroy() end
    if Root:FindFirstChild("Attachment")     then Root.Attachment:Destroy() end

    local Attachment = Instance.new("Attachment")
    Attachment.Parent = Root

    local Velocity = Instance.new("LinearVelocity")
    Velocity.Attachment0     = Attachment
    Velocity.RelativeTo      = Enum.ActuatorRelativeTo.World
    Velocity.MaxForce        = math.huge
    Velocity.Parent          = Root

    local currentPosIndex       = 1
    local intermediatePauseActive = false

    currentMovement = RunService.Heartbeat:Connect(function()
        if thisScriptStopped then
            if currentMovement then pcall(function() currentMovement:Disconnect() end) currentMovement = nil end
            return
        end
        if not Root or not Humanoid or not Root.Parent or Humanoid.Health <= 0 then
            if currentMovement then pcall(function() currentMovement:Disconnect() end) currentMovement = nil end
            return
        end
        if intermediatePauseActive then Velocity.VectorVelocity = Vector3.zero return end

        local TargetPosition = targetPositions[currentPosIndex]
        if not TargetPosition then return end

        local rootPos = Root.Position
        local dir     = Vector3.new(TargetPosition.X - rootPos.X, 0, TargetPosition.Z - rootPos.Z)
        local dist    = dir.Magnitude

        if currentPosIndex == 1 and dist <= grabStartDistance and not grabStarted then
            grabStarted = true
            task.spawn(function() executeSteal(prompt) end)
        end

        local speedMult = 1
        if dist < SLOW_DIST then speedMult = math.max(0.15, dist / SLOW_DIST) end

        if dist <= STOP_DIST then
            if currentPosIndex < #targetPositions then
                intermediatePauseActive = true
                Velocity.VectorVelocity = Vector3.zero
                Root.AssemblyLinearVelocity = Vector3.zero
                task.spawn(function()
                    currentPosIndex = currentPosIndex + 1
                    intermediatePauseActive = false
                end)
                return
            end

            Velocity.VectorVelocity = Vector3.zero
            Root.AssemblyLinearVelocity = Vector3.zero
            Velocity:Destroy()
            Attachment:Destroy()
            Root.CFrame = CFrame.new(TargetPosition)
            if currentMovement then pcall(function() currentMovement:Disconnect() end) currentMovement = nil end

            task.wait(0.12)
            Camera.CameraType = Enum.CameraType.Scriptable
            Camera.CFrame = CFrame.new(Root.Position + config.CamOffset) * CFrame.Angles(unpack(config.CamAngles))
            Humanoid:UnequipTools()
            task.wait(0.06)

            if needJump then
                Root.AssemblyLinearVelocity = Vector3.new(0, 55, 0)
                task.wait(0.08)
            end

            local flash = findTool("flash")
            if flash then
                Humanoid:EquipTool(flash)
                task.wait(0.08)
                flash:Activate()
            end

            task.wait(0.1)

            if _G.AutoGiant then
                local giant = findTool("giant potion")
                if giant then
                    Humanoid:EquipTool(giant) task.wait(0.08) giant:Activate()
                    task.wait(0.05) Humanoid:UnequipTools()
                end
            end

            Camera.CameraType = Enum.CameraType.Custom

            if _G.AutoBlock then
                task.spawn(function()
                    task.wait(0.13)
                    local target = getNearestPlayer()
                    if target then
                        waitForStealPrompt()
                        pcall(function() StarterGui:SetCore("PromptBlockPlayer", target) end)
                        FastConfirm()
                    end
                end)
            end

            task.spawn(function() task.wait(1.0) autoStealEnabled = false end)
            return
        end

        Velocity.VectorVelocity = Vector3.new(dir.Unit.X * Speed * speedMult, 0, dir.Unit.Z * Speed * speedMult)
    end)
    table.insert(ActiveConnections, currentMovement)
end

-- ==========================================
-- UPDATE PET LIST
-- ==========================================
local scrollListRef = nil

local function updatePetList()
    if isStealing or autoStealEnabled or thisScriptStopped then return end
    if not scrollListRef then return end

    for _, child in ipairs(scrollListRef:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then return end

    local tempPets = {}
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if not isMyPlot(plot) then
            local podiums = plot:FindFirstChild("AnimalPodiums")
            if podiums then
                for _, podium in ipairs(podiums:GetChildren()) do
                    local slotNumber  = tonumber(podium.Name:match("%d+")) or 1
                    local base        = podium:FindFirstChild("Base") or podium
                    local spawnPoint  = base:FindFirstChild("Spawn")
                    local attachment  = spawnPoint and spawnPoint:FindFirstChild("PromptAttachment")
                    if attachment then
                        for _, child in ipairs(attachment:GetChildren()) do
                            if child:IsA("ProximityPrompt") and isValidStealPrompt(child) then
                                local petName = child.ObjectText or "Pet"
                                table.insert(tempPets, { prompt = child, slot = slotNumber, name = petName })
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(tempPets, function(a, b) return a.slot < b.slot end)

    local C_list = {
        card   = Color3.fromRGB(14, 20, 40),
        accent = Color3.fromRGB(50, 120, 255),
        stroke = Color3.fromRGB(30, 50, 100),
        bright = Color3.fromRGB(220, 235, 255),
        mute   = Color3.fromRGB(80, 110, 170),
    }

    for _, petData in ipairs(tempPets) do
        if thisScriptStopped then break end
        local isSelected = (selectedPrompt == petData.prompt)

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -8, 0, 40)
        row.BackgroundColor3 = isSelected and Color3.fromRGB(10, 30, 80) or C_list.card
        row.BorderSizePixel = 0
        row.Parent = scrollListRef
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

        local rStroke = Instance.new("UIStroke")
        rStroke.Color     = isSelected and C_list.accent or C_list.stroke
        rStroke.Thickness = isSelected and 1.5 or 1
        rStroke.Parent    = row

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Text               = petData.name
        nameLabel.Size               = UDim2.new(1, -10, 1, 0)
        nameLabel.Position           = UDim2.new(0, 10, 0, -4)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3         = C_list.bright
        nameLabel.Font               = Enum.Font.GothamMedium
        nameLabel.TextSize           = 13
        nameLabel.TextXAlignment     = Enum.TextXAlignment.Left
        nameLabel.Parent             = row

        local slotLabel = Instance.new("TextLabel")
        slotLabel.Text               = "slot " .. petData.slot
        slotLabel.Size               = UDim2.new(1, -12, 1, 0)
        slotLabel.Position           = UDim2.new(0, 0, 0, 6)
        slotLabel.BackgroundTransparency = 1
        slotLabel.TextColor3         = C_list.mute
        slotLabel.Font               = Enum.Font.GothamMedium
        slotLabel.TextSize           = 11
        slotLabel.TextXAlignment     = Enum.TextXAlignment.Right
        slotLabel.Parent             = row

        local clickBtn = Instance.new("TextButton")
        clickBtn.Size               = UDim2.new(1, 0, 1, 0)
        clickBtn.BackgroundTransparency = 1
        clickBtn.Text               = ""
        clickBtn.BorderSizePixel    = 0
        clickBtn.Parent             = row

        local rowBtnConn = clickBtn.MouseButton1Click:Connect(function()
            if not isStealing and not autoStealEnabled then
                selectedPrompt     = petData.prompt
                selectedSlotNumber = petData.slot
                updatePetList()
            end
        end)
        table.insert(ActiveConnections, rowBtnConn)
    end

    if #tempPets == 0 then
        local emptyCard = Instance.new("Frame")
        emptyCard.Name             = "EmptyCard"
        emptyCard.Size             = UDim2.new(1, -8, 0, 120)
        emptyCard.BackgroundColor3 = Color3.fromRGB(14, 20, 40)
        emptyCard.BorderSizePixel  = 0
        emptyCard.ZIndex           = 4
        emptyCard.Parent           = scrollListRef
        Instance.new("UICorner", emptyCard).CornerRadius = UDim.new(0, 10)
        local es = Instance.new("UIStroke"); es.Color = Color3.fromRGB(30, 50, 100); es.Parent = emptyCard

        local iconCircle = Instance.new("Frame")
        iconCircle.Size             = UDim2.new(0, 40, 0, 40)
        iconCircle.Position         = UDim2.new(0.5, -20, 0, 18)
        iconCircle.BackgroundColor3 = Color3.fromRGB(14, 24, 55)
        iconCircle.BorderSizePixel  = 0
        iconCircle.ZIndex           = 5
        iconCircle.Parent           = emptyCard
        Instance.new("UICorner", iconCircle).CornerRadius = UDim.new(0, 20)
        local is = Instance.new("UIStroke"); is.Color = Color3.fromRGB(30, 50, 100); is.Parent = iconCircle

        local iconLabel = Instance.new("TextLabel")
        iconLabel.Size               = UDim2.new(1, 0, 1, 0)
        iconLabel.BackgroundTransparency = 1
        iconLabel.ZIndex             = 6
        iconLabel.Text               = "âš¡"
        iconLabel.TextColor3         = Color3.fromRGB(50, 120, 255)
        iconLabel.TextSize           = 18
        iconLabel.Font               = Enum.Font.GothamBold
        iconLabel.Parent             = iconCircle

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size               = UDim2.new(1, -16, 0, 22)
        titleLabel.Position           = UDim2.new(0, 8, 0, 64)
        titleLabel.BackgroundTransparency = 1
        titleLabel.ZIndex             = 5
        titleLabel.Text               = "No brainrots found"
        titleLabel.TextColor3         = Color3.fromRGB(220, 235, 255)
        titleLabel.TextSize           = 13
        titleLabel.Font               = Enum.Font.GothamMedium
        titleLabel.Parent             = emptyCard

        local subLabel = Instance.new("TextLabel")
        subLabel.Size               = UDim2.new(1, -16, 0, 18)
        subLabel.Position           = UDim2.new(0, 8, 0, 86)
        subLabel.BackgroundTransparency = 1
        subLabel.ZIndex             = 5
        subLabel.Text               = "No brainrots to detect for now"
        subLabel.TextColor3         = Color3.fromRGB(80, 110, 170)
        subLabel.TextSize           = 11
        subLabel.Font               = Enum.Font.Gotham
        subLabel.Parent             = emptyCard
    end
end

-- ==========================================
-- GUI DESIGN CONFIG
-- ==========================================
local old = PlayerGui:FindFirstChild("Kraken Flash TP Lock")
if old then old:Destroy() end
local oldB = PlayerGui:FindFirstChild("HugoHubBanner")
if oldB then oldB:Destroy() end

local C = {
    accent     = Color3.fromRGB(50, 120, 255),
    accentHi   = Color3.fromRGB(80, 160, 255),
    deepBlue   = Color3.fromRGB(10, 20, 60),
    body       = Color3.fromRGB(5, 8, 18),
    panel      = Color3.fromRGB(8, 12, 24),
    tabBar     = Color3.fromRGB(6, 9, 20),
    card       = Color3.fromRGB(14, 20, 40),
    iconBg     = Color3.fromRGB(14, 24, 55),
    stroke     = Color3.fromRGB(30, 50, 100),
    strokeDim  = Color3.fromRGB(20, 32, 65),
    textBright = Color3.fromRGB(220, 235, 255),
    textBlue   = Color3.fromRGB(100, 170, 255),
    textMute   = Color3.fromRGB(80, 110, 170),
    textDim    = Color3.fromRGB(50, 75, 130),
    knobOn     = Color3.fromRGB(200, 225, 255),
    knobOff    = Color3.fromRGB(60, 75, 110),
    trackOff   = Color3.fromRGB(18, 26, 50),
}

local borderGradientSeq = ColorSequence.new({
    ColorSequenceKeypoint.new(0,    C.accentHi),
    ColorSequenceKeypoint.new(0.25, C.deepBlue),
    ColorSequenceKeypoint.new(0.5,  C.accent),
    ColorSequenceKeypoint.new(0.75, C.deepBlue),
    ColorSequenceKeypoint.new(1,    C.accentHi),
})

local function getDevice()
    local screen = workspace.CurrentCamera.ViewportSize
    local w, h = screen.X, screen.Y
    local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    if isMobile then
        if w >= 900 or h >= 900 then return "ipad" end
        return "mobile"
    end
    return "pc"
end

local DEVICE = getDevice()

local LAYOUT = {
    pc = {
        winW = 310, winH = 400,
        posX = UDim2.new(0.5, 0, 0.5, 0),
        bannerW = 302, bannerH = 82,
        bannerPos = UDim2.new(0.5, -151, 0, 60),
        btnSize = 94, btnH = 40,
        tabH = 32, headerH = 47,
        actionXs = {8, 108, 208},
        textSize = { header = 11, btn = 12, tab = 12 },
    },
    ipad = {
        winW = 280, winH = 370,
        posX = UDim2.new(0.5, 0, 0.5, 0),
        bannerW = 260, bannerH = 76,
        bannerPos = UDim2.new(0.5, -130, 0, 50),
        btnSize = 83, btnH = 38,
        tabH = 30, headerH = 45,
        actionXs = {7, 96, 185},
        textSize = { header = 11, btn = 11, tab = 11 },
    },
    mobile = {
        winW = 240, winH = 310,
        posX = UDim2.new(0.5, 0, 0.5, 0),
        bannerW = 220, bannerH = 70,
        bannerPos = UDim2.new(0.5, -110, 0, 40),
        btnSize = 70, btnH = 36,
        tabH = 28, headerH = 42,
        actionXs = {6, 82, 158},
        textSize = { header = 10, btn = 10, tab = 10 },
    },
}

local L = LAYOUT[DEVICE]

local HUGO_SCRIPT_GUI = Instance.new("ScreenGui")
HUGO_SCRIPT_GUI.Name = "Kraken Flash TP Lock"
HUGO_SCRIPT_GUI.SelectionGroup = false
HUGO_SCRIPT_GUI.ResetOnSpawn   = false
HUGO_SCRIPT_GUI.DisplayOrder   = 999
HUGO_SCRIPT_GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
HUGO_SCRIPT_GUI.IgnoreGuiInset = false
HUGO_SCRIPT_GUI.Parent         = PlayerGui

-- Contour ExtÃ©rieur (BorderFrame)
local BorderFrame = Instance.new("Frame")
BorderFrame.Name             = "BorderFrame"
BorderFrame.SelectionGroup   = false
BorderFrame.Size             = UDim2.new(0, L.winW+4, 0, L.winH+4)
BorderFrame.Position         = L.posX
BorderFrame.AnchorPoint      = Vector2.new(0.5, 0.5)
BorderFrame.BackgroundColor3 = C.accent
BorderFrame.BorderSizePixel  = 0
BorderFrame.ClipsDescendants = false
BorderFrame.Active           = false
BorderFrame.Selectable       = false
BorderFrame.Parent           = HUGO_SCRIPT_GUI

-- FIX : Ajout des coins arrondis sur le contour extÃ©rieur pour Ã©viter l'effet carrÃ©
local BorderCorner = Instance.new("UICorner")
BorderCorner.CornerRadius = UDim.new(0, 13)
BorderCorner.Parent = BorderFrame

local UIGradient = Instance.new("UIGradient")
UIGradient.Color    = borderGradientSeq
UIGradient.Rotation = 308.077
UIGradient.Parent   = BorderFrame

local Win = Instance.new("Frame")
Win.Name             = "Win"
Win.SelectionGroup   = false
Win.Size             = UDim2.new(0, L.winW, 0, L.winH)
Win.Position         = L.posX
Win.AnchorPoint      = Vector2.new(0.5, 0.5)
Win.BackgroundTransparency = 1
Win.BorderSizePixel  = 0
Win.ZIndex           = 2
Win.ClipsDescendants = false
Win.Active           = false
Win.Selectable       = false
Win.Parent           = HUGO_SCRIPT_GUI

local Frame = Instance.new("Frame")
Frame.Name             = "Frame"
Frame.SelectionGroup   = false
Frame.Size             = UDim2.new(1, 0, 1, 0)
Frame.BackgroundColor3 = C.body
Frame.BorderSizePixel  = 0
Frame.ClipsDescendants = true
Frame.Active           = false
Frame.Selectable       = false
Frame.Parent           = Win
Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 13)

local Frame2 = Instance.new("Frame")
Frame2.Name             = "Frame"
Frame2.Size             = UDim2.new(1, 0, 1, -94)
Frame2.Position         = UDim2.new(0, 0, 0, 90)
Frame2.BackgroundColor3 = C.panel
Frame2.BorderSizePixel  = 0
Frame2.ClipsDescendants = false
Frame2.Parent           = Frame
Instance.new("UICorner", Frame2).CornerRadius = UDim.new(0, 13)

local Frame3 = Instance.new("Frame")
Frame3.Name             = "Frame"
Frame3.Size             = UDim2.new(1, 0, 0, L.headerH)
Frame3.Position         = UDim2.new(0, 0, 0, -8)
Frame3.BackgroundTransparency = 1
Frame3.BorderSizePixel  = 0
Frame3.ZIndex           = 3
Frame3.ClipsDescendants = false
Frame3.Active           = false
Frame3.Selectable       = false
Frame3.Parent           = Frame

local Frame4 = Instance.new("Frame")
Frame4.Size             = UDim2.new(1, 0, 0, 1)
Frame4.Position         = UDim2.new(0, 0, 1, -1)
Frame4.BackgroundColor3 = C.stroke
Frame4.BorderSizePixel  = 0
Frame4.ZIndex           = 4
Frame4.Parent           = Frame3

local Frame5 = Instance.new("Frame")
Frame5.Size             = UDim2.new(0, 6, 0, 6)
Frame5.Position         = UDim2.new(0, 10, 0.5, -3)
Frame5.BackgroundColor3 = C.accent
Frame5.BorderSizePixel  = 0
Frame5.ZIndex           = 5
Frame5.Parent           = Frame3
Instance.new("UICorner", Frame5).CornerRadius = UDim.new(0, 4)

local Frame6 = Instance.new("Frame")
Frame6.Size                 = UDim2.new(0, 12, 0, 12)
Frame6.Position             = UDim2.new(0, 7, 0.5, -6)
Frame6.BackgroundColor3     = C.accent
Frame6.BackgroundTransparency = 0.75
Frame6.BorderSizePixel      = 0
Frame6.ZIndex               = 4
Frame6.Parent               = Frame3
Instance.new("UICorner", Frame6).CornerRadius = UDim.new(0, 7)

local TextLabel = Instance.new("TextLabel")
TextLabel.Size               = UDim2.new(0, 120, 1, 0)
TextLabel.Position           = UDim2.new(0, 24, 0, 0)
TextLabel.BackgroundTransparency = 1
TextLabel.ZIndex             = 5
TextLabel.Text = "KRAKEN FLASH TP LOCK"
TextLabel.TextColor3         = C.textBright
TextLabel.TextSize           = 11
TextLabel.Font               = Enum.Font.GothamBold
TextLabel.TextXAlignment     = Enum.TextXAlignment.Left
TextLabel.Parent             = Frame3

local TextLabel2 = Instance.new("TextLabel")
TextLabel2.Size               = UDim2.new(1, -163, 1, 0)
TextLabel2.Position           = UDim2.new(0, 115, 0, 0)
TextLabel2.BackgroundTransparency = 1
TextLabel2.ZIndex             = 5
TextLabel2.Text               = '<font color="rgb(50,120,255)">Hugo pvp</font>'
TextLabel2.TextColor3         = C.textBright
TextLabel2.TextSize           = 11
TextLabel2.Font               = Enum.Font.GothamBold
TextLabel2.TextXAlignment     = Enum.TextXAlignment.Left
TextLabel2.RichText           = true
TextLabel2.Parent             = Frame3

local HB = DEVICE == "mobile" and 20 or 22
local function headerButton(name, txt, xOff)
    local b = Instance.new("TextButton")
    b.Name            = name
    b.Size            = UDim2.new(0, HB, 0, HB)
    b.Position        = UDim2.new(1, xOff, 0.5, -HB/2)
    b.BackgroundColor3= C.card
    b.BorderSizePixel = 0
    b.ZIndex          = 6
    b.Text            = txt
    b.TextColor3      = C.textMute
    b.TextSize        = L.textSize.header
    b.Font            = Enum.Font.GothamBold
    b.AutoButtonColor = false
    b.Parent          = Frame3
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    local s = Instance.new("UIStroke"); s.Color = C.stroke; s.Parent = b
    return b
end

local hbOff = DEVICE == "mobile" and {-64, -42, -20} or {-70, -46, -22}
local LockBtn  = headerButton("Lock",  "ðŸ”“", hbOff[1])
local MinBtn   = headerButton("Min",   "â€“",  hbOff[2])
local CloseBtn = headerButton("Close", "X",  hbOff[3])

local Frame7 = Instance.new("Frame")
Frame7.Size             = UDim2.new(1, 0, 0, 69)
Frame7.Position         = UDim2.new(0, 0, 0, 34)
Frame7.BackgroundTransparency = 1
Frame7.BorderSizePixel  = 0
Frame7.ZIndex           = 4
Frame7.Parent           = Frame

local Frame8 = Instance.new("Frame")
Frame8.Size             = UDim2.new(1, 0, 0, 1)
Frame8.Position         = UDim2.new(0, 0, 0, 55)
Frame8.BackgroundColor3 = C.stroke
Frame8.BorderSizePixel  = 0
Frame8.ZIndex           = 4
Frame8.Parent           = Frame7

local function actionButton(name, label, xPos, bW)
    local btn = Instance.new("TextButton")
    btn.Name            = name
    btn.Size            = UDim2.new(0, bW, 0, L.btnH)
    btn.Position        = UDim2.new(0, xPos, 0, 8)
    btn.BackgroundColor3= C.card
    btn.BorderSizePixel = 0
    btn.ZIndex          = 5
    btn.Text            = ""
    btn.AutoButtonColor = false
    btn.Parent          = Frame7
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
    local s = Instance.new("UIStroke"); s.Color = C.stroke; s.Parent = btn
    local top = Instance.new("Frame")
    top.Size             = UDim2.new(1, -10, 0, 2)
    top.Position         = UDim2.new(0, 5, 0, 0)
    top.BackgroundColor3 = C.stroke
    top.BorderSizePixel  = 0
    top.ZIndex           = 6
    top.Parent           = btn
    Instance.new("UICorner", top).CornerRadius = UDim.new(0, 1)
    local lbl = Instance.new("TextLabel")
    lbl.Size             = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.ZIndex           = 7
    lbl.Text             = label
    lbl.TextColor3       = C.textBright
    lbl.TextSize         = L.textSize.btn
    lbl.Font             = Enum.Font.GothamBold
    lbl.Parent           = btn
    return btn, top
end

local FLASHTP, flashAccent = actionButton("FLASH TP", "FLASH TP", L.actionXs[1], L.btnSize)
local BLOCK,   blockAccent = actionButton("BLOCK",    "BLOCK",    L.actionXs[2], L.btnSize)
local RESET,   resetAccent = actionButton("RESET",    "RESET",    L.actionXs[3], L.btnSize)

-- Barre d'onglets (En dessous de Flash, Block, Reset)
local Frame12 = Instance.new("Frame")
Frame12.Size             = UDim2.new(1, 0, 0, L.tabH)
Frame12.Position         = UDim2.new(0, 0, 0, 90)
Frame12.BackgroundColor3 = C.tabBar
Frame12.BorderSizePixel  = 0
Frame12.ZIndex           = 5
Frame12.Parent           = Frame
local UIListLayout = Instance.new("UIListLayout")
UIListLayout.SortOrder        = Enum.SortOrder.LayoutOrder
UIListLayout.FillDirection    = Enum.FillDirection.Horizontal
UIListLayout.VerticalAlignment= Enum.VerticalAlignment.Center
UIListLayout.Parent           = Frame12

-- FIX : Changement de la taille de 155 fixe Ã  0.5 (MoitiÃ© exacte de la largeur) pour Ã©viter le dÃ©bordement
local TextButton4 = Instance.new("TextButton")
TextButton4.Size             = UDim2.new(0.5, 0, 1, 0)
TextButton4.BackgroundColor3 = C.tabBar
TextButton4.BorderSizePixel = 0
TextButton4.ZIndex           = 5
TextButton4.LayoutOrder      = 1
TextButton4.Text             = ""
TextButton4.AutoButtonColor  = false
TextButton4.Parent           = Frame12

local TextLabel7 = Instance.new("TextLabel")
TextLabel7.Size               = UDim2.new(1, 0, 1, 0)
TextLabel7.BackgroundTransparency = 1
TextLabel7.ZIndex             = 6
TextLabel7.Text               = "Brainrots"
TextLabel7.TextColor3         = C.textBlue
TextLabel7.TextSize           = L.textSize.tab
TextLabel7.Font               = Enum.Font.GothamMedium
TextLabel7.Parent             = TextButton4

local Frame13 = Instance.new("Frame")
Frame13.Size             = UDim2.new(1, -16, 0, 2)
Frame13.Position         = UDim2.new(0, 8, 1, -2)
Frame13.BackgroundColor3 = C.accent
Frame13.BorderSizePixel  = 0
Frame13.ZIndex           = 7
Frame13.Parent           = TextButton4
Instance.new("UICorner", Frame13).CornerRadius = UDim.new(0, 1)

-- FIX : Changement de la taille de 155 fixe Ã  0.5 Ã©galement
local TextButton5 = Instance.new("TextButton")
TextButton5.Size             = UDim2.new(0.5, 0, 1, 0)
TextButton5.BackgroundColor3 = C.tabBar
TextButton5.BorderSizePixel = 0
TextButton5.ZIndex           = 5
TextButton5.LayoutOrder      = 2
TextButton5.Text             = ""
TextButton5.AutoButtonColor  = false
TextButton5.Parent           = Frame12

local TextLabel8 = Instance.new("TextLabel")
TextLabel8.Size               = UDim2.new(1, 0, 1, 0)
TextLabel8.BackgroundTransparency = 1
TextLabel8.ZIndex             = 6
TextLabel8.Text               = "Settings"
TextLabel8.TextColor3         = C.textDim
TextLabel8.TextSize           = L.textSize.tab
TextLabel8.Font               = Enum.Font.GothamMedium
TextLabel8.Parent             = TextButton5

local Frame14 = Instance.new("Frame")
Frame14.Size                 = UDim2.new(1, -16, 0, 2)
Frame14.Position             = UDim2.new(0, 8, 1, -2)
Frame14.BackgroundColor3     = C.accent
Frame14.BackgroundTransparency = 1
Frame14.BorderSizePixel      = 0
Frame14.ZIndex               = 7
Frame14.Parent               = TextButton5
Instance.new("UICorner", Frame14).CornerRadius = UDim.new(0, 1)

local Frame15 = Instance.new("Frame")
Frame15.Size             = UDim2.new(1, 0, 0, 1)
Frame15.Position         = UDim2.new(0, 0, 0, 121)
Frame15.BackgroundColor3 = C.stroke
Frame15.BorderSizePixel  = 0
Frame15.ZIndex           = 6
Frame15.Parent           = Frame

local Frame16 = Instance.new("Frame")
Frame16.Size             = UDim2.new(1, 0, 1, -126)
Frame16.Position         = UDim2.new(0, 0, 0, 122)
Frame16.BackgroundTransparency = 1
Frame16.BorderSizePixel  = 0
Frame16.ZIndex           = 2
Frame16.ClipsDescendants = true
Frame16.Parent           = Frame

local Frame17 = Instance.new("Frame")
Frame17.Name             = "Frame"
Frame17.Size             = UDim2.new(1, 0, 1, 0)
Frame17.BackgroundTransparency = 1
Frame17.BorderSizePixel  = 0
Frame17.ZIndex           = 3
Frame17.Parent           = Frame16

local ScrollingFrame = Instance.new("ScrollingFrame")
ScrollingFrame.Name                  = "ScrollingFrame"
ScrollingFrame.Size                  = UDim2.new(1, 0, 1, 0)
ScrollingFrame.BackgroundTransparency= 1
ScrollingFrame.BorderSizePixel       = 0
ScrollingFrame.Active                = false
ScrollingFrame.CanvasSize            = UDim2.new(0, 0, 0, 0)
ScrollingFrame.ScrollBarThickness    = 3
ScrollingFrame.ScrollBarImageColor3  = C.accent
ScrollingFrame.ScrollingDirection    = Enum.ScrollingDirection.Y
ScrollingFrame.AutomaticCanvasSize   = Enum.AutomaticSize.Y
ScrollingFrame.Parent                = Frame17

local UIListLayout2 = Instance.new("UIListLayout")
UIListLayout2.SortOrder           = Enum.SortOrder.LayoutOrder
UIListLayout2.HorizontalAlignment = Enum.HorizontalAlignment.Center
UIListLayout2.Padding             = UDim.new(0, 4)
UIListLayout2.Parent              = ScrollingFrame

local UIPaddingList = Instance.new("UIPadding")
UIPaddingList.PaddingTop    = UDim.new(0, 6)
UIPaddingList.PaddingBottom = UDim.new(0, 6)
UIPaddingList.PaddingLeft   = UDim.new(0, 4)
UIPaddingList.PaddingRight  = UDim.new(0, 4)
UIPaddingList.Parent        = ScrollingFrame

scrollListRef = ScrollingFrame

local Frame21 = Instance.new("Frame")
Frame21.Name             = "Frame"
Frame21.Size             = UDim2.new(1, 0, 1, 0)
Frame21.Position         = UDim2.new(1, 0, 0, 0)
Frame21.BackgroundTransparency = 1
Frame21.BorderSizePixel  = 0
Frame21.Visible          = false
Frame21.ZIndex           = 3
Frame21.Parent           = Frame16

local ScrollingFrame2 = Instance.new("ScrollingFrame")
ScrollingFrame2.Size                  = UDim2.new(1, 0, 1, 0)
ScrollingFrame2.BackgroundTransparency= 1
ScrollingFrame2.BorderSizePixel       = 0
ScrollingFrame2.CanvasSize            = UDim2.new(0, 0, 0, 0)
ScrollingFrame2.ScrollBarThickness    = 3
ScrollingFrame2.ScrollBarImageColor3  = C.accent
ScrollingFrame2.ScrollingDirection    = Enum.ScrollingDirection.Y
ScrollingFrame2.AutomaticCanvasSize   = Enum.AutomaticSize.Y
ScrollingFrame2.Parent                = Frame21

local UIListLayout3 ... (20 Ko restants)