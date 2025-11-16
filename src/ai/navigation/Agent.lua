-- ai/navigation/Agent.lua
-- Enhanced DQN agent with action masking and heuristic guidance

local Config = require(script.Parent:WaitForChild("Config"))
local ReplayBuffer = require(script.Parent:WaitForChild("ReplayBuffer"))
local BotNavigatorModule = require(script.Parent:WaitForChild("BotNavigator"))

local Weights = require(script.Parent:WaitForChild("DqnWeights"))
print("[Agent] Weights loaded: state_dim=", Weights.state_dim,
      "num_actions=", Weights.num_actions,
      "layers=", #Weights.layers)

local Agent = {}
Agent.__index = Agent

function Agent.new()
    local self = setmetatable({}, Agent)

    self.gamma = Config.gamma
    self.numActions = Config.numActions
    self.stateDim = Config.stateDim

    self.epsilon = Config.epsilonStart
    self.totalSteps = 0
    self.episodeCount = 0

    self.replayBuffer = ReplayBuffer.new(Config.replayBufferSize)
    
    self.episodeTransitions = {}
    self.allTransitions = {}

    self.qNetwork = nil
    
    -- Curriculum flag (no longer tied to IDLE/REVERSE)
    self.enableLowPriorityActions = false
    self.lowPriorityThreshold = Config.lowPriorityActionThreshold or 50

    return self
end

-- ReLU activation
local function relu(x)
    if x > 0 then
        return x
    else
        return 0
    end
end

----------------------------------------------------------------------
-- Q-network forward pass (Lua-side inference from saved weights)
----------------------------------------------------------------------

function Agent:qValues(state)
    local x = state

    for layerIdx, layer in ipairs(Weights.layers) do
        local W = layer.W
        local b = layer.b
        local out_dim = #b
        local in_dim = #x

        local y = table.create(out_dim, 0)

        for j = 1, out_dim do
            local sum = b[j]
            local rowW = W[j]

            for i = 1, in_dim do
                sum += rowW[i] * x[i]
            end

            if layerIdx < #Weights.layers then
                sum = relu(sum)
            end

            y[j] = sum
        end

        x = y
    end

    return x
end

----------------------------------------------------------------------
-- Heuristic policy (used for early episodes / emergencies)
----------------------------------------------------------------------

function Agent:getHeuristicAction(state)
    -- State indices:
    -- 1: progress, 2: lateral, 3: headingDot, 4: forwardSpeed, 
    -- 5: lateralSpeed, 6: velocityMag, 7: distCenter, 8: distLeft, 9: distRight
    
    local lateral = state[2]
    local headingDot = state[3]
    local forwardSpeed = state[4]
    local distCenter = state[7]
    local distLeft = state[8]
    local distRight = state[9]

    local wallThreshold      = 0.25  -- very close to a side wall
    local distAheadDanger    = 0.08  -- obstacle extremely close ahead
    local distAheadCaution   = 0.20  -- obstacle somewhat ahead

    -- 1) Hard wall avoidance first: if a side is very close, steer away
    if distLeft < wallThreshold and distRight > distLeft then
        return 3  -- FORWARD_RIGHT (move away from left wall)
    elseif distRight < wallThreshold and distLeft > distRight then
        return 2  -- FORWARD_LEFT (move away from right wall)
    end

    -- 2) Emergency: obstacle extremely close ahead -> SHARP turn
    if distCenter < distAheadDanger then
        if distLeft > distRight then
            return 4  -- SHARP_LEFT (hard escape)
        else
            return 5  -- SHARP_RIGHT
        end
    end

    -- 3) Caution: obstacle somewhat ahead -> mild turn in clearer direction
    if distCenter < distAheadCaution then
        if distLeft > distRight then
            return 2  -- FORWARD_LEFT
        else
            return 3  -- FORWARD_RIGHT
        end
    end

    -- 4) If badly misaligned, prioritize turning while moving forward
    if headingDot < 0.3 then
        if lateral < 0 then
            return 3  -- FORWARD_RIGHT
        else
            return 2  -- FORWARD_LEFT
        end
    end

    -- 5) If too far left or right, steer back to center
    if lateral < -0.5 then
        return 3  -- FORWARD_RIGHT
    elseif lateral > 0.5 then
        return 2  -- FORWARD_LEFT
    end

    -- 6) Default: keep moving straight forward
    return 1  -- FORWARD
end

----------------------------------------------------------------------
-- Action probability mask based on safety and geometry
----------------------------------------------------------------------

function Agent:getActionMask(state, validActions)
    local mask = table.create(self.numActions, 0)
    
    for _, actionId in ipairs(validActions) do
        mask[actionId] = 1.0
    end

    local lateral    = state[2]
    local headingDot = state[3]
    local distCenter = state[7]
    local distLeft   = state[8]
    local distRight  = state[9]

    local wallThreshold = 0.3

    -- Prefer pure FORWARD when we're aligned, near center, and clear ahead
    if headingDot > 0.7 and math.abs(lateral) < 0.5 and distCenter > 0.4 then
        if mask[1] > 0 then
            mask[1] = mask[1] + 2.0
        end
    end

    -- Deprioritize sharp turns when already well aligned
    if headingDot > 0.8 then
        if mask[4] and mask[4] > 0 then
            mask[4] = mask[4] * 0.3   -- SHARP_LEFT
        end
        if mask[5] and mask[5] > 0 then
            mask[5] = mask[5] * 0.3   -- SHARP_RIGHT
        end
    end

    -- If left wall is very close, downweight left turns, boost right turns slightly
    if distLeft < wallThreshold then
        if mask[2] and mask[2] > 0 then
            mask[2] = mask[2] * 0.1   -- FORWARD_LEFT
        end
        if mask[4] and mask[4] > 0 then
            mask[4] = mask[4] * 0.1   -- SHARP_LEFT
        end
        if mask[3] and mask[3] > 0 then
            mask[3] = mask[3] * 1.5   -- FORWARD_RIGHT
        end
        if mask[5] and mask[5] > 0 then
            mask[5] = mask[5] * 1.2   -- SHARP_RIGHT (boosted, but less than mild)
        end
    end

    -- Symmetric for right wall
    if distRight < wallThreshold then
        if mask[3] and mask[3] > 0 then
            mask[3] = mask[3] * 0.1   -- FORWARD_RIGHT
        end
        if mask[5] and mask[5] > 0 then
            mask[5] = mask[5] * 0.1   -- SHARP_RIGHT
        end
        if mask[2] and mask[2] > 0 then
            mask[2] = mask[2] * 1.5   -- FORWARD_LEFT
        end
        if mask[4] and mask[4] > 0 then
            mask[4] = mask[4] * 1.2   -- SHARP_LEFT
        end
    end

    -- If we're relatively safe (not hugging walls, nothing right in front),
    -- strongly downweight sharp turns so the policy prefers mild / straight.
    if distCenter > 0.3 and distLeft > 0.4 and distRight > 0.4 then
        if mask[4] and mask[4] > 0 then
            mask[4] = mask[4] * 0.2   -- SHARP_LEFT
        end
        if mask[5] and mask[5] > 0 then
            mask[5] = mask[5] * 0.2   -- SHARP_RIGHT
        end
    end
    
    return mask
end

----------------------------------------------------------------------
-- Action selection (epsilon-greedy + heuristics + masking)
----------------------------------------------------------------------

function Agent:selectAction(state)
    self.totalSteps += 1

    -- Curriculum toggle (kept, but with 5-action space this is a no-op)
    if not self.enableLowPriorityActions and self.episodeCount >= self.lowPriorityThreshold then
        self.enableLowPriorityActions = true
        print("[Agent] Curriculum: enabling full action set")
    end

    local validActions = BotNavigatorModule.getValidActions(self.enableLowPriorityActions)

    -- Epsilon decay
    local frac = math.clamp(self.totalSteps / Config.epsilonDecaySteps, 0, 1)
    self.epsilon = Config.epsilonStart + (Config.epsilonEnd - Config.epsilonStart) * frac

    -- Occasional heuristic-only picks during very early episodes
    local useHeuristic = false
    if self.episodeCount < 20 and math.random() < 0.3 then
        useHeuristic = true
    end

    if useHeuristic then
        local heuristicAction = self:getHeuristicAction(state)
        return heuristicAction
    end

    local distCenter = state[7]
    local distLeft   = state[8]
    local distRight  = state[9]

    -- NOTE: We intentionally removed the old "always SHARP when distCenter < 0.1"
    -- override so that sharp turns are reserved for true emergencies in the
    -- heuristic, and the learned policy + mask can favor smoother behavior.

    -- Epsilon-greedy with masking
    if math.random() < self.epsilon then
        local mask = self:getActionMask(state, validActions)
        
        local totalWeight = 0
        for _, actionId in ipairs(validActions) do
            totalWeight += mask[actionId]
        end
        
        local rand = math.random() * totalWeight
        local cumulative = 0
        
        for _, actionId in ipairs(validActions) do
            cumulative += mask[actionId]
            if rand <= cumulative then
                return actionId
            end
        end
        
        return validActions[math.random(1, #validActions)]
    end

    -- Exploitation: choose argmax_a Q(s,a) over valid actions
    local q = self:qValues(state)
    
    local bestA, bestQ = validActions[1], q[validActions[1]]
    for i = 2, #validActions do
        local actionId = validActions[i]
        if q[actionId] > bestQ then
            bestQ = q[actionId]
            bestA = actionId
        end
    end

    -- Stability override: if centered, aligned, and clear ahead, prefer straight
    local lateral    = state[2]
    local headingDot = state[3]
    if headingDot > 0.9 and math.abs(lateral) < 0.3 and distCenter > 0.5 then
        bestA = 1  -- FORWARD
    end

    return bestA
end

----------------------------------------------------------------------
-- Experience logging
----------------------------------------------------------------------

function Agent:remember(state, action, reward, nextState, done)
    self.replayBuffer:add(state, action, reward, nextState, done)

    table.insert(self.episodeTransitions, {
        s = state,
        a = action,
        r = reward,
        ns = nextState,
        d = done,
    })
end

function Agent:trainStep()
    if not Config.trainingEnabled then
        return
    end

    if self.replayBuffer:size() < Config.minReplaySize then
        return
    end

    local batch = self.replayBuffer:sample(Config.batchSize)
    -- Online learning placeholder (training happens offline in Python)
end

----------------------------------------------------------------------
-- Episode end: log transitions to local HTTP server
----------------------------------------------------------------------

local HttpService = game:GetService("HttpService")
local LOG_ENDPOINT = "http://127.0.0.1:5000/transitions"

function Agent:onEpisodeEnd()
    self.episodeCount += 1
    
    print(string.format(
        "[Agent] Episode %d complete. Total steps: %d, Epsilon: %.3f",
        self.episodeCount,
        self.totalSteps,
        self.epsilon
    ))

    -- If logging is disabled, just clear transitions and return.
    if not Config.enableTransitionLogging then
        self.episodeTransitions = {}
        return
    end
    
    local payload = {
        episodeId = os.time(),
        episodeNum = self.episodeCount,
        transitions = self.episodeTransitions,
        metadata = {
            totalSteps = self.totalSteps,
            epsilon = self.epsilon,
            enabledLowPriority = self.enableLowPriorityActions,
        }
    }

    local json = HttpService:JSONEncode(payload)

    local ok, err = pcall(function()
        HttpService:PostAsync(
            LOG_ENDPOINT,
            json,
            Enum.HttpContentType.ApplicationJson
        )
    end)

    if not ok then
        warn("[Agent] Failed to POST transitions:", err)
    else
        print("[Agent] Posted transitions for episode", self.episodeCount)
    end

    self.episodeTransitions = {}
end


return Agent
