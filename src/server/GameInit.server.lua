print("[GameInit] start")

-- Build the world terrain
local TerrainGen = require(script.Parent.world:WaitForChild("TerrainGen"))
TerrainGen.build()

-- Start the dock system FIRST
local DockService = require(script.Parent:WaitForChild("gameplay"):WaitForChild("DockService"))
DockService.start()

-- Start the boat system and connect it to dock service
local BoatService = require(script.Parent:WaitForChild("gameplay"):WaitForChild("BoatService"))
BoatService.setDockService(DockService)
BoatService.start()

-- Start the river current system
-- local CurrentService = require(script.Parent:WaitForChild("gameplay"):WaitForChild("CurrentService"))
-- CurrentService.start()

-- Start the boat destruction system
local BoatDestructionService = require(script.Parent:WaitForChild("gameplay"):WaitForChild("BoatDestructionService"))
BoatDestructionService.start()

-- Start the player health system
local PlayerHealthService = require(script.Parent:WaitForChild("gameplay"):WaitForChild("PlayerHealthService"))
PlayerHealthService.start()

-- Start the finish-line service (detects win & shows celebration)
local FinishService = require(script.Parent:WaitForChild("gameplay"):WaitForChild("FinishService"))
FinishService.start()


local BotService = require(script.Parent.gameplay.BotService)
BotService.start()

print("[GameInit] ok")