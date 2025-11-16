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
    local minSpacing = WorldConfig.ROCK_MIN_SPACING or 30

    local function rand(a,b) return a + math.random()*(b-a) end
    local placed = {}

    local function isFarEnough(x, z)
        for _,pt in ipairs(placed) do
            local dx = x - pt.x
            local dz = z - pt.z
            if (dx*dx + dz*dz) < (minSpacing * minSpacing) then
                return false
            end
        end
        return true
    end

    for _ = 1, WorldConfig.ROCK_COUNT do
        local tries = 0
        local ok, x, z = false, nil, nil
        while tries < 40 do
            tries += 1
            local candX = rand(cfg.xMin, cfg.xMax)
            local candZ = rand(cfg.zMin, cfg.zMax)
            if isFarEnough(candX, candZ) then
                ok, x, z = true, candX, candZ
                break
            end
        end
        if ok then
            local r = rand(minR, maxR)
            local p = Instance.new("Part")
            p.Shape = Enum.PartType.Ball
            p.Material = Enum.Material.Rock
            p.Color = Color3.fromRGB(110,108,104)
            p.Size = Vector3.new(r*2, r*2, r*2)
            p.Anchored = true
            p.CanCollide = true
            p.Name = "Rock"
            -- Sink slightly so it looks embedded
            local y = cfg.y - r * 0.4
            p.CFrame = CFrame.new(x, y, z)
            p.Parent = folder
            table.insert(placed, {x = x, z = z})
        end
    end
end

local function createFinishLine()
    -- Clean up old finish line if it exists
    local old = Workspace:FindFirstChild("FinishLine")
    if old then old:Destroy() end

    local model = Instance.new("Model")
    model.Name = "FinishLine"
    model.Parent = Workspace

    local finishZ = WorldConfig.COURSE_FINISH_Z
    local width = WorldConfig.FINISH_LINE_WIDTH
    local depth = WorldConfig.FINISH_LINE_DEPTH
    local y = WorldConfig.WATER_SURFACE_Y + 8 -- a bit above water

    -- Visual gate: a big checkered plank across the river
    local gate = Instance.new("Part")
    gate.Name = "Gate"
    gate.Size = Vector3.new(width, 12, depth)
    gate.Anchored = true
    gate.CanCollide = false
    gate.Material = Enum.Material.SmoothPlastic
    gate.Color = Color3.fromRGB(255, 255, 255)
    gate.CFrame = CFrame.new(0, y, finishZ)
    gate.Parent = model

    -- Black / white checkered texture (swap TextureId with any you like)
    local texture = Instance.new("Texture")
    texture.Name = "CheckeredTexture"
    texture.Texture = "rbxassetid://130229010" -- placeholder ID
    texture.Face = Enum.NormalId.Front
    texture.StudsPerTileU = 4
    texture.StudsPerTileV = 4
    texture.Parent = gate

    local texture2 = texture:Clone()
    texture2.Face = Enum.NormalId.Back
    texture2.Parent = gate

    -- Invisible trigger volume slightly upstream of the gate
    local trigger = Instance.new("Part")
    trigger.Name = "FinishTrigger"
    trigger.Size = Vector3.new(width, 20, depth * 2)
    trigger.Anchored = true
    trigger.CanCollide = false
    trigger.CanTouch = true
    trigger.Transparency = 1
    trigger.CFrame = CFrame.new(0, WorldConfig.WATER_SURFACE_Y + 5, finishZ - 5)
    trigger.Parent = model

    print("[TerrainGen] Created finish line at Z =", finishZ)
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

-- Visual marker for the exact boat spawn position
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

-- NEW: Show current direction with flowing particles
local function createCurrentParticles()
    if not WorldConfig.CURRENT_ENABLED then return end
    
    local folder = Workspace:FindFirstChild("CurrentParticles") or Instance.new("Folder")
    folder.Name = "CurrentParticles"
    folder.Parent = Workspace
    for _,c in ipairs(folder:GetChildren()) do c:Destroy() end
    
    local direction = WorldConfig.CURRENT_DIRECTION.Unit
    local riverLength = WorldConfig.RIVER_LENGTH
    local riverWidth = WorldConfig.RIVER_WIDTH
    local spacing = 80  -- Place particle emitters every 80 studs
    
    -- Create a grid of particle emitters across the river
    for z = -riverLength/2 + 100, riverLength/2 - 100, spacing do
        for x = -riverWidth/2 + 20, riverWidth/2 - 20, 40 do
            -- Invisible part to hold particles
            local emitter = Instance.new("Part")
            emitter.Name = "CurrentEmitter"
            emitter.Size = Vector3.new(1, 1, 1)
            emitter.Anchored = true
            emitter.CanCollide = false
            emitter.Transparency = 1
            emitter.Position = Vector3.new(x, WorldConfig.WATER_SURFACE_Y + 0.2, z)
            emitter.Parent = folder
            
            -- Calculate angle for emission direction
            local angle = math.atan2(direction.Z, direction.X)
            emitter.CFrame = CFrame.new(emitter.Position) * CFrame.Angles(0, angle, 0)
            
            -- Flowing water droplet particles
            local waterFlow = Instance.new("ParticleEmitter")
            waterFlow.Name = "WaterFlow"
            waterFlow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
            waterFlow.Color = ColorSequence.new(Color3.fromRGB(150, 200, 255))
            waterFlow.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.4),
                NumberSequenceKeypoint.new(0.5, 0.2),
                NumberSequenceKeypoint.new(1, 0.9)
            })
            waterFlow.Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.4),
                NumberSequenceKeypoint.new(0.5, 0.6),
                NumberSequenceKeypoint.new(1, 0.3)
            })
            waterFlow.Lifetime = NumberRange.new(3, 5)
            waterFlow.Rate = 12
            waterFlow.Speed = NumberRange.new(8, 12)
            waterFlow.SpreadAngle = Vector2.new(10, 5)
            waterFlow.EmissionDirection = Enum.NormalId.Front
            waterFlow.Rotation = NumberRange.new(0, 360)
            waterFlow.RotSpeed = NumberRange.new(-40, 40)
            waterFlow.Acceleration = direction * 3 + Vector3.new(0, -0.5, 0)
            waterFlow.LightEmission = 0.3
            waterFlow.Parent = emitter

        end
    end
    
    print("[TerrainGen] Created current particles - direction:", direction)
end

function M.build()
    print("[TerrainGen] building world…")
    clearAllTerrain()
    buildBase()
    buildRiver()
    scatterRocks()
    createFinishLine()
    placeSpawn()
    dropSpawnMarker(WorldConfig.BOAT_WATER_SPAWN)
    createCurrentParticles()
    print("[TerrainGen] World build complete")
end

return M