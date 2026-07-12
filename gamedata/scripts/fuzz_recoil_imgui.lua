--FIXME: this namesacpe is bad for refactor
local frm = fuzz_recoil -- or require("scripts.fuzz_recoil")
local utils = fuzz_recoil_utils
local logger = fuzz_recoil_logger
local cvter = fuzz_recoil_converter
local camrc = fuzz_recoil_cam_recoil.instance
local hudrc = fuzz_recoil_hud_recoil.instance
--stylua: ignore start
--stylua: ignore end
-- local log_text = frm.log_text
-- l

local showImguiWin = fuzz_dev and true or false
local overlay_toggle = fuzz_dev and true or false
local showProfile = fuzz_dev and true or false
local showInfo = fuzz_dev and true or false
local showLogs = fuzz_dev and true or false
local showPlots = fuzz_dev and true or false

local debug_text1 = "Weapon profile won't refresh untill you shot a bullet"
local auto_scroll_logs = true
local export_hint = "Export profile to your game's bin folder"

--NOTE: we have to updadte all raw vector and nullable ref here
--silly but work for debuging

local LinePlot = {}
LinePlot.__index = LinePlot
function LinePlot.new(label, max_size, min_val, max_val, width, height)
	local self = setmetatable({}, LinePlot)

	self.label = label or "Plot"
	self.max_size = max_size or 100
	self.min_val = min_val or -1.0
	self.max_val = max_val or 1.0
	self.width = width or 300
	self.height = height or 150

	self.history_data = {}
	for i = 1, self.max_size do
		table.insert(self.history_data, 0)
	end

	return self
end
function LinePlot:draw(new_value)
	table.remove(self.history_data, 1)
	table.insert(self.history_data, new_value)

	local min_y = self.min_val or nil
	local max_y = self.max_val or nil

	--NOTE: sadly no lua bindings for plot...
	ImGui.PlotLines(
		self.label,
		self.history_data,
		self.max_size,
		0,
		nil,
		min_y,
		max_y,
		vector2():set(self.width, self.height)
	)
end

local LinePlotHack = {}
LinePlotHack.__index = LinePlotHack

function LinePlotHack.new(max_size, width, unit_size)
	local self = setmetatable({}, LinePlotHack)
	self.max_size = max_size or 50
	self.width = width or 300
	self.unit_size = unit_size or 1
	self.history_data = {}
	for i = 1, self.max_size do
		table.insert(self.history_data, 0.0)
	end
	return self
end
function LinePlotHack:draw(new_val)
	if new_val then
		table.remove(self.history_data, 1)
		table.insert(self.history_data, math.max(0.0, math.min(1.0, new_val)))
	end
	ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, vector2():set(0, 0))
	for i, val in ipairs(self.history_data) do
		ImGui.ProgressBar(val, vector2():set(self.width, 1), "")
	end
	ImGui.PopStyleVar()
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
	ImGui.SameLine()
	if ImGui.Button("ToggleOverlays", vector2():set(100, 25)) then
		overlay_toggle = not overlay_toggle
		showPlots = overlay_toggle
		showLogs = overlay_toggle
		showInfo = overlay_toggle
		showProfile = overlay_toggle
	end
	ImGui.Text(debug_text1)
	_, showProfile = ImGui.Checkbox("Profile", showProfile)
	ImGui.SameLine()
	_, showInfo = ImGui.Checkbox("Info", showInfo)
	ImGui.SameLine()
	if ImGui.Button("Load Weapon", vector2():set(100, 25)) then
		if frm.get_current_weapon() then
			debug_text1 = frm.cur_wpn:section() .. ":" .. frm.state.cur_wpn_id
		else
			debug_text1 = "Failed to load weapon"
		end
	end
	----------------
	----------------
	_, showPlots = ImGui.Checkbox("Histogram", showPlots)
	ImGui.SameLine()
	_, showLogs = ImGui.Checkbox("Logs", showLogs)
	ImGui.SameLine()
	_, auto_scroll_logs = ImGui.Checkbox("AutoScroll", auto_scroll_logs)
	ImGui.SameLine()
	if ImGui.Button("Clear Log", vector2():set(100, 25)) then
		logger.clear_internal_log()
	end
	ImGui.SameLine()
	if ImGui.Button("Export Log", vector2():set(100, 25)) then
		logger.export_internal_log()
	end
	----------------
	----------------
	if frm.cur_wpn then
		ImGui.TextColored(vector4():set(0, 1, 0, 1), "Weapon: " .. frm.cur_wpn:section())
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
			hudrc.renderHudControls()
			ImGui.TreePop()
		end
		if ImGui.TreeNode("Debug Vars") then
			renderDebugVars()
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
	ImGui.SetNextWindowSize(vector2():set(400, 200), ImGuiCond.FirstUseEver)
	if not showLogs then
		return
	end
	expanded, _ = ImGui.Begin("Recoil Log", true)
	if expanded and frm.cur_wpn then
		-- Force scroll if the user was already at the bottom, or if a new item triggered a scroll
		ImGui.Text(logger.get_log_text())
		if auto_scroll_logs and ImGui.GetScrollY() >= ImGui.GetScrollMaxY() then
			ImGui.SetScrollHereY(1.0)
		end
	end
	ImGui.End()
end
AddUniqueCall(log_overlay)

local cam_angle_plot = LinePlotHack.new(300, 300, 1)
local handling_power_plot = LinePlotHack.new(300, 300, 1)
function plot_overlay()
	if not showPlots then
		return
	end
	expanded, _ = ImGui.Begin("Histogram", true)
	ImGui.SetNextWindowSize(vector2():set(300, 600), ImGuiCond.FirstUseEver)
	if expanded and frm.cur_wpn then
		if ImGui.TreeNode("cam_angle") then
			local new_val = frm.state.active and camrc.get_angle() or nil
			cam_angle_plot:draw(new_val)
			ImGui.TreePop()
		end
		if ImGui.TreeNode("handling_power") then
			new_val = frm.state.active and frm.state.handling_power or nil
			handling_power_plot:draw(new_val)
			ImGui.TreePop()
		end
	end
	ImGui.End()
end
AddUniqueCall(plot_overlay)

function profile_overlay()
	ImGui.SetNextWindowSize(vector2():set(400, 600), ImGuiCond.FirstUseEver)
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
	ImGui.SetNextWindowSize(vector2():set(400, 600), ImGuiCond.FirstUseEver)
	if not showInfo then
		return
	end
	expanded, _ = ImGui.Begin("Recoil Info", true)
	if expanded and frm.cur_wpn then
		ImGui.Separator()

		ImGui.Text(
			string.format(
				"Active:%s,Firing:%s,Cam_FX:%s",
				frm.state.active,
				frm.state.is_firing,
				camrc.has_camera_effector()
			)
		)
		ImGui.Text(string.format("CamRetrun:%s,HudReturn:%s", camrc.is_returned(), hudrc.is_returned()))

		ImGui.ProgressBar(
			frm.state.handling_power,
			vector2():set(-1, 0),
			string.format("Handling power: %.1f%%", frm.state.handling_power * 100)
		)
		ImGui.Separator()
		hudrc.imgui_info_drawer()
		ImGui.Separator()
		camrc.imgui_info_drawer()
	end
	ImGui.End()
end
AddUniqueCall(info_overlay)

function renderProfile()
	if ImGui.TreeNode("Weapon profile") then
		ImGui.Text("To input a value directly,You can crlt+click on the slider")
		_, frm.wpn_profile.is_bolt_action = ImGui.Checkbox("Bolt Action", frm.wpn_profile.is_bolt_action)
		_, frm.wpn_profile.cam_recoil_power =
			ImGui.SliderFloat("Cam Recoil Power", frm.wpn_profile.cam_recoil_power, 0.1, 16.0, "%.2f")
		_, frm.wpn_profile.cam_return_speed =
			ImGui.SliderFloat("Cam Return Speed", frm.wpn_profile.cam_return_speed, 0.5, 2, "%.2f")

		ImGui.Text("Shot Impact")
		_, frm.wpn_profile.shot_pitch = ImGui.SliderFloat("Pitch", frm.wpn_profile.shot_pitch, 0, 60, "%.2f")
		_, frm.wpn_profile.shot_pos_y = ImGui.SliderFloat("PosY", frm.wpn_profile.shot_pos_y, -0.06, 0.06, "%.4f")
		frm.wpn_profile.shot_pos_y = frm.wpn_profile.shot_pos_y
		_, frm.wpn_profile.shot_yaw = ImGui.SliderFloat("Yaw", frm.wpn_profile.shot_yaw, 0, 60, "%.2f")
		_, frm.wpn_profile.shot_pos_x = ImGui.SliderFloat("PosX", frm.wpn_profile.shot_pos_x, 0.0001, 0.0025, "%.4f")
		frm.wpn_profile.shot_pos_x = frm.wpn_profile.shot_pos_x
		_, frm.wpn_profile.pull_force = ImGui.SliderFloat("Pull Force", frm.wpn_profile.pull_force, 0.1, 4.0, "%.2f")
		_, frm.wpn_profile.firing_damping =
			ImGui.SliderFloat("Spring Damping", frm.wpn_profile.firing_damping, 0.1, 4.0, "%.2f")

		ImGui.Text("Handling")
		handle_speed_change, frm.wpn_profile.handling_speed =
			ImGui.SliderFloat("Handling speed", frm.wpn_profile.handling_speed, 0.1, 2.0, "%.2f")
		if handle_speed_change then
			frm.config.firing_handling_ease:set_speed(frm.wpn_profile.handling_speed)
			frm.config.idle_handling_ease:set_speed(frm.wpn_profile.handling_speed)
		end
		ImGui.TextColored(vector4():set(1, 0, 0, 1), "NOT IMPLEMENTED YET")
		_, frm.wpn_profile.increase_rate =
			ImGui.SliderFloat("Increase Rate", frm.wpn_profile.increase_rate, 0.0, 2.0, "%.2f")
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
		frm.config.firing_handling_ease:draw_imgui("Handling inc")
		frm.config.idle_handling_ease:draw_imgui("Handling dec")
		camrc.imgui_config_drawer()
		ImGui.Separator()
		hudrc.imgui_config_drawer()
		if ImGui.Button("Dump All Weapon datas(need json.lua)", vector2():set(-1, 25)) then
			utils.get_all_weapon_sections()
		end
		ImGui.Separator()
		ImGui.Text("Settings")
		_, frm.settings.bolt_action_Y_lift = ImGui.Checkbox("Bolt-Action Lift", frm.settings.bolt_action_Y_lift)
		_, frm.settings.cam_drag = ImGui.SliderFloat("Cam Drag", frm.settings.cam_drag, 5.0, 20.0, "%.2f")
		ImGui.TextColored(vector4():set(1, 0, 0, 1), "NOT IMPLEMENTED YET")
		_, frm.settings.recoil_v_scale =
			ImGui.SliderFloat("Recoil scale(Vert)", frm.settings.recoil_v_scale, 0.1, 2.0, "%.2f")
		_, frm.settings.recoil_h_scale =
			ImGui.SliderFloat("Recoil scale(Hori) ", frm.settings.recoil_h_scale, 0.1, 2.0, "%.2f")
		_, frm.settings.recoil_cam_scale =
			ImGui.SliderFloat("Recoil scale(Cam)", frm.settings.recoil_cam_scale, 0.1, 2.0, "%.2f")
		_, frm.settings.increase_rate_scale =
			ImGui.SliderFloat("Increase Rate", frm.settings.increase_rate_scale, 0.1, 2.0, "%.2f")
		_, frm.settings.handling_speed_scale =
			ImGui.SliderFloat("Handling Speed", frm.settings.handling_speed_scale, 0.1, 2.0, "%.2f")
		ImGui.TreePop()
		if ImGui.Button("Apply Settings", vector2():set(-1, 25)) then
			frm.settings.apply()
		end
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
function renderDebugVars()
	vars = frm.debug_var
	ImGui.TextColored(vector4():set(0.2, 0.9, 0.4, 1), "=== DEBUG VARS ===")
	_, vars.bool0 = ImGui.Checkbox("bool0", vars.bool0)
	_, vars.bool1 = ImGui.Checkbox("bool1", vars.bool1)
	_, vars.float_s1 = ImGui.SliderFloat("float_s1", vars.float_s1, 0, 1, "%.4f")
	_, vars.float_s2 = ImGui.SliderFloat("float_s2", vars.float_s2, 0, 1, "%.4f")
	_, vars.float_x1 = ImGui.SliderFloat("float_x1", vars.float_x1, 0, 50, "%.2f")
	_, vars.float_x2 = ImGui.SliderFloat("float_x2", vars.float_x2, 0, 50, "%.2f")
end

local M = {}
_G.fuzz_recoil_imgui = M
function M.on_game_start()
	hudrc = fuzz_recoil_hud_recoil
end
function M.vector_imgui_text_drawer(vec, label, is_rot)
	local formater = is_rot and "Y: %.5f | P: %.5f | R: %.5f" or "X: %.5f | Y: %.5f | Z: %.5f"
	local info = string.format(formater, vec.x, vec.y, vec.z)
	ImGui.TextColored(vector4():set(0, 1, 0.5, 1), label)
	ImGui.Text(info)
end
function M.vector_imgui_slider_drawer(vec, label, limit, is_rot, is_info)
	limit = limit or 1
	ImGui.Text(label)
	ImGui.PushID(label)
	if is_info then
		ImGui.BeginDisabled(true)
	end
	if is_rot then
		_, vec.x = ImGui.SliderFloat("Yaw", vec.x, -limit, limit, "%.5f")
		_, vec.y = ImGui.SliderFloat("Pitch", vec.y, -limit, limit, "%.5f")
		_, vec.z = ImGui.SliderFloat("Roll", vec.z, -limit, limit, "%.5f")
	else
		_, vec.x = ImGui.SliderFloat("X", vec.x, -limit, limit, "%.5f")
		_, vec.y = ImGui.SliderFloat("Y", vec.y, -limit, limit, "%.5f")
		_, vec.z = ImGui.SliderFloat("Z", vec.z, -limit, limit, "%.5f")
	end
	if is_info then
		ImGui.EndDisabled()
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
	local wpn_name = tostring(utils.get_base_weapon(frm.cur_wpn:section()))

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
