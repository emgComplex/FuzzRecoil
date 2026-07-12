fuzz_recoil = { version = "a4" }
---@diagnostic disable: lowercase-global
----Imports
local utils = fuzz_recoil_utils
local cvter = fuzz_recoil_converter
local logger = fuzz_recoil_logger
---
cur_wpn = nil
cur_cast_wpn = nil
local player = nil
local allowed_kinds = {
	w_pistol = true,
	w_rifle = true,
	w_shotgun = true,
	w_sniper = true,
	w_smg = true,
}

wpn_info = {
	cam_dispersion = 0,
	cam_dispersion_inc = 0,
	zoom_cam_dispersion = 0,
	zoom_cam_dispersion_inc = 0,
	cam_step_angle_horz = 0,
	cam_relax_speed = 0,
	inv_weight = 0,
	rpm = 600,
}
settings = {
	debug_mode = fuzz_dev and true or false,

	--TODO:
	recoil_v_scale = 1,
	recoil_h_scale = 1,
	recoil_cam_scale = 1,
	increase_rate_scale = 1,
	handling_speed_scale = 1,
	--The higher the sharper, the lower the smoother (and softer)
	cam_drag = 12,
	bolt_action_Y_lift = true,
}
config = {
	max_hud_rot = vector():set(3, 3, 0),
	max_hud_pos = vector():set(0.0025, 0.0035, 0),
	base_cam_return_speed = 4.0,
	min_cam_return_step = 0.0045,

	return_spring = 150,
	return_damping = 15.0,
	smooth_firing = 4.5,
	smooth_return = 10,

	firing_handling_ease = utils.simple_ease:new(1, 1, 0.2, 4),
	idle_handling_ease = utils.simple_ease:new(-1, -1, 0.2, 6),

	--NOGUI
	sniper_idle_handling = { offset = 0.2, intensity = 0.8 },
	pitch_expansion = 1.5,
}
wpn_profile = {
	is_bolt_action = false,
	cam_recoil_power = 4,
	cam_return_speed = 1,
	--TODO:
	--zoom_scale_ratio

	shot_pitch = 15,
	shot_pos_y = -0.04,
	shot_yaw = 15,
	shot_pos_x = 0.0006,

	pull_force = 1.5,
	firing_damping = 1.0,
	-- hud_return_speed = 1,

	handling_speed = 0.5,

	-- shot_delay
	should_shot_delay = false,
	shot_delay_time = 0.4,
	shot_cam_impulse_factor = 0.2,

	--TODO:NOT IMPLEMENTED
	increase_rate = 0,
	-- mass_inertia = -1,
	-- hidden vars
	fire_interval = 0.1,
}
state = {
	active = false,
	is_firing = false,
	handling_power = 0.0,
	--TODO: duration or ? we need a way to achieve recoil expansion
	--i don't like duration at all,too "linear-like"
	--maybe an  arm muscle (or aimming) stamina ,
	-- cur_aim_state = 0
	--no need to reset
	cur_wpn_id = 0,
}
local shot_delay_table = {
	w_sniper = { rpm = 60, cam_impulse = 1 },
	w_shotgun = { rpm = 250, cam_impulse = 0.7 },
	w_pistol = { rpm = 340, cam_impulse = 0.4 },
}

sim_firing = false
sim_timer = 0.0
debug_var = {
	bool0 = false,
	bool1 = true,
	float_s1 = 0,
	float_s2 = 0,
	float_x1 = 0,
	float_x2 = 0,
}

local camrc = fuzz_recoil_cam_recoil:new()
local hudrc = fuzz_recoil_hud_recoil

function on_game_start()
	RegisterScriptCallback("actor_on_update", actor_on_update)
	RegisterScriptCallback("actor_on_weapon_before_fire", on_before_fire)
	RegisterScriptCallback("actor_on_weapon_fired", on_fire)
	RegisterScriptCallback("actor_on_changed_slot", function(_, _, _, _)
		--FIXME: i think calling  this will cause cam glith when camera not fully is_cam_returned
		--Never seen it happens since switching animation will give us a natrual delay
		--but if it happens we can fix it with a TimeEvent
		force_reset_recoil()
	end)
end
function actor_on_update()
	on_update(device().time_delta / 1000)
end

function on_before_fire()
	-- logger.dbg("Before Shot ")
	if not state.active then
		--TODO: this is fine,we need a hook when applying upgrades on cur_weapon,to refresh
		state.active = get_current_weapon()
		---check ammo
		-- if cur_cast_wpn:GetAmmoElapsed() == 0 then
		-- 	return
		-- end
	end
end
function on_fire()
	if not state.active then
		--TODO:this is the major impact(0.26ms) on peformance, i mean 0.26ms is not that slow
		--this is bad entry point i think ,but i got nothing better
		--so find out who did the impact(i m guessing cam_effector or hud_adjust.enabled)
		--no need to good deep for optimization ,leave it here for now.
		start_recoil()
	end
	if wpn_profile.shot_dealy_enabled then
		CreateTimeEvent("fuzz_recoil", "bolt_delay_stop", wpn_profile.shot_delay_time, function()
			on_fire_stop()
			return true
		end)
	end
	logger.dbg("Shot ")

	state.is_firing = true

	-- local inertia_modifier = 1.0 / (1.0 + (wpn_profile.mass_inertia * 0.1))

	hudrc.on_fire()
	camrc:on_fire(state.handling_power, wpn_profile.cam_recoil_power, wpn_profile.shot_cam_impulse_factor)
end

function on_update(dt)
	if state.active == false then
		return
	end
	-- logger.dbg("Update")
	if state.is_firing and cur_wpn:get_state() ~= 5 then
		on_fire_stop()
	end
	-- update_sim_shooting(dt)

	update_handling_power(dt)
	local hud_returned = hudrc.update(dt, state.is_firing and state.handling_power or nil)
	local cam_returned = camrc:update(dt, state.is_firing)
	if state.handling_power <= 0 and hud_returned and cam_returned then
		reset_recoil()
	end
end
function on_fire_stop()
	state.is_firing = false
	sim_firing = false
	logger.dbg("Fire stopped")
end

function update_handling_power(dt)
	if state.is_firing then
		state.handling_power = utils.math_clamp(config.firing_handling_ease:update(state.handling_power, dt), 0, 1)
	else
		-- state.handling_power = 0
		state.handling_power = utils.math_clamp(config.idle_handling_ease:update(state.handling_power, dt), 0, 1)
	end
end
function update_sim_shooting(dt)
	if sim_firing then
		sim_timer = sim_timer - dt
		if sim_timer <= 0 then
			on_fire_stop()
		else
			if math.modf(sim_timer / 0.08) ~= math.modf((sim_timer + dt) / 0.08) then
				on_fire()
			end
		end
	end
end

--PERF:smart_cast everytime or cached table?
--i think cached table is better ,but we still have to update the profile evertime
function init_weapon(wpn_sec)
	collect_wpn_info(wpn_sec)
	remove_vanilla_cam_recoil()

	-- inil some recoil paramete from here
	wpn_profile.fire_interval = 60 / wpn_info.rpm
	config.firing_handling_ease:set_speed(wpn_profile.handling_speed)
	config.idle_handling_ease:set_speed(wpn_profile.handling_speed)

	if wpn_profile.is_bolt_action then
		config.idle_handling_ease.intensity = config.sniper_idle_handling.intensity
		config.idle_handling_ease.offset = config.sniper_idle_handling.offset
	else
		config.idle_handling_ease:reset()
	end

	-- NOTE: or we can just check available firemodes?
	-- REFT: look at this mess...move this to converter
	wpn_profile.shot_dealy_enabled = false
	wpn_profile.shot_cam_impulse_factor = 0.2

	local skind = shot_delay_table[wpn_info.kind]
	if skind and wpn_info.rpm <= skind.rpm then
		wpn_profile.shot_dealy_enabled = true
		wpn_profile.shot_delay_time = utils.math_clamp(wpn_profile.fire_interval, 0.1, 0.5)
		wpn_profile.shot_cam_impulse_factor = skind.cam_impulse
	end

	camrc:init(wpn_profile.cam_return_speed, wpn_profile.shot_dealy_enabled and "cubic" or "exp")
	hudrc.init(wpn_sec, wpn_profile)

	logger.dbg("Initialize weapon")
end
function start_recoil()
	state.active = true
	camrc:start()
	hudrc.start()
	RemoveTimeEvent("fuzz_recoil", "bolt_delay")
	logger.dbg("Initialize Recoil")
end

function reset_recoil()
	state.active = false
	state.is_firing = false
	state.handling_power = 0

	camrc.remove_cam_fx()
	hudrc.disable_hud_adjust()
	RemoveTimeEvent("fuzz_recoil", "bolt_delay")

	logger.dbg("reset recoil")
end
function force_reset_recoil()
	camrc:stop()
	hudrc.stop()
	reset_recoil()
end

--------------------------------------
---Feat
--------------------------------------
function get_current_weapon()
	player = db.actor
	if not player then
		return false
	end
	cur_wpn = player:active_item()
	if not cur_wpn then
		return false
	end
	local new_id = cur_wpn:id()
	if state.cur_wpn_id == new_id then
		return state.active
	end
	--NOTE: give the previous weapon its vanilla cam recoil back,
	--otherwise re-equipping it would collect our zeroed values
	restore_vanilla_cam_recoil()
	state.cur_wpn_id = new_id
	local wpn_sec = cur_wpn:section()
	local flag, kind = should_active(wpn_sec)
	if flag then
		logger.dbg("active:" .. kind)
	else
		logger.dbg("Should not active:" .. kind)
		return false
	end
	cur_cast_wpn = cur_wpn:cast_Weapon()
	if not cur_cast_wpn then
		logger.err("Cannot cast Weapon:%s(%s)", tostring(cur_wpn), state.cur_wpn_id)
		return false
	end
	init_weapon(wpn_sec)
	return true
end
function should_active(wpn_sec)
	local kind = utils.get_string(wpn_sec, "kind")
	return allowed_kinds[kind], kind
end

function remove_vanilla_cam_recoil()
	set_vanilla_cam_recoil(cur_cast_wpn, 0, 0, 0, 0)
end
function restore_vanilla_cam_recoil()
	if not cur_cast_wpn then
		return
	end
	--NOTE: setters take raw radians,wpn_info is kept in ini degrees
	set_vanilla_cam_recoil(
		cur_cast_wpn,
		math.rad(wpn_info.cam_dispersion),
		math.rad(wpn_info.cam_dispersion_inc),
		math.rad(wpn_info.zoom_cam_dispersion),
		math.rad(wpn_info.zoom_cam_dispersion_inc)
	)
end
function set_vanilla_cam_recoil(cast_wpn, cam_disp, cam_disp_inc, zoom_cam_disp, zoom_cam_dis_inc)
	cast_wpn:SetCamDispersion(cam_disp)
	cast_wpn:SetCamDispersionInc(cam_disp_inc)
	cast_wpn:SetZoomCamDispersion(zoom_cam_disp)
	cast_wpn:SetZoomCamDispersionInc(zoom_cam_dis_inc)
end

--=========Init Recoil and Info Collection============
--FIXME: only cam_step_angle_horz update with upgrades
--tested with wpn_m98b,there is an unpacked upgrades ltx in
--configs/items/weapons/upgrades/w_m98b_up.ltx
--it does reduce cam_dispersion
--NOTE: engine getters return the live post-upgrade values in radians,
--converter rules are tuned to ini degrees,so convert back with math.deg
function collect_wpn_info(wpn_sec)
	wpn_info.kind = utils.get_string(wpn_sec, "kind")
	if cur_cast_wpn then
		wpn_info.cam_dispersion = math.deg(cur_cast_wpn:GetCamDispersion())
		wpn_info.cam_dispersion_inc = math.deg(cur_cast_wpn:GetCamDispersionInc())
		wpn_info.zoom_cam_dispersion = math.deg(cur_cast_wpn:GetZoomCamDispersion())
		wpn_info.zoom_cam_dispersion_inc = math.deg(cur_cast_wpn:GetZoomCamDispersionInc())
		wpn_info.cam_step_angle_horz = math.deg(cur_cast_wpn:GetCamStepAngleHorz())
		wpn_info.cam_relax_speed = math.deg(cur_cast_wpn:GetCamRelaxSpeed())
		wpn_info.rpm = cur_cast_wpn:RealRPM()
		wpn_info.inv_weight = cur_cast_wpn:Weight()
	else
		--fallback: base section values,no upgrades
		wpn_info.cam_dispersion = utils.get_float(wpn_sec, "cam_dispersion")
		wpn_info.cam_dispersion_inc = utils.get_float(wpn_sec, "cam_dispersion_inc")
		wpn_info.zoom_cam_dispersion = utils.get_float(wpn_sec, "zoom_cam_dispersion")
		wpn_info.zoom_cam_dispersion_inc = utils.get_float(wpn_sec, "zoom_cam_dispersion_inc")
		wpn_info.cam_step_angle_horz = utils.get_float(wpn_sec, "cam_step_angle_horz")
		wpn_info.cam_relax_speed = utils.get_float(wpn_sec, "cam_relax_speed")
		wpn_info.rpm = utils.get_float(wpn_sec, "rpm", 600)
		--NOTE: if we are considering mass effect,we should use engine-getter
		wpn_info.inv_weight = utils.get_float(wpn_sec, "inv_weight", 3)
	end
	try_get_recoil_profile(wpn_sec)
	for k, v in pairs(wpn_info) do
		logger.dbg(type(v) == "number" and "%s:%.6f" or "%s:%s", k, v)
	end
end
function try_get_recoil_profile(wpn_sec)
	local profile = ini_sys:r_string_ex(wpn_sec, "fuzz_recoil", nil)
	if profile then
		wpn_profile.is_bolt_action = utils.get_bool(profile, "is_bolt_action", false)
		wpn_profile.cam_recoil_power = utils.get_float(profile, "cam_recoil_power", 4)
		wpn_profile.cam_return_speed = utils.get_float(profile, "cam_return_speed", 1)

		wpn_profile.shot_pitch = utils.get_float(profile, "shot_pitch", 15)
		wpn_profile.shot_pos_y = utils.get_float(profile, "shot_pos_y", -0.04)
		wpn_profile.shot_yaw = utils.get_float(profile, "shot_yaw", 15)
		wpn_profile.shot_pos_x = utils.get_float(profile, "shot_pos_x", 0)

		wpn_profile.pull_force = utils.get_float(profile, "pull_force", 1.5)
		wpn_profile.firing_damping = utils.get_float(profile, "firing_damping", 1)
		-- wpn_profile.hud_return_speed = utils.get_float(profile, "hud_return_speed", 1)

		wpn_profile.handling_speed = utils.get_float(profile, "handling_speed", 0.5)
		wpn_profile.increase_rate = utils.get_float(profile, "increase_rate", 0)
	else
		cvter.convert(wpn_info, wpn_profile)
	end
end

-- local function get_aim_state()
-- 	-- local is_gl = weapon:weapon_in_grenade_mode()
-- 	if not cur_cast_wpn:IsZoomed() then
-- 		state.cur_aim_state = 0
-- 		return
-- 	end
-- 	state.cur_aim_state = cur_cast_wpn:GetZoomType() + 1
-- 	if state.cur_aim_state > 3 then
-- 		logger.err("Unknown aim state(out of bound):" .. state.cur_aim_state)
-- 		state.cur_aim_state = 0
-- 	end
-- end
--------------------------------------
---Debug
--------------------------------------
