-- WorldConfig.lua

local WorldConfig = {}

-- === Land ===
WorldConfig.BASE_CENTER = CFrame.new(0, 0, 0)
-- Bigger base to hold a long, wide river (surface Y = 0 + 40/2 = 20)
WorldConfig.BASE_SIZE   = Vector3.new(2048, 40, 3072)
local BASE_SURFACE_Y = WorldConfig.BASE_CENTER.Y + WorldConfig.BASE_SIZE.Y * 0.5

-- === River geometry (water surface == ground surface) ===
WorldConfig.RIVER_WIDTH   = 120         -- was 48
WorldConfig.RIVER_LENGTH  = 2000        -- was 420
WorldConfig.WATER_DEPTH   = 18          -- a hair deeper for a bigger river

local RIVER_TOP_Y    = BASE_SURFACE_Y
local RIVER_BOTTOM_Y = BASE_SURFACE_Y - WorldConfig.WATER_DEPTH
local RIVER_CENTER_Y = (RIVER_TOP_Y + RIVER_BOTTOM_Y) * 0.5

WorldConfig.RIVER_CENTER = CFrame.new(0, RIVER_CENTER_Y, 0)
WorldConfig.RIVER_SIZE   = Vector3.new(WorldConfig.RIVER_WIDTH, WorldConfig.WATER_DEPTH, WorldConfig.RIVER_LENGTH)
WorldConfig.WATER_SURFACE_Y = RIVER_TOP_Y

-- === Spawns (place near the upstream end of the river) ===
local upstreamZ = -(WorldConfig.RIVER_LENGTH * 0.5) + 120
WorldConfig.PLAYER_SPAWN     = CFrame.new(-100, BASE_SURFACE_Y + 15, upstreamZ)
WorldConfig.BOAT_WATER_SPAWN = CFrame.new(0, WorldConfig.WATER_SURFACE_Y + 2.0, upstreamZ + 20)

-- === Rocks (sparse, inside the wet channel) ===
WorldConfig.ROCK_COUNT        = 16                         -- sparse across 2km
WorldConfig.ROCK_RADIUS_RANGE = Vector2.new(4, 8)
WorldConfig.ROCK_MIN_SPACING  = 35                         -- keep distance between rocks

-- Compute a rock region that fits inside the widened river
do
    local halfW = WorldConfig.RIVER_WIDTH * 0.5
    local halfL = WorldConfig.RIVER_LENGTH * 0.5
    -- Keep rocks away from banks a bit
    local marginX = 10
    local marginZ = 80

    WorldConfig.ROCK_REGION = {
        xMin = -halfW + marginX, xMax = halfW - marginX,
        zMin = -halfL + marginZ, zMax = halfL - marginZ,
        y    = WorldConfig.WATER_SURFACE_Y
    }
end

-- === Water visuals ===
WorldConfig.WATER_TRANSPARENCY = 0.2
WorldConfig.WATER_REFLECTANCE  = 0.1
WorldConfig.WATER_WAVE_SIZE    = 0.15
WorldConfig.WATER_WAVE_SPEED   = 8.0
WorldConfig.WATER_COLOR        = Color3.fromRGB(16, 120, 180)

return WorldConfig
