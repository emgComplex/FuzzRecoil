local frm = fuzz_recoil
local utils = fuzz_recoil_utils
local logger = fuzz_recoil_logger
local cvter = fuzz_recoil_converter
local camrc = fuzz_recoil_cam_recoil.instance
local hudrc = fuzz_recoil_hud_recoil.instance
local punchrc = fuzz_recoil_punch
local impacts = fuzz_recoil_impacts
local options = fuzz_recoil_mcm
local modifier = fuzz_recoil_modifier
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
	ImGui.SameLine()
	if ImGui.Button("ToggleOverlays", vector2():set(100, 25)) then
		overlay_toggle = not overlay_toggle
		showPlots = overlay_toggle
		showLogs = overlay_toggle
		showInfo = overlay_toggle
		showProfile = overlay_toggle
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
		if ImGui.Button("ForceResetRecoil", vector2():set(150, 25)) then
			frm.force_reset_recoil()
		end
		--NOTE: useful move to root
		if ImGui.TreeNode("Weapon profile") then
			renderProfile()
			ImGui.TreePop()
		end
		renderOptions()
		if ImGui.TreeNode("Impact Marker") then
			impacts.imgui_settings_drawer()
			ImGui.TreePop()
		end
		renderWeaponSpawner()
		if not fuzz_dev then
			ImGui.Text("Not in dev mode,advanced configs disabled")
			return
		end
		renderExtra()
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
	if expanded then
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
		if ImGui.TreeNode("Vanilla profile") then
			local wpn_info = frm.get_wpn_info()
			for k, v in pairs(wpn_info) do
				text_drawer(k, v)
			end
			ImGui.TreePop()
		end
		ImGui.Separator()
		if ImGui.TreeNode("New profile") then
			ImGui.TextColored(vector4():set(0, 1, 0.5, 1), "Converted")
			for k, v in pairs(frm.get_recoil_profile().raw_profile) do
				text_drawer(k, v)
			end
			ImGui.TreePop()
		end
		if ImGui.TreeNode("Weapon profile viewer") then
			ImGui.PushID("prf_viewer")
			ImGui.BeginDisabled(true)
			renderProfile()
			ImGui.EndDisabled()
			ImGui.PopID()
			ImGui.TreePop()
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
		--NOTE: double calc ,but it's ok for debug
		hdl_power = frm.get_real_handling_power()
		--stylua: ignore
		ImGui.ProgressBar(hdl_power, vector2():set(-1, 0), string.format("Real Handling power: %.1f%%", hdl_power * 100))
		local hdl_fatigue = frm.get_handling_fatigue()
		ImGui.ProgressBar(hdl_fatigue, vector2():set(-1, 0), string.format("Handling fatigue: %.2f", hdl_fatigue))
		ImGui.Separator()
		hudrc.imgui_info_drawer()
		ImGui.Separator()
		camrc.imgui_info_drawer()
	end
	ImGui.End()
end

local _prf_type = 1
local modi_enabled = true
local export_to_gamedata = fuzz_dev and true or false
local force_convert = false
--TODO:! load and apply modifier
--don't forget sort this out ,man
function renderProfile()
	local prf = frm.get_recoil_profile()
	local wpn_sec = frm.get_cur_wpn():section()
	ImGui.Text("To input a value directly,You can crlt+click on the slider")
	ImGui.Text("Profile:")
	for i, v in ipairs({ "Raw(Edit this)", "Static", "Dynamic" }) do
		ImGui.SameLine()
		if ImGui.RadioButton(v, _prf_type == i) then
			_prf_type = i
		end
	end
	local available_prf = { prf.raw_profile, prf.static_profile, prf }
	---@diagnostic disable: param-type-mismatch
	prf.imgui_editor_drawer(available_prf[_prf_type], _prf_type, prf.info.name)

	ImGui.Separator()
	ImGui.Text("Edit without modifier if you want to share your recoil profile")
	if ImGui.Button("Apply profile", vector2():set(200, 25)) then
		prf:reload_modifiers()
		hudrc.cache_profile(prf)
		camrc.cache_profile(prf)
	end
	---@diagnostic enable: param-type-mismatch
	ImGui.SameLine()
	modi_enabled_change, modi_enabled = ImGui.Checkbox("With Modifier", modi_enabled)
	if modi_enabled_change then
		fuzz_recoil.static_modifiers.enabled(modi_enabled)
		fuzz_recoil.dynamic_modifiers.enabled(modi_enabled)
	end
	ImGui.Text(export_hint)
	if ImGui.Button("Export to LTX", vector2():set(150, 25)) then
		export_profile_to_ltx(prf, wpn_sec, export_to_gamedata)
	end
	ImGui.SameLine()
	export_folder_change, export_to_gamedata = ImGui.Checkbox("Gamedata", export_to_gamedata)
	if export_folder_change then
		local dest = export_to_gamedata and "gamedata" or "game's bin"
		export_hint = string.format("Export profile to your %s folder", dest)
	end
	ImGui.SameLine()
	if ImGui.Button("Reload Profile", vector2():set(150, 25)) then
		logger.dbg(wpn_sec)
		fuzz_recoil_profile.set_force_convert(force_convert)
		frm.force_recheck_weapon()
		fuzz_recoil_profile.set_force_convert(false)
	end
	ImGui.SameLine()
	_, force_convert = ImGui.Checkbox("Convert", force_convert)
end
function renderOptions()
	if ImGui.TreeNode("Options") then
		_, options.recoil_cam_scale = ImGui.SliderFloat("Recoil scale(Cam)", options.recoil_cam_scale, -0.9, 2, "%.2f")
		_, options.recoil_h_scale = ImGui.SliderFloat("Recoil scale(Hori) ", options.recoil_h_scale, -0.9, 2, "%.2f")
		_, options.handling_speed_scale =
			ImGui.SliderFloat("Handling Speed", options.handling_speed_scale, -0.9, 2, "%.2f")
		_, options.impulse_fatigue_ratio =
			ImGui.SliderFloat("Fatigue Increase Rate", options.impulse_fatigue_ratio, 0, 0.3, "%.3f")

		_, options.bolt_action_Y_lift = ImGui.Checkbox("Bolt-Action Lift", options.bolt_action_Y_lift)
		_, options.cam_drag = ImGui.SliderFloat("Cam Drag", options.cam_drag, 5.0, 20.0, "%.2f")
		_, options.hud_kick_v2 = ImGui.Checkbox("Tarkov Kick (V2 instant)", options.hud_kick_v2)
		_, options.use_bloom = ImGui.Checkbox("Fire Bloom", options.use_bloom)
		ImGui.Text("Vanilla data extras")
		_, options.use_pitch_frac = ImGui.Checkbox("Pitch Frac Variance", options.use_pitch_frac)
		_, options.use_addon_ammo_koefs = ImGui.Checkbox("Addon & Ammo Koefs", options.use_addon_ammo_koefs)
		_, options.use_zoom_ratio = ImGui.Checkbox("ADS Zoom Ratio", options.use_zoom_ratio)
		ImGui.Text("2Axis cam and Punch")
		_, options.use_punch = ImGui.Checkbox("FOV Punch / Shove", options.use_punch)
		_, options.punch_legacy = ImGui.Checkbox("Punch Legacy (console/PiP)", options.punch_legacy)
		_, options.use_2axis = ImGui.Checkbox("2-Axis Camera (yaw)", options.use_2axis)
		_, options.use_roll = ImGui.Checkbox("Camera Roll (3-axis)", options.use_roll)
		-- _, options.recoil_v_scale =
		-- 	ImGui.SliderFloat("Recoil scale(Vert)", options.recoil_v_scale, -0.9, 2, "%.2f")
		if ImGui.Button("Apply Options", vector2():set(-1, 25)) then
			frm.on_option_change()
		end
		ImGui.TreePop()
	end
end
local cheat_mag = false
local inf_weight = fuzz_dev and true or false
function renderExtra()
	if ImGui.Button("Log Modi") then
		local modi_text = "\nstatic_modifiers =" .. tostring(fuzz_recoil.static_modifiers)
		modi_text = modi_text .. "\n dynamic_modifiers=" .. tostring(fuzz_recoil.dynamic_modifiers)
		logger.dbg(modi_text)
	end
	ImGui.SameLine()
	if ImGui.Button("0Pow") then
		db.actor:change_power(-1)
	end
	ImGui.SameLine()
	if ImGui.Button("0Hun") then
		db.actor:change_satiety(-1)
	end
	ImGui.SameLine()
	if ImGui.Button("1Hun") then
		db.actor:change_satiety(1)
	end
	ImGui.SameLine()
	change_weight, inf_weight = ImGui.Checkbox("Wgt", inf_weight)
	if change_weight then
		if inf_weight then
			weight.add_weight("fuzz_cheat", 8888)
		else
			weight.remove_weight("fuzz_cheat")
		end
	end
	ImGui.SameLine()
	_, cheat_mag = ImGui.Checkbox("InfAmmo", cheat_mag)
end
local allowed_kinds = {
	w_pistol = false,
	w_rifle = false,
	w_shotgun = false,
	w_sniper = false,
	w_smg = false,
}
function renderWeaponSpawner()
	if ImGui.TreeNode("Weapon Spawner") then
		ImGui.Text("Kind")
		local i = 1
		for k, v in pairs(allowed_kinds) do
			if i ~= 4 then
				ImGui.SameLine()
			end
			_, allowed_kinds[k] = ImGui.Checkbox(k, v)
			i = i + 1
		end
		ImGui.SameLine()
		if ImGui.Button("Toogle all", vector2():set(120, 25)) then
			for k, v in pairs(allowed_kinds) do
				allowed_kinds[k] = not v
			end
		end
		if ImGui.Button("Spawn Weapons", vector2():set(120, 25)) then
			utils.get_all_weapon_sections(allowed_kinds, true)
		end
		ImGui.SameLine()
		if ImGui.Button("Dump  Weapons datas (need json.lua)", vector2():set(-1, 25)) then
			utils.get_all_weapon_sections(allowed_kinds)
		end
		ImGui.TreePop()
	end
end
function renderConfig()
	-- ImGui.TextColored(vector4():set(1, 0, 0, 1), "vvvvv DO NOT TOUCH THIS vvvvv")
	-- if ImGui.TreeNode("Config") then
	-- ImGui.TextColored(vector4():set(1, 1, 0, 1), "UNLESS YOU KNOW WHAT YOU ARE DOING")
	frm.imgui_config_drawer()
	camrc.imgui_config_drawer()
	ImGui.Separator()
	hudrc.imgui_config_drawer()
	ImGui.Separator()
	punchrc.imgui_config_drawer()
	-- 	ImGui.TreePop()
	-- end
	--TODO:refactor this to base
	ImGui.Separator()
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

function export_profile_to_ltx(input_profile, wpn_sec, folder_flag)
	local profile = input_profile.raw_profile
	local wpn_name = tostring(utils.get_base_weapon(wpn_sec))

	local filename = string.format("mod_system_z_fuzz_recoil_%s.ltx", wpn_name)
	if folder_flag then
		filename = "../gamedata/configs/" .. filename
	end
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
function M.on_game_start()
	if not fuzz_dev then
		return
	end
	hudrc = fuzz_recoil_hud_recoil
	RegisterScriptCallback("actor_on_weapon_fired", on_fire)
	RegisterScriptCallback("actor_on_first_update", actor_on_first_update)
	-- RegisterScriptCallback("actor_on_update", on_update)
	log("Fuzz:Dev mode enabled")
end
function actor_on_first_update()
	if inf_weight then
		weight.add_weight("fuzz_cheat", 8888)
	end
end
function on_fire()
	if cheat_mag then
		cast_wpn = fuzz_recoil.get_cur_wpn():cast_Weapon()
		cast_wpn:SetAmmoElapsed(30)
		cast_wpn:SetMisfire(false)
	end
end
