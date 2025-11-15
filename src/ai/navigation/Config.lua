-- ai/navigation/Config.lua
-- Central config for the navigation RL setup.

local Config = {}

-- DQN-style hyperparameters
Config.gamma = 0.99

-- These learning parameters are for when you implement real DQN training
Config.learningRate = 1e-3
Config.batchSize = 64
Config.replayBufferSize = 50000
Config.minReplaySize = 1000        -- don't start training until buffer has this many samples
Config.targetUpdateFreq = 2000     -- steps between target net syncs

-- Epsilon-greedy exploration
Config.epsilonStart = 1.0
Config.epsilonEnd = 0.05
Config.epsilonDecaySteps = 50000   -- how many steps to anneal epsilon over

-- Episode / environment
Config.maxEpisodeSteps = 500

-- State + action space (keep in sync with Env.lua and BotNavigator.lua)
Config.stateDim = 8   -- zProgress, xOffset, headingErr, speed, yaw, distF, distL, distR
Config.numActions = 5 -- IDLE, FORWARD, REVERSE, TURN_LEFT, TURN_RIGHT

-- Toggle whether to actually train online in Roblox or just collect experience
Config.trainingEnabled = false     -- start as false; turn on only in a dedicated training session

return Config
