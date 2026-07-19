---@diagnostic disable: undefined-global, duplicate-set-field
local hudrc = fuzz_recoil_hud_recoil
local logger = fuzz_recoil_logger
local wct = weapon_cover_tilt
function on_game_start()
	if not hudrc then
		log("Can't find Fuzz recoil")
		return
	end
	local ori_init = hudrc.init_offset
	if wct then
		hudrc.init_offset = function(wpn_sec, cast_wpn)
			--FIXME: this is just a temp fix,to see if it works.
			ori_init(wpn_sec, cast_wpn)
			wct.reset_wpn_hud(wpn_sec)
		end
		logger.dbg("Use wct to init")
	else
		logger.err("(MASG Patch)Can't find weapon cover tilt")
	end
end
