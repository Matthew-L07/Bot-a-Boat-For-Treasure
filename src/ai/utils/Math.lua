-- Math.lua
-- Utility math functions for AI navigation

local Math = {}

-- Normalize an angle to [-pi, pi]
function Math.normalizeAngle(angle)
    while angle > math.pi do
        angle = angle - 2 * math.pi
    end
    while angle < -math.pi do
        angle = angle + 2 * math.pi
    end
    return angle
end

-- Linear interpolation
function Math.lerp(a, b, t)
    return a + (b - a) * t
end

-- Smooth interpolation (ease in/out)
function Math.smoothstep(t)
    return t * t * (3 - 2 * t)
end

-- Clamp value between min and max
function Math.clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

-- Map value from one range to another
function Math.map(value, inMin, inMax, outMin, outMax)
    return outMin + (value - inMin) * (outMax - outMin) / (inMax - inMin)
end

-- Exponential moving average
function Math.ema(current, new, alpha)
    return alpha * new + (1 - alpha) * current
end

-- Calculate angle between two vectors (in radians)
function Math.angleBetween(v1, v2)
    local dot = v1.X * v2.X + v1.Y * v2.Y + v1.Z * v2.Z
    local mag1 = math.sqrt(v1.X^2 + v1.Y^2 + v1.Z^2)
    local mag2 = math.sqrt(v2.X^2 + v2.Y^2 + v2.Z^2)
    
    if mag1 == 0 or mag2 == 0 then
        return 0
    end
    
    local cosAngle = Math.clamp(dot / (mag1 * mag2), -1, 1)
    return math.acos(cosAngle)
end

-- Get signed angle from v1 to v2 around axis
function Math.signedAngle(v1, v2, axis)
    local angle = Math.angleBetween(v1, v2)
    
    -- Calculate cross product
    local cross = Vector3.new(
        v1.Y * v2.Z - v1.Z * v2.Y,
        v1.Z * v2.X - v1.X * v2.Z,
        v1.X * v2.Y - v1.Y * v2.X
    )
    
    -- Determine sign based on axis
    local dot = cross.X * axis.X + cross.Y * axis.Y + cross.Z * axis.Z
    
    return dot >= 0 and angle or -angle
end

-- Distance between two points
function Math.distance(p1, p2)
    local dx = p2.X - p1.X
    local dy = p2.Y - p1.Y
    local dz = p2.Z - p1.Z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- Distance between two points (ignoring Y)
function Math.distance2D(p1, p2)
    local dx = p2.X - p1.X
    local dz = p2.Z - p1.Z
    return math.sqrt(dx*dx + dz*dz)
end

-- Rotate a 2D vector by angle (radians)
function Math.rotate2D(x, z, angle)
    local cos = math.cos(angle)
    local sin = math.sin(angle)
    return x * cos - z * sin, x * sin + z * cos
end

-- Generate random float in range
function Math.randomFloat(min, max)
    return min + math.random() * (max - min)
end

-- Generate random vector in unit sphere
function Math.randomUnitVector()
    -- Using rejection sampling
    local x, y, z
    repeat
        x = Math.randomFloat(-1, 1)
        y = Math.randomFloat(-1, 1)
        z = Math.randomFloat(-1, 1)
    until x*x + y*y + z*z <= 1
    
    local mag = math.sqrt(x*x + y*y + z*z)
    return Vector3.new(x/mag, y/mag, z/mag)
end

-- Gaussian/normal distribution random number
function Math.randomGaussian(mean, stddev)
    mean = mean or 0
    stddev = stddev or 1
    
    -- Box-Muller transform
    local u1 = math.random()
    local u2 = math.random()
    local z0 = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    
    return mean + z0 * stddev
end

-- Moving average calculator
function Math.createMovingAverage(windowSize)
    local values = {}
    local sum = 0
    local count = 0
    
    return {
        add = function(value)
            table.insert(values, value)
            sum = sum + value
            count = count + 1
            
            if count > windowSize then
                sum = sum - table.remove(values, 1)
                count = count - 1
            end
        end,
        
        get = function()
            return count > 0 and (sum / count) or 0
        end,
        
        reset = function()
            values = {}
            sum = 0
            count = 0
        end,
    }
end

-- Softmax function (for action probabilities)
function Math.softmax(values)
    local maxVal = math.max(table.unpack(values))
    local expSum = 0
    local expValues = {}
    
    for i, v in ipairs(values) do
        local expVal = math.exp(v - maxVal)
        expValues[i] = expVal
        expSum = expSum + expVal
    end
    
    for i, expVal in ipairs(expValues) do
        expValues[i] = expVal / expSum
    end
    
    return expValues
end

-- Weighted random choice
function Math.weightedChoice(choices, weights)
    local totalWeight = 0
    for _, w in ipairs(weights) do
        totalWeight = totalWeight + w
    end
    
    local rand = math.random() * totalWeight
    local cumulative = 0
    
    for i, w in ipairs(weights) do
        cumulative = cumulative + w
        if cumulative >= rand then
            return choices[i], i
        end
    end
    
    return choices[#choices], #choices
end

return Math