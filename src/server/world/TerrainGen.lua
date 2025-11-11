local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldConfig = require(ReplicatedStorage.world.WorldConfig)
local Constants = require(ReplicatedStorage:WaitForChild("Constants"))

local M = {}

local function clearAllTerrain() Terrain:Clear() end

local function buildBase()
    Terrain:FillBlock(WorldConfig.BASE_CENTER, WorldConfig.BASE_SIZE, Enum.Material.Grass)
end

local function buildRiver()
    local pad = Vector3.new(2, 2, 2)
    Terrain:FillBlock(WorldConfig.RIVER_CENTER, WorldConfig.RIVER_SIZE + pad, Enum.Material.Air)
    Terrain:FillBlock(WorldConfig.RIVER_CENTER, WorldConfig.RIVER_SIZE, Enum.Material.Water)

    Terrain.WaterTransparency = WorldConfig.WATER_TRANSPARENCY
    Terrain.WaterReflectance  = WorldConfig.WATER_REFLECTANCE
    Terrain.WaterWaveSize     = WorldConfig.WATER_WAVE_SIZE
    Terrain.WaterWaveSpeed    = WorldConfig.WATER_WAVE_SPEED
    Terrain.WaterColor        = WorldConfig.WATER_COLOR
end

local function scatterRocks()
    local folder = Workspace:FindFirstChild("Rocks") or Instance.new("Folder")
    folder.Name = "Rocks"; folder.Parent = Workspace
    for _,c in ipairs(folder:GetChildren()) do c:Destroy() end

    local cfg = WorldConfig.ROCK_REGION
    local minR, maxR = WorldConfig.ROCK_RADIUS_RANGE.X, WorldConfig.ROCK_RADIUS_RANGE.Y
    local function rand(a,b) return a + math.random()*(b-a) end

    for _ = 1, WorldConfig.ROCK_COUNT do
        local r = rand(minR, maxR)
        local p = Instance.new("Part")
        p.Shape = Enum.PartType.Ball
        p.Material = Enum.Material.Rock
        p.Color = Color3.fromRGB(110,108,104)
        p.Size = Vector3.new(r*2, r*2, r*2)
        p.Anchored = true
        p.CanCollide = true
        p.Name = "Rock"
        local x = rand(cfg.xMin, cfg.xMax)
        local z = rand(cfg.zMin, cfg.zMax)
        local y = cfg.y - r * 0.4 -- slightly embedded
        p.CFrame = CFrame.new(x, y, z)
        p.Parent = folder
    end
end

local function placeSpawn()
    local spawn = Workspace:FindFirstChild("LandSpawn") or Instance.new("SpawnLocation")
    spawn.Name = "LandSpawn"
    spawn.Size = Vector3.new(6,1,6)
    spawn.Anchored = true; spawn.CanCollide = true; spawn.Enabled = true
    spawn.Transparency = 0.5; spawn.Material = Enum.Material.Grass
    spawn.CFrame = Constants.PLAYER_SPAWN
    spawn.Parent = Workspace
end

-- NEW: visual marker for the exact boat spawn position
local function dropSpawnMarker(cf)
    local p = Instance.new("Part")
    p.Name = "BoatSpawnMarker"
    p.Size = Vector3.new(3,3,3)
    p.Material = Enum.Material.Neon
    p.Color = Color3.fromRGB(255,0,0)
    p.Anchored = true
    p.CanCollide = false
    p.CFrame = cf
    p.Parent = Workspace
end

function M.build()
    print("[TerrainGen] building world…")
    clearAllTerrain()
    buildBase()
    buildRiver()
    scatterRocks()
    placeSpawn()
    dropSpawnMarker(WorldConfig.BOAT_WATER_SPAWN)
end

return M
