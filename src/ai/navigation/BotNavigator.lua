-- ai/navigation/BotNavigator.lua
-- Simple action-space controller for a boat's helm seat.
-- Actions are server-side and compatible with BoatService's physics loop.

local BotNavigator = {}
BotNavigator.__index = BotNavigator

-- Discrete action space:
--  1: IDLE
--  2: FORWARD
--  3: REVERSE
--  4: TURN_LEFT  (forward + left turn)
--  5: TURN_RIGHT (forward + right turn)
local ACTIONS = {
    {
        id = 1,
        name = "IDLE",
        throttle = 0.0,
        steer = 0.0,
    },
    {
        id = 2,
        name = "FORWARD",
        throttle = 1.0,
        steer = 0.0,
    },
    {
        id = 3,
        name = "REVERSE",
        throttle = -1.0,
        steer = 0.0,
    },
    {
        id = 4,
        name = "TURN_LEFT",
        throttle = 0.6,
        steer = -1.0,
    },
    {
        id = 5,
        name = "TURN_RIGHT",
        throttle = 0.6,
        steer = 1.0,
    },
}

-- Create a navigator for a specific boat model (must have Helm seat)
function BotNavigator.new(boat)
    local self = setmetatable({}, BotNavigator)

    self.boat = boat
    self.seat = nil

    if boat and boat:IsA("Model") then
        local seat = boat:FindFirstChild("Helm")
        if seat and seat:IsA("VehicleSeat") then
            self.seat = seat
        end
    end

    return self
end

function BotNavigator:getRandomAction()
    local idx = math.random(1, #ACTIONS)
    return ACTIONS[idx]
end

function BotNavigator:getActionById(id)
    return ACTIONS[id]
end

function BotNavigator:getNumActions()
    return #ACTIONS
end

-- Apply an action to the helm seat (sets throttle + steer)
function BotNavigator:applyAction(action)
    if not action then
        warn("[BotNavigator] applyAction called with nil action")
        return
    end

    if not (self.seat and self.seat:IsA("VehicleSeat")) then
        warn("[BotNavigator] No valid Helm VehicleSeat for this boat")
        return
    end

    self.seat.ThrottleFloat = action.throttle
    self.seat.SteerFloat = action.steer

    print(string.format(
        "[BotNavigator] Action %s (id=%d): throttle=%.2f steer=%.2f",
        action.name,
        action.id,
        action.throttle,
        action.steer
    ))
end

-- Convenience: pick a random action and apply it
function BotNavigator:stepRandom()
    local action = self:getRandomAction()
    self:applyAction(action)
end

-- Convenience: apply a specific action ID (for RL agent control)
function BotNavigator:stepAction(actionId)
    local action = ACTIONS[actionId]
    if not action then
        warn("[BotNavigator] Invalid actionId", actionId)
        return
    end
    self:applyAction(action)
end

return {
    ACTIONS = ACTIONS,
    new = BotNavigator.new,
}
