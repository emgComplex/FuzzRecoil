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
local M = {}
_G.fuzz_recoil_profile = M

local default_profile = {
	is_bolt_action = false,
	cam_recoil_power = 4,
	cam_return_speed = 1,
	--0 means uncapped, radians like cam angle
	cam_max_angle = 0,
	--1 means no per shot variance
	pitch_frac = 1,
	--ads kick relative to hip, from vanilla zoom_cam_dispersion/cam_dispersion
	zoom_ratio = 1,

	force_pitch = 15,
	force_y = -0.04,
	force_yaw = 15,
	force_x = 0.0006,
	--shoulder push, z pop per shot
	force_z = 0.006,

	pull_force = 1.5,
	firing_damping = 1.0,
	-- hud_return_speed = 1,

	handling_speed = 0.5,
	--per shot growth ratio, kick = base*(1 + increase_rate*burst_shot_index)
	increase_rate = 0,
	--deterministic weapon class, drives burst heat
	burst_class = "other",

	-- TODO: need a better name for shot_delay
	-- shot_delay
	shot_delay_enabled = false,
	shot_delay_time = 0.4,
	shot_cam_impulse_factor = 0.2,

	--TODO:NOT IMPLEMENTED
	stamina_factor = 1,
	-- mass_inertia = -1,
	-- hidden vars
	fire_interval = 0.1,
}
M.__index = M
M.raw_profile = {}
setmetatable(M, { __index = default_profile })

function M.shallow_copy(target, source)
	--TODO: very scary my friend...
	target = target or {}
	for k, v in pairs(source) do
		if type(v) == "number" or type(v) == "boolean" then
			target[k] = v
		end
	end
end

function M:new()
	local ins = {}
	setmetatable(ins, M)
	ins.raw_profile = {}
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
		self.increase_rate = utils.get_float(prf_sec, "increase_rate", 0)
		self.stamina_factor = utils.get_float(prf_sec, "stamina_factor", 0)
	else
		cvter.convert(wpn_info, self)
		cvter.convert(wpn_info, self:new())
	end
	return self
end

function M:load(wpn_sec, wpn_info)
	self.fire_interval = 60 / wpn_info.rpm

	self:read_profile(wpn_sec, wpn_info)

	self:process_shot_delay(wpn_info)
	self.burst_class = classify_burst_class(wpn_info.kind, wpn_info.mag_size)

	local raw_table = {}
	M.shallow_copy(raw_table, self)
	self.raw_profile = raw_table
	-- logger.print_table(self)
	return self
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

function M:restore()
	self:shallow_copy(self.raw_profile)
	return self
end

---------------
---IMGUI
---------------
--TODO:! should edit raw
function M:imgui_editor_drawer()
	_, self.is_bolt_action = ImGui.Checkbox("Bolt Action", self.is_bolt_action)
	ImGui.Text("Camera recoil")
	_, self.cam_recoil_power = ImGui.SliderFloat("Cam Recoil Power", self.cam_recoil_power, 0.1, 16.0, "%.2f")
	_, self.cam_return_speed = ImGui.SliderFloat("Cam Return Speed", self.cam_return_speed, 0.5, 2, "%.2f")
	_, self.cam_max_angle = ImGui.SliderFloat("Cam Max Angle", self.cam_max_angle, 0, 1, "%.3frad")
	_, self.pitch_frac = ImGui.SliderFloat("Pitch Frac", self.pitch_frac, 0, 1, "%.2f")
	_, self.zoom_ratio = ImGui.SliderFloat("Zoom Ratio", self.zoom_ratio, 0.25, 2, "%.2f")

	ImGui.Text("Hud Recoil")
	_, self.pull_force = ImGui.SliderFloat("Pull Force", self.pull_force, 0.1, 4.0, "%.2f")
	_, self.firing_damping = ImGui.SliderFloat("Spring Damping", self.firing_damping, 0.1, 4.0, "%.2f")
	ImGui.Text("Shot Impact Force")
	_, self.force_pitch = ImGui.SliderFloat("Pitch", self.force_pitch, 0, 60, "%.2f")
	_, self.force_y = ImGui.SliderFloat("PosY", self.force_y, -0.06, 0.06, "%.4f")
	self.force_y = self.force_y
	_, self.force_yaw = ImGui.SliderFloat("Yaw", self.force_yaw, 0, 60, "%.2f")
	_, self.force_x = ImGui.SliderFloat("PosX", self.force_x, 0.0001, 0.0025, "%.4f")
	_, self.force_z = ImGui.SliderFloat("PosZ (shoulder)", self.force_z, 0.0, 0.02, "%.4f")
	self.force_x = self.force_x

	ImGui.Text("Handling")
	handle_speed_change, self.handling_speed =
		ImGui.SliderFloat("Handling speed", self.handling_speed, 0.1, 2.0, "%.2f")
	if handle_speed_change then
		fuzz_recoil.set_handling_speed(self.handling_speed)
	end
	_, self.increase_rate = ImGui.SliderFloat("Increase Rate", self.increase_rate, 0.0, 2.0, "%.2f")
	ImGui.Separator()
end
