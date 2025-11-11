print("[GameInit] start")
local TerrainGen = require(script.Parent.world:WaitForChild("TerrainGen"))
TerrainGen.build()

local BoatService = require(script.Parent:WaitForChild("gameplay"):WaitForChild("BoatService"))
BoatService.start()
print("[GameInit] ok")
