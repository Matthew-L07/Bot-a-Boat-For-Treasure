local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WorldConfig = require(ReplicatedStorage.world.WorldConfig)

local M = {}

-- Configuration
local MAX_HEALTH = 100
local WATER_DAMAGE_PER_SECOND = 10  -- Damage taken per second in water
local DAMAGE_TICK_INTERVAL = 0.5    -- How often to apply damage (in seconds)
local WATER_CHECK_HEIGHT_OFFSET = 2 -- How far above feet to check for water

local playerData = {} -- Track player states
local connections = {}

local function isInWater(position)
    -- Check if position is in the river water
    local waterY = WorldConfig.WATER_SURFACE_Y
    local region = WorldConfig.CURRENT_REGION
    
    -- Check if below water surface
    if position.Y > waterY then
        return false
    end
    
    -- Check if within river bounds
    return position.X >= region.xMin and position.X <= region.xMax
       and position.Z >= region.zMin and position.Z <= region.zMax
       and position.Y >= region.yMin
end

local function createHealthGui(player)
    -- Create a simple health bar GUI
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "HealthGui"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = player:WaitForChild("PlayerGui")
    
    -- Background frame
    local frame = Instance.new("Frame")
    frame.Name = "HealthBar"
    frame.Size = UDim2.new(0, 200, 0, 30)
    frame.Position = UDim2.new(0.5, -100, 0, 20)
    frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    frame.BorderSizePixel = 2
    frame.BorderColor3 = Color3.fromRGB(0, 0, 0)
    frame.Parent = screenGui
    
    -- Health fill bar
    local healthFill = Instance.new("Frame")
    healthFill.Name = "Fill"
    healthFill.Size = UDim2.new(1, 0, 1, 0)
    healthFill.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    healthFill.BorderSizePixel = 0
    healthFill.Parent = frame
    
    -- Health text
    local healthText = Instance.new("TextLabel")
    healthText.Name = "Text"
    healthText.Size = UDim2.new(1, 0, 1, 0)
    healthText.BackgroundTransparency = 1
    healthText.Text = "100 / 100"
    healthText.TextColor3 = Color3.fromRGB(255, 255, 255)
    healthText.TextStrokeTransparency = 0.5
    healthText.Font = Enum.Font.SourceSansBold
    healthText.TextSize = 18
    healthText.Parent = frame
    
    return screenGui
end

local function updateHealthGui(player, currentHealth)
    local gui = player:FindFirstChild("PlayerGui"):FindFirstChild("HealthGui")
    if not gui then return end
    
    local frame = gui:FindFirstChild("HealthBar")
    if not frame then return end
    
    local fill = frame:FindFirstChild("Fill")
    local text = frame:FindFirstChild("Text")
    
    if fill then
        local healthPercent = math.max(0, currentHealth / MAX_HEALTH)
        fill.Size = UDim2.new(healthPercent, 0, 1, 0)
        
        -- Change color based on health
        if healthPercent > 0.6 then
            fill.BackgroundColor3 = Color3.fromRGB(0, 255, 0) -- Green
        elseif healthPercent > 0.3 then
            fill.BackgroundColor3 = Color3.fromRGB(255, 255, 0) -- Yellow
        else
            fill.BackgroundColor3 = Color3.fromRGB(255, 0, 0) -- Red
        end
    end
    
    if text then
        text.Text = string.format("%d / %d", math.floor(currentHealth), MAX_HEALTH)
    end
end

local function takeDamage(player, amount)
    local data = playerData[player.UserId]
    if not data then return end
    
    data.health = math.max(0, data.health - amount)
    updateHealthGui(player, data.health)
    
    -- Flash red effect
    local char = player.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            -- Visual feedback - briefly show damage
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    local originalColor = part.Color
                    part.Color = Color3.fromRGB(255, 100, 100)
                    task.delay(0.1, function()
                        if part and part.Parent then
                            part.Color = originalColor
                        end
                    end)
                end
            end
        end
    end
    
    print("[PlayerHealth]", player.Name, "took", amount, "damage. Health:", data.health)
    
    -- Check if player died
    if data.health <= 0 then
        data.health = 0
        updateHealthGui(player, 0)
        
        -- Kill the player
        local char = player.Character
        if char then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.Health = 0
                print("[PlayerHealth]", player.Name, "died from water damage!")
            end
        end
    end
end

local function setupPlayer(player)
    -- Initialize player data
    playerData[player.UserId] = {
        health = MAX_HEALTH,
        lastDamageTick = 0
    }
    
    -- Wait for character
    player.CharacterAdded:Connect(function(character)
        -- Reset health on respawn
        playerData[player.UserId].health = MAX_HEALTH
        playerData[player.UserId].lastDamageTick = 0
        
        -- Create health GUI
        task.wait(0.5) -- Wait for PlayerGui to exist
        createHealthGui(player)
        updateHealthGui(player, MAX_HEALTH)
        
        print("[PlayerHealth] Setup health for", player.Name)
    end)
    
    -- If character already exists
    if player.Character then
        task.spawn(function()
            task.wait(0.5)
            createHealthGui(player)
            updateHealthGui(player, MAX_HEALTH)
        end)
    end
end

local heartbeatConn
local function startHealthSystem()
    if heartbeatConn then heartbeatConn:Disconnect() end
    
    heartbeatConn = RunService.Heartbeat:Connect(function(dt)
        local currentTime = tick()
        
        for _, player in ipairs(Players:GetPlayers()) do
            local data = playerData[player.UserId]
            if not data then continue end
            if data.health <= 0 then continue end
            
            local character = player.Character
            if not character then continue end
            
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if not (humanoid and rootPart) then continue end
            
            -- Skip if player is seated (in boat)
            if humanoid.Sit then continue end
            
            -- Check if player's feet are in water
            local feetPosition = rootPart.Position - Vector3.new(0, WATER_CHECK_HEIGHT_OFFSET, 0)
            
            if isInWater(feetPosition) then
                -- Apply damage at intervals
                if currentTime - data.lastDamageTick >= DAMAGE_TICK_INTERVAL then
                    local damageAmount = WATER_DAMAGE_PER_SECOND * DAMAGE_TICK_INTERVAL
                    takeDamage(player, damageAmount)
                    data.lastDamageTick = currentTime
                end
            end
        end
    end)
end

function M.start()
    print("[PlayerHealthService] Starting...")
    
    -- Setup existing players
    for _, player in ipairs(Players:GetPlayers()) do
        setupPlayer(player)
    end
    
    -- Setup new players
    local conn = Players.PlayerAdded:Connect(function(player)
        setupPlayer(player)
    end)
    table.insert(connections, conn)
    
    -- Cleanup on player leave
    local leaveConn = Players.PlayerRemoving:Connect(function(player)
        playerData[player.UserId] = nil
    end)
    table.insert(connections, leaveConn)
    
    -- Start the health monitoring system
    startHealthSystem()
    
    print("[PlayerHealthService] Started successfully")
end

function M.stop()
    if heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end
    
    for _, conn in ipairs(connections) do
        conn:Disconnect()
    end
    connections = {}
    playerData = {}
end

return M