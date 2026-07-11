local utils = fuzz_recoil_utils

local M = {}
_G.fuzz_recoil_converter = M

M.rule = {
	["cam_recoil_power"] = { offset = 1, from = { min = 0, max = 4 }, to = { min = 1, max = 5 } },
	["cam_return_speed"] = { offset = 0, from = { min = 0, max = 10 }, to = { min = 0, max = 2 }, clamp = true },

	["shot_pitch"] = { offset = 0, from = { min = 0, max = 4 }, to = { min = 3, max = 16 }, clamp = true },
	["shot_pos_y"] = { offset = 0, from = { min = 0, max = 4 }, to = { min = 0, max = -0.08 }, clamp = true },
	["shot_yaw"] = { offset = 0, from = { min = 0, max = 2 }, to = { min = 0, max = 1 }, clamp = true },
	["shot_pos_x"] = { offset = 0, from = { min = 0, max = 2 }, to = { min = 0, max = 0.001 }, clamp = true },

	["pull_force"] = { offset = 1, from = { min = 0, max = 0.09 }, to = { min = 0.8, max = 0.3 }, clamp = true },
	-- ["firing_damping"] = { offset = 0, from = { min = 0.1, max = 0.7 }, to = { min = 1, max = 1.5 } },

	["handling_speed"] = { offset = 0.3, from = { min = 0, max = 0.09 }, to = { min = 0.35, max = 0 }, clamp = true },
	-- ["increase_rate"] = { offset = 0, from = { min = 0.1, max = 0.7 }, to = { min = 1, max = 1.5 } },
}

local function apply_rules(np, rule)
	for k, v in pairs(rule) do
		np[k] = utils.range_lerp(np[k], v.from, v.to, v.offset, v.clamp)
	end
end
local function is_bolt_action(op)
	if op.kind ~= "w_sniper" then
		return false
	end
	--NOTE: rpm now comes from cast_wpn:RealRPM() (60/fOneShotTime)
	--thx to @Gabriell
	return op.rpm <= 60
	--NOTE: no lua api exposes hud motion length,animation check not feasible
	-- credite @verdatim
end

M.convert = function(op, np)
	np.cam_recoil_power = op.cam_dispersion
	np.cam_return_speed = op.cam_relax_speed

	np.shot_pitch = op.cam_dispersion
	np.shot_pos_y = op.cam_dispersion
	np.shot_yaw = op.cam_step_angle_horz
	np.shot_pos_x = op.cam_step_angle_horz

	np.pull_force = op.cam_dispersion_inc
	np.handling_speed = op.cam_dispersion_inc
	apply_rules(np, M.rule)
	np.firing_damping = 1
	np.is_bolt_action = is_bolt_action(op)

	np.shot_yaw = np.shot_pitch + np.shot_yaw

	--TODO: Kind bonus
	--TODO: mass bonus
end
