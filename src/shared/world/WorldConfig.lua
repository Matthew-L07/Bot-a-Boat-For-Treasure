-- WorldConfig.lua

local WorldConfig = {}

-- === Land ===
WorldConfig.BASE_CENTER = CFrame.new(0, 0, 0)
WorldConfig.BASE_SIZE   = Vector3.new(2048, 40, 3072)
local BASE_SURFACE_Y = WorldConfig.BASE_CENTER.Y + WorldConfig.BASE_SIZE.Y * 0.5

-- === River geometry (water surface == ground surface) ===
WorldConfig.RIVER_WIDTH   = 120
WorldConfig.RIVER_LENGTH  = 2000
WorldConfig.WATER_DEPTH   = 5

local RIVER_TOP_Y    = BASE_SURFACE_Y
local RIVER_BOTTOM_Y = BASE_SURFACE_Y - WorldConfig.WATER_DEPTH
local RIVER_CENTER_Y = (RIVER_TOP_Y + RIVER_BOTTOM_Y) * 0.5

WorldConfig.RIVER_CENTER = CFrame.new(0, RIVER_CENTER_Y, 0)
WorldConfig.RIVER_SIZE   = Vector3.new(WorldConfig.RIVER_WIDTH, WorldConfig.WATER_DEPTH, WorldConfig.RIVER_LENGTH)
WorldConfig.WATER_SURFACE_Y = RIVER_TOP_Y

-- === Spawns ===
local upstreamZ = -(WorldConfig.RIVER_LENGTH * 0.5) + 120
WorldConfig.PLAYER_SPAWN     = CFrame.new(-100, BASE_SURFACE_Y + 15, upstreamZ)
WorldConfig.BOAT_WATER_SPAWN = CFrame.new(0, WorldConfig.WATER_SURFACE_Y + 2.0, upstreamZ + 20)

-- === River current ===
WorldConfig.CURRENT_ENABLED = true
WorldConfig.CURRENT_DIRECTION = Vector3.new(0, 0, 1)
WorldConfig.CURRENT_STRENGTH = 2000

WorldConfig.CURRENT_REGION = {
    xMin = -WorldConfig.RIVER_WIDTH * 0.5,
    xMax =  WorldConfig.RIVER_WIDTH * 0.5,
    yMin =  RIVER_BOTTOM_Y,
    yMax =  RIVER_TOP_Y + 5,
    zMin = -WorldConfig.RIVER_LENGTH * 0.5,
    zMax =  WorldConfig.RIVER_LENGTH * 0.5,
}

-- === Rocks ===
WorldConfig.ROCK_COUNT        = 16
WorldConfig.ROCK_RADIUS_RANGE = Vector2.new(4, 8)
WorldConfig.ROCK_MIN_SPACING  = 35

-- no-rock zone around the dock / boat spawn
WorldConfig.ROCK_SAFE_RADIUS = 120 

do
    local halfW = WorldConfig.RIVER_WIDTH * 0.5
    local halfL = WorldConfig.RIVER_LENGTH * 0.5
    local marginX = 10
    local marginZ = 80

    WorldConfig.ROCK_REGION = {
        xMin = -halfW + marginX, xMax = halfW - marginX,
        zMin = -halfL + marginZ, zMax = halfL - marginZ,
        y    = WorldConfig.WATER_SURFACE_Y,
    }
end

-- === Course / Finish Line ===
WorldConfig.COURSE_START_Z = WorldConfig.BOAT_WATER_SPAWN.Z
WorldConfig.COURSE_FINISH_Z = WorldConfig.CURRENT_REGION.zMax - 80

-- RL geometry: direction and origin for progress/heading and obstacle sensing
WorldConfig.RIVER_FORWARD = Vector3.new(0, 0, 1)  -- downstream is +Z
WorldConfig.RIVER_ORIGIN  = Vector3.new(
    0,
    WorldConfig.WATER_SURFACE_Y,
    WorldConfig.COURSE_START_Z
)
WorldConfig.RIVER_CENTER_X   = WorldConfig.RIVER_CENTER.Position.X
WorldConfig.RIVER_HALF_WIDTH = WorldConfig.RIVER_WIDTH * 0.5
WorldConfig.OBSTACLE_SENSE_DISTANCE = 200

-- Width of the finish line gate across the river
WorldConfig.FINISH_LINE_WIDTH = WorldConfig.RIVER_WIDTH - 10


-- RL geometry: “downriver” is +Z from start to finish
WorldConfig.RIVER_FORWARD = Vector3.new(0, 0, 1)
WorldConfig.RIVER_ORIGIN  = Vector3.new(0, WorldConfig.WATER_SURFACE_Y, WorldConfig.COURSE_START_Z)
WorldConfig.RIVER_CENTER_X   = WorldConfig.RIVER_CENTER.Position.X
WorldConfig.RIVER_HALF_WIDTH = WorldConfig.RIVER_WIDTH * 0.5
WorldConfig.OBSTACLE_SENSE_DISTANCE = 200

WorldConfig.FINISH_LINE_WIDTH = WorldConfig.RIVER_WIDTH - 10
WorldConfig.FINISH_LINE_DEPTH = 4

-- === River walls / boundaries ===
WorldConfig.RIVER_WALL_HEIGHT       = 20
WorldConfig.RIVER_WALL_THICKNESS    = 4
WorldConfig.RIVER_WALL_EXTRA_LENGTH = 40
WorldConfig.RIVER_WALL_NAME         = "RiverWall"

WorldConfig.RIVER_STAIRS_STEPS = 6
WorldConfig.RIVER_STAIRS_WIDTH = 12
WorldConfig.RIVER_STAIRS_DEPTH = 6

-- === Water visuals ===
WorldConfig.WATER_TRANSPARENCY = 0.4
WorldConfig.WATER_REFLECTANCE  = 0.1
WorldConfig.WATER_WAVE_SIZE    = 0.15
WorldConfig.WATER_WAVE_SPEED   = 8.0
WorldConfig.WATER_COLOR        = Color3.fromRGB(16, 120, 180)

return WorldConfig
