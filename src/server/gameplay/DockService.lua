local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.world.WorldConfig)
local Constants = require(ReplicatedStorage:WaitForChild("Constants"))

local M = {}

-- Track which boats are docked: [ownerUserId] = boatInstance
local dockedBoats = {}
local connections = {}

----------------------------------------------------------------------
-- Dock creation / management
----------------------------------------------------------------------

local function createDock()
    -- Create a dock structure at the spawn location
    local dockFolder = Instance.new("Folder")
    dockFolder.Name = "Dock"
    dockFolder.Parent = Workspace
    
    local spawnCF = WorldConfig.BOAT_WATER_SPAWN
    local dockWidth = 30
    local dockLength = 40

    local dockPos = Vector3.new(
        spawnCF.Position.X,
        WorldConfig.WATER_SURFACE_Y - 0.5,
        spawnCF.Position.Z
    )

    -- Compute direction from dock toward finish line
    local goalPos = Vector3.new(dockPos.X, dockPos.Y, WorldConfig.COURSE_FINISH_Z)
    local dir = goalPos - dockPos
    if dir.Magnitude == 0 then
        dir = Vector3.new(0, 0, -1)
    end
    local forwardDir = Vector3.new(dir.X, 0, dir.Z).Unit

    -- Orient dock so its forward faces downriver (toward the finish line)
    local dockCF = CFrame.lookAt(dockPos, dockPos + forwardDir)

    -- Main dock platform
    local platform = Instance.new("Part")
    platform.Name = "DockPlatform"
    platform.Size = Vector3.new(dockWidth, 2, dockLength)
    platform.Material = Enum.Material.WoodPlanks
    platform.Color = Color3.fromRGB(139, 90, 43)
    platform.Anchored = true
    platform.CanCollide = true
    platform.CFrame = dockCF
    platform.Parent = dockFolder

    -- Dock posts (4 corners)
    local postPositions = {
        Vector3.new(-dockWidth/2 + 2, -5, -dockLength/2 + 2),
        Vector3.new(dockWidth/2 - 2, -5, -dockLength/2 + 2),
        Vector3.new(-dockWidth/2 + 2, -5, dockLength/2 - 2),
        Vector3.new(dockWidth/2 - 2, -5, dockLength/2 - 2),
    }
    
    for i, offset in ipairs(postPositions) do
        local post = Instance.new("Part")
        post.Name = "DockPost" .. i
        post.Size = Vector3.new(2, 10, 2)
        post.Material = Enum.Material.Wood
        post.Color = Color3.fromRGB(100, 70, 40)
        post.Anchored = true
        post.CanCollide = true
        post.CFrame = platform.CFrame * CFrame.new(offset)
        post.Parent = dockFolder
    end
    
    -- Railings
    local railingHeight = 3
    local railingSides = {
        {pos = Vector3.new(0, railingHeight, -dockLength/2), size = Vector3.new(dockWidth, 0.5, 1)},
        {pos = Vector3.new(0, railingHeight, dockLength/2), size = Vector3.new(dockWidth, 0.5, 1)},
        {pos = Vector3.new(-dockWidth/2, railingHeight, 0), size = Vector3.new(1, 0.5, dockLength)},
        {pos = Vector3.new(dockWidth/2, railingHeight, 0), size = Vector3.new(1, 0.5, dockLength)},
    }
    
    for i, rail in ipairs(railingSides) do
        local railing = Instance.new("Part")
        railing.Name = "Railing" .. i
        railing.Size = rail.size
        railing.Material = Enum.Material.Wood
        railing.Color = Color3.fromRGB(120, 80, 50)
        railing.Anchored = true
        railing.CanCollide = true
        railing.CFrame = platform.CFrame * CFrame.new(rail.pos)
        railing.Parent = dockFolder
    end
    
    print("[DockService] Created dock at", platform.Position)
    return dockFolder
end

-- Public helper: ensure a dock exists (used when resetting episodes)
function M.ensureDock()
    local dock = Workspace:FindFirstChild("Dock")
    if dock and dock.Parent == Workspace then
        return dock
    end
    return createDock()
end

----------------------------------------------------------------------
-- Launch UI
----------------------------------------------------------------------

local function createLaunchButton(boat, player)
    -- Create a proximity prompt on the boat seat
    local seat = boat:FindFirstChild("Helm")
    if not seat then return end
    
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "LaunchPrompt"
    prompt.ActionText = "Launch Boat"
    prompt.ObjectText = "Press to Launch"
    prompt.HoldDuration = 0.5
    prompt.MaxActivationDistance = 15
    prompt.RequiresLineOfSight = false
    prompt.Style = Enum.ProximityPromptStyle.Default
    prompt.Parent = seat
    
    -- Create a visual indicator above the seat
    local indicator = Instance.new("Part")
    indicator.Name = "LaunchIndicator"
    indicator.Size = Vector3.new(4, 0.5, 4)
    indicator.Material = Enum.Material.Neon
    indicator.Color = Color3.fromRGB(255, 255, 0)
    indicator.Anchored = true
    indicator.CanCollide = false
    indicator.Transparency = 0.3
    indicator.CFrame = seat.CFrame * CFrame.new(0, 3, 0)
    indicator.Parent = seat
    
    -- Add a "READY TO LAUNCH" text
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Name = "LaunchText"
    billboardGui.Size = UDim2.new(0, 200, 0, 50)
    billboardGui.StudsOffset = Vector3.new(0, 4, 0)
    billboardGui.AlwaysOnTop = true
    billboardGui.Parent = seat
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = "READY TO LAUNCH"
    textLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
    textLabel.TextStrokeTransparency = 0
    textLabel.Font = Enum.Font.SourceSansBold
    textLabel.TextSize = 24
    textLabel.Parent = billboardGui
    
    -- Bobbing animation for indicator
    local bobConnection
    bobConnection = game:GetService("RunService").Heartbeat:Connect(function()
        if indicator and indicator.Parent then
            local time = tick()
            indicator.CFrame = seat.CFrame * CFrame.new(0, 3 + math.sin(time * 2) * 0.3, 0)
        else
            bobConnection:Disconnect()
        end
    end)
    
    return prompt, indicator, billboardGui
end

----------------------------------------------------------------------
-- Boat launch / dock
----------------------------------------------------------------------

function M.launchBoat(boat, player)
    local ownerUserId = boat:GetAttribute(Constants.BOAT_OWNER_ATTR)
    if not ownerUserId or dockedBoats[ownerUserId] ~= boat then
        warn("[DockService] launchBoat called but boat is not docked for", player and player.Name)
        return
    end
    
    print("[DockService] Launching boat for", player.Name)
    
    -- Remove docked status
    dockedBoats[ownerUserId] = nil
    
    -- Make dock disappear with animation
    local dock = Workspace:FindFirstChild("Dock")
    if dock then
        -- Fade out and sink the dock
        for _, part in ipairs(dock:GetDescendants()) do
            if part:IsA("BasePart") then
                task.spawn(function()
                    local originalCFrame = part.CFrame
                    local originalTransparency = part.Transparency
                    
                    for i = 0, 20 do
                        if part and part.Parent then
                            -- Sink down
                            part.CFrame = originalCFrame * CFrame.new(0, -i * 0.5, 0)
                            -- Fade out
                            part.Transparency = originalTransparency + (i / 20) * (1 - originalTransparency)
                            task.wait(0.05)
                        end
                    end
                end)
            end
        end
        
        -- Destroy dock after animation
        task.delay(1.5, function()
            if dock and dock.Parent then
                dock:Destroy()
                print("[DockService] Dock removed")
            end
        end)
    end
    
    -- Unanchor all parts
    for _, part in ipairs(boat:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = false
        end
    end
    
    -- Zero initial velocities for smooth start
    local hull = boat:FindFirstChild("CenterBlock") or boat:FindFirstChild("Hull")
    if hull and hull:IsA("BasePart") then
        hull.AssemblyLinearVelocity = Vector3.zero
        hull.AssemblyAngularVelocity = Vector3.zero
    end
    
    -- Remove launch button and indicator
    local seat = boat:FindFirstChild("Helm")
    if seat then
        local prompt = seat:FindFirstChild("LaunchPrompt")
        if prompt then prompt:Destroy() end
        
        local indicator = seat:FindFirstChild("LaunchIndicator")
        if indicator then indicator:Destroy() end
        
        local textGui = seat:FindFirstChild("LaunchText")
        if textGui then textGui:Destroy() end
    end
    
    -- Play launch sound
    local launchSound = Instance.new("Sound")
    launchSound.SoundId = "rbxassetid://6114974207" -- Boat horn sound
    launchSound.Volume = 0.5
    launchSound.Parent = hull or seat
    launchSound:Play()
    game:GetService("Debris"):AddItem(launchSound, 3)
    
    print("[DockService] Boat launched!")
end

function M.dockBoat(boat, player)
    local ownerUserId = boat:GetAttribute(Constants.BOAT_OWNER_ATTR)
    if not ownerUserId then return end
    
    -- Mark boat as docked for this owner
    dockedBoats[ownerUserId] = boat
    
    -- Keep all parts anchored
    for _, part in ipairs(boat:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
        end
    end
    
    -- Create launch button
    local prompt, indicator, textGui = createLaunchButton(boat, player)
    
    if prompt then
        local conn = prompt.Triggered:Connect(function(triggeringPlayer)
            -- Only the boat owner can launch
            if triggeringPlayer.UserId == ownerUserId then
                M.launchBoat(boat, triggeringPlayer)
            else
                -- Show message that only owner can launch
                local char = triggeringPlayer.Character
                if char then
                    local head = char:FindFirstChild("Head")
                    if head then
                        local gui = head:FindFirstChild("LaunchMessage") or Instance.new("BillboardGui")
                        gui.Name = "LaunchMessage"
                        gui.Size = UDim2.new(0, 200, 0, 50)
                        gui.StudsOffset = Vector3.new(0, 3, 0)
                        gui.Parent = head
                        
                        local text = gui:FindFirstChild("TextLabel") or Instance.new("TextLabel")
                        text.Size = UDim2.new(1, 0, 1, 0)
                        text.BackgroundTransparency = 1
                        text.Text = "Only the owner can launch!"
                        text.TextColor3 = Color3.fromRGB(255, 100, 100)
                        text.TextStrokeTransparency = 0
                        text.Font = Enum.Font.SourceSansBold
                        text.TextSize = 20
                        text.Parent = gui
                        
                        task.delay(2, function()
                            if gui and gui.Parent then
                                gui:Destroy()
                            end
                        end)
                    end
                end
            end
        end)
        table.insert(connections, conn)
    end
    
    print("[DockService] Boat docked for", player.Name)
end

function M.isBoatDocked(boat)
    local ownerUserId = boat:GetAttribute(Constants.BOAT_OWNER_ATTR)
    if not ownerUserId then
        return false
    end
    return dockedBoats[ownerUserId] == boat
end

-- Return the currently docked boat for this player if it exists
function M.getDockedBoatForPlayer(player)
    local userId = player.UserId
    local boat = dockedBoats[userId]
    if boat and boat.Parent then
        return boat
    end
    dockedBoats[userId] = nil
    return nil
end

-- Hard-reset all boats for this player (used between episodes)
function M.clearBoatsForPlayer(player)
    local userId = player.UserId
    dockedBoats[userId] = nil

    -- Destroy any full boats for this player
    for _, model in ipairs(Workspace:GetChildren()) do
        if model:IsA("Model") and model:GetAttribute(Constants.BOAT_OWNER_ATTR) == userId then
            model:Destroy()
        end
    end

    -- NEW: also destroy detached debris tagged with this owner
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("BasePart") and inst:GetAttribute(Constants.BOAT_OWNER_ATTR) == userId then
            inst:Destroy()
        end
    end
end


----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function M.start()
    print("[DockService] Starting...")
    
    -- Create the dock structure
    createDock()
    
    print("[DockService] Started successfully")
end

function M.stop()
    for _, conn in ipairs(connections) do
        conn:Disconnect()
    end
    connections = {}
    dockedBoats = {}
end

return M
