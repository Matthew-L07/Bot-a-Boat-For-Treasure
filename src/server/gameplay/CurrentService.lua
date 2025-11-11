local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local WorldConfig = require(ReplicatedStorage.world.WorldConfig)
local Constants = require(ReplicatedStorage:WaitForChild("Constants"))

local M = {}

-- Tag to mark objects that should be affected by current
local CURRENT_TAG = "AffectedByCurrent"

local function isInCurrentRegion(position)
    if not WorldConfig.CURRENT_ENABLED then return false end
    
    local region = WorldConfig.CURRENT_REGION
    return position.X >= region.xMin and position.X <= region.xMax
       and position.Y >= region.yMin and position.Y <= region.yMax
       and position.Z >= region.zMin and position.Z <= region.zMax
end

local heartbeatConn
local function startCurrentSystem()
    if heartbeatConn then heartbeatConn:Disconnect() end
    
    heartbeatConn = RunService.Heartbeat:Connect(function(dt)
        if not WorldConfig.CURRENT_ENABLED then return end
        
        -- Apply current to boats
        for _, boat in ipairs(Workspace:GetChildren()) do
            if not boat:IsA("Model") then continue end
            if not boat:GetAttribute(Constants.BOAT_OWNER_ATTR) then continue end
            
            local hull = boat:FindFirstChild("Hull")
            if not (hull and hull:IsA("BasePart")) then continue end
            if hull.Anchored then continue end
            
            local position = hull.Position
            if not isInCurrentRegion(position) then continue end
            
            -- Apply current force directly to the CurrentForce VectorForce
            local currentForce = hull:FindFirstChild("CurrentForce")
            if currentForce and currentForce:IsA("VectorForce") then
                local direction = WorldConfig.CURRENT_DIRECTION.Unit
                local strength = WorldConfig.CURRENT_STRENGTH
                currentForce.Force = direction * strength
            end
        end
        
        -- Apply current to any other tagged objects
        for _, obj in ipairs(CollectionService:GetTagged(CURRENT_TAG)) do
            if not obj:IsA("BasePart") then continue end
            if obj.Anchored then continue end
            
            local position = obj.Position
            if not isInCurrentRegion(position) then continue end
            
            -- Apply impulse for tagged objects
            local direction = WorldConfig.CURRENT_DIRECTION.Unit
            local strength = WorldConfig.CURRENT_STRENGTH
            local mass = obj.AssemblyMass
            local impulse = direction * strength * dt * mass * 0.5
            obj:ApplyImpulse(impulse)
        end
    end)
end

function M.start()
    print("[CurrentService] Starting...")
    print("[CurrentService] Current enabled:", WorldConfig.CURRENT_ENABLED)
    print("[CurrentService] Current strength:", WorldConfig.CURRENT_STRENGTH)
    print("[CurrentService] Current direction:", WorldConfig.CURRENT_DIRECTION)
    
    -- Verify current region
    local region = WorldConfig.CURRENT_REGION
    print("[CurrentService] Current region X:", region.xMin, "to", region.xMax)
    print("[CurrentService] Current region Y:", region.yMin, "to", region.yMax)
    print("[CurrentService] Current region Z:", region.zMin, "to", region.zMax)
    
    startCurrentSystem()
    print("[CurrentService] Started successfully")
end

function M.stop()
    if heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end
end

return M