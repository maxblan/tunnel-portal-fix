local mock_engine = require("mock_engine")

-- Portal positions (one open-air and one tunnel edge) on the track at lateral offset y.
local function portals_at(world, y)
	local result = {}
	for id, node in pairs(world.nodes) do
		if math.abs(node.position.y - y) < 0.01 then
			local edges = world.node_edges(id)
			local types = {}
			for _, edge in ipairs(edges) do types[world.edges[edge].type] = true end
			if #edges == 2 and types[mock_engine.NORMAL] and types[mock_engine.TUNNEL] then
				result[#result + 1] = node.position
			end
		end
	end
	return result
end

describe("portal_align game script", function()
	local world, game

	before_each(function()
		world = mock_engine.new()
		game = mock_engine.new_game(world, mock_engine.load_game_script())
		game.frame() -- the first update subscribes to events
	end)

	it("subscribes to the build and align events on its first update", function()
		assert.truthy(game.state.subscriptions.onPostBuildProposal)
		assert.truthy(game.state.subscriptions["tunnel_portal_fix.align"])
	end)

	describe("with a parallel track whose portal lies 10 m further in", function()
		local a, b

		before_each(function()
			a = world.straight_tunnel_track(0, 0)
			b = world.straight_tunnel_track(5, 10)
		end)

		it("waits while the track tool is open and aligns once it is closed", function()
			-- observed: with the track tool open the game reports these tool ids
			world.active_tools = { "Construction", "variant-tracks", "construction-menu-tracks" }
			game.player_built({ b.outer, b.tunnel })
			game.run(10)
			assert.are.equal(0, #world.applied, "proposals while the tool is open")

			world.active_tools = { "EntityDetailsTool" }
			game.run(5)
			assert.are.equal(1, #world.applied, "proposals after closing the tool")
		end)

		it("moves the later portal level with the neighbour and removes the old portal node", function()
			game.player_built({ b.outer, b.tunnel })
			game.run(5)

			local portals = portals_at(world, 5)
			assert.are.equal(1, #portals, "portals on track B")
			assert.near(0, portals[1].x, 0.05, "portal x")
			assert.is_nil(world.nodes[b.portal], "old portal node")
			assert.truthy(world.nodes[b.far] and world.nodes[b.start], "far nodes are kept")
			local far_edges = world.node_edges(b.far)
			assert.are.equal(1, #far_edges, "tunnel still reaches the far node")
			assert.are.equal(mock_engine.TUNNEL, world.edges[far_edges[1]].type)
			assert.are.equal(7, world.edges[far_edges[1]].typeIndex, "tunnel type kept")
		end)

		it("keeps the open-air edge's exact shape and lets the tunnel tangents follow the track", function()
			game.player_built({ b.outer, b.tunnel })
			game.run(5)

			local outer = world.edges[world.node_edges(b.start)[1]]
			assert.near(100, outer.tangent0.x, 0.5, "outer tangent0")
			assert.near(100, outer.tangent1.x, 0.5, "outer tangent1")
			local tunnel = world.edges[world.node_edges(b.far)[1]]
			assert.near(100, tunnel.tangent0.x, 0.5, "tunnel tangent0")
			assert.near(0, tunnel.tangent0.y, 0.01, "tunnel tangent0 y")
			assert.near(100, tunnel.tangent1.x, 0.5, "tunnel tangent1")
		end)

		it("re-adds the neighbour's portal edges unchanged in the same proposal", function()
			local before = { outer = mock_engine.copy(world.edges[a.outer]), tunnel = mock_engine.copy(world.edges[a.tunnel]) }
			game.player_built({ b.tunnel })
			game.run(5)

			local sp = world.applied[1].proposal.streetProposal
			local removed = {}
			for _, edge in ipairs(sp.edgesToRemove) do removed[edge] = true end
			assert.truthy(removed[a.outer] and removed[a.tunnel], "neighbour edges are part of the proposal")
			assert.are.equal(4, #sp.edgesToAdd, "added edges")

			local tunnel = world.edges[world.node_edges(a.far)[1]]
			assert.are.equal(before.tunnel.node0, tunnel.node0, "tunnel node0")
			assert.near(before.tunnel.tangent0.x, tunnel.tangent0.x, 1e-6, "tunnel tangent0")
			assert.are.equal(mock_engine.TUNNEL, tunnel.type)
			local outer = world.edges[world.node_edges(a.start)[1]]
			assert.are.equal(before.outer.node1, outer.node1, "outer node1")
			assert.are.equal(mock_engine.NORMAL, outer.type)
		end)

		it("aligns an existing later track when the player builds the earlier one", function()
			game.player_built({ a.outer, a.tunnel })
			game.run(5)
			assert.near(0, portals_at(world, 5)[1].x, 0.05, "track B portal x")
			assert.near(0, portals_at(world, 0)[1].x, 0.05, "track A untouched")
		end)

		it("sends exactly one proposal when both portals are queued", function()
			game.player_built({ a.tunnel, b.tunnel })
			game.run(5)
			assert.are.equal(1, #world.applied)
		end)

		it("does not loop: the follow-up build event finds nothing to do", function()
			game.player_built({ b.tunnel })
			game.run(30)
			assert.are.equal(1, #world.applied)
		end)

		it("leaves the pair alone when signals sit next to its portal", function()
			world.edges[b.outer].objects = { { 1234, 2 } }
			game.player_built({ b.tunnel })
			game.run(5)
			assert.are.equal(0, #world.applied)
		end)

		it("leaves the pair alone when signals sit next to the neighbour's portal", function()
			world.edges[a.outer].objects = { { 1234, 2 } }
			game.player_built({ b.tunnel })
			game.run(5)
			assert.are.equal(0, #world.applied)
		end)

		it("leaves the pair alone when the tunnel types differ", function()
			world.edges[b.tunnel].typeIndex = 3
			game.player_built({ b.tunnel })
			game.run(5)
			assert.are.equal(0, #world.applied)
		end)

		it("skips queued nodes that were removed before the alignment ran", function()
			world.active_tools = { "Construction" }
			game.player_built({ b.tunnel })
			game.run(2)
			-- The player bulldozes track B while the tool is still open.
			world.edges[b.tunnel], world.edges[b.outer] = nil, nil
			world.nodes[b.portal], world.nodes[b.far], world.nodes[b.start] = nil, nil, nil
			world.active_tools = { "EntityDetailsTool" }
			game.run(5)
			assert.are.equal(0, #world.applied)
		end)
	end)

	it("handles tracks drawn in the opposite direction", function()
		world.straight_tunnel_track(0, 0)
		local b = world.straight_tunnel_track(5, 10, true)
		game.player_built({ b.outer, b.tunnel })
		game.run(5)

		local portals = portals_at(world, 5)
		assert.are.equal(1, #portals, "portals on track B")
		assert.near(0, portals[1].x, 0.05, "portal x")
		local tunnel = world.edges[world.node_edges(b.far)[1]]
		assert.are.equal(b.far, tunnel.node0, "tunnel orientation kept")
		assert.near(-100, tunnel.tangent1.x, 0.5, "tunnel tangent1 points along the edge")
	end)

	it("leaves tunnels entering from opposite sides alone", function()
		world.straight_tunnel_track(0, 0)
		-- Track B is open-air on the +x side and tunnels towards -x.
		local portal = world.add_node(10, 5)
		local outer = world.add_edge(portal, world.add_node(100, 5), mock_engine.NORMAL)
		local tunnel = world.add_edge(world.add_node(-100, 5), portal, mock_engine.TUNNEL)
		game.player_built({ outer, tunnel })
		game.run(5)
		assert.are.equal(0, #world.applied)
	end)

	for _, case in ipairs({
		{ name = "already aligned portals", spacing = 5, stagger = 0.3 },
		{ name = "a stagger above 20 m", spacing = 5, stagger = 30 },
		{ name = "tracks 6 m apart (the engine never merges them)", spacing = 6, stagger = 10 },
		{ name = "tracks 12 m apart", spacing = 12, stagger = 10 },
		{ name = "tracks 2 m apart", spacing = 2, stagger = 10 },
	}) do
		it("leaves alone: " .. case.name, function()
			world.straight_tunnel_track(0, 0)
			local b = world.straight_tunnel_track(case.spacing, case.stagger)
			game.player_built({ b.tunnel })
			game.run(5)
			assert.are.equal(0, #world.applied)
		end)
	end
end)
