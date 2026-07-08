--FIXME: this namesacpe is bad for refactor
local frm = fuzz_recoil -- or require("scripts.fuzz_recoil")
local utils = fuzz_utils or fuzz_recoil_utils.fuzz_utils
local logger = logger or fuzz_recoil_logger.logger
local cvter = converter or fuzz_recoil_converter.converter
local CAM_FX_ID = frm.CAM_FX_ID
--stylua: ignore start
local cur_wpn = frm.cur_wpn
local config = frm.config
local ori_hand_trs = frm.ori_hand_trs
local state = frm.state
local cur_hud_pos =frm.cur_hud_pos
local cur_hud_rot = frm.cur_hud_rot
local wpn_profile = frm.wpn_profile
local settings = frm.settings
--stylua: ignore end
-- local log_text = frm.log_text

local test_cur_pos_inc = VEC_ZERO
local test_cur_rot_inc = VEC_ZERO

local showImguiWin = false
local showProfile = false
local showInfo = false
local showLogs = false
local debug_text1 = "Weapon profile won't refresh untill you shot a bullet"
local auto_scroll_logs = true
local export_hint = "Export profile to your game's bin folder"

--NOTE: we have to updadte all raw vector and nullable ref here
--silly but work for debuging
function update_ref()
	cur_wpn = frm.cur_wpn
	ori_hand_trs = frm.ori_hand_trs
	cur_hud_pos = frm.cur_hud_pos
	cur_hud_rot = frm.cur_hud_rot
	ori_hand_trs = frm.ori_hand_trs
	wpn_info = frm.wpn_info
	wpn_profile = frm.wpn_profile
end

function renderImguiWindow()
	ImGui.SetNextWindowSize(vector2():set(800, 600), ImGuiCond.FirstUseEver)

	local expanded, visible = ImGui.Begin("FuzzRecoil", showImguiWin, ImGuiWindowFlags.None)
	showImguiWin = visible

	if expanded then
		renderImguiTab()
	end

	ImGui.End()
end
function renderImguiTab()
	update_ref()
	ImGui.Text(debug_text1)
	_, showProfile = ImGui.Checkbox("Profile", showProfile)
	ImGui.SameLine()
	_, showInfo = ImGui.Checkbox("Info", showInfo)
	ImGui.SameLine()
	_, showLogs = ImGui.Checkbox("Logs", showLogs)
	ImGui.SameLine()
	_, auto_scroll_logs = ImGui.Checkbox("AutoScroll", auto_scroll_logs)
	ImGui.SameLine()
	if ImGui.Button("Clear Log", vector2():set(100, 25)) then
		logger.clear_internal_log()
	end
	ImGui.SameLine()
	if ImGui.Button("Load Weapon", vector2():set(100, 25)) then
		if frm.get_current_weapon() then
			debug_text1 = cur_wpn:section() .. ":" .. state.cur_wpn_id
		else
			debug_text1 = "Failed to load weapon"
		end
	end
	if cur_wpn then
		ImGui.TextColored(vector4():set(0, 1, 0, 1), "Weapon: " .. cur_wpn:section())
		ImGui.Separator()
		if ImGui.Button("ResetHand") then
			frm.reset_hud_hand()
		end
		ImGui.SameLine()
		if ImGui.Button("ForeceResetRecoil", vector2():set(150, 25)) then
			frm.force_reset_recoil()
		end
		renderProfile()
		if ImGui.TreeNode("Recoil Config") then
			renderConfig()
			ImGui.TreePop()
		end
		if ImGui.TreeNode("HUD Control") then
			renderHudControls()
			ImGui.TreePop()
		end
	end
end
ImGui.Groups.Main.Widget(function()
	if showImguiWin then
		renderImguiWindow()
	end
end)
ImGui.Groups.Mods.Widget(function()
	_, showImguiWin = ImGui.MenuItem("FuzzRecoil", nil, showImguiWin, true)
end)

-- Force scroll if the user was already at the bottom, or if a new item triggered a scroll
function log_overlay()
	if not showLogs then
		return
	end
	expanded, _ = ImGui.Begin("Recoil Log", true)
	if expanded and cur_wpn then
		-- Force scroll if the user was already at the bottom, or if a new item triggered a scroll
		ImGui.Text(logger.get_log_text())
		if auto_scroll_logs and ImGui.GetScrollY() >= ImGui.GetScrollMaxY() then
			ImGui.SetScrollHereY(1.0)
		end
	end
	ImGui.End()
end
AddUniqueCall(log_overlay)

function profile_overlay()
	if not showProfile then
		return
	end
	local function text_drawer(label, val)
		if type(val) == "number" then
			ImGui.Text(string.format("%s:%.5f", label, val))
		elseif type(val) == "boolean" then
			_, _ = ImGui.Checkbox(label, val)
		end
	end
	expanded, _ = ImGui.Begin("Weapon Profile", true)
	if expanded and frm.cur_wpn then
		ImGui.Text(frm.cur_wpn:section() .. ":" .. frm.state.cur_wpn_id)
		for k, v in pairs(frm.wpn_info) do
			text_drawer(k, v)
		end
		ImGui.Separator()
		ImGui.TextColored(vector4():set(0, 1, 0.5, 1), "Converted")
		for k, v in pairs(frm.wpn_profile) do
			text_drawer(k, v)
		end
	end
	ImGui.End()
end
AddUniqueCall(profile_overlay)

function info_overlay()
	if not showInfo then
		return
	end
	expanded, _ = ImGui.Begin("Recoil Info", true)
	if expanded and frm.cur_wpn then
		update_ref()
		ImGui.Separator()

		ImGui.Text(
			string.format(
				"Active:%s,Firing:%s,Cam_FX:%s",
				state.active,
				state.is_firing,
				level.check_cam_effector(CAM_FX_ID)
			)
		)
		ImGui.Text(string.format("CamRetrun:%s,HudReturn:%s", state.is_cam_returned, state.is_hud_returned))

		ImGui.ProgressBar(
			state.handling_power,
			vector2():set(-1, 0),
			string.format("Handling power: %.1f%%", state.handling_power * 100)
		)
		ImGui.Separator()
		ImGui.TextColored(vector4():set(0, 1, 0.5, 1), "Hud Trans offset")
		vector_imgui_text_drawer(cur_hud_pos - ori_hand_trs[1], "Pos")
		vector_imgui_text_drawer(cur_hud_rot - ori_hand_trs[2], "Rot", true)
		vector_imgui_text_drawer(state.vel_hud_rot, "Vel Rot", true)
		vector_imgui_text_drawer(state.hud_rot_smooth, "Smoothed Rot", true)
		ImGui.Text(string.format("Raw Pitch: %.2f", math.deg(state.hud_rot_raw.y)))
		ImGui.Text(string.format("Raw Target:Y%.2f|P %.2f", state.hud_rot_raw.x, state.hud_rot_raw.y))
		-- ImGui.Text(string.format("EMA Smooth Y:%.2f P: %.2f", state.hud_rot_smooth.x, state.hud_rot_smooth.y))

		local v_cap_ratio = math.abs(state.hud_rot_smooth.y) / config.max_hud_rot.y
		ImGui.ProgressBar(v_cap_ratio, vector2():set(-1, 0), string.format("Pitch %.1f%%", v_cap_ratio * 100))

		local yaw_value = state.hud_rot_smooth.x
		local yaw_display = yaw_value
		local _, _ = ImGui.SliderFloat("##yaw_slider", yaw_display, -0.5, 0.5, string.format("Yaw: %.4f", yaw_value))

		ImGui.Separator()
		ImGui.TextColored(vector4():set(0, 1, 0.5, 1), "Camera recoil")
		ImGui.Text(string.format("Cam pitch: %.3f", state.cam_angle))
		ImGui.Text(string.format("Cam velocity: %.3f", state.cam_vel))
		-- cam_total_up
	end
	ImGui.End()
end
AddUniqueCall(info_overlay)

function renderProfile()
	if ImGui.TreeNode("Weapon profile") then
		ImGui.Text("To input a value directly,You can crlt+click on the slider")
		_, wpn_profile.is_bolt_action = ImGui.Checkbox("Bolt Action", wpn_profile.is_bolt_action)
		_, wpn_profile.cam_recoil_power =
			ImGui.SliderFloat("Cam Recoil Power", wpn_profile.cam_recoil_power, 0.1, 16.0, "%.2f")
		_, wpn_profile.cam_return_speed =
			ImGui.SliderFloat("Cam Return Speed", wpn_profile.cam_return_speed, 0.5, 2, "%.2f")

		ImGui.Text("Shot Impact")
		_, wpn_profile.shot_pitch = ImGui.SliderFloat("Pitch", wpn_profile.shot_pitch, 0, 60, "%.2f")
		_, wpn_profile.shot_pos_y = ImGui.SliderFloat("PosY", wpn_profile.shot_pos_y, -0.06, 0.06, "%.4f")
		wpn_profile.shot_pos_y = wpn_profile.shot_pos_y
		_, wpn_profile.shot_yaw = ImGui.SliderFloat("Yaw", wpn_profile.shot_yaw, 0, 60, "%.2f")
		_, wpn_profile.shot_pos_x = ImGui.SliderFloat("PosX", wpn_profile.shot_pos_x, 0.0001, 0.0025, "%.4f")
		wpn_profile.shot_pos_x = wpn_profile.shot_pos_x
		_, wpn_profile.pull_force = ImGui.SliderFloat("Pull Force", wpn_profile.pull_force, 0.1, 4.0, "%.2f")
		_, wpn_profile.firing_damping =
			ImGui.SliderFloat("Spring Damping", wpn_profile.firing_damping, 0.1, 4.0, "%.2f")
		-- _, wpn_profile.hud_return_speed =
		-- 	ImGui.SliderFloat("Hud Return Speed", config.hud_return_speed, 0.5, 2, "%.2frad")

		ImGui.Text("Handling")
		handle_speed_change, wpn_profile.handling_speed =
			ImGui.SliderFloat("Handling speed", wpn_profile.handling_speed, 0.1, 2.0, "%.2f")
		if handle_speed_change then
			config.firing_handling_ease:set_speed(wpn_profile.handling_speed)
			config.idle_handling_ease:set_speed(wpn_profile.handling_speed * -1)
		end
		ImGui.TextColored(vector4():set(1, 0, 0, 1), "NOT IMPLEMENTED YET")
		_, wpn_profile.increase_rate = ImGui.SliderFloat("Increase Rate", wpn_profile.increase_rate, 0.0, 2.0, "%.2f")
		ImGui.Separator()
		ImGui.Text(export_hint)
		if ImGui.Button("Export to LTX", vector2():set(-1, 25)) then
			export_profile_to_ltx()
		end
		if ImGui.Button("Convert from vannilla", vector2():set(-1, 25)) then
			cvter.convert(frm.wpn_info, frm.wpn_profile)
		end
		ImGui.TreePop()
	end
end
function renderConfig()
	ImGui.TextColored(vector4():set(1, 0, 0, 1), "vvvvv DO NOT TOUCH THIS vvvvv")
	if ImGui.TreeNode("Config") then
		ImGui.TextColored(vector4():set(1, 1, 0, 1), "UNLESS YOU KNOW WHAT YOU ARE DOING")
		ImGui.Separator()
		config.firing_handling_ease:draw_imgui("Handling inc")
		config.idle_handling_ease:draw_imgui("Handling dec")
		--FIXME: tree does not PushID?
		_, config.base_cam_return_speed =
			ImGui.SliderFloat("Base Cam Return Speed", config.base_cam_return_speed, 0.1, 10, "%.2frad")
		_, config.min_cam_return_step =
			ImGui.SliderFloat("Min Cam Return step", config.min_cam_return_step, 0.001, 0.01, "%.4frad")

		ImGui.Separator()
		ImGui.TextColored(vector4():set(0.3, 0.8, 1, 1), "Physics")
		_, config.smooth_firing = ImGui.SliderFloat("Smooth Firing", config.smooth_firing, 0.0, 10.0, "%.2f")
		_, config.smooth_return = ImGui.SliderFloat("Smooth Return", config.smooth_return, 5.0, 15.0, "%.2f")
		_, config.return_spring = ImGui.SliderFloat("Return Spring", config.return_spring, 0.1, 30.0, "%.2f")
		_, config.return_damping = ImGui.SliderFloat("Return Damping", config.return_damping, 0.1, 16.0, "%.2f")
		ImGui.Text("Settings")
		ImGui.TextColored(vector4():set(1, 0, 0, 1), "NOT IMPLEMENTED YET")
		_, settings.recoil_v_scale = ImGui.SliderFloat("Recoil scale(Vert)", settings.recoil_v_scale, 0.1, 2.0, "%.2f")
		_, settings.recoil_h_scale = ImGui.SliderFloat("Recoil scale(Hori) ", settings.recoil_h_scale, 0.1, 2.0, "%.2f")
		_, settings.recoil_cam_scale =
			ImGui.SliderFloat("Recoil scale(Cam)", settings.recoil_cam_scale, 0.1, 2.0, "%.2f")
		_, settings.increase_rate_scale =
			ImGui.SliderFloat("Increase Rate", settings.increase_rate_scale, 0.1, 2.0, "%.2f")
		_, settings.handling_speed_scale =
			ImGui.SliderFloat("Handling Speed", settings.handling_speed_scale, 0.1, 2.0, "%.2f")
		-- ImGui.TextColored(vector4():set(0.2, 0.9, 0.4, 1), "=== HUD EMA FILTER CONTROLS ===")
		-- _, config.hud_fire_step = ImGui.SliderFloat("Fire Smooth Steps", config.hud_fire_step, 1, 12)
		-- _, config.hud_return_step = ImGui.SliderFloat("Return Smooth Steps", config.hud_return_step, 2, 25)
		if ImGui.Button("Dump All Weapon datas(need json.lua)", vector2():set(-1, 25)) then
			utils.get_all_weapon_sections()
		end
		ImGui.TreePop()
	end
	--TODO:refactor this to base
	ImGui.Separator()
	-- if not sim_firing then
	-- 	if ImGui.Button("SIMULATE", vector2():set(-1, 40)) then
	-- 		sim_firing = true
	-- 		sim_timer = 5.0
	-- 		frm.on_before_fire()
	-- 	end
	-- else
	-- 	ImGui.TextColored(vector4():set(1, 0, 0, 1), "FIRING IN PROGRESS... SIMULATING 750 RPM BURST")
	-- 	if ImGui.Button("FORCE STOP SIMULATION", vector2():set(-1, 30)) then
	-- 		frm.on_fire_stop()
	-- 	end
	-- end
end

function renderHudControls()
	ImGui.Text("Original Hand Pos:" .. utils.vector_to_string(ori_hand_trs[1]))
	ImGui.Text("Original Hand Rot:" .. utils.vector_to_string(ori_hand_trs[2]))
	ImGui.Text(string.format("Current HUD Pos: X:%.3f, Y:%.3f, Z:%.3f", cur_hud_pos.x, cur_hud_pos.y, cur_hud_pos.z))
	ImGui.Text(string.format("Current HUD Rot: X:%.3f, Y:%.3f, Z:%.3f", cur_hud_rot.x, cur_hud_rot.y, cur_hud_rot.z))
	ImGui.Separator()

	ImGui.Text("Direct")

	local changed_px, n_px = ImGui.SliderFloat("Pos X", cur_hud_pos.x, -5.2, 5.2, "%.6f")
	local changed_py, n_py = ImGui.SliderFloat("Pos Y", cur_hud_pos.y, -5.2, 5.2, "%.6f")
	local changed_pz, n_pz = ImGui.SliderFloat("Pos Z", cur_hud_pos.z, -5.2, 5.2, "%.6f")

	local changed_rx, n_rx = ImGui.SliderFloat("Yaw", cur_hud_rot.x, -3.2, 3.2, "%.6f")
	local changed_ry, n_ry = ImGui.SliderFloat("Pitch", cur_hud_rot.y, -3.2, 3.2, "%.6f")
	local changed_rz, n_rz = ImGui.SliderFloat("Roll", cur_hud_rot.z, -3.2, 3.2, "%.6f")

	if changed_px or changed_py or changed_pz or changed_rx or changed_ry or changed_rz then
		frm.enable_hud_adjust()
		frm.cur_hud_pos = vector():set(n_px or cur_hud_pos.x, n_py or cur_hud_pos.y, n_pz or cur_hud_pos.z)
		frm.cur_hud_rot = vector():set(n_rx or cur_hud_rot.x, n_ry or cur_hud_rot.y, n_rz or cur_hud_rot.z)
		frm.apply_cur_hud_hand()
	end

	if ImGui.Button("Reset HUD to Default") then
		frm.reset_hud_hand()
		frm.disable_hud_adjust()
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
		frm.enable_hud_adjust()
		frm.cur_hud_pos = ori_hand_trs[1] + test_cur_pos_inc
		frm.cur_hud_rot = ori_hand_trs[2] + test_cur_rot_inc
		frm.apply_cur_hud_hand()
	end
	ImGui.SameLine()
	if ImGui.Button("GetOffset") then
		test_cur_pos_inc = cur_hud_pos - ori_hand_trs[1]
		test_cur_rot_inc = cur_hud_rot - ori_hand_trs[2]
	end
	ImGui.SameLine()
	if ImGui.Button("ResetInc") then
		test_cur_pos_inc = vector():set(0, 0, 0)
		test_cur_rot_inc = vector():set(0, 0, 0)
	end
	ImGui.SameLine()
	if ImGui.Button("Shot") then
		frm.enable_hud_adjust()
		frm.update_cur_hud_hand_by(test_cur_pos_inc, test_cur_rot_inc)
		frm.apply_cur_hud_hand()
	end
end

function vector_imgui_text_drawer(vec, label, is_rot)
	local formater = is_rot and "Y: %.5f | P: %.5f | R: %.5f" or "X: %.5f | Y: %.5f | Z: %.5f"
	local info = string.format(formater, vec.x, vec.y, vec.z)
	ImGui.TextColored(vector4():set(0, 1, 0.5, 1), label)
	ImGui.Text(info)
end
function vector_imgui_slider_drawer(vec, label, is_rot)
	local limit = is_rot and 3.2 or 5.2
	ImGui.PushID(label)
	if is_rot then
		_, _ = ImGui.SliderFloat("Yaw", vec.x, -limit, limit, "%.5f")
		_, _ = ImGui.SliderFloat("Pitch", vec.y, -limit, limit, "%.5f")
		_, _ = ImGui.SliderFloat("Roll", vec.z, -limit, limit, "%.5f")
	else
		_, _ = ImGui.SliderFloat("X", vec.x, -limit, limit, "%.5f")
		_, _ = ImGui.SliderFloat("Y", vec.y, -limit, limit, "%.5f")
		_, _ = ImGui.SliderFloat("Z", vec.z, -limit, limit, "%.5f")
	end
	ImGui.PopID()
end

function indicator_drawer(val, label, min, max)
	if type(val) == "number" then
		_, _ = ImGui.SliderFloat(label, val, min, max, "%.5f")
	end
end

function export_profile_to_ltx()
	local profile = frm.wpn_profile
	--FIXME: scope name will be appended when attaching
	local wpn_name = tostring(frm.cur_wpn:section())

	local filename = string.format("mod_system_z_fuzz_recoil_%s.ltx", wpn_name)
	local file = io.open(filename, "w")
	if not file then
		export_hint = "Failed to open file when exporting"
		logger.err(export_hint)
	end

	local content = ""
	local function new_line(msg, ...)
		content = content .. "\n" .. string.format(msg, ...)
	end
	new_line("![%s]", wpn_name)
	new_line("fuzz_recoil=%s_fuzz_recoil", wpn_name)
	new_line("[%s_fuzz_recoil]", wpn_name)
	for k, v in pairs(profile) do
		new_line("%s=%s", k, v)
	end
	file:write(content)
	file:close()
	export_hint = "Recoil profile exported to " .. filename
end
