--- Decides whether two parallel tunnel portals should be aligned and builds the proposal.
--
-- The engine merges parallel tracks into one tunnel strip (one wide portal) only when they are at
-- most about 5.2 m apart and built together. When their entries are staggered, the strip starts
-- at the later entry: the earlier track gets a single portal and the later entry a double one,
-- and the two clip. Aligning the later portal with the earlier one, and re-adding the neighbour
-- in the same build, gives one strip from the portal on. All limits were measured in-game
-- (spec/ingame).
-- @module tunnel_portal_fix.alignment
local curve = require("/tunnel_portal_fix/curve.lua")
local logger = require("/tunnel_portal_fix/logger.lua")
local portal = require("/tunnel_portal_fix/portal.lua")

local alignment = {}

local MAX_STAGGER = 20.0 -- m along the track between the two entries
local MIN_STAGGER = 1.0 -- below this the entries count as aligned
local MIN_SPACING = 2.5 -- m between the tracks
local MAX_SPACING = 5.3 -- the engine merges tracks up to 5.2 m apart, but not from 5.4 m
local MAX_HEIGHT_DIFF = 3.0 -- ignore tunnels stacked above each other
local MIN_PARALLEL_DOT = 0.95

--- Radius around a portal in which neighbours are considered.
alignment.SEARCH_RADIUS = MAX_STAGGER + MAX_SPACING

local TRACK = 1 -- SegmentAndEntity.type

local function with_player_owned(segment, edge_entity)
	local player_owned = api.engine.getComponent(edge_entity, api.type.ComponentType.PLAYER_OWNED)
	if player_owned then segment.playerOwned = player_owned end
	return segment
end

local function new_segment(entity, edge_entity)
	local segment = api.type.SegmentAndEntity.new()
	segment.entity = entity
	segment.type = TRACK
	segment.comp = api.engine.getComponent(edge_entity, api.type.ComponentType.BASE_EDGE)
	return with_player_owned(segment, edge_entity)
end

local function has_edge_objects(...)
	for i = 1, select("#", ...) do
		if #select(i, ...).objects > 0 then return true end
	end
	return false
end

--- Plan to move `late`'s portal level with `early`'s, or nil if the pair does not qualify.
-- A plan is a table with the fields: late, early, t (parameter of the new portal position on
-- late's open-air edge), stagger, spacing.
function alignment.plan(late, early)
	if late.tunnel.typeIndex ~= early.tunnel.typeIndex then return nil end
	if late.inward.x * early.inward.x + late.inward.y * early.inward.y < MIN_PARALLEL_DOT then return nil end
	if math.abs(late.position.z - early.position.z) > MAX_HEIGHT_DIFF then return nil end

	local outer = late.outer
	local t, spacing = curve.project(outer, early.position)
	if spacing < MIN_SPACING or spacing > MAX_SPACING then return nil end

	local portal_t = outer.node0 == late.node and 0 or 1
	local stagger = curve.arc_length(outer, math.min(t, portal_t), math.max(t, portal_t))
	if stagger < MIN_STAGGER or stagger > MAX_STAGGER then return nil end

	-- The new portal must lie inside the open-air edge; otherwise the neighbour's portal is beyond
	-- this edge and the track is left alone.
	local from_start = curve.arc_length(outer, 0, t)
	if from_start < MIN_STAGGER or curve.arc_length(outer, 0, 1) - from_start < MIN_STAGGER then return nil end

	if has_edge_objects(outer, late.tunnel, early.outer, early.tunnel) then
		logger.info("skipped: portals", late.node, early.node, "have signals or waypoints next to them")
		return nil
	end

	return { late = late, early = early, t = t, stagger = stagger, spacing = spacing }
end

--- Proposal that executes `plan`:
--  * late's open-air edge is shortened to end at the new portal (exact sub-curve),
--  * late's tunnel edge is extended to start there and the old portal node is removed
--    (a short tunnel piece in front of the old portal would still leave two portals),
--  * early's edges at its portal are re-added unchanged, so the engine sees both tracks in one
--    build; otherwise it rejects the moved portal as a collision with early's strip.
function alignment.make_proposal(plan)
	local late, early, t = plan.late, plan.early, plan.t
	local outer, tunnel, node = late.outer, late.tunnel, late.node
	local position, derivative = curve.point(outer, t)
	local portal_at_start = outer.node0 == node
	local inward = curve.unit(portal_at_start and derivative * -1 or derivative)

	local new_node = api.type.NodeAndEntity.new()
	new_node.entity = -3
	new_node.comp.position = position

	local outer_segment = new_segment(-1, late.outer_edge)
	if portal_at_start then
		outer_segment.comp.node0 = -3
		outer_segment.comp.position0 = position
		outer_segment.comp.tangent0 = derivative * (1 - t)
		outer_segment.comp.tangent1 = outer.tangent1 * (1 - t)
	else
		outer_segment.comp.node1 = -3
		outer_segment.comp.position1 = position
		outer_segment.comp.tangent0 = outer.tangent0 * t
		outer_segment.comp.tangent1 = derivative * t
	end

	-- The extension is a few metres of the open-air curve, so one Hermite segment with the
	-- original end directions fits closely.
	local length = plan.stagger + curve.arc_length(tunnel, 0, 1)
	local tunnel_segment = new_segment(-2, late.tunnel_edge)
	if tunnel.node0 == node then
		tunnel_segment.comp.node0 = -3
		tunnel_segment.comp.position0 = position
		tunnel_segment.comp.tangent0 = inward * length
		tunnel_segment.comp.tangent1 = curve.unit(tunnel.tangent1) * length
	else
		tunnel_segment.comp.node1 = -3
		tunnel_segment.comp.position1 = position
		tunnel_segment.comp.tangent0 = curve.unit(tunnel.tangent0) * length
		tunnel_segment.comp.tangent1 = inward * -length
	end

	local proposal = api.type.SimpleProposal.new()
	-- List fields of engine objects are copies: always assign whole lists.
	proposal.streetProposal.edgesToRemove = { late.outer_edge, late.tunnel_edge, early.outer_edge, early.tunnel_edge }
	proposal.streetProposal.nodesToRemove = { node }
	proposal.streetProposal.nodesToAdd = { new_node }
	proposal.streetProposal.edgesToAdd = {
		outer_segment,
		tunnel_segment,
		new_segment(-4, early.outer_edge),
		new_segment(-5, early.tunnel_edge),
	}
	return proposal
end

--- Plan for the portal at `node` and the first qualifying neighbour, or nil.
-- Portals in `handled` are skipped, and the pair of a returned plan is added to it: proposals
-- are built from the current network, so two proposals for one pair would fight over the same,
-- by then removed, edges.
function alignment.plan_around(node, handled)
	if handled[node] then return nil end
	local origin = portal.at_node(node)
	if not origin then return nil end
	for _, line in ipairs(logger.DEBUG and portal.describe_strips(origin) or {}) do
		logger.debug(line)
	end

	for _, other in ipairs(portal.neighbours(origin, alignment.SEARCH_RADIUS)) do
		if not handled[other.node] then
			local plan = alignment.plan(origin, other) or alignment.plan(other, origin)
			if plan then
				handled[origin.node], handled[other.node] = true, true
				return plan
			end
		end
	end
	return nil
end

return alignment
