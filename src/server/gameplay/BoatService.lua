local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Constants"))
local WorldConfig = require(ReplicatedStorage.world.WorldConfig)
local SimpleBoat = require(script.Parent:WaitForChild("SimpleBoat"))

local M = {}
local DockService -- Will be set via setDockService

local function placeCharacterOnLand(player)
    player.CharacterAdded:Connect(function(char)
        task.defer(function()
            local hrp = char:WaitForChild("HumanoidRootPart", 10)
            if hrp then
                char:PivotTo(Constants.PLAYER_SPAWN)
            end
        end)
    end)
end

local function removeBoat(ownerUserId)
    for _, m in ipairs(Workspace:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute(Constants.BOAT_OWNER_ATTR) == ownerUserId then
            m:Destroy()
        end
    end
end

local function seatPlayer(player, seat)
    local char = player.Character
    if not (char and seat and seat:IsA("Seat")) then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not (hum and hrp) then return end

    -- Move character above the seat
    local seatCF = seat.CFrame * CFrame.new(0, 5, 0)
    char:PivotTo(seatCF)
    task.wait(0.05)
    
    -- Sit the humanoid
    if seat:IsA("VehicleSeat") then
        seat:Sit(hum)
    end
end

local function spawnBoatFor(player)
    removeBoat(player.UserId)

    local boat = SimpleBoat.create(player.UserId)
    boat.Parent = Workspace

    -- Spawn position at dock
    local spawnCF = WorldConfig.BOAT_WATER_SPAWN
    local spawnPos = spawnCF.Position
    
    -- Position the boat oriented forward (looking down -Z)
    local boatCF = CFrame.new(spawnPos) * CFrame.Angles(0, 0, 0)
    boat:PivotTo(boatCF)

    -- Keep all parts ANCHORED initially (boat is docked)
    for _, d in ipairs(boat:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
        end
    end

    -- Zero initial velocities
    local hull = boat:FindFirstChild("CenterBlock") or boat:FindFirstChild("Hull")
    if hull and hull:IsA("BasePart") then
        hull.AssemblyLinearVelocity = Vector3.zero
        hull.AssemblyAngularVelocity = Vector3.zero
    end

    -- Dock the boat (adds launch button)
    if DockService then
        DockService.dockBoat(boat, player)
    end

    -- Auto-seat player after a brief delay
    local seat = boat:FindFirstChild("Helm")
    if seat and seat:IsA("VehicleSeat") then
        task.delay(0.3, function()
            seatPlayer(player, seat)
        end)
    end

    print("[BoatService] Spawned docked boat for", player.Name, "at", spawnPos)
end

local heartbeatConn
local function startController()
    if heartbeatConn then heartbeatConn:Disconnect() end
    
    heartbeatConn = RunService.Heartbeat:Connect(function(dt)
        for _, boat in ipairs(Workspace:GetChildren()) do
            if not boat:IsA("Model") then continue end
            if not boat:GetAttribute(Constants.BOAT_OWNER_ATTR) then continue end
            -- Skip finished boats (they've reached the treasure)
            if boat:GetAttribute("Finished") then continue end
            
            -- Skip docked boats
            if DockService and DockService.isBoatDocked(boat) then continue end
            
            local hull = boat:FindFirstChild("CenterBlock") or boat:FindFirstChild("Hull")
            local seat = boat:FindFirstChild("Helm")
            if not (hull and hull:IsA("BasePart") and seat and seat:IsA("VehicleSeat")) then continue end

            -- Get components
            local thrust = hull:FindFirstChild("Thrust")
            local turnControl = hull:FindFirstChild("TurnControl")
            if not (thrust and turnControl) then continue end

            -- Get parameters
            local maxThrust = boat:GetAttribute("MaxThrust") or 12000
            local turnSpeed = boat:GetAttribute("TurnTorque") or 4000
            local linDrag = boat:GetAttribute("LinearDrag") or 0.7
            local angDrag = boat:GetAttribute("AngularDrag") or 0.8

            -- Get input
            local throttle = seat.ThrottleFloat
            local steer = seat.SteerFloat

            -- Calculate forward direction (horizontal plane only)
            local lookVector = hull.CFrame.LookVector
            local forward = Vector3.new(lookVector.X, 0, lookVector.Z)
            if forward.Magnitude > 0 then
                forward = forward.Unit
            else
                forward = Vector3.new(0, 0, -1)
            end

            -- Apply thrust in forward direction
            local thrustForce = forward * (maxThrust * throttle)
            
            -- Apply linear drag (water resistance)
            local velocity = hull.AssemblyLinearVelocity
            local horizVel = Vector3.new(velocity.X, 0, velocity.Z)
            local dragForce = -horizVel * (linDrag * 100)
            
            thrust.Force = thrustForce + dragForce

            -- Apply smooth turning via AngularVelocity
            local desiredTurnRate = -steer * (turnSpeed / 1000)
            
            -- Get current angular velocity for damping
            local currentAngVel = hull.AssemblyAngularVelocity
            
            -- Apply damping when not actively steering
            local dampingFactor = angDrag * 0.5
            local finalTurnRate = desiredTurnRate - (currentAngVel.Y * dampingFactor)
            
            turnControl.AngularVelocity = Vector3.new(0, finalTurnRate, 0)
        end
    end)
end

function M.setDockService(dockServiceModule)
    DockService = dockServiceModule
end

function M.start()
    print("[BoatService] Starting...")
    
    Players.PlayerAdded:Connect(function(p)
        placeCharacterOnLand(p)
        spawnBoatFor(p)
    end)

    for _, p in ipairs(Players:GetPlayers()) do
        placeCharacterOnLand(p)
        spawnBoatFor(p)
    end

    startController()
    print("[BoatService] Started successfully")
end

return M