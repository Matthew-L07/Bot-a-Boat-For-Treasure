-- ai/navigation/Env.lua
-- Enhanced environment with velocity rewards and improved state representation

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Env = {}

----------------------------------------------------------------------
-- Config modules
----------------------------------------------------------------------

local Config
pcall(function()
    Config = require(script.Parent:WaitForChild("Config"))
end)

local function tryGetWorldConfig()
    local candidates = { "world", "World" }
    for _, name in ipairs(candidates) do
        local folder = ReplicatedStorage:FindFirstChild(name)
        if folder and folder:IsA("Folder") then
            local ok, mod = pcall(function()
                return require(folder:WaitForChild("WorldConfig"))
            end)
            if ok and mod then
                return mod
            end
        end
    end
    return nil
end

local WorldConfig = tryGetWorldConfig()

----------------------------------------------------------------------
-- Geometry constants
----------------------------------------------------------------------

local DEFAULT_RIVER_FORWARD = Vector3.new(0, 0, -1)

local RIVER_FORWARD = WorldConfig and WorldConfig.RIVER_FORWARD or DEFAULT_RIVER_FORWARD
if RIVER_FORWARD.Magnitude < 1e-3 then
    RIVER_FORWARD = DEFAULT_RIVER_FORWARD
end
RIVER_FORWARD = RIVER_FORWARD.Unit

local RIVER_ORIGIN = WorldConfig and WorldConfig.RIVER_ORIGIN or Vector3.new(0, 0, 0)
local RIVER_LENGTH = WorldConfig and WorldConfig.RIVER_LENGTH or 1000

local RIVER_CENTER_X = WorldConfig and WorldConfig.RIVER_CENTER_X or 0
local RIVER_HALF_WIDTH = WorldConfig and WorldConfig.RIVER_HALF_WIDTH or 150

local MAX_RAY_DISTANCE = WorldConfig and WorldConfig.OBSTACLE_SENSE_DISTANCE or 200

----------------------------------------------------------------------
-- Enhanced reward constants
----------------------------------------------------------------------

local PROGRESS_REWARD_SCALE = (Config and Config.progressRewardScale) or 2.0
local STEP_PENALTY = (Config and Config.stepPenalty) or -0.002
local FINISH_REWARD = (Config and Config.finishReward) or 20.0
local CRASH_PENALTY = (Config and Config.crashPenalty) or -10.0

local VELOCITY_REWARD_SCALE = (Config and Config.velocityRewardScale) or 0.5
local TARGET_FORWARD_SPEED = (Config and Config.targetForwardSpeed) or 0.7
local LATERAL_PENALTY_SCALE = (Config and Config.lateralPenaltyScale) or 0.3

local ALIGNMENT_REWARD_SCALE = (Config and Config.alignmentRewardScale) or 0.2

----------------------------------------------------------------------
-- Helper functions
----------------------------------------------------------------------

local function clamp01(x)
    if x < 0 then
        return 0
    elseif x > 1 then
        return 1
    else
        return x
    end
end

local function clampSymmetric(x, limit)
    if x > limit then
        return limit
    elseif x < -limit then
        return -limit
    else
        return x
    end
end

local function getBoatRoot(boat)
    if not boat or not boat:IsA("Model") then
        return nil
    end

    local root = boat.PrimaryPart
    if root and root:IsA("BasePart") then
        return root
    end

    return boat:FindFirstChildWhichIsA("BasePart")
end

local function computeProgress(pos)
    local offset = pos - RIVER_ORIGIN
    local d = offset:Dot(RIVER_FORWARD)
    return clamp01(d / RIVER_LENGTH)
end

local function computeLateralOffset(pos)
    local dx = pos.X - RIVER_CENTER_X
    if RIVER_HALF_WIDTH <= 0 then
        return 0
    end
    local t = dx / RIVER_HALF_WIDTH
    return clampSymmetric(t, 1)
end

local function decomposeVelocity(root)
    local vel = root.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
    local forward = root.CFrame.LookVector
    local right = root.CFrame.RightVector

    local forwardSpeed = vel:Dot(forward)
    local lateralSpeed = vel:Dot(right)

    local speedNorm = 100
    return forwardSpeed / speedNorm, lateralSpeed / speedNorm
end

local function getVelocityMagnitude(root)
    local vel = root.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
    local magnitude = vel.Magnitude
    return magnitude / 100
end

local function rayDistanceNormalized(root, localDir)
    localDir = localDir.Unit

    local cf = root.CFrame
    local worldDir = cf:VectorToWorldSpace(localDir)

    local origin = root.Position + cf.LookVector * 5 + Vector3.new(0, 3, 0)

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { root.Parent }
    params.IgnoreWater = true

    local result = Workspace:Raycast(origin, worldDir * MAX_RAY_DISTANCE, params)
    if not result then
        return 1.0
    end

    local dist = (result.Position - origin).Magnitude
    return clamp01(dist / MAX_RAY_DISTANCE)
end

----------------------------------------------------------------------
-- Public API: getState
----------------------------------------------------------------------

function Env.getState(boat)
    local root = getBoatRoot(boat)
    if not root then
        return nil, nil
    end

    local pos = root.Position

    local progress = computeProgress(pos)
    local lateral = computeLateralOffset(pos)

    local headingForward = root.CFrame.LookVector
    local headingDot = headingForward:Dot(RIVER_FORWARD)
    headingDot = clampSymmetric(headingDot, 1)

    local forwardSpeed, lateralSpeed = decomposeVelocity(root)
    local velocityMag = getVelocityMagnitude(root)

    -- IMPORTANT: ray directions are forward (+Z in local space), not backward
    local distCenter = rayDistanceNormalized(root, Vector3.new(0, 0, 1))
    local distLeft   = rayDistanceNormalized(root, Vector3.new(-1, 0, 0))
    local distRight  = rayDistanceNormalized(root, Vector3.new(1, 0, 0))

    


    local state = {
        progress,
        lateral,
        headingDot,
        forwardSpeed,
        lateralSpeed,
        velocityMag,
        distCenter,
        distLeft,
        distRight,
    }

    local info = {
        progress = progress,
        lateral = lateral,
        headingDot = headingDot,
        forwardSpeed = forwardSpeed,
        lateralSpeed = lateralSpeed,
        velocityMag = velocityMag,
        distCenter = distCenter,
        distLeft = distLeft,
        distRight = distRight,
        finished = boat:GetAttribute("Finished") == true,
        crashed = (boat:GetAttribute("Crashed") == true)
            or (boat:GetAttribute("Sunk") == true),
    }

    return state, info
end

----------------------------------------------------------------------
-- Public API: getRewardAndDone (Enhanced)
----------------------------------------------------------------------

function Env.getRewardAndDone(prevInfo, info, stepCount)
    if not prevInfo or not info then
        return 0, false
    end

    local reward = 0
    local done = false

    local prevProgress = prevInfo.progress or 0
    local currProgress = info.progress or 0
    local deltaProgress = currProgress - prevProgress
    local progressReward = PROGRESS_REWARD_SCALE * deltaProgress
    reward += progressReward

    local forwardSpeed = info.forwardSpeed or 0
    local velocityReward = 0
    
    if forwardSpeed > 0 then
        local speedDiff = math.abs(forwardSpeed - TARGET_FORWARD_SPEED)
        velocityReward = VELOCITY_REWARD_SCALE * (1.0 - speedDiff)
    else
        velocityReward = VELOCITY_REWARD_SCALE * forwardSpeed
    end
    
    reward += velocityReward

    local headingDot = info.headingDot or 0
    local alignmentReward = ALIGNMENT_REWARD_SCALE * headingDot
    reward += alignmentReward

    local lateralSpeed = math.abs(info.lateralSpeed or 0)
    local lateralPenalty = -LATERAL_PENALTY_SCALE * lateralSpeed
    reward += lateralPenalty

    reward += STEP_PENALTY

    -- Only allow positive reward if we actually moved closer to the finish
    if deltaProgress <= 0 and reward > 0 then
        reward = 0
    end

    if info.finished and not prevInfo.finished then
        reward += FINISH_REWARD
        done = true
    elseif info.crashed and not prevInfo.crashed then
        reward += CRASH_PENALTY
        done = true
    end

    return reward, done
end

return Env
