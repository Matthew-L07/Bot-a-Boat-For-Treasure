-- ai/navigation/Env.lua
-- Defines state representation and reward for the boat navigation task.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.world.WorldConfig)
local Config = require(script.Parent:WaitForChild("Config"))

local Env = {}

Env.STATE_DIM = Config.stateDim

-- Compute normalized state vector + auxiliary info
-- Returns stateVector (array of numbers) and info (table with raw values)
function Env.getState(boat)
    if not (boat and boat.Parent) then
        return nil, { crashed = true }
    end

    local hull = boat:FindFirstChild("CenterBlock") or boat:FindFirstChild("Hull")
    if not (hull and hull:IsA("BasePart")) then
        return nil, { crashed = true }
    end

    local seat = boat:FindFirstChild("Helm")

    -- === Progress along course (0 at start, 1 at finish) ===
    local pos = hull.Position
    local dz = WorldConfig.COURSE_FINISH_Z - WorldConfig.COURSE_START_Z
    if dz == 0 then dz = 1 end

    local zProgress = (pos.Z - WorldConfig.COURSE_START_Z) / dz
    zProgress = math.clamp(zProgress, 0, 1)

    -- === Lateral offset from river center line (x = 0 assumed center) ===
    local riverHalfWidth = WorldConfig.RIVER_WIDTH * 0.5
    local xOffset = pos.X / (riverHalfWidth + 1e-6)
    xOffset = math.clamp(xOffset, -1, 1)

    -- === Heading error relative to river direction ===
    local headingError = 0
    local riverDir = Vector3.new(0, 0, dz).Unit
    if seat and seat:IsA("VehicleSeat") then
        local forward = seat.CFrame.LookVector
        local dot = forward:Dot(riverDir)
        dot = math.clamp(dot, -1, 1)
        local angle = math.acos(dot) -- 0..pi

        -- Signed using cross product (Y component)
        local cross = forward:Cross(riverDir)
        local sign = (cross.Y >= 0) and 1 or -1
        headingError = (angle * sign) / math.pi -- normalize to [-1,1]
    end

    -- === Speed and yaw ===
    local vel = hull.AssemblyLinearVelocity
    local horizontalSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
    local maxSpeed = 80.0
    local speedNorm = math.clamp(horizontalSpeed / maxSpeed, 0, 1)

    local angVel = hull.AssemblyAngularVelocity
    local yawSpeed = math.abs(angVel.Y)
    local maxYaw = 5.0
    local yawNorm = math.clamp(yawSpeed / maxYaw, 0, 1)

    -- === Simple obstacle sensing via raycasts ===
    local function sense(dirVector)
        local origin = hull.Position + Vector3.new(0, 2, 0)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = { boat }

        local maxDist = 150
        local result = Workspace:Raycast(origin, dirVector.Unit * maxDist, params)
        if result then
            return math.clamp(result.Distance / maxDist, 0, 1)
        else
            return 1.0 -- nothing nearby
        end
    end

    local forwardVec = (seat and seat:IsA("VehicleSeat")) and seat.CFrame.LookVector or Vector3.new(0, 0, 1)
    local leftVec = (CFrame.fromAxisAngle(Vector3.new(0, 1, 0), -math.rad(30)) * forwardVec)
    local rightVec = (CFrame.fromAxisAngle(Vector3.new(0, 1, 0), math.rad(30)) * forwardVec)

    local distForward = sense(forwardVec)
    local distLeft = sense(leftVec)
    local distRight = sense(rightVec)

    -- Finished / crashed flags
    local finished = boat:GetAttribute("Finished") == true
    local crashed = (not boat.Parent)

    local stateVector = {
        zProgress,
        xOffset,
        headingError,
        speedNorm,
        yawNorm,
        distForward,
        distLeft,
        distRight,
    }

    local info = {
        zProgress = zProgress,
        xOffset = xOffset,
        headingError = headingError,
        speedNorm = speedNorm,
        yawNorm = yawNorm,
        distForward = distForward,
        distLeft = distLeft,
        distRight = distRight,
        finished = finished,
        crashed = crashed,
    }

    return stateVector, info
end

-- Compute reward + termination from previous and current info
function Env.getRewardAndDone(prevInfo, info, stepCount)
    if not prevInfo or not info then
        return 0, false
    end

    -- Per-step shaping reward
    local dz = info.zProgress - prevInfo.zProgress
    local reward = 5.0 * dz      -- forward progress
    reward -= 0.01               -- time penalty
    reward -= 0.1 * math.abs(info.xOffset)  -- keep near center

    local done = false

    -- Finish / crash bonuses
    if info.finished then
        reward += 10.0
        done = true
    end

    if info.crashed then
        reward -= 10.0
        done = true
    end

    -- Max steps cutoff
    if stepCount >= Config.maxEpisodeSteps then
        done = true
    end

    return reward, done
end

return Env
