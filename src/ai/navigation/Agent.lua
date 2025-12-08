-- ai/navigation/Agent.lua
-- Improved rock avoidance with more aggressive safety thresholds

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

    self.enableLowPriorityActions = false
    self.lowPriorityThreshold = Config.lowPriorityActionThreshold or 50

    return self
end

local function relu(x)
    if x > 0 then
        return x
    else
        return 0
    end
end

----------------------------------------------------------------------
-- Q-network forward pass
----------------------------------------------------------------------

function Agent:qValues(state)
    local x = state

    local expectedDim = Weights.state_dim or #x
    if #x ~= expectedDim then
        error(string.format(
            "CRITICAL: State dimension mismatch (got %d, expected %d)! Re-export DqnWeights.",
            #x,
            expectedDim
        ))
    end

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
-- IMPROVED heuristic policy with better rock avoidance
----------------------------------------------------------------------

function Agent:getHeuristicAction(state)
    local lateral      = state[2]
    local headingDot   = state[3]

    local distFarLeft  = state[7]
    local distLeft     = state[8]
    local distCenter   = state[9]
    local distRight    = state[10]
    local distFarRight = state[11]

    local leftProx   = math.min(distFarLeft, distLeft)
    local rightProx  = math.min(distFarRight, distRight)
    local aheadProx  = math.min(distLeft, distCenter, distRight)

    -- CRITICAL: More aggressive thresholds for rocks
    -- Normalized distances: 0 = touching, 1 = 120 studs away
    -- So 0.4 = 48 studs, 0.5 = 60 studs
    local wallThreshold    = 0.35  -- Side obstacles
    local distAheadDanger  = 0.25  -- Emergency (30 studs)
    local distAheadCaution = 0.50  -- Caution zone (60 studs)

    -- 1) Side wall avoidance
    if leftProx < wallThreshold and rightProx > leftProx + 0.1 then
        return 3  -- FORWARD_RIGHT
    elseif rightProx < wallThreshold and leftProx > rightProx + 0.1 then
        return 2  -- FORWARD_LEFT
    end

    -- 2) Emergency: obstacle very close ahead -> SHARP turn
    if aheadProx < distAheadDanger then
        if leftProx > rightProx + 0.05 then
            return 4  -- SHARP_LEFT
        else
            return 5  -- SHARP_RIGHT
        end
    end

    -- 3) Caution: obstacle ahead -> gentle turn
    if aheadProx < distAheadCaution then
        if leftProx > rightProx + 0.05 then
            return 2  -- FORWARD_LEFT
        else
            return 3  -- FORWARD_RIGHT
        end
    end

    -- 4) Misalignment correction
    if headingDot < 0.3 then
        if lateral < 0 then
            return 3
        else
            return 2
        end
    end

    -- 5) Centering
    if lateral < -0.25 then
        return 3
    elseif lateral > 0.25 then
        return 2
    end

    -- 6) Default: straight
    return 1
end

----------------------------------------------------------------------
-- Action selection with improved safety
----------------------------------------------------------------------

function Agent:selectAction(state)
    self.totalSteps += 1

    if not self.enableLowPriorityActions and self.episodeCount >= self.lowPriorityThreshold then
        self.enableLowPriorityActions = true
        print("[Agent] Curriculum: enabling full action set")
    end

    local validActions = BotNavigatorModule.getValidActions(self.enableLowPriorityActions)

    local distFarLeft  = state[7]
    local distLeft     = state[8]
    local distCenter   = state[9]
    local distRight    = state[10]
    local distFarRight = state[11]

    local leftProx  = math.min(distFarLeft, distLeft)
    local rightProx = math.min(distFarRight, distRight)
    local aheadProx = math.min(distLeft, distCenter, distRight)

    ------------------------------------------------------------------
    -- 1) AGGRESSIVE emergency override for rocks
    ------------------------------------------------------------------
    local wallDanger  = 0.40  -- Increased from 0.30
    local aheadDanger = 0.45  -- Increased significantly from 0.30

    if leftProx < wallDanger or rightProx < wallDanger or aheadProx < aheadDanger then
        return self:getHeuristicAction(state)
    end

    ------------------------------------------------------------------
    -- 2) Epsilon decay (episode-based)
    ------------------------------------------------------------------
    local frac = math.clamp(self.episodeCount / 200, 0, 1)
    self.epsilon = Config.epsilonStart + (Config.epsilonEnd - Config.epsilonStart) * frac

    ------------------------------------------------------------------
    -- 3) Early episode heuristic injection
    ------------------------------------------------------------------
    if self.episodeCount < 30 and math.random() < 0.4 then
        return self:getHeuristicAction(state)
    end

    ------------------------------------------------------------------
    -- 4) Exploration
    ------------------------------------------------------------------
    if math.random() < self.epsilon then
        local idx = math.random(1, #validActions)
        return validActions[idx]
    end

    ------------------------------------------------------------------
    -- 5) Exploitation
    ------------------------------------------------------------------
    local q = self:qValues(state)

    local bestA = nil
    local bestQ = -math.huge

    for _, actionId in ipairs(validActions) do
        local value = q[actionId] or -math.huge
        if value > bestQ then
            bestQ = value
            bestA = actionId
        end
    end

    if not bestA then
        bestA = validActions[1]
    end

    ------------------------------------------------------------------
    -- 6) Preemptive obstacle avoidance (earlier warning)
    ------------------------------------------------------------------
    local cautionZone = 0.55  -- Increased from 0.40 (react at 66 studs)

    if aheadProx < cautionZone then
        -- Strongly bias toward clearer side
        if leftProx > rightProx + 0.1 then
            -- Left much clearer - avoid right turns
            if bestA == 3 or bestA == 5 then
                bestA = 2
            end
        elseif rightProx > leftProx + 0.1 then
            -- Right much clearer - avoid left turns
            if bestA == 2 or bestA == 4 then
                bestA = 3
            end
        end
    end

    ------------------------------------------------------------------
    -- 7) Stability & centering
    ------------------------------------------------------------------
    local lateral    = state[2]
    local headingDot = state[3]

    -- Prefer straight when centered and aligned
    if headingDot > 0.9 and math.abs(lateral) < 0.3 and aheadProx > 0.6 then
        bestA = 1
    end

    -- Wall guardrail
    if lateral > 0.6 then
        if bestA == 3 or bestA == 5 then
            bestA = 2
        end
    elseif lateral < -0.6 then
        if bestA == 2 or bestA == 4 then
            bestA = 3
        end
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

    local _batch = self.replayBuffer:sample(Config.batchSize)
end

----------------------------------------------------------------------
-- Episode end logging
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

    if not Config.enableTransitionLogging then
        print("[Agent] Transition logging disabled in Config; skipping HTTP POST")
        self.episodeTransitions = {}
        return
    end

    local numTransitions = #self.episodeTransitions
    print(string.format(
        "[Agent] Logging %d transitions for episode %d",
        numTransitions,
        self.episodeCount
    ))

    local payload = {
        episodeId = os.time(),
        episodeNum = self.episodeCount,
        transitions = self.episodeTransitions,
        metadata = {
            totalSteps = self.totalSteps,
            epsilon = self.epsilon,
            enabledLowPriority = self.enableLowPriorityActions,
        },
    }

    local json = HttpService:JSONEncode(payload)

    local ok, res = pcall(function()
        return HttpService:RequestAsync({
            Url = LOG_ENDPOINT,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = json,
        })
    end)

    if not ok then
        warn("[Agent] Failed to POST transitions:", res)
    else
        if Config.debugTransitionHttp then
            print("[Agent] HTTP status:", res.StatusCode, res.StatusMessage)
            if res.Body and #res.Body > 0 then
                print("[Agent] Response body:", res.Body)
            end
        else
            print(string.format(
                "[Agent] Posted transitions for episode %d (status %d)",
                self.episodeCount,
                res.StatusCode or -1
            ))
        end
    end

    self.episodeTransitions = {}
end

return Agent