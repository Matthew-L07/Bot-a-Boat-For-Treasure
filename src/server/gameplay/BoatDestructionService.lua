local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local Constants = require(ReplicatedStorage:WaitForChild("Constants"))

local M = {}

local BREAK_FORCE_THRESHOLD = 50 -- Minimum collision force to break a piece
local FLOAT_TIME = 10 -- How long broken pieces float before sinking
local connections = {}

local function createBreakEffect(position)
    -- Spawn wood splinter particles
    local emitter = Instance.new("Part")
    emitter.Size = Vector3.new(0.1, 0.1, 0.1)
    emitter.Transparency = 1
    emitter.Anchored = true
    emitter.CanCollide = false
    emitter.Position = position
    emitter.Parent = Workspace
    
    local particles = Instance.new("ParticleEmitter")
    particles.Texture = "rbxasset://textures/particles/smoke_main.dds"
    particles.Color = ColorSequence.new(Color3.fromRGB(139, 90, 43))
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 0.1)
    })
    particles.Lifetime = NumberRange.new(0.5, 1.5)
    particles.Rate = 50
    particles.Speed = NumberRange.new(5, 15)
    particles.SpreadAngle = Vector2.new(180, 180)
    particles.Acceleration = Vector3.new(0, -20, 0)
    particles.Parent = emitter
    
    particles.Enabled = true
    task.delay(0.1, function()
        particles.Enabled = false
    end)
    
    Debris:AddItem(emitter, 3)
    
    -- Play sound effect
    local breakSound = Instance.new("Sound")
    breakSound.SoundId = "rbxassetid://3581383408" -- Wood break sound
    breakSound.Volume = 0.5
    breakSound.Parent = emitter
    breakSound:Play()
end

local function ejectPlayer(seat)
    -- Eject any player sitting in the seat
    if seat and seat:IsA("VehicleSeat") then
        local occupant = seat.Occupant
        if occupant then
            local humanoid = occupant
            humanoid.Sit = false
            
            -- Give player upward velocity to "jump" off
            local character = humanoid.Parent
            if character then
                local hrp = character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.AssemblyLinearVelocity = Vector3.new(
                        math.random(-10, 10),
                        20,
                        math.random(-10, 10)
                    )
                end
            end
        end
    end
end

local function getRemainingBlocks(boat)
    local count = 0
    for _, part in ipairs(boat:GetDescendants()) do
        if part:IsA("BasePart") and part:GetAttribute("BoatPiece") and not part:GetAttribute("Broken") then
            count = count + 1
        end
    end
    return count
end

local function findNewCenterBlock(boat)
    -- Find any remaining unbroken block to be the new center
    for _, part in ipairs(boat:GetDescendants()) do
        if part:IsA("BasePart") and part:GetAttribute("BoatPiece") and not part:GetAttribute("Broken") then
            return part
        end
    end
    return nil
end

local function transferPhysicsToNewCenter(boat, oldCenter, newCenter)
    -- Move all physics components from old center to new center
    print("[BoatDestruction] Transferring physics from", oldCenter.Name, "to", newCenter.Name)
    
    -- Create new attachment on new center
    local newAttach = Instance.new("Attachment")
    newAttach.Name = "RootAttachment"
    newAttach.Parent = newCenter
    
    -- Move all constraints to new center
    for _, child in ipairs(oldCenter:GetChildren()) do
        if child:IsA("VectorForce") or child:IsA("AngularVelocity") or child:IsA("AlignOrientation") then
            child.Attachment0 = newAttach
            child.Parent = newCenter
        end
    end
    
    -- Reweld remaining blocks to new center
    for _, part in ipairs(boat:GetDescendants()) do
        if part:IsA("BasePart") and part:GetAttribute("BoatPiece") and not part:GetAttribute("Broken") and part ~= newCenter then
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = newCenter
            weld.Part1 = part
            weld.Name = "BlockWeld_" .. part.Name
            weld.Parent = newCenter
        end
    end
    
    -- Update PrimaryPart
    boat.PrimaryPart = newCenter
end

local function breakPieceOff(boat, piece)
    if not piece:GetAttribute("BoatPiece") then return end
    if piece:GetAttribute("Broken") then return end -- Already broken
    
    print("[BoatDestruction] Breaking piece:", piece.Name, "from boat")
    
    piece:SetAttribute("Broken", true)
    
    -- Check if this is the center block
    local isCenterBlock = (piece.Name == "CenterBlock")
    local seat = nil
    
    if isCenterBlock then
        print("[BoatDestruction] Center block breaking! Finding new center...")
        seat = boat:FindFirstChild("Helm")
        
        -- Eject player from seat
        if seat then
            ejectPlayer(seat)
        end
        
        -- Find new center block
        local newCenter = findNewCenterBlock(boat)
        if newCenter then
            transferPhysicsToNewCenter(boat, piece, newCenter)
            
            -- Move seat to new center if it exists
            if seat and seat.Parent then
                seat:SetAttribute("Broken", true)
                local seatWeld = Instance.new("WeldConstraint")
                seatWeld.Part0 = newCenter
                seatWeld.Part1 = seat
                seatWeld.Name = "SeatWeld"
                seatWeld.Parent = newCenter
                
                -- Reposition seat on top of new center
                local blockHeight = newCenter.Size.Y
                seat.CFrame = newCenter.CFrame * CFrame.new(0, blockHeight/2 + 0.5, 0)
            end
        else
            print("[BoatDestruction] No blocks remaining! Boat destroyed!")
            -- Destroy the entire boat after a delay
            task.delay(2, function()
                if boat and boat.Parent then
                    boat:Destroy()
                end
            end)
        end
    end
    
    -- Find and destroy the weld connecting this piece
    local centerBlock = boat:FindFirstChild("CenterBlock") or boat.PrimaryPart
    if centerBlock then
        for _, weld in ipairs(centerBlock:GetChildren()) do
            if weld:IsA("WeldConstraint") and weld.Part1 == piece then
                weld:Destroy()
                break
            end
        end
    end
    
    -- Make piece independent
    piece.Anchored = false
    piece.Parent = Workspace -- Move out of boat model
    
    -- Add some ejection force based on collision
    local velocity = piece.AssemblyLinearVelocity
    local ejectForce = velocity + Vector3.new(
        math.random(-10, 10),
        math.random(5, 15),
        math.random(-10, 10)
    )
    piece.AssemblyLinearVelocity = ejectForce
    
    -- Add spin
    piece.AssemblyAngularVelocity = Vector3.new(
        math.random(-5, 5),
        math.random(-5, 5),
        math.random(-5, 5)
    )
    
    -- Create visual effect
    createBreakEffect(piece.Position)
    
    -- Make piece gradually sink and disappear
    task.delay(FLOAT_TIME, function()
        if piece and piece.Parent then
            -- Fade out
            local originalTransparency = piece.Transparency
            for i = 0, 10 do
                if piece and piece.Parent then
                    piece.Transparency = originalTransparency + (i / 10) * (1 - originalTransparency)
                    task.wait(0.2)
                end
            end
            if piece and piece.Parent then
                piece:Destroy()
            end
        end
    end)
    
    -- Show remaining blocks
    local remaining = getRemainingBlocks(boat)
    print("[BoatDestruction] Blocks remaining:", remaining)
end

local function onBoatPieceHit(boat, piece, otherPart, normalForce)
    -- Check if hit a rock
    if not otherPart:IsA("BasePart") then return end
    if otherPart.Name ~= "Rock" then return end
    
    -- Calculate impact force magnitude
    local forceMagnitude = normalForce.Magnitude
    
    if forceMagnitude > BREAK_FORCE_THRESHOLD then
        breakPieceOff(boat, piece)
    end
end

local function monitorBoat(boat)
    -- Monitor all boat pieces for collisions
    for _, piece in ipairs(boat:GetDescendants()) do
        if piece:IsA("BasePart") and piece:GetAttribute("BoatPiece") then
            local conn = piece.Touched:Connect(function(otherPart)
                -- For Touched event, we estimate force based on velocity difference
                if not piece:GetAttribute("Broken") then
                    local relativeVelocity = piece.AssemblyLinearVelocity
                    if otherPart:IsA("BasePart") and not otherPart.Anchored then
                        relativeVelocity = relativeVelocity - otherPart.AssemblyLinearVelocity
                    end
                    
                    local estimatedForce = relativeVelocity * piece.AssemblyMass
                    onBoatPieceHit(boat, piece, otherPart, estimatedForce)
                end
            end)
            
            table.insert(connections, conn)
        end
    end
end

function M.start()
    print("[BoatDestructionService] Starting...")
    
    -- Monitor existing boats
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Model") and obj:GetAttribute(Constants.BOAT_OWNER_ATTR) then
            monitorBoat(obj)
        end
    end
    
    -- Monitor new boats
    local conn = Workspace.ChildAdded:Connect(function(child)
        if child:IsA("Model") and child:GetAttribute(Constants.BOAT_OWNER_ATTR) then
            task.wait(0.1) -- Wait for boat to be fully constructed
            monitorBoat(child)
        end
    end)
    
    table.insert(connections, conn)
    
    print("[BoatDestructionService] Started successfully")
end

function M.stop()
    for _, conn in ipairs(connections) do
        conn:Disconnect()
    end
    connections = {}
end

return M