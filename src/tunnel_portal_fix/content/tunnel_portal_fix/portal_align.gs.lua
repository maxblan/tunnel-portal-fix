-- Game script registration (TF3 resource file; the engine reads the table returned by data()).
function data()
	return {
		updateScript = {
			fileName = "portal_align.script@update",
		},
		handleEventScript = {
			fileName = "portal_align.script@handleEvent",
		},
		guiUpdateScript = {
			fileName = "portal_align.script@guiUpdate",
		},
	}
end
