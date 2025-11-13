local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Constants"))

local SimpleBoat = {}

function SimpleBoat.create(ownerUserId)
    local BOAT = Constants.BOAT

    local model = Instance.new("Model")
    model.Name = Constants.BOAT_NAME_PREFIX .. tostring(ownerUserId)
    model:SetAttribute(Constants.BOAT_OWNER_ATTR, ownerUserId)

    -- Calculate block size - divide the original hull into 3x3 grid
    local totalWidth = BOAT.HullSize.X
    local totalHeight = BOAT.HullSize.Y
    local totalLength = BOAT.HullSize.Z
    
    local blockWidth = totalWidth / 3
    local blockHeight = totalHeight
    local blockLength = totalLength / 3
    local blockSize = Vector3.new(blockWidth, blockHeight, blockLength)
    
    -- Create 3x3 grid of blocks
    -- Grid positions: rows (-1, 0, 1) and columns (-1, 0, 1)
    local blocks = {}
    local centerBlock = nil
    
    for row = -1, 1 do
        for col = -1, 1 do
            local block = Instance.new("Part")
            
            -- Name blocks by position
            local blockName = "Block_" .. (row + 1) .. "_" .. (col + 1)
            if row == 0 and col == 0 then
                blockName = "CenterBlock"
            end
            block.Name = blockName
            
            block.Size = blockSize
            block.Material = Enum.Material.WoodPlanks
            
            -- Vary colors slightly for visual distinction
            local baseColor = Color3.fromRGB(200, 160, 90)
            local variation = math.random(-10, 10)
            block.Color = Color3.fromRGB(
                math.clamp(baseColor.R * 255 + variation, 0, 255) / 255,
                math.clamp(baseColor.G * 255 + variation, 0, 255) / 255,
                math.clamp(baseColor.B * 255 + variation, 0, 255) / 255
            )
            
            block.TopSurface = Enum.SurfaceType.Smooth
            block.BottomSurface = Enum.SurfaceType.Smooth
            block.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.5, 0.5, 1, 1)
            block.CanCollide = true
            block.Anchored = true
            block.Parent = model
            
            -- Position in grid
            local xOffset = col * blockWidth
            local zOffset = row * blockLength
            block.CFrame = CFrame.new(xOffset, 0, zOffset)
            
            -- Mark as boat piece
            block:SetAttribute("BoatPiece", true)
            block:SetAttribute("GridRow", row)
            block:SetAttribute("GridCol", col)
            
            table.insert(blocks, block)
            
            -- Store center block reference
            if row == 0 and col == 0 then
                centerBlock = block
            end
        end
    end

    -- Set center block as primary part
    model.PrimaryPart = centerBlock

    -- === Seat (on top of center block) ===
    local seat = Instance.new("VehicleSeat")
    seat.Name = "Helm"
    seat.Size = Vector3.new(blockWidth * 0.8, 0.5, blockLength * 0.8)
    seat.CanCollide = true
    seat.MaxSpeed = 0
    seat.TurnSpeed = 0
    seat.Anchored = true
    seat.Material = Enum.Material.Wood
    seat.Color = Color3.fromRGB(139, 90, 43)
    seat.Parent = model
    
    -- Position seat on top of center block
    local seatOffset = CFrame.new(0, blockHeight/2 + 0.5, 0)
    seat.CFrame = centerBlock.CFrame * seatOffset

    -- === Weld all blocks together ===
    -- Weld all blocks to the center block
    for _, block in ipairs(blocks) do
        if block ~= centerBlock then
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = centerBlock
            weld.Part1 = block
            weld.Name = "BlockWeld_" .. block.Name
            weld.Parent = centerBlock
        end
    end
    
    -- Weld seat to center block
    local seatWeld = Instance.new("WeldConstraint")
    seatWeld.Part0 = centerBlock
    seatWeld.Part1 = seat
    seatWeld.Name = "SeatWeld"
    seatWeld.Parent = centerBlock

    -- === Physics Setup (all on center block) ===
    local rootAttach = Instance.new("Attachment")
    rootAttach.Name = "RootAttachment"
    rootAttach.Position = Vector3.new(0, 0, 0)
    rootAttach.Parent = centerBlock

    -- Thrust force
    local thrust = Instance.new("VectorForce")
    thrust.Name = "Thrust"
    thrust.Attachment0 = rootAttach
    thrust.ApplyAtCenterOfMass = true
    thrust.RelativeTo = Enum.ActuatorRelativeTo.World
    thrust.Force = Vector3.zero
    thrust.Parent = centerBlock

    -- Current force (will be controlled by CurrentService)
    local currentForce = Instance.new("VectorForce")
    currentForce.Name = "CurrentForce"
    currentForce.Attachment0 = rootAttach
    currentForce.ApplyAtCenterOfMass = true
    currentForce.RelativeTo = Enum.ActuatorRelativeTo.World
    currentForce.Force = Vector3.zero
    currentForce.Enabled = true
    currentForce.Parent = centerBlock

    -- Torque for turning (uses AngularVelocity for smooth rotation)
    local angVel = Instance.new("AngularVelocity")
    angVel.Name = "TurnControl"
    angVel.Attachment0 = rootAttach
    angVel.RelativeTo = Enum.ActuatorRelativeTo.World
    angVel.MaxTorque = 100000
    angVel.AngularVelocity = Vector3.zero
    angVel.Parent = centerBlock

    -- Alignment to keep boat upright (only stabilizes roll/pitch, not yaw)
    local align = Instance.new("AlignOrientation")
    align.Name = "Upright"
    align.Attachment0 = rootAttach
    align.Mode = Enum.OrientationAlignmentMode.OneAttachment
    align.Responsiveness = 20
    align.MaxAngularVelocity = 5
    align.MaxTorque = 30000
    align.AlignType = Enum.AlignType.PrimaryAxisPerpendicular
    align.PrimaryAxisOnly = true
    align.PrimaryAxis = Vector3.new(0, 1, 0)  -- Keep Y-axis up
    align.Parent = centerBlock
    align.CFrame = CFrame.new()

    -- Tunables
    model:SetAttribute("MaxThrust", BOAT.MaxThrust)
    model:SetAttribute("TurnTorque", BOAT.TurnTorque)
    model:SetAttribute("LinearDrag", BOAT.LinearDrag)
    model:SetAttribute("AngularDrag", BOAT.AngularDrag)

    print("[SimpleBoat] Created 3x3 grid boat with", #blocks, "blocks for user", ownerUserId)

    return model
end

return SimpleBoat