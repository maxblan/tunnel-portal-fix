--- Tagged logging to the game log (stdout.txt).
-- @module tunnel_portal_fix.logger
local logger = {}

local TAG = "[tunnel_portal_fix]"

--- Set to true to log queueing, tool state and the engine's parallel strips.
logger.DEBUG = false

function logger.info(...)
	debugPrint(TAG, ...)
end

function logger.debug(...)
	if logger.DEBUG then debugPrint(TAG, ...) end
end

return logger
