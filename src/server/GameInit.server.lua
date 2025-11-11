print("[GameInit] start")

-- Build the world terrain
local TerrainGen = require(script.Parent.world:WaitForChild("TerrainGen"))
TerrainGen.build()

-- Start the boat system
local BoatService = require(script.Parent:WaitForChild("gameplay"):WaitForChild("BoatService"))
BoatService.start()

-- Start the river current system
local CurrentService = require(script.Parent:WaitForChild("gameplay"):WaitForChild("CurrentService"))
CurrentService.start()

print("[GameInit] ok")