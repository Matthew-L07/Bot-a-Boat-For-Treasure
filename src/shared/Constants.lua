local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldConfig = require(ReplicatedStorage.world.WorldConfig)

local Constants = {}

Constants.PLAYER_SPAWN = WorldConfig.PLAYER_SPAWN
Constants.BOAT_SPAWN_POINTS = { WorldConfig.BOAT_WATER_SPAWN }

Constants.BOAT_NAME_PREFIX = "Boat_"
Constants.BOAT_OWNER_ATTR  = "OwnerUserId"

Constants.BOAT = {
    HullSize    = Vector3.new(12, 1.5, 8),  -- Slightly taller for better buoyancy
    MaxThrust   = 18000,  -- Good acceleration
    TurnTorque  = 3000,   -- Turning speed (higher = faster turns)
    LinearDrag  = 0.7,    -- Water resistance
    AngularDrag = 1.2,    -- Rotation damping (higher = less spinning)
}

return Constants