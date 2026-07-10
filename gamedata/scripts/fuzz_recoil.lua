fuzz_recoil = { version = "a3" }
---@diagnostic disable: lowercase-global
----Imports
local utils = fuzz_utils or fuzz_recoil_utils.fuzz_utils
local cvter = converter or fuzz_recoil_converter.converter
local logger = logger or fuzz_recoil_logger.logger
---
CAM_FX_ID = 7897
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

	firing_handling_ease = utils.simple_ease:new(1, 0.2, 4),
	idle_handling_ease = utils.simple_ease:new(-1, 0.7, 0.5, "in"),

	--NOGUI
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
	--TODO:NOT IMPLEMENTED
	increase_rate = 0,
	-- mass_inertia = -1,
}
state = {
	active = false,
	is_firing = false,
	handling_power = 0.0,
	--TODO: duration or ? we need a way to achieve recoil expansion

	is_cam_returned = false,
	cam_angle = 0,
	cam_vel = 0.0,

	is_hud_returned = false,
	vel_hud_pos = VEC_ZERO,
	vel_hud_rot = VEC_ZERO,
	hud_pos_raw = VEC_ZERO,
	hud_rot_raw = VEC_ZERO,
	hud_pos_smooth = VEC_ZERO,
	hud_rot_smooth = VEC_ZERO,
	-- cur_aim_state = 0
	--no need to reset
	cur_wpn_id = 0,
	fire_interval = 0.1,
	-- shot_delay
	should_shot_delay = false,
	shot_delay_time = 0.4,
	shot_cam_impulse_factor = 0.2,
}
local shot_delay_table = {
	w_sniper = { rpm = 60, cam_impulse = 1 },
	w_shotgun = { rpm = 250, cam_impulse = 0.7 },
	w_pistol = { rpm = 340, cam_impulse = 0.4 },
}

ori_hand_trs = {
	VEC_ZERO,
	VEC_ZERO,
}
cur_hud_pos = VEC_ZERO
cur_hud_rot = VEC_ZERO
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

function on_game_start()
	RegisterScriptCallback("actor_on_update", actor_on_update)
	RegisterScriptCallback("actor_on_weapon_before_fire", on_before_fire)
	RegisterScriptCallback("actor_on_weapon_fired", on_fire)
end
function actor_on_update()
	on_update(device().time_delta / 1000)
end

function on_before_fire()
	-- logger.dbg("Before Shot ")
	if not state.active then
		--PERF:NEED NEW ENTRY POINT
		--init before fire is difinitely a bad practise,
		--the best entry point is when switching weapon,which i can only hook to it through on_animation_paly
		state.active = get_current_weapon()
		---check ammo
		-- if cur_cast_wpn:GetAmmoElapsed() == 0 then
		-- 	return
		-- end
	end
end
function on_fire()
	--FIXME: this is definately a lazy way
	if not state.active then
		init_recoil()
	end
	if state.should_shot_delay then
		CreateTimeEvent("fuzz_recoil", "bolt_delay_stop", state.shot_delay_time, function()
			on_fire_stop()
			return true
		end)
	end
	logger.dbg("Shot ")

	state.is_firing = true
	state.is_cam_returned = false
	state.is_hud_returned = false

	-- local inertia_modifier = 1.0 / (1.0 + (wpn_profile.mass_inertia * 0.1))

	on_fire_phys()

	local cam_impulse = wpn_profile.cam_recoil_power * (1.0 - state.handling_power) * state.shot_cam_impulse_factor
	state.cam_vel = state.cam_vel + cam_impulse
end
function on_fire_phys()
	state.vel_hud_rot.y = state.vel_hud_rot.y + wpn_profile.shot_pitch
	state.vel_hud_pos.y = state.vel_hud_pos.y + wpn_profile.shot_pos_y

	local yaw_impulse = (math.random() * 2 - 1) * wpn_profile.shot_yaw
	state.vel_hud_rot.x = state.vel_hud_rot.x + yaw_impulse

	--NOTE:count_ratio = 1/20
	local pos_x_impulse = (math.random() * 2 - 1) * wpn_profile.shot_pos_x
	state.vel_hud_pos.x = state.vel_hud_pos.x + pos_x_impulse
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
	if state.is_firing then
		if state.should_shot_delay then
			on_cam_update_cubic(dt)
		else
			on_cam_update(dt)
		end
		on_hud_update_phys(dt)
		return
	else
		if not state.is_cam_returned then
			do_cam_return(dt)
			-- reset_cam_recoil()
		end
		if not state.is_hud_returned then
			do_hud_return_phys(dt)
			-- reset_hud_recoil()
		end
		if state.is_cam_returned and state.is_hud_returned and state.handling_power <= 0 then
			reset_recoil()
		end
	end

	-- logger.dbg(
	-- 	"on_hud_update,pitch:%.5f,ptich vel:%.5f,pos:%.5f,pos_vel:%.5f",
	-- 	dt,
	-- 	state.hud_rot_smooth.y,
	-- 	state.vel_hud_rot.y,
	-- 	state.hud_pos_smooth.y,
	-- 	state.vel_hud_pos.y
	-- )
end
function on_fire_stop()
	state.is_firing = false
	sim_firing = false
	logger.dbg("Fire stopped")
end

--FIXME: should we udpate handling power when system is inactive
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
--TODO: we should desync it
function pos_y_sync_with_cam()
	if state.should_shot_delay then
		--PERF: should cached once code is stablelized
		y_impulse = wpn_profile.is_bolt_action and math.abs(wpn_profile.shot_pos_y) * 2 or wpn_profile.shot_pos_y
		state.hud_pos_raw.y = state.cam_angle * y_impulse
	end
end
function on_hud_update_phys(dt)
	local pull_strength = wpn_profile.pull_force * state.handling_power

	apply_recoil_forces(dt, pull_strength, wpn_profile.firing_damping)

	-- limit before smooth
	state.hud_rot_raw:clamp(config.max_hud_rot)
	state.hud_pos_raw:clamp(config.max_hud_pos)

	pos_y_sync_with_cam()
	apply_simple_smooth(dt, config.smooth_firing)

	set_hud_offset(state.hud_pos_smooth, state.hud_rot_smooth)
end
function do_hud_return_phys(dt)
	local spring = config.return_spring
	local damping = config.return_damping

	apply_spring_vec(state.hud_pos_raw, state.vel_hud_pos, dt, spring, damping)
	apply_spring_vec(state.hud_rot_raw, state.vel_hud_rot, dt, spring, damping)

	local threshold_return = 0.001
	if state.hud_rot_raw:magnitude() < threshold_return and state.hud_pos_raw:magnitude() < threshold_return then
		reset_hud_recoil()
		return
	end

	pos_y_sync_with_cam()

	apply_simple_smooth(dt, config.smooth_return)
	set_hud_offset(state.hud_pos_smooth, state.hud_rot_smooth)
end

debug_var.float_x1 = 12
debug_var.float_x2 = 15
function on_cam_update(dt)
	if state.is_firing and math.abs(state.cam_vel) > 0.01 then
		-- state.cam_vel = state.cam_vel * (1.0 - dt * debug_var.float_x2)
		local decay = math.exp(-dt * debug_var.float_x1)
		local step = state.cam_vel * (1 - decay) / debug_var.float_x2
		state.cam_vel = state.cam_vel * decay
		state.cam_angle = state.cam_angle + step
		set_player_angle(state.cam_angle)
	end
end
function on_cam_update_cubic(dt)
	if state.is_firing and math.abs(state.cam_vel) > 0.01 then
		local drag = settings.cam_drag * math.sqrt(math.abs(state.cam_vel))
		state.cam_vel = state.cam_vel * math.exp(-drag * dt)
		local step = state.cam_vel * dt
		state.cam_angle = state.cam_angle + step
		set_player_angle(state.cam_angle)
	end
end
function on_cam_update_spring(dt)
	if state.is_firing and math.abs(state.cam_vel) > 0.01 then
		state.cam_angle, state.cam_vel = apply_spring(state.cam_angle, state.cam_vel, dt, debug_var.float_x1)
		set_player_angle(state.cam_angle)
	end
end
--NOTE: min_step is the best i can got...still can't get the final phase right.
--TODO: maybe try simple_ease and lerp the vel to a min value?,it could be more natrual when the angle is high.
function do_cam_return(dt)
	-- logger.dbg("cam returning")
	if state.cam_angle <= config.min_cam_return_step then
		reset_cam_recoil()
		return
	end
	--TODO:Bonus ,mass, upgrades?
	--refactor this to state
	local speed_factor = config.base_cam_return_speed + wpn_profile.cam_return_speed
	local lerp_factor = 1.0 - math.exp(-speed_factor * dt)
	local step = state.cam_angle * lerp_factor

	local min_step = config.min_cam_return_step
	local final_step = math.max(step, min_step)
	--NOTE:vel is actually step when returning ,im just lazy ,its easy to debug
	state.cam_vel = final_step
	state.cam_angle = state.cam_angle - final_step
	set_player_angle(state.cam_angle)
end

--PERF:smart_cast everytime or cached table?
function init_weapon(wpn_sec)
	collect_wpn_info(wpn_sec)
	init_hud_adjust(wpn_sec)
	remove_vanilla_cam_recoil()

	-- inil some recoil paramete from here
	state.fire_interval = 60 / wpn_info.rpm
	config.firing_handling_ease:set_speed(wpn_profile.handling_speed)
	config.idle_handling_ease:set_speed(wpn_profile.handling_speed * -1)

	-- NOTE: or we can just check available firemodes?
	-- REFT: look at this mess...
	state.should_shot_delay = false
	state.shot_cam_impulse_factor = 0.2

	local skind = shot_delay_table[wpn_info.kind]
	if skind and wpn_info.rpm <= skind.rpm then
		state.should_shot_delay = true
		state.shot_delay_time = utils.math_clamp(state.fire_interval, 0.1, 0.5)
		state.shot_cam_impulse_factor = skind.cam_impulse
	end

	logger.dbg("Initialize weapon")
end
function init_recoil()
	state.active = true
	reset_hud_hand()
	enable_hud_adjust()
	if not level.check_cam_effector(CAM_FX_ID) then
		level.add_cam_effector("camera_effects\\onerad.anm", 7897, true, "", 0, true, 0.0001)
	end
	RemoveTimeEvent("fuzz_recoil", "bolt_delay")
	logger.dbg("Initialize Recoil")
end

function reset_cam_recoil()
	set_player_angle(0.0001)
	state.is_cam_returned = true
	state.cam_angle = 0
	state.cam_vel = 0
end
function reset_hud_recoil()
	logger.dbg("reset hud recoil")
	state.is_hud_returned = true

	state.vel_hud_rot = VEC_ZERO
	state.vel_hud_pos = VEC_ZERO

	state.hud_pos_raw = VEC_ZERO
	state.hud_pos_smooth = VEC_ZERO
	state.hud_rot_raw = VEC_ZERO
	state.hud_rot_smooth = VEC_ZERO

	reset_hud_hand()
end
function reset_recoil()
	state.active = false
	state.is_firing = false
	state.handling_power = 0

	disable_hud_adjust()
	if level.check_cam_effector(CAM_FX_ID) then
		level.remove_cam_effector(7897)
	end
	RemoveTimeEvent("fuzz_recoil", "bolt_delay")

	logger.dbg("reset recoil")
end
function force_reset_recoil()
	reset_cam_recoil()
	reset_hud_recoil()
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
	set_vanilla_cam_recoil(
		cur_cast_wpn,
		wpn_info.cam_dispersion,
		wpn_info.cam_dispersion_inc,
		wpn_info.zoom_cam_dispersion,
		wpn_info.zoom_cam_dispersion_inc
	)
end
function set_vanilla_cam_recoil(cast_wpn, cam_disp, cam_disp_inc, zoom_cam_disp, zoom_cam_dis_inc)
	cast_wpn:SetCamDispersion(cam_disp)
	cast_wpn:SetCamDispersionInc(cam_disp_inc)
	cast_wpn:SetZoomCamDispersion(zoom_cam_disp)
	cast_wpn:SetZoomCamDispersionInc(zoom_cam_dis_inc)
end

function set_player_angle(angle)
	if not player then
		logger.err("player not found")
		return
	end
	level.set_cam_effector_factor(7897, math.max(0.0001, math.min(angle, 0.999)))
end

function enable_hud_adjust()
	hud_adjust.enabled(true)
end
function disable_hud_adjust()
	hud_adjust.enabled(false)
end
function set_hud_hand(pos, rot)
	hud_adjust.set_vector(0, 0, pos.x, pos.y, pos.z)
	hud_adjust.set_vector(1, 0, rot.x, rot.y, rot.z)
end
function apply_cur_hud_hand()
	set_hud_hand(cur_hud_pos, cur_hud_rot)
end
function update_cur_hud_hand_by(pos, rot)
	cur_hud_pos:add(pos)
	cur_hud_rot:add(rot)
end
function set_hud_offset(pos, rot)
	cur_hud_pos = vector():set(ori_hand_trs[1]):add(pos)
	cur_hud_rot = vector():set(ori_hand_trs[2]):add(rot)
	apply_cur_hud_hand()
end
function reset_hud_hand()
	cur_hud_pos = vector():set(ori_hand_trs[1])
	cur_hud_rot = vector():set(ori_hand_trs[2])
	apply_cur_hud_hand()
end
--=========Init Recoil and Info Collection============
--NOTE:this is safer,cause we are changing cam_recoil
--FIXME: this doesn't respect upgrades!
function collect_wpn_info(wpn_sec)
	wpn_info.kind = utils.get_string(wpn_sec, "kind")
	wpn_info.cam_dispersion = utils.get_float(wpn_sec, "cam_dispersion")
	wpn_info.cam_dispersion_inc = utils.get_float(wpn_sec, "cam_dispersion_inc")
	wpn_info.zoom_cam_dispersion = utils.get_float(wpn_sec, "zoom_cam_dispersion")
	wpn_info.zoom_cam_dispersion_inc = utils.get_float(wpn_sec, "zoom_cam_dispersion_inc")
	wpn_info.cam_step_angle_horz = utils.get_float(wpn_sec, "cam_step_angle_horz")
	wpn_info.cam_relax_speed = utils.get_float(wpn_sec, "cam_relax_speed")
	wpn_info.inv_weight = utils.get_float(wpn_sec, "inv_weight", 3)
	wpn_info.rpm = utils.get_float(wpn_sec, "rpm", 600)
	try_get_recoil_profile(wpn_sec)
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
function init_hud_adjust(wpn_sec)
	hud_adjust.enabled(true)
	local hud = utils.get_string(wpn_sec, "hud")
	local postfix = utils_xml.is_widescreen() and "_16x9" or ""
	local function get_hud_vector(hud_sec, key, v)
		local value = utils.get_string(hud_sec, key .. postfix)
		if value == "" then
			value = utils.get_string(hud_sec, key)
		end
		if value == "" then
			return v.def or VEC_ZERO
		end
		return utils_data.string_to_vector(value)
	end
	local function set_hud_vector(hud_sec, key, v)
		local _vec = get_hud_vector(hud_sec, key, v)
		hud_adjust.set_vector(v.idxa, v.idxb, _vec.x, _vec.y, _vec.z)
	end
	ori_hand_trs = {
		get_hud_vector(hud, "hands_position", { def = VEC_ZERO }),
		get_hud_vector(hud, "hands_orientation", { def = VEC_ZERO }),
	}
	--credit:@demonized's weapon tilt cover
	local offset_key_list = {
		["hands_position"] = { idxa = 0, idxb = 0 },
		["hands_orientation"] = { idxa = 1, idxb = 0 },
		["aim_hud_offset_pos"] = { idxa = 0, idxb = 1 },
		["aim_hud_offset_rot"] = { idxa = 1, idxb = 1 },
		["gl_hud_offset_pos"] = { idxa = 0, idxb = 2 },
		["gl_hud_offset_rot"] = { idxa = 1, idxb = 2 },
		["aim_hud_offset_alt_pos"] = { idxa = 0, idxb = 3 },
		["aim_hud_offset_alt_rot"] = { idxa = 1, idxb = 3 },
		["lowered_hud_offset_pos"] = { idxa = 0, idxb = 4 },
		["lowered_hud_offset_rot"] = { idxa = 1, idxb = 4 },
		["fire_point"] = { idxa = 0, idxb = 10 },
		["fire_point2"] = { idxa = 0, idxb = 11 },
		["fire_direction"] = { def = VEC_Z, idxa = 1, idxb = 10 },
		["shell_point"] = { idxa = 1, idxb = 11 },
		["custom_ui_pos"] = { idxa = 0, idxb = 20 },
		["custom_ui_rot"] = { idxa = 1, idxb = 20 },
		["item_position"] = { idxa = 0, idxb = 12 },
		["item_orientation"] = { idxa = 1, idxb = 12 },
	}
	local value_list = {
		["scope_zoom_factor"] = {},
		["gl_zoom_factor"] = {},
		["scope_zoom_factor_alt"] = {},
		["attach_scale"] = { def = 1 },
	}
	--credit: @MsPizza727
	if MODDED_EXES_VERSION >= 20240412 then
		offset_key_list["base_hud_offset_pos"] = { idxa = 0, idxb = 5 }
		offset_key_list["base_hud_offset_rot"] = { idxa = 1, idxb = 5 }
		offset_key_list["attach_base_hud_offset_pos"] = { idxa = 0, idxb = 6 }
		offset_key_list["attach_base_hud_offset_rot"] = { idxa = 1, idxb = 6 }
		offset_key_list["attach_mount_hud_offset_pos"] = { idxa = 0, idxb = 7 }
		offset_key_list["attach_mount_hud_offset_rot"] = { idxa = 1, idxb = 7 }
	else
		offset_key_list["attach_base_hud_offset_pos"] = { idxa = 0, idxb = 6 }
		offset_key_list["attach_base_hud_offset_rot"] = { idxa = 1, idxb = 6 }
		offset_key_list["attach_mount_hud_offset_pos"] = { idxa = 0, idxb = 7 }
		offset_key_list["attach_mount_hud_offset_rot"] = { idxa = 1, idxb = 7 }
	end
	for k, v in pairs(offset_key_list) do
		set_hud_vector(hud, k, v)
	end
	for k, v in pairs(value_list) do
		local value = utils.get_float(hud, k, v.def or 0)
		if value then
			hud_adjust.set_value(k, utils.get_float(wpn_sec, k))
		end
	end
	hud_adjust.enabled(false)
end
local function get_aim_state()
	-- local is_gl = weapon:weapon_in_grenade_mode()
	if not cur_cast_wpn:IsZoomed() then
		state.cur_aim_state = 0
		return
	end
	state.cur_aim_state = cur_cast_wpn:GetZoomType() + 1
	-- --FIXME: out of bound check
	if state.cur_aim_state > 3 then
		logger.err("Unknown aim state(out of bound):" .. state.cur_aim_state)
		state.cur_aim_state = 0
	end
end
--================PHYSICS======================
function apply_spring(raw_val, vel, dt, spring, damping)
	if not damping then
		--Calculate critical damping
		damping = math.sqrt(spring) * 2
	end
	--TODO: switch to solution for better fps adaption
	dt = math.min(dt, 1 / 30)
	local acc = raw_val * -spring - vel * damping
	vel = vel + acc * dt
	return raw_val + vel * dt, vel
end
function apply_spring_vec(raw_vec, vel_vec, dt, spring, damping)
	if not damping then
		--Calculate critical damping
		damping = math.sqrt(spring) * 2
	end
	--TODO: switch to solution
	dt = math.min(dt, 1 / 30)
	local acc = vector():set(raw_vec):mul(-spring)
	acc:sub(vector():set(vel_vec):mul(damping))
	vel_vec:add(acc:mul(dt))
	raw_vec:add(vector():set(vel_vec):mul(dt))
end
--REFT:redundant
--NOTE: i mean i know this is not accurate (or completely wrong) , but it works...
function apply_spring_vec_with_decay(raw_vec, vel_vec, dt, spring, damping)
	--TODO: switch to solution
	dt = math.min(dt, 1 / 30)
	local damping_factor = math.max(0, 1 - damping * dt)
	vel_vec:sub(vector():set(raw_vec):mul(spring:mul(dt))):mul(damping_factor)
	raw_vec:add(vector():set(vel_vec):mul(dt))
end

---FIXME: duck duck tell me, why this is not working.
-- function apply_spring_vec(raw_vec, vel_vec, dt, spring, damping)
-- 	apply_spring(raw_vec.x, vel_vec.x, dt, spring, damping)
-- 	apply_spring(raw_vec.y, vel_vec.y, dt, spring, damping)
-- 	-- apply_spring(raw_vec.z, vel_vec.z, dt, spring, damping)
-- end
-- function apply_spring_vec_with_decay(raw_vec, vel_vec, dt, spring, damping)
-- 	if not damping then
-- 		--Calculate critical damping
-- 		damping = math.sqrt(spring) * 2
-- 	end
-- 	--TODO: switch to solution
-- 	dt = math.min(dt, 1 / 30)
-- 	local acc = vector():set(raw_vec):mul(-spring):mul(dt)
-- 	vel_vec:add(dt)
-- 	local damping_factor = math.max(0, 1 - damping * dt)
-- 	-- vel_vec:mul(decay factor)
-- 	vel_vec:mul(damping_factor)
-- 	raw_vec:add(vector():set(vel_vec):mul(dt))
-- end
function apply_recoil_forces(dt, control_strength, damping)
	local base_feedback = (wpn_profile.shot_pitch / state.fire_interval) * control_strength
	local feedback_strength = base_feedback * wpn_profile.pull_force

	local strength_vec = vector():set(feedback_strength * 1.5, feedback_strength, 0)

	apply_spring_vec_with_decay(state.hud_rot_raw, state.vel_hud_rot, dt, strength_vec, damping)
	apply_spring_vec_with_decay(state.hud_pos_raw, state.vel_hud_pos, dt, strength_vec, damping)
end
function apply_simple_smooth(dt, smooth)
	if smooth <= 0.001 then
		state.hud_rot_smooth = vector():set(state.hud_rot_raw)
		state.hud_pos_smooth = vector():set(state.hud_pos_raw)
	else
		local smooth_factor = utils.math_clamp(smooth * dt, 0, 1)
		state.hud_rot_smooth = utils.vector_lerp(state.hud_rot_smooth, state.hud_rot_raw, smooth_factor)
		state.hud_pos_smooth = utils.vector_lerp(state.hud_pos_smooth, state.hud_pos_raw, smooth_factor)
	end
end
--------------------------------------
---Debug
--------------------------------------
