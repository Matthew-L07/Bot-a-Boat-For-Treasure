-- server/gameplay/BotService.lua

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage:WaitForChild("Constants"))
local DockService = require(script.Parent:WaitForChild("DockService"))
local BoatService = require(script.Parent:WaitForChild("BoatService"))

-- AI navigation modules under ServerScriptService.ai.navigation
local AIFolder = ServerScriptService:WaitForChild("ai")
local NavigationFolder = AIFolder:WaitForChild("navigation")

local BotNavigatorModule = require(NavigationFolder:WaitForChild("BotNavigator"))
local Env = require(NavigationFolder:WaitForChild("Env"))
local AgentModule = require(NavigationFolder:WaitForChild("Agent"))
local Config = require(NavigationFolder:WaitForChild("Config"))

local BotService = {}

-- Episode controls
local MAX_STEPS = Config.maxStepsPerEpisode or 400
local EPISODE_DELAY = Config.episodeDelay or 2.0  -- seconds between episodes

----------------------------------------------------------------------
-- Boat discovery helpers
----------------------------------------------------------------------

local function findBoatForPlayer(player)
    if not player then return nil end

    -- Fast path: ask DockService directly
    if DockService.getDockedBoatForPlayer then
        local docked = DockService.getDockedBoatForPlayer(player)
        if docked then
            return docked
        end
    end

    -- Fallback: scan Workspace but require that the boat is docked
    local ownerId = player.UserId
    for _, model in ipairs(Workspace:GetChildren()) do
        if model:IsA("Model") and model:GetAttribute(Constants.BOAT_OWNER_ATTR) == ownerId then
            if DockService.isBoatDocked and DockService.isBoatDocked(model) then
                return model
            end
        end
    end

    return nil
end

local function waitForBoatForPlayer(player, timeoutSeconds)
    local timeout = timeoutSeconds or 5
    local startTime = os.clock()

    while os.clock() - startTime < timeout do
        local boat = findBoatForPlayer(player)
        if boat then
            print(
                "[BotService] Found boat for",
                player.Name,
                "after",
                string.format("%.2f", os.clock() - startTime),
                "seconds"
            )
            return boat
        end
        task.wait(0.2)
    end

    warn("[BotService] Timed out waiting for boat for", player and player.Name)
    return nil
end

----------------------------------------------------------------------
-- Step 1: put the bot (player) onto the boat seat
----------------------------------------------------------------------

local function seatPlayerOnBoat(player, boat)
    if not (player and boat) then
        warn("[BotService] seatPlayerOnBoat: missing player or boat")
        return false
    end

    local character = player.Character
    if not character then
        warn("[BotService] seatPlayerOnBoat: no character for", player.Name)
        return false
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        warn("[BotService] seatPlayerOnBoat: no Humanoid for", player.Name)
        return false
    end

    local seat = boat:FindFirstChild("Helm")
    if not (seat and seat:IsA("VehicleSeat")) then
        warn("[BotService] seatPlayerOnBoat: no Helm seat on boat for", player.Name)
        return false
    end

    if seat.Occupant == humanoid then
        print("[BotService] Player already seated on helm:", player.Name)
        return true
    end

    print("[BotService] Moving player onto boat seat for", player.Name)
    character:PivotTo(seat.CFrame * CFrame.new(0, 5, 0))
    task.wait(0.05)
    seat:Sit(humanoid)

    print("[BotService] Seat occupant after Sit() for", player.Name, "=>", seat.Occupant)
    return true
end

----------------------------------------------------------------------
-- Step 2: ask DockService to launch the boat (undock)
----------------------------------------------------------------------

local function launchBoatForPlayer(player, boat)
    if not (player and boat) then
        warn("[BotService] launchBoatForPlayer: missing player or boat")
        return false
    end

    if not DockService or not DockService.launchBoat then
        warn("[BotService] DockService.launchBoat not available")
        return false
    end

    if DockService.isBoatDocked and not DockService.isBoatDocked(boat) then
        warn("[BotService] launchBoatForPlayer: boat is not docked for", player.Name)
        return false
    end

    print("[BotService] Requesting DockService.launchBoat for", player.Name)
    DockService.launchBoat(boat, player)
    return true
end

----------------------------------------------------------------------
-- Step 3: RL-based navigation loop using Env + Agent + BotNavigator
----------------------------------------------------------------------

-- Single shared agent for now (you can move to per-player later)
local Agent = AgentModule.new()

-- Track active controllers so we can stop old loops if needed
local activeControllers = {} -- [userId] = controlState

local function startRLControlForBoat(player, boat)
    if not (player and boat) then return end

    local userId = player.UserId

    -- Stop any previous loop for this player
    local existing = activeControllers[userId]
    if existing then
        existing.stop = true
    end

    local navigator = BotNavigatorModule.new(boat)
    if not navigator or not navigator.seat then
        warn("[BotService] Could not create BotNavigator for", player.Name)
        return
    end

    local state = {
        navigator = navigator,
        stop = false,
        lastState = nil,
        lastInfo = nil,
        lastAction = nil,
        stepCount = 0,
    }
    activeControllers[userId] = state

    print("[BotService] Starting RL navigation loop for", player.Name)

    -- Small delay to let DockService fully undock/unanchor
    task.wait(0.5)

    while not state.stop do
        if not boat.Parent then
            print("[BotService] Stopping nav loop for", player.Name, "(boat destroyed/removed)")
            break
        end

        if boat:GetAttribute("Finished") then
            print("[BotService] Stopping nav loop for", player.Name, "(boat finished)")
            break
        end

        -- Get current state from Env
        local currentState, info = Env.getState(boat)
        if not currentState then
            print("[BotService] Nav loop ending: no state for", player.Name)
            break
        end

        state.stepCount += 1

        -- Compute reward for the previous action
        if state.lastState and state.lastAction and state.lastInfo then
            local reward, envDone = Env.getRewardAndDone(state.lastInfo, info, state.stepCount)

            -- Enforce MAX_STEPS as a hard episode cutoff
            local finalDone = envDone
            if not finalDone and state.stepCount >= MAX_STEPS then
                finalDone = true
                print(
                    "[BotService] Episode ended by MAX_STEPS for",
                    player.Name,
                    "steps=",
                    state.stepCount
                )
            end

            Agent:remember(state.lastState, state.lastAction, reward, currentState, finalDone)
            Agent:trainStep()

            if finalDone then
                if envDone then
                    print("[BotService] Episode ended for", player.Name, "reward=", reward)
                end
                Agent:onEpisodeEnd()
                break
            end
        end

        -- Choose next action via Agent (DQN-style epsilon-greedy)
        local actionId = Agent:selectAction(currentState)

        state.lastState = currentState
        state.lastInfo = info
        state.lastAction = actionId

        -- Apply action to the boat
        state.navigator:stepAction(actionId)

        -- Adjust this to control decision frequency
        task.wait(Config.stepInterval or 1.0)
    end

    if activeControllers[userId] == state then
        activeControllers[userId] = nil
    end

    print(
        "[BotService] Navigation loop ended for",
        player.Name,
        "after",
        state.stepCount,
        "steps"
    )
end

----------------------------------------------------------------------
-- Single episode flow
----------------------------------------------------------------------

local function runSingleEpisodeForPlayer(player)
    if not player or not player.Parent then
        return false
    end

    print("[BotService] Starting bot episode for", player.Name)

    -- Hard reset environment for this player
    if DockService.clearBoatsForPlayer then
        DockService.clearBoatsForPlayer(player)
    end
    if DockService.ensureDock then
        DockService.ensureDock()
    end
    if BoatService.spawnDockedBoatForPlayer then
        BoatService.spawnDockedBoatForPlayer(player)
    end

    -- 1) Wait for / find boat
    local boat = waitForBoatForPlayer(player, 8)
    if not boat then
        warn("[BotService] Aborting episode – no boat for", player.Name)
        return false
    end

    -- 2) Seat player
    print("[BotService] Bot episode: seating player on boat", boat.Name)
    local seated = seatPlayerOnBoat(player, boat)
    if not seated then
        warn("[BotService] Aborting episode – could not seat player", player.Name)
        return false
    end

    -- 3) Small delay to ensure dock is ready
    task.wait(1.0)

    -- 4) Launch boat
    print("[BotService] Bot episode: attempting to launch boat for", player.Name)
    local launched = launchBoatForPlayer(player, boat)
    if not launched then
        warn("[BotService] Launch failed; not starting navigation for", player.Name)
        return false
    end

    -- 5) RL control loop (blocks until episode ends)
    startRLControlForBoat(player, boat)

    print("[BotService] Episode finished for", player.Name)
    return true
end

----------------------------------------------------------------------
-- Looping episodes per player
----------------------------------------------------------------------

local episodeLoops = {} -- [userId] = true while loop is running

local function runEpisodesLoopForPlayer(player)
    local userId = player.UserId
    local episodeIndex = 0

    while player.Parent do
        episodeIndex += 1
        print("[BotService] === Starting episode #"
            .. episodeIndex
            .. " for "
            .. player.Name
            .. " ===")

        local ok = runSingleEpisodeForPlayer(player)
        if not ok then
            warn("[BotService] Episode aborted for", player.Name, "- stopping loop")
            break
        end

        -- Small pause between episodes so the world can reset / dock boats, etc.
        task.wait(EPISODE_DELAY)
    end

    episodeLoops[userId] = nil
    print("[BotService] Episode loop ended for", player.Name)
end

----------------------------------------------------------------------
-- Player hooks
----------------------------------------------------------------------

local function onCharacterAdded(player, _character)
    print("[BotService] CharacterAdded for", player.Name)

    local userId = player.UserId
    if episodeLoops[userId] then
        print("[BotService] Episode loop already running for", player.Name)
        return
    end

    episodeLoops[userId] = true

    -- Run the episodes loop in the background so we don't block CharacterAdded
    task.spawn(function()
        -- short delay so character finishes spawning
        task.wait(1.0)
        runEpisodesLoopForPlayer(player)
    end)
end

local function setupPlayer(player)
    print("[BotService] Setting up bot for player", player.Name)

    player.CharacterAdded:Connect(function(character)
        onCharacterAdded(player, character)
    end)

    if player.Character then
        onCharacterAdded(player, player.Character)
    end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function BotService.start()
    print("[BotService] Starting...")

    print("[BotService] DockService has launchBoat:", DockService and DockService.launchBoat)

    Players.PlayerAdded:Connect(function(player)
        setupPlayer(player)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        setupPlayer(player)
    end

    print("[BotService] Started successfully")
end

return BotService
