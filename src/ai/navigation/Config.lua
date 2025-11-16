-- ai/navigation/Config.lua
-- Enhanced configuration with action persistence and improved rewards

local Config = {}

----------------------------------------------------------------------
-- Action Space
----------------------------------------------------------------------

-- 5 discrete actions:
--   1: FORWARD
--   2: FORWARD_LEFT
--   3: FORWARD_RIGHT
--   4: SHARP_LEFT
--   5: SHARP_RIGHT
Config.numActions = 5
Config.stateDim = 9    -- 9-dim state: progress, lateral, heading, velocities, distances

----------------------------------------------------------------------
-- Episode Control
----------------------------------------------------------------------

Config.maxStepsPerEpisode = 500  -- Increased from 400
Config.episodeDelay = 2.0        -- seconds between episodes
Config.stepInterval = 0.1        -- faster decision frequency (was 1.0)
Config.useActionPersistence = true  -- enable action holding

----------------------------------------------------------------------
-- Action Persistence Settings
----------------------------------------------------------------------

Config.minActionHoldSteps = 2
Config.maxActionHoldSteps = 5

----------------------------------------------------------------------
-- Reward Function Parameters
----------------------------------------------------------------------

-- Core rewards
Config.progressRewardScale = 3.0    -- Increased from 1.0
Config.stepPenalty = -0.005         -- Small time penalty
Config.finishReward = 1000.0          -- Increased from 10.0
Config.crashPenalty = -100.0         -- Increased magnitude from -5.0

-- Velocity-based rewards
Config.velocityRewardScale = 0.5
Config.targetForwardSpeed = 0.2
Config.lateralPenaltyScale = 0.3

-- Alignment rewards
Config.alignmentRewardScale = 0.2

----------------------------------------------------------------------
-- Exploration Parameters
----------------------------------------------------------------------

Config.epsilonStart = 0.2
Config.epsilonEnd   = 0.05
Config.epsilonDecaySteps = 10000

----------------------------------------------------------------------
-- Curriculum Learning
----------------------------------------------------------------------

-- Still used as a generic “early vs late episodes” toggle, but
-- no longer tied to IDLE/REVERSE (since those actions are removed).
Config.lowPriorityActionThreshold = 50

----------------------------------------------------------------------
-- Training Parameters
----------------------------------------------------------------------

Config.trainingEnabled = false      -- Training happens offline
Config.gamma = 0.99
Config.batchSize = 32
Config.minReplaySize = 1000
Config.replayBufferSize = 50000


-- Turn this OFF (false) while you're testing behavior.
-- Turn it ON (true) when you want to collect data for train_dqn.py.
Config.enableTransitionLogging = true

return Config
