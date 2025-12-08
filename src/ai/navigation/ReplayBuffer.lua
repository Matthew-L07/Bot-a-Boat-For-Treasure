-- ai/navigation/ReplayBuffer.lua

local ReplayBuffer = {}
ReplayBuffer.__index = ReplayBuffer

function ReplayBuffer.new(maxSize)
    local self = setmetatable({}, ReplayBuffer)
    self.maxSize = maxSize or 10000
    self.buffer = {}
    self.nextIdx = 1
    self.sizeVal = 0
    return self
end

function ReplayBuffer:size()
    return self.sizeVal
end

function ReplayBuffer:add(state, action, reward, nextState, done)
    -- each state and nextState are Lua arrays (tables) of numbers
    self.buffer[self.nextIdx] = {
        s = state,
        a = action,
        r = reward,
        ns = nextState,
        d = done,
    }

    self.nextIdx += 1
    if self.nextIdx > self.maxSize then
        self.nextIdx = 1
    end

    if self.sizeVal < self.maxSize then
        self.sizeVal += 1
    end
end

-- Sample a mini-batch (returns a table of transitions)
function ReplayBuffer:sample(batchSize)
    local n = math.min(batchSize, self.sizeVal)
    local result = table.create(n)

    for i = 1, n do
        local idx = math.random(1, self.sizeVal)
        result[i] = self.buffer[idx]
    end

    return result
end

return ReplayBuffer