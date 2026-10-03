--- Reads back what the engine built: portals and how it grouped the tracks into tunnel strips.
-- @module tunnel_portal_fix_testbench.inspection
local inspection = {}

local LANE_TOLERANCE = 1.0 -- m

local function edge_types()
	return api.type["enum"].BaseEdgeType
end

--- Portals (nodes joining one open-air and one tunnel track edge) within `radius` of x, y,
-- sorted along +y. Each is { node, position, tunnel_edge }.
function inspection.find_portals(x, y, radius)
	local seen, portals = {}, {}
	local edges = api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(x, y), radius,
		api.type.ComponentType.BASE_EDGE)
	for _, edge_entity in ipairs(edges) do
		local edge = api.engine.getComponent(edge_entity, api.type.ComponentType.BASE_EDGE)
		for _, node in ipairs(edge and { edge.node0, edge.node1 } or {}) do
			if not seen[node] then
				seen[node] = true
				local segments = api.engine.system.streetSystem.getNodeTrackSegments(node)
				if #segments == 2 then
					local types, tunnel_edge = {}, nil
					for _, segment in ipairs(segments) do
						local segment_edge = api.engine.getComponent(segment, api.type.ComponentType.BASE_EDGE)
						types[segment_edge.type] = true
						if segment_edge.type == edge_types().TUNNEL then tunnel_edge = segment end
					end
					if types[edge_types().NORMAL] and tunnel_edge then
						local position = api.engine.getComponent(node, api.type.ComponentType.BASE_NODE).position
						portals[#portals + 1] = { node = node, position = position, tunnel_edge = tunnel_edge }
					end
				end
			end
		end
	end
	table.sort(portals, function(a, b) return a.position.y < b.position.y end)
	return portals
end

--- Cross-sections of the strips on `tunnel_edge`: per section, the lateral offsets of its lanes
-- relative to `reference_y`. Each strip is a list of cross-section groups; each group lists the
-- parallel lanes (edge ranges) side by side.
function inspection.sections(tunnel_edge, reference_y)
	local result = {}
	for _, strip in ipairs(api.engine.system.baseParallelStripSystem.getStrips(tunnel_edge)) do
		local component = api.engine.getComponent(strip, api.type.ComponentType.BASE_PARALLEL_STRIP)
		for _, group in ipairs(component and component.rangeGroups or {}) do
			local lanes = {}
			for _, range in ipairs(group) do
				local edge = api.engine.getComponent(range.edge, api.type.ComponentType.BASE_EDGE)
				if edge then lanes[#lanes + 1] = (edge.position0.y + edge.position1.y) / 2 - reference_y end
			end
			result[#result + 1] = lanes
		end
	end
	return result
end

local function has_lane_near(lanes, offset)
	for _, lane in ipairs(lanes) do
		if math.abs(lane - offset) < LANE_TOLERANCE then return true end
	end
	return false
end

local function format_lanes(lanes)
	local parts = {}
	for i, lane in ipairs(lanes) do parts[i] = string.format("%.1f", lane) end
	return "{" .. table.concat(parts, ",") .. "}"
end

--- Outcome of a scenario: "clean" (every section holds both tracks), "partial" or "separate",
-- plus a description of the portals and sections for the log.
function inspection.evaluate(scenario, x, y)
	local portals = inspection.find_portals(x, y + scenario.spacing / 2, 40)
	local positions, sections = {}, {}
	local clean, any_merged = #portals > 0, false
	for _, portal in ipairs(portals) do
		positions[#positions + 1] = string.format("(%.1f,%.1f)", portal.position.x - x, portal.position.y - y)
		for _, lanes in ipairs(inspection.sections(portal.tunnel_edge, y)) do
			sections[#sections + 1] = format_lanes(lanes)
			local both = has_lane_near(lanes, 0) and has_lane_near(lanes, scenario.spacing)
			any_merged = any_merged or both
			clean = clean and both
		end
	end
	local outcome = clean and "clean" or (any_merged and "partial" or "separate")
	local details = string.format("portals=%d %s strips=%s", #portals, table.concat(positions, " "),
		table.concat(sections, " "))
	return outcome, details
end

return inspection
