-- overwrite vector operators
local M = {}
_G.fuzz_recoil_utils = M
local logger = fuzz_recoil_logger
local frm = fuzz_recoil

---------------
---Engine
--------------
function M.get_string(sec, param, def)
	return SYS_GetParam(0, sec, param, def ~= nil and def or "")
end
function M.get_bool(sec, param, def)
	--SYS_GetParam drops the caller def for bools and returns nil on missing keys
	local v = SYS_GetParam(1, sec, param)
	if v == nil then
		return def or false
	end
	return v
end
function M.get_float(sec, param, def)
	return SYS_GetParam(2, sec, param, def ~= nil and def or 0.0)
end
--NOTE: recusive needed?
function M.get_base_weapon(wpn_sec)
	local parent_section = ini_sys:r_string_ex(wpn_sec, "parent_section")
	if parent_section and wpn_sec ~= parent_section then
		return M.get_base_weapon(parent_section)
	else
		return wpn_sec
	end
end

---------------
---math
--------------
function M.math_clamp(val, min, max)
	return math.max(min, math.min(max, val))
end
function M.lerp_in(val, from, to)
	return M.math_clamp(M.lerp(val, from, to), from, to)
end
function M.lerp(val, from, to)
	return val * (to - from) + from
end
function M.range_lerp(val, from, to, offset, clamp)
	if not offset then
		offset = 0
	end
	if clamp then
		val = M.math_clamp(val, from.min, from.max)
	end
	local range = from.max - from.min
	if range == 0 then
		return to.min + offset
	end
	return (val - from.min) / range * (to.max - to.min) + to.min + offset
end
function M.math_sign(val)
	return val >= 0 and 1 or -1
end
function M.vector_clamp_with_sign(val, min)
	local flag = val < 0
	local sign = flag and -1 or 1
	local magnitude = math.max(math.abs(val), min)
	return magnitude * sign
end
function M.vector_lerp(from, to, t)
	return vector():set(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t, from.z + (to.z - from.z) * t)
end
function M.vector_to_string(vec)
	return string.format("x:%.4f,y:%.4f,z:%.4f", vec.x, vec.y, vec.z)
end
---------------
---Physics and ease
--------------

---@param raw_val any
---@param vel number
---@param dt number delta time
---@param spring number
---@param damping? number critical damping if nil
---@return number updated_val
---@return number updated_vel
function M.apply_spring(raw_val, vel, dt, spring, damping)
	if not damping then
		--critical damping solved exactly, identical motion at any fps
		local w = math.sqrt(spring)
		local e = math.exp(-w * dt)
		local a = vel + w * raw_val
		return (raw_val + a * dt) * e, (vel - a * w * dt) * e
	end
	--TODO: switch to solution for better fps adaption
	dt = math.min(dt, 1 / 30)
	local acc = raw_val * -spring - vel * damping
	vel = vel + acc * dt
	return raw_val + vel * dt, vel
end

---@class simple_ease
---@field base_speed number
---@field speed_mul number
---@field offset number
---@field offset_def number
---@field intensity number
---@field intensity_def number
---@field is_ease_in string
M.simple_ease = {}
M.simple_ease.__index = M.simple_ease
---@return simple_ease
function M.simple_ease.new(base_speed, speed_mul, offset, intensity, mode)
	local ins = {
		base_speed = base_speed,
		speed_mul = speed_mul,
		offset = offset,
		offset_def = offset,
		intensity = intensity,
		intensity_def = intensity,
		is_ease_in = (mode == "in"),
	}
	setmetatable(ins, M.simple_ease)
	return ins
end
function M.simple_ease:set_speed(speed)
	self.base_speed = speed * self.speed_mul
end
function M.simple_ease:update(progress, dt)
	local p_factor = self.is_ease_in and progress or (1 - progress)
	local eased_speed = self.base_speed * (self.offset + self.intensity * p_factor) * dt
	local new_p = progress + eased_speed
	return new_p
end
function M.simple_ease:draw_imgui(label)
	if ImGui.TreeNode(label) then
		_, self.offset = ImGui.SliderFloat("Offset", self.offset, 0.1, 10, "%.2f")
		_, self.intensity = ImGui.SliderFloat("Intensity", self.intensity, 0.1, 10, "%.2f")
		ImGui.TreePop()
	end
end
function M.simple_ease:reset()
	self.offset = self.offset_def
	self.intensity = self.intensity_def
end
--===========================
--Dump weapons
--===========================
--Credit:@verdatim
local dumped_weapons = {}
local iteration_result = ""
local ini_loadouts = ini_file_ex("items\\settings\\npc_loadouts\\npc_loadouts.ltx")
local disallowed_sections = {}
local allowed_sections = {}
local m_allowed_kinds = {
	w_pistol = true,
	w_rifle = true,
	w_shotgun = true,
	w_sniper = true,
	w_smg = true,
}

function M.get_all_weapon_sections(allowed_kinds, action, postaction)
	dumped_weapons = {}
	M.iterate_action = action
	m_allowed_kinds = allowed_kinds

	local scripted_loadouts = ini_loadouts:collect_section("loadouts_per_name")
	for i, v in pairs(scripted_loadouts) do
		local primary_loadout = ini_loadouts:r_string_ex(v, "primary") or "nil"
		local secondary_loadout = ini_loadouts:r_string_ex(v, "secondary") or "nil"
		local extra_loadout = ini_loadouts:r_string_ex(v, "extra") or "nil"

		disallowed_sections[primary_loadout] = true
		disallowed_sections[secondary_loadout] = true
		disallowed_sections[extra_loadout] = true
		--NOTE: fixed typo
		logger.dbg("made these sections disallowed: %s, %s, %s", primary_loadout, secondary_loadout, extra_loadout)
	end

	ini_loadouts:section_for_each(loadout_exists_iterator)

	ini_loadouts:section_for_each(iterator)
	if postaction then
		postaction()
	end
end
function loadout_exists_iterator(section)
	-- checks if a loadout section is mentioned in any stalker loadout section; exists just in case sections that arent assigned to any loadout exists
	local primary = ini_loadouts:r_string_ex(section, "primary") or "nil"
	local secondary = ini_loadouts:r_string_ex(section, "secondary") or "nil"
	local extra = ini_loadouts:r_string_ex(section, "extra") or "nil"
	allowed_sections[primary] = true
	allowed_sections[secondary] = true
	allowed_sections[extra] = true
end
function iterator(section)
	-- logger.dbg("iterator called")

	--checks if loadout is a 'scripted' loadout, i.e. probably not 'valid'
	if disallowed_sections[section] or not allowed_sections[section] then
		-- logger.dbg("section %s is a scripted_loadout", section)
		return
	end
	local key_to_dik = ini_loadouts:collect_section(section)
	-- logger.dbg("section is %s", section)
	-- logger.print_table(key_to_dik, section)
	for key, value in pairs(key_to_dik) do
		local wpn_sec_name = str_explode(key, ":")[1]
		wpn_sec_name = ini_sys:r_string_ex(wpn_sec_name, "parent_section") or wpn_sec_name
		-- logger.dbg("wpn_sec_name is %s", wpn_sec_name)
		if ini_sys:section_exist(wpn_sec_name) and not dumped_weapons[wpn_sec_name] then
			local kind = ini_sys:r_string_ex(wpn_sec_name, "kind")
			if m_allowed_kinds[kind] then
				M.iterate_action(wpn_sec_name)
			end
		end
	end
end
M.iterate_action = M.spawn_weapon
function M.spawn_weapon(wpn_sec_name)
	give_object_to_actor(wpn_sec_name)
	dumped_weapons[wpn_sec_name] = true
end
function M.dump_vanilla_data(wpn_sec_name)
	dumped_weapons[wpn_sec_name] = {
		kind = ini_sys:r_string_ex(wpn_sec_name, "kind"),
		inv_weight = ini_sys:r_string_ex(wpn_sec_name, "inv_weight"),
		cam_dispersion = ini_sys:r_string_ex(wpn_sec_name, "cam_dispersion"),
		cam_dispersion_inc = ini_sys:r_string_ex(wpn_sec_name, "cam_dispersion_inc"),
		cam_step_angle_horz = ini_sys:r_string_ex(wpn_sec_name, "cam_step_angle_horz"),
		cam_relax_speed = ini_sys:r_string_ex(wpn_sec_name, "cam_relax_speed"),
		rpm = ini_sys:r_string_ex(wpn_sec_name, "rpm"),
	}
end
function M.dump_to_json()
	json = require("json")
	if not json then
		logger.err("Cannot find json.lua")
	end

	local f = io.open("dumped_weapons.json", "w")
	if not f then
		logger.err("Failed to open file")
		return
	end
	f:write(json.encode(dumped_weapons))
	f:close()
end

function M.write_zero_inertion(wpn_sec_name)
	iteration_result = iteration_result
		.. string.format("![%s]:hud_base\n", wpn_sec_name)
		.. "inertion_offset_LRUD = 0.0, 0.0, 0.0, 0.0\n"
		.. "inertion_offset_LRUD_aim = 0.0, 0.0, 0.0, 0.0\n"
		.. "inertion_min_angle = 89.0\n"
		.. "inertion_min_angle_aim = 89.0\n"
		.. "inertion_tendto_aim_speed = 0.0\n"
		.. "inertion_tendto_speed = 0.0\n"
		.. "inertion_tendto_ret_speed = 0.0\n"
		.. "inertion_tendto_ret_aim_speed = 0.0\n"
		.. "strafe_aim_enabled = false\n"
	dumped_weapons[wpn_sec_name] = true
end
function M.write_result_to_file()
	local f = io.open("fuzz_recoil_result.txt", "w")
	if not f then
		logger.err("Failed to open file")
		return
	end
	f:write(iteration_result)
	f:close()
end
