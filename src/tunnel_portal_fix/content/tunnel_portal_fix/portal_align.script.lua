--- Game script: aligns staggered entries of parallel rail tunnels after the player builds them.
--
-- Flow:
--  1. handleEvent(onPostBuildProposal) queues the nodes of every new tunnel edge.
--  2. guiUpdate waits until no build tool is open, then asks the engine side to align. The track
--     tool keeps references to the edges it just built and crashes if they disappear while open.
--  3. handleEvent(ALIGN_EVENT) marks the queue ready; update() plans and sends the proposals.
--
-- All progress lives in the game script state: the engine runs game scripts in changing Lua
-- states, so module-level variables do not survive between calls.
-- @module tunnel_portal_fix.portal_align
local alignment = require("/tunnel_portal_fix/alignment.lua")
local logger = require("/tunnel_portal_fix/logger.lua")

local portal_align = {}

local EVENT_ID = "tunnel_portal_fix"
local ALIGN_EVENT = "tunnel_portal_fix.align"
local SUBSCRIPTIONS_VERSION = 2
local TRACK = 1 -- SegmentAndEntity.type

-- With the track tool open the game reports e.g. "Construction,variant-tracks,construction-menu-tracks";
-- with nothing open only the default selection tool. Aligning too late is harmless, too early
-- crashes the track tool.
local IDLE_TOOLS = { EntityDetailsTool = true }

local function is_build_tool_active(tool_ids)
	for _, id in ipairs(tool_ids) do
		if not IDLE_TOOLS[id] then return true end
	end
	return false
end

local function send_proposal(plan)
	logger.info(string.format("aligning portal %d to %d (stagger %.1f m, spacing %.1f m)",
		plan.late.node, plan.early.node, plan.stagger, plan.spacing))
	local context = api.type.Context.new()
	context.player = api.engine.util.getPlayer()
	-- Game scripts may not pass a callback ("Callbacks are currently disallowed"); the engine logs
	-- rejected proposals itself.
	api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(alignment.make_proposal(plan), context, false, true))
end

local function align_pending(pending)
	local handled = {}
	for _, node in ipairs(pending) do
		local ok, result = pcall(alignment.plan_around, node, handled)
		if not ok then
			logger.info("error:", result)
		elseif result then
			send_proposal(result)
		end
	end
end

function portal_align.update(_user_params, state, _dt)
	local s = state:get() or {}
	-- Savegames from earlier versions of this mod already hold older subscriptions.
	if s.subscriptions ~= SUBSCRIPTIONS_VERSION then
		state:subscribeToEvent("onPostBuildProposal")
		state:subscribeToEvent(ALIGN_EVENT)
		s.subscriptions = SUBSCRIPTIONS_VERSION
		state:set(s)
	end

	if not s.ready or not s.pending or #s.pending == 0 then return end
	local pending = s.pending
	s.pending, s.ready = {}, false
	state:set(s)
	align_pending(pending)
end

function portal_align.handleEvent(_user_params, state, _src, id, name, param)
	if id == EVENT_ID and name == ALIGN_EVENT then
		local s = state:get() or {}
		if s.batch == param then
			s.ready = true
			state:set(s)
		end
		return
	end

	if id ~= "apply_command" or name ~= "onPostBuildProposal" then return end
	local street_proposal = param[1] and param[1].proposal
	if not street_proposal then return end

	local s = state:get() or {}
	s.pending = s.pending or {}
	local queued = #s.pending
	for _, segment in ipairs(street_proposal.addedSegments) do
		if segment.type == TRACK and segment.comp.type == api.type["enum"].BaseEdgeType.TUNNEL then
			s.pending[#s.pending + 1] = segment.comp.node0
			s.pending[#s.pending + 1] = segment.comp.node1
		end
	end
	if #s.pending > queued then
		s.batch = (s.batch or 0) + 1
		s.ready = false
		logger.debug("queued", #s.pending - queued, "tunnel nodes")
		state:set(s)
	end
end

function portal_align.guiUpdate(_user_params, state, gui_state)
	local s = state:get() or {}
	if not s.pending or #s.pending == 0 or s.ready then return end

	local g = gui_state:get() or {}
	if g.sent_batch == s.batch then return end

	local tool_ids = api.gui.contextHelper.getIdsOfActiveTool()
	local tools = table.concat(tool_ids, ",")
	if tools ~= g.last_tools then
		logger.debug("waiting for build tools to close; active:", tools)
		g.last_tools = tools
		gui_state:set(g)
	end
	if is_build_tool_active(tool_ids) then return end

	g.sent_batch = s.batch
	gui_state:set(g)
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", EVENT_ID, ALIGN_EVENT, s.batch))
end

-- The engine loads resource files (unlike modules loaded with require) by calling the global
-- data(); see base/init.lua.
function data()
	return portal_align
end
