---------------
---import
---------------
local utils = fuzz_recoil_utils
local cvter = fuzz_recoil_converter
local logger = fuzz_recoil_logger
---------------
---config
---------------
local shot_delay_table = {
	w_sniper = { rpm = 60, cam_impulse = 1 },
	w_shotgun = { rpm = 250, cam_impulse = 0.7 },
	w_pistol = { rpm = 340, cam_impulse = 0.4 },
}
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
---@field force_pitch number
---@field force_y number
---@field force_yaw number
---@field force_x number
---@field force_z number
---@field handling_speed number
---@field pull_force number
---@field firing_damping number
---@field zoom_ratio number
---@field is_bolt_action boolean
---@field fire_interval number
---@field pitch_frac number
---
---@field burst_class string
---@field shot_delay_enabled boolean
---@field shot_delay_time number
---@field shot_cam_impulse_factor number

---@type FuzzRecoilProfile
local default_profile = {

	cam_recoil_power = 4,
	cam_return_speed = 1,

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
	fire_interval = 0.1,
	--1 means no per shot variance
	pitch_frac = 1,

	--deterministic weapon class, drives burst heat
	burst_class = "other",

	-- TODO: need a better name for shot_delay
	-- shot_delay
	shot_delay_enabled = false,
	shot_delay_time = 0.4,
	shot_cam_impulse_factor = 0.2,

	--NOTE: CONSIDER REMOVE
	--0 means uncapped, radians like cam angle
	cam_max_angle = 0,
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
function M.shallow_copy(source, target)
	target = target or {}
	--NOTE: use default_profile as indexer to make sure we copied everything
	for k, v in pairs(default_profile) do
		if type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
			target[k] = v
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

--TODO: fallback to converter if missing parameter?
function M:read_profile(wpn_sec, wpn_info)
	local prf_sec = ini_sys:r_string_ex(wpn_sec, "fuzz_recoil", nil)
	if prf_sec then
		self.is_bolt_action = utils.get_bool(prf_sec, "is_bolt_action", false)
		self.cam_recoil_power = utils.get_float(prf_sec, "cam_recoil_power", 4)
		self.cam_return_speed = utils.get_float(prf_sec, "cam_return_speed", 1)
		self.cam_max_angle = utils.get_float(prf_sec, "cam_max_angle", 0)
		self.pitch_frac = utils.math_clamp(utils.get_float(prf_sec, "pitch_frac", 1), 0, 1)
		self.zoom_ratio = utils.math_clamp(utils.get_float(prf_sec, "zoom_ratio", 1), 0.25, 2)
		self.force_pitch = utils.get_float(prf_sec, "force_pitch", 15)
		self.force_y = utils.get_float(prf_sec, "force_y", -0.04)
		self.force_yaw = utils.get_float(prf_sec, "force_yaw", 15)
		self.force_x = utils.get_float(prf_sec, "force_x", 0)
		self.force_z = utils.get_float(prf_sec, "force_z", 0.006)
		self.pull_force = utils.get_float(prf_sec, "pull_force", 1.5)
		self.firing_damping = utils.get_float(prf_sec, "firing_damping", 1)
		self.handling_speed = utils.get_float(prf_sec, "handling_speed", 0.5)

		self.info.is_converted = false
	else
		cvter.convert(wpn_info, self)
		cvter.convert(wpn_info, self:new())
		self.info.is_converted = true
	end
	return self
end

function M:load(wpn_sec, wpn_info)
	self.info.name = utils.get_base_weapon(wpn_sec)

	self.fire_interval = 60 / wpn_info.rpm

	self:read_profile(wpn_sec, wpn_info)

	self:process_shot_delay(wpn_info)
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

function M:process_shot_delay(wpn_info)
	-- NOTE: or we can just check available firemodes?
	local skind = shot_delay_table[wpn_info.kind]
	if skind and wpn_info.rpm <= skind.rpm then
		self.shot_delay_enabled = true
		self.shot_delay_time = utils.math_clamp(self.fire_interval, 0.1, 0.5)
		self.shot_cam_impulse_factor = skind.cam_impulse
	end
	return self
end

---------------
---IMGUI
---------------

function M.imgui_editor_drawer(_prf, _prf_type, _prf_name)
	ImGui.PushID("profile" .. _prf_type)
	ImGui.BeginDisabled(_prf_type ~= "raw")
	ImGui.Text(_prf_name)
	ImGui.Separator()
	_, _prf.is_bolt_action = ImGui.Checkbox("Bolt Action", _prf.is_bolt_action)

	ImGui.Text("Camera recoil")
	_, _prf.cam_recoil_power = ImGui.SliderFloat("Cam Recoil Power", _prf.cam_recoil_power, 0.1, 16.0, "%.2f")
	_, _prf.cam_return_speed = ImGui.SliderFloat("Cam Return Speed", _prf.cam_return_speed, 0.5, 2, "%.2f")
	_, _prf.cam_max_angle = ImGui.SliderFloat("Cam Max Angle", _prf.cam_max_angle, 0, 1, "%.3frad")
	_, _prf.pitch_frac = ImGui.SliderFloat("Pitch Frac", _prf.pitch_frac, 0, 1, "%.2f")
	_, _prf.zoom_ratio = ImGui.SliderFloat("Zoom Ratio", _prf.zoom_ratio, 0.25, 2, "%.2f")

	ImGui.Text("Hud Recoil")
	_, _prf.pull_force = ImGui.SliderFloat("Pull Force", _prf.pull_force, 0.1, 4.0, "%.2f")
	_, _prf.firing_damping = ImGui.SliderFloat("Spring Damping", _prf.firing_damping, 0.1, 4.0, "%.2f")

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
	ImGui.Text("Handling")
	local handle_speed_change
	handle_speed_change, _prf.handling_speed =
		ImGui.SliderFloat("Handling speed", _prf.handling_speed, 0.1, 2.0, "%.2f")
	if handle_speed_change then
		fuzz_recoil.set_handling_speed(_prf.handling_speed)
	end

	ImGui.EndDisabled()
	ImGui.PopID()
end
