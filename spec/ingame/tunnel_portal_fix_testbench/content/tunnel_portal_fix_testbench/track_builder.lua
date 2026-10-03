--- Build commands for test tracks, sent player-initiated so the mod under test reacts to them.
-- @module tunnel_portal_fix_testbench.track_builder
local site = require("/tunnel_portal_fix_testbench/site.lua")

local track_builder = {}

local TRACK_TEMPLATE = "::/infrastructure/track/standard/standard.street_template"
local TRACK = 1 -- SegmentAndEntity.type

local function vec3(x, y, z)
	return api.type.Vec3f.new(x, y, z)
end

--- A new, empty build command.
function track_builder.new()
	local build = {
		proposal = api.type.SimpleProposal.new(),
		nodes = {},
		edges = {},
		to_remove = {},
		next_id = -1,
	}

	function build.id()
		local id = build.next_id
		build.next_id = build.next_id - 1
		return id
	end

	function build.node(x, y, z)
		local node = api.type.NodeAndEntity.new()
		node.entity = build.id()
		node.comp.position = vec3(x, y, z)
		build.nodes[#build.nodes + 1] = node
		return node.entity, node.comp.position
	end

	function build.edge(node0, p0, node1, p1, edge_type, type_index, tangent0, tangent1)
		local template = api.res.streetTemplateRep.get(api.res.streetTemplateRep.find(TRACK_TEMPLATE))
		local chord = vec3(p1.x - p0.x, p1.y - p0.y, p1.z - p0.z)
		local segment = api.type.SegmentAndEntity.new()
		segment.entity = build.id()
		segment.type = TRACK
		segment.comp.node0, segment.comp.node1 = node0, node1
		segment.comp.position0, segment.comp.position1 = p0, p1
		segment.comp.tangent0, segment.comp.tangent1 = tangent0 or chord, tangent1 or chord
		segment.comp.type = edge_type
		segment.comp.typeIndex = type_index
		segment.comp.laneConfigs = template.laneConfigs
		segment.comp.roadTemplate = TRACK_TEMPLATE
		segment.comp.roadStyle = template.streetStyle
		segment.comp.roadType = api.type["enum"].RoadType.TRACK
		build.edges[#build.edges + 1] = segment
	end

	function build.send()
		-- List fields of engine objects are copies: always assign whole lists.
		build.proposal.streetProposal.nodesToAdd = build.nodes
		build.proposal.streetProposal.edgesToAdd = build.edges
		build.proposal.streetProposal.edgesToRemove = build.to_remove
		local context = api.type.Context.new()
		context.player = api.engine.util.getPlayer()
		api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(build.proposal, context, false, true))
	end

	return build
end

--- Adds a track at lateral position y whose portal lies at portal_x (site-relative).
function track_builder.add_track(build, found, y, portal_x, tunnel_type)
	local edge_types = api.type["enum"].BaseEdgeType
	local x0, level_z = found.x, found.base - site.DEPTH
	local start_z = site.height(x0 + site.START_X, y)
	local start, start_pos = build.node(x0 + site.START_X, y, start_z)
	local kink, kink_pos = build.node(x0 + site.KINK_X, y, level_z)
	local portal, portal_pos = build.node(x0 + portal_x, y, level_z)
	local finish, finish_pos = build.node(x0 + site.END_X, y, level_z)

	-- Smooth descent: level tangent at the kink.
	local descent = site.KINK_X - site.START_X
	build.edge(start, start_pos, kink, kink_pos, edge_types.NORMAL, 0,
		vec3(descent, 0, level_z - start_z), vec3(descent, 0, 0))
	build.edge(kink, kink_pos, portal, portal_pos, edge_types.NORMAL, 0)
	build.edge(portal, portal_pos, finish, finish_pos, edge_types.TUNNEL, tunnel_type)
end

--- Removes the existing track edges along y and re-adds identical copies in the same build, so
-- the engine sees them together with the new track. Returns the number of re-added edges.
function track_builder.readd_track(build, found, y)
	local center = api.type.Vec2f.new(found.x + (site.START_X + site.END_X) / 2, y)
	local radius = site.END_X - site.START_X
	for _, edge_entity in ipairs(api.engine.util.octree.findEntitiesInCircle(center, radius,
		api.type.ComponentType.BASE_EDGE)) do
		local edge = api.engine.getComponent(edge_entity, api.type.ComponentType.BASE_EDGE)
		if edge and math.abs(edge.position0.y - y) < 0.5 and math.abs(edge.position1.y - y) < 0.5 then
			local segment = api.type.SegmentAndEntity.new()
			segment.entity = build.id()
			segment.type = TRACK
			segment.comp = edge
			local player_owned = api.engine.getComponent(edge_entity, api.type.ComponentType.PLAYER_OWNED)
			if player_owned then segment.playerOwned = player_owned end
			build.edges[#build.edges + 1] = segment
			build.to_remove[#build.to_remove + 1] = edge_entity
		end
	end
	return #build.to_remove
end

return track_builder
