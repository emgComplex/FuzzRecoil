-- overwrite vector operators
local M = {}
_G.fuzz_recoil_utils = M
local logger = fuzz_recoil_logger
local frm = fuzz_recoil

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

M.simple_ease = {}
M.simple_ease.__index = M.simple_ease
function M.simple_ease:new(base_speed, speed_mul, offset, intensity, mode)
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

function M.math_clamp(val, min, max)
	return math.max(min, math.min(max, val))
end
function M.range_lerp(val, from, to, offset, clamp)
	if not offset then
		offset = 0
	end
	if clamp then
		val = M.math_clamp(val, from.min, from.max)
	end
	-- logger.dbg(
	-- 	string.format(
	-- 		"val:%.2f,from_min:%.2f,from_max:%.2f,to_min:%.2f,to_max:%.2f,offset:%.2f",
	-- 		val,
	-- 		from.min,
	-- 		from.max,
	-- 		to.min,
	-- 		to.max,
	-- 		offset
	-- 	)
	-- )
	local range = from.max - from.min
	if range == 0 then
		return to.min + offset
	end
	return (val - from.min) / range * (to.max - to.min) + to.min + offset
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

--NOTE: recusive needed?
function M.get_base_weapon(wpn_sec)
	local parent_section = ini_sys:r_string_ex(wpn_sec, "parent_section")
	if parent_section and wpn_sec ~= parent_section then
		return M.get_base_weapon(parent_section)
	else
		return wpn_sec
	end
end

--===========================
--Dump weapons
--===========================
--Credit:@verdatim
local dumped_weapons = {}
local ini_loadouts = ini_file_ex("items\\settings\\npc_loadouts\\npc_loadouts.ltx")
local allowed_kinds = {
	w_pistol = true,
	w_rifle = true,
	w_shotgun = true,
	w_sniper = true,
	w_smg = true,
}
local disallowed_sections = {}
local allowed_sections = {}
function M.get_all_weapon_sections()
	json = require("json")
	if not json then
		logger.err("Cannot find json.lua")
	end
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

	local f = io.open("dumped_weapons.json", "w")
	if not f then
		logger.err("Failed to open file")
	end
	f:write(json.encode(dumped_weapons))
	f:close()
	dumped_weapons = {}
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
	logger.dbg("iterator called")

	--checks if loadout is a 'scripted' loadout, i.e. probably not 'valid'
	if disallowed_sections[section] or not allowed_sections[section] then
		logger.dbg("section %s is a scripted_loadout", section)
		return
	end
	local key_to_dik = ini_loadouts:collect_section(section)
	logger.dbg("section is %s", section)
	print_r(key_to_dik)
	for key, value in pairs(key_to_dik) do
		local wpn_sec_name = str_explode(key, ":")[1]
		wpn_sec_name = ini_sys:r_string_ex(wpn_sec_name, "parent_section") or wpn_sec_name
		logger.dbg("wpn_sec_name is %s", wpn_sec_name)
		if ini_sys:section_exist(wpn_sec_name) and not dumped_weapons[wpn_sec_name] then
			local kind = ini_sys:r_string_ex(wpn_sec_name, "kind")
			if allowed_kinds[kind] then
				dumped_weapons[wpn_sec_name] = {
					kind = ini_sys:r_string_ex(wpn_sec_name, "kind"),
					inv_weight = ini_sys:r_string_ex(wpn_sec_name, "inv_weight"),
					cam_dispersion = ini_sys:r_string_ex(wpn_sec_name, "cam_dispersion"),
					cam_dispersion_inc = ini_sys:r_string_ex(wpn_sec_name, "cam_dispersion_inc"),
					cam_step_angle_horz = ini_sys:r_string_ex(wpn_sec_name, "cam_step_angle_horz"),
					cam_relax_speed = ini_sys:r_string_ex(wpn_sec_name, "cam_relax_speed"),
					rpm = ini_sys:r_string_ex(wpn_sec_name, "rpm"),
				}
				--give_object_to_actor(wpn_sec_name)
			end
		end
	end
end

--NOTE: this could slow down the whole game,i'll have to do the refator
--i just left a code here to remind me this is a bad idea
-- function fuzz_utils.init_vector_extensions()
-- 	local temp_vec = vector()
-- 	local mt = getmetatable(temp_vec)
-- 	if mt then
-- 		local ori_add = mt.__add
-- 		local ori_sub = mt.__sub
-- 		local ori_div = mt.__div
-- 		local ori_unm = mt.__unm
-- 		local ori_mul = mt.__mul
--
-- 		local function is_vector(v)
-- 			return type(v) == "userdata" and v.x ~= nil
-- 		end
--
-- 		mt.__add = function(a, b)
-- 			if is_vector(a) and is_vector(b) then
-- 				return vector():set(a.x + b.x, a.y + b.y, a.z + b.z)
-- 			elseif ori_add then
-- 				return ori_add(a, b)
-- 			else
-- 				error(string.format("Unsupported operator(+) for %s and %s", tostring(a), tostring(b)))
-- 			end
-- 		end
--
-- 		mt.__sub = function(a, b)
-- 			if is_vector(a) and is_vector(b) then
-- 				return vector():set(a.x - b.x, a.y - b.y, a.z - b.z)
-- 			elseif ori_sub then
-- 				return ori_sub(a, b)
-- 			else
-- 				error(string.format("Unsupported operator(-) for %s and %s", tostring(a), tostring(b)))
-- 			end
-- 		end
--
-- 		mt.__mul = function(a, b)
-- 			if type(a) == "number" and is_vector(b) then
-- 				return vector():set(b.x * a, b.y * a, b.z * a)
-- 			elseif is_vector(a) and type(b) == "number" then
-- 				return vector():set(a.x * b, a.y * b, a.z * b)
-- 			elseif is_vector(a) and is_vector(b) then
-- 				return vector():set(a.x * b.x, a.y * b.y, a.z * b.z)
-- 			elseif ori_mul then
-- 				return ori_mul(a, b)
-- 			else
-- 				error(string.format("Unsupported operator(*) for %s and %s", tostring(a), tostring(b)))
-- 			end
-- 		end
--
-- 		mt.__div = function(a, b)
-- 			if is_vector(a) and type(b) == "number" then
-- 				if b == 0 then
-- 					error("divided by 0!")
-- 				end
-- 				return vector():set(a.x / b, a.y / b, a.z / b)
-- 			elseif ori_div then
-- 				return ori_div(a, b)
-- 			else
-- 				error(string.format("Unsupported operator(/) for %s and %s", tostring(a), tostring(b)))
-- 			end
-- 		end
--
-- 		mt.__unm = function(a)
-- 			if is_vector(a) then
-- 				return vector():set(-a.x, -a.y, -a.z)
-- 			elseif ori_unm then
-- 				return ori_unm(a)
-- 			else
-- 				error("Unsupported type to negate: " .. tostring(a))
-- 			end
-- 		end
-- 	else
-- 		error("Can't find vector metatable")
-- 	end
-- end
