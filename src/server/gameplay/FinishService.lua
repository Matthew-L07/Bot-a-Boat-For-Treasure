local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Constants"))
local WorldConfig = require(ReplicatedStorage.world.WorldConfig)

local M = {}

local connections = {}
local finishedPlayers = {} -- [userId] = true

-- Helper: try to find the boat model for this part
local function getBoatFromPart(part)
    if not part then return nil end
    local model = part:FindFirstAncestorWhichIsA("Model")
    if model and model:GetAttribute(Constants.BOAT_OWNER_ATTR) then
        return model
    end
    return nil
end

local function getPlayerFromBoat(boat)
    local ownerUserId = boat:GetAttribute(Constants.BOAT_OWNER_ATTR)
    if not ownerUserId then return nil end
    return Players:GetPlayerByUserId(ownerUserId)
end

local function freezeBoat(boat)
    for _, part in ipairs(boat:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
        end
    end
    boat:SetAttribute("Finished", true)
end

local function createConfettiAbove(boat)
    local hull = boat:FindFirstChild("Hull")
    if not (hull and hull:IsA("BasePart")) then return end

    local part = Instance.new("Part")
    part.Name = "ConfettiEmitter"
    part.Size = Vector3.new(1, 1, 1)
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.CFrame = hull.CFrame * CFrame.new(0, 10, 0)
    part.Parent = Workspace

    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    emitter.Rate = 200
    emitter.Lifetime = NumberRange.new(1, 2)
    emitter.Speed = NumberRange.new(20, 30)
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(1, 0.1)
    })
    emitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
        ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 255, 0)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 0)),
        ColorSequenceKeypoint.new(0.75, Color3.fromRGB(0, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 255)),
    })
    emitter.Parent = part

    -- Burst quickly then stop
    emitter.Enabled = true
    task.delay(1.0, function()
        if emitter then
            emitter.Enabled = false
        end
    end)

    Debris:AddItem(part, 4)
end

local function showWinGui(player)
    if not player or not player:FindFirstChild("PlayerGui") then return end

    local playerGui = player.PlayerGui
    local existing = playerGui:FindFirstChild("WinGui")
    if existing then existing:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "WinGui"
    gui.ResetOnSpawn = false
    gui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0.5, 0, 0.3, 0)
    frame.Position = UDim2.new(0.25, 0, 0.35, 0)
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0.2
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, -20, 1, -20)
    text.Position = UDim2.new(0, 10, 0, 10)
    text.BackgroundTransparency = 1
    text.Text = "🎉 CONGRATS! You reached the treasure! 🎉"
    text.TextColor3 = Color3.fromRGB(255, 255, 255)
    text.TextStrokeTransparency = 0.3
    text.TextWrapped = true
    text.Font = Enum.Font.SourceSansBold
    text.TextSize = 36
    text.Parent = frame

    -- Optional: small "Play again" hint
    local hint = Instance.new("TextLabel")
    hint.Size = UDim2.new(1, -20, 0, 30)
    hint.Position = UDim2.new(0, 10, 1, -40)
    hint.BackgroundTransparency = 1
    hint.Text = "Reset your character to build another boat!"
    hint.TextColor3 = Color3.fromRGB(200, 200, 200)
    hint.TextStrokeTransparency = 0.8
    hint.Font = Enum.Font.SourceSans
    hint.TextSize = 20
    hint.Parent = frame

    -- Fade out after some time
    task.delay(8, function()
        if gui and gui.Parent then
            gui:Destroy()
        end
    end)
end

local function onPlayerFinished(boat)
    local player = getPlayerFromBoat(boat)
    if not player then return end
    if finishedPlayers[player.UserId] then return end -- already finished

    finishedPlayers[player.UserId] = true

    print("[FinishService]", player.Name, "has reached the finish line!")

    freezeBoat(boat)
    createConfettiAbove(boat)
    showWinGui(player)

    -- Optional: you could also award points, coins, etc. here
end

local function hookFinishTrigger()
    local finishModel = Workspace:FindFirstChild("FinishLine")
    if not finishModel then
        warn("[FinishService] No 'FinishLine' model found in Workspace")
        return
    end

    local trigger = finishModel:FindFirstChild("FinishTrigger")
    if not (trigger and trigger:IsA("BasePart")) then
        warn("[FinishService] No 'FinishTrigger' part found under FinishLine")
        return
    end

    local conn = trigger.Touched:Connect(function(hit)
        local boat = getBoatFromPart(hit)
        if not boat then return end
        onPlayerFinished(boat)
    end)

    table.insert(connections, conn)
    print("[FinishService] Bound to FinishTrigger touch event")
end

function M.start()
    print("[FinishService] Starting...")
    hookFinishTrigger()
    print("[FinishService] Started successfully")
end

function M.stop()
    for _, conn in ipairs(connections) do
        conn:Disconnect()
    end
    connections = {}
    finishedPlayers = {}
end

return M