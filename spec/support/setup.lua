--- Busted helper (see .busted): makes the mod's modules loadable outside the game.
-- Run from the repository root.

package.path = "spec/support/?.lua;" .. package.path

-- Inside the game, require("/x/y.lua") resolves relative to the content folder of the mod that
-- owns the calling file. Mirror that for this mod.
local MOD_CONTENT = "src/tunnel_portal_fix/content"

table.insert(package.searchers, 2, function(name)
	if name:sub(1, 1) ~= "/" then return nil end
	local path = MOD_CONTENT .. name
	local chunk, err = loadfile(path)
	if not chunk then return "\n\tno file '" .. path .. "' (" .. tostring(err) .. ")" end
	return chunk, path
end)
