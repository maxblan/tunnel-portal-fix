--- Tunnel portals in the track network: nodes where an open-air edge meets a tunnel edge.
-- @module tunnel_portal_fix.portal
local curve = require("/tunnel_portal_fix/curve.lua")

local portal = {}

local function edge_types()
	return api.type["enum"].BaseEdgeType
end

--- The portal at `node`, or nil if `node` is not (or no longer) a portal.
-- A portal is a table with the fields: node, position, tunnel_edge, tunnel, outer_edge, outer,
-- inward (horizontal unit direction from the portal into the tunnel).
function portal.at_node(node)
	-- Queued nodes may have been removed by later builds.
	if not api.engine.entityExists(node) then return nil end
	local base_node = api.engine.getComponent(node, api.type.ComponentType.BASE_NODE)
	if not base_node then return nil end
	local segments = api.engine.system.streetSystem.getNodeTrackSegments(node)
	if #segments ~= 2 then return nil end

	local result = { node = node, position = base_node.position }
	for _, segment in ipairs(segments) do
		local edge = api.engine.getComponent(segment, api.type.ComponentType.BASE_EDGE)
		if not edge then return nil end
		if edge.type == edge_types().TUNNEL then
			result.tunnel_edge, result.tunnel = segment, edge
		elseif edge.type == edge_types().NORMAL then
			result.outer_edge, result.outer = segment, edge
		end
	end
	if not result.tunnel or not result.outer then return nil end

	local tunnel = result.tunnel
	local tangent = tunnel.node0 == node and tunnel.tangent0 or tunnel.tangent1 * -1
	result.inward = curve.direction_2d(tangent)
	if not result.inward then return nil end
	return result
end

--- Portals of other tracks within `radius` of `origin`.
function portal.neighbours(origin, radius)
	local result, seen = {}, { [origin.node] = true }
	local center = api.type.Vec2f.new(origin.position.x, origin.position.y)
	local edges = api.engine.util.octree.findEntitiesInCircle(center, radius, api.type.ComponentType.BASE_EDGE)
	for _, edge_entity in ipairs(edges) do
		local edge = api.engine.getComponent(edge_entity, api.type.ComponentType.BASE_EDGE)
		if edge and edge.type == edge_types().TUNNEL then
			for _, node in ipairs({ edge.node0, edge.node1 }) do
				if not seen[node] then
					seen[node] = true
					local other = portal.at_node(node)
					if other then result[#result + 1] = other end
				end
			end
		end
	end
	return result
end

--- Human-readable description of how the engine grouped the portal's tunnel edge into
-- parallel strips: one line per strip, one {...} per cross-section, one range per lane.
function portal.describe_strips(origin)
	local lines = {}
	for _, strip in ipairs(api.engine.system.baseParallelStripSystem.getStrips(origin.tunnel_edge)) do
		local component = api.engine.getComponent(strip, api.type.ComponentType.BASE_PARALLEL_STRIP)
		local groups = {}
		for _, range_group in ipairs(component and component.rangeGroups or {}) do
			local ranges = {}
			for _, range in ipairs(range_group) do
				local edge = api.engine.getComponent(range.edge, api.type.ComponentType.BASE_EDGE)
				local mid = edge and curve.point(edge, (range.bounds[1] + range.bounds[2]) / 2)
				ranges[#ranges + 1] = string.format("%d[%.2f-%.2f]@(%.1f,%.1f)", range.edge, range.bounds[1],
					range.bounds[2], mid and mid.x or 0, mid and mid.y or 0)
			end
			groups[#groups + 1] = "{" .. table.concat(ranges, " ") .. "}"
		end
		lines[#lines + 1] = string.format("portal %d edge %d strip %d: %s", origin.node, origin.tunnel_edge, strip,
			table.concat(groups, " "))
	end
	return lines
end

return portal
