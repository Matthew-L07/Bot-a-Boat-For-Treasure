-- ai/navigation/Env.lua
-- Fixed: Debug rays are now properly ignored by the raycaster so they don't cause collisions

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

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
-- Setup Debug Folder (Prevents self-collision)
----------------------------------------------------------------------

-- Create a dedicated folder for debug rays so we can filter it out easily
local DEBUG_FOLDER_NAME = "BotDebugRays"
local debugFolder = Workspace:FindFirstChild(DEBUG_FOLDER_NAME)
if not debugFolder then
    debugFolder = Instance.new("Folder")
    debugFolder.Name = DEBUG_FOLDER_NAME
    debugFolder.Parent = Workspace
end

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

local VISION_MAX_DISTANCE = (Config and Config.visionMaxDistance) or MAX_RAY_DISTANCE

local RAYCAST_FORWARD_OFFSET = 15
local RAYCAST_HEIGHT_OFFSET = 3

local FAR_LEFT_DIR_LOCAL      = Vector3.new(-1,   0, -1).Unit
local LEFT_DIR_LOCAL          = Vector3.new(-0.5, 0, -1).Unit
local CENTER_DIR_LOCAL        = Vector3.new(0,    0, -1)
local RIGHT_DIR_LOCAL         = Vector3.new(0.5,  0, -1).Unit
local FAR_RIGHT_DIR_LOCAL     = Vector3.new(1,    0, -1).Unit

----------------------------------------------------------------------
-- Reward constants
----------------------------------------------------------------------

local PROGRESS_REWARD_SCALE = (Config and Config.progressRewardScale) or 2.0
local STEP_PENALTY          = (Config and Config.stepPenalty) or -0.002
local FINISH_REWARD         = (Config and Config.finishReward) or 20.0
local CRASH_PENALTY         = (Config and Config.crashPenalty) or -10.0

local VELOCITY_REWARD_SCALE  = (Config and Config.velocityRewardScale) or 0.5
local TARGET_FORWARD_SPEED   = (Config and Config.targetForwardSpeed) or 0.7
local LATERAL_PENALTY_SCALE  = (Config and Config.lateralPenaltyScale) or 0.3
local ALIGNMENT_REWARD_SCALE = (Config and Config.alignmentRewardScale) or 0.2

local CHECKPOINT_STEP   = (Config and Config.checkpointStep)   or 0.1
local CHECKPOINT_REWARD = (Config and Config.checkpointReward) or 10.0

local CENTER_PENALTY_SCALE = (Config and Config.centerPenaltyScale) or 0.0

local OBSTACLE_PROX_PENALTY_SCALE = (Config and Config.obstacleProxPenaltyScale) or 0.0
local OBSTACLE_PROX_THRESHOLD     = (Config and Config.obstacleProxThreshold) or 0.4

local DEBUG_REWARD_SUMMARY = Config and Config.debugRewardSummary

----------------------------------------------------------------------
-- Helper functions
----------------------------------------------------------------------

local function clamp01(x)
    if x < 0 then return 0 elseif x > 1 then return 1 else return x end
end

local function clampSymmetric(x, limit)
    if x > limit then return limit elseif x < -limit then return -limit else return x end
end

local function getBoatRoot(boat)
    if not boat or not boat:IsA("Model") then return nil end
    local root = boat.PrimaryPart
    if root and root:IsA("BasePart") then return root end
    return boat:FindFirstChildWhichIsA("BasePart")
end

local function computeProgress(pos)
    local offset = pos - RIVER_ORIGIN
    local d = offset:Dot(RIVER_FORWARD)
    return clamp01(d / RIVER_LENGTH)
end

local function computeLateralOffset(pos)
    local dx = pos.X - RIVER_CENTER_X
    if RIVER_HALF_WIDTH <= 0 then return 0 end
    return clampSymmetric(dx / RIVER_HALF_WIDTH, 1)
end

local function decomposeVelocity(root)
    local vel = root.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
    local forward = root.CFrame.LookVector
    local right = root.CFrame.RightVector
    return vel:Dot(forward) / 100, vel:Dot(right) / 100
end

local function getVelocityMagnitude(root)
    return (root.AssemblyLinearVelocity or Vector3.new(0,0,0)).Magnitude / 100
end

----------------------------------------------------------------------
-- Visualization Helper
----------------------------------------------------------------------

local function visualizeRay(origin, direction, distance, didHit)
    if not (Config and Config.debugRays) then return end

    local p = Instance.new("Part")
    p.Anchored = true
    p.CanCollide = false
    p.CastShadow = false
    p.Material = Enum.Material.Neon
    p.Size = Vector3.new(0.1, 0.1, distance)
    
    p.Color = didHit and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 255, 0)
    
    local midpoint = origin + direction * (distance / 2)
    p.CFrame = CFrame.lookAt(midpoint, origin + direction * distance)
    
    -- IMPORTANT: Parent to the excluded folder!
    p.Parent = debugFolder 
    Debris:AddItem(p, 0.1) 
end

----------------------------------------------------------------------
-- Optimized raycasting (Filtered)
----------------------------------------------------------------------

local function rayDistanceNormalized(root, localDir)
    localDir = localDir.Unit

    local cf = root.CFrame
    local worldDir = cf:VectorToWorldSpace(localDir)

    local origin = root.Position 
        + cf.LookVector * RAYCAST_FORWARD_OFFSET
        + Vector3.new(0, RAYCAST_HEIGHT_OFFSET, 0)

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    -- CRITICAL FIX: Exclude the debug folder so rays don't hit their own visuals
    params.FilterDescendantsInstances = { root.Parent, debugFolder }
    params.IgnoreWater = true

    local result = Workspace:Raycast(origin, worldDir * VISION_MAX_DISTANCE, params)
    
    if not result then
        visualizeRay(origin, worldDir, VISION_MAX_DISTANCE, false)
        return 1.0
    end

    local dist = (result.Position - origin).Magnitude
    visualizeRay(origin, worldDir, dist, true)
    
    return clamp01(dist / VISION_MAX_DISTANCE)
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function Env.getState(boat)
    local root = getBoatRoot(boat)
    if not root then return nil, nil end

    local pos = root.Position
    local progress = computeProgress(pos)
    local lateral = computeLateralOffset(pos)

    local headingForward = root.CFrame.LookVector
    local headingDot = clampSymmetric(headingForward:Dot(RIVER_FORWARD), 1)

    local forwardSpeed, lateralSpeed = decomposeVelocity(root)
    local velocityMag = getVelocityMagnitude(root)

    local distFarLeft  = rayDistanceNormalized(root, FAR_LEFT_DIR_LOCAL)
    local distLeft     = rayDistanceNormalized(root, LEFT_DIR_LOCAL)
    local distCenter   = rayDistanceNormalized(root, CENTER_DIR_LOCAL)
    local distRight    = rayDistanceNormalized(root, RIGHT_DIR_LOCAL)
    local distFarRight = rayDistanceNormalized(root, FAR_RIGHT_DIR_LOCAL)

    local state = {
        progress, lateral, headingDot,
        forwardSpeed, lateralSpeed, velocityMag,
        distFarLeft, distLeft, distCenter, distRight, distFarRight,
    }

    local info = {
        progress = progress, lateral = lateral, headingDot = headingDot,
        forwardSpeed = forwardSpeed, lateralSpeed = lateralSpeed, velocityMag = velocityMag,
        distFarLeft = distFarLeft, distLeft = distLeft, distCenter = distCenter,
        distRight = distRight, distFarRight = distFarRight,
        finished = boat:GetAttribute("Finished") == true,
        crashed = (boat:GetAttribute("Crashed") == true) or (boat:GetAttribute("Sunk") == true),
    }

    return state, info
end

function Env.getRewardAndDone(prevInfo, info, stepCount)
    if not prevInfo or not info then return 0, false end

    local reward = 0
    local done = false

    local deltaProgress = (info.progress or 0) - (prevInfo.progress or 0)
    reward += PROGRESS_REWARD_SCALE * deltaProgress

    if DEBUG_REWARD_SUMMARY and (stepCount % 50 == 0) then
        print(string.format("[RewardDebug] step=%d dProg=%.3f", stepCount, deltaProgress))
    end

    if CHECKPOINT_STEP > 0 then
        local prevCP = math.floor((prevInfo.progress or 0) / CHECKPOINT_STEP)
        local currCP = math.floor((info.progress or 0) / CHECKPOINT_STEP)
        if currCP > prevCP then
            reward += CHECKPOINT_REWARD * (currCP - prevCP)
        end
    end

    local fwd = info.forwardSpeed or 0
    if fwd > 0 then
        reward += VELOCITY_REWARD_SCALE * (1.0 - math.abs(fwd - TARGET_FORWARD_SPEED))
    else
        reward += VELOCITY_REWARD_SCALE * fwd
    end

    reward += ALIGNMENT_REWARD_SCALE * (info.headingDot or 0)
    reward += -LATERAL_PENALTY_SCALE * math.abs(info.lateralSpeed or 0)

    if CENTER_PENALTY_SCALE > 0 then
        reward -= CENTER_PENALTY_SCALE * (math.abs(info.lateral or 0) ^ 2)
    end

    if OBSTACLE_PROX_PENALTY_SCALE > 0 then
        local minRay = math.min(info.distFarLeft or 1, info.distLeft or 1, info.distCenter or 1, info.distRight or 1, info.distFarRight or 1)
        if minRay < OBSTACLE_PROX_THRESHOLD then
            reward -= OBSTACLE_PROX_PENALTY_SCALE * ((OBSTACLE_PROX_THRESHOLD - minRay) / OBSTACLE_PROX_THRESHOLD)
        end
    end

    reward += STEP_PENALTY
    if deltaProgress <= 0 and reward > 0 then reward = 0 end

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