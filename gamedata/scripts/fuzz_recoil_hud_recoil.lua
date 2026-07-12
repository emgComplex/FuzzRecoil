local m_settings = settings or fuzz_recoil.settings
local m_cfg = config or fuzz_recoil.config
local utils = fuzz_recoil_utils
local logger = fuzz_recoil_logger
local iui = fuzz_recoil_imgui

local M = {}
_G.fuzz_recoil_hud_recoil = M

--NOTE:fixed by Lost In Place
local ori_hand_trs = {
	vector():set(0, 0, 0),
	vector():set(0, 0, 0),
}

local cur_pos = vector():set(0, 0, 0)
local cur_rot = vector():set(0, 0, 0)

local is_returned = false

local vel_pos = vector():set(0, 0, 0)
local vel_rot = vector():set(0, 0, 0)

local pos_raw = vector():set(0, 0, 0)
local rot_raw = vector():set(0, 0, 0)
local pos_smooth = vector():set(0, 0, 0)
local rot_smooth = vector():set(0, 0, 0)
--------------
--Cahced variables
--------------
local camrc = fuzz_recoil_cam_recoil.instance
local fire_interval = 0.1
local pull_force = 1.5
local firing_damping = 1
local force_pitch = 15
local force_y = -0.04
local force_yaw = 15
local force_x = 0.0006
local shot_dealy_enable = false
local is_bolt_action = false
--------
---public getters
--------
function M.is_returned()
	return is_returned
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
	vel_vec:sub(vector():set(raw_vec):mul(spring:mul(dt))):mul(damping_factor)
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
	if m_settings.bolt_action_Y_lift and shot_dealy_enable then
		--PERF: should cached once code is stablelized
		y_impulse = is_bolt_action and math.abs(force_y) * 2 or force_y
		pos_raw.y = camrc.angle * y_impulse
	end
end
------------------------------------------
---3DB offsets
------------------------------------------
local function init_offset(wpn_sec)
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
		["fire_direction"] = { def = vector():set(0, 0, 1), idxa = 1, idxb = 10 },
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
--------------
---Methods
--------------
function M.init(wpn_sec, profile)
	init_offset(wpn_sec)

	fire_interval = profile.fire_interval
	firing_damping = profile.firing_damping
	pull_force = profile.pull_force

	force_pitch = profile.shot_pitch
	force_y = profile.shot_pos_y
	force_yaw = profile.shot_yaw
	force_x = profile.shot_pos_x

	is_bolt_action = profile.is_bolt_action
	shot_dealy_enabled = profile.shot_dealy_enabled
end

function M.start()
	M.reset_hud_hand()
	M.enable_hud_adjust()
end
function M.stop()
	logger.dbg("reset hud recoil")
	is_returned = true

	vel_rot = VEC_ZERO
	vel_pos = VEC_ZERO

	pos_raw = VEC_ZERO
	pos_smooth = VEC_ZERO
	rot_raw = VEC_ZERO
	rot_smooth = VEC_ZERO

	M.reset_hud_hand()
end

function M.on_fire()
	vel_rot.y = vel_rot.y + force_pitch --/ mass_factor
	vel_pos.y = vel_pos.y + force_y --/mass_factor

	local yaw_impulse = (math.random() * 2 - 1) * force_yaw
	vel_rot.x = vel_rot.x + yaw_impulse

	--NOTE:count_ratio = 1/20
	local pos_x_impulse = (math.random() * 2 - 1) * force_x
	vel_pos.x = vel_pos.x + pos_x_impulse

	is_returned = false
end

function M.update_on_firing(dt, handling_power)
	local pull_strength = pull_force * handling_power

	apply_recoil_forces(dt, pull_strength, firing_damping)

	-- limit before smooth
	rot_raw:clamp(m_cfg.max_hud_rot)
	pos_raw:clamp(m_cfg.max_hud_pos)
end

function M.update_on_return(dt)
	local spring = m_cfg.return_spring
	local damping = m_cfg.return_damping

	apply_spring_vec(pos_raw, vel_pos, dt, spring, damping)
	apply_spring_vec(rot_raw, vel_rot, dt, spring, damping)

	local threshold_return = 0.001
	if rot_raw:magnitude() < threshold_return and pos_raw:magnitude() < threshold_return then
		M.stop()
		return
	end
end

--TODO: this is shit ,use deleate instead
function M.update(dt, handling_power)
	if is_returned then
		return true
	end
	if handling_power then
		M.update_on_firing(dt, handling_power)
	else
		M.update_on_return(dt)
	end
	pos_y_sync_with_cam()

	apply_simple_smooth(dt, m_cfg.smooth_return)
	M.set_hud_offset(pos_smooth, rot_smooth)
	return false
end

------------------------------------
---IMGUI
------------------------------------
function M.imgui_info_drawer()
	ImGui.TextColored(vector4():set(0, 1, 0.5, 1), "Hud Trans offset")
	iui.vector_imgui_text_drawer(pos_raw, "Pos")
	iui.vector_imgui_text_drawer(rot_raw, "Rot", true)
	iui.vector_imgui_text_drawer(vel_rot, "Vel Rot", true)
	iui.vector_imgui_text_drawer(rot_smooth, "Smoothed Rot", true)
	ImGui.Text(string.format("Raw Pitch: %.2f", math.deg(rot_raw.y)))
	ImGui.Text(string.format("Raw Target:Y%.2f|P %.2f", rot_raw.x, rot_raw.y))
	-- ImGui.Text(string.format("EMA Smooth Y:%.2f P: %.2f", state.hud_rot_smooth.x, state.hud_rot_smooth.y))

	local v_cap_ratio = math.abs(rot_smooth.y) / m_cfg.max_hud_rot.y
	ImGui.ProgressBar(v_cap_ratio, vector2():set(-1, 0), string.format("Pitch %.1f%%", v_cap_ratio * 100))

	local yaw_value = rot_smooth.x
	local yaw_display = yaw_value
	local _, _ = ImGui.SliderFloat("##yaw_slider", yaw_display, -0.5, 0.5, string.format("Yaw: %.4f", yaw_value))
end
---------------
local test_cur_pos_inc = vector():set(0, 0, 0)
local test_cur_rot_inc = vector():set(0, 0, 0)
function M.renderHudControls()
	ImGui.Text("Original Hand Pos:" .. utils.vector_to_string(ori_hand_trs[1]))
	ImGui.Text("Original Hand Rot:" .. utils.vector_to_string(ori_hand_trs[2]))
	ImGui.Text(string.format("Current HUD Pos: X:%.3f, Y:%.3f, Z:%.3f", cur_pos.x, cur_pos.y, cur_pos.z))
	ImGui.Text(string.format("Current HUD Rot: X:%.3f, Y:%.3f, Z:%.3f", cur_hud_rot.x, cur_hud_rot.y, cur_hud_rot.z))
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
---
-----------------
---toilet
-----------------
-- NOTE: have to make is work,since we are doing different movement on the y Axis
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
