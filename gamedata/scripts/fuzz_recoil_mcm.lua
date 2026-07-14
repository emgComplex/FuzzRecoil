local logger = fuzz_recoil_logger
---@class fuzz_recoil_mcm
---@field debug_mode boolean
---@field recoil_cam_scale number
---@field recoil_h_scale number
---@field handling_speed_scale number
---@field impulse_fatigue_ratio number
---@field cam_drag number
---@field bolt_action_Y_lift boolean
---@field hud_kick_v2 boolean
---@field use_bloom boolean
---@field use_zoom_ratio boolean
---@field use_pitch_frac boolean
---@field use_addon_ammo_koefs boolean
---@field use_cam_max_angle boolean
---@field recoil_v_scale number
local M = {}
_G.fuzz_recoil_mcm = M

local defaults = {
	debug_mode = false,
	--Global vertical recoil additional scale,
	--positive increases, negative decreases , 0 means default
	---(-0,9---2.0)
	recoil_cam_scale = 0.1,
	--Global horizontal recoil additional scale,
	--positive increases, negative decreases , 0 means default
	---(-0,9---2.0)
	recoil_h_scale = 0.1,
	--Global recoil handling additional scale,
	--positive increases, negative decreases , 0 means default
	--(-0,9---2.0)
	handling_speed_scale = 0,
	--how fast fatigue increases,higher than 0.15 is recommanded,0 to turn it off
	--(0-0.3)
	impulse_fatigue_ratio = 0.25, --cam_impulse/2/10 most gun impulse landed around 2
	--Camera drag for bolt-action weapon
	--The higher the sharper, the lower the smoother (and softer)
	--(8-20)
	cam_drag = 12,
	--Bolt Action will have be lifted on y-axis
	bolt_action_Y_lift = true,
	--NOTE: EXPERIMENTAL
	--tarkov style hud kick, instant displacement with eased recovery
	hud_kick_v2 = false,
	--fire bloom, sustained fire and hip stance widen the real bullet cone
	use_bloom = true,
	--gamma zoom values sit at 0.6-0.8 of hip, on would weaken ads below the tune
	use_zoom_ratio = false,
	--NOTE: HIDDEN FROM MCM for now

	--vanilla data extras, off keeps stock feel
	use_pitch_frac = false,
	use_addon_ammo_koefs = false,
	--NOTE: CONSIDER REMOVE

	--Does not fit in current recoil pattern,it looks weird visually
	use_cam_max_angle = false,
	-- verti recoil comes from cam recoil ,
	recoil_v_scale = 0,
}

function on_option_change()
	read_options()
	fuzz_recoil.on_option_change()
end

function get_config(key)
	if ui_mcm then
		local val = ui_mcm.get("fuzz_recoil/" .. key)
		return val
	end
	return defaults[key]
end

function read_options()
	for k, v in pairs(defaults) do
		local result = get_config(k)
		if result then
			M[k] = result
		end
	end
end

function M.on_game_start()
	RegisterScriptCallback("on_option_change", on_option_change)
	on_option_change()
end

--stylua: ignore start
function M.on_mcm_load()
    return {
        id = "fuzz_recoil",
        sh = true,
        gr = {
            { id = "title", type = "slide", link = "ui_options_slider_player", text = "ui_mcm_fuzz_recoil_title", size = {512, 50}, spacing = 20 },
            { id = "debug_mode", type = "check", val = 1, def = defaults.debug_mode },
            { id = "recoil_group_title", type = "line" },
            { id = "recoil_cam_scale", type = "track", val = 2, min = -0.9, max = 2.0, step = 0.05, def = defaults.recoil_cam_scale },
            { id = "recoil_h_scale", type = "track", val = 2, min = -0.9, max = 2.0, step = 0.05, def = defaults.recoil_h_scale },
            { id = "handling_speed_scale", type = "track", val = 2, min = -0.9, max = 2.0, step = 0.05, def = defaults.handling_speed_scale },
            { id = "impulse_fatigue_ratio", type = "track", val = 2, min = 0.0, max = 0.3, step = 0.01, def = defaults.impulse_fatigue_ratio },
            { id = "use_zoom_ratio", type = "check", val = 1, def = defaults.use_zoom_ratio },
            { id = "bolt_cam_group_line", type = "line" },
            { id = "cam_drag", type = "track", val = 2, min = 8, max = 20, step = 1, def = defaults.cam_drag },
            { id = "bolt_action_Y_lift", type = "check", val = 1, def = defaults.bolt_action_Y_lift },
            { id = "experimental_group_title", type = "title",align = "l",text = "ui_mcm_fuzz_recoil_experimental_group_title" },
            { id = "experimental_group_line", type = "line" },
            { id = "use_bloom", type = "check", val = 1, def = defaults.use_bloom },
            { id = "hud_kick_v2", type = "check", val = 1, def = defaults.hud_kick_v2 },
        }
    }
end
--stylua: ignore end
