local frm = fuzz_recoil
local utils = fuzz_recoil_utils
local logger = fuzz_recoil_logger
local cvter = fuzz_recoil_converter
local camrc = fuzz_recoil_cam_recoil.instance
local hudrc = fuzz_recoil_hud_recoil.instance
local impacts = fuzz_recoil_impacts
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
		if frm.check_current_weapon() then
			debug_text1 = frm.get_cur_wpn():section() .. ":" .. frm.get_cur_wpn_id()
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
	--TODO: pass wpn,id,sec to render funcs
	local cur_wpn = frm.get_cur_wpn()
	if cur_wpn then
		ImGui.TextColored(vector4():set(0, 1, 0, 1), "Weapon: " .. cur_wpn:section())
		ImGui.Separator()
		if ImGui.Button("ResetHand") then
			hudrc.reset_hud_hand()
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

--NOTE: all windows must draw inside imgui_on_render (main thread, open frame)
--raw AddUniqueCall drawing races the render thread when mt_level_call is on
ImGui.Groups.Main.Widget(function()
	if showImguiWin then
		renderImguiWindow()
	end
end)
--overlays stay visible during gameplay, Unique group renders every frame
ImGui.Groups.Unique.Widget(function()
	log_overlay()
	plot_overlay()
	profile_overlay()
	info_overlay()
end)
ImGui.Groups.Mods.Widget(function()
	_, showImguiWin = ImGui.MenuItem("FuzzRecoil", nil, showImguiWin, true)
end)

-- Force scroll if the user was already at the bottom, or if a new item triggered a scroll
function log_overlay()
	if not showLogs then
		return
	end
	ImGui.SetNextWindowSize(vector2():set(400, 200), ImGuiCond.FirstUseEver)
	expanded, _ = ImGui.Begin("Recoil Log", true)
	if expanded and frm.get_cur_wpn() then
		-- Force scroll if the user was already at the bottom, or if a new item triggered a scroll
		ImGui.Text(logger.get_log_text())
		if auto_scroll_logs and ImGui.GetScrollY() >= ImGui.GetScrollMaxY() then
			ImGui.SetScrollHereY(1.0)
		end
	end
	ImGui.End()
end

local cam_angle_plot = LinePlotHack.new(300, 300, 1)
local handling_power_plot = LinePlotHack.new(300, 300, 1)
function plot_overlay()
	if not showPlots then
		return
	end
	ImGui.SetNextWindowSize(vector2():set(300, 600), ImGuiCond.FirstUseEver)
	expanded, _ = ImGui.Begin("Histogram", true)
	if expanded and frm.get_cur_wpn() then
		if ImGui.TreeNode("cam_angle") then
			local new_val = frm.is_active() and camrc.get_angle() or nil
			cam_angle_plot:draw(new_val)
			ImGui.TreePop()
		end
		if ImGui.TreeNode("handling_power") then
			new_val = frm.is_active() and frm.get_handling_power() or nil
			handling_power_plot:draw(new_val)
			ImGui.TreePop()
		end
	end
	ImGui.End()
end

function profile_overlay()
	if not showProfile then
		return
	end
	ImGui.SetNextWindowSize(vector2():set(400, 600), ImGuiCond.FirstUseEver)
	local function text_drawer(label, val)
		if type(val) == "number" then
			ImGui.Text(string.format("%s:%.5f", label, val))
		elseif type(val) == "boolean" then
			_, _ = ImGui.Checkbox(label, val)
		end
	end
	expanded, _ = ImGui.Begin("Weapon Profile", true)
	local cur_wpn = frm.get_cur_wpn()
	if expanded and cur_wpn then
		ImGui.Text(cur_wpn:section() .. ":" .. frm.get_cur_wpn_id())
		local wpn_info = frm.get_wpn_info()
		for k, v in pairs(wpn_info) do
			text_drawer(k, v)
		end
		ImGui.Separator()
		ImGui.TextColored(vector4():set(0, 1, 0.5, 1), "Converted")
		for k, v in pairs(frm.get_recoil_profile().raw_profile) do
			text_drawer(k, v)
		end
	end
	ImGui.End()
end

function info_overlay()
	if not showInfo then
		return
	end
	ImGui.SetNextWindowSize(vector2():set(400, 600), ImGuiCond.FirstUseEver)
	expanded, _ = ImGui.Begin("Recoil Info", true)
	if expanded and frm.get_cur_wpn() then
		ImGui.Separator()

		ImGui.Text(
			string.format(
				"Active:%s,Firing:%s,Cam_FX:%s",
				frm.is_active(),
				frm.is_firing(),
				camrc.has_camera_effector()
			)
		)
		ImGui.Text(string.format("CamRetrun:%s,HudReturn:%s", camrc.is_returned(), hudrc.is_returned()))

		local hdl_power = frm.get_handling_power()
		ImGui.ProgressBar(hdl_power, vector2():set(-1, 0), string.format("Handling power: %.1f%%", hdl_power * 100))
		ImGui.Separator()
		hudrc.imgui_info_drawer()
		ImGui.Separator()
		camrc.imgui_info_drawer()
	end
	ImGui.End()
end

--TODO:! load and apply modifier
--don't forget sort this out ,man
function renderProfile()
	if ImGui.TreeNode("Weapon profile") then
		local prf = frm.get_recoil_profile()
		local wpn_sec = frm.get_cur_wpn():section()
		ImGui.Text("To input a value directly,You can crlt+click on the slider")
		prf:imgui_editor_drawer()
		ImGui.Text(export_hint)
		if ImGui.Button("Apply", vector2():set(-1, 25)) then
			hudrc.cache_profile(prf)
			camrc.cache_profile(prf)
		end
		if ImGui.Button("Export to LTX", vector2():set(-1, 25)) then
			export_profile_to_ltx(prf, wpn_sec)
		end
		if ImGui.Button("Reload Profile", vector2():set(-1, 25)) then
			frm.init_weapon(wpn_sec)
		end
		ImGui.TreePop()
	end
end
function renderConfig()
	ImGui.TextColored(vector4():set(1, 0, 0, 1), "vvvvv DO NOT TOUCH THIS vvvvv")
	if ImGui.TreeNode("Config") then
		ImGui.TextColored(vector4():set(1, 1, 0, 1), "UNLESS YOU KNOW WHAT YOU ARE DOING")
		frm.imgui_config_drawer()
		camrc.imgui_config_drawer()
		ImGui.Separator()
		hudrc.imgui_config_drawer()
		if ImGui.Button("Dump All Weapon datas(need json.lua)", vector2():set(-1, 25)) then
			utils.get_all_weapon_sections()
		end
		ImGui.Separator()
		ImGui.Text("Settings")
		_, frm.settings.hud_kick_v2 = ImGui.Checkbox("Tarkov Kick (V2 instant)", frm.settings.hud_kick_v2)
		_, frm.settings.use_bloom = ImGui.Checkbox("Fire Bloom", frm.settings.use_bloom)
		impacts.imgui_settings_drawer()
		_, frm.settings.bolt_action_Y_lift = ImGui.Checkbox("Bolt-Action Lift", frm.settings.bolt_action_Y_lift)
		_, frm.settings.cam_drag = ImGui.SliderFloat("Cam Drag", frm.settings.cam_drag, 5.0, 20.0, "%.2f")
		ImGui.Text("Vanilla data extras")
		_, frm.settings.use_pitch_frac = ImGui.Checkbox("Pitch Frac Variance", frm.settings.use_pitch_frac)
		_, frm.settings.use_cam_max_angle = ImGui.Checkbox("Cam Max Angle Cap", frm.settings.use_cam_max_angle)
		_, frm.settings.use_addon_ammo_koefs = ImGui.Checkbox("Addon & Ammo Koefs", frm.settings.use_addon_ammo_koefs)
		_, frm.settings.use_increase_rate = ImGui.Checkbox("Burst Expansion", frm.settings.use_increase_rate)
		_, frm.settings.use_zoom_ratio = ImGui.Checkbox("ADS Zoom Ratio", frm.settings.use_zoom_ratio)
		_, frm.settings.recoil_v_scale =
			ImGui.SliderFloat("Recoil scale(Vert)", frm.settings.recoil_v_scale, -2, 2, "%.2f")
		_, frm.settings.recoil_h_scale =
			ImGui.SliderFloat("Recoil scale(Hori) ", frm.settings.recoil_h_scale, -2, 2, "%.2f")
		_, frm.settings.recoil_cam_scale =
			ImGui.SliderFloat("Recoil scale(Cam)", frm.settings.recoil_cam_scale, -2, 2, "%.2f")
		_, frm.settings.increase_rate_scale =
			ImGui.SliderFloat("Increase Rate", frm.settings.increase_rate_scale, -2, 2, "%.2f")
		_, frm.settings.handling_speed_scale =
			ImGui.SliderFloat("Handling Speed", frm.settings.handling_speed_scale, -2, 2, "%.2f")
		ImGui.TreePop()
		if ImGui.Button("Apply Settings", vector2():set(-1, 25)) then
			frm.apply_settings()
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

function export_profile_to_ltx(input_profile, wpn_sec)
	local profile = input_profile.raw_profile
	local wpn_name = tostring(utils.get_base_weapon(wpn_sec))

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
