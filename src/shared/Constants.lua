local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldConfig = require(ReplicatedStorage.world.WorldConfig)

local Constants = {}

Constants.PLAYER_SPAWN = WorldConfig.PLAYER_SPAWN
Constants.BOAT_SPAWN_POINTS = { WorldConfig.BOAT_WATER_SPAWN }

Constants.BOAT_NAME_PREFIX = "Boat_"
Constants.BOAT_OWNER_ATTR  = "OwnerUserId"

Constants.BOAT = {
    HullSize   = Vector3.new(12, 1.2, 8),
    MaxThrust  = 9000,
    TurnTorque = 3500,
    LinearDrag = 0.6,
    AngularDrag= 0.6,
}

return Constants
