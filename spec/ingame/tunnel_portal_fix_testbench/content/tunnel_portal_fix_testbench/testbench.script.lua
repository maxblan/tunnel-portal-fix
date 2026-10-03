--- Testbench game script (development only).
--
-- On game start, runs every scenario in turn: builds track A and B (see scenarios.lua), waits
-- for the mod under test to react, then logs "PASS"/"FAIL" with the engine's strips. Progress is
-- kept in the game script state, because the engine runs game scripts in changing Lua states.
-- spec/ingame/run.sh collects the "[tpf_test]" lines.
-- @module tunnel_portal_fix_testbench.testbench
local inspection = require("/tunnel_portal_fix_testbench/inspection.lua")
local scenarios = require("/tunnel_portal_fix_testbench/scenarios.lua")
local site = require("/tunnel_portal_fix_testbench/site.lua")
local track_builder = require("/tunnel_portal_fix_testbench/track_builder.lua")

local testbench = {}

local TAG = "[tpf_test]"
local TUNNEL_TYPES = { "::/infrastructure/tunnel/tunnel_a.tunnel.lua", "::/infrastructure/tunnel/tunnel_a.tunnel" }
local WAIT_START, WAIT_AFTER_A, WAIT_AFTER_B = 60, 30, 100 -- update() calls, 0.2 s game time each

local function log(...)
	local parts = { TAG }
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	debugPrint(table.concat(parts, " "))
end

local function find_resource(repository, names)
	for _, name in ipairs(names) do
		local ok, index = pcall(repository.find, name)
		if ok and index and index >= 0 then return index, name end
	end
	return nil
end

local function finish(run)
	log("DONE")
	run.phase = "done"
end

local function setup(run)
	run.tunnel_type, run.tunnel_name = find_resource(api.res.tunnelTypeRep, TUNNEL_TYPES)
	run.site = site.find(#scenarios)
	if not run.tunnel_type or not run.site then
		log("ERROR setup failed: tunnel_type=" .. tostring(run.tunnel_type), "site=" .. tostring(run.site ~= nil))
		return finish(run)
	end
	log(string.format("START scenarios=%d site=(%.0f,%.0f) flatness=%.1fm tunnel=%s", #scenarios, run.site.x,
		run.site.y, run.site.range, run.tunnel_name))
	run.phase, run.frames = "next", 0
end

local function start_scenario(run)
	run.index = run.index + 1
	local scenario = scenarios[run.index]
	if not scenario then return finish(run) end
	log("SCENARIO", scenario.name)

	local y = site.track_y(run.site, run.index)
	local build = track_builder.new()
	track_builder.add_track(build, run.site, y, 0, run.tunnel_type)
	if scenario.mode == "together" then
		track_builder.add_track(build, run.site, y + scenario.spacing, scenario.stagger, run.tunnel_type)
		run.phase = "built_b"
	else
		run.phase = "built_a"
	end
	build.send()
	run.frames = 0
end

local function build_track_b(run)
	local scenario = scenarios[run.index]
	local y = site.track_y(run.site, run.index)
	local build = track_builder.new()
	if scenario.mode == "rebuild" then
		log("rebuild: re-adding", track_builder.readd_track(build, run.site, y), "edges of track A")
	end
	track_builder.add_track(build, run.site, y + scenario.spacing, scenario.stagger, run.tunnel_type)
	build.send()
	run.phase, run.frames = "built_b", 0
end

local function evaluate(run)
	local scenario = scenarios[run.index]
	local outcome, details = inspection.evaluate(scenario, run.site.x, site.track_y(run.site, run.index))
	log(outcome == scenario.expect and "PASS" or "FAIL", scenario.name, "expected=" .. scenario.expect,
		"got=" .. outcome, details)
	run.phase, run.frames = "next", 0
end

local function step(run)
	run.frames = run.frames + 1
	if run.phase == "wait" and run.frames >= WAIT_START then
		setup(run)
	elseif run.phase == "next" then
		start_scenario(run)
	elseif run.phase == "built_a" and run.frames >= WAIT_AFTER_A then
		build_track_b(run)
	elseif run.phase == "built_b" and run.frames >= WAIT_AFTER_B then
		evaluate(run)
	end
end

function testbench.update(_user_params, state, _dt)
	local run = state:get() or {}
	if not run.phase then
		run.phase, run.frames, run.index = "wait", 0, 0
		log("update running")
	end
	if run.phase == "done" then return end

	local ok, err = pcall(step, run)
	if not ok then
		log("ERROR", err)
		finish(run)
	end
	state:set(run)
end

function testbench.handleEvent()
end

--- A new game starts paused, and update() only runs while the simulation runs.
function testbench.guiUpdate(_user_params, _state, gui_state)
	local g = gui_state:get() or {}
	if g.unpaused then return end
	api.cmd.sendCommand(api.cmd.makeGameSetSpeedCmd(1))
	g.unpaused = true
	gui_state:set(g)
	log("gui: unpaused the simulation")
end

-- The engine loads resource files (unlike modules loaded with require) by calling the global
-- data(); see base/init.lua.
function data()
	return testbench
end
