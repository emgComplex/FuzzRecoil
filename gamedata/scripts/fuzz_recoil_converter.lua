local utils = fuzz_recoil_utils

local M = {}
_G.fuzz_recoil_converter = M
local desync_hud_list = {
	w_shotgun = true,
	w_pistol = true,
}
local function is_bolt_action(op)
	if op.kind ~= "w_sniper" then
		return false
	end
	return op.rpm <= 60
end

M.rule = {
	["cam_recoil_power"] = { offset = 1, from = { min = 0, max = 4 }, to = { min = 1, max = 5 } },
	["cam_return_speed"] = { offset = 0, from = { min = 0, max = 10 }, to = { min = 0, max = 2 }, clamp = true },

	["force_pitch"] = { offset = 0, from = { min = 0, max = 4 }, to = { min = 3, max = 16 }, clamp = true },
	["force_y"] = { offset = 0, from = { min = 0, max = 4 }, to = { min = 0, max = -0.08 }, clamp = true },
	["force_z"] = { offset = 0, from = { min = 0, max = 4 }, to = { min = 0.003, max = 0.012 }, clamp = true },
	["force_yaw"] = { offset = 0, from = { min = 0, max = 2 }, to = { min = 0, max = 1 }, clamp = true },
	["force_x"] = { offset = 0, from = { min = 0, max = 2 }, to = { min = 0, max = 0.001 }, clamp = true },

	["pull_force"] = { offset = 1, from = { min = 0, max = 0.09 }, to = { min = 0.8, max = 0.3 }, clamp = true },

	["handling_speed"] = { offset = 0.3, from = { min = 0, max = 0.09 }, to = { min = 0.35, max = 0 }, clamp = true },
}

local source_fields = {
	cam_recoil_power = "cam_dispersion",
	cam_return_speed = "cam_relax_speed",
	force_pitch = "cam_dispersion",
	force_y = "cam_dispersion",
	force_z = "cam_dispersion",
	force_x = "cam_step_angle_horz",
}

local function apply_rule_single(k, val)
	local v = M.rule[k]
	if v then
		return utils.range_lerp(val, v.from, v.to, v.offset, v.clamp)
	end
	return val
end

local special_converter = {
	["pull_force"] = function(op)
		return apply_rule_single("pull_force", op.cam_dispersion_inc * (op.addon_cam_inc_k or 1))
	end,
	["handling_speed"] = function(op)
		return apply_rule_single("handling_speed", op.cam_dispersion_inc * (op.addon_cam_inc_k or 1))
	end,
	["force_yaw"] = function(op)
		local base_pitch = apply_rule_single("force_pitch", op.cam_dispersion)
		local base_yaw = apply_rule_single("force_yaw", op.cam_step_angle_horz)
		return base_pitch + base_yaw
	end,
	["firing_damping"] = function(op)
		return 1
	end,
	["is_bolt_action"] = function(op)
		return is_bolt_action(op)
	end,
	["desync_hud"] = function(op)
		return (desync_hud_list[op.kind] and true or false) or is_bolt_action(op)
	end,
	["cam_max_angle"] = function(op)
		--TODO: pistol rule here
		local kind = op.kind
		if kind == "w_shotgun" then
			return 0.17
		end
		return 0.9999
	end,
	["pitch_frac"] = function(op)
		return utils.math_clamp(op.cam_dispersion_frac or 1, 0, 1)
	end,
	["zoom_ratio"] = function(op)
		return op.cam_dispersion > 0 and utils.math_clamp(op.zoom_cam_dispersion / op.cam_dispersion, 0.25, 2) or 1
	end,
}

local function convert_single(param_name, op)
	if special_converter[param_name] then
		return special_converter[param_name](op)
	end

	local src_field = source_fields[param_name]
	if src_field and op[src_field] then
		return apply_rule_single(param_name, op[src_field])
	end

	return nil
end

---@param first any param or old_profile
---@param second any old_profile or new_profile
M.convert = function(first, second)
	if type(first) == "string" then
		return convert_single(first, second)
	elseif type(first) == "table" and type(second) == "table" then
		local op, np = first, second
		for param_name, _ in pairs(source_fields) do
			np[param_name] = convert_single(param_name, op)
		end
		for param_name, _ in pairs(special_converter) do
			np[param_name] = convert_single(param_name, op)
		end
		return np
	end
end

local shot_delay_list = {
	w_sniper = { rpm = 60, cam_impulse = 1, mul = 1 },
	w_shotgun = { rpm = 1000, cam_impulse = 0.7, mul = 0.25 },
	w_pistol = { rpm = 340, cam_impulse = 0.4, mul = 0.5 },
}
-- NOTE: or we can just check available firemodes?
function M.get_shot_delay(prf, wpn_info)
	local skind = shot_delay_list[wpn_info.kind]
	if skind and wpn_info.rpm <= skind.rpm then
		prf.shot_delay_enabled = true
		prf.shot_delay_time = utils.math_clamp(prf.fire_interval * skind.mul, 0.04, 0.5)
		prf.shot_cam_impulse_factor = skind.cam_impulse
	end
end
