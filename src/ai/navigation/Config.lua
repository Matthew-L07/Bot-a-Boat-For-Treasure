-- ai/navigation/Config.lua
-- Enhanced configuration with improved safety and training settings

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

-- 11-dim state:
--   progress, lateral, headingDot,
--   forwardSpeed, lateralSpeed, velocityMag,
--   distFarLeft, distLeft, distCenter, distRight, distFarRight
Config.stateDim = 11

----------------------------------------------------------------------
-- Episode Control
----------------------------------------------------------------------

Config.maxStepsPerEpisode = 800
Config.episodeDelay = 2.0
Config.stepInterval = 0.1
Config.useActionPersistence = true

----------------------------------------------------------------------
-- Action Persistence Settings
----------------------------------------------------------------------

Config.minActionHoldSteps = 2
Config.maxActionHoldSteps = 5

----------------------------------------------------------------------
-- Vision / sensing
----------------------------------------------------------------------

-- How far ahead rays look (studs) for RL. Obstacles beyond this are treated as "far" (distance = 1.0)
Config.visionMaxDistance = 120    -- must be <= WorldConfig.OBSTACLE_SENSE_DISTANCE

----------------------------------------------------------------------
-- Reward Function Parameters
----------------------------------------------------------------------

-- Core rewards
Config.progressRewardScale = 5.0
Config.stepPenalty         = -0.001
Config.finishReward        = 500.0
Config.crashPenalty        = -30.0

-- Checkpoints (normalized progress in [0,1])
Config.checkpointStep      = 0.1    -- every 10% of course
Config.checkpointReward    = 10.0   -- bonus per checkpoint crossed

-- Velocity-based rewards
Config.velocityRewardScale = 0.3
Config.targetForwardSpeed  = 0.2
Config.lateralPenaltyScale = 0.15   -- sideways sliding penalty

-- Alignment rewards
Config.alignmentRewardScale = 0.1

-- Centerline shaping (distance from river center)
Config.centerPenaltyScale   = 0.1   -- Reduced from 0.2 to allow more exploration

-- Obstacle proximity shaping (walls/rocks via rays)
Config.obstacleProxPenaltyScale = 0.15  -- Increased from 0.1 (stronger avoidance signal)
Config.obstacleProxThreshold    = 0.5   -- Increased from 0.4 (earlier warning)

----------------------------------------------------------------------
-- Exploration Parameters (IMPROVED: episode-based decay)
----------------------------------------------------------------------

Config.epsilonStart      = 0.6
Config.epsilonEnd        = 0.05
Config.epsilonDecaySteps = 30000  -- DEPRECATED: now using episode-based decay in Agent.lua

----------------------------------------------------------------------
-- Curriculum Learning
----------------------------------------------------------------------

Config.lowPriorityActionThreshold = 50

----------------------------------------------------------------------
-- Training Parameters
----------------------------------------------------------------------

Config.trainingEnabled   = true
Config.gamma             = 0.95  -- Reduced from 0.99 for tactical navigation
Config.batchSize         = 32
Config.minReplaySize     = 1000
Config.replayBufferSize  = 50000

----------------------------------------------------------------------
-- Debug / logging toggles
----------------------------------------------------------------------

-- Visualize raycasts with neon parts
Config.debugRays = true -- Set to true only when debugging specific episodes

-- Per-step textual debug:
Config.debugSteps          = false  -- log full state each step
Config.debugRewards        = false  -- log reward each step
Config.debugActions        = false  -- log every new BotNavigator action
Config.debugRewardSummary  = false  -- Env.lua reward summary print every N steps
Config.debugTransitionHttp = false  -- verbose HTTP logging in Agent:onEpisodeEnd

-- Turn this ON when you want to collect data for train_dqn.py.
-- IMPORTANT: Make sure Flask server (log_data.py) is running first!
Config.enableTransitionLogging = false

return Config