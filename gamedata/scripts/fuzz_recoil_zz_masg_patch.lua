---@diagnostic disable: undefined-global, duplicate-set-field
local hudrc = fuzz_recoil_hud_recoil
local logger = fuzz_recoil_logger
local wct = weapon_cover_tilt
function on_game_start()
	if not hudrc then
		log("Can't find Fuzz recoil")
		return
	end
	if wct then
		hudrc.set_3db_offsets = wct.reset_wpn_hud
		logger.dbg("Use wct to set 3db offfsets")
	else
		logger.err("(MASG Patch)Can't find weapon cover tilt")
	end
end
