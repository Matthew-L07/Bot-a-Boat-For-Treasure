local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Constants"))

local SimpleBoat = {}

function SimpleBoat.create(ownerUserId)
    local BOAT = Constants.BOAT

    local model = Instance.new("Model")
    model.Name = Constants.BOAT_NAME_PREFIX .. tostring(ownerUserId)
    model:SetAttribute(Constants.BOAT_OWNER_ATTR, ownerUserId)

    -- === Main Hull (Center) ===
    local hull = Instance.new("Part")
    hull.Name = "Hull"
    hull.Size = Vector3.new(BOAT.HullSize.X * 0.6, BOAT.HullSize.Y, BOAT.HullSize.Z * 0.6)
    hull.Material = Enum.Material.WoodPlanks
    hull.Color = Color3.fromRGB(200, 160, 90)
    hull.TopSurface = Enum.SurfaceType.Smooth
    hull.BottomSurface = Enum.SurfaceType.Smooth
    hull.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.5, 0.5, 1, 1)
    hull.CanCollide = true
    hull.Anchored = true
    hull.Parent = model

    -- === Bow (Front piece) ===
    local bow = Instance.new("Part")
    bow.Name = "Bow"
    bow.Size = Vector3.new(BOAT.HullSize.X * 0.5, BOAT.HullSize.Y * 0.8, BOAT.HullSize.Z * 0.3)
    bow.Material = Enum.Material.WoodPlanks
    bow.Color = Color3.fromRGB(180, 140, 70)
    bow.TopSurface = Enum.SurfaceType.Smooth
    bow.BottomSurface = Enum.SurfaceType.Smooth
    bow.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.5, 0.5, 1, 1)
    bow.CanCollide = true
    bow.Anchored = true
    bow.Parent = model
    bow.CFrame = hull.CFrame * CFrame.new(0, 0, -(BOAT.HullSize.Z * 0.45))
    bow:SetAttribute("BoatPiece", true)

    -- === Stern (Back piece) ===
    local stern = Instance.new("Part")
    stern.Name = "Stern"
    stern.Size = Vector3.new(BOAT.HullSize.X * 0.5, BOAT.HullSize.Y * 0.8, BOAT.HullSize.Z * 0.3)
    stern.Material = Enum.Material.WoodPlanks
    stern.Color = Color3.fromRGB(180, 140, 70)
    stern.TopSurface = Enum.SurfaceType.Smooth
    stern.BottomSurface = Enum.SurfaceType.Smooth
    stern.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.5, 0.5, 1, 1)
    stern.CanCollide = true
    stern.Anchored = true
    stern.Parent = model
    stern.CFrame = hull.CFrame * CFrame.new(0, 0, (BOAT.HullSize.Z * 0.45))
    stern:SetAttribute("BoatPiece", true)

    -- === Port Side (Left) ===
    local port = Instance.new("Part")
    port.Name = "PortSide"
    port.Size = Vector3.new(BOAT.HullSize.X * 0.15, BOAT.HullSize.Y * 0.6, BOAT.HullSize.Z * 0.8)
    port.Material = Enum.Material.WoodPlanks
    port.Color = Color3.fromRGB(190, 150, 80)
    port.TopSurface = Enum.SurfaceType.Smooth
    port.BottomSurface = Enum.SurfaceType.Smooth
    port.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.5, 0.5, 1, 1)
    port.CanCollide = true
    port.Anchored = true
    port.Parent = model
    port.CFrame = hull.CFrame * CFrame.new(-(BOAT.HullSize.X * 0.375), 0, 0)
    port:SetAttribute("BoatPiece", true)

    -- === Starboard Side (Right) ===
    local starboard = Instance.new("Part")
    starboard.Name = "StarboardSide"
    starboard.Size = Vector3.new(BOAT.HullSize.X * 0.15, BOAT.HullSize.Y * 0.6, BOAT.HullSize.Z * 0.8)
    starboard.Material = Enum.Material.WoodPlanks
    starboard.Color = Color3.fromRGB(190, 150, 80)
    starboard.TopSurface = Enum.SurfaceType.Smooth
    starboard.BottomSurface = Enum.SurfaceType.Smooth
    starboard.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.5, 0.5, 1, 1)
    starboard.CanCollide = true
    starboard.Anchored = true
    starboard.Parent = model
    starboard.CFrame = hull.CFrame * CFrame.new((BOAT.HullSize.X * 0.375), 0, 0)
    starboard:SetAttribute("BoatPiece", true)

    -- === Seat (driver) ===
    local seat = Instance.new("VehicleSeat")
    seat.Name = "Helm"
    seat.Size = Vector3.new(2, 0.5, 2)
    seat.CanCollide = true
    seat.MaxSpeed = 0
    seat.TurnSpeed = 0
    seat.Anchored = true
    seat.Material = Enum.Material.Wood
    seat.Color = Color3.fromRGB(139, 90, 43)
    seat.Parent = model
    
    local seatOffset = CFrame.new(0, BOAT.HullSize.Y/2 + 0.75, BOAT.HullSize.Z/2 - 1.5)
    seat.CFrame = hull.CFrame * seatOffset

    model.PrimaryPart = hull

    -- === Weld all pieces to the hull ===
    local pieces = {bow, stern, port, starboard, seat}
    for _, piece in ipairs(pieces) do
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = hull
        weld.Part1 = piece
        weld.Name = "PieceWeld_" .. piece.Name
        weld.Parent = hull
    end

    -- === Physics Setup ===
    local rootAttach = Instance.new("Attachment")
    rootAttach.Name = "RootAttachment"
    rootAttach.Position = Vector3.new(0, 0, 0)
    rootAttach.Parent = hull

    local thrust = Instance.new("VectorForce")
    thrust.Name = "Thrust"
    thrust.Attachment0 = rootAttach
    thrust.ApplyAtCenterOfMass = true
    thrust.RelativeTo = Enum.ActuatorRelativeTo.World
    thrust.Force = Vector3.zero
    thrust.Parent = hull

    local currentForce = Instance.new("VectorForce")
    currentForce.Name = "CurrentForce"
    currentForce.Attachment0 = rootAttach
    currentForce.ApplyAtCenterOfMass = true
    currentForce.RelativeTo = Enum.ActuatorRelativeTo.World
    currentForce.Force = Vector3.zero
    currentForce.Enabled = true
    currentForce.Parent = hull

    local angVel = Instance.new("AngularVelocity")
    angVel.Name = "TurnControl"
    angVel.Attachment0 = rootAttach
    angVel.RelativeTo = Enum.ActuatorRelativeTo.World
    angVel.MaxTorque = 100000
    angVel.AngularVelocity = Vector3.zero
    angVel.Parent = hull

    local align = Instance.new("AlignOrientation")
    align.Name = "Upright"
    align.Attachment0 = rootAttach
    align.Mode = Enum.OrientationAlignmentMode.OneAttachment
    align.Responsiveness = 20
    align.MaxAngularVelocity = 5
    align.MaxTorque = 30000
    align.AlignType = Enum.AlignType.PrimaryAxisPerpendicular
    align.PrimaryAxisOnly = true
    align.PrimaryAxis = Vector3.new(0, 1, 0)
    align.Parent = hull
    align.CFrame = CFrame.new()

    model:SetAttribute("MaxThrust", BOAT.MaxThrust)
    model:SetAttribute("TurnTorque", BOAT.TurnTorque)
    model:SetAttribute("LinearDrag", BOAT.LinearDrag)
    model:SetAttribute("AngularDrag", BOAT.AngularDrag)

    return model
end

return SimpleBoat