local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Constants"))
local WorldConfig = require(ReplicatedStorage.world.WorldConfig)
local SimpleBoat = require(script.Parent:WaitForChild("SimpleBoat"))

local M = {}

local function placeCharacterOnLand(player)
    player.CharacterAdded:Connect(function(char)
        task.defer(function()
            local hrp = char:WaitForChild("HumanoidRootPart", 10)
            if hrp then char:PivotTo(Constants.PLAYER_SPAWN) end
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

local function spawnBoatFor(player)
    removeBoat(player.UserId)

    local boat = SimpleBoat.create(player.UserId)
    boat.Parent = Workspace

    local cf = WorldConfig.BOAT_WATER_SPAWN
    boat:PivotTo(cf)

    -- now unanchor
    for _, d in ipairs(boat:GetDescendants()) do
        if d:IsA("BasePart") then d.Anchored = false end
    end

    print("[BoatService] spawned @", cf.Position, "path:", boat:GetFullName())
end

local heartbeatConn
local function startController()
    if heartbeatConn then heartbeatConn:Disconnect() end
    heartbeatConn = RunService.Heartbeat:Connect(function(dt)
        for _, boat in ipairs(Workspace:GetChildren()) do
            if not boat:IsA("Model") then continue end
            if not boat:GetAttribute(Constants.BOAT_OWNER_ATTR) then continue end
            local hull = boat:FindFirstChild("Hull")
            local seat = boat:FindFirstChild("Helm")
            if not (hull and hull:IsA("BasePart") and seat and seat:IsA("VehicleSeat")) then continue end

            local rootAttach = hull:FindFirstChild("RootAttachment")
            local thrust = hull:FindFirstChild("Thrust")
            local gyro = hull:FindFirstChild("Yaw")
            local lin = hull:FindFirstChildOfClass("LinearVelocity")
            if not (rootAttach and thrust and gyro and lin) then continue end

            local maxThrust = boat:GetAttribute("MaxThrust") or 8000
            local turnTorque = boat:GetAttribute("TurnTorque") or 3000
            local linDrag = boat:GetAttribute("LinearDrag") or 0.5
            local angDrag = boat:GetAttribute("AngularDrag") or 0.5

            local throttle = seat.ThrottleFloat
            local steer = seat.SteerFloat

            local look = hull.CFrame.LookVector
            local fwd = Vector3.new(look.X, 0, look.Z)
            if fwd.Magnitude > 0 then fwd = fwd.Unit else fwd = Vector3.new(0,0,-1) end

            thrust.Force = fwd * (maxThrust * throttle)
            gyro.AngularVelocity = Vector3.new(0, steer * (turnTorque / 1000), 0)

            local v = hull.AssemblyLinearVelocity
            local horizV = Vector3.new(v.X, 0, v.Z)
            thrust.Force += -horizV * (linDrag * 60)

            local av = hull.AssemblyAngularVelocity
            local yawDrag = -Vector3.new(0, av.Y, 0) * (angDrag * 60)
            gyro.AngularVelocity += yawDrag
        end
    end)
end

function M.start()
    print("[BoatService] starting")
    Players.PlayerAdded:Connect(function(p)
        print("[BoatService] PlayerAdded", p.Name)
        placeCharacterOnLand(p)
        spawnBoatFor(p)
        print("[BoatService] spawned boat for", p.Name, p.UserId)
    end)

    local existing = Players:GetPlayers()
    print("[BoatService] existing players at start:", #existing)
    for _, p in ipairs(existing) do
        placeCharacterOnLand(p)
        spawnBoatFor(p)
        print("[BoatService] spawned boat for (existing)", p.Name, p.UserId)
    end
    startController()
end

return M
