--- Geometry of base edges: cubic Hermite curves given by two positions and two tangents.
-- @module tunnel_portal_fix.curve
local curve = {}

local SAMPLES = 64
local GOLDEN = (math.sqrt(5) - 1) / 2

--- Horizontal distance between two points.
function curve.distance_2d(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

--- Horizontal unit direction of `v`, or nil for a vertical or zero vector.
function curve.direction_2d(v)
	local length = math.sqrt(v.x * v.x + v.y * v.y)
	if length < 1e-6 then return nil end
	return { x = v.x / length, y = v.y / length }
end

--- `v` scaled to length 1.
function curve.unit(v)
	return v * (1 / math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z))
end

--- Position and derivative of `edge` at parameter t in [0, 1].
function curve.point(edge, t)
	local p0, p1, m0, m1 = edge.position0, edge.position1, edge.tangent0, edge.tangent1
	local t2, t3 = t * t, t * t * t
	local h00, h10, h01, h11 = 2 * t3 - 3 * t2 + 1, t3 - 2 * t2 + t, -2 * t3 + 3 * t2, t3 - t2
	local d00, d10, d01, d11 = 6 * t2 - 6 * t, 3 * t2 - 4 * t + 1, -6 * t2 + 6 * t, 3 * t2 - 2 * t

	local function combine(a, b, c, d, axis)
		return a * p0[axis] + b * m0[axis] + c * p1[axis] + d * m1[axis]
	end

	local position = api.type.Vec3f.new(combine(h00, h10, h01, h11, "x"), combine(h00, h10, h01, h11, "y"),
		combine(h00, h10, h01, h11, "z"))
	local derivative = api.type.Vec3f.new(combine(d00, d10, d01, d11, "x"), combine(d00, d10, d01, d11, "y"),
		combine(d00, d10, d01, d11, "z"))
	return position, derivative
end

--- Parameter of the point on `edge` closest to `target` (horizontally), and that distance.
function curve.project(edge, target)
	local best_t, best_distance = 0, math.huge
	for i = 0, SAMPLES do
		local t = i / SAMPLES
		local distance = curve.distance_2d(curve.point(edge, t), target)
		if distance < best_distance then
			best_t, best_distance = t, distance
		end
	end

	-- Golden-section refinement between the neighbouring samples.
	local lo, hi = math.max(0, best_t - 1 / SAMPLES), math.min(1, best_t + 1 / SAMPLES)
	for _ = 1, 30 do
		local a, b = hi - GOLDEN * (hi - lo), lo + GOLDEN * (hi - lo)
		if curve.distance_2d(curve.point(edge, a), target) < curve.distance_2d(curve.point(edge, b), target) then
			hi = b
		else
			lo = a
		end
	end

	local t = (lo + hi) / 2
	return t, curve.distance_2d(curve.point(edge, t), target)
end

--- Horizontal length of `edge` between parameters t0 and t1.
function curve.arc_length(edge, t0, t1)
	local length, previous = 0, curve.point(edge, t0)
	for i = 1, SAMPLES do
		local current = curve.point(edge, t0 + (t1 - t0) * i / SAMPLES)
		length = length + curve.distance_2d(previous, current)
		previous = current
	end
	return length
end

return curve
