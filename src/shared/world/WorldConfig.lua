local WorldConfig = {}

-- === Land ===
WorldConfig.BASE_CENTER = CFrame.new(0, 0, 0)
WorldConfig.BASE_SIZE   = Vector3.new(512, 40, 512)   -- surface Y = 0 + 40/2 = 20
local BASE_SURFACE_Y = WorldConfig.BASE_CENTER.Y + WorldConfig.BASE_SIZE.Y * 0.5

-- === River geometry (derived so water surface == ground surface) ===
WorldConfig.RIVER_WIDTH   = 48
WorldConfig.RIVER_LENGTH  = 420
WorldConfig.WATER_DEPTH   = 16   -- how far below ground the river bottom goes

local RIVER_TOP_Y    = BASE_SURFACE_Y
local RIVER_BOTTOM_Y = BASE_SURFACE_Y - WorldConfig.WATER_DEPTH
local RIVER_CENTER_Y = (RIVER_TOP_Y + RIVER_BOTTOM_Y) * 0.5

WorldConfig.RIVER_CENTER = CFrame.new(0, RIVER_CENTER_Y, 0)
WorldConfig.RIVER_SIZE   = Vector3.new(WorldConfig.RIVER_WIDTH, WorldConfig.WATER_DEPTH, WorldConfig.RIVER_LENGTH)
WorldConfig.WATER_SURFACE_Y = RIVER_TOP_Y

-- === Spawns ===
WorldConfig.PLAYER_SPAWN     = CFrame.new(-80, BASE_SURFACE_Y + 15, -160)
WorldConfig.BOAT_WATER_SPAWN = CFrame.new(0, WorldConfig.WATER_SURFACE_Y + 2.0, -180) -- spawn just above water

-- === Rocks (sit at the water surface) ===
WorldConfig.ROCK_COUNT        = 10
WorldConfig.ROCK_RADIUS_RANGE = Vector2.new(4, 8)
WorldConfig.ROCK_REGION = {
    xMin = -18, xMax = 18,
    zMin = -170, zMax = 170,
    y    = WorldConfig.WATER_SURFACE_Y,  -- place rocks at surface
}

-- === Water visuals ===
WorldConfig.WATER_TRANSPARENCY = 0.2
WorldConfig.WATER_REFLECTANCE  = 0.1
WorldConfig.WATER_WAVE_SIZE    = 0.15
WorldConfig.WATER_WAVE_SPEED   = 8.0
WorldConfig.WATER_COLOR        = Color3.fromRGB(16, 120, 180)

return WorldConfig
