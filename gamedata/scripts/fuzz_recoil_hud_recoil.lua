local frm = fuzz_recoil
local camrc = fuzz_recoil_cam_recoil.instance
local utils = fuzz_recoil_utils
local logger = fuzz_recoil_logger
local iui = fuzz_recoil_imgui
local options = fuzz_recoil_mcm

local M = {}
_G.fuzz_recoil_hud_recoil = M

--------------
--internal state
--------------
local cur_pos = vector():set(0, 0, 0)
local cur_rot = vector():set(0, 0, 0)

local is_restored = false

local vel_pos = vector():set(0, 0, 0)
local vel_rot = vector():set(0, 0, 0)

local pos_raw = vector():set(0, 0, 0)
local rot_raw = vector():set(0, 0, 0)
local pos_smooth = vector():set(0, 0, 0)
local rot_smooth = vector():set(0, 0, 0)

--------------
local yaw_sign = -1

--instant mode state, wandering aim point with momentum
local is_ads = false
local shot_cam_k = 1
local drift_pitch = 0
local drift_yaw = 0
local drift_vel_pitch = 0
local drift_vel_yaw = 0
local yaw_target = 0
local shots_since_target = 0
local dwell_shots = 0

--------------
--Cahced variables
--------------
--NOTE:fixed by Lost In Place
local ori_hand_trs = {
	vector():set(0, 0, 0),
	vector():set(0, 0, 0),
}

local fire_interval = 0.1
local pull_force = 1.5
local firing_damping = 1
local force_pitch = 15
local force_y = -0.04
local force_yaw = 15
local force_x = 0.0006
--shoulder push, z pop per shot
local force_z = 0.006
--deterministic weapon class, drives burst heat
local burst_class = "other"
local shot_delay_enabled = false
local use_Y_lift = false

--------------
--Cahced configs
--------------
--TODO:should be constant
local max_hud_rot = vector():set(3, 3, 0)
local max_hud_pos = vector():set(0.0025, 0.0035, 0.02)

restore_spring = 150
restore_damping = 15.0
smooth_firing = 4.5
smooth_restore = 10
local threshold_restore = 0.001

--v2 kick   profile impulses rescaled into instant hud displacement
v2_pitch_scale = 0.022
v2_yaw_scale = 0.025
v2_pos_scale = 0.02
--fraction of the kick fed straight into the smoothed value   frame one snap
v2_kick_feedforward = 0.65
--per shot kick variance   plateau jitter scales with handling so the peak needs work
v2_pitch_jitter = 0.16
v2_plateau_jitter = 0.05
--small aim point wander   visual shake only since bullets follow the camera
--kept tight so the sight picture stays honest about the real poi
--the uncompensatable spread comes from fire bloom instead
v2_wander = 0.08
v2_wander_vel = 0.18
v2_burst_kick = 0.12
v2_wander_damp = 0.9
v2_wander_max = 0.4
v2_wander_decay = 0.25
--ads uses vanilla zoom ratio   hip fire kicks harder and wanders more
ads_kick_mul = 1.0
--ads walk speed and dwell   shift far then settle a few shots then shift again
ads_wander_mul = 1.15
ads_dwell_shots = 3
hip_kick_mul = 1.3
hip_spread_mul = 2.2
hip_jitter_mul = 2.0
hip_recover_mul = 0.72
--hip wander roams a wider box than ads
hip_wander_box = 1.55
--burst heat, sustained fire grows the variance, short bursts stay clean
--grace is the free shot budget, rate is escalation per shot past it
v2_heat = {
	smg = { grace = 8, rate = 0.06 },
	ar = { grace = 6, rate = 0.09 },
	lmg = { grace = 12, rate = 0.05 },
	other = { grace = 6, rate = 0.06 },
}
v2_heat_max = 1.6
--recovery rate, base plus handling driven convergence
v2_recover_base = 3.0
v2_recover_gain = 3.0
--recenter fraction per fire interval   each snap returns before the next shot
v2_snap_restore = 2.0
--horizontal recovers slower like tarkov   z shoulder pop recovers fast
v2_h_recover_mul = 0.65
v2_z_recover = 9.0
smooth_firing_instant = 25

--------------
--Cahced options
--------------
local bolt_action_Y_lift = true
--------
---public getters
--------
function M.is_restored()
	return is_restored
end
function M.get_rot_raw()
	return rot_raw
end
function M.get_vel_rot()
	return vel_rot
end
--TODO:apply to spring with different mul...
--ads kick vs hip kick for the camera channel, independent of hud mode
function M.get_ads_kick_mul(ads)
	return ads and ads_kick_mul or hip_kick_mul
end
function M.get_mode_kick_mul()
	return M.get_ads_kick_mul(is_ads)
end

--------------
---HUD Adujst
--------------
local function set_hud_hand(pos, rot)
	hud_adjust.set_vector(0, 0, pos.x, pos.y, pos.z)
	hud_adjust.set_vector(1, 0, rot.x, rot.y, rot.z)
end
local function apply_cur_hud_hand()
	set_hud_hand(cur_pos, cur_rot)
end
function M.enable_hud_adjust()
	hud_adjust.enabled(true)
end
function M.disable_hud_adjust()
	hud_adjust.enabled(false)
end
function M.update_cur_hud_hand_by(pos, rot)
	cur_pos:add(pos)
	cur_rot:add(rot)
end
function M.set_hud_offset(pos, rot)
	cur_pos = vector():set(ori_hand_trs[1]):add(pos)
	cur_rot = vector():set(ori_hand_trs[2]):add(rot)
	apply_cur_hud_hand()
end
function M.reset_hud_hand()
	cur_pos = vector():set(ori_hand_trs[1])
	cur_rot = vector():set(ori_hand_trs[2])
	apply_cur_hud_hand()
end
--------------
---Physics
--------------
function apply_spring_vec(raw_vec, vel_vec, dt, spring, damping)
	if not damping then
		--Calculate critical damping
		damping = math.sqrt(spring) * 2
	end
	--TODO: switch to solution for better fps adaption once everthings is stalblized
	dt = math.min(dt, 1 / 30)
	local acc = vector():set(raw_vec):mul(-spring)
	acc:sub(vector():set(vel_vec):mul(damping))
	vel_vec:add(acc:mul(dt))
	raw_vec:add(vector():set(vel_vec):mul(dt))
end
--NOTE: i mean i know this is not accurate (or completely wrong) , but it works...
local function apply_spring_vec_with_decay(raw_vec, vel_vec, dt, spring, damping)
	dt = math.min(dt, 1 / 30)
	local damping_factor = math.max(0, 1 - damping * dt)
	--mul mutates, scale a copy so the callers spring vector survives the call
	local spring_dt = vector():set(spring):mul(dt)
	vel_vec:sub(vector():set(raw_vec):mul(spring_dt)):mul(damping_factor)
	raw_vec:add(vector():set(vel_vec):mul(dt))
end
local function apply_recoil_forces(dt, control_strength, damping)
	local base_feedback = (force_pitch / fire_interval) * control_strength
	local feedback_strength = base_feedback * pull_force

	local strength_vec = vector():set(feedback_strength * 1.5, feedback_strength, 0)

	apply_spring_vec_with_decay(rot_raw, vel_rot, dt, strength_vec, damping)
	apply_spring_vec_with_decay(pos_raw, vel_pos, dt, strength_vec, damping)
end
local function apply_simple_smooth(dt, smooth)
	if smooth <= 0.001 then
		rot_smooth = vector():set(rot_raw)
		pos_smooth = vector():set(pos_raw)
	else
		local smooth_factor = utils.math_clamp(smooth * dt, 0, 1)
		rot_smooth = utils.vector_lerp(rot_smooth, rot_raw, smooth_factor)
		pos_smooth = utils.vector_lerp(pos_smooth, pos_raw, smooth_factor)
	end
end
--TODO: we should desync it
local function pos_y_sync_with_cam()
	if bolt_action_Y_lift and shot_delay_enabled then
		--PERF: should cached once code is stablelized
		y_impulse = math.min(use_Y_lift and math.abs(force_y) * 4 or force_y, 0.12)
		pos_raw.y = camrc.get_angle() * y_impulse
	end
end
--displayed rotation = smoothed offset plus the wandering aim point
local function rot_with_drift()
	local rot = vector():set(rot_smooth)
	rot.y = rot.y + drift_pitch
	rot.x = rot.x + drift_yaw
	rot:clamp(max_hud_rot)
	return rot
end
------------------------------------------
---3DB offsets
------------------------------------------
local function init_offset(wpn_sec, cast_wpn)
	hud_adjust.enabled(true)
	local hud = utils.get_string(wpn_sec, "hud")
	local postfix = utils_xml.is_widescreen() and "_16x9" or ""
	local function get_hud_vector(hud_sec, key, v)
		local value = utils.get_string(hud_sec, key .. postfix)
		if value == "" then
			value = utils.get_string(hud_sec, key)
		end
		if value == "" then
			return v.def or vector():set(0, 0, 0)
		end
		return utils_data.string_to_vector(value)
	end
	local function set_hud_vector(hud_sec, key, v)
		local _vec = get_hud_vector(hud_sec, key, v)
		hud_adjust.set_vector(v.idxa, v.idxb, _vec.x, _vec.y, _vec.z)
	end
	ori_hand_trs = {
		get_hud_vector(hud, "hands_position", { def = vector():set(0, 0, 0) }),
		get_hud_vector(hud, "hands_orientation", { def = vector():set(0, 0, 0) }),
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
		["fire_direction"] = { def = vector():set(0, 0, 1), idxa = 1, idxb = 10 },
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
	if cast_wpn and cast_wpn:IsScopeAttached() then
		local scope_sec = cast_wpn:GetScopeName()
		if scope_sec and scope_sec ~= "" then
			scope_zoom = utils.get_float(scope_sec, "scope_zoom_factor", scope_zoom)
			--3D scope reads its aim offset from adjust slots 8/9, mirror the scope hud section
			local scope_hud = utils.get_string(scope_sec, "hud")
			if scope_hud ~= "" then
				set_hud_vector(scope_hud, "aim_hud_offset_pos", { idxa = 0, idxb = 8 })
				set_hud_vector(scope_hud, "aim_hud_offset_rot", { idxa = 1, idxb = 8 })
				set_hud_vector(scope_hud, "aim_hud_offset_alt_pos", { def = vector():set(0, 0, 0), idxa = 0, idxb = 9 })
				set_hud_vector(scope_hud, "aim_hud_offset_alt_rot", { def = vector():set(0, 0, 0), idxa = 1, idxb = 9 })
			end
		end
	end
	hud_adjust.set_value("scope_zoom_factor", scope_zoom)
	hud_adjust.set_value("gl_zoom_factor", utils.get_float(wpn_sec, "gl_zoom_factor"))
	hud_adjust.set_value("scope_zoom_factor_alt", utils.get_float(wpn_sec, "scope_zoom_factor_alt"))
	hud_adjust.enabled(false)
end
--------------
--Spring Mode
--------------
local function apply_trans_and_smooth(dt, smooth, rot)
	pos_y_sync_with_cam()

	apply_simple_smooth(dt, smooth)
	M.set_hud_offset(pos_smooth, rot)
end
---@type fuzz_on_shot
local function on_shot_spring(handling_power, _, ads)
	is_restored = false
	--instant mode writes this in its own handler, keep spring fresh too
	is_ads = ads and true or false
	-- NOTE: vertical recoil should come from cam recoil  no this
	-- but we could turn this into an visual effect.
	-- local pitch_kick_enhancer = 1
	-- if handling_power > 0.7 then
	-- 	pitch_kick_enhancer = ((yaw_sign > 0) and 1 or 0.8) * yaw_sign -- * utils.lerp(math.random(), 0.7, 1)
	-- 	-- pitch_kick_enhancer = utils.lerp(math.random(), 0.7, 1)
	-- end
	-- vel_rot.y = vel_rot.y + pitch_kick_enhancer * force_pitch --/ mass_factor
	vel_rot.y = vel_rot.y + force_pitch --/ mass_factor
	vel_pos.y = vel_pos.y + force_y --/mass_factor

	--TODO: options for enabled and scales
	local yaw_kick_enhancer = utils.lerp(math.random(), 0.5, 1)
	if handling_power < 0.7 and fuzz_recoil.get_handling_fatigue() < 1 then
		yaw_kick_enhancer = utils.lerp(math.random(), 0.7, 1) * yaw_sign
	else
		M.pick_yaw_sign()
		yaw_kick_enhancer = yaw_kick_enhancer * yaw_sign
	end

	local yaw_impulse = force_yaw * yaw_kick_enhancer
	vel_rot.x = vel_rot.x + yaw_impulse

	--NOTE:count_ratio = 1/20
	local pos_x_impulse = (math.random() * 2 - 1) * force_x
	vel_pos.x = vel_pos.x + pos_x_impulse
end
---@type fuzz_on_firing
local function firing_update_spring(dt, handling_power)
	local pull_strength = pull_force * handling_power

	apply_recoil_forces(dt, pull_strength, firing_damping)

	-- limit before smooth
	rot_raw:clamp(max_hud_rot)
	pos_raw:clamp(max_hud_pos)
	apply_trans_and_smooth(dt, smooth_firing, rot_smooth)
end
---@type fuzz_on_restoring
local function restoring_update_spring(dt)
	local spring = restore_spring
	local damping = restore_damping

	apply_spring_vec(pos_raw, vel_pos, dt, spring, damping)
	apply_spring_vec(rot_raw, vel_rot, dt, spring, damping)

	if rot_raw:magnitude() < threshold_restore and pos_raw:magnitude() < threshold_restore then
		M.restored()
		return
	end
	apply_trans_and_smooth(dt, smooth_restore, rot_smooth)
end

--------------
--Instant Mode
--------------
--instant displacement per shot, recovery eases it back (snap out ease back)
---@type fuzz_on_shot
local function on_shot_instant(handling_power, _, ads, cam_k, burst_shots)
	is_restored = false
	is_ads = ads and true or false
	shot_cam_k = cam_k or 1

	local mode_mul = M.get_mode_kick_mul()
	local jitter_mul = is_ads and 1 or hip_jitter_mul
	local spread_mul = is_ads and 1 or hip_spread_mul
	local v_scale = shot_cam_k * mode_mul
	local h_scale = spread_mul

	--burst heat, every shot past the class grace budget grows the variance
	local hc = v2_heat[burst_class] or v2_heat.other
	local heat = 1 + hc.rate * math.max(0, burst_shots - hc.grace)
	if heat > v2_heat_max then
		heat = v2_heat_max
	end

	--kick variance floored, starved kicks would let the recovery sink the baseline
	local jitter = 1 + (math.random() * 2 - 1) * v2_pitch_jitter * jitter_mul
	if jitter < 0.6 then
		jitter = 0.6
	end
	--plateau jitter only adds on top, the ride height never dips
	local plateau = math.random() * v2_plateau_jitter * handling_power * jitter_mul * heat

	--heat widens the roam box and speeds the stride just enough to keep legs completable
	--dwell spots land farther apart, that is where the sustained fire spread comes from
	local wander_mul = is_ads and ads_wander_mul or hip_jitter_mul
	local vmax = v2_wander_vel * wander_mul * math.min(heat, 1.6)
	local wmax = v2_wander_max * (is_ads and 1 or hip_wander_box) * heat
	local accel = v2_wander * handling_power * wander_mul * heat

	--pitch rides above the plateau, surges up freely, sags down only gently, never dives
	local pmax = wmax * 0.12
	if burst_shots == 0 then
		drift_vel_pitch = math.random() * v2_burst_kick * jitter_mul
	else
		drift_vel_pitch = drift_vel_pitch * v2_wander_damp + (math.random() * 2 - 1) * accel
	end
	drift_vel_pitch = utils.math_clamp(drift_vel_pitch, -0.22 * vmax, vmax)
	drift_pitch = utils.math_clamp(drift_pitch + drift_vel_pitch, 0, pmax)
	if drift_pitch >= pmax then
		drift_vel_pitch = -0.18 * vmax
	elseif drift_pitch <= 0 then
		drift_vel_pitch = (0.4 + math.random() * 0.5) * vmax
	end

	--lateral wander walks waypoint to waypoint, traversal is guaranteed, camping impossible
	--ads settles a few shots at each stop, spread comes from dwelling at varied spots
	local hop_limit = is_ads and 10 or 8
	local dwell_limit = is_ads and ads_dwell_shots or 0
	local arrived = math.abs(yaw_target - drift_yaw) < 0.15 * wmax
	if burst_shots == 0 or shots_since_target >= hop_limit or (arrived and dwell_shots >= dwell_limit) then
		--next stop is on the other side of here, coin flip when we sit at center
		local dir
		if math.abs(drift_yaw) < 0.05 * wmax then
			dir = math.random() < 0.5 and -1 or 1
		else
			dir = drift_yaw >= 0 and -1 or 1
		end
		yaw_target = dir * (0.2 + math.random() * 0.8) * wmax
		shots_since_target = 0
		dwell_shots = 0
	elseif arrived then
		dwell_shots = dwell_shots + 1
	end
	shots_since_target = shots_since_target + 1
	--steering ramps in with handling so the first shots keep a clean climb
	local steer = utils.math_clamp((yaw_target - drift_yaw) * 0.6, -vmax, vmax) * (0.3 + 0.7 * handling_power)
	drift_vel_yaw = drift_vel_yaw * 0.55 + steer * 0.45 + (math.random() * 2 - 1) * accel
	drift_vel_yaw = utils.math_clamp(drift_vel_yaw, -vmax, vmax)
	drift_yaw = utils.math_clamp(drift_yaw + drift_vel_yaw, -wmax, wmax)

	local d_pitch = force_pitch * v2_pitch_scale * v_scale * jitter + plateau
	local d_pos_y = force_y * v2_pos_scale * v_scale
	--bounded horizontal walk, small random steps instead of full size flips
	local d_yaw = (math.random() * 2 - 1) * force_yaw * v2_yaw_scale * h_scale
	local d_pos_x = (math.random() * 2 - 1) * force_x * h_scale
	--shoulder push
	local d_pos_z = -force_z * shot_cam_k

	rot_raw.y = rot_raw.y + d_pitch
	rot_raw.x = rot_raw.x + d_yaw
	pos_raw.y = pos_raw.y + d_pos_y
	pos_raw.x = pos_raw.x + d_pos_x
	pos_raw.z = pos_raw.z + d_pos_z

	--feed part of the kick straight into the smoothed value, the ema only shapes recovery
	local ff = v2_kick_feedforward
	rot_smooth.y = rot_smooth.y + d_pitch * ff
	rot_smooth.x = rot_smooth.x + d_yaw * ff
	pos_smooth.y = pos_smooth.y + d_pos_y * ff
	pos_smooth.x = pos_smooth.x + d_pos_x * ff
	pos_smooth.z = pos_smooth.z + d_pos_z * ff
end
--recovery, exponential pull toward aim, rate grows with handling for climb then plateau
---@type fuzz_on_firing
local function firing_update_instant(dt, handling_power)
	local r = (v2_recover_base + v2_recover_gain * handling_power) * pull_force
	if not is_ads then
		r = r * hip_recover_mul
	end
	--rpm scaled recentering, the standing offset stays near zero at any fire rate
	r = r + v2_snap_restore / fire_interval
	local d_v = math.exp(-r * dt)
	local d_h = math.exp(-r * v2_h_recover_mul * dt)
	rot_raw.y = rot_raw.y * d_v
	pos_raw.y = pos_raw.y * d_v
	rot_raw.x = rot_raw.x * d_h
	pos_raw.x = pos_raw.x * d_h
	pos_raw.z = pos_raw.z * math.exp(-v2_z_recover * dt)
	--drift barely reverts while firing, that is the point
	local wd = math.exp(-v2_wander_decay * dt)
	drift_pitch = drift_pitch * wd
	drift_yaw = drift_yaw * wd
	rot_raw:clamp(max_hud_rot)
	pos_raw:clamp(max_hud_pos)
	apply_trans_and_smooth(dt, smooth_firing_instant, rot_with_drift())
end
---@type fuzz_on_restoring
local function restoring_update_instant(dt)
	restoring_update_spring(dt, false)
	-- FIXME: doubled applying
	local wd = math.exp(-6 * dt)
	drift_pitch = drift_pitch * wd
	drift_yaw = drift_yaw * wd
	apply_trans_and_smooth(dt, smooth_firing_instant, rot_with_drift())
	--drift comes home fast once firing stops
end

----------
---Event
----------
local EVENT_ID = fuzz_recoil_event.getEventID("hud_recoil")
--------------
--Mode Switching
--------------
M.MODE = {
	SPRING = 0,
	INSTANT = 1,
}
---@type fuzz_on_shot
local _on_shot_fn = on_shot_spring
---@type fuzz_on_firing
local _firing_update_fn = firing_update_spring
---@type fuzz_on_restoring
local _restoring_update_fn = restoring_update_spring
function M.switch_mode(mode)
	if mode == M.MODE.SPRING then
		_on_shot_fn = on_shot_spring
		_firing_update_fn = firing_update_spring
		_restoring_update_fn = restoring_update_spring
	elseif mode == M.MODE.INSTANT then
		_on_shot_fn = on_shot_instant
		_firing_update_fn = firing_update_instant
		_restoring_update_fn = restoring_update_instant
	end
end
--------------
---Public functions
--------------
--TODO: is this bad? but loading order is a little messy, some null error occurs
--if it's bad we can set reference when on_game_start
function M.awake()
	frm.on_init_wpn:add(EVENT_ID, M.init)
	frm.on_start:add(EVENT_ID, M.start)
	frm.on_before_fire:add(EVENT_ID, M.pick_yaw_sign)
	frm.on_firing_stop:add(EVENT_ID, M.on_firing_stop)
	frm.on_stop:add(EVENT_ID, M.stop)
	M.instance = M
	return M
end
function M.on_option_change()
	bolt_action_Y_lift = options.bolt_action_Y_lift
	M.switch_mode(options.instant_mode and M.MODE.INSTANT or M.MODE.SPRING)
	frm.on_shot:add(EVENT_ID, _on_shot_fn)
	frm.on_firing:add(EVENT_ID, _firing_update_fn)
end
function M.cache_profile(profile)
	fire_interval = profile.fire_interval
	firing_damping = profile.firing_damping
	pull_force = profile.pull_force

	force_pitch = profile.force_pitch
	force_y = profile.force_y
	force_yaw = profile.force_yaw
	force_x = profile.force_x
	force_z = profile.force_z or 0.006
	burst_class = profile.burst_class or "other"

	use_Y_lift = profile.is_bolt_action
	shot_delay_enabled = profile.shot_delay_enabled
end
function M.invert_yaw_sign()
	yaw_sign = yaw_sign * -1
end

---@type fuzz_on_init_wpn
function M.init(_, cast_wpn, wpn_sec)
	init_offset(wpn_sec, cast_wpn)
end
---@type fuzz_on_start
function M.start(profile)
	M.cache_profile(profile)
	M.reset_hud_hand()
	M.enable_hud_adjust()
end
---@type fuzz_on_before_fire
function M.pick_yaw_sign()
	yaw_sign = math.random() > 0.5 and 1 or -1
end
---@type fuzz_on_firing_stop
function M.on_firing_stop()
	frm.on_restoring:add(EVENT_ID, _restoring_update_fn)
end

function M.restored()
	frm.on_restoring:remove(EVENT_ID)
	is_restored = true

	vel_rot = vector():set(0, 0, 0)
	vel_pos = vector():set(0, 0, 0)

	pos_raw = vector():set(0, 0, 0)
	pos_smooth = vector():set(0, 0, 0)
	rot_raw = vector():set(0, 0, 0)
	rot_smooth = vector():set(0, 0, 0)

	drift_pitch = 0
	drift_yaw = 0
	drift_vel_pitch = 0
	drift_vel_yaw = 0

	M.reset_hud_hand()
	-- logger.dbg("reset hud recoil")
end

---@type fuzz_on_stop
function M.stop()
	M.disable_hud_adjust()
end
------------------------------------
---IMGUI
------------------------------------
function M.imgui_info_drawer()
	ImGui.TextColored(vector4():set(0, 1, 0.5, 1), "Hud Trans offset")
	iui.vector_imgui_text_drawer(pos_raw, "Pos")
	-- iui.vector_imgui_slider_drawer(pos_raw, "POS", 0.006, false, true)
	iui.vector_imgui_text_drawer(rot_raw, "Rot", true)
	iui.vector_imgui_text_drawer(vel_rot, "Vel Rot", true)
	iui.vector_imgui_text_drawer(rot_smooth, "Smoothed Rot", true)
	ImGui.Text(string.format("Raw Pitch: %.2f", math.deg(rot_raw.y)))
	ImGui.Text(string.format("Drift Y:%.3f|P:%.3f", drift_yaw, drift_pitch))
	ImGui.Text(string.format("ADS:%s, Shot cam k (addon x ammo): %.3f", tostring(is_ads), shot_cam_k))

	local v_cap_ratio = math.abs(rot_smooth.y) / max_hud_rot.y
	ImGui.ProgressBar(v_cap_ratio, vector2():set(-1, 0), string.format("Pitch %.4f", rot_smooth.y))

	local yaw_value = rot_smooth.x / 8 + 0.5
	ImGui.ProgressBar(-1 * yaw_value, vector2():set(-1, 0), string.format("Yaw: %.4f", rot_smooth.x))
	-- local _, _ = ImGui.SliderFloat("", yaw_value, -3, 3, string.format("Yaw: %.4f", yaw_value))
end
function M.imgui_config_drawer()
	ImGui.Text("Hud Recoil Config")
	ImGui.TextColored(vector4():set(0.3, 0.8, 1, 1), "Physics")
	_, smooth_firing = ImGui.SliderFloat("Smooth Firing", smooth_firing, 0.0, 10.0, "%.2f")
	_, smooth_restore = ImGui.SliderFloat("Smooth Restore", smooth_restore, 5.0, 15.0, "%.2f")
	_, restore_spring = ImGui.SliderFloat("Restore Spring", restore_spring, 0.1, 30.0, "%.2f")
	_, restore_damping = ImGui.SliderFloat("Restore Damping", restore_damping, 0.1, 16.0, "%.2f")
	iui.vector_imgui_slider_drawer(max_hud_rot, "Max Hud Rot", 5, true)
	iui.vector_imgui_slider_drawer(max_hud_pos, "Max Hud Pos", 0.004, false)
	if ImGui.TreeNode("V2 Kick Tuning") then
		_, v2_pitch_scale = ImGui.SliderFloat("Pitch Scale", v2_pitch_scale, 0.01, 0.4, "%.3f")
		_, v2_yaw_scale = ImGui.SliderFloat("Yaw Scale", v2_yaw_scale, 0.01, 0.3, "%.3f")
		_, v2_pos_scale = ImGui.SliderFloat("Pos Scale", v2_pos_scale, 0.001, 0.2, "%.3f")
		_, v2_kick_feedforward = ImGui.SliderFloat("Kick Feedforward", v2_kick_feedforward, 0, 1, "%.2f")
		_, v2_pitch_jitter = ImGui.SliderFloat("Pitch Jitter", v2_pitch_jitter, 0, 0.6, "%.2f")
		_, v2_plateau_jitter = ImGui.SliderFloat("Plateau Jitter", v2_plateau_jitter, 0, 1, "%.2f")
		_, v2_wander = ImGui.SliderFloat("Wander Accel", v2_wander, 0, 1, "%.2f")
		_, v2_wander_vel = ImGui.SliderFloat("Wander Max Vel", v2_wander_vel, 0, 1.5, "%.2f")
		_, v2_burst_kick = ImGui.SliderFloat("Burst Start Kick", v2_burst_kick, 0, 1, "%.2f")
		_, v2_wander_damp = ImGui.SliderFloat("Wander Damp", v2_wander_damp, 0.5, 1, "%.2f")
		_, v2_wander_max = ImGui.SliderFloat("Wander Box", v2_wander_max, 0.2, 4, "%.2f")
		_, v2_wander_decay = ImGui.SliderFloat("Wander Decay", v2_wander_decay, 0, 3, "%.2f")
		_, v2_recover_base = ImGui.SliderFloat("Recover Base", v2_recover_base, 0.1, 5, "%.2f")
		_, v2_recover_gain = ImGui.SliderFloat("Recover Gain", v2_recover_gain, 0, 8, "%.2f")
		_, v2_h_recover_mul = ImGui.SliderFloat("H Recover Mul", v2_h_recover_mul, 0.1, 1, "%.2f")
		_, v2_z_recover = ImGui.SliderFloat("Z Recover", v2_z_recover, 1, 20, "%.1f")
		_, smooth_firing_instant = ImGui.SliderFloat("Smooth Firing V2", smooth_firing_instant, 5, 60, "%.1f")
		ImGui.TreePop()
	end
	if ImGui.TreeNode("Burst Heat") then
		_, v2_heat_max = ImGui.SliderFloat("Heat Max", v2_heat_max, 1, 4, "%.2f")
		for _, class in ipairs({ "smg", "ar", "lmg", "other" }) do
			local hc = v2_heat[class]
			_, hc.grace = ImGui.SliderFloat(class .. " grace", hc.grace, 0, 20, "%.0f")
			_, hc.rate = ImGui.SliderFloat(class .. " rate", hc.rate, 0, 0.3, "%.3f")
		end
		ImGui.TreePop()
	end
	if ImGui.TreeNode("ADS & Hip") then
		_, ads_kick_mul = ImGui.SliderFloat("ADS Kick Mul", ads_kick_mul, 0.2, 2, "%.2f")
		_, ads_wander_mul = ImGui.SliderFloat("ADS Wander Mul", ads_wander_mul, 0.2, 3, "%.2f")
		_, ads_dwell_shots = ImGui.SliderFloat("ADS Dwell Shots", ads_dwell_shots, 0, 8, "%.0f")
		_, hip_kick_mul = ImGui.SliderFloat("Hip Kick Mul", hip_kick_mul, 0.5, 3, "%.2f")
		_, hip_spread_mul = ImGui.SliderFloat("Hip Spread Mul", hip_spread_mul, 0.5, 4, "%.2f")
		_, hip_jitter_mul = ImGui.SliderFloat("Hip Jitter Mul", hip_jitter_mul, 0.5, 4, "%.2f")
		_, hip_recover_mul = ImGui.SliderFloat("Hip Recover Mul", hip_recover_mul, 0.2, 1.5, "%.2f")
		_, hip_wander_box = ImGui.SliderFloat("Hip Wander Box", hip_wander_box, 0.5, 3, "%.2f")
		ImGui.TreePop()
	end
end
---------------
---HUD controls
---------------
local test_cur_pos_inc = vector():set(0, 0, 0)
local test_cur_rot_inc = vector():set(0, 0, 0)
function M.renderHudControls()
	ImGui.Text("Original Hand Pos:" .. utils.vector_to_string(ori_hand_trs[1]))
	ImGui.Text("Original Hand Rot:" .. utils.vector_to_string(ori_hand_trs[2]))
	ImGui.Text(string.format("Current HUD Pos: X:%.3f, Y:%.3f, Z:%.3f", cur_pos.x, cur_pos.y, cur_pos.z))
	ImGui.Text(string.format("Current HUD Rot: X:%.3f, Y:%.3f, Z:%.3f", cur_rot.x, cur_rot.y, cur_rot.z))
	ImGui.Separator()

	ImGui.Text("Direct")

	local changed_px, n_px = ImGui.SliderFloat("Pos X", cur_pos.x, -5.2, 5.2, "%.6f")
	local changed_py, n_py = ImGui.SliderFloat("Pos Y", cur_pos.y, -5.2, 5.2, "%.6f")
	local changed_pz, n_pz = ImGui.SliderFloat("Pos Z", cur_pos.z, -5.2, 5.2, "%.6f")

	local changed_rx, n_rx = ImGui.SliderFloat("Yaw", cur_rot.x, -3.2, 3.2, "%.6f")
	local changed_ry, n_ry = ImGui.SliderFloat("Pitch", cur_rot.y, -3.2, 3.2, "%.6f")
	local changed_rz, n_rz = ImGui.SliderFloat("Roll", cur_rot.z, -3.2, 3.2, "%.6f")

	if changed_px or changed_py or changed_pz or changed_rx or changed_ry or changed_rz then
		M.enable_hud_adjust()
		cur_pos = vector():set(n_px or cur_pos.x, n_py or cur_pos.y, n_pz or cur_pos.z)
		cur_rot = vector():set(n_rx or cur_rot.x, n_ry or cur_rot.y, n_rz or cur_rot.z)
		apply_cur_hud_hand()
	end

	if ImGui.Button("Reset HUD to Default") then
		M.reset_hud_hand()
		M.disable_hud_adjust()
	end
	ImGui.Separator()

	ImGui.Text("Impulse Delta")

	_, test_cur_pos_inc.x = ImGui.SliderFloat("Delta PosX", test_cur_pos_inc.x, -0.01, 0.01, "%.6f")
	_, test_cur_pos_inc.y = ImGui.SliderFloat("Delta PosY", test_cur_pos_inc.y, -0.01, 0.01, "%.6f")
	_, test_cur_pos_inc.z = ImGui.SliderFloat("Delta PosZ", test_cur_pos_inc.z, -0.01, 0.01, "%.6f")

	_, test_cur_rot_inc.x = ImGui.SliderFloat("Delta Yaw", test_cur_rot_inc.x, -0.5, 0.5, "%.6f")
	_, test_cur_rot_inc.y = ImGui.SliderFloat("Delta Pitch", test_cur_rot_inc.y, -0.5, 0.5, "%.6f")
	_, test_cur_rot_inc.z = ImGui.SliderFloat("Delta Roll", test_cur_rot_inc.z, -0.5, 0.5, "%.6f")
	--TODO: messy...
	if ImGui.Button("UseOffset") then
		M.enable_hud_adjust()
		cur_pos = vector():set(ori_hand_trs[1]):add(test_cur_pos_inc)
		cur_rot = vector():set(ori_hand_trs[2]):add(test_cur_rot_inc)
		apply_cur_hud_hand()
	end
	ImGui.SameLine()
	if ImGui.Button("GetOffset") then
		test_cur_pos_inc = vector():set(cur_pos):sub(ori_hand_trs[1])
		test_cur_rot_inc = vector():set(cur_rot):sub(ori_hand_trs[2])
	end
	ImGui.SameLine()
	if ImGui.Button("ResetInc") then
		test_cur_pos_inc = vector():set(0, 0, 0)
		test_cur_rot_inc = vector():set(0, 0, 0)
	end
	ImGui.SameLine()
	if ImGui.Button("Shot") then
		M.enable_hud_adjust()
		M.update_cur_hud_hand_by(test_cur_pos_inc, test_cur_rot_inc)
		apply_cur_hud_hand()
	end
end
