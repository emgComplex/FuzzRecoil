local logger = fuzz_recoil_logger
---@class fuzz_recoil_mcm
---@field debug_mode boolean
---@field recoil_cam_scale number
---@field recoil_h_scale number
---@field fixed_yaw_direction boolean
---@field handling_speed_scale number
---@field cam_restore_speed_scale number
---@field impulse_fatigue_ratio number
---@field pistol_recoil_mul number
---@field bolt_action_recoil_mul number
---@field shotgun_recoil_mul number
---@field cam_drag number
---@field bolt_action_Y_lift boolean
---@field instant_mode boolean
---@field use_bloom boolean
---@field use_punch boolean
---@field punch_legacy boolean
---@field no_cam_restore boolean
---@field use_comp_return boolean
---@field use_addon_ammo_koefs boolean
local M = {}
_G.fuzz_recoil_mcm = M

local defaults = {
	debug_mode = false,
	--Global vertical recoil additional scale,
	--positive increases, negative decreases , 0 means default
	---(-0,9---2.0)
	recoil_cam_scale = 0,
	--Global horizontal recoil additional scale,
	--positive increases, negative decreases , 0 means default
	---(-0,9---2.0)
	recoil_h_scale = 0,
	--Fixed yaw direction if you don't like RNG on horizontal axis
	fixed_yaw_direction = false,
	--Global recoil handling additional scale,
	--positive increases, negative decreases , 0 means default
	--(-0,9---2.0)
	handling_speed_scale = 0,
	--Global camera return speed additional scale
	--positive increases, negative decreases , 0 means default
	cam_restore_speed_scale = 0,
	--how fast fatigue increases,higher than 0.15 is recommanded,0 to turn it off
	--(0-0.3)
	impulse_fatigue_ratio = 0.15, --most gun impulse landed around 2-3
	--per shot punch, fov widen at hip and a positional shove while aiming
	use_punch = false,
	--revert the punch to the prior system, console fov and shove only under true PiP
	punch_legacy = false,
	-- mutilpier for pistol's shot_delay_impulse
	pistol_recoil_mul = 0.15,
	-- mutilpier for shotgun's shot_delay_impulse
	shotgun_recoil_mul = 0.7,
	--mutilpier for sniper's shot_delay_impulse
	bolt_action_recoil_mul = 1,
	--no camera restore at all
	no_cam_restore = false,
	--return floor at the burst start aim, user downpull is not returned again
	use_comp_return = true,
	--Camera drag for bolt-action weapon
	--The higher the sharper, the lower the smoother (and softer)
	--(8-20)
	cam_drag = 12,
	--Bolt Action will have be lifted on y-axis
	bolt_action_Y_lift = true,
	--NOTE: EXPERIMENTAL
	--Hud instant displacement with eased recovery
	instant_mode = false,
	--fire bloom, sustained fire and hip stance widen the real bullet cone
	use_bloom = true,
	--NOTE: HIDDEN FROM MCM for now

	use_addon_ammo_koefs = false,
	--NOTE: CONSIDER REMOVE
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
		if result ~= nil then
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
            { id = "easy", type = "button", functor_ui = { function(gui) apply_preset_by_id("easy", gui) end, }, },
            { id = "noraml", type = "button", functor_ui = { function(gui) apply_preset_by_id("normal", gui) end, }, },
            { id = "hard", type = "button", functor_ui = { function(gui) apply_preset_by_id("hard", gui) end, }, },
            { id = "recoil_group_title", type = "line" },
            { id = "recoil_cam_scale", type = "track", val = 2, min = -0.2, max = 0.6, step = 0.01, def = defaults.recoil_cam_scale },
            { id = "recoil_h_scale", type = "track", val = 2, min = -0.9, max = 0.2, step = 0.01, def = defaults.recoil_h_scale },
            { id = "fixed_yaw_direction", type = "check", val = 1, def = defaults.fixed_yaw_direction },
            { id = "handling_speed_scale", type = "track", val = 2, min = -0.5, max = 1, step = 0.05, def = defaults.handling_speed_scale },
            { id = "cam_restore_speed_scale", type = "track", val = 2, min = -0.5, max = 4, step = 0.05, def = defaults.cam_restore_speed_scale },
            { id = "impulse_fatigue_ratio", type = "track", val = 2, min = 0.0, max = 0.3, step = 0.01, def = defaults.impulse_fatigue_ratio },
            { id = "use_punch", type = "check", val = 1, def = defaults.use_punch },
            { id = "punch_legacy", type = "check", val = 1, def = defaults.punch_legacy },
            { id = "kind_cam_impulse_group_title", type = "title",align = "l",text = "ui_mcm_fuzz_recoil_cam_impulse_group_title" },
            { id = "kind_cam_impulse_group_line", type = "line" },
            { id = "pistol_recoil_mul", type = "track", val = 2, min = 0.01, max = 0.3, step = 0.01, def = defaults.pistol_recoil_mul },
            { id = "shotgun_recoil_mul", type = "track", val = 2, min = 0.05, max = 1.5, step = 0.05, def = defaults.shotgun_recoil_mul },
            { id = "bolt_action_recoil_mul", type = "track", val = 2, min = 0.05, max = 1.5, step = 0.05, def = defaults.bolt_action_recoil_mul },
            { id = "bolt_cam_group_line", type = "line" },
            { id = "cam_drag", type = "track", val = 2, min = 8, max = 20, step = 1, def = defaults.cam_drag },
            { id = "bolt_action_Y_lift", type = "check", val = 1, def = defaults.bolt_action_Y_lift },
            { id = "experimental_group_title", type = "title",align = "l",text = "ui_mcm_fuzz_recoil_experimental_group_title" },
            { id = "experimental_group_line", type = "line" },
            { id = "use_bloom", type = "check", val = 1, def = defaults.use_bloom },
            { id = "no_cam_restore", type = "check", val = 1, def = defaults.no_cam_restore },
            { id = "use_comp_return", type = "check", val = 1, def = defaults.use_comp_return },
            { id = "instant_mode", type = "check", val = 1, def = defaults.instant_mode },
            { id = "debug_mode", type = "check", val = 1, def = defaults.debug_mode },
		}
    }
end
--stylua: ignore end

DIFFICULTY_PRESET = {
	easy = {
		recoil_cam_scale = -0.1,
		recoil_h_scale = -0.1,
		impulse_fatigue_ratio = 0,
	},
	normal = {
		recoil_cam_scale = 0,
		recoil_h_scale = 0,
		impulse_fatigue_ratio = 0.15,
	},
	hard = {
		recoil_cam_scale = 0.15,
		recoil_h_scale = 0.15,
		impulse_fatigue_ratio = 0.22,
	},
}
function apply_preset_by_id(preset_id, gui)
	logger.dbg("Apllying preset" .. preset_id)
	local preset = DIFFICULTY_PRESET[preset_id]
	if not preset then
		logger.err("Wrong Preset ID:" .. preset_id)
		return
	end

	local path = "fuzz_recoil/"

	logger.dbg("before saving")
	for key, value in pairs(preset) do
		ui_mcm.set(path .. key, value)
	end
	on_option_change()
	if gui then
		if gui.owner and gui.owner.SetMsg then
			gui.owner:SetMsg("Difficulty preset applied:" .. preset_id, 3)
		end
		if gui.On_Cancel then
			gui:On_Cancel()
		end
	end
end
