--- In-game scenarios: pairs of parallel tracks that dive into the ground and become tunnels.
--
-- spacing: lateral distance between track A and track B (m).
-- stagger: how far track B's portal lies behind track A's (m).
-- mode:    "together" = A and B in one build;
--          "separate" = A, then B in its own build (like dragging them one after another);
--          "rebuild"  = A, then one build that re-adds A's edges together with B.
-- expect:  "clean"    = every tunnel section at the portals holds both tracks (one wide portal);
--          "separate" = the tracks keep separate sections (too far apart for the engine to merge).
-- @module tunnel_portal_fix_testbench.scenarios
return {
	{ name = "spacing5.0_stagger0_together", spacing = 5.0, stagger = 0, mode = "together", expect = "clean" },
	{ name = "spacing5.0_stagger3_together", spacing = 5.0, stagger = 3, mode = "together", expect = "clean" },
	{ name = "spacing5.0_stagger10_together", spacing = 5.0, stagger = 10, mode = "together", expect = "clean" },
	{ name = "spacing5.2_stagger5_together", spacing = 5.2, stagger = 5, mode = "together", expect = "clean" },
	{ name = "spacing5.0_stagger3_rebuild", spacing = 5.0, stagger = 3, mode = "rebuild", expect = "clean" },
	{ name = "spacing6.0_stagger3_separate", spacing = 6.0, stagger = 3, mode = "separate", expect = "separate" },
}
