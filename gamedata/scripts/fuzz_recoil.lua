fuzz_recoil = { version = "a4" }
---@diagnostic disable: lowercase-global
----Imports
local utils = fuzz_recoil_utils
local cvter = fuzz_recoil_converter
local logger = fuzz_recoil_logger
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
	cam_dispersion_frac = 0.7,
	cam_max_angle = 0,
	cam_max_angle_horz = 0,
	cam_step_angle_horz = 0,
	cam_relax_speed = 0,
	zoom_cam_dispersion = 0,
	zoom_cam_dispersion_inc = 0,
	zoom_cam_dispersion_frac = 0.7,
	zoom_cam_max_angle = 0,
	zoom_cam_max_angle_horz = 0,
	zoom_cam_step_angle_horz = 0,
	zoom_cam_relax_speed = 0,
	addon_cam_k = 1,
	addon_cam_inc_k = 1,
	inv_weight = 0,
	mag_size = 30,
	rpm = 600,
}
settings = {
	debug_mode = fuzz_dev and true or false,

	recoil_v_scale = 1,
	recoil_h_scale = 1,
	recoil_cam_scale = 1,
	increase_rate_scale = 1,
	handling_speed_scale = 1,
	--The higher the sharper, the lower the smoother (and softer)
	cam_drag = 12,
	bolt_action_Y_lift = true,
	--tarkov style hud kick, instant displacement with eased recovery
	hud_kick_v2 = true,

	--vanilla data extras, off keeps stock feel
	use_pitch_frac = false,
	use_cam_max_angle = false,
	use_addon_ammo_koefs = false,
	use_increase_rate = false,
}
config = {
	max_hud_rot = vector():set(3, 3, 0),
	max_hud_pos = vector():set(0.0025, 0.0035, 0.02),
	base_cam_return_speed = 4.0,
	min_cam_return_step = 0.0045,

	--v2 kick, profile impulses rescaled into instant hud displacement
	v2_pitch_scale = 0.1,
	v2_yaw_scale = 0.035,
	v2_pos_scale = 0.02,
	--fraction of the kick fed straight into the smoothed value, frame one snap
	v2_kick_feedforward = 0.65,
	--per shot kick variance, plateau jitter scales with handling so the peak needs work
	v2_pitch_jitter = 0.16,
	v2_plateau_jitter = 0.18,
	--aim point wander with momentum, the recovery does NOT pull it back
	--each burst rolls its own travel direction, velocity capped so its trackable
	--aggregate study winner, spread comes from confident travel not shakiness
	v2_wander = 0.18,
	v2_wander_vel = 0.42,
	v2_burst_kick = 0.32,
	v2_wander_damp = 0.9,
	v2_wander_max = 1.5,
	v2_wander_decay = 0.25,
	--ads uses vanilla zoom ratio, hip fire kicks harder and wanders more
	ads_kick_mul = 1.0,
	--ads walk speed and dwell, shift far then settle a few shots then shift again
	ads_wander_mul = 1.15,
	ads_dwell_shots = 3,
	hip_kick_mul = 1.3,
	hip_spread_mul = 2.2,
	hip_jitter_mul = 2.0,
	hip_recover_mul = 0.72,
	--hip wander roams a wider box than ads
	hip_wander_box = 1.55,
	--burst heat, sustained fire grows the variance, short bursts stay clean
	--grace is the free shot budget, rate is escalation per shot past it
	v2_heat = {
		smg = { grace = 8, rate = 0.06 },
		ar = { grace = 6, rate = 0.09 },
		lmg = { grace = 12, rate = 0.05 },
		other = { grace = 6, rate = 0.06 },
	},
	v2_heat_max = 1.6,
	--recovery rate, base plus handling driven convergence
	v2_recover_base = 1.2,
	v2_recover_gain = 3.0,
	--horizontal recovers slower like tarkov, z shoulder pop recovers fast
	v2_h_recover_mul = 0.4,
	v2_z_recover = 9.0,
	smooth_firing_v2 = 25,

	return_spring = 150,
	return_damping = 15.0,
	smooth_firing = 4.5,
	smooth_return = 10,

	--auto fire cam impulse decay and step divisor
	cam_impulse_decay = 12,
	cam_step_div = 15,

	firing_handling_ease = utils.simple_ease:new(1, 1, 0.2, 4),
	idle_handling_ease = utils.simple_ease:new(-1, -1, 0.2, 6),

	--NOGUI
	sniper_idle_handling = { offset = 0.2, intensity = 0.8 },
}
wpn_profile = {
	is_bolt_action = false,
	cam_recoil_power = 4,
	cam_return_speed = 1,
	--0 means uncapped, radians like cam angle
	cam_max_angle = 0,
	--1 means no per shot variance
	pitch_frac = 1,
	--ads kick relative to hip, from vanilla zoom_cam_dispersion/cam_dispersion
	zoom_ratio = 1,

	shot_pitch = 15,
	shot_pos_y = -0.04,
	shot_yaw = 15,
	shot_pos_x = 0.0006,

	pull_force = 1.5,
	firing_damping = 1.0,
	--shoulder push, z pop per shot
	shot_pos_z = 0.006,
	-- hud_return_speed = 1,

	handling_speed = 0.5,

	-- shot_delay
	should_shot_delay = false,
	shot_delay_time = 0.4,
	shot_cam_impulse_factor = 0.2,

	--per shot growth ratio, kick = base*(1 + increase_rate*burst_shot_index)
	increase_rate = 0,
	-- mass_inertia = -1,
}
state = {
	active = false,
	is_firing = false,
	handling_power = 0.0,
	--shots in the current burst, drives recoil expansion
	burst_shots = 0,

	is_hud_returned = false,
	--own instances, VEC_ZERO is one shared global and these get mutated in place
	vel_hud_pos = vector():set(0, 0, 0),
	vel_hud_rot = vector():set(0, 0, 0),
	hud_pos_raw = vector():set(0, 0, 0),
	hud_rot_raw = vector():set(0, 0, 0),
	hud_pos_smooth = vector():set(0, 0, 0),
	hud_rot_smooth = vector():set(0, 0, 0),
	--no need to reset
	cur_wpn_id = 0,
	addon_sig = "",
	next_addon_check = 0,
	fire_interval = 0.1,
	--addon koefs x ammo k_cam_dispersion, refreshed per shot
	shot_cam_k = 1,
	is_ads = false,
	--wandering aim point, momentum walk per shot
	drift_pitch = 0,
	drift_yaw = 0,
	drift_vel_pitch = 0,
	drift_vel_yaw = 0,
	yaw_target = 0,
	shots_since_target = 0,
	dwell_shots = 0,
}
local shot_delay_table = {
	w_sniper = { rpm = 60, cam_impulse = 1 },
	w_shotgun = { rpm = 250, cam_impulse = 0.7 },
	w_pistol = { rpm = 340, cam_impulse = 0.4 },
}

ori_hand_trs = {
	vector():set(0, 0, 0),
	vector():set(0, 0, 0),
}
cur_hud_pos = vector():set(0, 0, 0)
cur_hud_rot = vector():set(0, 0, 0)
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

local camrc = fuzz_recoil_cam:new()

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
	--first draw reaches here with active already true, check the effector too
	if not state.active or not level.check_cam_effector(CAM_FX_ID) then
		start_recoil()
	end
	if wpn_profile.should_shot_delay then
		--create is a no op while one is pending, reset makes the delay count from the last shot
		CreateTimeEvent("fuzz_recoil", "bolt_delay_stop", wpn_profile.shot_delay_time, function()
			on_fire_stop()
			return true
		end)
		ResetTimeEvent("fuzz_recoil", "bolt_delay_stop", wpn_profile.shot_delay_time)
	end
	logger.dbg("Shot ")

	state.is_firing = true
	state.is_hud_returned = false

	-- local inertia_modifier = 1.0 / (1.0 + (wpn_profile.mass_inertia * 0.1))

	update_shot_cam_k()
	on_fire_phys()

	--vanilla dispersion_frac as mean preserving per shot variance
	local frac_factor = settings.use_pitch_frac and (1 + (math.random() * 2 - 1) * (1 - wpn_profile.pitch_frac)) or 1
	--engine style expansion, kick grows linearly with burst length (EffectorShot Shot)
	local expansion = settings.use_increase_rate
			and (1 + wpn_profile.increase_rate * settings.increase_rate_scale * state.burst_shots)
		or 1
	state.burst_shots = state.burst_shots + 1
	local kick_scale = wpn_profile.shot_cam_impulse_factor
		* frac_factor
		* expansion
		* state.shot_cam_k
		* settings.recoil_cam_scale
		* (settings.hud_kick_v2 and get_mode_kick_mul() or 1)
	camrc:on_fire(state.handling_power, wpn_profile.cam_recoil_power, kick_scale)
end
--v2, instant displacement per shot, recovery eases it back (snap out ease back)
function on_fire_phys_v2()
	local mode_mul = get_mode_kick_mul()
	local jitter_mul = state.is_ads and 1 or config.hip_jitter_mul
	local spread_mul = state.is_ads and 1 or config.hip_spread_mul
	local v_scale = state.shot_cam_k * settings.recoil_v_scale * mode_mul
	local h_scale = settings.recoil_h_scale * spread_mul

	--burst heat, every shot past the class grace budget grows the variance
	local hc = config.v2_heat[wpn_info.burst_class] or config.v2_heat.other
	local heat = 1 + hc.rate * math.max(0, state.burst_shots - hc.grace)
	if heat > config.v2_heat_max then
		heat = config.v2_heat_max
	end

	--kick variance floored, starved kicks would let the recovery sink the baseline
	local jitter = 1 + (math.random() * 2 - 1) * config.v2_pitch_jitter * jitter_mul
	if jitter < 0.6 then
		jitter = 0.6
	end
	--plateau jitter only adds on top, the ride height never dips
	local plateau = math.random() * config.v2_plateau_jitter * state.handling_power * jitter_mul * heat

	--heat widens the roam box and speeds the stride just enough to keep legs completable
	--dwell spots land farther apart, that is where the sustained fire spread comes from
	local wander_mul = state.is_ads and config.ads_wander_mul or config.hip_jitter_mul
	local vmax = config.v2_wander_vel * wander_mul * math.min(heat, 1.6)
	local wmax = config.v2_wander_max * (state.is_ads and 1 or config.hip_wander_box) * heat
	local accel = config.v2_wander * state.handling_power * wander_mul * heat

	--pitch rides above the plateau, surges up freely, sags down only gently, never dives
	local pmax = wmax * 0.7
	if state.burst_shots == 0 then
		state.drift_vel_pitch = math.random() * config.v2_burst_kick * jitter_mul
	else
		state.drift_vel_pitch = state.drift_vel_pitch * config.v2_wander_damp + (math.random() * 2 - 1) * accel
	end
	state.drift_vel_pitch = utils.math_clamp(state.drift_vel_pitch, -0.22 * vmax, vmax)
	state.drift_pitch = utils.math_clamp(state.drift_pitch + state.drift_vel_pitch, 0, pmax)
	if state.drift_pitch >= pmax then
		state.drift_vel_pitch = -0.18 * vmax
	elseif state.drift_pitch <= 0 then
		state.drift_vel_pitch = (0.4 + math.random() * 0.5) * vmax
	end

	--lateral wander walks waypoint to waypoint, traversal is guaranteed, camping impossible
	--ads settles a few shots at each stop, spread comes from dwelling at varied spots
	local hop_limit = state.is_ads and 10 or 8
	local dwell_limit = state.is_ads and config.ads_dwell_shots or 0
	local arrived = math.abs(state.yaw_target - state.drift_yaw) < 0.15 * wmax
	if
		state.burst_shots == 0
		or state.shots_since_target >= hop_limit
		or (arrived and state.dwell_shots >= dwell_limit)
	then
		--next stop is on the other side of here, coin flip when we sit at center
		local dir
		if math.abs(state.drift_yaw) < 0.05 * wmax then
			dir = math.random() < 0.5 and -1 or 1
		else
			dir = state.drift_yaw >= 0 and -1 or 1
		end
		state.yaw_target = dir * (0.2 + math.random() * 0.8) * wmax
		state.shots_since_target = 0
		state.dwell_shots = 0
	elseif arrived then
		state.dwell_shots = state.dwell_shots + 1
	end
	state.shots_since_target = state.shots_since_target + 1
	--steering ramps in with handling so the first shots keep a clean climb
	local steer = utils.math_clamp((state.yaw_target - state.drift_yaw) * 0.6, -vmax, vmax)
		* (0.3 + 0.7 * state.handling_power)
	state.drift_vel_yaw = state.drift_vel_yaw * 0.55 + steer * 0.45 + (math.random() * 2 - 1) * accel
	state.drift_vel_yaw = utils.math_clamp(state.drift_vel_yaw, -vmax, vmax)
	state.drift_yaw = utils.math_clamp(state.drift_yaw + state.drift_vel_yaw, -wmax, wmax)

	local d_pitch = wpn_profile.shot_pitch * config.v2_pitch_scale * v_scale * jitter + plateau
	local d_pos_y = wpn_profile.shot_pos_y * config.v2_pos_scale * v_scale
	--bounded horizontal walk, small random steps instead of full size flips
	local d_yaw = (math.random() * 2 - 1) * wpn_profile.shot_yaw * config.v2_yaw_scale * h_scale
	local d_pos_x = (math.random() * 2 - 1) * wpn_profile.shot_pos_x * h_scale
	--shoulder push
	local d_pos_z = -wpn_profile.shot_pos_z * state.shot_cam_k * settings.recoil_v_scale

	state.hud_rot_raw.y = state.hud_rot_raw.y + d_pitch
	state.hud_rot_raw.x = state.hud_rot_raw.x + d_yaw
	state.hud_pos_raw.y = state.hud_pos_raw.y + d_pos_y
	state.hud_pos_raw.x = state.hud_pos_raw.x + d_pos_x
	state.hud_pos_raw.z = state.hud_pos_raw.z + d_pos_z

	--feed part of the kick straight into the smoothed value, the ema only shapes recovery
	local ff = config.v2_kick_feedforward
	state.hud_rot_smooth.y = state.hud_rot_smooth.y + d_pitch * ff
	state.hud_rot_smooth.x = state.hud_rot_smooth.x + d_yaw * ff
	state.hud_pos_smooth.y = state.hud_pos_smooth.y + d_pos_y * ff
	state.hud_pos_smooth.x = state.hud_pos_smooth.x + d_pos_x * ff
	state.hud_pos_smooth.z = state.hud_pos_smooth.z + d_pos_z * ff
end
function on_fire_phys()
	if settings.hud_kick_v2 then
		on_fire_phys_v2()
		return
	end
	--shot_cam_k scales the cam_dispersion derived axes only
	local v_scale = state.shot_cam_k * settings.recoil_v_scale
	state.vel_hud_rot.y = state.vel_hud_rot.y + wpn_profile.shot_pitch * v_scale
	state.vel_hud_pos.y = state.vel_hud_pos.y + wpn_profile.shot_pos_y * v_scale

	local yaw_impulse = (math.random() * 2 - 1) * wpn_profile.shot_yaw * settings.recoil_h_scale
	state.vel_hud_rot.x = state.vel_hud_rot.x + yaw_impulse

	--NOTE:count_ratio = 1/20
	local pos_x_impulse = (math.random() * 2 - 1) * wpn_profile.shot_pos_x * settings.recoil_h_scale
	state.vel_hud_pos.x = state.vel_hud_pos.x + pos_x_impulse
end

function on_update(dt)
	if state.active == false then
		return
	end
	-- logger.dbg("Update")
	--addon swap while adjust mode is on sticks the hands, reset and reinit instead
	if time_global() >= state.next_addon_check then
		state.next_addon_check = time_global() + 250
		if get_addon_sig() ~= state.addon_sig then
			force_reset_recoil()
			state.cur_wpn_id = 0
			return
		end
	end
	if state.is_firing and cur_wpn:get_state() ~= 5 then
		on_fire_stop()
	end
	-- update_sim_shooting(dt)

	update_handling_power(dt)
	if state.is_firing then
		camrc:update(dt, state.is_firing)
		on_hud_update_phys(dt)
		return
	else
		local cam_returned = camrc:update(dt, state.is_firing)
		if not state.is_hud_returned then
			do_hud_return_phys(dt)
			-- reset_hud_recoil()
		end
		if cam_returned and state.is_hud_returned and state.handling_power <= 0 then
			reset_recoil()
		end
	end
end
function on_fire_stop()
	state.is_firing = false
	state.burst_shots = 0
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
	if wpn_profile.should_shot_delay then
		--PERF: should cached once code is stablelized
		y_impulse = (wpn_profile.is_bolt_action and settings.bolt_action_Y_lift) and math.abs(wpn_profile.shot_pos_y) * 2
			or wpn_profile.shot_pos_y
		state.hud_pos_raw.y = camrc.angle * y_impulse
	end
end
--v2 recovery, exponential pull toward aim, rate grows with handling for climb then plateau
function apply_recover_v2(dt)
	local r = (config.v2_recover_base + config.v2_recover_gain * state.handling_power) * wpn_profile.pull_force
	if not state.is_ads then
		r = r * config.hip_recover_mul
	end
	local d_v = math.exp(-r * dt)
	local d_h = math.exp(-r * config.v2_h_recover_mul * dt)
	state.hud_rot_raw.y = state.hud_rot_raw.y * d_v
	state.hud_pos_raw.y = state.hud_pos_raw.y * d_v
	state.hud_rot_raw.x = state.hud_rot_raw.x * d_h
	state.hud_pos_raw.x = state.hud_pos_raw.x * d_h
	state.hud_pos_raw.z = state.hud_pos_raw.z * math.exp(-config.v2_z_recover * dt)
	--drift barely reverts while firing, that is the point
	local wd = math.exp(-config.v2_wander_decay * dt)
	state.drift_pitch = state.drift_pitch * wd
	state.drift_yaw = state.drift_yaw * wd
end
function on_hud_update_phys(dt)
	if settings.hud_kick_v2 then
		apply_recover_v2(dt)
	else
		local pull_strength = wpn_profile.pull_force * state.handling_power
		apply_recoil_forces(dt, pull_strength, wpn_profile.firing_damping)
	end

	-- limit before smooth
	state.hud_rot_raw:clamp(config.max_hud_rot)
	state.hud_pos_raw:clamp(config.max_hud_pos)

	pos_y_sync_with_cam()
	apply_simple_smooth(dt, settings.hud_kick_v2 and config.smooth_firing_v2 or config.smooth_firing)

	set_hud_offset(state.hud_pos_smooth, rot_with_drift())
end
--displayed rotation = smoothed offset plus the wandering aim point
function rot_with_drift()
	local rot = vector():set(state.hud_rot_smooth)
	rot.y = rot.y + state.drift_pitch
	rot.x = rot.x + state.drift_yaw
	rot:clamp(config.max_hud_rot)
	return rot
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

	--drift comes home fast once firing stops
	local wd = math.exp(-6 * dt)
	state.drift_pitch = state.drift_pitch * wd
	state.drift_yaw = state.drift_yaw * wd

	apply_simple_smooth(dt, config.smooth_return)
	set_hud_offset(state.hud_pos_smooth, rot_with_drift())
end

--PERF:smart_cast everytime or cached table?
--i think cached table is better
function init_weapon(wpn_sec)
	collect_wpn_info(wpn_sec)
	init_hud_adjust(wpn_sec)
	remove_vanilla_cam_recoil()

	-- inil some recoil paramete from here
	state.fire_interval = 60 / wpn_info.rpm
	config.firing_handling_ease:set_speed(wpn_profile.handling_speed * settings.handling_speed_scale)
	config.idle_handling_ease:set_speed(wpn_profile.handling_speed * settings.handling_speed_scale)

	if wpn_profile.is_bolt_action then
		config.idle_handling_ease.intensity = config.sniper_idle_handling.intensity
		config.idle_handling_ease.offset = config.sniper_idle_handling.offset
	else
		config.idle_handling_ease:reset()
	end

	-- NOTE: or we can just check available firemodes?
	-- REFT: look at this mess...move this to converter
	wpn_profile.should_shot_delay = false
	wpn_profile.shot_cam_impulse_factor = 0.2

	local skind = shot_delay_table[wpn_info.kind]
	if skind and wpn_info.rpm <= skind.rpm then
		wpn_profile.should_shot_delay = true
		wpn_profile.shot_delay_time = utils.math_clamp(state.fire_interval, 0.1, 0.5)
		wpn_profile.shot_cam_impulse_factor = skind.cam_impulse
	end

	camrc:init(wpn_profile.cam_return_speed, wpn_profile.should_shot_delay and "cubic" or "exp")
	camrc.max_angle = wpn_profile.cam_max_angle

	logger.dbg("Initialize weapon")
end
function start_recoil()
	state.active = true
	camrc:start()
	reset_hud_hand()
	enable_hud_adjust()
	RemoveTimeEvent("fuzz_recoil", "bolt_delay_stop")
	logger.dbg("Initialize Recoil")
end

function reset_hud_recoil()
	logger.dbg("reset hud recoil")
	state.is_hud_returned = true

	state.vel_hud_rot = vector():set(0, 0, 0)
	state.vel_hud_pos = vector():set(0, 0, 0)

	state.hud_pos_raw = vector():set(0, 0, 0)
	state.hud_pos_smooth = vector():set(0, 0, 0)
	state.hud_rot_raw = vector():set(0, 0, 0)
	state.hud_rot_smooth = vector():set(0, 0, 0)
	state.drift_pitch = 0
	state.drift_yaw = 0
	state.drift_vel_pitch = 0
	state.drift_vel_yaw = 0

	reset_hud_hand()
end
function reset_recoil()
	state.active = false
	state.is_firing = false
	state.burst_shots = 0
	state.handling_power = 0

	disable_hud_adjust()
	if level.check_cam_effector(CAM_FX_ID) then
		level.remove_cam_effector(7897)
	end
	RemoveTimeEvent("fuzz_recoil", "bolt_delay_stop")

	logger.dbg("reset recoil")
end
function force_reset_recoil()
	camrc:stop()
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
	--NOTE: setters take raw radians, wpn_info is kept in ini degrees
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
--NOTE: engine getters return the live post-upgrade values in radians,
--converter rules are tuned to ini degrees, so convert back with math.deg
--engine clamps addon koefs to [0.01, 2.0], empty section means koef 1 like engine reset
local function get_addon_koef(sec, key)
	if not sec or sec == "" then
		return 1
	end
	return utils.math_clamp(utils.get_float(sec, key, 1), 0.01, 2.0)
end
--NOTE: engine multiplies cam recoil by attached addon section koefs (EffectorShot.cpp)
function collect_addon_koefs()
	if not settings.use_addon_ammo_koefs then
		wpn_info.addon_cam_k = 1
		wpn_info.addon_cam_inc_k = 1
		return
	end
	local cam_k, cam_inc_k = 1, 1
	local addons = {
		{ cur_cast_wpn:IsSilencerAttached(), cur_cast_wpn:GetSilencerName() },
		{ cur_cast_wpn:IsScopeAttached(), cur_cast_wpn:GetScopeName() },
		{ cur_cast_wpn:IsGrenadeLauncherAttached(), cur_cast_wpn:GetGrenadeLauncherName() },
	}
	for _, addon in ipairs(addons) do
		if addon[1] then
			cam_k = cam_k * get_addon_koef(addon[2], "cam_dispersion_k")
			cam_inc_k = cam_inc_k * get_addon_koef(addon[2], "cam_dispersion_inc_k")
		end
	end
	wpn_info.addon_cam_k = cam_k
	wpn_info.addon_cam_inc_k = cam_inc_k
end
--k_cam_dispersion of the selected ammo type, default 1 unclamped like engine
--NOTE: engine uses the chambered round, no lua export, selected type is the best approximation
function get_ammo_cam_k()
	local cur_type = cur_cast_wpn:GetAmmoType()
	local ammo_k = 1
	cur_cast_wpn:AmmoTypeForEach(function(i, sec)
		if i == cur_type then
			ammo_k = utils.get_float(sec, "k_cam_dispersion", 1)
			return true
		end
		return false
	end)
	return ammo_k
end
--refresh per shot so addon attach, ammo switch and ads state apply without a weapon re draw
function update_shot_cam_k()
	state.is_ads = (cur_cast_wpn and cur_cast_wpn:IsZoomed()) and true or false
	if not cur_cast_wpn or not settings.use_addon_ammo_koefs then
		state.shot_cam_k = 1
		return
	end
	collect_addon_koefs()
	state.shot_cam_k = wpn_info.addon_cam_k * get_ammo_cam_k()
end
--ads scales by the vanilla zoom ratio, hip fire kicks harder
function get_mode_kick_mul()
	if state.is_ads then
		return wpn_profile.zoom_ratio * config.ads_kick_mul
	end
	return config.hip_kick_mul
end
function collect_wpn_info(wpn_sec)
	wpn_info.kind = utils.get_string(wpn_sec, "kind")
	if cur_cast_wpn then
		--NOTE: dispersion_frac is a unitless fraction, no deg conversion
		wpn_info.cam_dispersion = math.deg(cur_cast_wpn:GetCamDispersion())
		wpn_info.cam_dispersion_inc = math.deg(cur_cast_wpn:GetCamDispersionInc())
		wpn_info.cam_dispersion_frac = cur_cast_wpn:GetCamDispersionFrac()
		wpn_info.cam_max_angle = math.deg(cur_cast_wpn:GetCamMaxAngleVert())
		wpn_info.cam_max_angle_horz = math.deg(cur_cast_wpn:GetCamMaxAngleHorz())
		wpn_info.cam_step_angle_horz = math.deg(cur_cast_wpn:GetCamStepAngleHorz())
		wpn_info.cam_relax_speed = math.deg(cur_cast_wpn:GetCamRelaxSpeed())
		wpn_info.zoom_cam_dispersion = math.deg(cur_cast_wpn:GetZoomCamDispersion())
		wpn_info.zoom_cam_dispersion_inc = math.deg(cur_cast_wpn:GetZoomCamDispersionInc())
		wpn_info.zoom_cam_dispersion_frac = cur_cast_wpn:GetZoomCamDispersionFrac()
		wpn_info.zoom_cam_max_angle = math.deg(cur_cast_wpn:GetZoomCamMaxAngleVert())
		wpn_info.zoom_cam_max_angle_horz = math.deg(cur_cast_wpn:GetZoomCamMaxAngleHorz())
		wpn_info.zoom_cam_step_angle_horz = math.deg(cur_cast_wpn:GetZoomCamStepAngleHorz())
		wpn_info.zoom_cam_relax_speed = math.deg(cur_cast_wpn:GetZoomCamRelaxSpeed())
		wpn_info.rpm = cur_cast_wpn:RealRPM()
		wpn_info.mag_size = cur_cast_wpn:GetAmmoMagSize()
		--live weight includes attached addons
		wpn_info.inv_weight = cur_cast_wpn:Weight()
		collect_addon_koefs()
	else
		--fallback: base section values, no upgrades
		wpn_info.cam_dispersion = utils.get_float(wpn_sec, "cam_dispersion")
		wpn_info.cam_dispersion_inc = utils.get_float(wpn_sec, "cam_dispersion_inc")
		wpn_info.cam_dispersion_frac = utils.get_float(wpn_sec, "cam_dispersion_frac", 0.7)
		wpn_info.cam_max_angle = utils.get_float(wpn_sec, "cam_max_angle")
		wpn_info.cam_max_angle_horz = utils.get_float(wpn_sec, "cam_max_angle_horz")
		wpn_info.cam_step_angle_horz = utils.get_float(wpn_sec, "cam_step_angle_horz")
		wpn_info.cam_relax_speed = utils.get_float(wpn_sec, "cam_relax_speed")
		--NOTE: engine copies hip values to zoom when the ini omits the zoom keys
		wpn_info.zoom_cam_dispersion = utils.get_float(wpn_sec, "zoom_cam_dispersion", wpn_info.cam_dispersion)
		wpn_info.zoom_cam_dispersion_inc = utils.get_float(wpn_sec, "zoom_cam_dispersion_inc", wpn_info.cam_dispersion_inc)
		wpn_info.zoom_cam_dispersion_frac = utils.get_float(wpn_sec, "zoom_cam_dispersion_frac", wpn_info.cam_dispersion_frac)
		wpn_info.zoom_cam_max_angle = utils.get_float(wpn_sec, "zoom_cam_max_angle", wpn_info.cam_max_angle)
		wpn_info.zoom_cam_max_angle_horz = utils.get_float(wpn_sec, "zoom_cam_max_angle_horz", wpn_info.cam_max_angle_horz)
		wpn_info.zoom_cam_step_angle_horz = utils.get_float(wpn_sec, "zoom_cam_step_angle_horz", wpn_info.cam_step_angle_horz)
		wpn_info.zoom_cam_relax_speed = utils.get_float(wpn_sec, "zoom_cam_relax_speed", wpn_info.cam_relax_speed)
		wpn_info.rpm = utils.get_float(wpn_sec, "rpm", 600)
		wpn_info.mag_size = utils.get_float(wpn_sec, "ammo_mag_size", 30)
		wpn_info.inv_weight = utils.get_float(wpn_sec, "inv_weight", 3)
		wpn_info.addon_cam_k = 1
		wpn_info.addon_cam_inc_k = 1
	end
	wpn_info.burst_class = classify_burst_class(wpn_info.kind, wpn_info.mag_size)
	state.addon_sig = get_addon_sig()
	try_get_recoil_profile(wpn_sec)
end
--attached addon fingerprint, a change means the engine reloaded hud measures
function get_addon_sig()
	if not cur_cast_wpn then
		return ""
	end
	return (cur_cast_wpn:IsScopeAttached() and "s" or "")
		.. tostring(cur_cast_wpn:GetScopeName())
		.. (cur_cast_wpn:IsSilencerAttached() and "m" or "")
		.. tostring(cur_cast_wpn:GetSilencerName())
		.. (cur_cast_wpn:IsGrenadeLauncherAttached() and "g" or "")
end
--deterministic weapon class from data, belt or drum feed is the lmg tell
function classify_burst_class(kind, mag_size)
	if kind == "w_smg" then
		return "smg"
	end
	if kind == "w_rifle" then
		return (mag_size or 30) >= 50 and "lmg" or "ar"
	end
	return "other"
end
function try_get_recoil_profile(wpn_sec)
	local profile = ini_sys:r_string_ex(wpn_sec, "fuzz_recoil", nil)
	if profile then
		wpn_profile.is_bolt_action = utils.get_bool(profile, "is_bolt_action", false)
		wpn_profile.cam_recoil_power = utils.get_float(profile, "cam_recoil_power", 4)
		wpn_profile.cam_return_speed = utils.get_float(profile, "cam_return_speed", 1)
		wpn_profile.cam_max_angle = utils.get_float(profile, "cam_max_angle", 0)
		wpn_profile.pitch_frac = utils.math_clamp(utils.get_float(profile, "pitch_frac", 1), 0, 1)
		wpn_profile.zoom_ratio = utils.math_clamp(utils.get_float(profile, "zoom_ratio", 1), 0.25, 2)

		wpn_profile.shot_pitch = utils.get_float(profile, "shot_pitch", 15)
		wpn_profile.shot_pos_y = utils.get_float(profile, "shot_pos_y", -0.04)
		wpn_profile.shot_yaw = utils.get_float(profile, "shot_yaw", 15)
		wpn_profile.shot_pos_x = utils.get_float(profile, "shot_pos_x", 0)

		wpn_profile.pull_force = utils.get_float(profile, "pull_force", 1.5)
		wpn_profile.firing_damping = utils.get_float(profile, "firing_damping", 1)
		wpn_profile.shot_pos_z = utils.get_float(profile, "shot_pos_z", 0.006)
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
	--engine reads these while adjust mode is on (UpdateZoomParams), mirror its sources
	--attach_scale dropped, hud_adjust.set_value silently ignores that key
	local scope_zoom = utils.get_float(wpn_sec, "scope_zoom_factor")
	if cur_cast_wpn and cur_cast_wpn:IsScopeAttached() then
		local scope_sec = cur_cast_wpn:GetScopeName()
		if scope_sec and scope_sec ~= "" then
			scope_zoom = utils.get_float(scope_sec, "scope_zoom_factor", scope_zoom)
		end
	end
	hud_adjust.set_value("scope_zoom_factor", scope_zoom)
	hud_adjust.set_value("gl_zoom_factor", utils.get_float(wpn_sec, "gl_zoom_factor"))
	hud_adjust.set_value("scope_zoom_factor_alt", utils.get_float(wpn_sec, "scope_zoom_factor_alt"))
	hud_adjust.enabled(false)
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
	--mul mutates, scale a copy so the callers spring vector survives the call
	local spring_dt = vector():set(spring):mul(dt)
	vel_vec:sub(vector():set(raw_vec):mul(spring_dt)):mul(damping_factor)
	raw_vec:add(vector():set(vel_vec):mul(dt))
end

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
