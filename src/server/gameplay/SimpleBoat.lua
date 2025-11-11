local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Constants"))

local SimpleBoat = {}

function SimpleBoat.create(ownerUserId)
    local BOAT = Constants.BOAT

    local model = Instance.new("Model")
    model.Name = Constants.BOAT_NAME_PREFIX .. tostring(ownerUserId)
    model:SetAttribute(Constants.BOAT_OWNER_ATTR, ownerUserId)

    -- === Hull ===
    local hull = Instance.new("Part")
    hull.Name = "Hull"
    hull.Size = BOAT.HullSize
    hull.Material = Enum.Material.WoodPlanks
    hull.Color = Color3.fromRGB(200, 160, 90)
    hull.TopSurface = Enum.SurfaceType.Smooth
    hull.BottomSurface = Enum.SurfaceType.Smooth
    -- Density for good buoyancy - lighter floats better
    hull.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.5, 0.5, 1, 1)
    hull.CanCollide = true
    hull.Anchored = true
    hull.Parent = model

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
    
    -- Position seat on top-back of hull
    local seatOffset = CFrame.new(0, BOAT.HullSize.Y/2 + 0.75, BOAT.HullSize.Z/2 - 1.5)
    seat.CFrame = hull.CFrame * seatOffset

    -- Weld seat to hull
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = hull
    weld.Part1 = seat
    weld.Parent = hull

    model.PrimaryPart = hull

    -- === Physics Setup ===
    local rootAttach = Instance.new("Attachment")
    rootAttach.Name = "RootAttachment"
    rootAttach.Position = Vector3.new(0, 0, 0)
    rootAttach.Parent = hull

    -- Thrust force
    local thrust = Instance.new("VectorForce")
    thrust.Name = "Thrust"
    thrust.Attachment0 = rootAttach
    thrust.ApplyAtCenterOfMass = true
    thrust.RelativeTo = Enum.ActuatorRelativeTo.World
    thrust.Force = Vector3.zero
    thrust.Parent = hull

    -- Current force (will be controlled by CurrentService)
    local currentForce = Instance.new("VectorForce")
    currentForce.Name = "CurrentForce"
    currentForce.Attachment0 = rootAttach
    currentForce.ApplyAtCenterOfMass = true
    currentForce.RelativeTo = Enum.ActuatorRelativeTo.World
    currentForce.Force = Vector3.zero
    currentForce.Enabled = true
    currentForce.Parent = hull
    
    print("[SimpleBoat] Created boat with CurrentForce for user", ownerUserId)

    -- Torque for turning (uses AngularVelocity for smooth rotation)
    local angVel = Instance.new("AngularVelocity")
    angVel.Name = "TurnControl"
    angVel.Attachment0 = rootAttach
    angVel.RelativeTo = Enum.ActuatorRelativeTo.World
    angVel.MaxTorque = 100000
    angVel.AngularVelocity = Vector3.zero
    angVel.Parent = hull

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
    align.Parent = hull
    align.CFrame = CFrame.new()

    -- Tunables
    model:SetAttribute("MaxThrust", BOAT.MaxThrust)
    model:SetAttribute("TurnTorque", BOAT.TurnTorque)
    model:SetAttribute("LinearDrag", BOAT.LinearDrag)
    model:SetAttribute("AngularDrag", BOAT.AngularDrag)

    return model
end

return SimpleBoat