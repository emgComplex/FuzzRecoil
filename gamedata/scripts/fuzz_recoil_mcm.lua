local defaults = {
	debug_mode = false,
	recoil_cam_scale = 0.1,
	recoil_h_scale = 0.1,
	handling_speed_scale = 0,
	impulse_fatigue_ratio = 0.25,
	cam_drag = 12,
	bolt_action_Y_lift = true,
	use_zoom_ratio = false,
	hud_kick_v2 = false,
	use_bloom = true,
}

function on_option_change()
	load_settings()
	fuzz_recoil.apply_settings()
end

function get_config(key)
	if ui_mcm then
		local val = ui_mcm.get("fuzz_recoil/" .. key)
		if val ~= nil then
			return val
		end
	end
	return defaults[key]
end

function load_settings()
	for k, v in pairs(defaults) do
		fuzz_recoil.settings[k] = get_config(k)
	end
end

function on_game_start()
	RegisterScriptCallback("on_option_change", on_option_change)
	on_option_change()
end

--stylua: ignore start
function on_mcm_load()
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
