-- ai/navigation/Agent.lua
-- DQN-style agent shell: epsilon-greedy policy + replay buffer.
-- The actual neural network training should be implemented outside Roblox
-- (e.g., in Python) and the trained Q-network weights loaded back in.

local Config = require(script.Parent:WaitForChild("Config"))
local ReplayBuffer = require(script.Parent:WaitForChild("ReplayBuffer"))

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

    self.replayBuffer = ReplayBuffer.new(Config.replayBufferSize)
    
    self.episodeTransitions = {}  -- cleared at episode reset
    self.allTransitions = {}      -- you can append episodes here if you want a big dataset


    -- Placeholder Q-network weights; in a real setup you'd populate this
    -- with trained parameters loaded from a ModuleScript.
    self.qNetwork = nil

    return self
end

-- ReLU helper
local function relu(x)
    if x > 0 then
        return x
    else
        return 0
    end
end

function Agent:qValues(state)
    -- state: numeric array of length Weights.state_dim
    -- We’ll run it through a 3-layer MLP: Linear->ReLU->Linear->ReLU->Linear

    local x = state

    for layerIdx, layer in ipairs(Weights.layers) do
        local W = layer.W      -- 2D: [out_dim][in_dim]
        local b = layer.b      -- 1D: [out_dim]
        local out_dim = #b
        local in_dim = #x

        local y = table.create(out_dim, 0)

        for j = 1, out_dim do
            local sum = b[j]
            local rowW = W[j]

            -- dot product: W[j] · x
            for i = 1, in_dim do
                sum += rowW[i] * x[i]
            end

            -- ReLU for hidden layers (all but last)
            if layerIdx < #Weights.layers then
                sum = relu(sum)
            end

            y[j] = sum
        end

        x = y
    end

    -- x is now a table of length num_actions: Q(s, a) for each action
    return x
end


function Agent:selectAction(state)
    self.totalSteps += 1

    local frac = math.clamp(self.totalSteps / Config.epsilonDecaySteps, 0, 1)
    self.epsilon = Config.epsilonStart + (Config.epsilonEnd - Config.epsilonStart) * frac

    -- Exploration
    if math.random() < self.epsilon then
        local a = math.random(1, self.numActions)
        return a
    end

    -- Exploitation
    local q = self:qValues(state)

    -- DEBUG: sanity check q-values
    print("[Agent] qValues length:", #q, "values:", table.concat(q, ", "))

    local bestA, bestQ = 1, q[1]
    for i = 2, self.numActions do
        if q[i] > bestQ then
            bestQ = q[i]
            bestA = i
        end
    end

    return bestA
end


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

    -- TODO: Perform a DQN update here (in Lua or offline).
    -- Pseudocode:
    --  1) For each transition in batch:
    --        qNext = max_a' Q_target(nextState, a')
    --        target = reward + gamma * qNext * (1 - done)
    --  2) Compute loss = MSE(Q_online(state, action), target)
    --  3) Backprop through network weights and apply gradient updates.
    --
    -- Practically, you will usually:
    --  * Export this replay buffer off-platform,
    --  * Train in Python with PyTorch / TensorFlow,
    --  * Export the trained weights to a Lua table,
    --  * And implement qValues() above to use those weights.

    -- For now, this function is a no-op to avoid heavy math on the server.
end

local HttpService = game:GetService("HttpService")
local LOG_ENDPOINT = "http://127.0.0.1:5000/transitions"  -- use 127.0.0.1 instead of 'localhost'

function Agent:onEpisodeEnd()
    local payload = {
        episodeId = os.time(),
        transitions = self.episodeTransitions,
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
        print("[Agent] Posted transitions for episode")
    end

    self.episodeTransitions = {}
end





return Agent
