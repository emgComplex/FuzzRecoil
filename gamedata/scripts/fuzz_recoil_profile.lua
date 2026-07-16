---------------
---import
---------------
local utils = fuzz_recoil_utils
local cvter = fuzz_recoil_converter
local logger = fuzz_recoil_logger
---------------
---config
---------------
---------------
---object
---------------
---@class fuzz_recoil_profile
local M = {}
_G.fuzz_recoil_profile = M
M.__index = M

---@class FuzzRecoilProfile
---@field cam_recoil_power number
---@field cam_return_speed number
---@field cam_max_angle number
---
---@field force_pitch number
---@field force_y number
---@field force_yaw number
---@field force_x number
---@field force_z number
---
---@field handling_speed number
---@field pull_force number
---@field firing_damping number
---
---@field zoom_ratio number
---@field is_bolt_action boolean
---@field desync_hud boolean
---@field pitch_frac number
---
---@field burst_class string
---
---@field shot_delay_enabled boolean
---@field shot_delay_time number
---@field shot_cam_impulse_factor number
---
---@field fire_interval number

--WARN:don forget the convert_list,i know this sucks

---@type FuzzRecoilProfile
local default_profile = {

	cam_recoil_power = 4,
	cam_return_speed = 1,
	--0 means uncapped, radians like cam angle
	cam_max_angle = 0.9999,

	force_pitch = 15,
	force_y = -0.04,
	force_yaw = 15,
	force_x = 0.0006,
	--shoulder push, z pop per shot
	force_z = 0.006,

	handling_speed = 0.5,
	pull_force = 1.5,
	firing_damping = 1.0,

	--ads kick relative to hip, from vanilla zoom_cam_dispersion/cam_dispersion
	zoom_ratio = 1,
	is_bolt_action = false,
	desync_hud = false,
	--1 means no per shot variance
	pitch_frac = 1,

	--deterministic weapon class, drives burst heat
	burst_class = "other",

	-- TODO: need a better name for shot_delay
	-- shot_delay
	shot_delay_enabled = false,
	shot_delay_time = 0.4,
	shot_cam_impulse_factor = 0.2,
	fire_interval = 0.1,
}
setmetatable(M, { __index = default_profile })
M.raw_profile = {}
M.static_profile = {}
M.info = {
	name = "w_nil_profile",
	is_converted = true,
}

---------------
---intenal functions
---------------
local force_convert = false
function M.set_force_convert(flag)
	force_convert = flag
end
function M.shallow_copy(source, target)
	target = target or {}
	--NOTE: use default_profile as indexer to make sure we copied everything
	for k, v in pairs(default_profile) do
		if type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
			target[k] = source[k]
		end
	end
end
---------------
---Methods
---------------
---@return fuzz_recoil_profile
function M:new()
	local ins = {}
	setmetatable(ins, M)
	ins.raw_profile = {}
	setmetatable(ins.raw_profile, M)
	ins.static_profile = {}
	setmetatable(ins.static_profile, M)
	return ins
end

--belt or drum feed is the lmg tell
local function classify_burst_class(kind, mag_size)
	if kind == "w_smg" then
		return "smg"
	end
	if kind == "w_pistol" then
		return "pistol"
	end
	if kind == "w_rifle" then
		return (mag_size or 30) >= 50 and "lmg" or "ar"
	end
	return "other"
end

function M:read_profile(wpn_sec, wpn_info, prf_sec)
	if prf_sec and not force_convert then
		------------Basic reading---------------------
		local convert_list = {
			--stylua: ignore start
			cam_recoil_power = { type = 2, read = false },
			cam_return_speed = { type = 2, read = false },

			force_pitch      = { type = 2, read = false },
			force_y          = { type = 2, read = false },
			force_z          = { type = 2, read = false },
			force_x          = { type = 2, read = false },
			force_yaw        = { type = 2, read = false },

			pull_force       = { type = 2, read = false },
			firing_damping   = { type = 2, read = false },
			handling_speed   = { type = 2, read = false },

			is_bolt_action   = { type = 1, read = false },
			desync_hud       = { type = 1, read = false },
			zoom_ratio       = { type = 2, read = false },

			pitch_frac       = { type = 2, read = false },
			cam_max_angle    = { type = 2, read = false },
			--stylua: ignore end
		}
		---@diagnostic disable: need-check-nil
		for param, v in pairs(convert_list) do
			local result = SYS_GetParam(v.type, prf_sec, param)
			v.read = not (result == nil)
			self[param] = result
		end
		---@diagnostic enable: need-check-nil

		for param, v in pairs(convert_list) do
			if not v.read then
				local cvt_result = cvter.convert(param, wpn_info)
				if cvt_result ~= nil then
					self[param] = cvt_result
				else
					logger.err("convertion failed at param %s", param)
					-- NOTE:
					-- NO ERROR handling and can't throw ,good luck...
				end
			end
		end
		---------------------------------

		self.info.is_converted = false
	else
		cvter.convert(wpn_info, self)
		self.info.is_converted = true
	end
end

function M:load(wpn_sec, wpn_info)
	self.info.name = utils.get_base_weapon(wpn_sec)

	self.fire_interval = 60 / wpn_info.rpm

	local prf_sec = ini_sys:r_string_ex(wpn_sec, "fuzz_recoil", nil)
	self:read_profile(wpn_sec, wpn_info, prf_sec)

	self:process_shot_delay(wpn_info, prf_sec)
	self.burst_class = classify_burst_class(wpn_info.kind, wpn_info.mag_size)

	local raw_table = {}
	self:shallow_copy(raw_table)

	local static_table = {}
	self:shallow_copy(static_table)

	self.raw_profile = raw_table
	self.static_profile = static_table

	return self
end

---@param modi fuzz_recoil_modifier
function M:_apply_modifiers(modi, label, source, target, extra_target)
	if not modi then
		logger.err("no %s modifier found for %s", label, self.info.name)
		return self
	end
	modi:apply_modifiers(source, target, extra_target)
	return self
end
function M:apply_static_modifiers()
	return self:_apply_modifiers(fuzz_recoil.static_modifiers, "static", self.raw_profile, self.static_profile, self)
	-- logger.print_table(self.static_profile)
end
function M:apply_dynamic_modifiers()
	local result = self:_apply_modifiers(fuzz_recoil.dynamic_modifiers, "dynamic", self.static_profile, self)
	-- logger.dbg("Applying dynamic modifiers for %s", self.name)
	-- logger.print_table(self.raw_profile)
	-- logger.dbg("------------------------")
	-- logger.print_table(self.static_profile)
	-- logger.dbg("------------------------")
	-- logger.print_table(self)
	return result
end
function M:RestoreFromRaw()
	M.shallow_copy(self.raw_profile, self.static_profile)
	M.shallow_copy(self.raw_profile, self)
end
function M:reload_modifiers()
	self:RestoreFromRaw()
	return self:apply_static_modifiers():apply_dynamic_modifiers()
end

function M:process_shot_delay(wpn_info, prf_sec)
	--EVEN worse,i guess
	if prf_sec then
		local e = SYS_GetParam(1, prf_sec, "shot_delay_enabled")
		if e ~= nil then
			self.shot_delay_enabled = e
			if not e then
				return self
			end
			local t = SYS_GetParam(2, prf_sec, "shot_delay_time")
			local f = SYS_GetParam(2, prf_sec, "shot_cam_impulse_factor")
			if t and f then
				self.shot_delay_time = t
				self.shot_cam_impulse_factor = f
				return self
			end
		end
	end
	cvter.get_shot_delay(self, wpn_info)
	return self
end

---------------
---IMGUI
---------------

---@param _prf FuzzRecoilProfile
function M.imgui_editor_drawer(_prf, _prf_type, _prf_name)
	ImGui.PushID("profile" .. _prf_type)
	ImGui.BeginDisabled(_prf_type > 1)
	ImGui.Text(_prf_name)
	ImGui.Separator()
	_, _prf.is_bolt_action = ImGui.Checkbox("Bolt Action", _prf.is_bolt_action)
	ImGui.SameLine()
	_, _prf.desync_hud = ImGui.Checkbox("Cam desync hud", _prf.desync_hud)

	ImGui.Text("Camera recoil")
	_, _prf.cam_recoil_power = ImGui.SliderFloat("Cam Recoil Power", _prf.cam_recoil_power, 0.1, 16.0, "%.2f")
	_, _prf.cam_return_speed = ImGui.SliderFloat("Cam Return Speed", _prf.cam_return_speed, -1, 2, "%.2f")
	_, _prf.cam_max_angle = ImGui.SliderFloat("Cam Max Angle", _prf.cam_max_angle, 0, 1, "%.3frad")

	ImGui.Text("Hud Recoil")
	_, _prf.pull_force = ImGui.SliderFloat("Pull Force", _prf.pull_force, 0.1, 4.0, "%.2f")
	_, _prf.firing_damping = ImGui.SliderFloat("Spring Damping", _prf.firing_damping, 0.1, 4.0, "%.2f")
	ImGui.Separator()
	ImGui.Text("Handling")
	local handle_speed_change
	handle_speed_change, _prf.handling_speed =
		ImGui.SliderFloat("Handling speed", _prf.handling_speed, 0.1, 2.0, "%.2f")
	if handle_speed_change then
		fuzz_recoil.set_handling_speed(_prf.handling_speed)
	end

	ImGui.Text("Shot Impact Force")
	_, _prf.force_pitch = ImGui.SliderFloat("Pitch", _prf.force_pitch, 0, 60, "%.2f")
	_, _prf.force_y = ImGui.SliderFloat("PosY", _prf.force_y, -0.06, 0.06, "%.4f")
	_, _prf.force_yaw = ImGui.SliderFloat("Yaw", _prf.force_yaw, 0, 60, "%.2f")
	_, _prf.force_x = ImGui.SliderFloat("PosX", _prf.force_x, 0.0001, 0.0025, "%.4f")
	_, _prf.force_z = ImGui.SliderFloat("PosZ (shoulder)", _prf.force_z, 0.0, 0.02, "%.4f")

	ImGui.Separator()
	ImGui.Text("Shot Delay")
	_, _prf.shot_delay_enabled = ImGui.Checkbox("Enabled", _prf.shot_delay_enabled)
	ImGui.BeginDisabled(not _prf.shot_delay_enabled)
	_, _prf.shot_delay_time = ImGui.SliderFloat("Shot Delay Time", _prf.shot_delay_time, 0.0, 1.0, "%.3f")
	ImGui.EndDisabled()
	_, _prf.shot_cam_impulse_factor =
		ImGui.SliderFloat("Shot Cam Impulse Factor", _prf.shot_cam_impulse_factor, 0.0, 5.0, "%.3f")

	ImGui.Separator()
	ImGui.Text("Misc")
	_, _prf.pitch_frac = ImGui.SliderFloat("Pitch Frac", _prf.pitch_frac, 0, 1, "%.2f")
	_, _prf.zoom_ratio = ImGui.SliderFloat("Zoom Ratio", _prf.zoom_ratio, 0.25, 2, "%.2f")

	ImGui.EndDisabled()
	ImGui.PopID()
end
