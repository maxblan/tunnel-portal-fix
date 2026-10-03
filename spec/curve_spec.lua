local mock_engine = require("mock_engine")

describe("curve", function()
	local curve, vec3

	before_each(function()
		mock_engine.new() -- installs api.type.Vec3f
		curve = require("/tunnel_portal_fix/curve.lua")
		vec3 = mock_engine.vec3
	end)

	-- Quarter circle of radius 100 around the origin, from (100, 0) to (0, 100).
	local function quarter_circle()
		local k = 100 * 4 / 3 * (math.sqrt(2) - 1) * 3 -- Hermite tangent length for a quarter arc
		return { position0 = vec3(100, 0), position1 = vec3(0, 100), tangent0 = vec3(0, k), tangent1 = vec3(-k, 0) }
	end

	local function straight()
		return { position0 = vec3(0, 0), position1 = vec3(100, 0), tangent0 = vec3(100, 0), tangent1 = vec3(100, 0) }
	end

	it("returns the end points at t = 0 and t = 1", function()
		local edge = quarter_circle()
		local p0, p1 = curve.point(edge, 0), curve.point(edge, 1)
		assert.near(100, p0.x, 1e-9)
		assert.near(0, p0.y, 1e-9)
		assert.near(0, p1.x, 1e-9)
		assert.near(100, p1.y, 1e-9)
	end)

	it("returns the tangents as derivatives at the end points", function()
		local edge = quarter_circle()
		local _, d0 = curve.point(edge, 0)
		local _, d1 = curve.point(edge, 1)
		assert.near(edge.tangent0.y, d0.y, 1e-9)
		assert.near(edge.tangent1.x, d1.x, 1e-9)
	end)

	it("measures the arc length of a straight edge", function()
		assert.near(100, curve.arc_length(straight(), 0, 1), 1e-6)
		assert.near(25, curve.arc_length(straight(), 0.25, 0.5), 1e-6)
	end)

	it("measures the arc length of a quarter circle within 0.1 %", function()
		assert.near(math.pi * 50, curve.arc_length(quarter_circle(), 0, 1), math.pi * 50 * 0.001)
	end)

	it("projects a point onto the edge and reports the lateral distance", function()
		local t, distance = curve.project(straight(), vec3(30, 5))
		assert.near(0.3, t, 1e-4)
		assert.near(5, distance, 1e-4)
	end)

	it("clamps projections beyond the ends to the end points", function()
		local t, distance = curve.project(straight(), vec3(-10, 0))
		assert.near(0, t, 1e-4)
		assert.near(10, distance, 1e-4)
	end)

	it("returns no horizontal direction for vertical vectors", function()
		assert.is_nil(curve.direction_2d(vec3(0, 0, 5)))
		local d = curve.direction_2d(vec3(3, 4, 7))
		assert.near(0.6, d.x, 1e-9)
		assert.near(0.8, d.y, 1e-9)
	end)
end)
