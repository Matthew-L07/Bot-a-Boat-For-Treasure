-- ai/navigation/BotNavigator.lua
-- Action-space controller with REDUCED action persistence for smoother movement

local Config = require(script.Parent:WaitForChild("Config"))

local BotNavigator = {}
BotNavigator.__index = BotNavigator

-- Discrete action space optimized for forward navigation:
--  1: FORWARD         - straight ahead (most common)
--  2: FORWARD_LEFT    - forward while turning left
--  3: FORWARD_RIGHT   - forward while turning right
--  4: SHARP_LEFT      - aggressive left turn with moderate speed
--  5: SHARP_RIGHT     - aggressive right turn with moderate speed

local ACTIONS = {
    {
        id = 1,
        name = "FORWARD",
        throttle = 1.0,
        steer = 0.0,
    },
    {
        id = 2,
        name = "FORWARD_LEFT",
        throttle = 1.0,
        steer = -0.5,     -- slightly softer turn
    },
    {
        id = 3,
        name = "FORWARD_RIGHT",
        throttle = 1.0,
        steer = 0.5,
    },
    {
        id = 4,
        name = "SHARP_LEFT",
        throttle = 0.9,
        steer = -1.0,
    },
    {
        id = 5,
        name = "SHARP_RIGHT",
        throttle = 0.9,
        steer = 1.0,
    },
}

-- Action masking: returns list of valid action IDs
function BotNavigator.getValidActions(enableLowPriority)
    local valid = {}
    for _, action in ipairs(ACTIONS) do
        table.insert(valid, action.id)
    end
    return valid
end

-- Create a navigator for a specific boat model
function BotNavigator.new(boat)
    local self = setmetatable({}, BotNavigator)

    self.boat = boat
    self.seat = nil
    
    -- Action persistence: hold actions for multiple steps
    self.currentAction = nil
    self.actionHoldSteps = 0
    self.actionHoldTarget = 0

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

-- Apply an action to the helm seat
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
end

-- IMPROVED: Reduced hold times for smoother, more responsive movement
function BotNavigator:stepActionWithPersistence(actionId, defaultMinHold, defaultMaxHold)
    local action = ACTIONS[actionId]
    if not action then
        return
    end

    -- If we're already holding this action and haven't reached the target, just reapply it
    if self.currentAction == action and self.actionHoldSteps < self.actionHoldTarget then
        self.actionHoldSteps += 1
        self:applyAction(action)
        return
    end

    -- Either new action or previous hold finished
    self.currentAction = action

    local id = action.id
    local minHold, maxHold

    if id == 1 then
        -- FORWARD: Medium-long holds for smooth straight motion
        -- REDUCED from (4, 8) to avoid overly committed straight paths
        minHold, maxHold = 3, 5
    elseif id == 2 or id == 3 then
        -- FORWARD_LEFT / FORWARD_RIGHT: Short holds for responsive turning
        -- REDUCED from (3, 5) to allow quicker corrections
        minHold, maxHold = 2, 3
    elseif id == 4 or id == 5 then
        -- SHARP_LEFT / SHARP_RIGHT: Very short taps
        -- Keep at (1, 2) - already good
        minHold, maxHold = 1, 2
    else
        -- Fallback to defaults if we ever add more actions
        minHold = defaultMinHold or 2
        maxHold = defaultMaxHold or 3
    end

    self.actionHoldTarget = math.random(minHold, maxHold)
    self.actionHoldSteps = 1

    self:applyAction(action)

    if Config.debugActions then
        print(string.format(
            "[BotNavigator] New action %s (id=%d): throttle=%.2f steer=%.2f, holding for %d steps",
            action.name,
            action.id,
            action.throttle,
            action.steer,
            self.actionHoldTarget
        ))
    end
end

-- Standard step for RL agent (with optional persistence)
function BotNavigator:stepAction(actionId, usePersistence)
    if usePersistence then
        return self:stepActionWithPersistence(actionId)
    else
        local action = ACTIONS[actionId]
        if not action then
            warn("[BotNavigator] Invalid actionId", actionId)
            return
        end
        self:applyAction(action)

        if Config.debugActions then
            print(string.format(
                "[BotNavigator] One-step action %s (id=%d): throttle=%.2f steer=%.2f",
                action.name,
                action.id,
                action.throttle,
                action.steer
            ))
        end
    end
end

-- Get action priority level (still useful for debugging)
function BotNavigator:getActionPriority(actionId)
    local action = ACTIONS[actionId]
    return action and action.priority or "low"
end

return {
    ACTIONS = ACTIONS,
    new = BotNavigator.new,
    getValidActions = BotNavigator.getValidActions,
}