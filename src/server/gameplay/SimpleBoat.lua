local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Constants"))

local SimpleBoat = {}

function SimpleBoat.create(ownerUserId)
    local BOAT = Constants.BOAT

    local model = Instance.new("Model")
    model.Name = Constants.BOAT_NAME_PREFIX .. tostring(ownerUserId)
    model:SetAttribute(Constants.BOAT_OWNER_ATTR, ownerUserId)

    local hull = Instance.new("Part")
    hull.Name = "Hull"
    hull.Size = BOAT.HullSize
    hull.Material = Enum.Material.WoodPlanks
    hull.Color = Color3.fromRGB(200, 160, 90)
    hull.Anchored = true -- anchor while assembling / positioning
    hull.CanCollide = true
    hull.TopSurface = Enum.SurfaceType.Smooth
    hull.BottomSurface = Enum.SurfaceType.Smooth
    hull.CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.4, 0.5)
    hull.Parent = model

    local seat = Instance.new("VehicleSeat")
    seat.Name = "Helm"
    seat.Anchored = true
    seat.CanCollide = true
    seat.MaxSpeed = 0
    seat.TurnSpeed = 0
    seat.Parent = model

    -- seat at rear-center
    seat.CFrame = hull.CFrame * CFrame.new(0, 1.25, BOAT.HullSize.Z/2 - 2)

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = hull
    weld.Part1 = seat
    weld.Parent = model

    model.PrimaryPart = hull

    -- Force/torque setup
    local rootAttach = Instance.new("Attachment")
    rootAttach.Name = "RootAttachment"
    rootAttach.Parent = hull

    local thrust = Instance.new("VectorForce")
    thrust.Name = "Thrust"
    thrust.Attachment0 = rootAttach
    thrust.ApplyAtCenterOfMass = true
    thrust.RelativeTo = Enum.ActuatorRelativeTo.World
    thrust.Force = Vector3.zero
    thrust.Parent = hull

    local gyro = Instance.new("AngularVelocity")
    gyro.Name = "Yaw"
    gyro.Attachment0 = rootAttach
    gyro.MaxTorque = math.huge
    gyro.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
    gyro.AngularVelocity = Vector3.zero
    gyro.Parent = hull

    local lin = Instance.new("LinearVelocity")
    lin.Attachment0 = rootAttach
    lin.RelativeTo = Enum.ActuatorRelativeTo.World
    lin.MaxForce = 0
    lin.VectorVelocity = Vector3.zero
    lin.Parent = hull

    model:SetAttribute("MaxThrust", BOAT.MaxThrust)
    model:SetAttribute("TurnTorque", BOAT.TurnTorque)
    model:SetAttribute("LinearDrag", BOAT.LinearDrag)
    model:SetAttribute("AngularDrag", BOAT.AngularDrag)

    return model
end

return SimpleBoat
